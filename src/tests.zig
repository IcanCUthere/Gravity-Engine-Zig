const std = @import("std");
const glfw = @import("zglfw");
const vk = @import("vulkan.zig");
const builtin = @import("builtin");

test "glfw working" {
    try glfw.init();
    defer glfw.terminate();
}

test "can create window" {
    if (builtin.os.tag == .windows or builtin.os.tag == .macos) {
        return error.SkipZigTest;
    }

    glfw.init() catch return error.SkipZigTest;
    defer glfw.terminate();

    var window = try glfw.Window.create(1000, 1000, "App", null);
    defer window.destroy();
}

test "vulkan supported" {
    glfw.init() catch return error.SkipZigTest;
    defer glfw.terminate();

    try std.testing.expectEqual(true, glfw.isVulkanSupported());
}

test "vulkan can load functions" {
    glfw.init() catch return error.SkipZigTest;
    defer glfw.terminate();

    const f = glfw.getInstanceProcAddress(null, "vkGetInstanceProcAddr");

    try std.testing.expect(f != null);
}

test "vulkan can create instance" {
    if (builtin.os.tag == .windows or builtin.os.tag == .macos) {
        return error.SkipZigTest;
    }

    try glfw.init();
    defer glfw.terminate();

    var bd = try vk.BaseDispatch.load(vk.glfwGetInstanceProcAddress);

    const instance = try bd.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "Gravity Control",
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "Gravity Engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        },
        .enabled_extension_count = 0,
        .pp_enabled_extension_names = null,
    }, null);

    var id = try vk.InstanceDispatch.load(instance, bd.dispatch.vkGetInstanceProcAddr);

    defer id.destroyInstance(instance, null);
}
