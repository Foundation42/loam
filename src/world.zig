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
//! `guards.zig` checks both by reconstructing every shared face from both
//! sides. This is the whole point of P1.2 and the gate that pays for it
//! straddles two gauges.
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
const thresholds = @import("thresholds.zig");

const Key = lattice.Key;
const Brick = brick.Brick;
const Plane = brick.Plane;
const Snapshot = tree.Snapshot;
const Front = front.Front;
const Channel = channel.Channel;

pub const Error = error{ OutOfMemory, GaugeConflict, TimeRegression, TooManyReaders, UnknownChannel };

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
};

pub const StepStats = struct {
    active_in: u64 = 0,
    region_evals: u64 = 0,
    front_steps: u64 = 0,
    fronts_dormant: u64 = 0,
    bricks_changed: u64 = 0,
    bricks_materialised: u64 = 0,
    seam_bricks: u64 = 0,
    seam_writes: u64 = 0,
    spawns: u64 = 0,
    deaths: u64 = 0,
    diffusion_clamped: u64 = 0,
    active_out: u64 = 0,
    // Wall-clock nanoseconds per phase: instrumentation only, printed
    // beside the counts, never read by the sim.
    ns_operate: u64 = 0,
    ns_fronts: u64 = 0,
    ns_apply: u64 = 0,
    ns_frontier: u64 = 0,
    ns_seams: u64 = 0,
    ns_finalize: u64 = 0,
    ns_build: u64 = 0,
    ns_publish: u64 = 0,

    fn accumulate(self: *StepStats, o: StepStats) void {
        inline for (std.meta.fields(StepStats)) |f| @field(self, f.name) += @field(o, f.name);
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
    /// Fronts queued by authoring or the front pass; ids assigned at commit.
    pending_spawns: std.ArrayListUnmanaged(update.Spawn) = .{},

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
        self.pending_spawns.deinit(self.gpa);
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
        try self.commit(.{ .frame = self.frame, .time_ns = self.time_ns }, self.head, false);
    }

    // ── The step ─────────────────────────────────────────────────────────

    pub fn step(self: *World, now: Now, js: ?*jobs.JobSystem) Error!void {
        if (self.started) {
            if (now.time_ns < self.time_ns or now.frame < self.frame) return Error.TimeRegression;
        } else {
            self.started = true;
            self.time_ns = now.time_ns;
            self.frame = now.frame;
        }
        const dt_ns = now.time_ns - self.time_ns;
        const dt: f64 = @as(f64, @floatFromInt(dt_ns)) / 1e9;
        self.time_ns = now.time_ns;
        self.frame = now.frame;
        self.epoch += 1;
        self.stats = .{};
        self.buffer.reset();

        const base = self.head;
        const gpa = self.gpa;

        // 1. The active set — every brick, under the mutation.
        var all_keys: []Key = &.{};
        defer if (all_keys.len > 0) gpa.free(all_keys);
        const active: []const Key = if (self.policy.active_only) base.active else blk: {
            const bs = try base.bricks(gpa);
            defer gpa.free(bs);
            all_keys = try gpa.alloc(Key, bs.len);
            for (bs, 0..) |b, i| all_keys[i] = b.key;
            break :blk all_keys;
        };
        self.stats.active_in = active.len;

        // 2. Entries, serially, one per active brick.
        var updates = try gpa.alloc(*update.RegionUpdate, active.len);
        defer gpa.free(updates);
        for (active, 0..) |k, i| updates[i] = try self.buffer.region(k);

        // 3. Operate: region-local, order-free.
        var timer = std.time.Timer.start() catch unreachable;
        const evaluated = dt > 0 and self.operators.items.len > 0;
        if (evaluated) {
            var ctx = OperateCtx{
                .world = self,
                .base = base,
                .dt = dt,
                .active = active,
                .updates = updates,
                .alloc = self.buffer.planeAllocator(),
                .evals = std.atomic.Value(u64).init(0),
                .clamped = std.atomic.Value(u64).init(0),
            };
            if (js) |sys| {
                var counter = jobs.Counter.init(0);
                sys.parallelFor(@intCast(active.len), self.policy.chunk, operateJob, &ctx, &counter);
                sys.waitFor(&counter);
            } else {
                operateRange(&ctx, 0, active.len);
            }
            self.stats.region_evals = ctx.evals.load(.monotonic);
            self.stats.diffusion_clamped = ctx.clamped.load(.monotonic);
        }

        self.stats.ns_operate = timer.lap();

        // 4. Fronts, serial, id order, after the barrier.
        if (dt > 0) try self.frontPass(base, dt);
        self.stats.ns_fronts = timer.lap();

        // 5. Commit and publish.
        try self.commit(now, base, evaluated);
        self.total.accumulate(self.stats);
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
                .seed = ctx.world.seed,
                .alloc = ctx.alloc,
                .registry = &ctx.world.registry,
                .fronts_here = ctx.world.frontsNear(key),
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

    /// Live, non-dormant fronts within a brick and a half of `key`'s
    /// centre — "something is already working here". Linear; fronts are
    /// the sparse working set and this is read once per active brick.
    /// (Counting only the brick itself let a wound edge spawn a repair
    /// front every few steps as each one moved on: 285 fronts for one
    /// wound.)
    fn frontsNear(self: *const World, key: Key) u32 {
        const o = key.origin();
        const side: f64 = @floatFromInt(key.side());
        const reach = side * 1.5;
        var n: u32 = 0;
        for (self.fronts.items) |*f| {
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

    fn frontPass(self: *World, base: *const Snapshot, dt: f64) !void {
        const gpa = self.gpa;
        var spawns = std.ArrayListUnmanaged(update.Spawn){};
        defer spawns.deinit(gpa);
        const n = self.fronts.items.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const f = &self.fronts.items[i];
            if (!f.alive) continue;
            if (f.dormant) {
                // Re-check only when something changed under the front.
                if (!keyInSorted(base.active, f.brick)) {
                    self.stats.fronts_dormant += 1;
                    continue;
                }
                if (!self.canGrow(base, f)) {
                    self.stats.fronts_dormant += 1;
                    continue;
                }
                f.dormant = false;
            } else if (!self.canGrow(base, f)) {
                f.dormant = true;
                self.stats.fronts_dormant += 1;
                continue;
            }
            try self.stepFront(base, f, dt, &spawns);
            self.stats.front_steps += 1;
        }
        for (spawns.items) |s| try self.pending_spawns.append(gpa, s);
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

    /// Growth potential one radius ahead of the front, and nothing of its
    /// own kind in the way there (inhibition).
    fn canGrow(_: *World, base: *const Snapshot, f: *const Front) bool {
        const ahead = aheadOf(f);
        const g = base.sample(Channel.growth.bit(), ahead);
        if (g <= thresholds.EPSILON) return false;
        const m = base.sample(Channel.material.bit(), ahead);
        return m <= f.params.inhibit;
    }

    fn stepFront(self: *World, base: *const Snapshot, f: *Front, dt: f64, spawns: *std.ArrayListUnmanaged(update.Spawn)) !void {
        const p = f.params;
        var stream = rng.Stream.front(self.seed, f.id, self.epoch);

        // Steer (spec §11): v = a·∇light + b·∇stimulus − d·∇self + e·heading + noise.
        const h: f64 = @max(1.0, @as(f64, p.radius) * 0.5);
        const gl = base.gradient(Channel.light.bit(), f.pos, h);
        const gs = base.gradient(Channel.stimulus.bit(), f.pos, h);
        const gm = base.gradient(Channel.material.bit(), f.pos, h);
        const nz = [3]f64{ stream.gauss(), stream.gauss(), stream.gauss() };
        var v: [3]f64 = undefined;
        inline for (0..3) |a| {
            v[a] = @as(f64, p.tropism_light) * gl[a] + @as(f64, p.tropism_stimulus) * gs[a] - @as(f64, p.avoid_self) * gm[a] + @as(f64, p.persist) * f.dir[a] + @as(f64, p.wander) * nz[a];
        }
        const vl = len3(v);
        const old_dir = f.dir;
        if (vl > 1e-9) f.dir = .{ v[0] / vl, v[1] / vl, v[2] / vl };
        f.normal = transport(f.normal, old_dir, f.dir);

        // Move by arc length.
        const ds: f64 = @as(f64, p.speed) * dt;
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
            self.stats.deaths += 1;
            return;
        }

        // The ring CA — loop-loft's update, one ring per step.
        const t: f32 = @floatCast(@min(1.0, f.s / @as(f64, p.length)));
        const envelope: f32 = p.radius * (1 - p.taper * t) * (1 + p.bulge * @sin(2 * std.math.pi * p.waves * t));
        ringStep(f, &stream, envelope);

        // Deposit the ring into the field; draw down the potential around it.
        const avail = base.sample(Channel.growth.bit(), aheadOf(f));
        try self.stamp(base, f, dt, envelope, avail);

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
                try spawns.append(self.gpa, self.budSpawn(f, si, envelope));
                f.ring[si] = .{};
                f.cooldown = p.branch_cooldown;
                self.stats.spawns += 1;
            }
        }

        f.brick = self.brickUnder(base, f.pos);
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
                f.ring[i].r += s * (0.5 + 0.5 * @cos(std.math.pi * @as(f32, @floatFromInt(d)) / @as(f32, @floatFromInt(w))));
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

    fn budSpawn(self: *World, f: *const Front, si: usize, envelope: f32) update.Spawn {
        _ = self;
        const p = f.params;
        const theta: f64 = 2 * std.math.pi * @as(f64, @floatFromInt(si)) / @as(f64, front.SLOTS) + f.roll;
        const bin = cross(f.dir, f.normal);
        var radial: [3]f64 = undefined;
        inline for (0..3) |a| radial[a] = @cos(theta) * f.normal[a] + @sin(theta) * bin[a];
        const rr: f64 = envelope + f.ring[si].r;
        var pos: [3]f64 = undefined;
        var dir: [3]f64 = undefined;
        const ca = @cos(@as(f64, p.branch_angle));
        const sa = @sin(@as(f64, p.branch_angle));
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

    /// Stamp the ring into Material, Activity and Age; draw down Growth
    /// in a sphere of two radii. Age holds the FED TIME at which a sample
    /// was first laid, so the age of tissue is `now − Age` — derivable
    /// without an ageing operator touching dormant bricks, which is the
    /// only encoding of history G5 allows.
    fn stamp(self: *World, base: *const Snapshot, f: *const Front, dt: f64, envelope: f32, avail: f32) !void {
        const p = f.params;
        const now_s: f32 = @floatCast(@as(f64, @floatFromInt(self.time_ns)) / 1e9);
        var rmax: f32 = 0;
        for (f.ring) |sl| rmax = @max(rmax, @abs(sl.r));
        const soft: f64 = 0.75;
        const reach: f64 = @as(f64, envelope + rmax) + soft;
        const half_len: f64 = @max(@as(f64, p.speed) * dt, 1.0) * 0.5 + soft;
        const draw_r: f64 = 2.0 * @as(f64, p.radius);
        const draw: f32 = p.consume * @as(f32, @floatCast(dt));
        const ext = @max(reach + half_len, draw_r);
        var lo: [3]i64 = undefined;
        var hi: [3]i64 = undefined;
        inline for (0..3) |a| {
            lo[a] = @max(@as(i64, 0), tree.floorI(f.pos[a] - ext));
            hi[a] = @min(@as(i64, lattice.CELLS), tree.floorI(f.pos[a] + ext) + 1);
        }
        const bin = cross(f.dir, f.normal);
        const deposit: f32 = p.deposit * @as(f32, @floatCast(dt)) * @min(1.0, avail);
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
            const ru = try self.buffer.region(key);
            const o = key.origin();
            const sp: i64 = key.spacing();
            const alloc = self.buffer.arena.allocator();
            const existing = base.brickAt(key);
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
                        const w = ringWeight(f, envelope, bin, half_len, soft, q);
                        if (w <= 0) continue;
                        if (deposit > 0) {
                            const cur: f32 = if (existing) |b| b.get(Channel.material.bit(), i, j, k) else 0;
                            // Material saturates: deposit what the sample can still take.
                            const room = @max(0.0, 1.0 - cur);
                            const d = @min(room, deposit * w);
                            if (d > 0) {
                                try ru.add(alloc, Channel.material.bit(), idx, d);
                                const born: f32 = if (existing) |b| b.get(Channel.age.bit(), i, j, k) else 0;
                                const pending: f32 = if (ru.deltas[Channel.age.bit()]) |dp| dp[idx] else 0;
                                if (born == 0 and pending == 0) try ru.add(alloc, Channel.age.bit(), idx, now_s);
                            }
                        }
                        try ru.add(alloc, Channel.activity.bit(), idx, w);
                    }
                }
            }
        }
    }

    /// Weight of a lattice point under the ring: inside the ring's radius
    /// at that angle, within the ring's axial slab, both softened.
    fn ringWeight(f: *const Front, envelope: f32, bin: [3]f64, half_len: f64, soft: f64, q: [3]f64) f32 {
        const d = [3]f64{ q[0] - f.pos[0], q[1] - f.pos[1], q[2] - f.pos[2] };
        const ax = dot(d, f.dir);
        const aw = smooth(half_len, half_len - soft, @abs(ax));
        if (aw <= 0) return 0;
        const rad = [3]f64{ d[0] - ax * f.dir[0], d[1] - ax * f.dir[1], d[2] - ax * f.dir[2] };
        const rho = len3(rad);
        const theta = std.math.atan2(dot(rad, bin), dot(rad, f.normal)) - f.roll;
        const N: f64 = front.SLOTS;
        var u = @mod(theta, 2 * std.math.pi) / (2 * std.math.pi) * N;
        if (u >= N) u -= N;
        const slot0: usize = @intFromFloat(@floor(u));
        const fr: f32 = @floatCast(u - @floor(u));
        const r0 = f.ring[slot0 % front.SLOTS].r;
        const r1 = f.ring[(slot0 + 1) % front.SLOTS].r;
        const ring_r: f64 = @max(0.25, envelope + std.math.lerp(r0, r1, fr));
        const rw = smooth(ring_r + soft, ring_r - soft, rho);
        return @floatCast(rw * aw);
    }

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
        max_delta: f32 = 0,
        materialised: bool = false,
        /// Seam precedence among equal gauges: 0 wrote deltas this
        /// commit, 1 was cloned by the seam pass or is unchanged, 2 was
        /// materialised empty. Lower wins. A tie on key alone once
        /// copied a new neighbour's zero over the point mass it was
        /// meant to receive.
        rank: u8 = 1,
    };

    /// `evaluated`: the operate phase ran over `base.active`, so a brick
    /// that did not change has settled. When it did not run — the epoch
    /// tick, an authoring apply — the active set carries forward.
    fn commit(self: *World, now: Now, base: *const Snapshot, evaluated: bool) Error!void {
        const gpa = self.gpa;
        const eps = thresholds.EPSILON;
        var timer = std.time.Timer.start() catch unreachable;
        var changed = std.AutoHashMapUnmanaged(u64, Changed){};
        defer changed.deinit(gpa);
        var order = std.ArrayListUnmanaged(u64){};
        defer order.deinit(gpa);
        // Until the real tree owns them, the changed bricks are ours.
        var bricks_owned = true;
        errdefer if (bricks_owned) {
            for (order.items) |raw| changed.get(raw).?.b.release(gpa);
        };

        // 1. Apply deltas in key order.
        const entries = try self.buffer.sorted(gpa);
        defer gpa.free(entries);
        var spawn_requests = std.ArrayListUnmanaged(update.Spawn){};
        defer spawn_requests.deinit(gpa);
        for (entries) |ru| {
            for (ru.spawns.items) |s| try spawn_requests.append(gpa, s);
            if (ru.mask == 0 and !ru.materialise) continue;
            const old = base.brickAt(ru.key);
            if (old == null and ru.mask == 0) {
                // materialise only: an empty brick
            }
            const nb = if (old) |o| try Brick.clone(gpa, o) else try Brick.create(gpa, ru.key);
            nb.version = if (old) |o| o.version + 1 else 1;
            var max_delta: f32 = 0;
            var bit: u6 = 0;
            while (true) : (bit += 1) {
                if (ru.deltas[bit]) |dp| {
                    const clamp = self.registry.clamp(bit);
                    const pl = try nb.ensurePlane(gpa, bit);
                    for (pl, dp) |*v, d| {
                        const nv = clamp.apply(v.* + d);
                        max_delta = @max(max_delta, @abs(nv - v.*));
                        v.* = nv;
                    }
                }
                if (bit == 63) break;
            }
            try changed.put(gpa, ru.key.raw(), .{ .b = nb, .old = old, .max_delta = max_delta, .materialised = old == null and ru.mask == 0, .rank = if (ru.mask != 0) 0 else 2 });
            try order.append(gpa, ru.key.raw());
        }

        self.stats.ns_apply = timer.lap();

        // 2. Frontier: a changed brick whose face carries a value above
        // the floor materialises the absent neighbour across it. Probed
        // against a scratch tree that already holds this commit's bricks,
        // so a neighbour is never placed inside a brick being created.
        var overrides = std.ArrayListUnmanaged(tree.Override){};
        defer overrides.deinit(gpa);
        {
            for (order.items) |raw| try overrides.append(gpa, .{ .key = Key.fromRaw(raw), .brick = changed.get(raw).?.b });
            std.mem.sort(tree.Override, overrides.items, {}, tree.Override.lessThan);
            const pre_root = try tree.build(gpa, base.root, overrides.items);
            defer if (pre_root) |r| r.release(gpa);
            const pre = Snapshot{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = pre_root };
            var i: usize = 0;
            const n0 = order.items.len;
            while (i < n0) : (i += 1) {
                const c = changed.get(order.items[i]).?;
                try self.materialiseFrontier(&pre, c.b, &changed, &order);
            }
        }

        self.stats.ns_frontier = timer.lap();

        // 3. A scratch tree with every changed brick, for the seam pass.
        overrides.clearRetainingCapacity();
        for (order.items) |raw| {
            const c = changed.get(raw).?;
            try overrides.append(gpa, .{ .key = Key.fromRaw(raw), .brick = c.b });
        }
        std.mem.sort(tree.Override, overrides.items, {}, tree.Override.lessThan);
        const scratch_root = try tree.build(gpa, base.root, overrides.items);
        var scratch = Snapshot{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = 0, .root = scratch_root };
        defer if (scratch_root) |r| r.release(gpa);

        // 4. Seams.
        try self.reconcile(&scratch, &changed, &order);
        self.stats.ns_seams = timer.lap();

        // 5. Finalize every changed brick, build the real tree.
        overrides.clearRetainingCapacity();
        var dirty = std.ArrayListUnmanaged(Key){};
        defer dirty.deinit(gpa);
        var active = std.ArrayListUnmanaged(Key){};
        defer active.deinit(gpa);
        for (order.items) |raw| {
            const c = changed.getPtr(raw).?;
            c.b.finalize(gpa);
            try overrides.append(gpa, .{ .key = Key.fromRaw(raw), .brick = c.b });
            try dirty.append(gpa, Key.fromRaw(raw));
            if (c.max_delta > eps or c.materialised) try active.append(gpa, Key.fromRaw(raw));
            if (c.materialised) self.stats.bricks_materialised += 1;
        }
        self.stats.bricks_changed = order.items.len;
        self.stats.ns_finalize = timer.lap();
        std.mem.sort(tree.Override, overrides.items, {}, tree.Override.lessThan);
        const root = try tree.build(gpa, base.root, overrides.items);
        errdefer if (root) |r| r.release(gpa);
        self.stats.ns_build = timer.lap();
        // The overrides' bricks were retained by their leaves; drop ours.
        for (order.items) |raw| changed.get(raw).?.b.release(gpa);
        bricks_owned = false;

        // 6. Fronts: spawn what was requested, assign ids in order.
        for (self.pending_spawns.items) |s| try spawn_requests.append(gpa, s);
        self.pending_spawns.clearRetainingCapacity();
        for (spawn_requests.items) |s| {
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
            };
            f.brick = self.brickUnder(base, f.pos);
            try self.fronts.append(gpa, f);
        }
        for (self.fronts.items) |*f| {
            if (f.alive and !f.dormant) try active.append(gpa, f.brick);
        }
        if (!evaluated) {
            for (base.active) |k| try active.append(gpa, k);
        }

        // 7. The snapshot.
        std.mem.sort(Key, active.items, {}, Key.lessThan);
        std.mem.sort(Key, dirty.items, {}, Key.lessThan);
        const snap = try gpa.create(Snapshot);
        errdefer gpa.destroy(snap);
        const fronts_copy = try gpa.dupe(Front, self.fronts.items);
        errdefer gpa.free(fronts_copy);
        const active_owned = try dedupKeys(gpa, active.items);
        errdefer gpa.free(active_owned);
        const dirty_owned = try dedupKeys(gpa, dirty.items);
        errdefer gpa.free(dirty_owned);
        snap.* = .{
            .gpa = gpa,
            .vid = self.vid + 1,
            .epoch = self.epoch,
            .time_ns = now.time_ns,
            .seed = self.seed,
            .root = root,
            .fronts = fronts_copy,
            .active = active_owned,
            .dirty = dirty_owned,
        };
        const counts = snap.countNodes();
        snap.brick_count = counts.bricks;
        snap.node_count = counts.nodes;
        self.stats.active_out = active_owned.len;
        try self.publish(snap);
        self.stats.ns_publish = timer.lap();
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

    fn materialiseFrontier(self: *World, view: *const Snapshot, b: *const Brick, changed: *std.AutoHashMapUnmanaged(u64, Changed), order: *std.ArrayListUnmanaged(u64)) !void {
        const eps = thresholds.EPSILON;
        const o = b.origin();
        const side: i64 = b.key.side();
        // Six faces: axis, and which end.
        var axis: usize = 0;
        while (axis < 3) : (axis += 1) {
            var end: u32 = 0;
            while (end < 2) : (end += 1) {
                const face: u32 = if (end == 0) 0 else brick.CELLS;
                var hot = false;
                for (b.planes) |pl| {
                    var u: u32 = 0;
                    while (u < brick.N and !hot) : (u += 1) {
                        var v: u32 = 0;
                        while (v < brick.N) : (v += 1) {
                            const ijk = faceIndex(axis, face, u, v);
                            if (@abs(pl[Brick.index(ijk[0], ijk[1], ijk[2])]) > eps) {
                                hot = true;
                                break;
                            }
                        }
                    }
                    if (hot) break;
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
                if (changed.contains(nk.raw())) continue;
                // Anything already there — a leaf at any gauge covering
                // the cube, or finer leaves inside it — shares the face
                // through the seam pass; only the void is materialised.
                if (view.nodeAt(nk) != null) continue;
                const nb = try Brick.create(self.gpa, nk);
                nb.version = 1;
                try changed.put(self.gpa, nk.raw(), .{ .b = nb, .old = null, .materialised = true, .rank = 2 });
                try order.append(self.gpa, nk.raw());
            }
        }
    }

    fn faceIndex(axis: usize, face: u32, u: u32, v: u32) [3]u32 {
        return switch (axis) {
            0 => .{ face, u, v },
            1 => .{ u, face, v },
            else => .{ u, v, face },
        };
    }

    // ── Seams ────────────────────────────────────────────────────────────

    const SeamCtx = struct {
        world: *World,
        view: *const Snapshot,
        changed: *std.AutoHashMapUnmanaged(u64, Changed),
        order: *std.ArrayListUnmanaged(u64),

        /// The live (editable, this-commit) version of a brick the view found.
        fn live(self: *SeamCtx, b: *const Brick) *const Brick {
            if (self.changed.get(b.key.raw())) |c| return c.b;
            return b;
        }

        fn rank(self: *SeamCtx, b: *const Brick) u8 {
            if (self.changed.get(b.key.raw())) |c| return c.rank;
            return 1;
        }



        /// Editable version, cloning on first write.
        fn mutable(self: *SeamCtx, b: *const Brick) !*Brick {
            if (self.changed.get(b.key.raw())) |c| return c.b;
            const nb = try Brick.clone(self.world.gpa, b);
            nb.version = b.version + 1;
            try self.changed.put(self.world.gpa, b.key.raw(), .{ .b = nb, .old = b });
            try self.order.append(self.world.gpa, b.key.raw());
            self.world.stats.seam_bricks += 1;
            return nb;
        }

        /// `b` is a live pointer (this commit's clone, or an untouched
        /// published brick). Nothing is looked up unless the value differs.
        fn write(self: *SeamCtx, b: *const Brick, bit: u6, idx: usize, v: f32) !void {
            const have: f32 = if (b.plane(bit)) |pl| pl[idx] else 0;
            if (have == v) return;
            const mb = try self.mutable(b);
            const pl = try mb.ensurePlane(self.world.gpa, bit);
            pl[idx] = v;
            const c = self.changed.getPtr(b.key.raw()).?;
            c.max_delta = @max(c.max_delta, @abs(v - have));
            self.world.stats.seam_writes += 1;
        }

        /// Copy `src`'s sample `sidx` into `b`'s sample `idx` for every
        /// channel either has. `b` is already live.
        fn copyPoint(self: *SeamCtx, b: *const Brick, idx: usize, src: *const Brick, sidx: usize) !void {
            var mask = b.mask | src.mask;
            while (mask != 0) {
                const bit: u6 = @intCast(@ctz(mask));
                mask &= mask - 1;
                const v: f32 = if (src.plane(bit)) |pl| pl[sidx] else 0;
                try self.write(b, bit, idx, v);
            }
        }

        /// Set `b`'s sample `idx` to `src`'s reconstruction at `q`.
        fn interpPoint(self: *SeamCtx, b: *const Brick, idx: usize, src: *const Brick, q: [3]f64) !void {
            var mask = b.mask | src.mask;
            while (mask != 0) {
                const bit: u6 = @intCast(@ctz(mask));
                mask &= mask - 1;
                try self.write(b, bit, idx, src.trilinear(bit, q));
            }
        }
    };

    /// The 26 cubes around a brick at its own level, resolved once: what
    /// leaf (same gauge or coarser) or leaves (finer) each holds. Every
    /// boundary point then finds its holders by key comparison instead of
    /// a tree descent — 26 descents per changed brick instead of 386×2.
    const Live = struct { b: *const Brick, rank: u8 };

    const Neighbourhood = struct {
        cells: [27]struct { start: u32, len: u32 },
        /// Resolved through `live`/`rank` once, so a point costs no lookups.
        leaves: std.ArrayListUnmanaged(Live) = .{},
        raw: std.ArrayListUnmanaged(*const Brick) = .{},

        fn cellIndex(dx: i64, dy: i64, dz: i64) usize {
            return @intCast((dx + 1) + 3 * (dy + 1) + 9 * (dz + 1));
        }

        fn build(gpa: std.mem.Allocator, ctx: *SeamCtx, view: *const Snapshot, b: *const Brick) !Neighbourhood {
            var nb = Neighbourhood{ .cells = undefined };
            errdefer nb.leaves.deinit(gpa);
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
                        for (nb.raw.items) |h| try nb.leaves.append(gpa, .{ .b = ctx.live(h), .rank = ctx.rank(h) });
                        nb.cells[ci].len = @intCast(nb.leaves.items.len - start);
                    }
                }
            }
            return nb;
        }

        fn deinit(self: *Neighbourhood, gpa: std.mem.Allocator) void {
            self.leaves.deinit(gpa);
            self.raw.deinit(gpa);
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

        /// Finer leaves around `b` (any cell holding more than one leaf, or
        /// one at a finer level): their boundary points on `b`'s surface
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

    /// One shared point: anchor (pass 1) or hang (pass 2) every holder.
    fn seamPoint(ctx: *SeamCtx, pass: u8, hs: []const Live, p: [3]i64) !void {
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
                try ctx.copyPoint(h.b, Brick.index(l[0], l[1], l[2]), finest.b, sidx);
            }
        } else {
            if (coarsest.localOf(p) != null) return; // on the coarse lattice: anchored
            const q = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
            for (hs) |h| {
                if (h.b == coarsest) continue;
                const l = h.b.localOf(p) orelse continue;
                try ctx.interpPoint(h.b, Brick.index(l[0], l[1], l[2]), coarsest, q);
            }
        }
    }

    /// `a` outranks `b` as the source of a shared point: finer, then
    /// lower rank, then lower key.
    fn outranks(a: Live, b: Live) bool {
        if (a.b.key.level != b.b.key.level) return a.b.key.level < b.b.key.level;
        if (a.rank != b.rank) return a.rank < b.rank;
        return a.b.key.raw() < b.b.key.raw();
    }

    fn reconcile(self: *World, view: *const Snapshot, changed: *std.AutoHashMapUnmanaged(u64, Changed), order: *std.ArrayListUnmanaged(u64)) !void {
        const gpa = self.gpa;
        var ctx = SeamCtx{ .world = self, .view = view, .changed = changed, .order = order };
        // Only points on a CHANGED brick's surface can have fallen out of
        // agreement: its own boundary samples, and the hanging samples of
        // any finer neighbour that lie on its faces. Neighbours the seam
        // pass clones join `order` but are not re-walked — their only
        // new values are copies made here.
        const n0 = order.items.len;
        var hs: [8]Live = undefined;
        var finer = std.ArrayListUnmanaged(*const Brick){};
        defer finer.deinit(gpa);
        var pass: u8 = 1;
        while (pass <= 2) : (pass += 1) {
            var ci: usize = 0;
            while (ci < n0) : (ci += 1) {
                const c = changed.get(order.items[ci]).?;
                const b = c.b;
                const bl = Live{ .b = b, .rank = c.rank };
                var nb = try Neighbourhood.build(gpa, &ctx, view, b);
                defer nb.deinit(gpa);
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
                            try seamPoint(&ctx, pass, hs[0..n], pi);
                        }
                    }
                }
                finer.clearRetainingCapacity();
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
                                try seamPoint(&ctx, pass, hs[0..n], pi);
                            }
                        }
                    }
                }
            }
        }
    }
};

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
