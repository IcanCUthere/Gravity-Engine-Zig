const std = @import("std");
const core = @import("core");
const builtin = @import("builtin");

pub const glfw = @import("zglfw");
pub const vk = @import("vulkan.zig");

pub usingnamespace vk;

pub var instance: vk.InstProxy = undefined;
pub var device: vk.DevProxy = undefined;
pub var physicalDevice: vk.PhysicalDevice = undefined;
pub var vkAllocator: vk.Allocator = undefined;

var baseDispatch: vk.BaseDispatch = undefined;
var instanceDispatch: vk.InstanceDispatch = undefined;
var deviceDispatch: vk.DeviceDispatch = undefined;

pub var renderFamily: u32 = undefined;
pub var renderQueue: vk.Queue = undefined;

const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
};

pub fn init() !void {
    try glfw.init();

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
        .enabled_layer_count = if (builtin.mode == std.builtin.Mode.Debug) 1 else 0,
        .pp_enabled_layer_names = if (builtin.mode == std.builtin.Mode.Debug) &.{"VK_LAYER_KHRONOS_validation"} else null,
    }, null);

    instanceDispatch = try vk.InstanceDispatch.load(instance.handle, baseDispatch.dispatch.vkGetInstanceProcAddr);
    instance.wrapper = &instanceDispatch;

    var devCount: u32 = undefined;
    _ = try instance.enumeratePhysicalDevices(&devCount, null);

    const pdevs = try core.mem.fba.alloc(vk.PhysicalDevice, devCount);
    defer core.mem.fba.free(pdevs);

    _ = try instance.enumeratePhysicalDevices(&devCount, pdevs.ptr);

    physicalDevice = for (pdevs) |pdev| {
        if (try checkSuitable(pdev)) |dev| {
            break dev;
        }
    } else return error.NoSuitibleDeviceFound;

    renderFamily = try getGraphicsFamily(physicalDevice);

    var familyCount: u32 = undefined;
    instance.getPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, null);

    const priority = [_]f32{1};
    const queueCreateInfo = try core.mem.fba.alloc(vk.DeviceQueueCreateInfo, familyCount);
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

    device.handle = try instance.createDevice(physicalDevice, &.{
        .p_next = &timelineFeature,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = &required_device_extensions,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .p_enabled_features = null,
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
    glfw.terminate();
}

pub fn createRenderPass(viewportFormat: vk.Format) !vk.RenderPass {
    const attachmentDescriptions = [_]vk.AttachmentDescription{
        vk.AttachmentDescription{
            .format = viewportFormat,
            .samples = vk.SampleCountFlags{ .@"1_bit" = true },
            .load_op = vk.AttachmentLoadOp.clear,
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

pub fn createPipeline(layout: vk.PipelineLayout, renderPass: vk.RenderPass, vertModule: vk.ShaderModule, fragModule: vk.ShaderModule, width: u32, height: u32) !vk.Pipeline {
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

    const vertBindings = [_]vk.VertexInputBindingDescription{
        vk.VertexInputBindingDescription{
            .binding = 0,
            .stride = 24,
            .input_rate = vk.VertexInputRate.vertex,
        },
    };
    const vertAttribs = [_]vk.VertexInputAttributeDescription{
        vk.VertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .offset = 0,
            .format = vk.Format.r32g32b32_sfloat,
        },
        //vk.VertexInputAttributeDescription{
        //    .binding = 0,
        //    .location = 1,
        //    .offset = 16,
        //    .format = vk.Format.r32g32_sfloat,
        //},
    };

    const viewports = [_]vk.Viewport{
        vk.Viewport{
            .height = @floatFromInt(width),
            .width = @floatFromInt(height),
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = 0.0,
        },
    };

    const scissors = [_]vk.Rect2D{
        vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .height = height, .width = width },
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
            .color_write_mask = vk.ColorComponentFlags{ .a_bit = true, .r_bit = true, .g_bit = true, .b_bit = true },
            .src_color_blend_factor = vk.BlendFactor.one,
            .dst_color_blend_factor = vk.BlendFactor.zero,
            .src_alpha_blend_factor = vk.BlendFactor.one,
            .dst_alpha_blend_factor = vk.BlendFactor.zero,
        },
    };

    const dynamicStates = [_]vk.DynamicState{
        vk.DynamicState.viewport,
        vk.DynamicState.scissor,
    };

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
                .p_vertex_attribute_descriptions = &vertAttribs,
                .vertex_attribute_description_count = @intCast(vertAttribs.len),
                .p_vertex_binding_descriptions = &vertBindings,
                .vertex_binding_description_count = @intCast(vertBindings.len),
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
                .depth_test_enable = vk.TRUE,
                .depth_write_enable = vk.TRUE,
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

    _ = try device.createGraphicsPipelines(vk.PipelineCache.null_handle, 1, @ptrCast(&createInfo), null, @ptrCast(&pipeline));

    return pipeline;
}

fn checkSuitable(pdev: vk.PhysicalDevice) !?vk.PhysicalDevice {
    if (try checkExtensionSupport(pdev)) {
        return pdev;
    }

    return null;
}

fn getGraphicsFamily(pdev: vk.PhysicalDevice) !u32 {
    var familyCount: u32 = undefined;
    instance.getPhysicalDeviceQueueFamilyProperties(pdev, &familyCount, null);
    const families = try core.mem.fba.alloc(vk.QueueFamilyProperties, familyCount);
    defer core.mem.fba.free(families);
    instance.getPhysicalDeviceQueueFamilyProperties(pdev, &familyCount, families.ptr);

    for (families, 0..) |properties, i| {
        if (properties.queue_flags.graphics_bit) {
            return @intCast(i);
        }
    }

    return error.NoRenderFamilyFound;
}

fn checkExtensionSupport(pdev: vk.PhysicalDevice) !bool {
    var count: u32 = undefined;
    _ = try instance.enumerateDeviceExtensionProperties(pdev, null, &count, null);

    const propsv = try core.mem.fba.alloc(vk.ExtensionProperties, count);
    defer core.mem.fba.free(propsv);

    _ = try instance.enumerateDeviceExtensionProperties(pdev, null, &count, propsv.ptr);

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
