const std = @import("std");
const math = @import("zmath");

pub const Camera = struct {
    const Self = @This();

    _position: math.Vec,
    _rotation: math.Vec,
    _positionMat: math.Mat = undefined,
    _rotationMat: math.Mat = undefined,

    _projectionMatrix: math.Mat = undefined,
    _translationMatrix: math.Mat = undefined,
    cameraMatrix: math.Mat = undefined,

    pub fn init(position: math.Vec, rotation: math.Vec, aspectRatio: f32, fovInDeg: f32, near: f32, far: f32) Camera {
        var self = Camera{
            ._projectionMatrix = math.perspectiveFovRh(std.math.degreesToRadians(fovInDeg), aspectRatio, near, far),
            ._positionMat = math.translationV(position),
            ._rotationMat = math.matFromRollPitchYawV(rotation),
            ._position = position,
            ._rotation = rotation,
        };

        self._translationMatrix = math.mul(self._rotationMat, self._positionMat);
        self.cameraMatrix = math.mul(self._translationMatrix, self._projectionMatrix);

        return self;
    }

    pub fn setProjectionMatrix(self: *Self, fovInDeg: f32, aspectRatio: f32, near: f32, far: f32) void {
        self._projectionMatrix = math.perspectiveFovRh(std.math.degreesToRadians(fovInDeg), aspectRatio, near, far);
        self.cameraMatrix = math.mul(self._translationMatrix, self._projectionMatrix);
    }

    pub fn addTranslation(self: *Self, translation: math.Vec) void {
        self._position += translation;
        self._positionMat = math.mul(self._positionMat, math.translationV(translation));
        self._translationMatrix = math.mul(self._positionMat, self._rotationMat);
        self.cameraMatrix = math.mul(self._translationMatrix, self._projectionMatrix);
    }

    pub fn addRotation(self: *Self, rotation: math.Vec) void {
        self._rotation += rotation;
        self._rotationMat = math.mul(self._rotationMat, math.matFromRollPitchYawV(rotation));
        self._translationMatrix = math.mul(self._positionMat, self._rotationMat);
        self.cameraMatrix = math.mul(self._translationMatrix, self._projectionMatrix);
    }

    pub fn getRightVector(self: *Self) math.Vec {
        return math.mul(self._rotationMat, math.Vec{ 1.0, 0.0, 0.0, 0.0 });
    }

    pub fn getUpVector(self: *Self) math.Vec {
        return math.mul(self._rotationMat, math.Vec{ 0.0, 1.0, 0.0, 0.0 });
    }

    pub fn getForwardVector(self: *Self) math.Vec {
        return math.mul(self._rotationMat, math.Vec{ 0.0, 0.0, 1.0, 0.0 });
    }
};
