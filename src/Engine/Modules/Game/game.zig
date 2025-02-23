const util = @import("util");
const fmt = util.fmt;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");
const graphics = @import("GraphicsModule");

const CameraController = @import("Components/CameraController.zig").CameraController;

pub const Game = struct {
    pub const name: []const u8 = "game";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var _scene: *flecs.world_t = undefined;

    const components = [_]type{
        CameraController,
    };

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        inline for (components) |comp| {
            comp.register(scene);
        }

        _ = flecs.set(scene, graphics.Graphics.mainCamera, graphics.Camera, try graphics.Camera.init(
            45.0,
            1.0,
            1.0,
            10000.0,
        ));

        _ = flecs.set(scene, graphics.Graphics.mainCamera, CameraController, .{});

        const prefab = try graphics.Model.new(
            "Helmet",
            "resources/models/DamagedHelmet.glb",
            graphics.Graphics.baseMaterial,
        );

        const max = 5;

        for (0..max) |x| {
            for (0..max) |y| {
                for (0..max) |z| {
                    const num = (z + (y * max) + (x * max * max)) * 10;
                    const res = try fmt.allocPrint(util.mem.heap, "Damaged helmet{d}", .{num});

                    res[res.len - 1] = 0;

                    _ = try graphics.ModelInstance.new(
                        @ptrCast(res.ptr),
                        prefab,
                        .{ @floatFromInt(x * 5), @floatFromInt(y * 5), @floatFromInt(z * 5), 1.0 },
                    );

                    util.mem.heap.free(res);
                }
            }
        }
    }

    pub fn preDeinit() !void {}

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try util.module.cleanUpComponent(comp, _scene);
        }
    }
};
