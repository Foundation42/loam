//! brick — the spatial storage unit (spec §5.2, §6, §18; brief R2, R7).
//!
//! A brick is a cube of 8 cells per axis at one GAUGE: samples sit on
//! lattice points spaced 2^gauge apart, 9 per axis, node-centred. Since
//! Phase 2 (R7) a plane is an 11³ BLOCK: the 9³ samples the brick owns
//! and one HALO layer beyond each face, copied from the neighbours at
//! commit by the anchor rule taken one layer deeper (`world.zig`, the
//! halo pass). Reconstruction is a uniform cubic B-spline over the block
//! with the SAMPLES AS CONTROL VALUES: C2 inside the cube and across a
//! same-gauge seam, because both sides reconstruct from the same 64
//! coefficients. B-spline samples are control values, not points the
//! zero set passes through — `tools/g13_predict.py` says by how much a
//! thin feature thins, and G13 holds the instrument to it.
//!
//! Planes are popcount-packed by channel mask: `planes.len ==
//! @popCount(mask)`, always. A channel that is absent has no plane, no
//! pointer and no slot — "do not instantiate absent channels" (§18) is a
//! structural fact a guard can check, not a manner. An absent channel
//! READS as its absent value: zero, or "far" (+band) for `surface`.
//!
//! A brick is immutable once it is in a published snapshot. The commit
//! clones a dirty brick (`clone`), edits the clone, and the old one lives
//! on in the older snapshot until its last reader releases it. Refcounts
//! are atomic because snapshots are read from other threads (G8).

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const summary = @import("summary.zig");

const Key = lattice.Key;
const Blake3 = std.crypto.hash.Blake3;

pub const CELLS: u32 = 1 << lattice.BRICK_LOG2;
/// Samples per axis the brick owns (node-centred: cells + 1).
pub const N: u32 = CELLS + 1;
/// Block entries per axis: the samples and one halo layer each side.
pub const HN: u32 = N + 2;
/// Entries per plane — the block.
pub const SAMPLES: usize = HN * HN * HN;
/// Samples per plane the brick owns.
pub const INTERIOR: usize = N * N * N;
pub const Plane = [SAMPLES]f32;

pub const Error = error{ OutOfMemory, GaugeConflict };

