const std = @import("std");
const gfx = @import("graphics");
const builtin = @import("builtin");

test "glfw working" {
    try gfx.glfw.init();
    defer gfx.glfw.terminate();
}

test "can create window" {
    if (builtin.os.tag == .windows or builtin.os.tag == .macos) {
        return error.SkipZigTest;
    }

    gfx.glfw.init() catch return error.SkipZigTest;
    defer gfx.glfw.terminate();

    var window = try gfx.glfw.Window.create(1000, 1000, "App", null);
    defer window.destroy();
}

test "vulkan supported" {
    gfx.glfw.init() catch return error.SkipZigTest;
    defer gfx.glfw.terminate();

    try std.testing.expectEqual(true, gfx.glfw.isVulkanSupported());
}

test "vulkan can load functions" {
    gfx.glfw.init() catch return error.SkipZigTest;
    defer gfx.glfw.terminate();

    _ = try gfx.BaseDispatch.load(gfx.glfwGetInstanceProcAddress);
    _ = try gfx.InstanceDispatch.load(gfx.Instance.null_handle, gfx.glfwGetInstanceProcAddress);
    //_ = try vk.DeviceDispatch.load(vk.Device.null_handle, vk.glfwGetInstanceProcAddress);
}

test "vulkan can create instance" {
    if (builtin.os.tag == .windows or builtin.os.tag == .macos) {
        return error.SkipZigTest;
    }

    gfx.glfw.init() catch return error.SkipZigTest;
    defer gfx.glfw.terminate();

    const extensions = try gfx.glfw.getRequiredInstanceExtensions();

    var bd = try gfx.BaseDispatch.load(gfx.glfwGetInstanceProcAddress);

    const instance = try bd.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "Gravity Control",
            .application_version = gfx.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "Gravity Engine",
            .engine_version = gfx.makeApiVersion(0, 0, 0, 0),
            .api_version = gfx.API_VERSION_1_2,
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
    }, null);

    var id = try gfx.InstanceDispatch.load(instance, gfx.bd.dispatch.vkGetInstanceProcAddr);

    defer id.destroyInstance(instance, null);
}
