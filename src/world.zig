//! world — fields, operators, fronts, and the update cycle (spec §9, §15;
//! brief P1.3–P1.6).
//!
//! One step, on fed time (R6): gather the active set → run the operators
//! over it, region-local, in parallel when a host lends its JobSystem →
//! barrier → the front pass, serial, in id order → commit: apply deltas in
//! key order, materialise the frontier, reconcile the seams, rebuild
//! summaries up the dirty paths, bump versions → publish the new snapshot
//! by one atomic swap. Nothing in the step reads a clock; nothing the
//! parallel phase does can reach the result in a different order.
//!
//! ── The seam contract (R2) ───────────────────────────────────────────────
//!
//! Every brick is self-contained for reconstruction inside its closed
//! cube, so two bricks that share a face both store the face. The
//! contract that makes them agree, enforced at commit over every brick
//! the commit touched and every brick sharing a point with one:
//!
//!   1. ANCHOR. A shared lattice point takes the value of the FINEST brick
//!      holding it (ties: lowest key). Every other holder copies.
//!   2. HANG. A sample of a finer brick that lies on a face shared with a
//!      coarser brick but not on the coarser lattice takes the coarser
//!      brick's interpolant there — the hanging-node rule. The coarse
//!      face governs the face; the fine brick loses face detail and gains
//!      C⁰ continuity across the seam.
//!
//!   3. HALO (R7). A brick's block carries one layer beyond each face,
//!      copied from whoever holds that point by the same rule taken one
//!      layer deeper — the finest holder's sample, or the coarse
//!      interpolant where the point is off the coarse lattice. Two
//!      same-gauge neighbours then reconstruct the shared face from the
//!      same 64 coefficients: C2 across the seam, which G9 measures.
//!
//! `guards.zig` checks all three by reconstructing every shared face and
//! recomputing every halo from the snapshot. This is the whole point of
//! P1.2 and the gate that pays for it straddles two gauges.
//!
//! ── Activity ─────────────────────────────────────────────────────────────
//!
//! A brick is in the next step's active set iff it holds a live,
//! non-dormant front, or a change above the epsilon floor landed in it
//! this commit — an operator's delta, a seam copy, or materialisation.
//! Diffusion therefore carries activity outward with the front of change
//! and drops it where the field has settled; Activity the channel is what
//! fronts deposit so a Decay operator keeps recent tissue's bricks warm
//! for a while, and the same rule turns them off. Dormant tissue is a
//! brick nobody writes, and it costs nothing (G5).

const std = @import("std");
const common = @import("common");
const jobs = common.jobs;
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const summary = @import("summary.zig");
const tree = @import("tree.zig");
const front = @import("front.zig");
const update = @import("update.zig");
const operators = @import("operators.zig");
const rng = @import("rng.zig");
const fmath = @import("fmath.zig");
const thresholds = @import("thresholds.zig");

const Key = lattice.Key;
const Brick = brick.Brick;
const Plane = brick.Plane;
const Snapshot = tree.Snapshot;
const Front = front.Front;
const Channel = channel.Channel;

pub const Error = error{ OutOfMemory, GaugeConflict, TimeRegression, TooManyReaders, UnknownChannel, StepInProgress, NoStep };

/// Fed time. `frame` and `time_ns` both monotone; a regression is refused.
pub const Now = struct { frame: u64, time_ns: u64 };

pub const Policy = struct {
    /// Iterate the active set only. False is the G5 mutation, kept as an
    /// instrument (`loam-run --all-regions`) so what dormancy buys is a
    /// number anyone can print.
    active_only: bool = true,
    /// Gauge of bricks materialised by fronts and the frontier rule.
    default_gauge: u5 = 0,
    /// Active bricks per job in the parallel phase.
    chunk: u32 = 8,
    /// The halo pass. False is G9's mutation: the halos stay at the absent
    /// value and the two holders of a face reconstruct from different
    /// coefficients — C0 at best. Never false outside a gate.
    halo: bool = true,
    /// Bricks a step may evaluate (R15, R16, R17). Null is no limit. With
    /// one set the head of the active set IS the step — its bricks'
    /// operators run and its fronts move. First the bricks hosting a live
    /// front, in key order, NEVER cut (Christian, struck: "a skipped
    /// front step is the front's clock silently halved, and clocks in
    /// Loam are meant to be explicit channels, never a side effect of the
    /// budget"): what the fronts alone exceed the budget by is an OVERRUN
    /// the step reports (`StepStats.overrun`), not a skip. Then the rest
    /// by THE RESIDUAL's score, pending × (1 + lag/τ) — pending the
    /// brick's attention accumulated by max since it was last evaluated,
    /// lag = now − the fed time it has been owed since
    /// (`Snapshot.active_since`) — descending, ties by key: deferral
    /// costs, so a hot region is served often and every brick with real
    /// pending change is served within a bounded delay (G14 e). The tail
    /// carries forward with its since intact, except that a brick whose
    /// READER attention has decayed under the change floor AND hosts no
    /// front FADES out (the fade rule, struck: a seam write of 1e-5
    /// cannot grow into something that mattered; a front can). What is
    /// NOT guaranteed is that the world keeps up: more load than budget
    /// raises lag everywhere, visibly, on the transcript.
    budget: ?u32 = null,
    /// The seam and halo apply passes chunked per target brick, so a
    /// `work` call stops between bricks. False is G15 (b)'s mutation: a
    /// pass applied whole, and a call exceeds its units.
    chunk_applies: bool = true,
    /// Fronts made deferrable: a `cut` during the front pass stops it,
    /// and the fronts it did not reach do not move this step. G15 (c)
    /// and (d)'s mutation — a skipped front step is the front's clock
    /// silently halved, which is what the fronts-first rule forbids.
    cut_fronts: bool = false,
    /// How the head is chosen under a budget. `.key` is G14 (c)'s
    /// mutation; `.queue` the tier ruling's — one obligation queue,
    /// fronts and backlog together in key order, cut at the budget;
    /// `.no_lag` the residual's (G14 e) — the score without its lag
    /// term, under which a cold region starves. All kept as instruments
    /// (`loam-run --budget-order key|queue|no_lag`).
    budget_order: BudgetOrder = .attention,
    /// What a capsule unions HARD into (P2.2, G12 a). `.recent`, struck:
    /// its own front's deposit within the collar's reach behind its start
    /// ring (`thresholds.collarReach`, through `chart_s`); smooth with
    /// `Params.collar` × the envelope into everything else, its own
    /// older tube included. The two mutations, kept as instruments
    /// (`loam-run --collar-gate`): `.none` — nothing is its own, the
    /// front beads into its own chain at k/4 a joint; `.own` — its own at
    /// any age, the coil's self-touch a hard crease.
    collar_gate: CollarGate = .recent,
};

pub const BudgetOrder = enum { attention, key, queue, no_lag };
pub const CollarGate = enum { recent, none, own };

pub const StepStats = struct {
    active_in: u64 = 0,
    region_evals: u64 = 0,
    front_steps: u64 = 0,
    fronts_dormant: u64 = 0,
    /// Under a budget: active bricks carried forward unevaluated, those
    /// that left the active set instead with their attention under the
    /// floor, and live fronts that did not move because their brick was
    /// carried.
    carried: u64 = 0,
    faded: u64 = 0,
    fronts_skipped: u64 = 0,
    /// Bricks the fronts' tier exceeded the budget by: non-deferrable
    /// work done beyond the budget, reported, never skipped.
    overrun: u64 = 0,
    /// Active bricks owed from before the last commit — carried at least
    /// once (`Snapshot.backlog`): a standing number. Backlog above the
    /// budget for consecutive steps (`World.overload_steps`) is the
    /// signal that the honest response is slowing the world's clock —
    /// D5's job, named.
    backlog: u64 = 0,
    bricks_changed: u64 = 0,
    bricks_materialised: u64 = 0,
    seam_bricks: u64 = 0,
    seam_writes: u64 = 0,
    halo_writes: u64 = 0,
    spawns: u64 = 0,
    deaths: u64 = 0,
    /// Front steps taken with an envelope under the gauge's FAITHFUL floor
    /// (G13: r/h < 2) — the demand for refinement, counted, not met.
    below_faithful: u64 = 0,
    diffusion_clamped: u64 = 0,
    /// Samples the collar acted on this step — a smooth union with k > 0
    /// that landed under the hard one — and samples whose provenance a
    /// front's op won (P2.2). Standing numbers: along a chain the first
    /// is zero by construction.
    collar_samples: u64 = 0,
    provenance_writes: u64 = 0,
    active_out: u64 = 0,
    /// R16: the step's work in units, the units of the last `work` call,
    /// the calls it took, and the units `finish` had to perform beyond
    /// the calls — the step's work past the host's budget, reported.
    units: u64 = 0,
    units_last_call: u64 = 0,
    calls: u64 = 0,
    units_finish: u64 = 0,
    /// Units by phase (`Phase` order): with the phase's nanoseconds, the
    /// cost of a unit of each shape — the step-cost beat's instrument.
    units_phase: [15]u64 = [_]u64{0} ** 15,
    // Wall-clock nanoseconds per phase: instrumentation only, printed
    // beside the counts, never read by the sim.
    ns_operate: u64 = 0,
    ns_fronts: u64 = 0,
    ns_apply: u64 = 0,
    ns_frontier: u64 = 0,
    ns_seams: u64 = 0,
    ns_finalize: u64 = 0,
    /// Of finalize: the Merkle hash alone (Blake3 over every plane).
    ns_hash: u64 = 0,
    ns_build: u64 = 0,
    ns_publish: u64 = 0,

    fn accumulate(self: *StepStats, o: StepStats) void {
        inline for (std.meta.fields(StepStats)) |f| {
            switch (@typeInfo(f.type)) {
                .array => for (&@field(self, f.name), @field(o, f.name)) |*a, b| {
                    a.* += b;
                },
                else => @field(self, f.name) += @field(o, f.name),
            }
        }
    }
};

pub const MAX_READERS = 64;

