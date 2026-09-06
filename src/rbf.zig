//! rbf — the material field as a PACKED SET OF RADIAL BASIS FUNCTIONS
//! (Christian's experiment, straight after the marble's columns: "try
//! baking via gradient descent to create a packed RBF set for the
//! albedo, roughness, metalness, emissives instead of the giant volume
//! texture").
//!
//! What a hit reads of a material field is, per present column,
//! M = entry·(1 − A) + B, where A is the vein's blend at the point (0
//! in the matrix, 1 inside a vein) and B = A·(the structure's material)
//! — linear in the field, so a sum of kernels can carry it, and the
//! entry is the BIAS: the matrix costs nothing, only the structure
//! costs kernels. A SET is N Gaussians, each a centre, a SHAPE and a
//! weight per channel of (A, B): KERNEL_FLOATS floats. The shape is
//! ANISOTROPIC (Christian: "let's try the anisotropic kernels next"):
//! the lower-triangular factor L of the kernel's precision, so the
//! Mahalanobis distance is |Lᵀ(q − μ)|, an isotropic kernel of width σ
//! is L = I/σ, and an ellipsoid — a vein is a tube, one ellipsoid
//! where a chain of spheres stood — is whatever the descent makes of
//! the six numbers, positive-definite by construction. It
//! is fitted by gradient descent (Adam) to the baked volume's own read
//! at random points, half of them drawn from the veins — uniform
//! sampling of a cube that is 6% vein would fit the matrix — from
//! centres seeded ON the veins with the vein's width. A read folds the
//! point by the mirror as the volume does and sums every kernel: the
//! GPU does the same (matryoshka's `loamRbf`), `materialAt` is its
//! twin term for term. The fit runs in `loam-run --rbf`, a tool, and
//! the set is a FILE (`write`/`read`): the archetype as an asset the
//! renderer loads without growing anything.
//!
//! Nothing here is on the sim path; the sim's hash never sees it.

const std = @import("std");
const bark = @import("bark.zig");
const rng = @import("rng.zig");
const fmath = @import("fmath.zig");
const thresholds = @import("thresholds.zig");

const Material = bark.Material;

/// The channels a kernel weighs: A, then B for albedo (3), roughness,
/// metallic, emissive (3). Always nine; the set's columns say which B
/// a read uses.
pub const CHANNELS: usize = 9;
/// A kernel: the centre, the six of L (l00, l10, l11, l20, l21, l22),
/// the nine weights.
pub const KERNEL_FLOATS: usize = 3 + 6 + CHANNELS;

pub const Kernel = struct {
    mu: [3]f32,
    /// The lower-triangular factor of the precision, row by row:
    /// l00, l10, l11, l20, l21, l22. Σ⁻¹ = L Lᵀ.
    l: [6]f32,
    w: [CHANNELS]f32,

    /// The isotropic kernel of width `sigma`.
    pub fn isotropic(mu: [3]f32, sigma: f32, w: [CHANNELS]f32) Kernel {
        const inv = 1 / sigma;
        return .{ .mu = mu, .l = .{ inv, 0, inv, 0, 0, inv }, .w = w };
    }

    /// The widths along the kernel's principal axes, longest first,
    /// from the precision's eigenvalues (1/√λ).
    pub fn widths(self: Kernel) [3]f32 {
        const l = self.l;
        // P = L Lᵀ, symmetric.
        const p00 = l[0] * l[0];
        const p10 = l[1] * l[0];
        const p11 = l[1] * l[1] + l[2] * l[2];
        const p20 = l[3] * l[0];
        const p21 = l[3] * l[1] + l[4] * l[2];
        const p22 = l[3] * l[3] + l[4] * l[4] + l[5] * l[5];
        const ev = eigen3(.{ p00, p10, p11, p20, p21, p22 });
        var out: [3]f32 = undefined;
        inline for (0..3) |i| out[i] = 1 / @sqrt(@max(ev[i], 1e-12));
        // Ascending eigenvalues are descending widths.
        return out;
    }

    /// The longest width over the shortest.
    pub fn aspect(self: Kernel) f32 {
        const wd = self.widths();
        return wd[0] / wd[2];
    }
};

