const util = @import("util");
const mem = util.mem;

const builtin = @import("builtin");

pub const glfw = @import("zglfw");
pub const vk = @import("vulkan.zig");

pub usingnamespace vk;

pub var instance: vk.InstProxy = undefined;
pub var device: vk.DevProxy = undefined;
pub var physicalDevice: vk.PhysicalDevice = undefined;
pub var vkAllocator: vk.Allocator = undefined;

pub var baseDispatch: vk.BaseDispatch = undefined;
var instanceDispatch: vk.InstanceDispatch = undefined;
var deviceDispatch: vk.DeviceDispatch = undefined;

pub var renderFamily: u32 = undefined;
pub var renderQueue: vk.Queue = undefined;

var deviceProperties: vk.PhysicalDeviceProperties = undefined;

const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
};

pub fn init() !void {
    const extensions = try glfw.getRequiredInstanceExtensions();

    baseDispatch = try vk.BaseDispatch.load(vk.glfwGetInstanceProcAddress);

    instance.handle = try baseDispatch.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "Gravity Control",
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "Gravity Engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = if (builtin.mode == .Debug) 1 else 0,
        .pp_enabled_layer_names = if (builtin.mode == .Debug) &.{"VK_LAYER_KHRONOS_validation"} else null,
    }, null);

    instanceDispatch = try vk.InstanceDispatch.load(instance.handle, baseDispatch.dispatch.vkGetInstanceProcAddr);
    instance.wrapper = &instanceDispatch;

    physicalDevice = try findBestDevice();

    deviceProperties = instance.getPhysicalDeviceProperties(physicalDevice);
    util.log.print("Used Graphics Card: {s}, Driver Version: {d}", .{ deviceProperties.device_name, deviceProperties.driver_version }, .Info, .Abstract, .{ .Vulkan = true });

    renderFamily = try getGraphicsFamily(physicalDevice);

    var familyCount: u32 = undefined;
    instance.getPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, null);

    const priority = [_]f32{1};
    const queueCreateInfo = try util.mem.fixedBuffer.alloc(vk.DeviceQueueCreateInfo, familyCount);
    defer util.mem.fixedBuffer.free(queueCreateInfo);

    for (queueCreateInfo, 0..) |*q, i| {
        q.* = vk.DeviceQueueCreateInfo{
            .queue_family_index = @intCast(i),
            .queue_count = 1,
            .p_queue_priorities = &priority,
        };
    }

    const timelineFeature = vk.PhysicalDeviceTimelineSemaphoreFeatures{
        .timeline_semaphore = vk.TRUE,
    };

    var deviceFeatures: vk.PhysicalDeviceFeatures = instance.getPhysicalDeviceFeatures(physicalDevice);
    deviceFeatures.sampler_anisotropy = vk.TRUE;

    device.handle = try instance.createDevice(physicalDevice, &.{
        .p_next = &timelineFeature,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = &required_device_extensions,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .p_enabled_features = &deviceFeatures,
        .queue_create_info_count = familyCount,
        .p_queue_create_infos = queueCreateInfo.ptr,
    }, null);

    deviceDispatch = try vk.DeviceDispatch.load(device.handle, instance.wrapper.dispatch.vkGetDeviceProcAddr);
    device.wrapper = &deviceDispatch;

    renderQueue = device.getDeviceQueue(renderFamily, 0);

    vkAllocator = try vk.createAllocator(instance, device, physicalDevice, vk.API_VERSION_1_2, baseDispatch);
}

pub fn deinit() void {
    vk.destroyAllocator(vkAllocator);
    device.destroyDevice(null);
    instance.destroyInstance(null);
}