/// A reader's hazard slot (G8). `acquire` publishes the pointer it is
/// about to retain here; the writer defers freeing any snapshot a slot
/// names. Two loads, one store, one retain — no lock.
pub const ReaderSlot = struct {
    hazard: std.atomic.Value(?*Snapshot) = std.atomic.Value(?*Snapshot).init(null),
    used: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

pub const InitOptions = struct {
    seed: u64 = 0,
    domain: lattice.Domain = .{},
    policy: Policy = .{},
};

pub const World = struct {
    gpa: std.mem.Allocator,
    domain: lattice.Domain,
    seed: u64,
    registry: channel.Registry,
    policy: Policy,
    /// The working base and the world's own reference to it.
    head: *Snapshot,
    /// What readers acquire; holds its own reference.
    published_ptr: std.atomic.Value(*Snapshot),
    readers: [MAX_READERS]ReaderSlot = [_]ReaderSlot{.{}} ** MAX_READERS,
    retired: std.ArrayListUnmanaged(*Snapshot) = .{},
    operators: std.ArrayListUnmanaged(operators.Operator) = .{},
    fronts: std.ArrayListUnmanaged(Front) = .{},
    buffer: update.Buffer,
    started: bool = false,
    frame: u64 = 0,
    time_ns: u64 = 0,
    epoch: u64 = 0,
    vid: u64 = 0,
    stats: StepStats = .{},
    total: StepStats = .{},
    /// The healing operator's front template; a scene sets it.
    heal_params: front.Params = .{},
    /// A host's JobSystem, used by every parallel phase — operate, apply,
    /// finalize, blob authoring — when set. `step` may pass one per call
    /// instead. Requires a thread-safe allocator (GPA, c_allocator and
    /// the testing allocator all are). Null runs everything serial, and
    /// G1 says the two agree to the byte.
    jobs: ?*jobs.JobSystem = null,
    /// Fronts queued by authoring or the front pass; ids assigned at commit.
    pending_spawns: std.ArrayListUnmanaged(update.Spawn) = .{},
    /// The bricks the last step evaluated, in the order it took them —
    /// attention order under a budget, Morton otherwise. Owned. G14 (a)
    /// recomputes this from the snapshot's summaries alone and compares.
    evaluated: []Key = &.{},
    /// The step in progress between `begin` and `finish` (R16).
    step_state: ?StepState = null,
    /// The ring history — the loft table (R12, P2.2): per front id, every
    /// ring it has swept, ring zero the seed, appended by the commit in id
    /// order. Optional history (R12a): nothing on the sim path reads it;
    /// a band-1 query does, through a sample's provenance, and G12 (b)
    /// rebuilds capsules from it. Not in the content hash — it is the
    /// fronts' past, which the hashes of the steps that made it hold.
    rings: std.ArrayListUnmanaged(std.ArrayListUnmanaged(front.Ring)) = .{},
    /// The last step's fed delta, seconds: the ring pitch is speed × this,
    /// band 2's scale for a reader (P2.3).
    dt_s: f64 = 1,
    /// Consecutive steps whose backlog exceeded the budget: under a
    /// sustained cut the backlog grows, obligations fill the head, tier
    /// two gets nothing, and the world degrades to key-order round-robin
    /// without anybody deciding it should. Counted so it is recognised.
    overload_steps: u64 = 0,

    pub fn init(gpa: std.mem.Allocator, opts: InitOptions) !World {
        const head = try tree.emptySnapshot(gpa, opts.seed);
        head.retain(); // the published slot's reference
        return .{
            .gpa = gpa,
            .domain = opts.domain,
            .seed = opts.seed,
            .registry = channel.Registry.init(),
            .policy = opts.policy,
            .head = head,
            .published_ptr = std.atomic.Value(*Snapshot).init(head),
            .buffer = update.Buffer.init(gpa),
        };
    }

    pub fn deinit(self: *World) void {
        for (self.retired.items) |s| s.release();
        self.retired.deinit(self.gpa);
        self.published_ptr.load(.acquire).release();
        self.head.release();
        self.operators.deinit(self.gpa);
        self.fronts.deinit(self.gpa);
        for (self.rings.items) |*r| r.deinit(self.gpa);
        self.rings.deinit(self.gpa);
        self.pending_spawns.deinit(self.gpa);
        self.gpa.free(self.evaluated);
        self.abortStep();
        self.buffer.deinit();
    }

    // ── Reading ──────────────────────────────────────────────────────────

    /// The latest snapshot, borrowed: valid until the next step or apply.
    pub fn published(self: *const World) *const Snapshot {
        return self.head;
    }

    pub fn registerReader(self: *World) Error!*ReaderSlot {
        for (&self.readers) |*r| {
            if (r.used.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) return r;
        }
        return Error.TooManyReaders;
    }

    pub fn unregisterReader(_: *World, slot: *ReaderSlot) void {
        slot.hazard.store(null, .release);
        slot.used.store(false, .release);
    }

    /// Retain the current published snapshot from any thread. Lock-free:
    /// the hazard slot keeps the writer from freeing what we are about
    /// to retain. Release it with `Snapshot.release`.
    pub fn acquire(self: *World, slot: *ReaderSlot) *Snapshot {
        while (true) {
            const p = self.published_ptr.load(.seq_cst);
            slot.hazard.store(p, .seq_cst);
            if (self.published_ptr.load(.seq_cst) == p) {
                p.retain();
                slot.hazard.store(null, .seq_cst);
                return p;
            }
        }
    }

    fn hazarded(self: *World, s: *Snapshot) bool {
        for (&self.readers) |*r| {
            if (r.hazard.load(.seq_cst) == s) return true;
        }
        return false;
    }

    fn publish(self: *World, new: *Snapshot) !void {
        new.retain(); // the published slot's reference
        const old = self.published_ptr.swap(new, .seq_cst);
        // Drop the published reference of `old`, or defer it while a
        // reader is between naming it and retaining it.
        if (self.hazarded(old)) try self.retired.append(self.gpa, old) else old.release();
        var i: usize = 0;
        while (i < self.retired.items.len) {
            const r = self.retired.items[i];
            if (self.hazarded(r)) {
                i += 1;
            } else {
                r.release();
                _ = self.retired.swapRemove(i);
            }
        }
        self.head.release();
        self.head = new;
        self.vid = new.vid;
    }

    // ── Mounting ─────────────────────────────────────────────────────────

    pub fn addOperator(self: *World, op: operators.Operator) !void {
        try self.operators.append(self.gpa, op);
    }

    pub fn channelBit(self: *const World, name: []const u8) Error!u6 {
        return self.registry.find(name) orelse Error.UnknownChannel;
    }

    /// Queue a front for the next commit. Ids are assigned at commit in
    /// queue order, so two worlds fed the same calls agree on them.
    pub fn spawnFront(self: *World, s: update.Spawn) !void {
        try self.pending_spawns.append(self.gpa, s);
    }

    /// The entry for `key` in the pending authoring buffer — the seedbed's
    /// door. Applied by `apply`.
    pub fn author(self: *World, key: Key) !*update.RegionUpdate {
        return self.buffer.region(key);
    }

    /// Commit whatever authoring has queued, as a step with no operators
    /// and no time. Publishes a new vid.
    pub fn apply(self: *World) Error!void {
        try self.beginAuthoring();
        _ = try self.work(std.math.maxInt(u64));
        try self.finish();
    }

    // ── The step (R16): begin / work / cut / finish ──────────────────────
    //
    // A step's state lives on the world between calls — the update
    // buffer, the changed set, the phase and its cursors. `work(units)`
    // performs up to that many units in phase order and never more;
    // `cut` stops the operate phase where it is; `finish` completes what
    // remains — counted apart, the step's work beyond the host's calls —
    // and publishes. `step` is the three in one, and publishes what the
    // one-piece step published: the phases keep their order and their
    // sorted applies, and the sinks are merged after the operators so
    // every floating-point sum lands as it did.

    pub const Phase = enum(u8) { fronts, operate, merge, apply, frontier, scratch, seam1_collect, seam1_apply, seam2_collect, seam2_apply, halo_collect, halo_apply, finalize, build, ready };

    const StepState = struct {
        now: Now,
        dt: f64,
        evaluated: bool,
        authoring: bool,
        sys: ?*jobs.JobSystem,
        base: *Snapshot,
        budget: ?u32,
        quiet: bool = false,
        phase: Phase = .fronts,
        units: u64 = 0,
        calls: u32 = 0,
        /// Units performed by the call in progress — counted, not
        /// inferred from the budget, so a phase that overshoots is seen.
        performed: u64 = 0,
        /// Units the running phase performed in this `runPhase` call.
        phase_units: u64 = 0,
        timer: std.time.Timer,
        // begin
        all_keys: []Key = &.{},
        head: []Key = &.{},
        head_sorted: []Key = &.{},
        /// The head as begun, sorted: what the front pass asks, uncut.
        front_head: []Key = &.{},
        carried: std.ArrayListUnmanaged(Key) = .{},
        fronts: []Key = &.{},
        updates: []*update.RegionUpdate = &.{},
        // fronts
        sinks: []Sink = &.{},
        front_cursor: usize = 0,
        front_end: usize = 0,
        // operate
        op_cursor: usize = 0,
        op_end: usize = 0,
        cut_at: ?u32 = null,
        // apply
        apply_started: bool = false,
        entries: []*update.RegionUpdate = &.{},
        results: []?Changed = &.{},
        results_live: bool = false,
        apply_cursor: usize = 0,
        spawn_requests: std.ArrayListUnmanaged(update.Spawn) = .{},
        changed: ChangedMap = .{},
        order: std.ArrayListUnmanaged(u64) = .{},
        bricks_owned: bool = false,
        // frontier
        overrides: std.ArrayListUnmanaged(tree.Override) = .{},
        pre_root: ?*tree.Node = null,
        frontier_stage: u8 = 0,
        frontier_cursor: usize = 0,
        requests: std.ArrayListUnmanaged(Key) = .{},
        // seams and halos
        scratch_root: ?*tree.Node = null,
        n0: usize = 0,
        /// One neighbourhood per brick of the seam pass's `order[0..n0]`,
        /// built by the first collect that reaches it and kept through the
        /// second and the halo's (the step-cost beat: the build was 60% of
        /// the seam phase, three times per brick).
        nbs: []?Neighbourhood = &.{},
        lists: []WriteList = &.{},
        all: WriteList = .{},
        collect_cursor: usize = 0,
        group_cursor: usize = 0,
        seam_writes_before: u64 = 0,
        // finalize, build
        finalize_cursor: usize = 0,
        dirty: std.ArrayListUnmanaged(Key) = .{},
        active_out: std.ArrayListUnmanaged(Key) = .{},
        root: ?*tree.Node = null,
    };

    fn deinitState(self: *World, st: *StepState) void {
        const gpa = self.gpa;
        if (st.all_keys.len > 0) gpa.free(st.all_keys);
        if (st.head.len > 0) gpa.free(st.head);
        if (st.head_sorted.len > 0) gpa.free(st.head_sorted);
        if (st.front_head.len > 0) gpa.free(st.front_head);
        st.carried.deinit(gpa);
        if (st.fronts.len > 0) gpa.free(st.fronts);
        if (st.updates.len > 0) gpa.free(st.updates);
        if (st.sinks.len > 0) gpa.free(st.sinks); // their contents are the buffer's arena's
        if (st.entries.len > 0) gpa.free(st.entries);
        if (st.results_live) {
            for (st.results) |r| if (r) |c| c.b.release(gpa);
        }
        if (st.results.len > 0) gpa.free(st.results);
        st.spawn_requests.deinit(gpa);
        if (st.bricks_owned) {
            for (st.order.items) |raw| st.changed.get(raw).?.b.release(gpa);
        }
        st.changed.deinit(gpa);
        st.order.deinit(gpa);
        st.overrides.deinit(gpa);
        if (st.pre_root) |r| r.release(gpa);
        st.requests.deinit(gpa);
        if (st.scratch_root) |r| r.release(gpa);
        for (st.lists) |*l| l.deinit(gpa);
        if (st.lists.len > 0) gpa.free(st.lists);
        for (st.nbs) |*slot| if (slot.*) |*nb| nb.deinit(gpa);
        if (st.nbs.len > 0) gpa.free(st.nbs);
        st.all.deinit(gpa);
        st.dirty.deinit(gpa);
        st.active_out.deinit(gpa);
        if (st.root) |r| r.release(gpa);
        st.base.release();
    }

    /// Drop a step in progress, publishing nothing.
    pub fn abortStep(self: *World) void {
        if (self.step_state) |*st| {
            self.deinitState(st);
            self.step_state = null;
        }
    }

    /// Begin a step on fed time (R6, R16). Refuses a regression and a
    /// step already in progress. After it: the active set and its head
    /// are chosen, the region entries exist, and `work` may be called.
    pub fn begin(self: *World, now: Now, js: ?*jobs.JobSystem) Error!void {
        if (self.step_state != null) return Error.StepInProgress;
        if (self.started) {
            if (now.time_ns < self.time_ns or now.frame < self.frame) return Error.TimeRegression;
        } else {
            self.started = true;
            self.time_ns = now.time_ns;
            self.frame = now.frame;
        }
        const dt_ns = now.time_ns - self.time_ns;
        const dt: f64 = @as(f64, @floatFromInt(dt_ns)) / 1e9;
        if (dt > 0) self.dt_s = dt;
        self.time_ns = now.time_ns;
        self.frame = now.frame;
        self.epoch += 1;
        self.stats = .{};

        const base = self.head;
        const gpa = self.gpa;
        base.retain();
        var st = StepState{
            .now = now,
            .dt = dt,
            // Time passed: the head was looked at, whether or not any
            // operator is mounted to look — a world with none has every
            // brick settled, and must not carry its active set forward
            // forever (the G4 mutation, healing unmounted, could never end
            // its season once the sapling stopped mounting Decay).
            .evaluated = dt > 0,
            .authoring = false,
            .sys = js orelse self.jobs,
            .base = base,
            .budget = self.policy.budget,
            .timer = std.time.Timer.start() catch unreachable,
        };
        errdefer self.deinitState(&st);

        // A QUIET step: nothing active, no front that could move, nothing
        // queued. No operator would run and no front would deposit, so
        // the commit would publish the same tree under a new vid — and a
        // host reading the vid would re-pack it. Stop at source: the
        // clock advances, the snapshot stands. (A dormant front wakes only
        // when its brick is active, which it is not.)
        if (self.isQuiet(base)) {
            st.quiet = true;
            st.phase = .ready;
            self.step_state = st;
            return;
        }
        self.buffer.reset();

        // 1. The active set — every brick, under the mutation.
        const active: []const Key = if (self.policy.active_only) base.active else blk: {
            const bs = try base.bricks(gpa);
            defer gpa.free(bs);
            st.all_keys = try gpa.alloc(Key, bs.len);
            for (bs, 0..) |b, i| st.all_keys[i] = b.key;
            break :blk st.all_keys;
        };
        self.stats.active_in = active.len;

        // 2. The head (R15, R17): the fronts' bricks, then the residual's
        // score, cut at the budget; the tail carried.
        const chosen = try self.chooseHead(base, active, now);
        st.head = chosen.head;
        st.fronts = chosen.fronts;
        if (chosen.carried.len > 0) {
            try st.carried.appendSlice(gpa, chosen.carried);
            gpa.free(chosen.carried);
        }
        self.stats.carried = st.carried.items.len;
        st.head_sorted = try gpa.dupe(Key, st.head);
        std.mem.sort(Key, st.head_sorted, {}, Key.lessThan);
        st.front_head = try gpa.dupe(Key, st.head_sorted);
        st.op_end = st.head.len;

        // 3. Entries, serially, one per evaluated brick; the fronts' sinks.
        st.updates = try gpa.alloc(*update.RegionUpdate, st.head.len);
        for (st.head, 0..) |k, i| st.updates[i] = try self.buffer.region(k);
        st.sinks = try gpa.alloc(Sink, self.fronts.items.len);
        st.front_end = st.sinks.len;
        const alloc = self.buffer.planeAllocator();
        for (st.sinks, 0..) |*sk, i| sk.* = .{ .alloc = alloc, .id = @intCast(i) };
        self.step_state = st;
    }

    /// Begin an authoring commit: what the buffer holds, applied as a
    /// step with no operators and no time; the active set carries.
    fn beginAuthoring(self: *World) Error!void {
        if (self.step_state != null) return Error.StepInProgress;
        const base = self.head;
        base.retain();
        self.step_state = StepState{
            .now = .{ .frame = self.frame, .time_ns = self.time_ns },
            .dt = 0,
            .evaluated = false,
            .authoring = true,
            .sys = self.jobs,
            .base = base,
            .budget = null,
            .phase = .apply,
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    /// Whether a step is between `begin` and `finish`.
    pub fn inProgress(self: *const World) bool {
        return self.step_state != null;
    }

    /// The head and the fronts this step will evaluate — for a host that
    /// budgets by them.
    pub const Plan = struct { fronts: usize, head: usize };
    pub fn plan(self: *const World) ?Plan {
        const st = if (self.step_state) |*s| s else return null;
        return .{ .fronts = self.fronts.items.len, .head = st.head.len };
    }

    /// Perform up to `units` units of the step in progress, in phase
    /// order, never more. True when only `finish` remains.
    pub fn work(self: *World, units: u64) Error!bool {
        const st: *StepState = if (self.step_state) |*s| s else return Error.NoStep;
        st.calls += 1;
        self.stats.calls += 1;
        if (st.quiet or st.phase == .ready) return true;
        errdefer self.abortStep();
        var remaining = units;
        st.performed = 0;
        while (remaining > 0 and st.phase != .ready) {
            if (try self.runPhase(st, &remaining)) st.phase = @enumFromInt(@intFromEnum(st.phase) + 1);
        }
        const spent = st.performed;
        st.units += spent;
        self.stats.units += spent;
        self.stats.units_last_call = spent;
        return st.phase == .ready;
    }

    /// Stop the operate phase where it is: what the head has not reached
    /// carries forward with its since intact (a cut brick rides the
    /// residual with lag ≥ one step by construction). No effect once the
    /// operators have run; the fronts are never cut.
    pub fn cut(self: *World) Error!void {
        const st: *StepState = if (self.step_state) |*s| s else return Error.NoStep;
        if (st.quiet or st.authoring or st.cut_at != null) return;
        if (@intFromEnum(st.phase) > @intFromEnum(Phase.operate)) return;
        const gpa = self.gpa;
        // The mutation: fronts made deferrable — the ones the cut reaches
        // before do not move this step (G15 c and d).
        if (self.policy.cut_fronts and st.phase == .fronts) {
            self.stats.fronts_skipped += st.front_end - st.front_cursor;
            st.front_end = st.front_cursor;
        }
        const at = st.op_cursor;
        st.cut_at = @intCast(at);
        st.op_end = at;
        try st.carried.appendSlice(gpa, st.head[at..]);
        self.stats.carried = st.carried.items.len;
        if (at < st.head.len) {
            st.head = if (at == 0) blk: {
                gpa.free(st.head);
                break :blk &.{};
            } else try gpa.realloc(st.head, at);
            gpa.free(st.head_sorted);
            st.head_sorted = try gpa.dupe(Key, st.head);
            std.mem.sort(Key, st.head_sorted, {}, Key.lessThan);
        }
    }

    /// Complete the step — whatever `work` left, counted apart as
    /// `units_finish` — and publish.
    pub fn finish(self: *World) Error!void {
        const st: *StepState = if (self.step_state) |*s| s else return Error.NoStep;
        errdefer self.abortStep();
        if (!st.quiet and st.phase != .ready) {
            var remaining: u64 = std.math.maxInt(u64);
            st.performed = 0;
            while (st.phase != .ready) {
                if (try self.runPhase(st, &remaining)) st.phase = @enumFromInt(@intFromEnum(st.phase) + 1);
            }
            const spent = st.performed;
            st.units += spent;
            self.stats.units += spent;
            self.stats.units_finish = spent;
        }
        if (!st.quiet) try self.publishStep(st);
        if (!st.authoring) {
            self.gpa.free(self.evaluated);
            self.evaluated = st.head;
            st.head = &.{};
            self.total.accumulate(self.stats);
        }
        const quiet = st.quiet;
        self.deinitState(st);
        self.step_state = null;
        // What was applied is applied: the buffer is consumed. A second
        // `apply` with nothing new applies nothing (it re-applied
        // everything until P2.1b — the seams scene's first blob was
        // doubled since P1.2), and a world that settled is quiet at the
        // next step, not one empty publish later (the stale entries made
        // `isQuiet` say no once).
        if (!quiet) self.buffer.reset();
    }

    /// One step on fed time: begin, work it whole, finish.
    pub fn step(self: *World, now: Now, js: ?*jobs.JobSystem) Error!void {
        try self.begin(now, js);
        _ = try self.work(std.math.maxInt(u64));
        try self.finish();
    }

    fn addNs(self: *World, phase: Phase, ns: u64) void {
        switch (phase) {
            .operate => self.stats.ns_operate += ns,
            .fronts, .merge => self.stats.ns_fronts += ns,
            .apply => self.stats.ns_apply += ns,
            .frontier => self.stats.ns_frontier += ns,
            .scratch, .seam1_collect, .seam1_apply, .seam2_collect, .seam2_apply, .halo_collect, .halo_apply => self.stats.ns_seams += ns,
            .finalize => self.stats.ns_finalize += ns,
            .build => self.stats.ns_build += ns,
            .ready => self.stats.ns_publish += ns,
        }
    }

    /// Run the current phase for up to `remaining` units. True when the
    /// phase is complete.
    fn runPhase(self: *World, st: *StepState, remaining: *u64) Error!bool {
        _ = st.timer.lap();
        st.phase_units = 0;
        defer self.stats.units_phase[@intFromEnum(st.phase)] += st.phase_units;
        const done = switch (st.phase) {
            .fronts => try self.runFronts(st, remaining),
            .operate => try self.runOperate(st, remaining),
            .merge => try self.runMerge(st, remaining),
            .apply => try self.runApply(st, remaining),
            .frontier => try self.runFrontier(st, remaining),
            .scratch => try self.runScratch(st, remaining),
            .seam1_collect => try self.runCollect(st, remaining, 1),
            .seam1_apply => try self.runApplyWrites(st, remaining, false),
            .seam2_collect => try self.runCollect(st, remaining, 2),
            .seam2_apply => try self.runApplyWrites(st, remaining, false),
            .halo_collect => if (self.policy.halo) try self.runCollect(st, remaining, 0) else true,
            .halo_apply => if (self.policy.halo) try self.runApplyWrites(st, remaining, true) else true,
            .finalize => try self.runFinalize(st, remaining),
            .build => try self.runBuild(st, remaining),
            .ready => true,
        };
        self.addNs(st.phase, st.timer.lap());
        return done;
    }

    fn takeOf(left: usize, remaining: u64) usize {
        return @intCast(@min(@as(u64, left), remaining));
    }

    /// Account `n` units: performed, and off the call's remaining budget,
    /// saturating — an indivisible phase may overshoot, and the overshoot
    /// is then seen in `performed` (G15 b's mutation).
    fn spend(st: *StepState, remaining: *u64, n: u64) void {
        st.performed += n;
        remaining.* -|= n;
        st.phase_units += n;
    }

    // Fronts, parallel into their sinks, one unit each — charged first,
    // never cut. Merged in id order in the phase after the operators.
    fn runFronts(self: *World, st: *StepState, remaining: *u64) Error!bool {
        if (st.authoring or !st.evaluated) return true;
        if (st.front_cursor >= st.front_end) return true;
        const take = takeOf(st.front_end - st.front_cursor, remaining.*);
        var ctx = FrontCtx{
            .world = self,
            .base = st.base,
            .dt = st.dt,
            .evaluated = if (st.carried.items.len > 0) st.front_head else null,
            .sinks = st.sinks,
            .failed = std.atomic.Value(bool).init(false),
        };
        parallelRangeFrom(st.sys, st.front_cursor, st.front_cursor + take, 2, FrontCtx, &ctx, frontOne);
        if (ctx.failed.load(.acquire)) return Error.OutOfMemory;
        st.front_cursor += take;
        spend(st, remaining, take);
        return st.front_cursor >= st.front_end;
    }

    // Operate: region-local, order-free, one unit per head brick — the
    // only phase a cut stops.
    fn runOperate(self: *World, st: *StepState, remaining: *u64) Error!bool {
        if (st.authoring or !st.evaluated or self.operators.items.len == 0) return true;
        if (st.op_cursor >= st.op_end) return true;
        const take = takeOf(st.op_end - st.op_cursor, remaining.*);
        var ctx = OperateCtx{
            .world = self,
            .base = st.base,
            .dt = st.dt,
            .active = st.head,
            .updates = st.updates,
            .alloc = self.buffer.planeAllocator(),
            .evals = std.atomic.Value(u64).init(0),
            .clamped = std.atomic.Value(u64).init(0),
        };
        parallelRangeFrom(st.sys, st.op_cursor, st.op_cursor + take, self.policy.chunk, OperateCtx, &ctx, operateOne);
        self.stats.region_evals += ctx.evals.load(.monotonic);
        self.stats.diffusion_clamped += ctx.clamped.load(.monotonic);
        st.op_cursor += take;
        spend(st, remaining, take);
        return st.op_cursor >= st.op_end;
    }

    fn operateOne(ctx: *OperateCtx, i: usize) void {
        operateRange(ctx, i, i + 1);
    }

    // The sinks merged in id order — the serial pass's order — one unit.
    fn runMerge(self: *World, st: *StepState, remaining: *u64) Error!bool {
        if (st.authoring or !st.evaluated) return true;
        for (st.sinks) |*sk| try self.mergeSink(sk);
        spend(st, remaining, 1);
        return true;
    }

    // Apply deltas: per entry independently (clone, add, clamp), one unit
    // each; then recorded in key order, serially, which is what fixes the
    // order of everything downstream.
    fn runApply(self: *World, st: *StepState, remaining: *u64) Error!bool {
        const gpa = self.gpa;
        if (!st.apply_started) {
            // A unit is a brick applied: an entry opened for a head brick
            // that no operator wrote to is nothing to apply (the epoch step
            // after the scene build counted 3,652 of them as work).
            const all_entries = try self.buffer.sorted(gpa);
            defer gpa.free(all_entries);
            var n: usize = 0;
            for (all_entries) |ru| {
                if (ru.mask != 0 or ru.materialise or ru.spawns.items.len > 0) n += 1;
            }
            st.entries = try gpa.alloc(*update.RegionUpdate, n);
            var j: usize = 0;
            for (all_entries) |ru| {
                if (ru.mask != 0 or ru.materialise or ru.spawns.items.len > 0) {
                    st.entries[j] = ru;
                    j += 1;
                }
            }
            st.results = try gpa.alloc(?Changed, st.entries.len);
            for (st.results) |*r| r.* = null;
            st.results_live = true;
            st.apply_started = true;
        }
        if (st.apply_cursor < st.entries.len) {
            const take = takeOf(st.entries.len - st.apply_cursor, remaining.*);
            var actx = ApplyCtx{ .world = self, .base = st.base, .entries = st.entries, .results = st.results, .failed = std.atomic.Value(bool).init(false) };
            parallelRangeFrom(st.sys, st.apply_cursor, st.apply_cursor + take, 16, ApplyCtx, &actx, applyEntry);
            if (actx.failed.load(.acquire)) return Error.OutOfMemory;
            st.apply_cursor += take;
            spend(st, remaining, take);
            if (st.apply_cursor < st.entries.len) return false;
        }
        for (st.entries, st.results) |ru, r| {
            for (ru.spawns.items) |sp| try st.spawn_requests.append(gpa, sp);
            const c = r orelse continue;
            self.stats.collar_samples += c.collared;
            self.stats.provenance_writes += c.provenance;
            try st.changed.put(gpa, ru.key.raw(), c);
            try st.order.append(gpa, ru.key.raw());
        }
        st.results_live = false;
        st.bricks_owned = true;
        return true;
    }

    fn overridesOf(self: *World, st: *StepState) !void {
        st.overrides.clearRetainingCapacity();
        for (st.order.items) |raw| try st.overrides.append(self.gpa, .{ .key = Key.fromRaw(raw), .brick = st.changed.get(raw).?.b });
        std.mem.sort(tree.Override, st.overrides.items, {}, tree.Override.lessThan);
    }

    // Frontier: a changed brick whose face carries a value above the
    // floor materialises the absent neighbour across it. Probed against a
    // scratch tree that already holds this commit's bricks (one unit), a
    // unit per changed brick for its requests, then resolved finest first
    // (one unit) so a coarse request over a cube that finer requests are
    // filling completes it at the finer gauge instead of colliding with
    // it (a GaugeConflict at the tree build, P2.1).
    fn runFrontier(self: *World, st: *StepState, remaining: *u64) Error!bool {
        const gpa = self.gpa;
        while (remaining.* > 0) {
            switch (st.frontier_stage) {
                0 => {
                    try self.overridesOf(st);
                    st.pre_root = try tree.build(gpa, st.base.root, st.overrides.items);
                    spend(st, remaining, 1);
                    st.frontier_stage = 1;
                },
                1 => {
                    const pre = Snapshot{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = st.pre_root };
                    while (st.frontier_cursor < st.order.items.len and remaining.* > 0) {
                        try self.frontierRequests(&pre, st.changed.get(st.order.items[st.frontier_cursor]).?.b, &st.requests);
                        st.frontier_cursor += 1;
                        spend(st, remaining, 1);
                    }
                    if (st.frontier_cursor < st.order.items.len) return false;
                    st.frontier_stage = 2;
                },
                2 => {
                    const pre = Snapshot{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = st.pre_root };
                    try self.materialiseRequests(st.base, &pre, st.requests.items, &st.changed, &st.order);
                    if (st.pre_root) |r| r.release(gpa);
                    st.pre_root = null;
                    spend(st, remaining, 1);
                    st.frontier_stage = 3;
                    return true;
                },
                else => return true,
            }
        }
        return st.frontier_stage == 3;
    }

    // A scratch tree with every changed brick, for the seam pass: one unit.
    fn runScratch(self: *World, st: *StepState, remaining: *u64) Error!bool {
        try self.overridesOf(st);
        st.scratch_root = try tree.build(self.gpa, st.base.root, st.overrides.items);
        spend(st, remaining, 1);
        return true;
    }

    // Seams (pass 1 and 2) and halos (pass 0): collect writes in parallel,
    // one unit per changed brick, into a list per brick; then gather and
    // sort them for the apply. Only the bricks changed before the pass
    // began are walked — neighbours the pass clones join `order` but
    // their only new values are copies made here.
    fn runCollect(self: *World, st: *StepState, remaining: *u64, pass: u8) Error!bool {
        const gpa = self.gpa;
        if (st.lists.len == 0 and st.collect_cursor == 0) {
            if (pass != 2) st.n0 = st.order.items.len;
            if (st.n0 == 0) return true;
            st.lists = try gpa.alloc(WriteList, st.n0);
            for (st.lists) |*l| l.* = .{};
            if (pass == 1) {
                st.nbs = try gpa.alloc(?Neighbourhood, st.n0);
                for (st.nbs) |*slot| slot.* = null;
            } else {
                for (st.nbs) |*slot| if (slot.*) |*nb| nb.refresh(&st.changed);
            }
        }
        if (st.n0 == 0) return true;
        const view = Snapshot{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = st.scratch_root };
        const take = takeOf(st.n0 - st.collect_cursor, remaining.*);
        if (pass == 0) {
            var ctx = HaloCtx{ .world = self, .view = &view, .changed = &st.changed, .order = st.order.items[0..st.n0], .chunk = 1, .lists = st.lists, .nbs = st.nbs, .failed = std.atomic.Value(bool).init(false) };
            parallelRangeFrom(st.sys, st.collect_cursor, st.collect_cursor + take, 4, HaloCtx, &ctx, haloCollectOne);
            if (ctx.failed.load(.acquire)) return Error.OutOfMemory;
        } else {
            var ctx = CollectCtx{ .world = self, .view = &view, .changed = &st.changed, .order = st.order.items[0..st.n0], .pass = pass, .chunk = 1, .lists = st.lists, .nbs = st.nbs, .failed = std.atomic.Value(bool).init(false) };
            parallelRangeFrom(st.sys, st.collect_cursor, st.collect_cursor + take, 4, CollectCtx, &ctx, collectOne);
            if (ctx.failed.load(.acquire)) return Error.OutOfMemory;
        }
        st.collect_cursor += take;
        spend(st, remaining, take);
        if (st.collect_cursor < st.n0) return false;
        st.all.clearRetainingCapacity();
        for (st.lists) |*l| {
            try st.all.appendSlice(gpa, l.items);
            l.deinit(gpa);
        }
        gpa.free(st.lists);
        st.lists = &.{};
        st.collect_cursor = 0;
        std.mem.sort(SeamWrite, st.all.items, {}, SeamWrite.lessThan);
        st.group_cursor = 0;
        return true;
    }

    // The sorted writes applied per target brick, one unit each (the
    // whole pass in one unit under the mutation). Halo writes are counted
    // apart.
    fn runApplyWrites(self: *World, st: *StepState, remaining: *u64, halo: bool) Error!bool {
        if (st.all.items.len == 0) return true;
        if (halo and st.group_cursor == 0) st.seam_writes_before = self.stats.seam_writes;
        const view = Snapshot{ .gpa = self.gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = st.scratch_root };
        const max: u64 = if (self.policy.chunk_applies) remaining.* else std.math.maxInt(u64);
        const done = try self.applyWriteGroups(&view, &st.changed, &st.order, st.all.items, &st.group_cursor, max);
        spend(st, remaining, done);
        if (st.group_cursor < st.all.items.len) return false;
        if (halo) {
            self.stats.halo_writes += self.stats.seam_writes - st.seam_writes_before;
            self.stats.seam_writes = st.seam_writes_before;
        }
        st.all.clearRetainingCapacity();
        st.group_cursor = 0;
        return true;
    }

    // Finalize every changed brick, one unit each; then the lists the
    // build and the snapshot need, serially.
    fn runFinalize(self: *World, st: *StepState, remaining: *u64) Error!bool {
        const gpa = self.gpa;
        const eps = thresholds.EPSILON;
        if (st.finalize_cursor < st.order.items.len) {
            const take = takeOf(st.order.items.len - st.finalize_cursor, remaining.*);
            var fctx = FinalizeCtx{ .world = self, .base = st.base, .changed = &st.changed, .order = st.order.items, .now_ns = st.now.time_ns, .head = st.head_sorted };
            parallelRangeFrom(st.sys, st.finalize_cursor, st.finalize_cursor + take, 8, FinalizeCtx, &fctx, finalizeOne);
            self.stats.ns_hash += fctx.hash_ns.load(.monotonic);
            st.finalize_cursor += take;
            spend(st, remaining, take);
            if (st.finalize_cursor < st.order.items.len) return false;
        }
        try self.overridesOf(st);
        for (st.order.items) |raw| {
            const c = st.changed.getPtr(raw).?;
            try st.dirty.append(gpa, Key.fromRaw(raw));
            if (c.max_delta > eps or c.materialised) try st.active_out.append(gpa, Key.fromRaw(raw));
            if (c.materialised) self.stats.bricks_materialised += 1;
        }
        self.stats.bricks_changed = st.order.items.len;
        return true;
    }

    // The real tree: one unit. The overrides' bricks are retained by
    // their leaves; ours are dropped.
    fn runBuild(self: *World, st: *StepState, remaining: *u64) Error!bool {
        const gpa = self.gpa;
        st.root = try tree.build(gpa, st.base.root, st.overrides.items);
        for (st.order.items) |raw| st.changed.get(raw).?.b.release(gpa);
        st.bricks_owned = false;
        if (st.scratch_root) |r| r.release(gpa);
        st.scratch_root = null;
        spend(st, remaining, 1);
        return true;
    }

    // Spawn what was requested, assign ids in order; the active set for
    // the next step; the snapshot; publish.
    fn publishStep(self: *World, st: *StepState) Error!void {
        const gpa = self.gpa;
        const base = st.base;
        const now = st.now;
        for (self.pending_spawns.items) |s| try st.spawn_requests.append(gpa, s);
        self.pending_spawns.clearRetainingCapacity();
        for (st.spawn_requests.items) |s| {
            const id: u32 = @intCast(self.fronts.items.len);
            var f = Front{
                .id = id,
                .parent = s.parent,
                .generation = s.generation,
                .pos = s.pos,
                .dir = s.dir,
                .normal = s.normal,
                .params = s.params,
                .morphogens = s.morphogens,
                .born_epoch = self.epoch,
                .brick = Key.ofBrick(0, .{ 0, 0, 0 }),
                .prev_pos = s.pos,
                .prev_dir = s.dir,
                .prev_normal = s.normal,
                .prev_envelope = s.params.radius,
            };
            f.brick = self.brickUnder(base, f.pos);
            try self.fronts.append(gpa, f);
            // Ring zero: the seed, where the first sweep starts.
            try self.rings.append(gpa, .{});
            try self.rings.items[id].append(gpa, f.prevRing());
        }
        var active = &st.active_out;
        for (self.fronts.items) |*f| {
            if (f.alive and !f.dormant) try active.append(gpa, f.brick);
        }
        if (!st.evaluated) {
            for (base.active) |k| try active.append(gpa, k);
        }
        for (st.carried.items) |k| try active.append(gpa, k);

        std.mem.sort(Key, active.items, {}, Key.lessThan);
        std.mem.sort(Key, st.dirty.items, {}, Key.lessThan);
        const snap = try gpa.create(Snapshot);
        errdefer gpa.destroy(snap);
        const fronts_copy = try gpa.dupe(Front, self.fronts.items);
        errdefer gpa.free(fronts_copy);
        const active_owned = try dedupKeys(gpa, active.items);
        errdefer gpa.free(active_owned);
        const dirty_owned = try dedupKeys(gpa, st.dirty.items);
        errdefer gpa.free(dirty_owned);
        // Since when each active brick is owed (R17): now if evaluated this
        // step, else what it was, else now.
        const since_owned = try gpa.alloc(u64, active_owned.len);
        errdefer gpa.free(since_owned);
        for (active_owned, 0..) |k, i| {
            since_owned[i] = if (keyInSorted(st.head_sorted, k)) now.time_ns else (base.sinceOf(k) orelse now.time_ns);
        }
        snap.* = .{
            .gpa = gpa,
            .vid = self.vid + 1,
            .epoch = self.epoch,
            .time_ns = now.time_ns,
            .seed = self.seed,
            .root = st.root,
            .fronts = fronts_copy,
            .active = active_owned,
            .dirty = dirty_owned,
            .active_since = since_owned,
            .budget = st.budget,
            .cut_at = st.cut_at,
            .units = st.units,
            .calls = st.calls,
        };
        st.root = null; // the snapshot's now
        const counts = snap.countNodes();
        snap.brick_count = counts.bricks;
        snap.node_count = counts.nodes;
        self.stats.active_out = active_owned.len;
        _ = st.timer.lap();
        try self.publish(snap);
        self.stats.ns_publish += st.timer.lap();
    }

    const Head = struct { head: []Key, carried: []Key, fronts: []Key };

    /// The bricks hosting a live front — dormant included: its wake check
    /// is its step, and a wake deferred by the budget is a clock touched
    /// by the budget. Obligations. Owned, sorted, unique.
    fn frontBricks(self: *const World, gpa: std.mem.Allocator) ![]Key {
        var list = std.ArrayListUnmanaged(Key){};
        defer list.deinit(gpa);
        for (self.fronts.items) |f| if (f.alive) try list.append(gpa, f.brick);
        std.mem.sort(Key, list.items, {}, Key.lessThan);
        return dedupKeys(gpa, list.items);
    }

    /// The bricks this step evaluates, owned: the active set as it is when
    /// no budget is set or it fits; otherwise the head in two tiers — the
    /// obligations (`base.obliged` and the live fronts' bricks) in key
    /// order, then the rest by attention at `now`, descending, ties by
    /// key — cut at the budget; and the tail, owned, to carry: what stays
    /// attentive above the floor or hosts a front, the rest faded. `.key`
    /// takes the first bricks in Morton order instead: G14 (c)'s mutation.
    fn chooseHead(self: *World, base: *const Snapshot, active: []const Key, now: Now) !Head {
        const gpa = self.gpa;
        const fronts = try self.frontBricks(gpa);
        errdefer gpa.free(fronts);
        const backlog = base.backlog();
        self.stats.backlog = backlog;
        const budget: usize = self.policy.budget orelse active.len;
        if (self.policy.budget) |b| {
            if (backlog > b) self.overload_steps += 1 else self.overload_steps = 0;
        } else self.overload_steps = 0;
        // The head is ORDERED whether or not the budget cuts it: a `cut`
        // (R16) stops the operate phase at its cursor, and the prefix it
        // keeps must be the fronts and then the highest by score. (Under
        // `.key` the order is Morton — the mutation.)
        // tier 0: hosts a live front (never cut); 1: the rest, by score.
        // Under `.queue` the backlog joins tier 0 — the tier ruling's
        // mutation, one key-ordered queue cut at the budget.
        const Scored = struct { key: Key, a: f64, score: f64, tier: u8 };
        const scored = try gpa.alloc(Scored, active.len);
        defer gpa.free(scored);
        const tau_a: f64 = thresholds.ATTENTION_TAU_S;
        const tau_lag: f64 = thresholds.LAG_TAU_S;
        const order = self.policy.budget_order;
        var n0: usize = 0;
        for (active, 0..) |k, i| {
            const hosts = keyInSorted(fronts, k);
            const since = base.sinceOf(k) orelse now.time_ns;
            const owed_before = since < base.time_ns;
            const pending: f64 = if (base.brickAt(k)) |b| b.summary.attention else 0;
            const lag_s: f64 = @as(f64, @floatFromInt(now.time_ns -| since)) / 1e9;
            scored[i] = .{
                .key = k,
                .a = attentionOf(base, k, now.time_ns, tau_a),
                .score = if (order == .no_lag) pending else pending * (1 + lag_s / tau_lag),
                .tier = if (hosts or (order == .queue and owed_before)) 0 else 1,
            };
            if (hosts) n0 += 1;
        }
        switch (order) {
            .attention, .queue, .no_lag => std.mem.sort(Scored, scored, {}, struct {
                fn lt(_: void, x: Scored, y: Scored) bool {
                    if (x.tier != y.tier) return x.tier < y.tier;
                    if (x.tier == 1 and x.score != y.score) return x.score > y.score;
                    return x.key.raw() < y.key.raw();
                }
            }.lt),
            .key => {}, // the active set is Morton-sorted already
        }
        // The fronts' tier is never cut: the head grows past the budget by
        // what they exceed it, and the step reports the overrun. (The
        // `.key` and `.queue` mutations cut at the budget, fronts and all.)
        // (Never past the active set: a budget of one over an empty active
        // set — the step after a world settles, reached through the
        // previous step's stale buffer — indexed an empty head once.)
        const take: usize = @min(if (order == .attention or order == .no_lag) @max(budget, n0) else budget, active.len);
        self.stats.overrun = take - budget;
        const head = try gpa.alloc(Key, take);
        errdefer gpa.free(head);
        for (scored[0..take], 0..) |s, i| head[i] = s.key;
        // The tail: carried while attentive above the floor or hosting a
        // front, faded otherwise.
        const eps: f64 = thresholds.EPSILON;
        var kept: usize = 0;
        for (scored[take..]) |s| {
            if (s.a > eps or keyInSorted(fronts, s.key)) kept += 1;
        }
        self.stats.faded = active.len - take - kept;
        const carried = try gpa.alloc(Key, kept);
        var j: usize = 0;
        for (scored[take..]) |s| {
            if (s.a > eps or keyInSorted(fronts, s.key)) {
                carried[j] = s.key;
                j += 1;
            }
        }
        return .{ .head = head, .carried = carried, .fronts = fronts };
    }

    /// A brick's attention at fed time `now_ns` for τ, from its summary
    /// alone; 0 where there is no brick.
    pub fn attentionOf(base: *const Snapshot, key: Key, now_ns: u64, tau_s: f64) f64 {
        const b = base.brickAt(key) orelse return 0;
        return b.summary.attentionAt(now_ns, tau_s);
    }

    /// The published brick's attention at `now_ns`, with the sim's τ.
    pub fn attention(self: *const World, key: Key, now_ns: u64) f64 {
        return attentionOf(self.published(), key, now_ns, thresholds.ATTENTION_TAU_S);
    }

    /// Nothing for a step to do: no active brick, no live non-dormant
    /// front, no spawn pending, nothing authored.
    fn isQuiet(self: *const World, base: *const Snapshot) bool {
        if (base.active.len != 0) return false;
        if (self.pending_spawns.items.len != 0) return false;
        if (self.buffer.regions.count() != 0) return false;
        for (self.fronts.items) |f| if (f.alive and !f.dormant) return false;
        return true;
    }

    const OperateCtx = struct {
        world: *World,
        base: *const Snapshot,
        dt: f64,
        active: []const Key,
        updates: []*update.RegionUpdate,
        alloc: std.mem.Allocator,
        evals: std.atomic.Value(u64),
        clamped: std.atomic.Value(u64),
    };

    fn operateJob(job: *jobs.Job) void {
        const range = job.getData(jobs.BatchRange);
        const ctx: *OperateCtx = @ptrCast(@alignCast(@constCast(range.context)));
        operateRange(ctx, range.start, range.end);
    }

    fn operateRange(ctx: *OperateCtx, start: usize, end: usize) void {
        var i = start;
        while (i < end) : (i += 1) {
            const key = ctx.active[i];
            const b = ctx.base.brickAt(key) orelse continue;
            var rc = operators.RegionContext{
                .snapshot = ctx.base,
                .brick = b,
                .dt = ctx.dt,
                .epoch = ctx.world.epoch,
                .time_s = @floatCast(@as(f64, @floatFromInt(ctx.world.time_ns)) / 1e9),
                .seed = ctx.world.seed,
                .alloc = ctx.alloc,
                .registry = &ctx.world.registry,
                .fronts_here = frontsNear(ctx.base.fronts, key),
            };
            for (ctx.world.operators.items) |op| {
                op.evaluate(&rc, ctx.updates[i]) catch |err| {
                    std.debug.panic("operator {s} failed: {s}", .{ op.name(), @errorName(err) });
                };
                _ = ctx.evals.fetchAdd(1, .monotonic);
            }
            _ = ctx.clamped.fetchAdd(rc.clamped, .monotonic);
        }
    }

    /// Run `f(ctx, i)` for i in [0, count): over the JobSystem in chunks
    /// when there is one, else here. `f` must be order-free — every
    /// parallel phase is gated by G1 running with and without a system.
    fn parallelRange(sys: ?*jobs.JobSystem, count: usize, chunk: u32, comptime Ctx: type, ctx: *Ctx, comptime f: fn (*Ctx, usize) void) void {
        parallelRangeFrom(sys, 0, count, chunk, Ctx, ctx, f);
    }

    /// `f(ctx, i)` for i in [start, end), over the job system in batches
    /// of `chunk` when there is one — a phase's cursor window (R16).
    fn parallelRangeFrom(sys: ?*jobs.JobSystem, start: usize, end: usize, chunk: u32, comptime Ctx: type, ctx: *Ctx, comptime f: fn (*Ctx, usize) void) void {
        if (end <= start) return;
        if (sys) |js| {
            const Off = struct { ctx: *Ctx, start: usize };
            const Wrap = struct {
                fn job(j: *jobs.Job) void {
                    const range = j.getData(jobs.BatchRange);
                    const o: *Off = @ptrCast(@alignCast(@constCast(range.context)));
                    var i: usize = range.start;
                    while (i < range.end) : (i += 1) f(o.ctx, o.start + i);
                }
            };
            var off = Off{ .ctx = ctx, .start = start };
            var counter = jobs.Counter.init(0);
            js.parallelFor(@intCast(end - start), chunk, Wrap.job, &off, &counter);
            js.waitFor(&counter);
        } else {
            var i: usize = start;
            while (i < end) : (i += 1) f(ctx, i);
        }
    }

    pub const parallelRangePub = parallelRange;

    /// Live, non-dormant fronts within a brick and a half of `key`'s
    /// centre — "something is already working here". Linear; fronts are
    /// the sparse working set and this is read once per active brick.
    /// (Counting only the brick itself let a wound edge spawn a repair
    /// front every few steps as each one moved on: 285 fronts for one
    /// wound.)
    /// Reads the fronts AS PUBLISHED (`base.fronts`), never the world's
    /// live list: the front pass runs before the operators now (R16,
    /// fronts charged first) and moves them, and an operator that read
    /// the moved positions spawned two more repair fronts (9 for 7) —
    /// a step's operators read the snapshot they step from, fronts
    /// included.
    fn frontsNear(fronts: []const Front, key: Key) u32 {
        const o = key.origin();
        const side: f64 = @floatFromInt(key.side());
        const reach = side * 1.5;
        var n: u32 = 0;
        for (fronts) |*f| {
            if (!f.alive or f.dormant) continue;
            var near = true;
            inline for (0..3) |a| {
                const c = @as(f64, @floatFromInt(o[a])) + side * 0.5;
                if (@abs(f.pos[a] - c) > reach) near = false;
            }
            if (near) n += 1;
        }
        return n;
    }

    // ── The front pass (R1) ──────────────────────────────────────────────
    //
    // Fronts run in parallel, each into a SINK of its own — its deposits
    // by brick, its spawns, its counts — and the sinks are merged into the
    // shared buffer in id order afterwards. Float addition is not
    // associative, so the merge adds each front's planes in the order the
    // serial pass added them; the bytes are the same at any thread count
    // and G1 says so.

    /// One front's output for the step.
    const Sink = struct {
        alloc: std.mem.Allocator,
        /// The front's id: sinks are one per front, in id order.
        id: u32 = 0,
        entries: std.ArrayListUnmanaged(*update.RegionUpdate) = .{},
        by_key: std.AutoHashMapUnmanaged(u64, *update.RegionUpdate) = .{},
        spawns: std.ArrayListUnmanaged(update.Spawn) = .{},
        stepped: bool = false,
        dormant: bool = false,
        skipped: bool = false,
        died: bool = false,
        spawned: u64 = 0,
        below_faithful: bool = false,
        /// The ring this step swept, for the history.
        ring: ?front.Ring = null,

        fn region(self: *Sink, key: Key) !*update.RegionUpdate {
            const gop = try self.by_key.getOrPut(self.alloc, key.raw());
            if (!gop.found_existing) {
                const ru = try self.alloc.create(update.RegionUpdate);
                ru.* = .{ .key = key };
                gop.value_ptr.* = ru;
                try self.entries.append(self.alloc, ru);
            }
            return gop.value_ptr.*;
        }
    };

    const FrontCtx = struct {
        world: *World,
        base: *const Snapshot,
        dt: f64,
        evaluated: ?[]const Key,
        sinks: []Sink,
        failed: std.atomic.Value(bool),
    };

    fn frontOne(ctx: *FrontCtx, i: usize) void {
        frontStep(ctx, i) catch {
            ctx.failed.store(true, .release);
        };
    }

    fn frontStep(ctx: *FrontCtx, i: usize) !void {
        const self = ctx.world;
        const base = ctx.base;
        const f = &self.fronts.items[i];
        const sink = &ctx.sinks[i];
        if (!f.alive) return;
        // A dormant front re-checks only when something changed under it;
        // nothing did, so nothing is owed and nothing is skipped.
        if (f.dormant and !keyInSorted(base.active, f.brick)) {
            sink.dormant = true;
            return;
        }
        // A brick the budget carried: its front waits with it, untouched
        // (only the two mutations cut a front's brick; struck otherwise).
        if (ctx.evaluated) |ev| if (!keyInSorted(ev, f.brick)) {
            sink.skipped = true;
            return;
        };
        if (f.dormant) {
            if (!self.canGrow(base, f)) {
                sink.dormant = true;
                return;
            }
            f.dormant = false;
        } else if (!self.canGrow(base, f)) {
            f.dormant = true;
            sink.dormant = true;
            return;
        }
        try self.stepFront(base, f, ctx.dt, sink);
        sink.stepped = true;
    }

    /// Merge one front's sink into the update buffer — in id order, the
    /// serial pass's order — brick by brick, channel by channel, sample by
    /// sample, adding only what the front wrote (a zero it never touched
    /// must not turn a −0 into +0).
    fn mergeSink(self: *World, sk: *Sink) !void {
        const gpa = self.gpa;
        if (sk.stepped) self.stats.front_steps += 1;
        if (sk.dormant) self.stats.fronts_dormant += 1;
        if (sk.skipped) self.stats.fronts_skipped += 1;
        if (sk.died) self.stats.deaths += 1;
        if (sk.below_faithful) self.stats.below_faithful += 1;
        self.stats.spawns += sk.spawned;
        if (sk.ring) |r| try self.rings.items[sk.id].append(gpa, r);
        std.mem.sort(*update.RegionUpdate, sk.entries.items, {}, struct {
            fn lt(_: void, a: *update.RegionUpdate, b: *update.RegionUpdate) bool {
                return a.key.raw() < b.key.raw();
            }
        }.lt);
        for (sk.entries.items) |local| {
            const ru = try self.buffer.region(local.key);
            // The carrier's ops ride across whole: composed at commit,
            // in id order, never summed (R10).
            for (local.surface_ops.items) |op| try ru.surface_ops.append(self.buffer.arena.allocator(), op);
            const op_mask = Channel.surface.mask() | channel.PROVENANCE_MASK | channel.SLOT_MASK;
            if (local.surface_ops.items.len > 0) ru.mask |= local.mask & op_mask;
            var mask = local.mask & ~op_mask;
            while (mask != 0) {
                const bit: u6 = @intCast(@ctz(mask));
                mask &= mask - 1;
                const src = local.deltas[bit].?;
                const dst = try ru.delta(self.buffer.arena.allocator(), bit);
                switch (channel.rule(bit)) {
                    // Birth time is written ONCE per sample per step: the
                    // serial pass let the first front's pending write
                    // stop the second's. Here the first in id order wins,
                    // which is the same front.
                    .set_once => for (dst, src) |*d, v| {
                        if (v != 0 and d.* == 0) d.* = v;
                    },
                    // A touch time: every front this step writes the same
                    // second, so the last in id order is the first.
                    .touch => for (dst, src) |*d, v| {
                        if (v != 0) d.* = v;
                    },
                    .add => for (dst, src) |*d, v| {
                        if (v != 0) d.* += v;
                    },
                    .smin, .set_by_winner, .distance => unreachable, // ops, above
                }
            }
        }
        for (sk.spawns.items) |sp| try self.pending_spawns.append(gpa, sp);
    }

    fn keyInSorted(keys: []const Key, k: Key) bool {
        var lo: usize = 0;
        var hi: usize = keys.len;
        const r = k.raw();
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const m = keys[mid].raw();
            if (m == r) return true;
            if (m < r) lo = mid + 1 else hi = mid;
        }
        return false;
    }

    fn aheadOf(f: *const Front) [3]f64 {
        const r: f64 = f.params.radius;
        return .{ f.pos[0] + f.dir[0] * (r + 1), f.pos[1] + f.dir[1] * (r + 1), f.pos[2] + f.dir[2] * (r + 1) };
    }

    /// The ramp a front's deposition softens over, lattice units: the
    /// Phase 1 material profile was 1 inside the ring and fell to 0 over
    /// this distance outside it, and what a front READS of tissue is that
    /// profile still (`occupancy`), so a change of representation did not
    /// move a front (the habit check, P2.1).
    pub const SOFT: f64 = 0.75;

    /// What a front sees of tissue at `p`: the carrier as an occupancy —
    /// 1 inside, 0 beyond `SOFT` outside, smooth between. Not the carrier
    /// itself: its gradient is a unit vector everywhere in the band and
    /// radially outward inside a tube, and reading that as self-avoidance
    /// pushed every front off its own axis (the trunk 25 units away from
    /// Phase 1's by step 160; with the read restored, 0.001).
    pub fn occupancy(base: *const Snapshot, p: [3]f64) f32 {
        return @floatCast(smooth(SOFT, -SOFT, base.sample(Channel.surface.bit(), p)));
    }

    /// Central-difference gradient of the occupancy at `p`, per lattice unit.
    fn occupancyGradient(base: *const Snapshot, p: [3]f64, h: f64) [3]f64 {
        var g: [3]f64 = undefined;
        inline for (0..3) |a| {
            var pp = p;
            var pm = p;
            pp[a] += h;
            pm[a] -= h;
            g[a] = (@as(f64, occupancy(base, pp)) - @as(f64, occupancy(base, pm))) / (2 * h);
        }
        return g;
    }

    /// Growth potential one radius ahead of the front, and no tissue in
    /// the way there (inhibition): the occupancy one radius ahead is not
    /// above `inhibit`. A front's own cap ends one radius short of that
    /// point, so it does not inhibit itself.
    fn canGrow(_: *World, base: *const Snapshot, f: *const Front) bool {
        const ahead = aheadOf(f);
        const g = base.sample(Channel.growth.bit(), ahead);
        if (g <= thresholds.EPSILON) return false;
        return occupancy(base, ahead) <= f.params.inhibit;
    }

    fn stepFront(self: *World, base: *const Snapshot, f: *Front, dt: f64, sink: *Sink) !void {
        const p = f.params;
        var stream = rng.Stream.front(self.seed, f.id, self.epoch);

        // Steer (spec §11): v = a·∇light + b·∇stimulus − d·∇self + e·heading + noise.
        const h: f64 = @max(1.0, @as(f64, p.radius) * 0.5);
        const gl = base.gradient(Channel.light.bit(), f.pos, h);
        const gs = base.gradient(Channel.stimulus.bit(), f.pos, h);
        // Self-avoidance reads the occupancy, as Phase 1 read Material.
        const gm = occupancyGradient(base, f.pos, h);
        const nz = [3]f64{ stream.gauss(), stream.gauss(), stream.gauss() };
        var v: [3]f64 = undefined;
        inline for (0..3) |a| {
            v[a] = @as(f64, p.tropism_light) * gl[a] + @as(f64, p.tropism_stimulus) * gs[a] - @as(f64, p.avoid_self) * gm[a] + @as(f64, p.persist) * f.dir[a] + @as(f64, p.wander) * nz[a];
        }
        const vl = len3(v);
        const old_dir = f.dir;
        if (vl > 1e-9) f.dir = .{ v[0] / vl, v[1] / vl, v[2] / vl };
        // Move by arc length.
        const ds: f64 = @as(f64, p.speed) * dt;
        // The coil: a fixed turn about the world's vertical per unit of
        // arc, the elbow measurement's knob (the sim's own sin and cos).
        if (p.coil != 0) {
            const ang = @as(f64, p.coil) * ds;
            const c = fmath.cos(ang);
            const sn = fmath.sin(ang);
            const x = f.dir[0];
            const z = f.dir[2];
            f.dir = .{ c * x + sn * z, f.dir[1], c * z - sn * x };
        }
        f.normal = transport(f.normal, old_dir, f.dir);
        inline for (0..3) |a| f.pos[a] += f.dir[a] * ds;
        f.s += ds;
        f.age += 1;
        if (f.cooldown > 0) f.cooldown -= 1;
        f.roll += @as(f64, p.drift);

        // Off the lattice, or grown out: the front ends.
        const margin: f64 = @as(f64, p.radius) + 2;
        inline for (0..3) |a| {
            if (f.pos[a] < margin or f.pos[a] > @as(f64, lattice.CELLS) - margin) f.alive = false;
        }
        if (f.s >= p.length) f.alive = false;
        if (!f.alive) {
            sink.died = true;
            return;
        }

        // The ring CA — loop-loft's update, one ring per step.
        const t: f32 = @floatCast(@min(1.0, f.s / @as(f64, p.length)));
        const envelope: f32 = p.radius * (1 - p.taper * t) * (1 + p.bulge * fmath.sinf(2 * std.math.pi * p.waves * t));
        ringStep(f, &stream, envelope);
        if (envelope < thresholds.G13_FAITHFUL_R_OVER_H * @as(f32, @floatFromInt(@as(u32, 1) << self.policy.default_gauge))) sink.below_faithful = true;

        // Deposit the ring into the field; draw down the potential around it.
        f.segment += 1;
        sink.ring = f.ringRecord(envelope);
        const avail = base.sample(Channel.growth.bit(), aheadOf(f));
        try self.stamp(base, f, dt, envelope, avail, sink);

        // Branch from a bud.
        if (f.age >= p.min_age and f.cooldown == 0 and f.generation < p.max_generation) {
            var best: ?usize = null;
            var best_r: f32 = 0;
            for (f.ring, 0..) |sl, si| {
                if (sl.tag == .bud and @abs(sl.r) > best_r) {
                    best = si;
                    best_r = @abs(sl.r);
                }
            }
            if (best) |si| {
                try sink.spawns.append(sink.alloc, self.budSpawn(f, si, envelope));
                sink.ring.?.bud = @intCast(si);
                f.ring[si] = .{};
                f.cooldown = p.branch_cooldown;
                sink.spawned += 1;
            }
        }

        f.brick = self.brickUnder(base, f.pos);
        // This ring is the next sweep's start.
        f.prev_pos = f.pos;
        f.prev_dir = f.dir;
        f.prev_normal = f.normal;
        f.prev_roll = f.roll;
        f.prev_s = f.s;
        f.prev_envelope = envelope;
        for (f.ring, 0..) |sl, i| f.prev_r[i] = sl.r;
    }

    fn ringStep(f: *Front, stream: *rng.Stream, envelope: f32) void {
        const p = f.params;
        const N = front.SLOTS;
        var tmp: [N]f32 = undefined;
        // leak toward the envelope (residual decays to 0)
        for (&f.ring) |*sl| {
            sl.r *= 1 - p.heal;
            sl.dz *= 1 - p.heal;
        }
        // ring diffusion
        for (0..N) |i| {
            const a = f.ring[(i + N - 1) % N].r;
            const b = f.ring[(i + 1) % N].r;
            tmp[i] = std.math.lerp(f.ring[i].r, (a + b) * 0.5, p.diffuse);
        }
        for (0..N) |i| f.ring[i].r = tmp[i];
        // noise drive
        for (&f.ring) |*sl| {
            sl.r += stream.gauss() * p.noise * 0.08 * p.radius;
            sl.dz += stream.gauss() * p.noise * 0.05 * p.speed;
        }
        // impulse: a bump kernel lands on the ring
        if (stream.unit() < p.impulse) {
            const c: i32 = @intCast(stream.below(@intCast(N)));
            const w: i32 = 2 + @as(i32, @intCast(stream.below(4)));
            const sign: f32 = if (stream.unit() < 0.5) -0.6 else 1.0;
            const s = sign * (0.25 + stream.unit() * 0.5) * p.radius * 0.6;
            var d: i32 = -w;
            while (d <= w) : (d += 1) {
                const i: usize = @intCast(@mod(c + d, @as(i32, @intCast(N))));
                f.ring[i].r += s * (0.5 + 0.5 * fmath.cosf(std.math.pi * @as(f32, @floatFromInt(d)) / @as(f32, @floatFromInt(w))));
            }
        }
        // jitter clamp, and the bud enzyme: hot for k rings earns the tag
        const jz = p.jitter * p.speed;
        for (&f.ring) |*sl| {
            sl.dz = @min(jz, @max(-jz, sl.dz));
            if (@abs(sl.r) > p.bud_threshold * envelope) {
                sl.age += 1;
                if (sl.age >= p.bud_rings) sl.tag = .bud;
            } else {
                sl.age = 0;
                if (sl.tag == .bud) sl.tag = .none;
            }
        }
    }

    pub fn budSpawn(self: *World, f: *const Front, si: usize, envelope: f32) update.Spawn {
        _ = self;
        const p = f.params;
        const theta: f64 = 2 * std.math.pi * @as(f64, @floatFromInt(si)) / @as(f64, front.SLOTS) + f.roll;
        const bin = cross(f.dir, f.normal);
        var radial: [3]f64 = undefined;
        const ct = fmath.cos(theta);
        const st = fmath.sin(theta);
        inline for (0..3) |a| radial[a] = ct * f.normal[a] + st * bin[a];
        const rr: f64 = envelope + f.ring[si].r;
        var pos: [3]f64 = undefined;
        var dir: [3]f64 = undefined;
        const ca = fmath.cos(@as(f64, p.branch_angle));
        const sa = fmath.sin(@as(f64, p.branch_angle));
        inline for (0..3) |a| {
            pos[a] = f.pos[a] + radial[a] * rr;
            dir[a] = ca * f.dir[a] + sa * radial[a];
        }
        const dl = len3(dir);
        inline for (0..3) |a| dir[a] /= dl;
        var cp = p;
        cp.radius = p.radius * p.child_ratio;
        cp.length = p.length * p.child_ratio;
        return .{
            .pos = pos,
            .dir = dir,
            .normal = transport(f.normal, f.dir, dir),
            .params = cp,
            .parent = f.id,
            .generation = f.generation + 1,
            .morphogens = f.morphogens,
        };
    }

    /// The brick holding `pos`: the leaf there, or the default-gauge key
    /// that would be materialised.
    fn brickUnder(self: *const World, base: *const Snapshot, pos: [3]f64) Key {
        const p = [3]i64{ tree.floorI(pos[0]), tree.floorI(pos[1]), tree.floorI(pos[2]) };
        if (base.findLeaf(p)) |b| return b.key;
        return Key.containing(self.policy.default_gauge, .{ clampU(p[0]), clampU(p[1]), clampU(p[2]) });
    }

    fn clampU(v: i64) u32 {
        return @intCast(@min(@as(i64, lattice.CELLS), @max(@as(i64, 0), v)));
    }

    /// Sweep the capsule from the previous ring to this one into the
    /// carrier (R11), stamp Activity and Age, and draw down Growth in a
    /// sphere of two radii. Between ring k−1 and ring k the front sweeps
    /// a lofted capsule whose radius at (s, θ) interpolates the two
    /// rings' profiles; at every node in reach it evaluates the signed
    /// implicit ρ − r(s, θ) and hands it to the commit as a surface op,
    /// smooth-unioned in with the front's collar. Nothing is quantised:
    /// the ring's residuals are the bark, laid at the ring's own
    /// resolution and reconstructed by the B-spline. Age holds the FED
    /// TIME at which a sample first fell inside, so the age of tissue is
    /// `now − Age` — derivable without an ageing operator touching
    /// dormant bricks, which is the only encoding of history G5 allows.
    fn stamp(self: *World, base: *const Snapshot, f: *const Front, dt: f64, envelope: f32, avail: f32, sink: *Sink) !void {
        const p = f.params;
        const now_s: f32 = @floatCast(@as(f64, @floatFromInt(self.time_ns)) / 1e9);
        var rmax: f32 = 0;
        for (f.ring) |sl| rmax = @max(rmax, @abs(sl.r));
        for (f.prev_r) |r| rmax = @max(rmax, @abs(r));
        const soft: f64 = SOFT;
        const band0: f64 = channel.band(@as(u32, 1) << self.policy.default_gauge);
        const reach: f64 = @as(f64, @max(envelope, f.prev_envelope) + rmax) + band0;
        // The collar (P2.2): k where this capsule meets another's deposit —
        // the ring's radius, "the child's radius at the join" — and how far
        // behind its start ring the smooth union could still act on the
        // front's own tube, out to the band's edge (`collarReach`). Within
        // that, own is hard; beyond, own is another front.
        const k_collar: f32 = p.collar * envelope;
        const own_reach: f32 = switch (self.policy.collar_gate) {
            .recent => thresholds.collarReach(k_collar, @as(f32, @floatCast(reach))),
            .none => -1, // nothing is recent enough
            .own => std.math.inf(f32), // everything of its own, at any age
        };
        const who: u32 = f.id + 1; // `channel.whoOf` as an integer: zero is nobody
        const draw_r: f64 = 2.0 * @as(f64, p.radius);
        const draw: f32 = p.consume * @as(f32, @floatCast(dt));
        const depositing = p.deposit > 0 and avail > 0;
        const ext = @max(reach, draw_r);
        var lo: [3]i64 = undefined;
        var hi: [3]i64 = undefined;
        inline for (0..3) |a| {
            lo[a] = @max(@as(i64, 0), tree.floorI(@min(f.pos[a], f.prev_pos[a]) - ext));
            hi[a] = @min(@as(i64, lattice.CELLS), tree.floorI(@max(f.pos[a], f.prev_pos[a]) + ext) + 1);
        }
        const floor = self.floorFor(p);
        const cap = Capsule.of(f, envelope, floor);
        const gpa = self.gpa;

        // Bricks under the box: what covers each default-gauge cube —
        // existing leaves at any gauge, else the cube itself. Deduped.
        var keys = std.AutoArrayHashMapUnmanaged(u64, void){};
        defer keys.deinit(gpa);
        var cover = std.ArrayListUnmanaged(Key){};
        defer cover.deinit(gpa);
        const side: i64 = @as(i64, 1) << (self.policy.default_gauge + lattice.BRICK_LOG2);
        var z = lo[2] - @mod(lo[2], side);
        while (z < hi[2]) : (z += side) {
            var y = lo[1] - @mod(lo[1], side);
            while (y < hi[1]) : (y += side) {
                var x = lo[0] - @mod(lo[0], side);
                while (x < hi[0]) : (x += side) {
                    cover.clearRetainingCapacity();
                    try base.coverCube(Key.ofBrick(self.policy.default_gauge, .{ @intCast(x), @intCast(y), @intCast(z) }), gpa, &cover);
                    for (cover.items) |ck| try keys.put(gpa, ck.raw(), {});
                }
            }
        }
        for (keys.keys()) |raw| {
            const key = Key.fromRaw(raw);
            const ru = try sink.region(key);
            const o = key.origin();
            const sp: i64 = key.spacing();
            const band: f32 = channel.band(key.spacing());
            const alloc = sink.alloc;
            const existing = base.brickAt(key);
            var op: ?*Plane = null;
            var k: u32 = 0;
            while (k < brick.N) : (k += 1) {
                const pz: i64 = @as(i64, o[2]) + @as(i64, k) * sp;
                if (pz < lo[2] or pz >= hi[2]) continue;
                var j: u32 = 0;
                while (j < brick.N) : (j += 1) {
                    const py: i64 = @as(i64, o[1]) + @as(i64, j) * sp;
                    if (py < lo[1] or py >= hi[1]) continue;
                    var i: u32 = 0;
                    while (i < brick.N) : (i += 1) {
                        const px: i64 = @as(i64, o[0]) + @as(i64, i) * sp;
                        if (px < lo[0] or px >= hi[0]) continue;
                        const q = [3]f64{ @floatFromInt(px), @floatFromInt(py), @floatFromInt(pz) };
                        const idx = Brick.index(i, j, k);
                        // The draw-down: the engine's kernel over two radii.
                        if (draw > 0) {
                            const dx = q[0] - f.pos[0];
                            const dy = q[1] - f.pos[1];
                            const dz = q[2] - f.pos[2];
                            const d2 = dx * dx + dy * dy + dz * dz;
                            if (d2 < draw_r * draw_r) {
                                const cur_g: f32 = if (existing) |b| b.get(Channel.growth.bit(), i, j, k) else 0;
                                if (cur_g > 0) {
                                    const qq = 1 - d2 / (draw_r * draw_r);
                                    try ru.add(alloc, Channel.growth.bit(), idx, -@min(cur_g, draw * @as(f32, @floatCast(qq * qq))));
                                }
                            }
                        }
                        if (!depositing) continue;
                        const phi = cap.signed(q);
                        if (phi >= band) continue;
                        if (op == null) op = try ru.surfaceOpFront(alloc, k_collar, who, f.segment, f.prev_s, own_reach);
                        op.?[idx] = @max(phi, -band);
                        if (phi < 0) {
                            const born: f32 = if (existing) |b| b.get(Channel.age.bit(), i, j, k) else 0;
                            const pending: f32 = if (ru.deltas[Channel.age.bit()]) |dp| dp[idx] else 0;
                            if (born == 0 and pending == 0) try ru.add(alloc, Channel.age.bit(), idx, now_s);
                        }
                        // Touched now: the fed second, where the sweep reaches.
                        if (phi < soft) {
                            const ap = try ru.delta(alloc, Channel.activity.bit());
                            ap[idx] = now_s;
                        }
                    }
                }
            }
        }
    }

    /// The thinnest tube a front lays under this world's gauge: its own
    /// `min_radius`, or the survival floor (G13).
    pub fn floorFor(self: *const World, p: front.Params) f32 {
        return if (p.min_radius > 0) p.min_radius else thresholds.G13_SURVIVE_R_OVER_H * @as(f32, @floatFromInt(@as(u32, 1) << self.policy.default_gauge));
    }

    // ── Bands (R12, P2.2): the ring history read through provenance ────
    //
    // Band 0 is the carrier. Band 1 is the ring morphology — the residual
    // the capsule laid above its envelope, at the sample's chart (s, θ);
    // band 2 the same relief's second difference from ring to ring, the
    // furrow one ring wide that the lattice smooths over. Bands 3+ are
    // procedural, P2.3's. A query names its class: a SPONGE reads band 0
    // and gathers nothing else; BARK reads the provenance and the rings.

    /// The ring record of front `who` at ring `segment`, if the history
    /// holds it (ring zero is the seed).
    pub fn ringAt(self: *const World, who: u32, segment: u32) ?*const front.Ring {
        if (who >= self.rings.items.len) return null;
        const list = self.rings.items[who].items;
        if (segment >= list.len) return null;
        return &list[segment];
    }

    /// The capsule that swept ring `segment` of front `who` — between
    /// that ring and the one before it, at the front's floor — rebuilt
    /// from the history exactly as the front built it.
    pub fn capsuleAt(self: *const World, who: u32, segment: u32) ?Capsule {
        if (segment == 0) return null;
        const a = self.ringAt(who, segment - 1) orelse return null;
        const b = self.ringAt(who, segment) orelse return null;
        if (who >= self.fronts.items.len) return null;
        return Capsule.between(a, b, self.floorFor(self.fronts.items[who].params));
    }

    pub const BandClass = enum { sponge, bark };

    pub const BandSample = struct {
        /// Band 0: the carrier's sample at the point.
        phi: f32,
        /// Band 1: the ring residual at the sample's chart, lattice units
        /// above the envelope — the bark's relief as the capsule laid it.
        /// Null where nobody laid the sample, or the class did not ask.
        band1: ?f32 = null,
        /// Band 2: the relief's second difference along s at the chart's
        /// θ, over the ring and its two neighbours; null at the ends.
        band2: ?f32 = null,
        /// The ring's slot at the chart's θ budded here: a scar.
        scar: bool = false,
        provenance: ?brick.Provenance = null,
        /// Bytes gathered, as G7 counts them: the surface plane's 64
        /// coefficients, then the four provenance samples and the ring
        /// records a bark query reads.
        bytes: u64,
    };

    /// A band query at lattice point `p` for a class (G12 c).
    pub fn bandQuery(self: *const World, snap: *const Snapshot, p: [3]i64, class: BandClass) BandSample {
        var out = BandSample{ .phi = channel.band(1), .bytes = thresholds.G12_SPONGE_BYTES };
        const b = snap.findLeaf(p) orelse return out;
        const l = b.localOf(p) orelse return out;
        out.phi = b.get(Channel.surface.bit(), l[0], l[1], l[2]);
        if (class == .sponge) return out;
        const pv = b.provenanceAt(l[0], l[1], l[2]) orelse return out;
        out.bytes += 2 * @sizeOf(f32);
        out.provenance = pv;
        const cap = self.capsuleAt(pv.who, pv.segment) orelse return out;
        out.bytes += 2 * @sizeOf(front.Ring);
        // The chart at the point: the capsule's foot there, exactly.
        const ft = cap.foot(.{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) });
        const t: f32 = @floatCast(@min(1, @max(0, ft.s_raw)));
        const th: f64 = cap.chartTheta(ft);
        const r0 = Capsule.residual(cap.r0, th);
        const r1 = Capsule.residual(cap.r1, th);
        out.band1 = std.math.lerp(r0, r1, @min(1, @max(0, t)));
        const ring = self.ringAt(pv.who, pv.segment).?;
        const slot: usize = @intFromFloat(@mod(th / (2 * std.math.pi) * @as(f64, front.SLOTS) + 0.5, @as(f64, front.SLOTS)));
        if (ring.bud) |bs| out.scar = bs == slot;
        if (self.ringAt(pv.who, pv.segment + 1)) |next| {
            out.bytes += @sizeOf(front.Ring);
            out.band2 = Capsule.residual(next.r, th) - 2 * r1 + r0;
        }
        return out;
    }

    /// The lofted capsule between a front's previous ring and its current
    /// one: the signed implicit ρ − r(s, θ), with r interpolated along the
    /// segment between the two rings' profiles and read around each ring
    /// in its own transported frame. Beyond the ends it is the end ring's
    /// cap. The profile's residual fades to zero on the axis so the
    /// implicit stays Lipschitz there (θ is not defined on the axis).
    /// Built from the front as it sweeps (`of`), or from two ring records
    /// of the history (`between`) — the same fields, the same arithmetic,
    /// so G12 (b) reads a deposit back from its provenance bit for bit.
    pub const Capsule = struct {
        p0: [3]f64,
        p1: [3]f64,
        axis: [3]f64,
        len2: f64,
        s0: f64,
        s1: f64,
        n0: [3]f64,
        b0: [3]f64,
        roll0: f64,
        env0: f32,
        r0: [front.SLOTS]f32,
        n1: [3]f64,
        b1: [3]f64,
        roll1: f64,
        env1: f32,
        r1: [front.SLOTS]f32,
        /// Nothing thinner than this is laid: the gauge's survival floor.
        floor: f32,

        pub fn of(f: *const Front, envelope: f32, floor: f32) Capsule {
            const r0 = f.prevRing();
            const r1 = f.ringRecord(envelope);
            return between(&r0, &r1, floor);
        }

        pub fn between(a: *const front.Ring, b: *const front.Ring, floor: f32) Capsule {
            const axis = [3]f64{ b.pos[0] - a.pos[0], b.pos[1] - a.pos[1], b.pos[2] - a.pos[2] };
            return .{
                .p0 = a.pos,
                .p1 = b.pos,
                .axis = axis,
                .len2 = dot(axis, axis),
                .s0 = a.s,
                .s1 = b.s,
                .n0 = a.normal,
                .b0 = cross(a.dir, a.normal),
                .roll0 = a.roll,
                .env0 = a.envelope,
                .r0 = a.r,
                .n1 = b.normal,
                .b1 = cross(b.dir, b.normal),
                .roll1 = b.roll,
                .env1 = b.envelope,
                .r1 = b.r,
                .floor = floor,
            };
        }

        /// A point's foot on the capsule: the axis parameter s ∈ [0, 1]
        /// (the cap beyond either end reads as the end), its unclamped
        /// value, the radial distance, and the angle in each ring's frame.
        pub const Foot = struct { s: f64, s_raw: f64, rho: f64, th0: f64, th1: f64 };

        pub fn foot(self: *const Capsule, q: [3]f64) Foot {
            const d = [3]f64{ q[0] - self.p0[0], q[1] - self.p0[1], q[2] - self.p0[2] };
            var s_raw: f64 = 0;
            if (self.len2 > 1e-18) s_raw = dot(d, self.axis) / self.len2;
            const s = @min(1.0, @max(0.0, s_raw));
            const rad = [3]f64{ d[0] - s * self.axis[0], d[1] - s * self.axis[1], d[2] - s * self.axis[2] };
            return .{
                .s = s,
                .s_raw = s_raw,
                .rho = len3(rad),
                .th0 = std.math.atan2(dot(rad, self.b0), dot(rad, self.n0)) - self.roll0,
                .th1 = std.math.atan2(dot(rad, self.b1), dot(rad, self.n1)) - self.roll1,
            };
        }

        /// The chart's s at the foot: the front's arc length there — the
        /// UNCLAMPED projection, so a sample in the cap behind a
        /// capsule's start reads the arc it lies beside, not the cap's.
        /// With the clamp, a ring whose bark bulged won samples axially
        /// behind it (its cap nearer than the previous capsule's side)
        /// and gave them its start's s: the chart jumped by up to a ring
        /// along a straight tube, and G16 (a) read 0.15 against 1e-3.
        pub fn chartS(self: *const Capsule, ft: Foot) f32 {
            return @floatCast(self.s0 + ft.s_raw * (self.s1 - self.s0));
        }

        /// The chart's θ at the foot, in [0, 2π): the two rings' angles
        /// lerped the short way round — by the UNCLAMPED parameter, as s
        /// is, so a sample in the cap behind the start reads the roll of
        /// the arc it lies beside (clamped, the far side of a straight
        /// tube read θ 0.0185 off: drift × a ring behind) — so a frame
        /// twisting between rings gives a continuous chart along the
        /// capsule, and across a bend the twist is extrapolated a step.
        pub fn chartTheta(_: *const Capsule, ft: Foot) f32 {
            const two_pi = 2 * std.math.pi;
            var dth = @mod(ft.th1 - ft.th0, two_pi);
            if (dth > std.math.pi) dth -= two_pi;
            const th = @mod(ft.th0 + ft.s_raw * dth, two_pi);
            return @floatCast(th);
        }

        /// The profile's residual at angle θ (radians about the ring's
        /// frame): the ring's 24 slots, linearly interpolated.
        pub fn residual(rs: [front.SLOTS]f32, theta: f64) f32 {
            const N: f64 = front.SLOTS;
            var u = @mod(theta, 2 * std.math.pi) / (2 * std.math.pi) * N;
            if (u >= N) u -= N;
            const slot0: usize = @intFromFloat(@floor(u));
            const fr: f32 = @floatCast(u - @floor(u));
            const a = rs[slot0 % front.SLOTS];
            const b = rs[(slot0 + 1) % front.SLOTS];
            return std.math.lerp(a, b, fr);
        }

        pub fn signed(self: *const Capsule, q: [3]f64) f32 {
            return self.signedAt(self.foot(q));
        }

        pub fn signedAt(self: *const Capsule, ft: Foot) f32 {
            const s = ft.s;
            const rho = ft.rho;
            const env: f32 = std.math.lerp(self.env0, self.env1, @as(f32, @floatCast(s)));
            const res: f32 = std.math.lerp(residual(self.r0, ft.th0), residual(self.r1, ft.th1), @as(f32, @floatCast(s)));
            // The residual fades to nothing on the axis.
            const fade: f32 = @floatCast(@min(1.0, rho / @max(0.5 * @as(f64, env), 1e-6)));
            const r: f32 = @max(self.floor, env + res * fade);
            return @as(f32, @floatCast(rho)) - r;
        }

        /// The ring residual at the foot: band 1's value at a sample the
        /// capsule laid (what its radius carried above the envelope).
        pub fn residualAt(self: *const Capsule, ft: Foot) f32 {
            return std.math.lerp(residual(self.r0, ft.th0), residual(self.r1, ft.th1), @as(f32, @floatCast(ft.s)));
        }
    };

    /// 1 at or below `one`, 0 at or above `zero`, smooth between.
    fn smooth(zero: f64, one: f64, x: f64) f64 {
        if (x >= zero) return 0;
        if (x <= one) return 1;
        const t = (zero - x) / (zero - one);
        return t * t * (3 - 2 * t);
    }

    // ── Commit (R3) ──────────────────────────────────────────────────────

    const Changed = struct {
        b: *Brick,
        old: ?*const Brick,
        /// The largest change in lattice value units: the active-set floor.
        max_delta: f32 = 0,
        /// The largest change per channel, each over its `attentionScale`,
        /// the max taken across channels: the brick's attention (R15).
        attention: f32 = 0,
        materialised: bool = false,
        /// Seam precedence among equal gauges: 0 wrote deltas this
        /// commit, 1 was cloned by the seam pass or is unchanged, 2 was
        /// materialised empty. Lower wins. A tie on key alone once
        /// copied a new neighbour's zero over the point mass it was
        /// meant to receive.
        rank: u8 = 1,
        /// P2.2's standing numbers for this brick's commit.
        collared: u32 = 0,
        provenance: u32 = 0,
    };

    const ApplyCtx = struct {
        world: *World,
        base: *const Snapshot,
        entries: []*update.RegionUpdate,
        results: []?Changed,
        failed: std.atomic.Value(bool),
    };

    fn applyEntry(ctx: *ApplyCtx, i: usize) void {
        const ru = ctx.entries[i];
        ctx.results[i] = null;
        if (ru.mask == 0 and !ru.materialise) return;
        const gpa = ctx.world.gpa;
        const old = ctx.base.brickAt(ru.key);
        const nb = (if (old) |o| Brick.clone(gpa, o) else Brick.create(gpa, ru.key)) catch {
            ctx.failed.store(true, .release);
            return;
        };
        nb.version = if (old) |o| o.version + 1 else 1;
        var max_delta: f32 = 0;
        var att: f32 = 0;
        const nbd = nb.band();
        var bit: u6 = 0;
        while (true) : (bit += 1) {
            if (ru.deltas[bit]) |dp| {
                const clamp = ctx.world.registry.clamp(bit);
                const scale = channel.attentionScale(bit, clamp, nbd);
                var bit_delta: f32 = 0;
                const pl = nb.ensurePlane(gpa, bit) catch {
                    nb.release(gpa);
                    ctx.failed.store(true, .release);
                    return;
                };
                // The brick's own samples only: the halo is the neighbours'
                // and the halo pass rewrites it after the seams.
                var k: u32 = 0;
                while (k < brick.N) : (k += 1) {
                    var j: u32 = 0;
                    while (j < brick.N) : (j += 1) {
                        var ii: u32 = 0;
                        while (ii < brick.N) : (ii += 1) {
                            const idx = Brick.index(ii, j, k);
                            const d = dp[idx];
                            const nv = switch (channel.rule(bit)) {
                                .touch => if (d != 0) clamp.apply(d) else pl[idx],
                                else => clamp.apply(pl[idx] + d),
                            };
                            bit_delta = @max(bit_delta, @abs(nv - pl[idx]));
                            pl[idx] = nv;
                        }
                    }
                }
                max_delta = @max(max_delta, bit_delta);
                att = @max(att, bit_delta / scale);
            }
            if (bit == 63) break;
        }
        var collared: u32 = 0;
        var prov: u32 = 0;
        if (ru.surface_ops.items.len > 0) {
            // The carrier: ops in order (front id, or authoring order),
            // each into the TWO SLOTS, band 0 their one smooth union held
            // to the band. Stable, so equal orders keep insertion order.
            std.sort.insertion(update.SurfaceOp, ru.surface_ops.items, {}, update.SurfaceOp.lessThan);
            const sbit = Channel.surface.bit();
            const pl = nb.ensurePlane(gpa, sbit) catch {
                nb.release(gpa);
                ctx.failed.store(true, .release);
                return;
            };
            var slots: [3]*Plane = undefined; // own, other, collar
            for ([_]Channel{ .own, .other, .collar }, 0..) |ch, n| {
                slots[n] = nb.ensurePlane(gpa, ch.bit()) catch {
                    nb.release(gpa);
                    ctx.failed.store(true, .release);
                    return;
                };
            }
            const bd = nb.band();
            const sscale = channel.attentionScale(sbit, ctx.world.registry.clamp(sbit), bd);
            var sdelta: f32 = 0;
            // The provenance planes, made once a front's op is here: read
            // for the collar's recency, written where the op wins (P2.2).
            var pv: ?[2]*Plane = null;
            for (ru.surface_ops.items) |op| {
                if (pv == null and (op.who != 0 or nb.has(Channel.who.bit()))) {
                    var planes: [2]*Plane = undefined;
                    for ([_]Channel{ .who, .segment }, 0..) |ch, n| {
                        planes[n] = nb.ensurePlane(gpa, ch.bit()) catch {
                            nb.release(gpa);
                            ctx.failed.store(true, .release);
                            return;
                        };
                    }
                    pv = planes;
                }
                const who_f: f32 = @floatFromInt(op.who);
                const seg_f: f32 = @floatFromInt(op.segment);
                // The front's ring arcs: a sample's `segment` names its
                // capsule, and the capsule's end arc against the op's
                // start is the window (Christian's count of segments,
                // read off the arcs so it survives a change of dt).
                const arcs: []const front.Ring = if (op.who != 0 and op.who - 1 < ctx.world.rings.items.len) ctx.world.rings.items[op.who - 1].items else &.{};
                const s0: f32 = @floatCast(op.s0);
                var k: u32 = 0;
                while (k < brick.N) : (k += 1) {
                    var j: u32 = 0;
                    while (j < brick.N) : (j += 1) {
                        var ii: u32 = 0;
                        while (ii < brick.N) : (ii += 1) {
                            const idx = Brick.index(ii, j, k);
                            const d = op.plane[idx];
                            if (d == update.SurfaceOp.NONE) continue;
                            const cur = pl[idx];
                            var own = slots[0][idx];
                            var other = slots[1][idx];
                            var kj = slots[2][idx];
                            var nv: f32 = undefined;
                            switch (op.mode) {
                                .join => {
                                    const dd = @max(d, -bd);
                                    // Whose is the sample? Its own front's,
                                    // within the collar's reach: hard into
                                    // `own`. Anyone else's — another front,
                                    // authored tissue, its own beyond the
                                    // reach — a nearer one takes `own` and
                                    // demotes what stood; a farther one
                                    // joins `other` by the hard min, so a
                                    // chain of capsules is one tube there.
                                    var mine = false;
                                    if (op.who != 0 and pv.?[0][idx] == who_f) {
                                        const seg: usize = @intFromFloat(@max(0, pv.?[1][idx]));
                                        if (seg < arcs.len) {
                                            const s_end: f32 = @floatCast(arcs[seg].s);
                                            if (s0 - s_end <= op.reach) mine = true;
                                        }
                                    }
                                    const first = own >= bd and other >= bd;
                                    if (mine) {
                                        if (dd < own) {
                                            own = dd;
                                            pv.?[1][idx] = seg_f;
                                            prov += 1;
                                        }
                                    } else if (dd < own) {
                                        other = own;
                                        own = dd;
                                        if (pv) |p2| {
                                            p2[0][idx] = who_f;
                                            p2[1][idx] = seg_f;
                                        }
                                        if (op.who != 0) prov += 1;
                                    } else {
                                        other = @min(other, dd);
                                    }
                                    // The join's collar: the least willing
                                    // member's — a child's radius at the
                                    // join is the smaller of the two.
                                    kj = if (first) op.k else @min(kj, op.k);
                                    nv = channel.smin(own, other, kj, bd);
                                    if (kj > 0 and nv < @min(own, other)) collared += 1;
                                },
                                // A cut writes no provenance: the scar
                                // remembers. It cuts the slots too, so a
                                // later join recomposes from cut tissue.
                                .cut => {
                                    nv = @max(cur, -d);
                                    own = @max(own, -d);
                                    other = @max(other, -d);
                                },
                            }
                            nv = @max(-bd, @min(bd, nv));
                            slots[0][idx] = @min(own, bd);
                            slots[1][idx] = @min(other, bd);
                            slots[2][idx] = kj;
                            sdelta = @max(sdelta, @abs(nv - cur));
                            pl[idx] = nv;
                        }
                    }
                }
            }
            max_delta = @max(max_delta, sdelta);
            att = @max(att, sdelta / sscale);
        }
        ctx.results[i] = .{ .b = nb, .old = old, .max_delta = max_delta, .attention = att, .materialised = old == null and ru.mask == 0, .rank = if (ru.mask != 0) 0 else 2, .collared = collared, .provenance = prov };
    }

    const FinalizeCtx = struct { world: *World, base: *const Snapshot, changed: *std.AutoHashMapUnmanaged(u64, Changed), order: []const u64, now_ns: u64, head: []const Key, hash_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0) };

    /// The attention bookkeeping is written here and nowhere else (R15):
    /// the largest change that reached the brick this commit — its own
    /// deltas and ops, a seam or halo write — per channel over that
    /// channel's range, the max across channels, and the commit's fed
    /// time. A brick still OWED — active in the base and not evaluated
    /// this step — accumulates by max: the earlier change is still
    /// pending (R17). Any other starts afresh: evaluated this step, or
    /// settled and re-entering (a settled brick is never cloned, so the
    /// attention it carries is the pending it had when last looked at,
    /// stale — accumulating it once made a re-entering brick owe twice).
    fn finalizeOne(ctx: *FinalizeCtx, i: usize) void {
        const c = ctx.changed.get(ctx.order[i]).?;
        const owed = ctx.base.sinceOf(c.b.key) != null and !keyInSorted(ctx.head, c.b.key);
        c.b.attention = if (owed) @max(c.b.attention, c.attention) else c.attention;
        c.b.changed_ns = ctx.now_ns;
        c.b.finalize(ctx.world.gpa);
        _ = ctx.hash_ns.fetchAdd(c.b.last_hash_ns, .monotonic);
    }

    fn dedupKeys(gpa: std.mem.Allocator, sorted: []const Key) ![]Key {
        var out = std.ArrayListUnmanaged(Key){};
        errdefer out.deinit(gpa);
        for (sorted, 0..) |k, i| {
            if (i > 0 and sorted[i - 1].eql(k)) continue;
            try out.append(gpa, k);
        }
        return out.toOwnedSlice(gpa);
    }

    /// The neighbour cubes, at `b`'s own gauge, across every face of `b`
    /// that carries a value reaching across it and has nothing there yet.
    fn frontierRequests(self: *World, view: *const Snapshot, b: *const Brick, out: *std.ArrayListUnmanaged(Key)) !void {
        const eps = thresholds.EPSILON;
        const bd = b.band();
        const o = b.origin();
        const side: i64 = b.key.side();
        // Six faces: axis, and which end.
        var axis: usize = 0;
        while (axis < 3) : (axis += 1) {
            var end: u32 = 0;
            while (end < 2) : (end += 1) {
                const face: u32 = if (end == 0) 0 else brick.CELLS;
                var hot = false;
                var bit: u6 = 0;
                while (!hot) : (bit += 1) {
                    if (b.plane(bit)) |pl| {
                        var u: u32 = 0;
                        while (u < brick.N and !hot) : (u += 1) {
                            var v: u32 = 0;
                            while (v < brick.N) : (v += 1) {
                                const ijk = faceIndex(axis, face, u, v);
                                // Above the floor, or nearer than the band: the
                                // field reaches across, so the neighbour must exist
                                // to carry it (and the halo needs it to be C2).
                                if (channel.reaches(bit, pl[Brick.index(ijk[0], ijk[1], ijk[2])], bd, eps)) {
                                    hot = true;
                                    break;
                                }
                            }
                        }
                    }
                    if (bit == 63) break;
                }
                if (!hot) continue;
                var probe = [3]i64{ o[0], o[1], o[2] };
                probe[axis] += if (end == 0) -1 else side + 1;
                inline for (0..3) |a| if (a != axis) {
                    probe[a] += @divExact(side, 2);
                };
                if (probe[axis] < 0 or probe[axis] > lattice.CELLS) continue;
                var no: [3]u32 = o;
                if (end == 0) no[axis] -= @intCast(side) else no[axis] += @intCast(side);
                const nk = Key.ofBrick(b.gauge(), no);
                // Anything already there — a leaf at any gauge covering
                // the cube, or finer leaves inside it — shares the face
                // through the seam pass; only the void is materialised.
                if (view.nodeAt(nk) != null) continue;
                try out.append(self.gpa, nk);
            }
        }
    }

    /// Create the requested cubes, finest gauge first. A request is
    /// resolved through `coverCube` against a view that already holds
    /// what finer requests created, so a coarse cube partly filled by
    /// them is completed at their gauge.
    fn materialiseRequests(self: *World, base: *const Snapshot, pre: *const Snapshot, requests: []Key, changed: *std.AutoHashMapUnmanaged(u64, Changed), order: *std.ArrayListUnmanaged(u64)) !void {
        const gpa = self.gpa;
        if (requests.len == 0) return;
        std.mem.sort(Key, requests, {}, struct {
            fn lt(_: void, a: Key, b: Key) bool {
                if (a.level != b.level) return a.level < b.level;
                return a.raw() < b.raw();
            }
        }.lt);
        var created = std.ArrayListUnmanaged(tree.Override){};
        defer created.deinit(gpa);
        var view_root: ?*tree.Node = pre.root;
        var view_owned = false;
        defer if (view_owned) if (view_root) |r| r.release(gpa);
        var cover = std.ArrayListUnmanaged(Key){};
        defer cover.deinit(gpa);
        var i: usize = 0;
        while (i < requests.len) {
            const level = requests[i].level;
            // A view holding everything created at finer levels.
            if (created.items.len > 0) {
                for (created.items) |*c| c.brick = changed.get(c.key.raw()).?.b;
                std.mem.sort(tree.Override, created.items, {}, tree.Override.lessThan);
                const root = try tree.build(gpa, pre.root, created.items);
                if (view_owned) if (view_root) |r| r.release(gpa);
                view_root = root;
                view_owned = true;
            }
            const view = Snapshot{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = view_root };
            const first = created.items.len;
            while (i < requests.len and requests[i].level == level) : (i += 1) {
                const rk = requests[i];
                if (i > 0 and requests[i - 1].eql(rk)) continue;
                cover.clearRetainingCapacity();
                try view.coverCube(rk, gpa, &cover);
                for (cover.items) |ck| {
                    if (view.brickAt(ck) != null) continue; // a leaf already there
                    if (changed.contains(ck.raw())) continue;
                    const nb = try Brick.create(gpa, ck);
                    nb.version = 1;
                    try changed.put(gpa, ck.raw(), .{ .b = nb, .old = null, .materialised = true, .rank = 2 });
                    try order.append(gpa, ck.raw());
                    try created.append(gpa, .{ .key = ck, .brick = nb });
                }
            }
            _ = first;
        }
        _ = base;
    }

    fn faceIndex(axis: usize, face: u32, u: u32, v: u32) [3]u32 {
        return switch (axis) {
            0 => .{ face, u, v },
            1 => .{ u, face, v },
            else => .{ u, v, face },
        };
    }

    // ── Seams ────────────────────────────────────────────────────────────
    //
    // Collect, then apply. Phase A runs over the changed bricks in
    // parallel and only READS: for every shared point on a changed brick's
    // surface it works out which holder must take which value and emits a
    // write when the holder's current value differs. Phase B sorts the
    // writes by (key, bit, idx), drops duplicates — the same point seen
    // from two changed bricks yields the same value, which is asserted —
    // and applies them in key order, cloning an untouched neighbour on
    // its first write. The schedule cannot reach the result: the write
    // SET is what the geometry says, and the order is the sort's.

    pub const Live = struct { b: *const Brick, rank: u8 };

    pub const ChangedMap = std.AutoHashMapUnmanaged(u64, Changed);

    /// The live (this-commit) version of a brick the view found.
    fn liveOf(changed: *const ChangedMap, b: *const Brick) Live {
        if (changed.get(b.key.raw())) |c| return .{ .b = c.b, .rank = c.rank };
        return .{ .b = b, .rank = 1 };
    }

    /// `a` outranks `b` as the source of a shared point: finer, then
    /// lower rank, then lower key.
    pub fn outranks(a: Live, b: Live) bool {
        if (a.b.key.level != b.b.key.level) return a.b.key.level < b.b.key.level;
        if (a.rank != b.rank) return a.rank < b.rank;
        return a.b.key.raw() < b.b.key.raw();
    }

    /// One seam write: this holder's sample takes this value.
    pub const SeamWrite = struct {
        key: u64,
        bit: u8,
        idx: u16,
        value: f32,

        fn lessThan(_: void, a: SeamWrite, b: SeamWrite) bool {
            if (a.key != b.key) return a.key < b.key;
            if (a.bit != b.bit) return a.bit < b.bit;
            return a.idx < b.idx;
        }
    };

    pub const WriteList = std.ArrayListUnmanaged(SeamWrite);

    /// Emit a write for `target` at `idx` unless it already holds `v`.
    fn emit(gpa: std.mem.Allocator, list: *WriteList, target: *const Brick, bit: u6, idx: usize, v_in: f32) !void {
        const have: f32 = if (target.plane(bit)) |pl| pl[idx] else target.absentValue(bit);
        // A coarser holder's band is wider: far is far, at this brick's band.
        const v = if (channel.isDistance(bit)) @min(v_in, target.band()) else v_in;
        if (have == v) return;
        try list.append(gpa, .{ .key = target.key.raw(), .bit = bit, .idx = @intCast(idx), .value = v });
    }

    /// Copy `src`'s sample `sidx` into `target`'s `idx` for every channel
    /// either has.
    fn emitCopy(gpa: std.mem.Allocator, list: *WriteList, target: *const Brick, idx: usize, src: *const Brick, sidx: usize) !void {
        var mask = target.mask | src.mask;
        while (mask != 0) {
            const bit: u6 = @intCast(@ctz(mask));
            mask &= mask - 1;
            const v: f32 = if (src.plane(bit)) |pl| pl[sidx] else src.absentValue(bit);
            try emit(gpa, list, target, bit, idx, v);
        }
    }

    /// Set `target`'s `idx` to `src`'s reconstruction at `q`.
    fn emitInterp(gpa: std.mem.Allocator, list: *WriteList, target: *const Brick, idx: usize, src: *const Brick, q: [3]f64) !void {
        var mask = target.mask | src.mask;
        while (mask != 0) {
            const bit: u6 = @intCast(@ctz(mask));
            mask &= mask - 1;
            // Provenance is not interpolated: an id between two ids is a
            // third front. The nearer coarse sample's stands.
            const v = if (channel.rule(bit) == .set_by_winner) src.nearest(bit, q) else src.trilinear(bit, q);
            try emit(gpa, list, target, bit, idx, v);
        }
    }

    /// The 26 cubes around a brick at its own level, resolved once: what
    /// leaf (same gauge or coarser) or leaves (finer) each holds. Every
    /// boundary point then finds its holders by key comparison instead of
    /// a tree descent — 26 descents per changed brick instead of 386×2.
    /// Instrumentation: nanoseconds spent building neighbourhoods, and
    /// how many were built — the step-cost beat's question.
    pub var nb_build_ns = std.atomic.Value(u64).init(0);
    pub var nb_builds = std.atomic.Value(u64).init(0);

    pub const Neighbourhood = struct {
        cells: [27]struct { start: u32, len: u32 },
        /// Resolved through `liveOf` once, so a point costs no lookups.
        leaves: std.ArrayListUnmanaged(Live) = .{},
        /// The view's brick behind each leaf, so a cached neighbourhood
        /// can be re-resolved after a pass clones a neighbour (`refresh`).
        origin: std.ArrayListUnmanaged(*const Brick) = .{},
        raw: std.ArrayListUnmanaged(*const Brick) = .{},

        pub fn cellIndex(dx: i64, dy: i64, dz: i64) usize {
            return @intCast((dx + 1) + 3 * (dy + 1) + 9 * (dz + 1));
        }

        pub fn build(gpa: std.mem.Allocator, changed: *const ChangedMap, view: *const Snapshot, b: *const Brick) !Neighbourhood {
            var timer = std.time.Timer.start() catch unreachable;
            defer {
                _ = nb_build_ns.fetchAdd(timer.read(), .monotonic);
                _ = nb_builds.fetchAdd(1, .monotonic);
            }
            var nb = Neighbourhood{ .cells = undefined };
            errdefer nb.leaves.deinit(gpa);
            errdefer nb.origin.deinit(gpa);
            errdefer nb.raw.deinit(gpa);
            const o = b.origin();
            const side: i64 = b.key.side();
            var dz: i64 = -1;
            while (dz <= 1) : (dz += 1) {
                var dy: i64 = -1;
                while (dy <= 1) : (dy += 1) {
                    var dx: i64 = -1;
                    while (dx <= 1) : (dx += 1) {
                        const ci = cellIndex(dx, dy, dz);
                        const start: u32 = @intCast(nb.leaves.items.len);
                        nb.cells[ci] = .{ .start = start, .len = 0 };
                        if (dx == 0 and dy == 0 and dz == 0) continue;
                        const nx = @as(i64, o[0]) + dx * side;
                        const ny = @as(i64, o[1]) + dy * side;
                        const nz = @as(i64, o[2]) + dz * side;
                        if (nx < 0 or ny < 0 or nz < 0 or nx >= lattice.CELLS or ny >= lattice.CELLS or nz >= lattice.CELLS) continue;
                        const nk = Key.init(b.key.level, .{ @intCast(nx), @intCast(ny), @intCast(nz) });
                        const nn = view.nodeAt(nk) orelse continue;
                        nb.raw.clearRetainingCapacity();
                        try Snapshot.leavesUnder(nn, gpa, &nb.raw);
                        for (nb.raw.items) |h| {
                            try nb.leaves.append(gpa, liveOf(changed, h));
                            try nb.origin.append(gpa, h);
                        }
                        nb.cells[ci].len = @intCast(nb.leaves.items.len - start);
                    }
                }
            }
            return nb;
        }

        pub fn deinit(self: *Neighbourhood, gpa: std.mem.Allocator) void {
            self.leaves.deinit(gpa);
            self.origin.deinit(gpa);
            self.raw.deinit(gpa);
        }

        /// Re-resolve every leaf through `liveOf`: a neighbour the last
        /// apply pass cloned is read as its clone from now on. The cells
        /// and the view bricks do not move between passes — the scratch
        /// tree is built once — so a neighbourhood is built once per
        /// commit and refreshed twice (the seam pass's second walk and the
        /// halo pass), where it was built three times.
        pub fn refresh(self: *Neighbourhood, changed: *const ChangedMap) void {
            for (self.leaves.items, self.origin.items) |*l, h| l.* = liveOf(changed, h);
        }

        /// Every leaf whose closed cube holds surface point `p` of `b`,
        /// `b` first. `p` must lie on `b`'s surface.
        fn holders(self: *const Neighbourhood, b: Live, p: [3]i64, out: *[8]Live) usize {
            const o = b.b.origin();
            const side: i64 = b.b.key.side();
            var d: [3]i64 = undefined;
            inline for (0..3) |a| {
                d[a] = if (p[a] == o[a]) -1 else if (p[a] == @as(i64, o[a]) + side) 1 else 0;
            }
            out[0] = b;
            var n: usize = 1;
            var dz: i64 = 0;
            while (true) {
                var dy: i64 = 0;
                while (true) {
                    var dx: i64 = 0;
                    while (true) {
                        if (!(dx == 0 and dy == 0 and dz == 0)) {
                            const c = self.cells[cellIndex(dx, dy, dz)];
                            for (self.leaves.items[c.start .. c.start + c.len]) |h| {
                                if (!h.b.key.holdsPoint(p)) continue;
                                var dup = false;
                                for (out[0..n]) |x| if (x.b == h.b) {
                                    dup = true;
                                };
                                if (!dup and n < 8) {
                                    out[n] = h;
                                    n += 1;
                                }
                            }
                        }
                        if (dx == d[0]) break;
                        dx = d[0];
                    }
                    if (dy == d[1]) break;
                    dy = d[1];
                }
                if (dz == d[2]) break;
                dz = d[2];
            }
            return n;
        }

        /// Finer leaves around `b`: their boundary points on `b`'s surface
        /// are the hanging points the coarse face governs.
        fn finerLeaves(self: *const Neighbourhood, b: *const Brick, gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(*const Brick)) !void {
            for (self.leaves.items) |h| {
                if (h.b.key.level >= b.key.level) continue;
                var dup = false;
                for (out.items) |x| if (x == h.b) {
                    dup = true;
                };
                if (!dup) try out.append(gpa, h.b);
            }
        }
    };

    /// One shared point: the anchor (pass 1) or hang (pass 2) writes for
    /// every holder, emitted.
    fn seamPoint(gpa: std.mem.Allocator, list: *WriteList, pass: u8, hs: []const Live, p: [3]i64) !void {
        var finest: Live = hs[0];
        var coarsest: *const Brick = hs[0].b;
        for (hs[1..]) |h| {
            if (outranks(h, finest)) finest = h;
            if (h.b.key.level > coarsest.key.level or (h.b.key.level == coarsest.key.level and h.b.key.raw() < coarsest.key.raw())) coarsest = h.b;
        }
        if (pass == 1) {
            const fl = finest.b.localOf(p) orelse unreachable;
            const sidx = Brick.index(fl[0], fl[1], fl[2]);
            for (hs) |h| {
                if (h.b == finest.b) continue;
                const l = h.b.localOf(p) orelse continue; // not on h's lattice: a hanging point, pass 2's
                try emitCopy(gpa, list, h.b, Brick.index(l[0], l[1], l[2]), finest.b, sidx);
            }
        } else {
            if (coarsest.localOf(p) != null) return; // on the coarse lattice: anchored
            const q = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
            for (hs) |h| {
                if (h.b == coarsest) continue;
                const l = h.b.localOf(p) orelse continue;
                try emitInterp(gpa, list, h.b, Brick.index(l[0], l[1], l[2]), coarsest, q);
            }
        }
    }

    const CollectCtx = struct {
        world: *World,
        view: *const Snapshot,
        changed: *const ChangedMap,
        order: []const u64,
        pass: u8,
        chunk: u32,
        /// One list per job chunk: `order[i]` writes into `lists[i / chunk]`,
        /// and a chunk runs on one thread.
        lists: []WriteList,
        /// The commit's neighbourhood cache, one slot per brick of `order`;
        /// a slot is written only by the job that owns its index.
        nbs: []?Neighbourhood,
        failed: std.atomic.Value(bool),
    };

    /// Phase A for one changed brick: its own boundary points, and the
    /// hanging points of finer neighbours on its surface.
    fn collectOne(ctx: *CollectCtx, i: usize) void {
        collectBrick(ctx, i) catch {
            ctx.failed.store(true, .release);
        };
    }

    fn collectBrick(ctx: *CollectCtx, i: usize) !void {
        const gpa = ctx.world.gpa;
        const list = &ctx.lists[i / ctx.chunk];
        const c = ctx.changed.get(ctx.order[i]).?;
        const b = c.b;
        const bl = Live{ .b = b, .rank = c.rank };
        if (ctx.nbs[i] == null) ctx.nbs[i] = try Neighbourhood.build(gpa, ctx.changed, ctx.view, b);
        const nb: *const Neighbourhood = &ctx.nbs[i].?;
        var hs: [8]Live = undefined;
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var ii: u32 = 0;
                while (ii < brick.N) : (ii += 1) {
                    if (!Brick.isBoundary(ii, j, k)) continue;
                    const p = b.pointAt(ii, j, k);
                    const pi = [3]i64{ p[0], p[1], p[2] };
                    const n = nb.holders(bl, pi, &hs);
                    if (n <= 1) continue;
                    try seamPoint(gpa, list, ctx.pass, hs[0..n], pi);
                }
            }
        }
        var finer = std.ArrayListUnmanaged(*const Brick){};
        defer finer.deinit(gpa);
        try nb.finerLeaves(b, gpa, &finer);
        for (finer.items) |h| {
            var hk: u32 = 0;
            while (hk < brick.N) : (hk += 1) {
                var hj: u32 = 0;
                while (hj < brick.N) : (hj += 1) {
                    var hi: u32 = 0;
                    while (hi < brick.N) : (hi += 1) {
                        if (!Brick.isBoundary(hi, hj, hk)) continue;
                        const p = h.pointAt(hi, hj, hk);
                        const pi = [3]i64{ p[0], p[1], p[2] };
                        if (!b.key.holdsPoint(pi)) continue;
                        if (b.localOf(pi) != null) continue; // one of b's own points: done above
                        const n = nb.holders(bl, pi, &hs);
                        if (n <= 1) continue;
                        try seamPoint(gpa, list, ctx.pass, hs[0..n], pi);
                    }
                }
            }
        }
    }

    /// Phase B: the writes, in key order, deduplicated, applied through
    /// clone-on-write. Serial: this is where `changed` and `order` grow.
    /// Apply sorted writes to their target bricks — cloning a target the
    /// commit has not touched — from `cursor`, at most `max` targets. A
    /// unit is a target brick (R16). Returns how many were applied.
    fn applyWriteGroups(self: *World, view: *const Snapshot, changed: *ChangedMap, order: *std.ArrayListUnmanaged(u64), all: []const SeamWrite, cursor: *usize, max: u64) !u64 {
        const gpa = self.gpa;
        var done: u64 = 0;
        var i: usize = cursor.*;
        while (i < all.len and done < max) {
            const key = all[i].key;
            const b0: *const Brick = if (changed.get(key)) |c| c.b else (view.brickAt(Key.fromRaw(key)) orelse unreachable);
            const mb: *Brick = blk: {
                if (changed.get(key)) |c| break :blk c.b;
                const nb = try Brick.clone(gpa, b0);
                nb.version = b0.version + 1;
                try changed.put(gpa, key, .{ .b = nb, .old = b0 });
                try order.append(gpa, key);
                self.stats.seam_bricks += 1;
                break :blk nb;
            };
            var max_delta: f32 = 0;
            var att: f32 = 0;
            const mbd = mb.band();
            var last: ?SeamWrite = null;
            while (i < all.len and all[i].key == key) : (i += 1) {
                const w = all[i];
                if (last) |l| if (l.bit == w.bit and l.idx == w.idx) {
                    // The same point from two changed bricks' perspectives:
                    // the same holders, so the same value. Anything else
                    // is a broken contract, not a tie to resolve.
                    std.debug.assert(l.value == w.value);
                    continue;
                };
                last = w;
                const wbit: u6 = @intCast(w.bit);
                const pl = try mb.ensurePlane(gpa, wbit);
                const have = pl[w.idx];
                pl[w.idx] = w.value;
                // The change floor and attention count what the world
                // reads — the carrier and the additive channels. The
                // slots and the provenance are the carrier's bookkeeping,
                // scored where the carrier is: a copied `who` of six
                // once woke every neighbour of a tube for nothing (G14 c's
                // budgeted run evaluated more than the unbudgeted one).
                const rule = channel.rule(wbit);
                if (rule != .set_by_winner and rule != .distance) {
                    const d = @abs(w.value - have);
                    max_delta = @max(max_delta, d);
                    att = @max(att, d / channel.attentionScale(wbit, self.registry.clamp(wbit), mbd));
                }
                self.stats.seam_writes += 1;
            }
            const cptr = changed.getPtr(key).?;
            cptr.max_delta = @max(cptr.max_delta, max_delta);
            cptr.attention = @max(cptr.attention, att);
            done += 1;
        }
        cursor.* = i;
        return done;
    }
};

