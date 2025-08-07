const util = @import("util");
const mem = util.mem;
const ArrayList = util.ArrayList;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const builtin = @import("builtin");

const Modules = @import("Modules/modules.zig");

const std = @import("std");

const releaseOrder = [_]type{};

const editOrder = [_]type{};

const needsEditor = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
const loadOrder = if (needsEditor) editOrder else releaseOrder;

pub const GravityEngine = struct {
    const Self = @This();

    var scene: *flecs.world_t = undefined;

    pub fn init() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Initialization", 0x00_ff_ff_00);
        defer tracy_zone.End();

        scene = flecs.init();

        try Modules.loadDLLs(scene);
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinitialization", 0x00_ff_ff_00);
        defer tracy_zone.End();

        //try Modules.stopStatic(&loadOrder);
        //try Modules.unloadStatic(&loadOrder);

        _ = flecs.fini(scene);

        if (builtin.mode == .Debug) {
            util.log.print(
                "Bytes allocated on heap after cleanup: {d}",
                .{util.mem.heapAllocator.total_requested_bytes},
                .Info,
                .Abstract,
                .{ .Allocations = true },
            );

            util.log.print(
                "Bytes allocated in fixedBuffer after cleanup: {d}",
                .{util.mem.fixedBufferAllocator.total_requested_bytes},
                .Info,
                .Abstract,
                .{ .Allocations = true },
            );
        }
    }

    pub fn run() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Running", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var shouldRun: bool = true;
        while (shouldRun) {
            tracy.FrameMarkStart("Frame");

            shouldRun = flecs.progress(scene, 0);

            tracy.FrameMarkEnd("Frame");
        }
    }
};
