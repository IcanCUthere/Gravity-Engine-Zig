const util = @import("util");
const mem = util.mem;
const ArrayList = util.ArrayList;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const builtin = @import("builtin");

const Modules = @import("Modules/modules.zig");

pub const GravityEngine = struct {
    const Self = @This();
    const ModuleArray = ArrayList([]const u8);

    var modules: ModuleArray = ModuleArray.init(util.mem.heap);
    var scene: *flecs.world_t = undefined;

    pub fn init() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Initialization", 0x00_ff_ff_00);
        defer tracy_zone.End();

        scene = flecs.init();

        try loadModules();
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinitialization", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try unloadModules();

        _ = flecs.fini(scene);

        if (builtin.mode == .Debug) {
            util.log.print("Bytes allocated on heap after cleanup: {d}", .{util.mem.heapAllocator.total_requested_bytes}, .Info, .Abstract, .{ .Allocations = true });
            util.log.print("Bytes allocated in fixedBuffer after cleanup: {d}", .{util.mem.fixedBufferAllocator.total_requested_bytes}, .Info, .Abstract, .{ .Allocations = true });
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

    fn isModuleLoaded(name: []const u8) bool {
        for (modules.items) |m| {
            if (mem.eql(u8, name, m)) {
                return true;
            }
        }

        return false;
    }

    fn loadModules() !void {
        inline for (Modules.loadOrder) |M| {
            util.log.print("Loading Module {s}", .{M.name}, .Info, .Abstract, .{ .Modules = true });

            if (isModuleLoaded(M.name)) {
                util.log.print("Module {s} already loaded", .{M.name}, .Critical, .Abstract, .{ .Modules = true });
            }

            for (M.dependencies) |d| {
                if (!isModuleLoaded(d)) {
                    util.log.print("Module {s} depends on module {s}, but was not loaded", .{ M.name, d }, .Critical, .Abstract, .{ .Modules = true });
                    return error.DependencyNotLoaded;
                }
            }

            try M.init(scene);
            try modules.append(M.name);
        }
    }

    fn unloadModules() !void {
        {
            comptime var i = Modules.loadOrder.len;
            inline while (i > 0) {
                i -= 1;

                util.log.print("Preparing to unload Module {s}", .{Modules.loadOrder[i].name}, .Info, .Abstract, .{ .Modules = true });
                try Modules.loadOrder[i].preDeinit();
            }
        }

        {
            comptime var i = Modules.loadOrder.len;
            inline while (i > 0) {
                i -= 1;

                util.log.print("Unloading Module {s}", .{Modules.loadOrder[i].name}, .Info, .Abstract, .{ .Modules = true });
                try Modules.loadOrder[i].deinit();
            }
        }

        modules.deinit();
    }
};