// ── The halo pass (R7) ───────────────────────────────────────────────────
//
// Collect, then apply, like the seams. For every changed brick B: every
// halo entry of B is recomputed from the holders of its point; and every
// halo entry of a NEIGHBOUR that lies inside B's closed cube is recomputed
// too, since it mirrors B's layer 1. A write is emitted only when the
// value differs, so an untouched neighbour whose halo did not move stays
// the same pointer (G4 checks identity). The value rule is the anchor's,
// one layer deeper: the finest holder's sample where the point is on its
// lattice, else its interpolant; the absent value where nothing holds it.

const HaloCtx = struct {
    world: *World,
    view: *const Snapshot,
    changed: *const World.ChangedMap,
    order: []const u64,
    chunk: u32,
    lists: []World.WriteList,
    /// The seam pass's neighbourhoods; a brick the seam pass cloned lies
    /// past their end and builds its own.
    nbs: []?World.Neighbourhood,
    failed: std.atomic.Value(bool),
};

fn haloCollectOne(ctx: *HaloCtx, i: usize) void {
    haloCollectBrick(ctx, i) catch {
        ctx.failed.store(true, .release);
    };
}

/// The holders of any point in or around `b`, through the neighbourhood
/// cache: `b` itself when its closed cube holds the point, and every
/// cached leaf whose cube does.
fn holdersAround(nb: *const World.Neighbourhood, b: World.Live, p: [3]i64, out: *[8]World.Live) usize {
    var n: usize = 0;
    if (b.b.key.holdsPoint(p)) {
        out[0] = b;
        n = 1;
    }
    const o = b.b.origin();
    const side: i64 = b.b.key.side();
    // Which cells of the 3×3×3 could hold p: strictly outside on a side
    // is that side's cell; on a boundary plane, both cells it separates.
    var cand: [3][2]i64 = undefined;
    var ncand: [3]usize = undefined;
    inline for (0..3) |a| {
        const lo: i64 = o[a];
        const hi: i64 = lo + side;
        if (p[a] < lo) {
            cand[a] = .{ -1, 0 };
            ncand[a] = 1;
        } else if (p[a] == lo) {
            cand[a] = .{ -1, 0 };
            ncand[a] = 2;
        } else if (p[a] < hi) {
            cand[a] = .{ 0, 0 };
            ncand[a] = 1;
        } else if (p[a] == hi) {
            cand[a] = .{ 0, 1 };
            ncand[a] = 2;
        } else {
            cand[a] = .{ 1, 0 };
            ncand[a] = 1;
        }
    }
    var iz: usize = 0;
    while (iz < ncand[2]) : (iz += 1) {
        var iy: usize = 0;
        while (iy < ncand[1]) : (iy += 1) {
            var ix: usize = 0;
            while (ix < ncand[0]) : (ix += 1) {
                const dx = cand[0][ix];
                const dy = cand[1][iy];
                const dz = cand[2][iz];
                if (dx == 0 and dy == 0 and dz == 0) continue;
                const c = nb.cells[World.Neighbourhood.cellIndex(dx, dy, dz)];
                for (nb.leaves.items[c.start .. c.start + c.len]) |h| {
                    if (!h.b.key.holdsPoint(p)) continue;
                    var dup = false;
                    for (out[0..n]) |x| if (x.b == h.b) {
                        dup = true;
                    };
                    if (!dup and n < 8) {
                        out[n] = h;
                        n += 1;
                    }
                }
            }
        }
    }
    return n;
}

