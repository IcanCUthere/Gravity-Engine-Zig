const util = @import("util");
const math = util.math;

const flecs = @import("zflecs");

pub const Transform = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    worldPosition: math.Vec3 = math.videntity(),
    worldRotation: math.Vec3 = math.videntity(),
    worldScale: math.Vec3 = math.videntity(),

    localPosition: math.Vec3 = math.videntity(),
    localRotation: math.Vec3 = math.videntity(),
    localScale: math.Vec3 = math.videntity(),

    translationMatrix: math.Mat = math.identity(),
    rotationMatrix: math.Mat = math.identity(),

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "TransformPrefab");
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);
    }

    pub fn init() Self {}

    pub fn deinit(_: Self) void {}

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn getLocalRightVector(self: Self) math.Vec3 {
        return math.vec4ToVec3(math.mulV(
            math.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.Vec{ 1, 0, 0, 0 },
        ));
    }

    pub fn getLocalUpVector(self: Self) math.Vec3 {
        return math.vec4ToVec3(math.mulV(
            math.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.Vec{ 0, 1, 0, 0 },
        ));
    }

    pub fn getLocalForwardVector(self: Self) math.Vec3 {
        return math.vec4ToVec3(math.mulV(
            math.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.Vec{ 0, 0, 1, 0 },
        ));
    }

    pub fn getLocalRightVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.Vec3 {
        return math.vec4ToVec3(
            math.mulV(
                getLockedRotation(
                    self.localRotation,
                    withPitch,
                    withYaw,
                    withRoll,
                ),
                math.vec3ToVec4(.{ 1, 0, 0 }),
            ),
        );
    }

    pub fn getLocalUpVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.Vec3 {
        return math.vec4ToVec3(
            math.mulV(
                getLockedRotation(
                    self.localRotation,
                    withPitch,
                    withYaw,
                    withRoll,
                ),
                math.vec3ToVec4(.{ 0, 1, 0 }),
            ),
        );
    }

    pub fn getLocalForwardVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.Vec3 {
        return math.vec4ToVec3(
            math.mulV(
                getLockedRotation(
                    self.localRotation,
                    withPitch,
                    withYaw,
                    withRoll,
                ),
                math.vec3ToVec4(.{ 0, 0, 1 }),
            ),
        );
    }

    pub fn getWorldRightVector() math.Vec3 {
        return .{ 1, 0, 0 };
    }

    pub fn getWorldUpVector() math.Vec3 {
        return .{ 0, 1, 0 };
    }

    pub fn getWorldForwardVector() math.Vec3 {
        return .{ 0, 0, 1 };
    }

    pub fn getLockedRotation(rot: math.Vec3, withPitch: bool, withYaw: bool, withRoll: bool) math.Mat {
        var lockedMat = math.identity();

        if (withPitch) {
            const pitchQ = math.quatFromRollPitchYawV(.{ math.degreesToRadians(rot[0]), 0, 0, 0 });
            lockedMat = math.matFromQuat(pitchQ);
        }

        if (withYaw) {
            const yawQ = math.quatFromRollPitchYawV(.{ 0, math.degreesToRadians(rot[1]), 0, 0 });
            lockedMat = math.mulV(math.matFromQuat(yawQ), lockedMat);
        }

        if (withRoll) {
            const rollQ = math.quatFromRollPitchYawV(.{ 0, 0, math.degreesToRadians(rot[2]), 0 });
            lockedMat = math.mulV(lockedMat, math.matFromQuat(rollQ));
        }

        return lockedMat;
    }
};
