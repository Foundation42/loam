//! Shared frozen-shape trajectory/sensitivity engine. Isotropic kernels
//! on the z=.5 plane; the shape provider fixes geometry at compile time.
const marl = @import("marl.zig");
pub fn Fixed(comptime count: usize, comptime getShape: fn (usize) marl.Shape) type {
    return struct {
        pub fn Basis(comptime T: type) type {
            return struct { g: [2]T, h: [2][2]T };
        }
        pub fn basis(comptime T: type, i: usize, x: [2]T) Basis(T) {
            const sh = getShape(i);
            const inv: T = @as(T, sh.l[0]) * @as(T, sh.l[0]);
            const d = [2]T{ x[0] - @as(T, sh.mu[0]), x[1] - @as(T, sh.mu[1]) };
            const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
            if (r2 > marl.CUTOFF) return .{ .g = .{ 0, 0 }, .h = .{ .{ 0, 0 }, .{ 0, 0 } } };
            const phi = @exp(-0.5 * r2);
            var b: Basis(T) = undefined;
            for (0..2) |a| {
                b.g[a] = -phi * inv * d[a];
                for (0..2) |c| b.h[a][c] = phi * (inv * inv * d[a] * d[c] - if (a == c) inv else @as(T, 0));
            }
            return b;
        }

        pub fn State(comptime T: type) type {
            return struct { x: [2]T, s: [count][2]T = .{.{ 0, 0 }} ** count };
        }
        fn rhs(comptime T: type, w: [count]T, z: State(T), omega: T, omit_position: bool) State(T) {
            var out = State(T){ .x = .{ -omega * (z.x[1] - 0.5), omega * (z.x[0] - 0.5) } };
            var jac = [2][2]T{ .{ 0, -omega }, .{ omega, 0 } };
            var b: [count]Basis(T) = undefined;
            for (0..count) |i| {
                b[i] = basis(T, i, z.x);
                for (0..2) |a| {
                    out.x[a] -= w[i] * b[i].g[a];
                    for (0..2) |c| jac[a][c] -= w[i] * b[i].h[a][c];
                }
            }
            for (0..count) |i| for (0..2) |a| {
                out.s[i][a] = -b[i].g[a];
                if (!omit_position) for (0..2) |c| {
                    out.s[i][a] += jac[a][c] * z.s[i][c];
                };
            };
            return out;
        }
        fn add(comptime T: type, z: State(T), dz: State(T), dt: T) State(T) {
            var out = z;
            for (0..2) |a| {
                out.x[a] += dt * dz.x[a];
                for (0..count) |i| out.s[i][a] += dt * dz.s[i][a];
            }
            return out;
        }
        pub fn trajectory(comptime T: type, w: [count]T, x: [2]T, dt: T, steps: u32, omega: T, omit_position: bool) State(T) {
            var z = State(T){ .x = x };
            for (0..steps) |_| z = advance(T, w, z, dt, omega, omit_position);
            return z;
        }

        pub fn advance(comptime T: type, w: [count]T, z: State(T), dt: T, omega: T, omit_position: bool) State(T) {
            const mid = add(T, z, rhs(T, w, z, omega, omit_position), dt / 2);
            return add(T, z, rhs(T, w, mid, omega, omit_position), dt);
        }
    };
}