pub const Brick = struct {
    key: Key,
    mask: channel.Mask = 0,
    planes: []*Plane = &.{},
    version: u32 = 0,
    /// The last change's magnitude and fed time (R15, `Summary.attention`):
    /// set by the commit before `finalize`, carried by `clone`, in the
    /// hash — under a budget it decides what the next step evaluates.
    attention: f32 = 0,
    changed_ns: u64 = 0,
    summary: summary.Summary = .{},
    hash: [32]u8 = [_]u8{0} ** 32,
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    pub fn create(gpa: std.mem.Allocator, key: Key) !*Brick {
        const b = try gpa.create(Brick);
        b.* = .{ .key = key };
        return b;
    }

    /// A deep copy with refs = 1 and the source's version. The caller
    /// edits it, then `finalize`s it.
    pub fn clone(gpa: std.mem.Allocator, src: *const Brick) !*Brick {
        const b = try gpa.create(Brick);
        errdefer gpa.destroy(b);
        b.* = .{ .key = src.key, .mask = src.mask, .version = src.version, .attention = src.attention, .changed_ns = src.changed_ns, .summary = src.summary, .hash = src.hash };
        const planes = try gpa.alloc(*Plane, src.planes.len);
        errdefer gpa.free(planes);
        var made: usize = 0;
        errdefer for (planes[0..made]) |p| gpa.destroy(p);
        for (src.planes, 0..) |p, i| {
            const np = try gpa.create(Plane);
            np.* = p.*;
            planes[i] = np;
            made += 1;
        }
        b.planes = planes;
        return b;
    }

    pub fn retain(self: *Brick) void {
        _ = self.refs.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Brick, gpa: std.mem.Allocator) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            for (self.planes) |p| gpa.destroy(p);
            gpa.free(self.planes);
            gpa.destroy(self);
        }
    }

    pub fn gauge(self: *const Brick) u5 {
        return self.key.gauge();
    }

    pub fn spacing(self: *const Brick) u32 {
        return self.key.spacing();
    }

    pub fn origin(self: *const Brick) [3]u32 {
        return self.key.origin();
    }

    /// The surface band in lattice units at this brick's gauge.
    pub fn band(self: *const Brick) f32 {
        return channel.band(self.spacing());
    }

    /// What an absent `bit` reads as here.
    pub fn absentValue(self: *const Brick, bit: u6) f32 {
        return channel.absentValue(bit, self.band());
    }

    pub fn has(self: *const Brick, bit: u6) bool {
        return channel.has(self.mask, bit);
    }

    pub fn plane(self: *const Brick, bit: u6) ?*Plane {
        if (!channel.has(self.mask, bit)) return null;
        return self.planes[channel.planeIndex(self.mask, bit)];
    }

    /// The plane for `bit`, allocating it filled with the absent value if
    /// absent. Only a brick under construction — this commit's clone,
    /// held by nothing but the commit and its scratch tree — may be
    /// written; a published brick is never handed out as `*Brick`, which
    /// is the guarantee.
    pub fn ensurePlane(self: *Brick, gpa: std.mem.Allocator, bit: u6) !*Plane {
        if (self.plane(bit)) |p| return p;
        const np = try gpa.create(Plane);
        @memset(np, self.absentValue(bit));
        const idx = channel.planeIndex(self.mask, bit);
        const planes = try gpa.alloc(*Plane, self.planes.len + 1);
        @memcpy(planes[0..idx], self.planes[0..idx]);
        planes[idx] = np;
        @memcpy(planes[idx + 1 ..], self.planes[idx..]);
        gpa.free(self.planes);
        self.planes = planes;
        self.mask |= channel.maskOf(bit);
        return np;
    }

    /// Drop a plane that says nothing: the channel becomes absent again.
    fn dropPlane(self: *Brick, gpa: std.mem.Allocator, bit: u6) void {
        const idx = channel.planeIndex(self.mask, bit);
        gpa.destroy(self.planes[idx]);
        const planes = gpa.alloc(*Plane, self.planes.len - 1) catch unreachable; // shrinking
        @memcpy(planes[0..idx], self.planes[0..idx]);
        @memcpy(planes[idx..], self.planes[idx + 1 ..]);
        gpa.free(self.planes);
        self.planes = planes;
        self.mask &= ~channel.maskOf(bit);
    }

    // ── Indexing ─────────────────────────────────────────────────────────
    //
    // Two coordinate systems on one block. SAMPLE coordinates (i, j, k)
    // in 0..8 are the brick's own points, what every operator, stamp and
    // seam write addresses; `index` maps them into the block. BLOCK
    // coordinates 0..10 include the halo (0 and 10); `bindex` maps them.

    /// Block index of the brick's own sample (i, j, k), each 0..CELLS.
    pub inline fn index(i: u32, j: u32, k: u32) usize {
        return bindex(i + 1, j + 1, k + 1);
    }

    /// Block index of block coordinates, each 0..HN-1.
    pub inline fn bindex(bi: u32, bj: u32, bk: u32) usize {
        return @as(usize, bi) + HN * (@as(usize, bj) + HN * @as(usize, bk));
    }

    /// Block coordinates of a block index.
    pub inline fn unindex(idx: usize) [3]u32 {
        const bi: u32 = @intCast(idx % HN);
        const bj: u32 = @intCast((idx / HN) % HN);
        const bk: u32 = @intCast(idx / (HN * HN));
        return .{ bi, bj, bk };
    }

    /// Whether block coordinates name one of the brick's own samples.
    pub inline fn isInterior(b: [3]u32) bool {
        return b[0] >= 1 and b[0] <= CELLS + 1 and b[1] >= 1 and b[1] <= CELLS + 1 and b[2] >= 1 and b[2] <= CELLS + 1;
    }

    /// Whether block coordinates lie in the halo.
    pub inline fn isHalo(b: [3]u32) bool {
        return !isInterior(b);
    }

    pub fn get(self: *const Brick, bit: u6, i: u32, j: u32, k: u32) f32 {
        const p = self.plane(bit) orelse return self.absentValue(bit);
        return p[index(i, j, k)];
    }

    /// Lattice point of sample (i, j, k).
    pub fn pointAt(self: *const Brick, i: u32, j: u32, k: u32) [3]u32 {
        const o = self.origin();
        const s = self.spacing();
        return .{ o[0] + i * s, o[1] + j * s, o[2] + k * s };
    }

    /// Lattice point of block coordinates — one spacing outside the cube
    /// for the halo, which may leave the lattice (hence i64).
    pub fn blockPoint(self: *const Brick, b: [3]u32) [3]i64 {
        const o = self.origin();
        const s: i64 = self.spacing();
        return .{
            @as(i64, o[0]) + (@as(i64, b[0]) - 1) * s,
            @as(i64, o[1]) + (@as(i64, b[1]) - 1) * s,
            @as(i64, o[2]) + (@as(i64, b[2]) - 1) * s,
        };
    }

    /// Sample index of lattice point `p` if it is one of this brick's
    /// samples (inside the closed cube and on this gauge's lattice).
    pub fn localOf(self: *const Brick, p: [3]i64) ?[3]u32 {
        if (!self.key.holdsPoint(p)) return null;
        const o = self.origin();
        const s: i64 = self.spacing();
        var r: [3]u32 = undefined;
        inline for (0..3) |a| {
            const d = p[a] - @as(i64, o[a]);
            if (@rem(d, s) != 0) return null;
            r[a] = @intCast(@divExact(d, s));
        }
        return r;
    }

    pub fn isBoundary(i: u32, j: u32, k: u32) bool {
        return i == 0 or i == CELLS or j == 0 or j == CELLS or k == 0 or k == CELLS;
    }

    // ── Reconstruction ───────────────────────────────────────────────────

    /// Local coordinates of `p` in cells, clamped to the closed cube, with
    /// the cell index and fractional part per axis. A point on the far
    /// face is cell 7 at t = 1, so the block indices stay in range.
    fn locate(self: *const Brick, p: [3]f64) struct { cell: [3]u32, t: [3]f32 } {
        const o = self.origin();
        const s: f64 = @floatFromInt(self.spacing());
        var cell: [3]u32 = undefined;
        var t: [3]f32 = undefined;
        inline for (0..3) |a| {
            var u = (p[a] - @as(f64, @floatFromInt(o[a]))) / s;
            if (u < 0) u = 0;
            if (u > @as(f64, CELLS)) u = @as(f64, CELLS);
            var ii: u32 = @intFromFloat(@floor(u));
            if (ii >= CELLS) ii = CELLS - 1;
            cell[a] = ii;
            t[a] = @floatCast(u - @as(f64, @floatFromInt(ii)));
        }
        return .{ .cell = cell, .t = t };
    }

    /// Trilinear reconstruction at `p` (lattice units) inside the closed
    /// cube; clamped at the faces so a point on the boundary reads the
    /// boundary. The absent value for an absent channel. Interpolating,
    /// C0: the hanging-node rule's interpolant (R9) and G13's instrument
    /// variation; the reconstruction the library answers with is
    /// `spline`.
    pub fn trilinear(self: *const Brick, bit: u6, p: [3]f64) f32 {
        const pl = self.plane(bit) orelse return self.absentValue(bit);
        return trilinearPlane(self, pl, p);
    }

    pub fn trilinearPlane(self: *const Brick, pl: *const Plane, p: [3]f64) f32 {
        const l = self.locate(p);
        const ix = l.cell;
        const c000 = pl[index(ix[0], ix[1], ix[2])];
        const c100 = pl[index(ix[0] + 1, ix[1], ix[2])];
        const c010 = pl[index(ix[0], ix[1] + 1, ix[2])];
        const c110 = pl[index(ix[0] + 1, ix[1] + 1, ix[2])];
        const c001 = pl[index(ix[0], ix[1], ix[2] + 1)];
        const c101 = pl[index(ix[0] + 1, ix[1], ix[2] + 1)];
        const c011 = pl[index(ix[0], ix[1] + 1, ix[2] + 1)];
        const c111 = pl[index(ix[0] + 1, ix[1] + 1, ix[2] + 1)];
        const fx = l.t[0];
        const fy = l.t[1];
        const fz = l.t[2];
        const c00 = c000 + (c100 - c000) * fx;
        const c10 = c010 + (c110 - c010) * fx;
        const c01 = c001 + (c101 - c001) * fx;
        const c11 = c011 + (c111 - c011) * fx;
        const c0 = c00 + (c10 - c00) * fy;
        const c1 = c01 + (c11 - c01) * fy;
        return c0 + (c1 - c0) * fz;
    }

    /// The uniform cubic B-spline basis on one axis at t ∈ [0, 1]: weights
    /// of the four control values at cells −1, 0, 1, 2 around the cell,
    /// with first and second derivatives in t. Partition of unity; the
    /// derivative rows sum to zero.
    pub const Basis = struct {
        w: [4]f32,
        dw: [4]f32,
        d2w: [4]f32,

        pub fn at(t: f32) Basis {
            const t2 = t * t;
            const t3 = t2 * t;
            const u = 1 - t;
            return .{
                .w = .{ u * u * u / 6, (3 * t3 - 6 * t2 + 4) / 6, (-3 * t3 + 3 * t2 + 3 * t + 1) / 6, t3 / 6 },
                .dw = .{ -u * u / 2, (3 * t2 - 4 * t) / 2, (-3 * t2 + 2 * t + 1) / 2, t2 / 2 },
                .d2w = .{ u, 3 * t - 2, -3 * t + 1, t },
            };
        }
    };

    /// Reconstruction with its first and second derivatives, per lattice
    /// unit. `hess` is (xx, yy, zz, xy, xz, yz).
    pub const Jet = struct {
        v: f32,
        grad: [3]f32,
        hess: [6]f32,
    };

    /// Cubic B-spline reconstruction at `p` (lattice units) inside the
    /// closed cube. The absent value for an absent channel.
    pub fn spline(self: *const Brick, bit: u6, p: [3]f64) f32 {
        const pl = self.plane(bit) orelse return self.absentValue(bit);
        return splinePlane(self, pl, p);
    }

    pub fn splinePlane(self: *const Brick, pl: *const Plane, p: [3]f64) f32 {
        const l = self.locate(p);
        const bx = Basis.at(l.t[0]);
        const by = Basis.at(l.t[1]);
        const bz = Basis.at(l.t[2]);
        var v: f32 = 0;
        // Block coordinates: cell c's four coefficients are samples c−1..c+2,
        // block entries c..c+3. Fixed loop order: the sum is bit-exact.
        var dk: u32 = 0;
        while (dk < 4) : (dk += 1) {
            var sj: f32 = 0;
            var dj: u32 = 0;
            while (dj < 4) : (dj += 1) {
                const row = bindex(l.cell[0], l.cell[1] + dj, l.cell[2] + dk);
                const si = pl[row] * bx.w[0] + pl[row + 1] * bx.w[1] + pl[row + 2] * bx.w[2] + pl[row + 3] * bx.w[3];
                sj += si * by.w[dj];
            }
            v += sj * bz.w[dk];
        }
        return v;
    }

    /// Value, gradient and Hessian of the B-spline at `p`.
    pub fn splineJet(self: *const Brick, bit: u6, p: [3]f64) Jet {
        const pl = self.plane(bit) orelse return .{ .v = self.absentValue(bit), .grad = .{ 0, 0, 0 }, .hess = .{ 0, 0, 0, 0, 0, 0 } };
        return splineJetPlane(self, pl, p);
    }

    pub fn splineJetPlane(self: *const Brick, pl: *const Plane, p: [3]f64) Jet {
        const l = self.locate(p);
        const bx = Basis.at(l.t[0]);
        const by = Basis.at(l.t[1]);
        const bz = Basis.at(l.t[2]);
        const h: f32 = @floatFromInt(self.spacing());
        // Ten tensor sums: (w,w,w), (d,w,w), (w,d,w), (w,w,d), (dd,w,w),
        // (w,dd,w), (w,w,dd), (d,d,w), (d,w,d), (w,d,d).
        var acc: [10]f32 = .{0} ** 10;
        var dk: u32 = 0;
        while (dk < 4) : (dk += 1) {
            var s_ww: f32 = 0;
            var s_dw: f32 = 0;
            var s_wd: f32 = 0;
            var s_ddw: f32 = 0;
            var s_wdd: f32 = 0;
            var s_dd: f32 = 0;
            var dj: u32 = 0;
            while (dj < 4) : (dj += 1) {
                const row = bindex(l.cell[0], l.cell[1] + dj, l.cell[2] + dk);
                const c0 = pl[row];
                const c1 = pl[row + 1];
                const c2 = pl[row + 2];
                const c3 = pl[row + 3];
                const si_w = c0 * bx.w[0] + c1 * bx.w[1] + c2 * bx.w[2] + c3 * bx.w[3];
                const si_d = c0 * bx.dw[0] + c1 * bx.dw[1] + c2 * bx.dw[2] + c3 * bx.dw[3];
                const si_dd = c0 * bx.d2w[0] + c1 * bx.d2w[1] + c2 * bx.d2w[2] + c3 * bx.d2w[3];
                s_ww += si_w * by.w[dj];
                s_dw += si_d * by.w[dj];
                s_wd += si_w * by.dw[dj];
                s_ddw += si_dd * by.w[dj];
                s_wdd += si_w * by.d2w[dj];
                s_dd += si_d * by.dw[dj];
            }
            acc[0] += s_ww * bz.w[dk]; // v
            acc[1] += s_dw * bz.w[dk]; // x
            acc[2] += s_wd * bz.w[dk]; // y
            acc[3] += s_ww * bz.dw[dk]; // z
            acc[4] += s_ddw * bz.w[dk]; // xx
            acc[5] += s_wdd * bz.w[dk]; // yy
            acc[6] += s_ww * bz.d2w[dk]; // zz
            acc[7] += s_dd * bz.w[dk]; // xy
            acc[8] += s_dw * bz.dw[dk]; // xz
            acc[9] += s_wd * bz.dw[dk]; // yz
        }
        const h2 = h * h;
        return .{
            .v = acc[0],
            .grad = .{ acc[1] / h, acc[2] / h, acc[3] / h },
            .hess = .{ acc[4] / h2, acc[5] / h2, acc[6] / h2, acc[7] / h2, acc[8] / h2, acc[9] / h2 },
        };
    }

    // ── Finalize ─────────────────────────────────────────────────────────

    /// Recompute the summary and the hash after editing; drop planes whose
    /// own samples all say nothing, so the mask says what is actually
    /// there. The halo is not consulted: it is the neighbours' content.
    pub fn finalize(self: *Brick, gpa: std.mem.Allocator) void {
        var bit: u6 = 0;
        while (true) : (bit += 1) {
            if (self.plane(bit)) |pl| {
                if (self.planeAbsent(bit, pl)) self.dropPlane(gpa, bit);
            }
            if (bit == 63) break;
        }
        self.summary = self.computeSummary();
        self.hash = self.computeHash();
    }

    /// Every sample the brick owns is the absent value.
    pub fn planeAbsent(self: *const Brick, bit: u6, pl: *const Plane) bool {
        const bd = self.band();
        var k: u32 = 0;
        while (k < N) : (k += 1) {
            var j: u32 = 0;
            while (j < N) : (j += 1) {
                var i: u32 = 0;
                while (i < N) : (i += 1) {
                    if (!channel.isAbsent(bit, pl[index(i, j, k)], bd)) return false;
                }
            }
        }
        return true;
    }

    fn computeSummary(self: *const Brick) summary.Summary {
        var s = summary.Summary{ .mask = self.mask, .version = self.version, .attention = self.attention, .changed_ns = self.changed_ns };
        const sp: f32 = @floatFromInt(self.spacing());
        const bd = self.band();
        const o = self.origin();
        const side: i64 = self.key.side();
        var bit: u6 = 0;
        while (true) : (bit += 1) {
            if (self.plane(bit)) |pl| {
                const range: ?*summary.Range = blk: {
                    if (bit == channel.Channel.density.bit()) break :blk &s.density;
                    if (bit == channel.Channel.extinction.bit()) break :blk &s.extinction;
                    if (bit == channel.Channel.emission.bit()) break :blk &s.emission;
                    if (bit == channel.Channel.material.bit()) break :blk &s.material;
                    if (bit == channel.Channel.surface.bit()) break :blk &s.surface;
                    break :blk null;
                };
                // Ranges, support and the Lipschitz bound are over the whole
                // BLOCK: the reconstruction inside the cube is a convex
                // combination of block coefficients, halo included, so a
                // bound from the interior alone would not be one. Support
                // from a halo entry is clamped to the cube it influences.
                var dmax: [3]f32 = .{ 0, 0, 0 };
                var bk: u32 = 0;
                while (bk < HN) : (bk += 1) {
                    var bj: u32 = 0;
                    while (bj < HN) : (bj += 1) {
                        var bi: u32 = 0;
                        while (bi < HN) : (bi += 1) {
                            const idx = bindex(bi, bj, bk);
                            const v = pl[idx];
                            if (range) |r| r.include(v);
                            if (!channel.isAbsent(bit, v, bd)) {
                                const bp = self.blockPoint(.{ bi, bj, bk });
                                var q: [3]u32 = undefined;
                                inline for (0..3) |a| q[a] = @intCast(@min(@max(bp[a], @as(i64, o[a])), @as(i64, o[a]) + side));
                                s.includePoint(q);
                            }
                            if (bi + 1 < HN) dmax[0] = @max(dmax[0], @abs(pl[idx + 1] - v));
                            if (bj + 1 < HN) dmax[1] = @max(dmax[1], @abs(pl[idx + HN] - v));
                            if (bk + 1 < HN) dmax[2] = @max(dmax[2], @abs(pl[idx + HN * HN] - v));
                        }
                    }
                }
                const lip = @sqrt(dmax[0] * dmax[0] + dmax[1] * dmax[1] + dmax[2] * dmax[2]) / sp;
                s.max_gradient = @max(s.max_gradient, lip);
                if (bit == channel.Channel.surface.bit()) s.lipschitz = lip;
            }
            if (bit == 63) break;
        }
        s.majorant = @max(@max(if (s.density.isEmpty()) 0 else s.density.max, if (s.extinction.isEmpty()) 0 else s.extinction.max), 0);
        return s;
    }

    fn computeHash(self: *const Brick) [32]u8 {
        var h = Blake3.init(.{});
        const raw = self.key.raw();
        h.update(std.mem.asBytes(&raw));
        h.update(std.mem.asBytes(&self.mask));
        h.update(std.mem.asBytes(&self.version));
        h.update(std.mem.asBytes(&self.attention));
        h.update(std.mem.asBytes(&self.changed_ns));
        for (self.planes) |p| h.update(std.mem.sliceAsBytes(p[0..]));
        var out: [32]u8 = undefined;
        h.final(&out);
        return out;
    }

    /// Max |value| over a plane's block — an additive channel's floor
    /// instrument.
    pub fn planeMaxAbs(pl: *const Plane) f32 {
        var m: f32 = 0;
        for (pl) |v| m = @max(m, @abs(v));
        return m;
    }
};

