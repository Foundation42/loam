//! front — the Lagrangian active front (brief R1; loop-loft's ring).
//!
//! The field is the memory; the front is the cell. A front is a tracer
//! carrying loop-loft's fixed-size state vector: per slot `r, dz, tag,
//! age`; per front `s, R, roll, morphogens`. It READS the field (light,
//! stimulus, self-density, growth potential) and DEPOSITS into it
//! (material, age, activity). The ring CA is the toy's update rule
//! (docs/loop-loft.jsx), used as a specification: leak toward the
//! envelope, ring diffusion, counter-based noise, impulses. The §11
//! gradient terms steer the spine; a parallel-transport frame rides along
//! so the ring's θ = 0 does not twist at inflections.
//!
//! This file is the state and its canonical bytes. The behaviour — one
//! step of every live front — is `world.zig`'s front pass, because it
//! needs the snapshot to read and the update buffer to write.

const std = @import("std");
const lattice = @import("lattice.zig");

pub const SLOTS: usize = 24;

pub const Tag = enum(u32) { none = 0, bud = 1 };

pub const Slot = struct {
    /// Radial residual, lattice units, on top of the envelope.
    r: f32 = 0,
    /// Axial jitter, clamped to ±jitter·spacing (the manifold guarantee,
    /// kept for parity with the toy though a field has no manifold to lose).
    dz: f32 = 0,
    tag: Tag = .none,
    /// Consecutive rings the residual has been hot — the bud enzyme's clock.
    age: u32 = 0,
};

/// Per-front knobs. Defaults are the toy's, in lattice units where the
/// toy's were world units. Every field is a number a scene may set.
pub const Params = struct {
    // Ring CA (loop-loft's names).
    heal: f32 = 0.06,
    noise: f32 = 0.14,
    impulse: f32 = 0.14,
    diffuse: f32 = 0.35,
    drift: f32 = 0.03,
    jitter: f32 = 0.25,
    taper: f32 = 0.35,
    bulge: f32 = 0.10,
    waves: f32 = 3,
    // Spine.
    /// Base radius R0, lattice units.
    radius: f32 = 3.0,
    /// Lattice units of spine per second; one ring per step at dt = 1 s.
    speed: f32 = 1.0,
    /// Arc length over which the taper runs, and where the front stops.
    length: f32 = 96,
    // Steering (spec §11): velocity = a·∇light + b·∇stimulus − d·∇self +
    // e·heading + noise.
    tropism_light: f32 = 0.0,
    tropism_stimulus: f32 = 0.0,
    avoid_self: f32 = 0.5,
    persist: f32 = 1.0,
    wander: f32 = 0.15,
    // Deposit and resources.
    /// Material laid per second at full weight.
    deposit: f32 = 1.0,
    /// Growth potential drawn down per second in a sphere of two radii
    /// around the front — the resource a front uses up as it passes, so
    /// dormancy is exhaustion and a wound's restored potential is local.
    consume: f32 = 1.0,
    /// Occupancy one radius ahead above this inhibits the front — the
    /// carrier read as Phase 1 read Material: 1 inside, falling to 0 over
    /// `World.SOFT` outside (`World.occupancy`). Potential is read at the
    /// same point: a front grows into what is ahead of it, not what it
    /// stands in.
    inhibit: f32 = 0.6,
    /// The thinnest tube a front lays, lattice units; 0 means the gauge's
    /// SURVIVAL FLOOR from G13 (r/h ≥ 1, struck): below it the B-spline
    /// loses the zero set, and a twig whose ring residual dipped under it
    /// showed as gaps along its length — the representation telling the
    /// truth about what the gauge can carry (Christian, watching it
    /// grow: "visible gaps in the branches"). The ring's radius is
    /// clamped at the floor; the demand for a finer gauge is counted
    /// (`StepStats.below_faithful`), and refinement (D2) is where it goes.
    min_radius: f32 = 0,
    /// The collar (R10, P2.2): the radius k of the smooth union where
    /// this front's capsule meets ANOTHER front's deposit, authored
    /// tissue, or its own tube beyond the collar's reach (self-touch:
    /// the ammonite, the creeper doubling back), as a fraction of the
    /// ring's envelope — 1 is "the child's radius at the join",
    /// Christian's number with a biological referent; 0 is the hard
    /// union everywhere, G12 (a)'s mutation. Into its own RECENT
    /// deposit the union is always hard: a chain of a front's own
    /// capsules smooth-unioned with k > 0 dips k/4 at every joint
    /// (beads, the ledger P2.1), and provenance says which is which
    /// (`thresholds.collarReach`).
    collar: f32 = 1.0,
    /// A fixed turn of the heading about the world's vertical, radians
    /// per lattice unit of arc — a tendril's coil. Zero in every scene
    /// but the inner elbow's deliberately tight curl (the ledger,
    /// "P2.2 — the collar"), where the bend between rings has to be a
    /// number the scene chose.
    coil: f32 = 0.0,
    // Branching: a slot whose |residual| exceeds bud_threshold × envelope
    // for bud_rings consecutive rings is a bud; a bud fires when the front
    // is old enough and its cooldown has run.
    bud_threshold: f32 = 0.15,
    bud_rings: u32 = 6,
    branch_angle: f32 = 0.8,
    child_ratio: f32 = 0.7,
    max_generation: u8 = 3,
    min_age: u32 = 12,
    branch_cooldown: u32 = 10,
};

