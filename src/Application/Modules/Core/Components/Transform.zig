const flecs = @import("zflecs");
const math = @import("core").math;

pub const Transform = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    worldPosition: math.Vec3 = math.videntity(),
    worldRotation: math.Quat = math.qidentity(),
    worldScale: math.Vec3 = math.videntity(),

    localPosition: math.Vec3 = math.videntity(),
    localRotation: math.Quat = math.qidentity(),
    localScale: math.Vec3 = math.videntity(),

    transformMatrix: math.Mat = math.identity(),

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "SceneComponent");
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);
    }

    pub fn init() Self {}

    pub fn deinit(_: Self) void {}

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn getLocalRightVector(self: Self) math.Vec3 {
        return math.vec4ToVec3(math.mul(math.matFromQuat(self.localRotation), math.Vec{ 1.0, 0.0, 0.0, 0.0 }));
    }

    pub fn getLocalUpVector(self: Self) math.Vec3 {
        return math.vec4ToVec3(math.mul(math.matFromQuat(self.localRotation), math.Vec{ 0.0, 1.0, 0.0, 0.0 }));
    }

    pub fn getLocalForwardVector(self: Self) math.Vec3 {
        return math.vec4ToVec3(math.mul(math.matFromQuat(self.localRotation), math.Vec{ 0.0, 0.0, 1.0, 0.0 }));
    }
};
