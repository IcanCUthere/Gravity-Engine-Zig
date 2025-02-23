const gui = @import("gui.zig");

pub const ImGuiVulkanInitInfo = extern struct {
    instance: ?*const anyopaque, // VkInstance
    physical_device: ?*const anyopaque, // VkPhysicalDevice
    device: ?*const anyopaque, // VkDevice
    queueFamily: u32,
    queue: ?*const anyopaque, // VkQueue
    descriptorPool: ?*const anyopaque, //VkDescriptorPool
    renderPass: ?*const anyopaque, // VkRenderPass
    minImageCount: u32,
    imageCount: u32,
    sampleCountFlags: u32 = 1,
    pipelineCache: ?*const anyopaque = null, // VkPipelineCache,
    subpass: u32 = 0,
    useDynamicRendering: bool = false,
    allocationCallbacks: ?*const anyopaque = null, // *VkAllocationCallbacks
    resultFn: ?*const anyopaque = null,
    minAllocSize: usize = 0,
};

pub fn load_functions(
    loadFn: *const anyopaque,
    user_data: ?*const anyopaque,
) bool {
    return ImGui_ImplVulkan_LoadFunctions(
        loadFn,
        user_data,
    );
}

pub fn init(
    initInfo: *const ImGuiVulkanInitInfo,
) void {
    if (!ImGui_ImplVulkan_Init(
        initInfo,
    )) {
        @panic("failed to init vulkan for imgui");
    }
}

pub fn deinit() void {
    ImGui_ImplVulkan_Shutdown();
}

pub fn newFrame() void {
    ImGui_ImplVulkan_NewFrame();
}

pub fn render(
    draw_data: *const anyopaque, // *gui.DrawData
    command_buffer: *const anyopaque, // VkCommandBuffer
) void {
    ImGui_ImplVulkan_RenderDrawData(draw_data, command_buffer, null);
}

extern fn ImGui_ImplVulkan_Init(
    initInfo: *const anyopaque,
) bool;
extern fn ImGui_ImplVulkan_Shutdown() void;
extern fn ImGui_ImplVulkan_NewFrame() void;

extern fn ImGui_ImplVulkan_RenderDrawData(
    draw_data: *const anyopaque, // *ImDrawData
    command_buffer: *const anyopaque, // VkCommandBuffer
    pipeline: ?*const anyopaque, //VkPipeline
) void;

extern fn ImGui_ImplVulkan_LoadFunctions(
    loadFn: *const anyopaque,
    user_data: ?*const anyopaque,
) bool;
