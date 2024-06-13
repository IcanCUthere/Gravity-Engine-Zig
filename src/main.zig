const std = @import("std");
const glfw = @import("zglfw");

const vk = @import("vulkan.zig");

var bd: vk.BaseDispatch = undefined;
var id: vk.InstanceDispatch = undefined;
var dd: vk.DeviceDispatch = undefined;

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    var window = try glfw.Window.create(1000, 1000, "App", null);
    defer window.destroy();

    const extensions = try glfw.getRequiredInstanceExtensions();

    bd = try vk.BaseDispatch.load(vk.glfwGetInstanceProcAddress);

    const instance = try bd.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "Gravity Control",
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "Gravity Engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = @ptrCast(extensions),
    }, null);

    id = try vk.InstanceDispatch.load(instance, bd.dispatch.vkGetInstanceProcAddr);

    defer id.destroyInstance(instance, null);

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
