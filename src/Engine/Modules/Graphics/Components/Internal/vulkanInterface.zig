pub const vk = @import("vulkanBindings.zig");
pub const vma = @cImport({
    @cInclude("vk_mem_alloc.cpp");
});
pub const glfw = @import("zglfw");
const builtin = @import("builtin");
pub const util = @import("util");
pub const mem = util.mem;

pub var renderFamily: u32 = undefined;
pub var renderQueue: vk.Queue = undefined;
pub var physicalDevice: vk.PhysicalDevice = undefined;
pub var vkAllocator: vma.VmaAllocation = undefined;
var deviceProperties: vk.PhysicalDeviceProperties = undefined;

pub fn init(version: type, extensions: []const type) !void {
    try version.loadBaseFunctions();

    const extensions = try glfw.getRequiredInstanceExtensions();

    var instanceExtensionCount: u32 = 0;
    var instanceExtensions: [extensions.len][*:0]const u8 = undefined;
    inline for (extensions) |ext| {
        if (ext.isInstanceExtension) {
            instanceExtensions[instanceExtensionCount] = ext.name;
            instanceExtensionCount += 1;
        }
    }

    vk.gInstance = try vk.CreateInstance(&vk.InstanceCreateInfo{
        .enabledExtensionCount = instanceExtensionCount,
        .ppEnabledExtensionNames = &instanceExtensions,
        .enabledLayerCount = if (builtin.mode == .Debug) 1 else 0,
        .ppEnabledLayerNames = &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"},
        .pApplicationInfo = &vk.ApplicationInfo{
            .apiVersion = vk.apiVersion13,
            .applicationVersion = 0,
            .engineVersion = 0,
            .pApplicationName = "Gravity: Control",
            .pEngineName = "Gravity Engine",
        },
    });

    try version.loadInstanceFunctions();
    inline for (extensions) |ext| {
        if (ext.isInstanceExtension) {
            try ext.load();
        }
    }

    physicalDevice = try findBestDevice();

    const physDevices = try vk.EnumeratePhysicalDevices(mem.fixedBuffer);
    defer mem.fixedBuffer.free(physDevices);

    var deviceExtensionCount: u32 = 0;
    var deviceExtensions: [extensions.len][*:0]const u8 = undefined;
    inline for (extensions) |ext| {
        if (!ext.isInstanceExtension) {
            deviceExtensions[deviceExtensionCount] = ext.name;
            deviceExtensionCount += 1;
        }
    }

    deviceProperties = instance.getPhysicalDeviceProperties(physicalDevice);
    util.log.print("Used Graphics Card: {s}, Driver Version: {d}", .{ deviceProperties.device_name, deviceProperties.driver_version }, .Info, .Abstract, .{ .Vulkan = true });

    renderFamily = try getGraphicsFamily(physicalDevice);

    queueFamilyProperties = try vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, mem.fixedBuffer);

    vk.gDevice = try vk.CreateDevice(physDevices[0], &vk.DeviceCreateInfo{
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = deviceExtensionCount,
        .ppEnabledExtensionNames = &deviceExtensions,
        .pEnabledFeatures = null,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &vk.DeviceQueueCreateInfo{
            .queueFamilyIndex = 0,
            .queueCount = 1,
            .pQueuePriorities = &[_]f32{1.0},
        },
    });

    try version.loadDeviceFunctions();

    renderQueue = vk.GetDeviceQueue(renderFamily, 0);

    vkAllocator = try vma.vmaCreateAllocator(instance, device, physicalDevice, vk.API_VERSION_1_3, baseDispatch);
}

pub fn deinit() !void {
    try vk.DestroyDevice();
    try vk.DestroyInstance();
}

pub fn getGraphicsCardName() []const u8 {
    return &deviceProperties.device_name;
}

pub fn getDriverVersion() u32 {
    return deviceProperties.driver_version;
}

fn getGraphicsFamily(pdev: vk.PhysicalDevice) !u32 {
    const families = try vk.GetPhysicalDeviceQueueFamilyProperties(pdev, mem.fixedBuffer);
    defer mem.fixedBuffer.free(families);

    for (families, 0..) |properties, i| {
        if (properties.queue_flags.graphics_bit) {
            return @intCast(i);
        }
    }

    return error.NoRenderFamilyFound;
}

fn findRankingSpot(T: type, ranking: []const T, item: T) u64 {
    for (ranking, 0..) |r, i| {
        if (r == item) {
            return i;
        }
    }

    return 100000;
}

fn getVRamSize(dev: vk.PhysicalDevice) u64 {
    const memProps = try vk.GetPhysicalDeviceMemoryProperties(dev);

    for (0..memProps.memory_heap_count) |i| {
        if (memProps.memory_heaps[i].flags.contains(.{ .device_local_bit = true })) {
            return memProps.memory_heaps[i].size;
        }
    }

    return 0;
}

fn hasBetterProperties(new: vk.PhysicalDevice, old: vk.PhysicalDevice) bool {
    const newProps = try vk.GetPhysicalDeviceProperties(new);
    const oldProps = try vk.GetPhysicalDeviceProperties(old);

    const typeRanking = [_]vk.PhysicalDeviceType{
        .discrete_gpu,
        .integrated_gpu,
        .virtual_gpu,
        .cpu,
        .other,
    };

    const newRanking = findRankingSpot(vk.PhysicalDeviceType, typeRanking[0..], newProps.device_type);
    const oldRanking = findRankingSpot(vk.PhysicalDeviceType, typeRanking[0..], oldProps.device_type);
    if (newRanking < oldRanking) {
        return true;
    } else if (newRanking > oldRanking) {
        return false;
    }

    const newVramSize = getVRamSize(new);
    const oldVramSize = getVRamSize(old);

    if (newVramSize > oldVramSize) {
        return true;
    } else if (newVramSize < oldVramSize) {
        return false;
    }

    return false;
}

fn findBestDevice() !vk.PhysicalDevice {
    const pdevs = try vk.EnumeratePhysicalDevices(mem.fixedBuffer);
    defer mem.fixedBuffer.free(pdevs);

    var bestDev: ?vk.PhysicalDevice = null;
    for (pdevs) |dev| {
        if (try checkExtensionSupport(dev)) {
            if (bestDev == null or hasBetterProperties(dev, bestDev.?)) {
                bestDev = dev;
            }
        }
    }

    if (bestDev) |d| {
        return d;
    } else {
        return error.NoSuitibleGPU;
    }
}

fn checkExtensionSupport(pdev: vk.PhysicalDevice) !bool {
    const propsv = try vk.EnumerateDeviceExtensionProperties(pdev, null, mem.fixedBuffer);
    defer mem.fixedBuffer.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (mem.eql(u8, mem.span(ext), mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}
