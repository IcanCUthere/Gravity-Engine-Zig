const gui = @import("gui.zig");
const backend_glfw = @import("backend_glfw.zig");
const backend_vulkan = @import("backend_vulkan.zig");

pub const VulkanInitInfo = backend_vulkan.ImGuiVulkanInitInfo;

pub fn init(
    window: *const anyopaque, // zglfw.Window
    vulkanInitInfo: *const backend_vulkan.ImGuiVulkanInitInfo,
) void {
    backend_glfw.initVulkan(window);
    backend_vulkan.init(vulkanInitInfo);
}

pub fn deinit() void {
    backend_vulkan.deinit();
    backend_glfw.deinit();
}

pub fn newFrame(fb_width: u32, fb_height: u32) void {
    backend_vulkan.newFrame();
    backend_glfw.newFrame();

    gui.io.setDisplaySize(@as(f32, @floatFromInt(fb_width)), @as(f32, @floatFromInt(fb_height)));
    gui.io.setDisplayFramebufferScale(1.0, 1.0);

    gui.newFrame();
}

pub fn draw(
    command_buffer: *const anyopaque, // VkCommandBuffer
) void {
    gui.render();
    backend_vulkan.render(gui.getDrawData(), command_buffer);
}

pub fn loadFunctions(loadFn: *const anyopaque, user_data: ?*const anyopaque) bool {
    return backend_vulkan.load_functions(loadFn, user_data);
}