pub fn createRenderPass(viewportFormat: vk.Format, clear: bool) !vk.RenderPass {
    const attachmentDescriptions = [_]vk.AttachmentDescription{
        vk.AttachmentDescription{
            .format = viewportFormat,
            .samples = vk.SampleCountFlags{ .@"1_bit" = true },
            .load_op = if (clear) vk.AttachmentLoadOp.clear else .dont_care,
            .store_op = vk.AttachmentStoreOp.store,
            .stencil_load_op = vk.AttachmentLoadOp.dont_care,
            .stencil_store_op = vk.AttachmentStoreOp.dont_care,
            .initial_layout = vk.ImageLayout.undefined,
            .final_layout = vk.ImageLayout.present_src_khr,
        },
        vk.AttachmentDescription{
            .format = vk.Format.d16_unorm,
            .samples = vk.SampleCountFlags{ .@"1_bit" = true },
            .load_op = vk.AttachmentLoadOp.clear,
            .store_op = vk.AttachmentStoreOp.dont_care,
            .stencil_load_op = vk.AttachmentLoadOp.dont_care,
            .stencil_store_op = vk.AttachmentStoreOp.dont_care,
            .initial_layout = vk.ImageLayout.undefined,
            .final_layout = vk.ImageLayout.depth_stencil_attachment_optimal,
        },
    };

    const colorReferences = [_]vk.AttachmentReference{
        vk.AttachmentReference{
            .attachment = 0,
            .layout = vk.ImageLayout.color_attachment_optimal,
        },
    };
    const depthRefernce = vk.AttachmentReference{
        .attachment = 1,
        .layout = vk.ImageLayout.depth_stencil_attachment_optimal,
    };

    const subpasses = [_]vk.SubpassDescription{
        vk.SubpassDescription{
            .pipeline_bind_point = vk.PipelineBindPoint.graphics,
            .p_input_attachments = null,
            .input_attachment_count = 0,
            .p_depth_stencil_attachment = &depthRefernce,
            .p_color_attachments = &colorReferences,
            .p_resolve_attachments = null,
            .color_attachment_count = 1,
            .p_preserve_attachments = null,
            .preserve_attachment_count = 0,
        },
    };

    const subpassDependencies = [_]vk.SubpassDependency{
        vk.SubpassDependency{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{
                .color_attachment_output_bit = true,
                .early_fragment_tests_bit = true,
            },
            .dst_stage_mask = .{
                .color_attachment_output_bit = true,
                .early_fragment_tests_bit = true,
            },
            .src_access_mask = .{},
            .dst_access_mask = .{
                .color_attachment_write_bit = true,
                .depth_stencil_attachment_write_bit = true,
            },
            .dependency_flags = .{},
        },
        vk.SubpassDependency{
            .src_subpass = 0,
            .dst_subpass = vk.SUBPASS_EXTERNAL,
            .src_stage_mask = .{
                .late_fragment_tests_bit = true,
                .color_attachment_output_bit = true,
            },
            .dst_stage_mask = .{
                .early_fragment_tests_bit = true,
            },
            .src_access_mask = .{
                .depth_stencil_attachment_write_bit = true,
                .color_attachment_write_bit = true,
            },
            .dst_access_mask = .{
                //.depth_stencil_attachment_write_bit = true,
            },
            .dependency_flags = .{},
        },
    };

    return try device.createRenderPass(&vk.RenderPassCreateInfo{
        .p_attachments = &attachmentDescriptions,
        .attachment_count = @intCast(attachmentDescriptions.len),
        .p_subpasses = &subpasses,
        .subpass_count = @intCast(subpasses.len),
        .p_dependencies = &subpassDependencies,
        .dependency_count = @intCast(subpassDependencies.len),
    }, null);
}

