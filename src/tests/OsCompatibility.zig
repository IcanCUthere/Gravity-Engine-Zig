const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const util = @import("util");

test "StableArray insert one" {
    var stableArray = try util.StableArray(u32).init(util.mem.heap, 25, 5);
    defer stableArray.deinit();

    const id = try stableArray.add(3);
    const val = stableArray.get(id);

    try testing.expectEqual(3, val);
}

fn printArray(arr: util.StableArray(u32)) void {
    std.log.warn("Array", .{});
    for (arr.data.items) |i| {
        std.log.warn("{d}", .{i});
    }

    for (arr.holes.items) |i| {
        std.log.warn("{d} - {d}", .{ i.index, i.size });
    }
}

test "StableArray insert and delete multiple" {
    var stableArray = try util.StableArray(u32).init(util.mem.heap, 25, 5);
    defer stableArray.deinit();

    const id1 = try stableArray.add(1);
    const id2 = try stableArray.add(2);
    const id3 = try stableArray.add(3);

    try testing.expectEqual(1, try stableArray.remove(id1));
    try testing.expectEqual(2, try stableArray.remove(id2));

    const id4 = try stableArray.add(4);
    const id5 = try stableArray.add(5);
    const id6 = try stableArray.add(6);

    try testing.expectEqual(6, try stableArray.remove(id6));
    try testing.expectEqual(5, try stableArray.remove(id5));

    const id7 = try stableArray.add(7);
    const id8 = try stableArray.add(8);
    const id9 = try stableArray.add(9);
    const id10 = try stableArray.add(10);
    const id11 = try stableArray.add(11);
    const id12 = try stableArray.add(12);
    const id13 = try stableArray.add(13);
    const id14 = try stableArray.add(14);

    try testing.expectEqual(7, try stableArray.remove(id7));
    try testing.expectEqual(11, try stableArray.remove(id11));
    try testing.expectEqual(13, try stableArray.remove(id13));
    try testing.expectEqual(14, try stableArray.remove(id14));
    try testing.expectEqual(10, try stableArray.remove(id10));
    try testing.expectEqual(8, try stableArray.remove(id8));
    try testing.expectEqual(9, try stableArray.remove(id9));

    try testing.expectEqual(3, stableArray.get(id3));
    try testing.expectEqual(4, stableArray.get(id4));
    try testing.expectEqual(12, stableArray.get(id12));

    printArray(stableArray);
}

test "glfw working" {
    //try gfx.glfw.init();
    //defer gfx.glfw.terminate();
}

test "can create window" {
    //if (builtin.os.tag == .windows or builtin.os.tag == .macos) {
    //    return error.SkipZigTest;
    //}

    //gfx.glfw.init() catch return error.SkipZigTest;
    //defer gfx.glfw.terminate();

    //var window = try gfx.glfw.Window.create(1000, 1000, "App", null);
    //defer window.destroy();
}

test "vulkan supported" {
    //gfx.glfw.init() catch return error.SkipZigTest;
    //defer gfx.glfw.terminate();

    //try std.testing.expectEqual(true, gfx.glfw.isVulkanSupported());
}

test "vulkan can load functions" {
    //gfx.glfw.init() catch return error.SkipZigTest;
    //defer gfx.glfw.terminate();

    //_ = try gfx.BaseDispatch.load(gfx.glfwGetInstanceProcAddress);
    //_ = try gfx.InstanceDispatch.load(gfx.Instance.null_handle, gfx.glfwGetInstanceProcAddress);
    //_ = try vk.DeviceDispatch.load(vk.Device.null_handle, vk.glfwGetInstanceProcAddress);
}

test "vulkan can create instance" {
    //if (builtin.os.tag == .windows or builtin.os.tag == .macos) {
    //    return error.SkipZigTest;
    //}

    //gfx.glfw.init() catch return error.SkipZigTest;
    //defer gfx.glfw.terminate();

    //const extensions = try gfx.glfw.getRequiredInstanceExtensions();

    //var bd = try gfx.BaseDispatch.load(gfx.glfwGetInstanceProcAddress);

    //const instance = try bd.createInstance(&.{
    //    .p_application_info = &.{
    //        .p_application_name = "Gravity Control",
    //        .application_version = gfx.makeApiVersion(0, 0, 0, 0),
    //        .p_engine_name = "Gravity Engine",
    //        .engine_version = gfx.makeApiVersion(0, 0, 0, 0),
    //        .api_version = gfx.API_VERSION_1_2,
    //    },
    //    .enabled_extension_count = @intCast(extensions.len),
    //    .pp_enabled_extension_names = extensions.ptr,
    //    .enabled_layer_count = 0,
    //    .pp_enabled_layer_names = null,
    //}, null);

    //var id = try gfx.InstanceDispatch.load(instance, gfx.bd.dispatch.vkGetInstanceProcAddr);

    //defer id.destroyInstance(instance, null);
}
