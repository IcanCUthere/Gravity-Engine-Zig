const std = @import("std");
const glfw = @import("zglfw");
const vk = @cImport({
    @cInclude("vulkan.h");
});

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    var window = try glfw.Window.create(1000, 1000, "App", null);
    defer window.destroy();

    var lib = try std.DynLib.open("vulkan-1");
    defer lib.close();

    const getInstanceAddr: vk.PFN_vkGetInstanceProcAddr = lib.lookup(vk.PFN_vkGetInstanceProcAddr, "vkGetInstanceProcAddr").?;

    if (getInstanceAddr) |getAddr| {
        const createInstance: vk.PFN_vkCreateInstance = @ptrCast(getAddr(null, "vkCreateInstance"));
        if (createInstance) |_| {
            std.debug.print("All clear\n", .{});
        } else {
            std.debug.print("Not all clear \n", .{});
        }
    } else {
        std.debug.print("Not found!\n", .{});
    }

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