/// Eigenvalues of a symmetric 3×3 (p00, p10, p11, p20, p21, p22),
/// ascending, by Jacobi rotations.
fn eigen3(p: [6]f32) [3]f32 {
    var a = [3][3]f64{ .{ p[0], p[1], p[3] }, .{ p[1], p[2], p[4] }, .{ p[3], p[4], p[5] } };
    var sweep: usize = 0;
    while (sweep < 32) : (sweep += 1) {
        var off: f64 = 0;
        for (0..3) |i| for (0..3) |j| {
            if (i != j) off += a[i][j] * a[i][j];
        };
        if (off < 1e-24) break;
        for (0..3) |pp| {
            var q: usize = pp + 1;
            while (q < 3) : (q += 1) {
                if (@abs(a[pp][q]) < 1e-18) continue;
                const theta = (a[q][q] - a[pp][pp]) / (2 * a[pp][q]);
                const t = std.math.sign(theta) / (@abs(theta) + @sqrt(theta * theta + 1));
                const c = 1 / @sqrt(t * t + 1);
                const sn = t * c;
                var r: [3][3]f64 = a;
                for (0..3) |k| {
                    r[k][pp] = c * a[k][pp] - sn * a[k][q];
                    r[k][q] = sn * a[k][pp] + c * a[k][q];
                }
                var r2: [3][3]f64 = r;
                for (0..3) |k| {
                    r2[pp][k] = c * r[pp][k] - sn * r[q][k];
                    r2[q][k] = sn * r[pp][k] + c * r[q][k];
                }
                a = r2;
            }
        }
    }
    var ev = [3]f32{ @floatCast(a[0][0]), @floatCast(a[1][1]), @floatCast(a[2][2]) };
    std.mem.sort(f32, &ev, {}, std.sort.asc(f32));
    return ev;
}

/// The nine channels of a read, or of a target.
pub const Channels = [CHANNELS]f32;

pub const Set = struct {
    /// The cube's extent in the archetype's units (the volume's).
    extent: f32,
    columns: bark.Columns,
    kernels: []Kernel,
    /// The volume the set was fitted to.
    hash: [32]u8,

    pub fn deinit(self: *Set, gpa: std.mem.Allocator) void {
        gpa.free(self.kernels);
    }

    pub fn bytes(self: *const Set) usize {
        return self.kernels.len * KERNEL_FLOATS * @sizeOf(f32);
    }

    /// `p` in the archetype's units, folded into the cube by the mirror
    /// on every axis — the volume's own fold.
    pub fn fold(extent: f32, p: [3]f32) [3]f32 {
        var q: [3]f32 = undefined;
        inline for (0..3) |a| {
            var f = @mod(p[a], 2 * extent);
            if (f >= extent) f = 2 * extent - f;
            q[a] = f;
        }
        return q;
    }

    /// The nine channels at a folded point: every kernel summed.
    pub fn eval(self: *const Set, q: [3]f32) Channels {
        var out: Channels = [_]f32{0} ** CHANNELS;
        for (self.kernels) |k| {
            const g = gaussian(k, q);
            inline for (0..CHANNELS) |c| out[c] += k.w[c] * g;
        }
        return out;
    }

    /// What a hit reads — the shader's twin: per present column the
    /// entry mixed by the blend, `entry·(1 − A) + B`; the entry alone
    /// for a column the archetype does not model.
    pub fn materialAt(self: *const Set, p_w: [3]f32, unit: f32, entry: Material) Material {
        const q = fold(self.extent, .{ p_w[0] / unit, p_w[1] / unit, p_w[2] / unit });
        const y = self.eval(q);
        return compose(self.columns, y, entry);
    }

    /// The set to a file: "LRBF", the version (2), the extent, the columns,
    /// the count, the hash, then the kernels, little-endian f32s.
    pub fn write(self: *const Set, path: []const u8) !void {
        var f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.writeAll("LRBF");
        try w.writeInt(u32, 2, .little);
        try w.writeInt(u32, @bitCast(self.extent), .little);
        try w.writeByte(self.columns);
        try w.writeInt(u32, @intCast(self.kernels.len), .little);
        try w.writeAll(&self.hash);
        for (self.kernels) |k| {
            for (k.mu) |v| try w.writeInt(u32, @bitCast(v), .little);
            for (k.l) |v| try w.writeInt(u32, @bitCast(v), .little);
            for (k.w) |v| try w.writeInt(u32, @bitCast(v), .little);
        }
        try bw.flush();
    }

    pub fn read(gpa: std.mem.Allocator, path: []const u8) !Set {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();
        var br = std.io.bufferedReader(f.reader());
        const r = br.reader();
        var magic: [4]u8 = undefined;
        try r.readNoEof(&magic);
        if (!std.mem.eql(u8, &magic, "LRBF")) return error.NotAnRbfSet;
        // Version 1 was the isotropic set of the same night; nothing kept it.
        if (try r.readInt(u32, .little) != 2) return error.RbfVersion;
        var out: Set = undefined;
        out.extent = @bitCast(try r.readInt(u32, .little));
        out.columns = try r.readByte();
        const n = try r.readInt(u32, .little);
        try r.readNoEof(&out.hash);
        out.kernels = try gpa.alloc(Kernel, n);
        errdefer gpa.free(out.kernels);
        for (out.kernels) |*k| {
            for (&k.mu) |*v| v.* = @bitCast(try r.readInt(u32, .little));
            for (&k.l) |*v| v.* = @bitCast(try r.readInt(u32, .little));
            for (&k.w) |*v| v.* = @bitCast(try r.readInt(u32, .little));
        }
        return out;
    }
};

