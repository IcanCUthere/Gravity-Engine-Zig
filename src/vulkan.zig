const std = @import("std");
const glfw = @import("zglfw");
const vk = @import("vulkan");
const vma = @cImport({
    @cInclude("vk_mem_alloc.cpp");
});

pub usingnamespace vk;

pub inline fn glfwGetInstanceProcAddress(handle: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    return @ptrCast(glfw.getInstanceProcAddress(@ptrFromInt(@intFromEnum(handle)), name));
}

pub inline fn createSurface(instance: vk.Instance, window: *glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    if (@as(vk.Result, @enumFromInt(glfw.createWindowSurface(@ptrFromInt(@intFromEnum(instance)), window, null, &surface))) != vk.Result.success) {
        return error.CreateSurfaceError;
    }

    return surface;
}

pub inline fn createAllocator(instance: vk.Instance, device: vk.Device, physDev: vk.PhysicalDevice, apiVersion: u32, bd: BaseDispatch, id: InstanceDispatch, dd: DeviceDispatch) !vma.VmaAllocator {
    var allocator: vma.VmaAllocator = undefined;

    const res = vma.vmaCreateAllocator(&.{
        .instance = @ptrFromInt(@intFromEnum(instance)),
        .device = @ptrFromInt(@intFromEnum(device)),
        .physicalDevice = @ptrFromInt(@intFromEnum(physDev)),
        .vulkanApiVersion = apiVersion,
        .pVulkanFunctions = &vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(bd.dispatch.vkGetInstanceProcAddr),

            .vkGetDeviceProcAddr = @ptrCast(id.dispatch.vkGetDeviceProcAddr),
            .vkGetPhysicalDeviceProperties = @ptrCast(id.dispatch.vkGetPhysicalDeviceProperties),
            .vkGetPhysicalDeviceMemoryProperties = @ptrCast(id.dispatch.vkGetPhysicalDeviceMemoryProperties),
            .vkGetPhysicalDeviceMemoryProperties2KHR = @ptrCast(id.dispatch.vkGetPhysicalDeviceMemoryProperties2),

            .vkAllocateMemory = @ptrCast(dd.dispatch.vkAllocateMemory),
            .vkFreeMemory = @ptrCast(dd.dispatch.vkFreeMemory),
            .vkBindBufferMemory = @ptrCast(dd.dispatch.vkBindBufferMemory),
            .vkBindBufferMemory2KHR = @ptrCast(dd.dispatch.vkBindBufferMemory2),
            .vkBindImageMemory = @ptrCast(dd.dispatch.vkBindImageMemory),
            .vkBindImageMemory2KHR = @ptrCast(dd.dispatch.vkBindImageMemory2),
            .vkCmdCopyBuffer = @ptrCast(dd.dispatch.vkCmdCopyBuffer),
            .vkCreateBuffer = @ptrCast(dd.dispatch.vkCreateBuffer),
            .vkDestroyBuffer = @ptrCast(dd.dispatch.vkDestroyBuffer),
            .vkCreateImage = @ptrCast(dd.dispatch.vkCreateImage),
            .vkDestroyImage = @ptrCast(dd.dispatch.vkDestroyImage),
            .vkGetBufferMemoryRequirements = @ptrCast(dd.dispatch.vkGetBufferMemoryRequirements),
            .vkGetBufferMemoryRequirements2KHR = @ptrCast(dd.dispatch.vkGetBufferMemoryRequirements2),
            .vkGetImageMemoryRequirements = @ptrCast(dd.dispatch.vkGetImageMemoryRequirements),
            .vkGetImageMemoryRequirements2KHR = @ptrCast(dd.dispatch.vkGetImageMemoryRequirements2),
            .vkMapMemory = @ptrCast(dd.dispatch.vkMapMemory),
            .vkUnmapMemory = @ptrCast(dd.dispatch.vkUnmapMemory),
            .vkInvalidateMappedMemoryRanges = @ptrCast(dd.dispatch.vkInvalidateMappedMemoryRanges),
            .vkFlushMappedMemoryRanges = @ptrCast(dd.dispatch.vkFlushMappedMemoryRanges),
            //.vkGetDeviceBufferMemoryRequirements = @ptrCast(dd.dispatch.vkGetDeviceBufferMemoryRequirements),
            //.vkGetDeviceImageMemoryRequirements = @ptrCast(dd.dispatch.vkGetDeviceImageMemoryRequirements),
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
            //.getDeviceBufferMemoryRequirements = true,
            //.getDeviceImageMemoryRequirements = true,
        },
    },
};

pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
