const std = @import("std");
const vk = @import("vulkan");

pub usingnamespace vk;

const glfwGetInstanceProcAddress_intern = @import("zglfw").getInstanceProcAddress;

pub inline fn glfwGetInstanceProcAddress(handle: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    return @ptrCast(glfwGetInstanceProcAddress_intern(@ptrFromInt(@intFromEnum(handle)), name));
}

const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .getInstanceProcAddr = true,
            .createInstance = true,
        },
        .instance_commands = .{
            .destroyInstance = true,
            .createDevice = true,
            .getDeviceProcAddr = true,
        },
    },
};

pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
