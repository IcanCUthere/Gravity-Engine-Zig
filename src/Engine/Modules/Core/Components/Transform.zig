const util = @import("util");
const math = util.math;

const flecs = @import("zflecs");

pub const Transform = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    worldPosition: math.simd.Vec = math.videntity(),
    worldRotation: math.simd.Vec = math.videntity(),
    worldScale: math.simd.Vec = math.videntity(),

    localPosition: math.simd.Vec = math.videntity(),
    localRotation: math.simd.Vec = math.videntity(),
    localScale: math.simd.Vec = math.videntity(),

    translationMatrix: math.simd.Mat = math.simd.identity(),
    rotationMatrix: math.simd.Mat = math.simd.identity(),

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "TransformPrefab");
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);
    }

    pub fn init() Self {}

    pub fn deinit(_: Self) !void {}

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn getLocalRightVector(self: Self) math.Vec {
        return math.simd.vec4ToVec3(math.simd.mul(
            math.simd.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.simd.Vec{ 1, 0, 0, 0 },
        ));
    }

    pub fn getLocalUpVector(self: Self) math.simd.Vec {
        return math.simd.vec4ToVec3(math.simd.mul(
            math.simd.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.simd.Vec{ 0, 1, 0, 0 },
        ));
    }

    pub fn getLocalForwardVector(self: Self) math.Vec {
        return math.simd.mul(
            math.simd.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.simd.Vec{ 0, 0, 1, 0 },
        );
    }

    pub fn getLocalRightVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.simd.Vec {
        return math.simd.mul(
            getLockedRotation(
                self.localRotation,
                withPitch,
                withYaw,
                withRoll,
            ),
            math.simd.Vec{ 1, 0, 0, 1 },
        );
    }

    pub fn getLocalUpVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.Vec {
        return math.mulV(
            getLockedRotation(
                self.localRotation,
                withPitch,
                withYaw,
                withRoll,
            ),
            math.Vec{ 0, 1, 0, 1 },
        );
    }

    pub fn getLocalForwardVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.simd.Vec {
        return math.simd.mul(
            getLockedRotation(
                self.localRotation,
                withPitch,
                withYaw,
                withRoll,
            ),
            math.simd.Vec{ 0, 0, 1, 1 },
        );
    }

    pub fn getWorldRightVector() math.simd.Vec {
        return math.simd.Vec{ 1, 0, 0, 0 };
    }

    pub fn getWorldUpVector() math.simd.Vec {
        return math.simd.Vec{ 0, 1, 0, 0 };
    }

    pub fn getWorldForwardVector() math.simd.Vec {
        return math.simd.Vec{ 0, 0, 1, 0 };
    }

    pub fn getLockedRotation(rot: math.simd.Vec, withPitch: bool, withYaw: bool, withRoll: bool) math.simd.Mat {
        var lockedMat = math.simd.identity();

        if (withPitch) {
            const pitchQ = math.simd.quatFromRollPitchYawV(.{ math.degreesToRadians(rot[0]), 0, 0, 0 });
            lockedMat = math.simd.matFromQuat(pitchQ);
        }

        if (withYaw) {
            const yawQ = math.simd.quatFromRollPitchYawV(.{ 0, math.degreesToRadians(rot[1]), 0, 0 });
            lockedMat = math.simd.mul(math.simd.matFromQuat(yawQ), lockedMat);
        }

        if (withRoll) {
            const rollQ = math.simd.quatFromRollPitchYawV(.{ 0, 0, math.degreesToRadians(rot[2]), 0 });
            lockedMat = math.simd.mul(lockedMat, math.simd.matFromQuat(rollQ));
        }

        return lockedMat;
    }
};
