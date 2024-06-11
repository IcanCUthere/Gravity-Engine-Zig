const std = @import("std");
const glfw = @import("zglfw");
const vk = @cImport({
    @cInclude("vulkan.h");
});

pub fn loadVkLib() !std.DynLib {
    return std.DynLib.open("vulkan-1.dll") catch std.DynLib.open("libvulkan.so") catch try std.DynLib.open("libvulkan.dylib");
}

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    var window = try glfw.Window.create(1000, 1000, "App", null);
    defer window.destroy();

    var lib = try loadVkLib();
    defer lib.close();

    const getInstanceAddr: vk.PFN_vkGetInstanceProcAddr = lib.lookup(vk.PFN_vkGetInstanceProcAddr, "vkGetInstanceProcAddr").?;

    if (getInstanceAddr) |getAddr| {
        const createInstance: vk.PFN_vkCreateInstance = @ptrCast(getAddr(null, "vkCreateInstance"));
        if (createInstance) |_| {
            std.log.info("All clear\n", .{});
        } else {
            std.log.info("Not all clear\n", .{});
        }
    } else {
        std.log.info("Not found!\n", .{});
    }

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