/// A kernel is nothing beyond this Mahalanobis distance squared (widths
/// squared, along whichever axis): exp(−16), a
/// tenth of a millionth — so far away a read is the entry EXACTLY (a
/// denormal exp once left 1e-42 of gold on the matrix) and the GPU
/// skips the kernel by the same rule (matryoshka's `loamRbf`).
pub const CUTOFF: f32 = 32;

/// The Mahalanobis form at q: v = Lᵀ(q − μ) and |v|².
const Mahal = struct { d: [3]f32, v: [3]f32, r2: f32 };

fn mahal(k: Kernel, q: [3]f32) Mahal {
    const d = [3]f32{ q[0] - k.mu[0], q[1] - k.mu[1], q[2] - k.mu[2] };
    const l = k.l;
    const v = [3]f32{ l[0] * d[0] + l[1] * d[1] + l[3] * d[2], l[2] * d[1] + l[4] * d[2], l[5] * d[2] };
    return .{ .d = d, .v = v, .r2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] };
}

fn gaussian(k: Kernel, q: [3]f32) f32 {
    const m = mahal(k, q);
    if (m.r2 > CUTOFF) return 0;
    return fmath.expf(-0.5 * m.r2);
}

/// The nine channels to a material through an entry: A is clamped to
/// the blend's range, B rides as it is.
pub fn compose(columns: bark.Columns, y: Channels, entry: Material) Material {
    const a = @min(1, @max(0, y[0]));
    var out = entry;
    if (columns & bark.Column.albedo.bit() != 0) inline for (0..3) |c| {
        out.albedo[c] = entry.albedo[c] * (1 - a) + y[1 + c];
    };
    if (columns & bark.Column.roughness.bit() != 0) out.roughness = entry.roughness * (1 - a) + y[4];
    if (columns & bark.Column.metallic.bit() != 0) out.metallic = entry.metallic * (1 - a) + y[5];
    if (columns & bark.Column.emissive.bit() != 0) inline for (0..3) |c| {
        out.emissive[c] = entry.emissive[c] * (1 - a) + y[6 + c];
    };
    return out;
}

/// The nine channels the volume reads at a point: the blend, and the
/// blend times the structure's columns (zero for an absent column).
pub fn target(vol: *const bark.Volume, vein: f32, q: [3]f32) Channels {
    const s = vol.sample(q);
    const a = bark.veinBlend(s.phi, vein);
    return .{ a, a * s.material.albedo[0], a * s.material.albedo[1], a * s.material.albedo[2], a * s.material.roughness, a * s.material.metallic, a * s.material.emissive[0], a * s.material.emissive[1], a * s.material.emissive[2] };
}

// ── The fit ───────────────────────────────────────────────────────────

pub const FitOptions = struct {
    kernels: u32 = 256,
    iterations: u32 = 2000,
    batch: u32 = 1024,
    /// Points drawn once for the fit, and apart for the report.
    pool: u32 = 32768,
    held_out: u32 = 4096,
    /// Adam's step; NEGATIVE climbs, the gate's mutation.
    rate: f32 = 0.02,
    seed: u64 = 0,
    /// The kernels held spherical: after every step the shape is
    /// projected back to one width (the mean log-width, no off-
    /// diagonal) — the tube gate's mutation, and the comparison.
    isotropic: bool = false,
};

pub const Report = struct {
    /// Held-out RMS over the nine channels, each normalised by its own
    /// range in the target, before and after the fit.
    rms_init: f32,
    rms_final: f32,
    /// Per channel, in the channel's own units, after the fit.
    rms_channel: Channels,
    iterations: u32,
    pool_vein: u32,
    /// The kernels' longest width over their shortest: the median and
    /// the largest — what the descent made of the shape.
    aspect_median: f32,
    aspect_max: f32,
};

pub const Fitted = struct { set: Set, report: Report };

/// A parameter vector: per kernel the centre (3), the LOG of L's
/// diagonal (3, so it stays positive), L's off-diagonal (3: l10, l20,
/// l21) and the weights (9).
const Params = struct {
    const PER: usize = KERNEL_FLOATS;
    data: []f32,

    fn mu(self: Params, i: usize) *[3]f32 {
        return self.data[i * PER ..][0..3];
    }
    fn logDiag(self: Params, i: usize) *[3]f32 {
        return self.data[i * PER + 3 ..][0..3];
    }
    fn off(self: Params, i: usize) *[3]f32 {
        return self.data[i * PER + 6 ..][0..3];
    }
    fn w(self: Params, i: usize) *[CHANNELS]f32 {
        return self.data[i * PER + 9 ..][0..CHANNELS];
    }
    fn kernel(self: Params, i: usize) Kernel {
        const a = self.logDiag(i).*;
        const o = self.off(i).*;
        return .{ .mu = self.mu(i).*, .l = .{ fmath.expf(a[0]), o[0], fmath.expf(a[1]), o[1], o[2], fmath.expf(a[2]) }, .w = self.w(i).* };
    }
};

