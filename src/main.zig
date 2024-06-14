const std = @import("std");
const glfw = @import("zglfw");

const vk = @import("vulkan.zig");

const builtin = @import("builtin");

var bd: vk.BaseDispatch = undefined;
var id: vk.InstanceDispatch = undefined;
var dd: vk.DeviceDispatch = undefined;

var buffer: [100000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

fn checkSuitable(pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?vk.PhysicalDevice {
    if (try checkExtensionSupport(pdev) and
        try checkSurfaceSupport(pdev, surface) and
        try allocateQueues(pdev, surface) != null)
    {
        return pdev;
    }

    return null;
}

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn allocateQueues(pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?QueueAllocation {
    var family_count: u32 = undefined;
    id.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, null);

    const families = try allocator.alloc(vk.QueueFamilyProperties, family_count);
    defer allocator.free(families);
    id.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, families.ptr);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try id.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try id.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try id.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(pdev: vk.PhysicalDevice) !bool {
    var count: u32 = undefined;
    _ = try id.enumerateDeviceExtensionProperties(pdev, null, &count, null);

    const propsv = try allocator.alloc(vk.ExtensionProperties, count);
    defer allocator.free(propsv);

    _ = try id.enumerateDeviceExtensionProperties(pdev, null, &count, propsv.ptr);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(glfw.WindowHint.client_api, @intFromEnum(glfw.ClientApi.no_api));
    var window = try glfw.Window.create(1000, 1000, "GravityControl", null);
    defer window.destroy();

    const extensions = try glfw.getRequiredInstanceExtensions();

    bd = try vk.BaseDispatch.load(vk.glfwGetInstanceProcAddress);

    const instance = try bd.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "Gravity Control",
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "Gravity Engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = if (builtin.mode == std.builtin.Mode.Debug) 1 else 0,
        .pp_enabled_layer_names = if (builtin.mode == std.builtin.Mode.Debug) &.{"VK_LAYER_KHRONOS_validation"} else null,
    }, null);

    id = try vk.InstanceDispatch.load(instance, bd.dispatch.vkGetInstanceProcAddr);
    defer id.destroyInstance(instance, null);

    const surface: vk.SurfaceKHR = try vk.createSurface(instance, window);
    defer id.destroySurfaceKHR(instance, surface, null);

    var devCount: u32 = undefined;
    _ = try id.enumeratePhysicalDevices(instance, &devCount, null);

    const pdevs = try allocator.alloc(vk.PhysicalDevice, devCount);
    defer allocator.free(pdevs);

    _ = try id.enumeratePhysicalDevices(instance, &devCount, pdevs.ptr);

    var bestDevice: vk.PhysicalDevice = undefined;

    for (pdevs) |pdev| {
        if (try checkSuitable(pdev, surface)) |dev| {
            bestDevice = dev;
        }
    }

    const queues: QueueAllocation = (try allocateQueues(bestDevice, surface)).?;

    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const device = try id.createDevice(bestDevice, &.{
        .enabled_extension_count = 0,
        .pp_enabled_extension_names = null,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .p_enabled_features = null,
        .queue_create_info_count = if (queues.graphics_family == queues.present_family) 1 else 2,
        .p_queue_create_infos = &qci,
    }, null);

    dd = try vk.DeviceDispatch.load(device, id.dispatch.vkGetDeviceProcAddr);

    defer dd.destroyDevice(device, null);

    const vkAllocator = try vk.createAllocator(instance, device, bestDevice, vk.API_VERSION_1_2, bd, id, dd);
    defer vk.destroyAllocator(vkAllocator);

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