/// One ring of a front's history — the loft table (R12, P2.2): what the
/// capsule between this ring and the previous one was swept from, kept
/// per front on the world in ring order, appended by the commit in id
/// order. A band-1 query reads the sample's provenance (who, segment)
/// and evaluates THIS at its chart; G12 (b) rebuilds the capsule from
/// two of these and reads the deposit back bit for bit. The residual is
/// the ring's AFTER its CA step and BEFORE a bud's slot is reset, which
/// is what the capsule used; `bud` marks the slot that left — the scar.
pub const Ring = struct {
    segment: u32,
    s: f64,
    pos: [3]f64,
    dir: [3]f64,
    normal: [3]f64,
    roll: f64,
    envelope: f32,
    r: [SLOTS]f32 = [_]f32{0} ** SLOTS,
    tag: [SLOTS]u8 = [_]u8{0} ** SLOTS,
    bud: ?u8 = null,

    /// The bend from the previous ring's heading to this one's, radians.
    pub fn bendFrom(self: *const Ring, prev: *const Ring) f64 {
        var d: f64 = 0;
        inline for (0..3) |a| d += self.dir[a] * prev.dir[a];
        return std.math.acos(@min(1.0, @max(-1.0, d)));
    }
};

pub const Front = struct {
    id: u32,
    parent: u32 = std.math.maxInt(u32),
    generation: u8 = 0,
    alive: bool = true,
    /// No growth potential or inhibited: the front neither moves nor
    /// deposits, and costs nothing, until the field wakes it.
    dormant: bool = false,
    pos: [3]f64,
    dir: [3]f64,
    normal: [3]f64,
    s: f64 = 0,
    roll: f64 = 0,
    age: u32 = 0,
    cooldown: u32 = 0,
    born_epoch: u64 = 0,
    /// Rings swept so far: the ring index the next capsule carries as its
    /// `segment` is this plus one. The seed is ring zero.
    segment: u32 = 0,
    morphogens: [4]f32 = .{ 0, 0, 0, 0 },
    ring: [SLOTS]Slot = [_]Slot{.{}} ** SLOTS,
    params: Params = .{},
    /// The brick under the front's position, as of the last step.
    brick: lattice.Key,
    /// The previous ring — where the next sweep starts (R11). At birth
    /// it is the seed itself, so the first step sweeps from the seed.
    prev_pos: [3]f64 = .{ 0, 0, 0 },
    prev_dir: [3]f64 = .{ 0, 1, 0 },
    prev_normal: [3]f64 = .{ 0, 0, 1 },
    prev_roll: f64 = 0,
    prev_s: f64 = 0,
    prev_envelope: f32 = 0,
    prev_r: [SLOTS]f32 = [_]f32{0} ** SLOTS,

    /// The ring as the sweep saw it — what `Ring` records for the history.
    pub fn ringRecord(self: *const Front, envelope: f32) Ring {
        var r = Ring{
            .segment = self.segment,
            .s = self.s,
            .pos = self.pos,
            .dir = self.dir,
            .normal = self.normal,
            .roll = self.roll,
            .envelope = envelope,
        };
        for (self.ring, 0..) |sl, i| {
            r.r[i] = sl.r;
            r.tag[i] = @intCast(@intFromEnum(sl.tag));
        }
        return r;
    }

    /// The previous ring, as the sweep starts from it.
    pub fn prevRing(self: *const Front) Ring {
        return .{
            .segment = if (self.segment > 0) self.segment - 1 else 0,
            .s = self.prev_s,
            .pos = self.prev_pos,
            .dir = self.prev_dir,
            .normal = self.prev_normal,
            .roll = self.prev_roll,
            .envelope = self.prev_envelope,
            .r = self.prev_r,
        };
    }

    /// Canonical bytes: every field, fixed layout, no padding — what the
    /// hash and the dump agree on.
    pub fn writeCanonical(self: *const Front, w: anytype) !void {
        try w.writeInt(u32, self.id, .little);
        try w.writeInt(u32, self.parent, .little);
        try w.writeByte(self.generation);
        try w.writeByte(@intFromBool(self.alive));
        try w.writeByte(@intFromBool(self.dormant));
        inline for (.{ self.pos, self.dir, self.normal }) |v| {
            for (v) |c| try w.writeInt(u64, @bitCast(c), .little);
        }
        try w.writeInt(u64, @bitCast(self.s), .little);
        try w.writeInt(u64, @bitCast(self.roll), .little);
        try w.writeInt(u32, self.age, .little);
        try w.writeInt(u32, self.cooldown, .little);
        try w.writeInt(u64, self.born_epoch, .little);
        try w.writeInt(u32, self.segment, .little);
        for (self.morphogens) |m| try w.writeInt(u32, @bitCast(m), .little);
        for (self.ring) |sl| {
            try w.writeInt(u32, @bitCast(sl.r), .little);
            try w.writeInt(u32, @bitCast(sl.dz), .little);
            try w.writeInt(u32, @intFromEnum(sl.tag), .little);
            try w.writeInt(u32, sl.age, .little);
        }
        inline for (std.meta.fields(Params)) |f| {
            const v = @field(self.params, f.name);
            switch (@typeInfo(f.type)) {
                .float => try w.writeInt(u32, @bitCast(@as(f32, v)), .little),
                .int => try w.writeInt(u32, @intCast(v), .little),
                else => @compileError("params field " ++ f.name),
            }
        }
        try w.writeInt(u64, self.brick.raw(), .little);
        inline for (.{ self.prev_pos, self.prev_dir, self.prev_normal }) |v| {
            for (v) |c| try w.writeInt(u64, @bitCast(c), .little);
        }
        try w.writeInt(u64, @bitCast(self.prev_roll), .little);
        try w.writeInt(u64, @bitCast(self.prev_s), .little);
        try w.writeInt(u32, @bitCast(self.prev_envelope), .little);
        for (self.prev_r) |r| try w.writeInt(u32, @bitCast(r), .little);
    }

    pub fn hashInto(self: *const Front, h: *std.crypto.hash.Blake3) void {
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        self.writeCanonical(fbs.writer()) catch unreachable; // 1024 covers the layout; a comptime bound would be nicer
        h.update(fbs.getWritten());
    }

    pub fn canonicalLen() usize {
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const f = Front{ .id = 0, .pos = .{ 0, 0, 0 }, .dir = .{ 0, 1, 0 }, .normal = .{ 0, 0, 1 }, .brick = lattice.Key.ofBrick(0, .{ 0, 0, 0 }) };
        f.writeCanonical(fbs.writer()) catch unreachable;
        return fbs.getWritten().len;
    }
};

test "canonical bytes fit the buffer and change with the state" {
    const len = Front.canonicalLen();
    try std.testing.expect(len < 1024);
    var a = Front{ .id = 1, .pos = .{ 1, 2, 3 }, .dir = .{ 0, 1, 0 }, .normal = .{ 0, 0, 1 }, .brick = lattice.Key.ofBrick(0, .{ 0, 0, 0 }) };
    var ha = std.crypto.hash.Blake3.init(.{});
    a.hashInto(&ha);
    var oa: [32]u8 = undefined;
    ha.final(&oa);
    a.ring[3].r = 0.25;
    var hb = std.crypto.hash.Blake3.init(.{});
    a.hashInto(&hb);
    var ob: [32]u8 = undefined;
    hb.final(&ob);
    try std.testing.expect(!std.mem.eql(u8, &oa, &ob));
}
