const std = @import("std");
const glfw = @import("zglfw");
const vk = @import("vulkan");
pub const vma = @cImport({
    @cInclude("vk_mem_alloc.cpp");
});

pub usingnamespace vk;

pub inline fn glfwGetInstanceProcAddress(handle: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    return @ptrCast(glfw.getInstanceProcAddress(@ptrFromInt(@intFromEnum(handle)), name));
}

pub inline fn createSurface(instance: InstProxy, window: *glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    if (@as(vk.Result, @enumFromInt(glfw.createWindowSurface(@ptrFromInt(@intFromEnum(instance.handle)), window, null, &surface))) != vk.Result.success) {
        return error.CreateSurfaceError;
    }

    return surface;
}

pub const Allocator = vma.VmaAllocator;
pub const AllocationCreateInfo = vma.VmaAllocationCreateInfo;
pub const Allocation = vma.VmaAllocation;
pub const AllocationInfo = vma.VmaAllocationInfo;

pub const ImageAllocation = struct {
    image: vk.Image,
    allocation: Allocation,
    //allocationInfo: AllocationInfo,
};

pub const BufferAllocation = struct {
    buffer: vk.Buffer,
    allocation: Allocation,
};

pub inline fn createAllocator(instance: InstProxy, device: DevProxy, physDev: vk.PhysicalDevice, apiVersion: u32, bd: BaseDispatch) !Allocator {
    var allocator: vma.VmaAllocator = undefined;

    const res = vma.vmaCreateAllocator(&.{
        .instance = @ptrFromInt(@intFromEnum(instance.handle)),
        .device = @ptrFromInt(@intFromEnum(device.handle)),
        .physicalDevice = @ptrFromInt(@intFromEnum(physDev)),
        .vulkanApiVersion = apiVersion,
        .pVulkanFunctions = &vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(bd.dispatch.vkGetInstanceProcAddr),

            .vkGetDeviceProcAddr = @ptrCast(instance.wrapper.dispatch.vkGetDeviceProcAddr),
            .vkGetPhysicalDeviceProperties = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceProperties),
            .vkGetPhysicalDeviceMemoryProperties = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceMemoryProperties),
            .vkGetPhysicalDeviceMemoryProperties2KHR = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceMemoryProperties2),

            .vkAllocateMemory = @ptrCast(device.wrapper.dispatch.vkAllocateMemory),
            .vkFreeMemory = @ptrCast(device.wrapper.dispatch.vkFreeMemory),
            .vkBindBufferMemory = @ptrCast(device.wrapper.dispatch.vkBindBufferMemory),
            .vkBindBufferMemory2KHR = @ptrCast(device.wrapper.dispatch.vkBindBufferMemory2),
            .vkBindImageMemory = @ptrCast(device.wrapper.dispatch.vkBindImageMemory),
            .vkBindImageMemory2KHR = @ptrCast(device.wrapper.dispatch.vkBindImageMemory2),
            .vkCmdCopyBuffer = @ptrCast(device.wrapper.dispatch.vkCmdCopyBuffer),
            .vkCreateBuffer = @ptrCast(device.wrapper.dispatch.vkCreateBuffer),
            .vkDestroyBuffer = @ptrCast(device.wrapper.dispatch.vkDestroyBuffer),
            .vkCreateImage = @ptrCast(device.wrapper.dispatch.vkCreateImage),
            .vkDestroyImage = @ptrCast(device.wrapper.dispatch.vkDestroyImage),
            .vkGetBufferMemoryRequirements = @ptrCast(device.wrapper.dispatch.vkGetBufferMemoryRequirements),
            .vkGetBufferMemoryRequirements2KHR = @ptrCast(device.wrapper.dispatch.vkGetBufferMemoryRequirements2),
            .vkGetImageMemoryRequirements = @ptrCast(device.wrapper.dispatch.vkGetImageMemoryRequirements),
            .vkGetImageMemoryRequirements2KHR = @ptrCast(device.wrapper.dispatch.vkGetImageMemoryRequirements2),
            .vkMapMemory = @ptrCast(device.wrapper.dispatch.vkMapMemory),
            .vkUnmapMemory = @ptrCast(device.wrapper.dispatch.vkUnmapMemory),
            .vkInvalidateMappedMemoryRanges = @ptrCast(device.wrapper.dispatch.vkInvalidateMappedMemoryRanges),
            .vkFlushMappedMemoryRanges = @ptrCast(device.wrapper.dispatch.vkFlushMappedMemoryRanges),
            //.vkGetDeviceBufferMemoryRequirements = @ptrCast(device.wrapper.dispatch.vkGetDeviceBufferMemoryRequirements),
            //.vkGetDeviceImageMemoryRequirements = @ptrCast(device.wrapper.dispatch.vkGetDeviceImageMemoryRequirements),
        },
    }, &allocator);

    if (@as(vk.Result, @enumFromInt(res)) != vk.Result.success) {
        return error.AllocatorCreateError;
    }

    return allocator;
}

pub inline fn destroyAllocator(allocator: vma.VmaAllocator) void {
    vma.vmaDestroyAllocator(allocator);
}

pub inline fn createImage(allocator: vma.VmaAllocator, imageCreateInfo: *const vk.ImageCreateInfo, allocationCreateInfo: *const AllocationCreateInfo) !ImageAllocation {
    var im: vk.Image = undefined;
    var all: vma.VmaAllocation = undefined;
    var allInfo: vma.VmaAllocationInfo = undefined;

    if (vma.vmaCreateImage(
        allocator,
        @ptrCast(imageCreateInfo),
        allocationCreateInfo,
        @ptrCast(&im),
        &all,
        &allInfo,
    ) != @intFromEnum(vk.Result.success)) {
        return error.ImageAllocationFailed;
    }

    return ImageAllocation{ .image = im, .allocation = all };
    //image.allInfo = allInfo;
}