/// The batch loss (mean squared error over the points and channels)
/// and its gradient into `grad` (same layout as the params). Exposed
/// for the gradient gate: a wrong derivative is the fit's own bug and
/// a finite difference is its witness.
pub fn lossAndGrad(params: Params, n: usize, points: []const [3]f32, targets: []const Channels, grad: []f32) f64 {
    @memset(grad, 0);
    var loss: f64 = 0;
    const inv = 1 / @as(f32, @floatFromInt(points.len));
    for (points, targets) |p, y| {
        var yhat: Channels = [_]f32{0} ** CHANNELS;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const k = params.kernel(i);
            const g = gaussian(k, p);
            inline for (0..CHANNELS) |c| yhat[c] += k.w[c] * g;
        }
        var e: Channels = undefined;
        inline for (0..CHANNELS) |c| {
            e[c] = yhat[c] - y[c];
            loss += @as(f64, e[c] * e[c]);
        }
        i = 0;
        while (i < n) : (i += 1) {
            const k = params.kernel(i);
            const m = mahal(k, p);
            if (m.r2 > CUTOFF) continue;
            const g = fmath.expf(-0.5 * m.r2);
            if (g < 1e-7) continue;
            var ew: f32 = 0; // Σ_c e_c w_c
            const gw = grad[i * Params.PER + 9 ..][0..CHANNELS];
            inline for (0..CHANNELS) |c| {
                gw[c] += 2 * e[c] * g * inv;
                ew += e[c] * k.w[c];
            }
            // ∂g/∂μ = g·(L v); ∂g/∂L_ij = −g·v_j·d_i, the diagonal through
            // its log (times L_ii).
            const l = k.l;
            const lv = [3]f32{ l[0] * m.v[0], l[1] * m.v[0] + l[2] * m.v[1], l[3] * m.v[0] + l[4] * m.v[1] + l[5] * m.v[2] };
            const gm = grad[i * Params.PER ..][0..3];
            inline for (0..3) |a| gm[a] += 2 * ew * g * lv[a] * inv;
            const gd = grad[i * Params.PER + 3 ..][0..3];
            gd[0] += -2 * ew * g * m.v[0] * m.d[0] * l[0] * inv;
            gd[1] += -2 * ew * g * m.v[1] * m.d[1] * l[2] * inv;
            gd[2] += -2 * ew * g * m.v[2] * m.d[2] * l[5] * inv;
            const go = grad[i * Params.PER + 6 ..][0..3];
            go[0] += -2 * ew * g * m.v[0] * m.d[1] * inv; // l10
            go[1] += -2 * ew * g * m.v[0] * m.d[2] * inv; // l20
            go[2] += -2 * ew * g * m.v[1] * m.d[2] * inv; // l21
        }
    }
    return loss * inv;
}

fn rmsOf(params: Params, n: usize, points: []const [3]f32, targets: []const Channels, scale: Channels, per_channel: ?*Channels) f32 {
    var acc: [CHANNELS]f64 = [_]f64{0} ** CHANNELS;
    for (points, targets) |p, y| {
        var yhat: Channels = [_]f32{0} ** CHANNELS;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const k = params.kernel(i);
            const g = gaussian(k, p);
            inline for (0..CHANNELS) |c| yhat[c] += k.w[c] * g;
        }
        inline for (0..CHANNELS) |c| {
            const e = yhat[c] - y[c];
            acc[c] += @as(f64, e * e);
        }
    }
    var total: f64 = 0;
    inline for (0..CHANNELS) |c| {
        acc[c] /= @floatFromInt(points.len);
        total += acc[c];
        if (per_channel) |pc| pc[c] = @floatCast(@sqrt(acc[c]) * scale[c]);
    }
    return @floatCast(@sqrt(total / CHANNELS));
}

