const flecs = @import("zflecs");
const math = @import("core").math;
const tracy = @import("ztracy");
const std = @import("std");
const core = @import("core");

const coreM = @import("CoreModule");
const graphicsM = @import("GraphicsModule");

const CameraController = @import("Components/CameraController.zig").CameraController;

const shaders = @import("shaders");

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

        _ = flecs.set(scene, graphicsM.Graphics.mainCamera, graphicsM.Camera, try graphicsM.Camera.init(
            45.0,
            1.0,
            1.0,
            10000.0,
        ));

        _ = flecs.set(scene, graphicsM.Graphics.mainCamera, CameraController, .{});

        const material = try graphicsM.Material.new(
            "BaseMaterial",
            &shaders.shader_vert,
            &shaders.shader_frag,
        );

        const prefab = try graphicsM.Model.new(
            "Helmet",
            "resources/DamagedHelmet.glb",
            material,
        );

        const max = 5;

        for (0..max) |x| {
            for (0..max) |y| {
                for (0..max) |z| {
                    const num = (z + (y * max) + (x * max * max)) * 10;
                    const res = try std.fmt.allocPrint(core.mem.heap, "Damaged helmet{d}", .{num});

                    res[res.len - 1] = 0;

                    _ = try graphicsM.ModelInstance.new(
                        @ptrCast(res.ptr),
                        prefab,
                        .{ @floatFromInt(x * 5), @floatFromInt(y * 5), @floatFromInt(z * 5) },
                    );

                    //std.log.info("CREATED {s} {d}", .{ res, num });
                    core.mem.heap.free(res);
                }
            }
        }
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Game Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try core.moduleHelpers.cleanUpComponent(comp, _scene);
        }
    }
};
