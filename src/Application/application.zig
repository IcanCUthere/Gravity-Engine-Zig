const std = @import("std");
const flecs = @import("zflecs");
const tracy = @import("ztracy");
const core = @import("core");

const Modules = @import("modules");

pub fn init() !void {
    const tracy_zone = tracy.ZoneNC(@src(), "Initialization", 0x00_ff_ff_00);
    defer tracy_zone.End();

    Application.Instance.scene = flecs.init();

    try loadModules();
}

pub fn deinit() !void {
    const tracy_zone = tracy.ZoneNC(@src(), "Deinitialization", 0x00_ff_ff_00);
    defer tracy_zone.End();

    _ = flecs.fini(Application.Instance.scene);

    try unloadModules();
}

pub fn run() !void {
    const tracy_zone = tracy.ZoneNC(@src(), "Running", 0x00_ff_ff_00);
    defer tracy_zone.End();

    while (Application.Instance.shouldRun) {
        tracy.FrameMarkStart("Frame");

        _ = flecs.progress(Application.Instance.scene, 0);

        tracy.FrameMarkEnd("Frame");
    }
}

fn moduleLoaded(name: []const u8) bool {
    const modules = &Application.Instance.modules;

    for (modules.items) |m| {
        if (std.mem.eql(u8, name, m)) {
            return true;
        }
    }

    return false;
}

fn loadModules() !void {
    var modules = &Application.Instance.modules;
    const scene = Application.Instance.scene;

    inline for (Modules.loadOrder) |M| {
        std.log.info("Loading Module {s}", .{M.name});

        for (M.dependencies) |d| {
            if (!moduleLoaded(d)) {
                std.log.err("Module {s} depends on module {s}, but was not loaded.", .{ M.name, d });
                return error.DependencyNotLoaded;
            }
        }

        try M.init(scene, &Application.Instance.shouldRun);
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

    Application.Instance.modules.deinit();
}

const Application = struct {
    const Self = @This();
    var Instance: Self = Self{};

    shouldRun: bool = true,
    modules: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(core.mem.ha),
    scene: *flecs.world_t = undefined,
};
