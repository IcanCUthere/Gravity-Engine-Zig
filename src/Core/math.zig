const math = @import("zmath");
pub usingnamespace math;

pub const Vec3 = @Vector(3, f32);

const smallNumber = 10e-9;

pub inline fn vec3ToVec4(vec: Vec3) math.Vec {
    return math.Vec{ vec[0], vec[1], vec[2], 0.0 };
}

pub inline fn vec4ToVec3(vec: math.Vec) Vec3 {
    return .{ vec[0], vec[1], vec[2] };
}

pub inline fn videntity() Vec3 {
    return .{ 0.0, 0.0, 0.0 };
}

pub fn normalize(vec: Vec3) Vec3 {
    const len = math.sqrt(vec[0] * vec[0] + vec[1] * vec[1] + vec[2] * vec[2]);

    if (len < smallNumber) {
        return vec;
    }

    return .{
        vec[0] / len,
        vec[1] / len,
        vec[2] / len,
    };
}