pub inline fn destroyImage(allocator: Allocator, image: ImageAllocation) void {
    vma.vmaDestroyImage(allocator, @ptrFromInt(@intFromEnum(image.image)), image.allocation);
}

pub inline fn createBuffer(allocator: Allocator, bufferCreateInfo: *const vk.BufferCreateInfo, allocationCreateInfo: *const AllocationCreateInfo) !BufferAllocation {
    var buf: vk.Buffer = undefined;
    var all: vma.VmaAllocation = undefined;
    var allInfo: vma.VmaAllocationInfo = undefined;

    if (vma.vmaCreateBuffer(
        allocator,
        @ptrCast(bufferCreateInfo),
        allocationCreateInfo,
        @ptrCast(&buf),
        &all,
        &allInfo,
    ) != @intFromEnum(vk.Result.success)) {
        return error.BufferAllocationFailed;
    }

    return BufferAllocation{ .buffer = buf, .allocation = all };
}

pub inline fn destroyBuffer(allocator: Allocator, buffer: BufferAllocation) void {
    vma.vmaDestroyBuffer(allocator, @ptrFromInt(@intFromEnum(buffer.buffer)), buffer.allocation);
}

pub inline fn uploadMemory(allocator: vma.VmaAllocator, buffer: BufferAllocation, datas: []const []align(4) const u8, initialOffset: u32) !u32 {
    var deviceMemory: *anyopaque = undefined;
    if (vma.vmaMapMemory(allocator, buffer.allocation, @ptrCast(&deviceMemory)) != @intFromEnum(vk.Result.success)) {
        return error.MemoryMapFailed;
    }

    var offset: u32 = initialOffset;
    for (datas) |d| {
        const destMemory = @as([*]u8, @ptrCast(deviceMemory))[offset .. offset + d.len];
        std.mem.copyForwards(u8, destMemory, d);
        offset += @intCast(d.len);
    }

    _ = vma.vmaFlushAllocation(allocator, buffer.allocation, 0, vma.VK_WHOLE_SIZE);
    vma.vmaUnmapMemory(allocator, buffer.allocation);

    return offset;
}

const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .getInstanceProcAddr = true,
            .createInstance = true,
        },
        .instance_commands = .{
            .destroyInstance = true,
            .destroySurfaceKHR = true,
            .enumeratePhysicalDevices = true,
            .createDevice = true,
            .getDeviceProcAddr = true,
            .enumerateDeviceExtensionProperties = true,
            .getPhysicalDeviceSurfaceFormatsKHR = true,
            .getPhysicalDeviceSurfacePresentModesKHR = true,
            .getPhysicalDeviceQueueFamilyProperties = true,
            .getPhysicalDeviceSurfaceSupportKHR = true,
            .getPhysicalDeviceProperties = true,
            .getPhysicalDeviceMemoryProperties = true,
            .getPhysicalDeviceMemoryProperties2 = true,
            .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
        },
        .device_commands = .{
            .destroyDevice = true,
            .allocateMemory = true,
            .freeMemory = true,
            .bindBufferMemory = true,
            .bindBufferMemory2 = true,
            .bindImageMemory = true,
            .bindImageMemory2 = true,
            .cmdCopyBuffer = true,
            .createBuffer = true,
            .destroyBuffer = true,
            .createImage = true,
            .destroyImage = true,
            .getBufferMemoryRequirements = true,
            .getBufferMemoryRequirements2 = true,
            .getImageMemoryRequirements = true,
            .getImageMemoryRequirements2 = true,
            .mapMemory = true,
            .unmapMemory = true,
            .invalidateMappedMemoryRanges = true,
            .flushMappedMemoryRanges = true,
            .createRenderPass = true,
            .destroyRenderPass = true,
            .createSwapchainKHR = true,
            .destroySwapchainKHR = true,
            .createImageView = true,
            .destroyImageView = true,
            .createFramebuffer = true,
            .destroyFramebuffer = true,
            .getDeviceQueue = true,
            .getSwapchainImagesKHR = true,
            .createCommandPool = true,
            .destroyCommandPool = true,
            .allocateCommandBuffers = true,
            .createSemaphore = true,
            .destroySemaphore = true,
            .createDescriptorSetLayout = true,
            .destroyDescriptorSetLayout = true,
            .createPipelineLayout = true,
            .destroyPipelineLayout = true,
            .createShaderModule = true,
            .destroyShaderModule = true,
            .createGraphicsPipelines = true,
            .destroyPipeline = true,
            .createDescriptorPool = true,
            .destroyDescriptorPool = true,
            .allocateDescriptorSets = true,
            .updateDescriptorSets = true,
            .beginCommandBuffer = true,
            .endCommandBuffer = true,
            .queueSubmit = true,
            .waitSemaphores = true,
            .acquireNextImageKHR = true,
            .resetCommandPool = true,
            .cmdBeginRenderPass = true,
            .cmdBindPipeline = true,
            .cmdSetViewport = true,
            .cmdSetScissor = true,
            .cmdBindVertexBuffers = true,
            .cmdBindIndexBuffer = true,
            .cmdBindDescriptorSets = true,
            .cmdDrawIndexed = true,
            .cmdEndRenderPass = true,
            .queuePresentKHR = true,
            .cmdPipelineBarrier = true,
            //.getDeviceBufferMemoryRequirements = true,
            //.getDeviceImageMemoryRequirements = true,
        },
    },
};

pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);

pub const InstProxy = vk.InstanceProxy(apis);
pub const DevProxy = vk.DeviceProxy(apis);
