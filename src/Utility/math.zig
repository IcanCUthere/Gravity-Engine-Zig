const std = @import("std");
pub const simd = @import("zmath");
pub usingnamespace std.math;

pub const roundingError = 10e-9;

pub inline fn videntity() simd.Vec {
    return .{ 0.0, 0.0, 0.0, 1.0 };
}

pub inline fn vzero() simd.Vec {
    return .{ 0.0, 0.0, 0.0, 0.0 };
}