/// Fit `opts.kernels` Gaussians to the volume's read through the
/// vein's blend. Targets are normalised per channel by their range in
/// the pool, so a glowing ember does not outweigh a matte grey; the
/// weights are scaled back at the end.
pub fn fit(gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, opts: FitOptions) !Fitted {
    var stream = rng.Stream.region(opts.seed, 0x5242_4600, 0);
    const n: usize = opts.kernels;
    const e = vol.extent;
    const cell = e / @as(f32, @floatFromInt(vol.res));

    // The vein's voxels, for the drawing and the seeding.
    var vein_voxels = std.ArrayListUnmanaged(u32){};
    defer vein_voxels.deinit(gpa);
    {
        const count: usize = @as(usize, vol.res) * vol.res * vol.res;
        var vi: usize = 0;
        while (vi < count) : (vi += 1) {
            if (bark.veinBlend(vol.data[vi * vol.stride], vein) > 0.05) try vein_voxels.append(gpa, @intCast(vi));
        }
    }
    const draw = struct {
        fn point(st: *rng.Stream, v: *const bark.Volume, veins: []const u32, ext: f32, cl: f32) [3]f32 {
            if (veins.len > 0 and st.unit() < 0.5) {
                const vi = veins[st.below(@intCast(veins.len))];
                const i = vi % v.res;
                const j = (vi / v.res) % v.res;
                const k = vi / (v.res * v.res);
                return .{ (@as(f32, @floatFromInt(i)) + st.unit()) * cl, (@as(f32, @floatFromInt(j)) + st.unit()) * cl, (@as(f32, @floatFromInt(k)) + st.unit()) * cl };
            }
            return .{ st.unit() * ext, st.unit() * ext, st.unit() * ext };
        }
    };

    const pool = try gpa.alloc([3]f32, opts.pool);
    defer gpa.free(pool);
    const pool_y = try gpa.alloc(Channels, opts.pool);
    defer gpa.free(pool_y);
    const held = try gpa.alloc([3]f32, opts.held_out);
    defer gpa.free(held);
    const held_y = try gpa.alloc(Channels, opts.held_out);
    defer gpa.free(held_y);
    var scale: Channels = [_]f32{1e-3} ** CHANNELS;
    for (pool, pool_y) |*p, *y| {
        p.* = draw.point(&stream, vol, vein_voxels.items, e, cell);
        y.* = target(vol, vein, p.*);
        inline for (0..CHANNELS) |c| scale[c] = @max(scale[c], @abs(y[c]));
    }
    for (held, held_y) |*p, *y| {
        p.* = draw.point(&stream, vol, vein_voxels.items, e, cell);
        y.* = target(vol, vein, p.*);
    }
    for (pool_y) |*y| inline for (0..CHANNELS) |c| {
        y[c] /= scale[c];
    };
    for (held_y) |*y| inline for (0..CHANNELS) |c| {
        y[c] /= scale[c];
    };

    // Seed the kernels on the veins, apart from one another by most of
    // a width, the target at the centre as the weight.
    const params = Params{ .data = try gpa.alloc(f32, n * Params.PER) };
    defer gpa.free(params.data);
    {
        var placed: usize = 0;
        var tries: usize = 0;
        while (placed < n and tries < 64 * n) : (tries += 1) {
            const c = if (vein_voxels.items.len > 0 and tries < 32 * n) blk: {
                const vi = vein_voxels.items[stream.below(@intCast(vein_voxels.items.len))];
                const i = vi % vol.res;
                const j = (vi / vol.res) % vol.res;
                const k = vi / (vol.res * vol.res);
                break :blk [3]f32{ (@as(f32, @floatFromInt(i)) + 0.5) * cell, (@as(f32, @floatFromInt(j)) + 0.5) * cell, (@as(f32, @floatFromInt(k)) + 0.5) * cell };
            } else [3]f32{ stream.unit() * e, stream.unit() * e, stream.unit() * e };
            var apart = true;
            var q: usize = 0;
            while (q < placed) : (q += 1) {
                const m = params.mu(q).*;
                const d2 = (c[0] - m[0]) * (c[0] - m[0]) + (c[1] - m[1]) * (c[1] - m[1]) + (c[2] - m[2]) * (c[2] - m[2]);
                if (d2 < 0.64 * vein * vein and tries < 32 * n) {
                    apart = false;
                    break;
                }
            }
            if (!apart) continue;
            params.mu(placed).* = c;
            params.logDiag(placed).* = .{ -@log(vein), -@log(vein), -@log(vein) };
            params.off(placed).* = .{ 0, 0, 0 };
            var y = target(vol, vein, c);
            inline for (0..CHANNELS) |ch| y[ch] = y[ch] / scale[ch] * 0.7;
            params.w(placed).* = y;
            placed += 1;
        }
    }

    var report = Report{ .rms_init = rmsOf(params, n, held, held_y, scale, null), .rms_final = 0, .rms_channel = undefined, .iterations = opts.iterations, .pool_vein = @intCast(vein_voxels.items.len), .aspect_median = 1, .aspect_max = 1 };

    // Adam.
    const grad = try gpa.alloc(f32, params.data.len);
    defer gpa.free(grad);
    const m1 = try gpa.alloc(f32, params.data.len);
    defer gpa.free(m1);
    const m2 = try gpa.alloc(f32, params.data.len);
    defer gpa.free(m2);
    @memset(m1, 0);
    @memset(m2, 0);
    const batch = try gpa.alloc([3]f32, opts.batch);
    defer gpa.free(batch);
    const batch_y = try gpa.alloc(Channels, opts.batch);
    defer gpa.free(batch_y);
    const b1: f32 = 0.9;
    const b2: f32 = 0.999;
    var it: u32 = 0;
    while (it < opts.iterations) : (it += 1) {
        for (batch, batch_y) |*p, *y| {
            const j = stream.below(opts.pool);
            p.* = pool[j];
            y.* = pool_y[j];
        }
        _ = lossAndGrad(params, n, batch, batch_y, grad);
        const t: f32 = @floatFromInt(it + 1);
        const c1 = 1 - std.math.pow(f32, b1, t);
        const c2 = 1 - std.math.pow(f32, b2, t);
        for (params.data, grad, m1, m2) |*x, g, *a, *b| {
            a.* = b1 * a.* + (1 - b1) * g;
            b.* = b2 * b.* + (1 - b2) * g * g;
            x.* -= opts.rate * (a.* / c1) / (@sqrt(b.* / c2) + 1e-8);
        }
        // A width never collapses below half a cell nor grows past the
        // cube: L's diagonal between 1/extent and 2/cell, its off-
        // diagonal within the same reach. Held isotropic, the shape
        // is projected back to one width.
        const lo_a = -@log(e);
        const hi_a = @log(2 / cell);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = params.logDiag(i);
            const o = params.off(i);
            if (opts.isotropic) {
                const mean = (a[0] + a[1] + a[2]) / 3;
                a.* = .{ mean, mean, mean };
                o.* = .{ 0, 0, 0 };
            }
            inline for (0..3) |c| {
                a[c] = @min(hi_a, @max(lo_a, a[c]));
                o[c] = @min(2 / cell, @max(-2 / cell, o[c]));
            }
        }
    }
    report.rms_final = rmsOf(params, n, held, held_y, scale, &report.rms_channel);

    const set = Set{ .extent = e, .columns = vol.columns, .kernels = try gpa.alloc(Kernel, n), .hash = vol.hash };
    const aspects = try gpa.alloc(f32, n);
    defer gpa.free(aspects);
    for (set.kernels, 0..) |*k, i| {
        k.* = params.kernel(i);
        inline for (0..CHANNELS) |c| k.w[c] = params.w(i).*[c] * scale[c];
        aspects[i] = k.aspect();
        report.aspect_max = @max(report.aspect_max, aspects[i]);
    }
    std.mem.sort(f32, aspects, {}, std.sort.asc(f32));
    report.aspect_median = aspects[n / 2];
    return .{ .set = set, .report = report };
}