test "planes are popcount-packed, an absent channel has no plane and reads as its absent value" {
    const gpa = std.testing.allocator;
    const b = try Brick.create(gpa, Key.ofBrick(0, .{ 0, 0, 0 }));
    defer b.release(gpa);
    try std.testing.expectEqual(@as(usize, 0), b.planes.len);
    try std.testing.expect(b.plane(channel.Channel.material.bit()) == null);
    try std.testing.expectEqual(@as(f32, 3), b.get(channel.Channel.surface.bit(), 1, 2, 3));
    const m = try b.ensurePlane(gpa, channel.Channel.material.bit());
    m[Brick.index(1, 2, 3)] = 0.5;
    const d = try b.ensurePlane(gpa, channel.Channel.density.bit());
    d[Brick.index(4, 4, 4)] = 2;
    // density (bit 0) packs before material (bit 12) whatever the order of creation
    try std.testing.expectEqual(@as(usize, 2), b.planes.len);
    try std.testing.expectEqual(d, b.planes[0]);
    try std.testing.expectEqual(m, b.planes[1]);
    try std.testing.expectEqual(@as(f32, 0.5), b.get(channel.Channel.material.bit(), 1, 2, 3));
    try std.testing.expectEqual(@as(f32, 0), b.get(channel.Channel.light.bit(), 1, 2, 3));
    b.finalize(gpa);
    try std.testing.expectEqual([3]u32{ 1, 2, 3 }, b.summary.lo);
    try std.testing.expectEqual([3]u32{ 4, 4, 4 }, b.summary.hi);
    try std.testing.expectEqual(@as(f32, 2), b.summary.density.max);
    try std.testing.expectEqual(@as(f32, 0.5), b.summary.material.max);
    try std.testing.expectEqual(@as(f32, 2), b.summary.majorant);
    // Zero the density plane: finalize drops it and the mask says so.
    @memset(d, 0);
    b.finalize(gpa);
    try std.testing.expectEqual(@as(usize, 1), b.planes.len);
    try std.testing.expect(!b.has(channel.Channel.density.bit()));
    // A surface plane at the band everywhere is absent too; one sample
    // nearer keeps it, and the summary's range and bound say so.
    const sf = try b.ensurePlane(gpa, channel.Channel.surface.bit());
    try std.testing.expectEqual(@as(f32, 3), sf[Brick.index(0, 0, 0)]);
    b.finalize(gpa);
    try std.testing.expect(!b.has(channel.Channel.surface.bit()));
    const sf2 = try b.ensurePlane(gpa, channel.Channel.surface.bit());
    sf2[Brick.index(2, 2, 2)] = -1;
    b.finalize(gpa);
    try std.testing.expect(b.has(channel.Channel.surface.bit()));
    try std.testing.expectEqual(@as(f32, -1), b.summary.surface.min);
    try std.testing.expectApproxEqAbs(@as(f32, 4 * @sqrt(3.0)), b.summary.lipschitz, 1e-5);
}