/// The value a halo entry of `target` at lattice point `p` must hold for
/// channel `bit`, given the holders of `p`.
fn haloValue(hs: []const World.Live, p: [3]i64, bit: u6, target: *const Brick) f32 {
    const bd = target.band();
    if (hs.len == 0) return channel.absentValue(bit, bd);
    var finest = hs[0];
    for (hs[1..]) |h| if (World.outranks(h, finest)) {
        finest = h;
    };
    var v: f32 = undefined;
    if (finest.b.localOf(p)) |l| {
        v = finest.b.get(bit, l[0], l[1], l[2]);
    } else if (channel.rule(bit) == .set_by_winner) {
        v = finest.b.nearest(bit, .{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) });
    } else {
        v = finest.b.trilinear(bit, .{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) });
    }
    // A coarser holder's band is wider than this brick's: far is far.
    if (channel.isDistance(bit)) v = @min(v, bd);
    return v;
}

fn haloEmit(gpa: std.mem.Allocator, list: *World.WriteList, nb: *const World.Neighbourhood, bl: World.Live, target: *const Brick, hb: [3]u32) !void {
    const p = target.blockPoint(hb);
    var hs: [8]World.Live = undefined;
    const n = if (p[0] < 0 or p[1] < 0 or p[2] < 0 or p[0] > lattice.CELLS or p[1] > lattice.CELLS or p[2] > lattice.CELLS) 0 else holdersAround(nb, bl, p, &hs);
    const idx = Brick.bindex(hb[0], hb[1], hb[2]);
    var mask = target.mask;
    while (mask != 0) {
        const bit: u6 = @intCast(@ctz(mask));
        mask &= mask - 1;
        const v = haloValue(hs[0..n], p, bit, target);
        const have = target.plane(bit).?[idx];
        if (have != v) try list.append(gpa, .{ .key = target.key.raw(), .bit = bit, .idx = @intCast(idx), .value = v });
    }
}

