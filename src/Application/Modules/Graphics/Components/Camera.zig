const flecs = @import("zflecs");
const math = @import("core").math;
const coreM = @import("CoreModule");

const std = @import("std");

pub const Camera = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    projectionMatrix: math.Mat = math.identity(),

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "CameraComponent");
        flecs.add_pair(scene, Prefab, flecs.IsA, coreM.Transform.getPrefab());
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn setProjectionMatrix(self: *Self, FOWinDeg: f32, aspectRatio: f32, near: f32, far: f32) void {
        self.projectionMatrix = math.perspectiveFovRh(std.math.degreesToRadians(FOWinDeg), aspectRatio, near, far);
    }
};