test "trilinear reproduces samples at points and interpolates between them, at gauge 2" {
    const gpa = std.testing.allocator;
    const b = try Brick.create(gpa, Key.ofBrick(2, .{ 32, 0, 0 }));
    defer b.release(gpa);
    const pl = try b.ensurePlane(gpa, 0);
    // f(x,y,z) = x + 2y + 3z in lattice units is reproduced exactly by trilinear.
    var k: u32 = 0;
    while (k < N) : (k += 1) {
        var j: u32 = 0;
        while (j < N) : (j += 1) {
            var i: u32 = 0;
            while (i < N) : (i += 1) {
                const p = b.pointAt(i, j, k);
                pl[Brick.index(i, j, k)] = @floatFromInt(p[0] + 2 * p[1] + 3 * p[2]);
            }
        }
    }
    try std.testing.expectApproxEqAbs(@as(f32, 36 + 2 * 4 + 3 * 8), b.trilinear(0, .{ 36, 4, 8 }), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 33.5 + 2 * 1.25 + 3 * 30), b.trilinear(0, .{ 33.5, 1.25, 30 }), 1e-3);
    // The closed cube's far face reads the face.
    try std.testing.expectApproxEqAbs(@as(f32, 64 + 2 * 32 + 3 * 32), b.trilinear(0, .{ 64, 32, 32 }), 1e-3);
    try std.testing.expectEqual([3]u32{ 1, 2, 0 }, b.localOf(.{ 36, 8, 0 }).?);
    try std.testing.expect(b.localOf(.{ 37, 8, 0 }) == null);
    try std.testing.expect(b.localOf(.{ 36, 8, 33 }) == null);
}

