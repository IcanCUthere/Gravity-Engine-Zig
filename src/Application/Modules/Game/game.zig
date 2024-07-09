const flecs = @import("zflecs");
const math = @import("core").math;
const tracy = @import("ztracy");
const std = @import("std");
const core = @import("core");

const coreM = @import("CoreModule");
const graphicsM = @import("GraphicsModule");

const CameraController = @import("Components/CameraController.zig").CameraController;

pub const Game = struct {
    pub const name: []const u8 = "game";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var _scene: *flecs.world_t = undefined;

    const components = [_]type{
        CameraController,
    };

    var model1: flecs.entity_t = undefined;
    var model2: flecs.entity_t = undefined;

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        inline for (components) |comp| {
            comp.register(scene);
        }

        _ = flecs.set(scene, graphicsM.Graphics.mainCamera, graphicsM.Camera, try graphicsM.Camera.init(
            45.0,
            1.0,
            1.0,
            10000.0,
        ));
        _ = flecs.set(scene, graphicsM.Graphics.mainCamera, CameraController, .{});

        model1 = try graphicsM.Model.new(
            "DamagedHelmet1",
            "resources/DamagedHelmet.glb",
            .{ 0, 0, 0 },
        );
        model2 = try graphicsM.Model.new(
            "DamagedHelmet2",
            "resources/DamagedHelmet.glb",
            .{ 5, 0, 0 },
        );
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try core.moduleHelpers.cleanUpComponent(comp, _scene);
        }
    }
};
