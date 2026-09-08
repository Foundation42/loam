//! loam — sparse field dynamics. Things grow in it; it does not make the oak.
//!
//! The library does not generate objects. It evolves spatial state.
//! Objects, organisms, materials and environments are interpretations of
//! persistent, interacting fields; a renderer merely asks what those
//! fields mean to a ray (spec §24). Nothing here emits a mesh and nothing
//! here knows what a triangle is.
//!
//! What this library owns: the 20-bit dyadic lattice everything is
//! addressed on (`lattice.zig`), bricks with popcount-packed channel
//! planes (`brick.zig`, `channel.zig`), the 8-way tree with conservative
//! summaries and its immutable snapshots (`tree.zig`, `summary.zig`), the
//! update cycle — gather, operate, region-local buffers, commit, seams,
//! publish (`world.zig`, `update.zig`), the standard operators
//! (`operators.zig`), Lagrangian fronts carrying loop-loft's ring
//! (`front.zig`), a ray cursor over the tree (`ray.zig`), the guards
//! (`guards.zig`), the dump (`dump.zig`) and the seedbed's authoring verbs
//! (`seedbed.zig`). What it borrows: common's one JobSystem, struple for
//! every byte that leaves memory.
//!
//!     var world = try loam.World.init(gpa, .{ .seed = 7 });
//!     defer world.deinit();
//!     try loam.seedbed.blob(&world, .light, .{ 0, 40, 0 }, 30, 1.0, 0);
//!     try loam.seedbed.plant(&world, .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{});
//!     var t: u64 = 0;
//!     while (t < 60) : (t += 1) try world.step(.{ .frame = t, .time_ns = t * std.time.ns_per_s }, null);
//!     const hash = world.published().rootHash();

const std = @import("std");

pub const lattice = @import("lattice.zig");
pub const channel = @import("channel.zig");
pub const rng = @import("rng.zig");
pub const fmath = @import("fmath.zig");
pub const thresholds = @import("thresholds.zig");
pub const summary = @import("summary.zig");
pub const brick = @import("brick.zig");
pub const tree = @import("tree.zig");
pub const front = @import("front.zig");
pub const update = @import("update.zig");
pub const world = @import("world.zig");
pub const operators = @import("operators.zig");
pub const ray = @import("ray.zig");
pub const guards = @import("guards.zig");
pub const dump = @import("dump.zig");
pub const seedbed = @import("seedbed.zig");
pub const bark = @import("bark.zig");
pub const rbf = @import("rbf.zig");
/// MARL-0: local online RBF learning (docs/MARL_CAMPAIGN.md). Not the sim
/// path, not a channel, not in any hash — `rbf`'s standing.
pub const marl = @import("marl.zig");
pub const marble = @import("marble.zig");
pub const cache = @import("cache.zig");
/// MARL-19: the milk round — a schedule revealed in STAGES, and whether a
/// consolidation refunds the capacity that history bought. Noiseless by
/// design, so it cannot borrow MARL-18's variance explanation.
pub const milk = @import("milk.zig");

// The working surface, re-exported flat.
pub const Domain = lattice.Domain;
pub const Key = lattice.Key;
pub const Channel = channel.Channel;
pub const Mask = channel.Mask;
pub const Brick = brick.Brick;
pub const Snapshot = tree.Snapshot;
pub const Summary = summary.Summary;
pub const World = world.World;
pub const Now = world.Now;
pub const Operator = operators.Operator;
pub const Front = front.Front;
pub const FrontParams = front.Params;
pub const RayQuery = ray.Query;
pub const Cursor = ray.Cursor;

test {
    _ = lattice;
    _ = channel;
    _ = rng;
    _ = fmath;
    _ = summary;
    _ = brick;
    _ = tree;
    _ = front;
    _ = update;
    _ = world;
    _ = operators;
    _ = ray;
    _ = guards;
    _ = dump;
    _ = seedbed;
    _ = bark;
    _ = rbf;
    _ = marl;
    _ = marble;
    _ = cache;
    _ = milk;
    _ = @import("tests.zig");
}
