const util = @import("util");
const mem = util.mem;

const glfw = @import("zglfw");
const vk = @import("vulkanBindings.zig");
pub const vma = @cImport({
    @cInclude("vk_mem_alloc.cpp");
});

pub usingnamespace vk;

pub inline fn glfwGetInstanceProcAddress(handle: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    return @ptrCast(glfw.getInstanceProcAddress(@ptrFromInt(@intFromEnum(handle)), name));
}

pub inline fn createSurface(window: *glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    if (@as(vk.Result, @enumFromInt(glfw.createWindowSurface(
        vk.gInstance,
        window,
        null,
        &surface,
    ))) != vk.Result.SUCCESS) {
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

pub inline fn createAllocator(instance: vk.Instance, device: vk.Device, physDev: vk.PhysicalDevice, apiVersion: u32) !Allocator {
    var allocator: vma.VmaAllocator = undefined;

    const res = vma.vmaCreateAllocator(&.{
        .instance = @ptrCast(instance),
        .device = @ptrCast(device),
        .physicalDevice = @ptrCast(physDev),
        .vulkanApiVersion = apiVersion,
        .pVulkanFunctions = &vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(vk.vkGetInstanceProcAddr),

            .vkGetDeviceProcAddr = @ptrCast(vk.vkGetDeviceProcAddr),
            .vkGetPhysicalDeviceProperties = @ptrCast(vk.vkGetPhysicalDeviceProperties),
            .vkGetPhysicalDeviceMemoryProperties = @ptrCast(vk.vkGetPhysicalDeviceMemoryProperties),
            .vkGetPhysicalDeviceMemoryProperties2KHR = @ptrCast(vk.vkGetPhysicalDeviceMemoryProperties2),

            .vkAllocateMemory = @ptrCast(vk.vkAllocateMemory),
            .vkFreeMemory = @ptrCast(vk.vkFreeMemory),
            .vkBindBufferMemory = @ptrCast(vk.vkBindBufferMemory),
            .vkBindBufferMemory2KHR = @ptrCast(vk.vkBindBufferMemory2),
            .vkBindImageMemory = @ptrCast(vk.vkBindImageMemory),
            .vkBindImageMemory2KHR = @ptrCast(vk.vkBindImageMemory2),
            .vkCmdCopyBuffer = @ptrCast(vk.vkCmdCopyBuffer),
            .vkCreateBuffer = @ptrCast(vk.vkCreateBuffer),
            .vkDestroyBuffer = @ptrCast(vk.vkDestroyBuffer),
            .vkCreateImage = @ptrCast(vk.vkCreateImage),
            .vkDestroyImage = @ptrCast(vk.vkDestroyImage),
            .vkGetBufferMemoryRequirements = @ptrCast(vk.vkGetBufferMemoryRequirements),
            .vkGetBufferMemoryRequirements2KHR = @ptrCast(vk.vkGetBufferMemoryRequirements2),
            .vkGetImageMemoryRequirements = @ptrCast(vk.vkGetImageMemoryRequirements),
            .vkGetImageMemoryRequirements2KHR = @ptrCast(vk.vkGetImageMemoryRequirements2),
            .vkMapMemory = @ptrCast(vk.vkMapMemory),
            .vkUnmapMemory = @ptrCast(vk.vkUnmapMemory),
            .vkInvalidateMappedMemoryRanges = @ptrCast(vk.vkInvalidateMappedMemoryRanges),
            .vkFlushMappedMemoryRanges = @ptrCast(vk.vkFlushMappedMemoryRanges),
            //.vkGetDeviceBufferMemoryRequirements = @ptrCast(vk.vkGetDeviceBufferMemoryRequirements),
            //.vkGetDeviceImageMemoryRequirements = @ptrCast(vk.vkGetDeviceImageMemoryRequirements),
        },
    }, &allocator);

    if (@as(vk.Result, @enumFromInt(res)) != vk.Result.SUCCESS) {
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
    ) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.ImageAllocationFailed;
    }

    return ImageAllocation{ .image = im, .allocation = all };
    //image.allInfo = allInfo;
}

pub inline fn destroyImage(allocator: Allocator, image: ImageAllocation) void {
    vma.vmaDestroyImage(allocator, @ptrCast(image.image), image.allocation);
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
    ) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.BufferAllocationFailed;
    }

    return BufferAllocation{ .buffer = buf, .allocation = all };
}

pub inline fn destroyBuffer(allocator: Allocator, buffer: BufferAllocation) void {
    vma.vmaDestroyBuffer(allocator, @ptrCast(buffer.buffer), buffer.allocation);
}

pub inline fn uploadMemory(allocator: vma.VmaAllocator, buffer: BufferAllocation, datas: []const []const u8, initialOffset: u32) !u32 {
    var deviceMemory: *anyopaque = undefined;
    if (vma.vmaMapMemory(allocator, buffer.allocation, @ptrCast(&deviceMemory)) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.MemoryMapFailed;
    }

    var offset: u32 = initialOffset;
    for (datas) |d| {
        const destMemory = @as([*]u8, @ptrCast(deviceMemory))[offset .. offset + d.len];
        mem.copyForwards(u8, destMemory, d);
        offset += @intCast(d.len);
    }

    vma.vmaUnmapMemory(allocator, buffer.allocation);

    return offset;
}

pub inline fn startReadMemory(allocator: vma.VmaAllocator, buffer: BufferAllocation, size: usize) ![]u8 {
    var deviceMemory: *anyopaque = undefined;
    if (vma.vmaMapMemory(allocator, buffer.allocation, @ptrCast(&deviceMemory)) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.MemoryMapFailed;
    }

    return @as([*]u8, @ptrCast(deviceMemory))[0..size];
}

pub inline fn stopReadMemory(allocator: vma.VmaAllocator, buffer: BufferAllocation) void {
    vma.vmaUnmapMemory(allocator, buffer.allocation);
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
            .getPhysicalDeviceFeatures = true,
            .getPhysicalDeviceImageFormatProperties = true,
            .getPhysicalDeviceFormatProperties = true,
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
            .createSampler = true,
            .destroySampler = true,
            .cmdCopyBufferToImage = true,
            .cmdPushConstants = true,
            .cmdCopyImageToBuffer = true,
            .createPipelineCache = true,
            .destroyPipelineCache = true,
            .getPipelineCacheData = true,
            //.getDeviceBufferMemoryRequirements = true,
            //.getDeviceImageMemoryRequirements = true,
        },
    },
};