// ── Gates ─────────────────────────────────────────────────────────────

test "a set of one kernel reads its weights back at its centre through the entry, the entry alone far away, and folds by the mirror" {
    const gpa = std.testing.allocator;
    var set = Set{ .extent = 8, .columns = bark.ALL_COLUMNS, .kernels = try gpa.alloc(Kernel, 1), .hash = undefined };
    defer set.deinit(gpa);
    set.kernels[0] = Kernel.isotropic(.{ 2, 2, 2 }, 0.5, .{ 1, 0.5, 0, 0, 0.9, 1, 0, 0, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 1), set.kernels[0].aspect(), 1e-5);
    const entry = Material{ .albedo = .{ 0, 0, 1 }, .roughness = 0.1, .metallic = 0, .emissive = .{ 0, 2, 0 } };
    const at = set.materialAt(.{ 2, 2, 2 }, 1, entry);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), at.albedo[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), at.albedo[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), at.roughness, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), at.metallic, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), at.emissive[1], 1e-6);
    const far = set.materialAt(.{ 6, 6, 6 }, 1, entry);
    try std.testing.expectEqual(entry.albedo, far.albedo);
    try std.testing.expectEqual(entry.emissive, far.emissive);
    // The mirror: −2 folds to 2, and 14 to 2.
    const m = set.materialAt(.{ -2, 14, 2 }, 1, entry);
    try std.testing.expectApproxEqAbs(at.roughness, m.roughness, 1e-6);
    // Columns the set does not model stay the entry's.
    set.columns = bark.Column.albedo.bit();
    const only = set.materialAt(.{ 2, 2, 2 }, 1, entry);
    try std.testing.expectEqual(entry.roughness, only.roughness);
    try std.testing.expectEqual(entry.metallic, only.metallic);
}

test "the fit's gradient is the finite difference's, for every kind of parameter: a centre, a log-diagonal, the three off-diagonals, a weight" {
    const gpa = std.testing.allocator;
    const n: usize = 3;
    const params = Params{ .data = try gpa.alloc(f32, n * Params.PER) };
    defer gpa.free(params.data);
    var st = rng.Stream.region(7, 1, 0);
    for (params.data) |*x| x.* = st.unit() - 0.5;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        params.logDiag(i).* = .{ 0.2 * st.unit(), 0.2 * st.unit(), 0.2 * st.unit() };
        params.off(i).* = .{ 0.3 * st.unit(), -0.2 * st.unit(), 0.1 * st.unit() };
    }
    var points: [16][3]f32 = undefined;
    var targets: [16]Channels = undefined;
    for (&points, &targets) |*p, *y| {
        p.* = .{ st.unit() * 2 - 1, st.unit() * 2 - 1, st.unit() * 2 - 1 };
        inline for (0..CHANNELS) |c| y[c] = st.unit() - 0.5;
    }
    const grad = try gpa.alloc(f32, params.data.len);
    defer gpa.free(grad);
    const scratch = try gpa.alloc(f32, params.data.len);
    defer gpa.free(scratch);
    _ = lossAndGrad(params, n, &points, &targets, grad);
    // One of each: a centre coordinate, a log-diagonal, each off-
    // diagonal, a weight.
    const probes = [_]usize{ 1 * Params.PER + 0, 2 * Params.PER + 3, 2 * Params.PER + 5, 0 * Params.PER + 6, 1 * Params.PER + 7, 2 * Params.PER + 8, 0 * Params.PER + 9 + 5 };
    for (probes) |j| {
        const h: f32 = 1e-3;
        const x0 = params.data[j];
        params.data[j] = x0 + h;
        const lp = lossAndGrad(params, n, &points, &targets, scratch);
        params.data[j] = x0 - h;
        const lm = lossAndGrad(params, n, &points, &targets, scratch);
        params.data[j] = x0;
        const fd: f32 = @floatCast((lp - lm) / (2 * h));
        try std.testing.expectApproxEqAbs(fd, grad[j], 1e-3 * @max(1, @abs(fd)));
    }
}