pub fn createPipeline(
    cache: vk.PipelineCache,
    layout: vk.PipelineLayout,
    renderPass: vk.RenderPass,
    vertModule: vk.ShaderModule,
    fragModule: vk.ShaderModule,
    vertexBindings: []const vk.VertexInputBindingDescription,
    vertexAttributes: []const vk.VertexInputAttributeDescription,
    depthEnable: bool,
    comptime viewportSize: ?[2]f32,
) !vk.Pipeline {
    const stages = [_]vk.PipelineShaderStageCreateInfo{
        vk.PipelineShaderStageCreateInfo{
            .p_name = "main",
            .stage = vk.ShaderStageFlags{ .vertex_bit = true },
            .module = vertModule,
        },
        vk.PipelineShaderStageCreateInfo{
            .p_name = "main",
            .stage = vk.ShaderStageFlags{ .fragment_bit = true },
            .module = fragModule,
        },
    };

    const viewports = [_]vk.Viewport{
        vk.Viewport{
            .width = if (viewportSize) |v| v[0] else 0,
            .height = if (viewportSize) |v| v[1] else 0,
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = 0.0,
        },
    };

    const scissors = [_]vk.Rect2D{
        vk.Rect2D{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = .{
                .width = if (viewportSize) |v| @intFromFloat(v[0]) else 0,
                .height = if (viewportSize) |v| @intFromFloat(v[1]) else 0,
            },
        },
    };

    const stencilOpState = vk.StencilOpState{
        .pass_op = vk.StencilOp.keep,
        .fail_op = vk.StencilOp.keep,
        .depth_fail_op = vk.StencilOp.keep,
        .compare_op = vk.CompareOp.always,
        .compare_mask = 0,
        .reference = 0,
        .write_mask = 0,
    };

    const colorBlendAttachments = [_]vk.PipelineColorBlendAttachmentState{
        vk.PipelineColorBlendAttachmentState{
            .blend_enable = vk.FALSE,
            .color_blend_op = vk.BlendOp.add,
            .alpha_blend_op = vk.BlendOp.add,
            .color_write_mask = vk.ColorComponentFlags{
                .a_bit = true,
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
            },
            .src_color_blend_factor = vk.BlendFactor.one,
            .dst_color_blend_factor = vk.BlendFactor.zero,
            .src_alpha_blend_factor = vk.BlendFactor.one,
            .dst_alpha_blend_factor = vk.BlendFactor.zero,
        },
    };

    const dynamicStates = if (viewportSize == null) [_]vk.DynamicState{
        vk.DynamicState.viewport,
        vk.DynamicState.scissor,
    } else [_]vk.DynamicState{};

    var pipeline: vk.Pipeline = undefined;

    const createInfo = [_]vk.GraphicsPipelineCreateInfo{
        vk.GraphicsPipelineCreateInfo{
            .layout = layout,
            .render_pass = renderPass,
            .subpass = 0,
            .base_pipeline_index = 0,
            .base_pipeline_handle = vk.Pipeline.null_handle,
            .p_stages = &stages,
            .stage_count = @intCast(stages.len),
            .p_vertex_input_state = &vk.PipelineVertexInputStateCreateInfo{
                .p_vertex_attribute_descriptions = vertexAttributes.ptr,
                .vertex_attribute_description_count = @intCast(vertexAttributes.len),
                .p_vertex_binding_descriptions = vertexBindings.ptr,
                .vertex_binding_description_count = @intCast(vertexBindings.len),
            },
            .p_input_assembly_state = &vk.PipelineInputAssemblyStateCreateInfo{
                .primitive_restart_enable = vk.FALSE,
                .topology = vk.PrimitiveTopology.triangle_list,
            },
            .p_tessellation_state = &vk.PipelineTessellationStateCreateInfo{
                .patch_control_points = 0,
            },
            .p_viewport_state = &vk.PipelineViewportStateCreateInfo{
                .p_viewports = &viewports,
                .viewport_count = @intCast(viewports.len),
                .p_scissors = &scissors,
                .scissor_count = @intCast(scissors.len),
            },
            .p_rasterization_state = &vk.PipelineRasterizationStateCreateInfo{
                .polygon_mode = vk.PolygonMode.fill,
                .cull_mode = vk.CullModeFlags{ .back_bit = true },
                .front_face = vk.FrontFace.counter_clockwise,
                .depth_bias_enable = vk.FALSE,
                .depth_clamp_enable = vk.FALSE,
                .rasterizer_discard_enable = vk.FALSE,
                .depth_bias_clamp = 0.0,
                .depth_bias_constant_factor = 0.0,
                .depth_bias_slope_factor = 0.0,
                .line_width = 1.0,
            },
            .p_multisample_state = &vk.PipelineMultisampleStateCreateInfo{
                .rasterization_samples = vk.SampleCountFlags{ .@"1_bit" = true },
                .alpha_to_coverage_enable = vk.FALSE,
                .alpha_to_one_enable = vk.FALSE,
                .sample_shading_enable = vk.FALSE,
                .min_sample_shading = 1.0,
                .p_sample_mask = null,
            },
            .p_depth_stencil_state = &vk.PipelineDepthStencilStateCreateInfo{
                .depth_test_enable = if (depthEnable) vk.TRUE else vk.FALSE,
                .depth_write_enable = if (depthEnable) vk.TRUE else vk.FALSE,
                .depth_bounds_test_enable = vk.FALSE,
                .stencil_test_enable = vk.FALSE,
                .depth_compare_op = vk.CompareOp.less,
                .min_depth_bounds = 0.0,
                .max_depth_bounds = 1.0,
                .front = stencilOpState,
                .back = stencilOpState,
            },
            .p_color_blend_state = &vk.PipelineColorBlendStateCreateInfo{
                .logic_op_enable = vk.FALSE,
                .logic_op = vk.LogicOp.copy,
                .p_attachments = &colorBlendAttachments,
                .attachment_count = @intCast(colorBlendAttachments.len),
                .blend_constants = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            },
            .p_dynamic_state = &vk.PipelineDynamicStateCreateInfo{
                .p_dynamic_states = &dynamicStates,
                .dynamic_state_count = @intCast(dynamicStates.len),
            },
        },
    };

    _ = try device.createGraphicsPipelines(cache, 1, @ptrCast(&createInfo), null, @ptrCast(&pipeline));

    return pipeline;
}