/// Which of B's six face slabs (its own samples within two layers of a
/// face — what any neighbour's halo, at any gauge, is read from) hold a
/// sample that changed this commit, per channel present. A brick with
/// no predecessor is dirty everywhere; a plane the predecessor lacked is
/// dirty everywhere.
const DirtyFaces = struct {
    /// [axis][end]
    face: [3][2]bool,
    /// B's own halo needs recomputing wholesale (new brick, or a plane it
    /// did not have).
    whole: bool,
};

fn dirtyFaces(b: *const Brick, old: ?*const Brick) DirtyFaces {
    var d = DirtyFaces{ .face = .{ .{ false, false }, .{ false, false }, .{ false, false } }, .whole = false };
    const o = old orelse {
        d.face = .{ .{ true, true }, .{ true, true }, .{ true, true } };
        d.whole = true;
        return d;
    };
    var mask = b.mask;
    while (mask != 0) {
        const bit: u6 = @intCast(@ctz(mask));
        mask &= mask - 1;
        const npl = b.plane(bit).?;
        const opl = o.plane(bit) orelse {
            d.face = .{ .{ true, true }, .{ true, true }, .{ true, true } };
            d.whole = true;
            return d;
        };
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const idx = Brick.index(i, j, k);
                    if (npl[idx] == opl[idx]) continue;
                    if (i <= 2) d.face[0][0] = true;
                    if (i >= brick.CELLS - 2) d.face[0][1] = true;
                    if (j <= 2) d.face[1][0] = true;
                    if (j >= brick.CELLS - 2) d.face[1][1] = true;
                    if (k <= 2) d.face[2][0] = true;
                    if (k >= brick.CELLS - 2) d.face[2][1] = true;
                }
            }
        }
    }
    return d;
}