/// Two balls of vein in a cube, different materials: the fixture.
fn twoBalls(gpa: std.mem.Allocator) !bark.Volume {
    const res: u32 = 16;
    const cols = bark.ALL_COLUMNS;
    var v = bark.Volume{ .res = res, .extent = 16, .columns = cols, .stride = bark.strideOf(cols), .data = try gpa.alloc(f32, res * res * res * bark.strideOf(cols)), .hash = [_]u8{0} ** 32, .min = -2, .max = 2 };
    const balls = [_]struct { c: [3]f32, m: Material }{
        .{ .c = .{ 5, 5, 5 }, .m = .{ .albedo = .{ 1, 0.7, 0.3 }, .roughness = 0.25, .metallic = 1, .emissive = .{ 0, 0, 0 } } },
        .{ .c = .{ 11, 10, 9 }, .m = .{ .albedo = .{ 0.5, 0.15, 0.05 }, .roughness = 0.45, .metallic = 0, .emissive = .{ 6, 2.5, 0.7 } } },
    };
    var k: u32 = 0;
    while (k < res) : (k += 1) {
        var j: u32 = 0;
        while (j < res) : (j += 1) {
            var i: u32 = 0;
            while (i < res) : (i += 1) {
                const p = [3]f32{ @as(f32, @floatFromInt(i)) + 0.5, @as(f32, @floatFromInt(j)) + 0.5, @as(f32, @floatFromInt(k)) + 0.5 };
                const rec = v.data[v.index(i, j, k)..][0..v.stride];
                var best: f32 = -2;
                var m = balls[0].m;
                for (balls) |b| {
                    const d = @sqrt((p[0] - b.c[0]) * (p[0] - b.c[0]) + (p[1] - b.c[1]) * (p[1] - b.c[1]) + (p[2] - b.c[2]) * (p[2] - b.c[2]));
                    const phi = 2 - d; // positive inside a ball of radius 2
                    if (phi > best) {
                        best = phi;
                        m = b.m;
                    }
                }
                rec[0] = @max(-2, best);
                rec[1..4].* = m.albedo;
                rec[4] = m.roughness;
                rec[5] = m.metallic;
                rec[6..9].* = m.emissive;
            }
        }
    }
    return v;
}

test "the fit lowers the held-out error on two balls by the predicted gain, climbs when the step's sign is flipped, and survives its file" {
    const gpa = std.testing.allocator;
    var vol = try twoBalls(gpa);
    defer vol.deinit(gpa);
    var fitted = try fit(gpa, &vol, 0.9, .{ .kernels = 6, .iterations = 300, .batch = 256, .pool = 4096, .held_out = 1024, .seed = 3 });
    defer fitted.set.deinit(gpa);
    std.debug.print("\nrbf: two balls, 6 kernels, 300 iterations: held-out RMS {d:.4} → {d:.4} (gain {d:.2} against {d:.1} predicted); per channel A {d:.3}, albedo {d:.3}/{d:.3}/{d:.3}, roughness {d:.3}, metallic {d:.3}, emissive {d:.3}/{d:.3}/{d:.3}; {d} bytes\n", .{ fitted.report.rms_init, fitted.report.rms_final, fitted.report.rms_init / fitted.report.rms_final, thresholds.RBF_FIT_GAIN, fitted.report.rms_channel[0], fitted.report.rms_channel[1], fitted.report.rms_channel[2], fitted.report.rms_channel[3], fitted.report.rms_channel[4], fitted.report.rms_channel[5], fitted.report.rms_channel[6], fitted.report.rms_channel[7], fitted.report.rms_channel[8], fitted.set.bytes() });
    try std.testing.expect(fitted.report.rms_init / fitted.report.rms_final >= thresholds.RBF_FIT_GAIN);
    // Inside the gold ball the read is gold through a white entry;
    // in the matrix it is the entry.
    const entry = Material{ .albedo = .{ 0.92, 0.9, 0.86 }, .roughness = 0.15, .metallic = 0, .emissive = .{ 0, 0, 0 } };
    const gold = fitted.set.materialAt(.{ 5, 5, 5 }, 1, entry);
    try std.testing.expect(gold.metallic > 0.6);
    const base = fitted.set.materialAt(.{ 13, 3, 13 }, 1, entry);
    try std.testing.expect(base.metallic < 0.1 and @abs(base.roughness - entry.roughness) < 0.05);
    // The mutation: ascent.
    var climbed = try fit(gpa, &vol, 0.9, .{ .kernels = 6, .iterations = 100, .batch = 256, .pool = 4096, .held_out = 1024, .seed = 3, .rate = -0.02 });
    defer climbed.set.deinit(gpa);
    try std.testing.expect(climbed.report.rms_final > climbed.report.rms_init);
    // The file.
    const path = "zig-cache-rbf-gate.lrbf";
    try fitted.set.write(path);
    defer std.fs.cwd().deleteFile(path) catch {};
    var back = try Set.read(gpa, path);
    defer back.deinit(gpa);
    try std.testing.expectEqual(fitted.set.kernels.len, back.kernels.len);
    try std.testing.expectEqual(fitted.set.kernels[2], back.kernels[2]);
    try std.testing.expectEqual(fitted.set.columns, back.columns);
}

