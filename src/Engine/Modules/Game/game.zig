const util = @import("util");
const fmt = util.fmt;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");
const graphics = @import("GraphicsModule");

const CameraController = @import("Components/CameraController.zig").CameraController;

pub const name: [*:0]const u8 = "game";
pub const dependencies = [_][*:0]const u8{ "core", "graphics" };

comptime {
    // We only want to export functions in from the actual module
    // Name clashes with other importet modules occur otherwise
    if (util.mem.eql(u8, util.mem.sliceTo(@import("root").name, 0), util.mem.sliceTo(name, 0))) {
        @export(&getName, .{ .name = "getName", .linkage = .strong });
        @export(&getDependencies, .{ .name = "getDependencies", .linkage = .strong });
        @export(&getDependencyCount, .{ .name = "getDependencyCount", .linkage = .strong });

        @export(&load, .{ .name = "load", .linkage = .strong });
        @export(&start, .{ .name = "start", .linkage = .strong });
        @export(&stop, .{ .name = "stop", .linkage = .strong });
        @export(&unload, .{ .name = "unload", .linkage = .strong });
    }
}

var _scene: *flecs.world_t = undefined;
const components = [_]type{
    CameraController,
};

fn getName() callconv(.c) [*:0]const u8 {
    return name;
}

fn getDependencies() callconv(.c) [*]const [*:0]const u8 {
    return (&dependencies).ptr;
}

fn getDependencyCount() callconv(.c) usize {
    return dependencies.len;
}

fn load(scene: *flecs.world_t) callconv(.c) bool {
    const tracy_zone = tracy.ZoneNC(@src(), "Game Module Init", 0x00_ff_ff_00);
    defer tracy_zone.End();

    _ = flecs.init();
    _scene = scene;

    util.module.registerComponents(_scene, &components) catch return false;

    _ = flecs.set(scene, graphics.mainCamera, CameraController, .{});

    const prefab = graphics.Model.new(
        "Helmet",
        "resources/models/DamagedHelmet.glb",
        graphics.baseMaterial,
    ) catch return false;

    const max = 5;

    for (0..max) |x| {
        for (0..max) |y| {
            for (0..max) |z| {
                const num = (z + (y * max) + (x * max * max)) * 10;
                const res = fmt.allocPrint(
                    util.mem.heap,
                    "Damaged helmet{d}",
                    .{num},
                ) catch return false;

                res[res.len - 1] = 0;

                _ = graphics.ModelEntity.init(
                    scene,
                    @ptrCast(res.ptr),
                    prefab,
                    .{ @floatFromInt(x * 5), @floatFromInt(y * 5), @floatFromInt(z * 5), 1.0 },
                ) catch return false;

                util.mem.heap.free(res);
            }
        }
    }

    return true;
}

fn start() callconv(.c) bool {
    return true;
}

fn stop() callconv(.c) bool {
    return true;
}

fn unload() callconv(.c) bool {
    const tracy_zone = tracy.ZoneNC(@src(), "Game Module Deinit", 0x00_ff_ff_00);
    defer tracy_zone.End();

    util.module.unregisterComponents(_scene, &components) catch return false;

    return true;
}