/// Whether a neighbour cell (dx, dy, dz) reads from a dirty slab of B:
/// any of its nonzero directions crosses a dirty face.
fn cellDirty(d: *const DirtyFaces, dx: i64, dy: i64, dz: i64) bool {
    if (dx < 0 and d.face[0][0]) return true;
    if (dx > 0 and d.face[0][1]) return true;
    if (dy < 0 and d.face[1][0]) return true;
    if (dy > 0 and d.face[1][1]) return true;
    if (dz < 0 and d.face[2][0]) return true;
    if (dz > 0 and d.face[2][1]) return true;
    return false;
}

/// Block coordinate ranges of `b`'s halo entries that face the neighbour
/// cell (dx, dy, dz): 0 on the low side, HN−1 on the high side, the
/// interior range in between.
fn haloRange(d: i64) [2]u32 {
    return if (d < 0) .{ 0, 1 } else if (d > 0) .{ brick.HN - 1, brick.HN } else .{ 1, brick.N + 1 };
}

/// Emit `value` for `target`'s halo entry at block `hb` for `bit` unless
/// it already holds it.
fn haloPut(gpa: std.mem.Allocator, list: *World.WriteList, target: *const Brick, bit: u6, hb: [3]u32, v: f32) !void {
    const idx = Brick.bindex(hb[0], hb[1], hb[2]);
    if (target.plane(bit).?[idx] != v) try list.append(gpa, .{ .key = target.key.raw(), .bit = bit, .idx = @intCast(idx), .value = v });
}

