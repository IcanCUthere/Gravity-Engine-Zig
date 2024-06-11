const std = @import("std");
const glfw = @import("zglfw");
const vk = @cImport({
    @cInclude("vulkan.h");
});

const main = @import("main.zig");
const cfg = @import("config");

test "glfw working" {
    try glfw.init();
    defer glfw.terminate();
}

test "vulkan supported" {
    glfw.init() catch return error.SkipZigTest;
    defer glfw.terminate();

    try std.testing.expectEqual(true, glfw.isVulkanSupported());
}

test "vulkan lib installed" {
    _ = try main.loadVkLib();
}

test "vulkan can load functions" {
    var lib: std.DynLib = main.loadVkLib() catch return error.SkipZigTest;
    const func = lib.lookup(vk.PFN_vkGetInstanceProcAddr, "vkGetInstanceProcAddr");

    if (func) |_| {} else return error.FunctionNotFound;
}