/// One straight tube of gold along x through a cube: the fixture an
/// ellipsoid should fit and a sphere cannot.
fn oneTube(gpa: std.mem.Allocator) !bark.Volume {
    const res: u32 = 16;
    const cols = bark.ALL_COLUMNS;
    var v = bark.Volume{ .res = res, .extent = 16, .columns = cols, .stride = bark.strideOf(cols), .data = try gpa.alloc(f32, res * res * res * bark.strideOf(cols)), .hash = [_]u8{0} ** 32, .min = -2, .max = 2 };
    const gold = Material{ .albedo = .{ 1, 0.7, 0.3 }, .roughness = 0.25, .metallic = 1, .emissive = .{ 0, 0, 0 } };
    var k: u32 = 0;
    while (k < res) : (k += 1) {
        var j: u32 = 0;
        while (j < res) : (j += 1) {
            var i: u32 = 0;
            while (i < res) : (i += 1) {
                const p = [3]f32{ @as(f32, @floatFromInt(i)) + 0.5, @as(f32, @floatFromInt(j)) + 0.5, @as(f32, @floatFromInt(k)) + 0.5 };
                const rec = v.data[v.index(i, j, k)..][0..v.stride];
                // A capsule from (2, 8, 8) to (14, 8, 8), radius 1.5.
                const sx = @min(14, @max(2, p[0]));
                const d = @sqrt((p[0] - sx) * (p[0] - sx) + (p[1] - 8) * (p[1] - 8) + (p[2] - 8) * (p[2] - 8));
                rec[0] = @max(-2, 1.5 - d);
                rec[1..4].* = gold.albedo;
                rec[4] = gold.roughness;
                rec[5] = gold.metallic;
                rec[6..9].* = gold.emissive;
            }
        }
    }
    return v;
}

test "a tube is an ellipsoid: two anisotropic kernels fit one straight vein by the predicted gain over two held spherical, and stretch along it" {
    const gpa = std.testing.allocator;
    var vol = try oneTube(gpa);
    defer vol.deinit(gpa);
    const opts = FitOptions{ .kernels = 2, .iterations = 400, .batch = 256, .pool = 4096, .held_out = 1024, .seed = 5 };
    var free = try fit(gpa, &vol, 0.9, opts);
    defer free.set.deinit(gpa);
    var iso_opts = opts;
    iso_opts.isotropic = true;
    var held = try fit(gpa, &vol, 0.9, iso_opts);
    defer held.set.deinit(gpa);
    std.debug.print("\nrbf: one tube, two kernels: anisotropic held-out RMS {d:.4} (aspect median {d:.2}, max {d:.2}), spherical {d:.4} (aspect {d:.2}); gain {d:.2} against {d:.1} predicted\n", .{ free.report.rms_final, free.report.aspect_median, free.report.aspect_max, held.report.rms_final, held.report.aspect_max, held.report.rms_final / free.report.rms_final, thresholds.RBF_ANISO_GAIN });
    try std.testing.expect(held.report.rms_final / free.report.rms_final >= thresholds.RBF_ANISO_GAIN);
    // Spherical is spherical; free is stretched, and along x: the
    // kernel is wider three units along the tube than across it.
    try std.testing.expect(held.report.aspect_max < 1.001);
    try std.testing.expect(free.report.aspect_median > 1.5);
    for (free.set.kernels) |k| {
        const along = gaussian(k, .{ k.mu[0] + 3, k.mu[1], k.mu[2] });
        const across = gaussian(k, .{ k.mu[0], k.mu[1] + 3, k.mu[2] });
        try std.testing.expect(along > across);
    }
}