fn haloCollectBrick(ctx: *HaloCtx, i: usize) !void {
    const gpa = ctx.world.gpa;
    const list = &ctx.lists[i / ctx.chunk];
    const c = ctx.changed.get(ctx.order[i]).?;
    const b = c.b;
    const bl = World.Live{ .b = b, .rank = c.rank };
    var local: ?World.Neighbourhood = null;
    defer if (local) |*l| l.deinit(gpa);
    const nb: *const World.Neighbourhood = if (i < ctx.nbs.len) blk: {
        if (ctx.nbs[i] == null) ctx.nbs[i] = try World.Neighbourhood.build(gpa, ctx.changed, ctx.view, b);
        break :blk &ctx.nbs[i].?;
    } else blk: {
        local = try World.Neighbourhood.build(gpa, ctx.changed, ctx.view, b);
        break :blk &local.?;
    };
    const dirty = dirtyFaces(b, c.old);
    // B's own halo is recomputed when B is new, gained a plane, or has any
    // changed neighbour at all — per cell would miss an entry on the
    // boundary between cells whose holder sits in the next cell over.
    var any_changed = dirty.whole;
    for (nb.leaves.items) |h| if (ctx.changed.contains(h.b.key.raw())) {
        any_changed = true;
    };
    var dz: i64 = -1;
    while (dz <= 1) : (dz += 1) {
        var dy: i64 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i64 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dx == 0 and dy == 0 and dz == 0) continue;
                const cell = nb.cells[World.Neighbourhood.cellIndex(dx, dy, dz)];
                const leaves = nb.leaves.items[cell.start .. cell.start + cell.len];
                // The neighbour is one brick at B's own gauge: a slab copy,
                // no lookups — it holds every point of the slab, faces
                // included, and agrees with any other holder by the seam
                // contract. Anything else, the VOID included, is the general
                // path: an entry at the edge of a face slab lies on the
                // boundary between cells, and a brick in the next cell may
                // hold it when this cell holds nothing (the diffusion gate's
                // point mass at a brick corner found exactly that).
                const single: ?*const Brick = if (cell.len == 1 and leaves[0].b.key.level == b.key.level) leaves[0].b else null;
                const fast = single != null;
                const rx = haloRange(dx);
                const ry = haloRange(dy);
                const rz = haloRange(dz);
                // (a) B's halo entries facing this cell.
                if (any_changed) {
                    var bk = rz[0];
                    while (bk < rz[1]) : (bk += 1) {
                        var bj = ry[0];
                        while (bj < ry[1]) : (bj += 1) {
                            var bi = rx[0];
                            while (bi < rx[1]) : (bi += 1) {
                                const hb = [3]u32{ bi, bj, bk };
                                if (!fast) {
                                    try haloEmit(gpa, list, nb, bl, b, hb);
                                    continue;
                                }
                                // Same point in the neighbour's block: shifted a brick.
                                const sb = [3]u32{ @intCast(@as(i64, bi) - 8 * dx), @intCast(@as(i64, bj) - 8 * dy), @intCast(@as(i64, bk) - 8 * dz) };
                                var mask = b.mask;
                                while (mask != 0) {
                                    const bit: u6 = @intCast(@ctz(mask));
                                    mask &= mask - 1;
                                    const n = single.?;
                                    const v: f32 = if (n.plane(bit)) |pl| pl[Brick.bindex(sb[0], sb[1], sb[2])] else n.absentValue(bit);
                                    try haloPut(gpa, list, b, bit, hb, v);
                                }
                            }
                        }
                    }
                }
                // (b) The neighbours' halo entries that mirror B's slab facing them.
                if (!cellDirty(&dirty, dx, dy, dz)) continue;
                if (single) |n| {
                    // N's halo entries facing B: the mirror ranges; each maps
                    // to B's block shifted the other way.
                    const nx = haloRange(-dx);
                    const ny = haloRange(-dy);
                    const nz = haloRange(-dz);
                    var nk = nz[0];
                    while (nk < nz[1]) : (nk += 1) {
                        var nj = ny[0];
                        while (nj < ny[1]) : (nj += 1) {
                            var ni = nx[0];
                            while (ni < nx[1]) : (ni += 1) {
                                const sb = [3]u32{ @intCast(@as(i64, ni) + 8 * dx), @intCast(@as(i64, nj) + 8 * dy), @intCast(@as(i64, nk) + 8 * dz) };
                                var mask = n.mask;
                                while (mask != 0) {
                                    const bit: u6 = @intCast(@ctz(mask));
                                    mask &= mask - 1;
                                    const v: f32 = if (b.plane(bit)) |pl| pl[Brick.bindex(sb[0], sb[1], sb[2])] else b.absentValue(bit);
                                    try haloPut(gpa, list, n, bit, .{ ni, nj, nk }, v);
                                }
                            }
                        }
                    }
                } else {
                    for (leaves) |h| {
                        var hk: u32 = 0;
                        while (hk < brick.HN) : (hk += 1) {
                            var hj: u32 = 0;
                            while (hj < brick.HN) : (hj += 1) {
                                var hi: u32 = 0;
                                while (hi < brick.HN) : (hi += 1) {
                                    if (!Brick.isHalo(.{ hi, hj, hk })) continue;
                                    const p = h.b.blockPoint(.{ hi, hj, hk });
                                    if (!b.key.holdsPoint(p)) continue;
                                    try haloEmit(gpa, list, nb, bl, h.b, .{ hi, hj, hk });
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── small vector helpers ─────────────────────────────────────────────────

pub fn dot(a: [3]f64, b: [3]f64) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn len3(a: [3]f64) f64 {
    return @sqrt(dot(a, a));
}

pub fn cross(a: [3]f64, b: [3]f64) [3]f64 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

pub fn normalize(a: [3]f64) [3]f64 {
    const l = len3(a);
    if (l < 1e-12) return a;
    return .{ a[0] / l, a[1] / l, a[2] / l };
}

/// Parallel transport of `n` from heading `a` to heading `b`: the
/// rotation taking a to b, applied to n, then re-orthogonalised. Frenet
/// is banned (loop-loft): this is what keeps θ = 0 from twisting.
pub fn transport(n: [3]f64, a: [3]f64, b: [3]f64) [3]f64 {
    const axis = cross(a, b);
    const s = len3(axis);
    const c = dot(a, b);
    var out = n;
    if (s > 1e-12) {
        const k = .{ axis[0] / s, axis[1] / s, axis[2] / s };
        const kxn = cross(k, n);
        const kdn = dot(k, n);
        inline for (0..3) |i| out[i] = n[i] * c + kxn[i] * s + k[i] * kdn * (1 - c);
    }
    // Re-orthogonalise against the new heading.
    const d = dot(out, b);
    inline for (0..3) |i| out[i] -= d * b[i];
    const l = len3(out);
    if (l < 1e-9) {
        // Degenerate: pick any perpendicular.
        const t: [3]f64 = if (@abs(b[0]) < 0.9) .{ 1, 0, 0 } else .{ 0, 1, 0 };
        return normalize(cross(b, t));
    }
    return .{ out[0] / l, out[1] / l, out[2] / l };
}

test "transport keeps the normal perpendicular and does not twist on a straight run" {
    const n = transport(.{ 0, 0, 1 }, .{ 0, 1, 0 }, .{ 0, 1, 0 });
    try std.testing.expectApproxEqAbs(@as(f64, 1), n[2], 1e-12);
    const a = normalize(.{ 0, 1, 0 });
    const b = normalize(.{ 1, 1, 0 });
    const m = transport(.{ 0, 0, 1 }, a, b);
    try std.testing.expectApproxEqAbs(@as(f64, 0), dot(m, b), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1), len3(m), 1e-12);
    // A normal in the plane of the turn follows the turn.
    const q = transport(.{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 0, 0 });
    try std.testing.expectApproxEqAbs(@as(f64, -1), q[1], 1e-12);
}