/// Fill a plane's whole block, halo included, from f at the lattice point.
fn fillBlock(b: *const Brick, pl: *Plane, comptime f: fn ([3]f64) f32) void {
    var bk: u32 = 0;
    while (bk < HN) : (bk += 1) {
        var bj: u32 = 0;
        while (bj < HN) : (bj += 1) {
            var bi: u32 = 0;
            while (bi < HN) : (bi += 1) {
                const p = b.blockPoint(.{ bi, bj, bk });
                pl[Brick.bindex(bi, bj, bk)] = f(.{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) });
            }
        }
    }
}

test "the B-spline reproduces a linear field exactly, a quadratic to its known bias, and the jet matches finite differences" {
    const gpa = std.testing.allocator;
    const b = try Brick.create(gpa, Key.ofBrick(1, .{ 64, 32, 0 }));
    defer b.release(gpa);
    const pl = try b.ensurePlane(gpa, 0);
    // Linear: the B-spline reproduces polynomials of degree ≤ 1 with samples
    // as control values (its approximation order is 2), gradient exact.
    fillBlock(b, pl, struct {
        fn f(p: [3]f64) f32 {
            return @floatCast(0.5 * p[0] - p[1] + 2 * p[2] + 3);
        }
    }.f);
    const q = [3]f64{ 66.3, 39.1, 11.7 };
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(0.5 * q[0] - q[1] + 2 * q[2] + 3)), b.spline(0, q), 1e-3);
    const jet = b.splineJet(0, q);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), jet.grad[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -1), jet.grad[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 2), jet.grad[2], 1e-4);
    for (jet.hess) |hh| try std.testing.expectApproxEqAbs(@as(f32, 0), hh, 1e-3);
    // On the far face the reconstruction is still the field: cell 7 at t = 1.
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(0.5 * 80 - 48 + 2 * 16 + 3)), b.spline(0, .{ 80, 48, 16 }), 1e-3);
    // Quadratic x²: samples as control values give x² + h²/3 (the kernel's
    // second moment) — the smoothing G13's threshold was derived from.
    fillBlock(b, pl, struct {
        fn f(p: [3]f64) f32 {
            return @floatCast((p[0] - 70) * (p[0] - 70));
        }
    }.f);
    const x = [3]f64{ 71.25, 40, 8 };
    try std.testing.expectApproxEqAbs(@as(f32, 1.25 * 1.25 + 4.0 / 3.0), b.spline(0, x), 1e-3);
    const j2 = b.splineJet(0, x);
    try std.testing.expectApproxEqAbs(@as(f32, 2 * 1.25), j2.grad[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 2), j2.hess[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), j2.hess[1], 1e-3);
    // The jet against central differences of the spline itself.
    const e: f64 = 0.05;
    inline for (0..3) |a| {
        var xp = x;
        var xm = x;
        xp[a] += e;
        xm[a] -= e;
        const fd = (@as(f64, b.spline(0, xp)) - @as(f64, b.spline(0, xm))) / (2 * e);
        try std.testing.expectApproxEqAbs(fd, @as(f64, j2.grad[a]), 1e-2);
    }
}
