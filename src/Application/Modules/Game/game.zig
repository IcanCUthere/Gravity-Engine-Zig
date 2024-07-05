const flecs = @import("zflecs");
const math = @import("core").math;
const tracy = @import("ztracy");
const std = @import("std");

const coreM = @import("CoreModule");
const graphicsM = @import("GraphicsModule");

const CameraController = @import("Components/CameraController.zig").CameraController;

pub const Game = struct {
    pub const name: []const u8 = "game";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var _scene: *flecs.world_t = undefined;

    var mesh: flecs.entity_t = undefined;

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        _ = CameraController.register(scene);

        _ = flecs.set(scene, graphicsM.Graphics.mainCamera, graphicsM.Camera, graphicsM.Camera{
            .projectionMatrix = math.perspectiveFovRh(std.math.degreesToRadians(45.0), 1.0, 1, 10000.0),
        });
        _ = flecs.set(scene, graphicsM.Graphics.mainCamera, CameraController, .{});

        mesh = flecs.new_entity(scene, "DamagedHelmet");
        flecs.add_pair(scene, mesh, flecs.IsA, coreM.Mesh.getPrefab());
        _ = flecs.set(scene, mesh, coreM.Mesh, .{ .path = "resources/DamagedHelmet.glb" });
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        flecs.delete(_scene, mesh);
    }
};