pub fn getGraphicsCardName() []const u8 {
    return &deviceProperties.device_name;
}

pub fn getDriverVersion() u32 {
    return deviceProperties.driver_version;
}

fn checkSuitable(pdev: vk.PhysicalDevice) !bool {
    return try checkExtensionSupport(pdev);
}

fn getGraphicsFamily(pdev: vk.PhysicalDevice) !u32 {
    var familyCount: u32 = undefined;
    instance.getPhysicalDeviceQueueFamilyProperties(pdev, &familyCount, null);
    const families = try util.mem.fixedBuffer.alloc(vk.QueueFamilyProperties, familyCount);
    defer util.mem.fixedBuffer.free(families);
    instance.getPhysicalDeviceQueueFamilyProperties(pdev, &familyCount, families.ptr);

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
    const memProps = instance.getPhysicalDeviceMemoryProperties(dev);

    for (0..memProps.memory_heap_count) |i| {
        if (memProps.memory_heaps[i].flags.contains(.{ .device_local_bit = true })) {
            return memProps.memory_heaps[i].size;
        }
    }

    return 0;
}

fn hasBetterProperties(new: vk.PhysicalDevice, old: vk.PhysicalDevice) bool {
    const newProps = instance.getPhysicalDeviceProperties(new);
    const oldProps = instance.getPhysicalDeviceProperties(old);

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
    var devCount: u32 = undefined;
    _ = try instance.enumeratePhysicalDevices(&devCount, null);
    const pdevs = try util.mem.fixedBuffer.alloc(vk.PhysicalDevice, devCount);
    defer util.mem.fixedBuffer.free(pdevs);
    _ = try instance.enumeratePhysicalDevices(&devCount, pdevs.ptr);

    var bestDev: ?vk.PhysicalDevice = null;
    for (pdevs) |dev| {
        if (try checkSuitable(dev)) {
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
    var count: u32 = undefined;
    _ = try instance.enumerateDeviceExtensionProperties(pdev, null, &count, null);

    const propsv = try util.mem.fixedBuffer.alloc(vk.ExtensionProperties, count);
    defer util.mem.fixedBuffer.free(propsv);

    _ = try instance.enumerateDeviceExtensionProperties(pdev, null, &count, propsv.ptr);

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
