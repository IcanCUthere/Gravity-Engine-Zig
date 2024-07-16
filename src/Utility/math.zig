const std = @import("std");
const math = @import("zmath");
pub usingnamespace math;
pub usingnamespace std.math;

pub const roundingError = 10e-9;

pub inline fn videntity() math.Vec {
    return .{ 0.0, 0.0, 0.0, 1.0 };
}

pub inline fn vzero() math.Vec {
    return .{ 0.0, 0.0, 0.0, 0.0 };
}
