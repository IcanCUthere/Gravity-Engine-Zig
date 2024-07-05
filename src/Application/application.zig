const std = @import("std");
const flecs = @import("zflecs");
const tracy = @import("ztracy");
const core = @import("core");

const Modules = @import("modules");

pub const Application = struct {
    const Self = @This();
    const ModuleArray = std.ArrayList([]const u8);

    var modules: ModuleArray = ModuleArray.init(core.mem.ha);
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
            if (std.mem.eql(u8, name, m)) {
                return true;
            }
        }

        return false;
    }

    fn loadModules() !void {
        inline for (Modules.loadOrder) |M| {
            std.log.info("Loading Module {s}", .{M.name});

            for (M.dependencies) |d| {
                if (!isModuleLoaded(d)) {
                    std.log.err("Module {s} depends on module {s}, but was not loaded.", .{ M.name, d });
                    return error.DependencyNotLoaded;
                }
            }

            try M.init(scene);
            try modules.append(M.name);
        }
    }

    fn unloadModules() !void {
        comptime var i = Modules.loadOrder.len;
        inline while (i > 0) {
            i -= 1;

            std.log.info("Unloading Module {s}", .{Modules.loadOrder[i].name});
            try Modules.loadOrder[i].deinit();
        }

        modules.deinit();
    }
};
