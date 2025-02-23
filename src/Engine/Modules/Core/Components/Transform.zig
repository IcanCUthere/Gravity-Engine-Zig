const util = @import("util");
const math = util.math;

const flecs = @import("zflecs");

pub const Transform = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    worldPosition: math.Vec = math.videntity(),
    worldRotation: math.Vec = math.videntity(),
    worldScale: math.Vec = math.videntity(),

    localPosition: math.Vec = math.videntity(),
    localRotation: math.Vec = math.videntity(),
    localScale: math.Vec = math.videntity(),

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

    pub fn getLocalRightVector(self: Self) math.Vec {
        return math.vec4ToVec3(math.mulV(
            math.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.Vec{ 1, 0, 0, 0 },
        ));
    }

    pub fn getLocalUpVector(self: Self) math.Vec {
        return math.vec4ToVec3(math.mulV(
            math.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.Vec{ 0, 1, 0, 0 },
        ));
    }

    pub fn getLocalForwardVector(self: Self) math.Vec {
        return math.mulV(
            math.matFromRollPitchYawV(math.vec3ToVec4(math.degreesToRadians(self.localRotation))),
            math.Vec{ 0, 0, 1, 0 },
        );
    }

    pub fn getLocalRightVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.Vec {
        return math.mulV(
            getLockedRotation(
                self.localRotation,
                withPitch,
                withYaw,
                withRoll,
            ),
            math.Vec{ 1, 0, 0, 1 },
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

    pub fn getLocalForwardVectorLocked(self: Self, withPitch: bool, withYaw: bool, withRoll: bool) math.Vec {
        return math.mulV(
            getLockedRotation(
                self.localRotation,
                withPitch,
                withYaw,
                withRoll,
            ),
            math.Vec{ 0, 0, 1, 1 },
        );
    }

    pub fn getWorldRightVector() math.Vec {
        return math.Vec{ 1, 0, 0, 0 };
    }

    pub fn getWorldUpVector() math.Vec {
        return math.Vec{ 0, 1, 0, 0 };
    }

    pub fn getWorldForwardVector() math.Vec {
        return math.Vec{ 0, 0, 1, 0 };
    }

    pub fn getLockedRotation(rot: math.Vec, withPitch: bool, withYaw: bool, withRoll: bool) math.Mat {
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
