const std = @import("std");
const glfw = @import("zglfw");
const math = @import("zmath");
const builtin = @import("builtin");
const gfx = @import("graphics.zig");
const viewport = @import("viewport.zig");
const mem = @import("memory.zig");

const shaders = @import("shaders");

const positions = [48]f32{
    -0.5, -0.5, 0.5, 0.0, 1.0, 0.0,
    0.5,  0.5,  0.5, 0.0, 0.0, 1.0,
    -0.5, 0.5,  0.5, 0.0, 1.0, 1.0,
    0.5,  -0.5, 0.5, 0.0, 0.0, 0.0,

    -0.5, -0.5, 0.0, 0.0, 1.0, 0.0,
    0.5,  0.5,  0.0, 0.0, 0.0, 1.0,
    -0.5, 0.5,  0.0, 0.0, 1.0, 1.0,
    0.5,  -0.5, 0.0, 0.0, 0.0, 0.0,
};

const indices = [12]u32{
    2, 1, 0,
    0, 1, 3,

    6, 5, 4,
    4, 5, 7,
};

pub fn main() !void {
    try gfx.init();
    defer gfx.deinit();

    const renderPass = try gfx.createRenderPass();
    defer gfx.device.destroyRenderPass(renderPass, null);

    var window = try viewport.init("Gravity Control", 1000, 1000, renderPass, 3, 1);
    defer window.deinit();

    const cmdPools = try mem.fba.alloc(gfx.CommandPool, window.getImageCount());
    defer mem.fba.free(cmdPools);

    const cmdLists = try mem.fba.alloc(gfx.CommandBuffer, window.getImageCount());
    defer mem.fba.free(cmdLists);

    const semaphores = try mem.fba.alloc(gfx.Semaphore, window.getImageCount());
    defer mem.fba.free(semaphores);

    for (cmdPools, cmdLists, semaphores) |*pool, *list, *sem| {
        pool.* = try gfx.device.createCommandPool(&.{
            .queue_family_index = gfx.renderFamily,
        }, null);

        try gfx.device.allocateCommandBuffers(&.{
            .command_pool = pool.*,
            .level = gfx.CommandBufferLevel.primary,
            .command_buffer_count = 1,
        }, @ptrCast(list));

        sem.* = try gfx.device.createSemaphore(&.{}, null);
    }

    const timelineSemaphore = try gfx.device.createSemaphore(&gfx.SemaphoreCreateInfo{
        .p_next = &gfx.SemaphoreTypeCreateInfo{
            .semaphore_type = gfx.SemaphoreType.timeline,
            .initial_value = 0,
        },
    }, null);
    defer gfx.device.destroySemaphore(timelineSemaphore, null);

    defer for (cmdPools, semaphores) |pool, sem| {
        gfx.device.destroySemaphore(sem, null);
        gfx.device.destroyCommandPool(pool, null);
    };

    const vert_module = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
        .code_size = shaders.shader_vert.len,
        .p_code = @ptrCast(&shaders.shader_vert),
    }, null);
    defer gfx.device.destroyShaderModule(vert_module, null);

    const frag_module = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
        .code_size = shaders.shader_frag.len,
        .p_code = @ptrCast(&shaders.shader_frag),
    }, null);
    defer gfx.device.destroyShaderModule(frag_module, null);

    const descriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
        gfx.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_type = gfx.DescriptorType.uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
        },
        //gfx.DescriptorSetLayoutBinding{
        //    .binding = 1,
        //    .descriptor_type = gfx.DescriptorType.combined_image_sampler,
        //    .descriptor_count = 1,
        //    .stage_flags = gfx.ShaderStageFlags{ .fragment_bit = true },
        //},
    };

    const descriptorLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
        .p_bindings = &descriptorBindings,
        .binding_count = @intCast(descriptorBindings.len),
    }, null);
    defer gfx.device.destroyDescriptorSetLayout(descriptorLayout, null);

    const pipelineLayout = try gfx.device.createPipelineLayout(&gfx.PipelineLayoutCreateInfo{
        .p_set_layouts = @ptrCast(&descriptorLayout),
        .set_layout_count = 1,
        .p_push_constant_ranges = null,
        .push_constant_range_count = 0,
    }, null);
    defer gfx.device.destroyPipelineLayout(pipelineLayout, null);

    const pipeline = try createPipeline(pipelineLayout, window, vert_module, frag_module);
    defer gfx.device.destroyPipeline(pipeline, null);

    const stagingBuffer = try gfx.createBuffer(
        gfx.vkAllocator,
        &gfx.BufferCreateInfo{
            .size = @sizeOf(@TypeOf(positions)) + @sizeOf(@TypeOf(indices)),
            .usage = gfx.BufferUsageFlags{ .transfer_src_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
        },
        &gfx.vma.VmaAllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
        },
    );
    defer gfx.destroyBuffer(gfx.vkAllocator, stagingBuffer);

    const vertexBuffer = try gfx.createBuffer(
        gfx.vkAllocator,
        &gfx.BufferCreateInfo{
            .size = @sizeOf(@TypeOf(positions)),
            .usage = gfx.BufferUsageFlags{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
        },
        &gfx.vma.VmaAllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        },
    );
    defer gfx.destroyBuffer(gfx.vkAllocator, vertexBuffer);

    const indexBuffer = try gfx.createBuffer(
        gfx.vkAllocator,
        &gfx.BufferCreateInfo{
            .size = @sizeOf(@TypeOf(positions)),
            .usage = gfx.BufferUsageFlags{ .index_buffer_bit = true, .transfer_dst_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
        },
        &gfx.vma.VmaAllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        },
    );
    defer gfx.destroyBuffer(gfx.vkAllocator, indexBuffer);

    const uniformBuffer = try gfx.createBuffer(
        gfx.vkAllocator,
        &gfx.BufferCreateInfo{
            .size = @sizeOf(@TypeOf(positions)),
            .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true, .transfer_dst_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
        },
        &gfx.vma.VmaAllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
        },
    );
    defer gfx.destroyBuffer(gfx.vkAllocator, uniformBuffer);

    var matrix = math.identity();

    const data = [_][]align(4) const u8{
        std.mem.sliceAsBytes(positions[0..]),
        std.mem.sliceAsBytes(indices[0..]),
        std.mem.sliceAsBytes(matrix[0..]),
    };

    _ = try gfx.uploadMemory(gfx.vkAllocator, stagingBuffer, data[0..2], 0);
    _ = try gfx.uploadMemory(gfx.vkAllocator, uniformBuffer, data[2..3], 0);

    const poolSizes = [_]gfx.DescriptorPoolSize{
        gfx.DescriptorPoolSize{
            .type = gfx.DescriptorType.uniform_buffer,
            .descriptor_count = 1,
        },
    };

    const descriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
        .p_pool_sizes = &poolSizes,
        .pool_size_count = @intCast(poolSizes.len),
        .max_sets = 10,
    }, null);
    defer gfx.device.destroyDescriptorPool(descriptorPool, null);

    var descriptorSet: gfx.DescriptorSet = undefined;
    try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
        .descriptor_pool = descriptorPool,
        .p_set_layouts = @ptrCast(&descriptorLayout),
        .descriptor_set_count = 1,
    }, @ptrCast(&descriptorSet));

    gfx.device.updateDescriptorSets(1, &[_]gfx.WriteDescriptorSet{
        gfx.WriteDescriptorSet{
            .dst_set = descriptorSet,
            .dst_array_element = 0,
            .dst_binding = 0,
            .descriptor_count = 1,
            .descriptor_type = gfx.DescriptorType.uniform_buffer,
            .p_buffer_info = &[_]gfx.DescriptorBufferInfo{
                gfx.DescriptorBufferInfo{
                    .buffer = uniformBuffer.buffer,
                    .offset = 0,
                    .range = @sizeOf(math.Mat),
                },
            },
            .p_image_info = @ptrFromInt(32),
            .p_texel_buffer_view = @ptrFromInt(32),
        },
    }, 0, null);

    try gfx.device.beginCommandBuffer(cmdLists[0], &gfx.CommandBufferBeginInfo{
        .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    });

    gfx.device.cmdCopyBuffer(cmdLists[0], stagingBuffer.buffer, vertexBuffer.buffer, 1, &[_]gfx.BufferCopy{
        gfx.BufferCopy{
            .src_offset = 0,
            .dst_offset = 0,
            .size = @sizeOf(@TypeOf(positions)),
        },
    });

    gfx.device.cmdCopyBuffer(cmdLists[0], stagingBuffer.buffer, indexBuffer.buffer, 1, &[_]gfx.BufferCopy{
        gfx.BufferCopy{
            .src_offset = @sizeOf(@TypeOf(positions)),
            .dst_offset = 0,
            .size = @sizeOf(@TypeOf(indices)),
        },
    });

    try gfx.device.endCommandBuffer(cmdLists[0]);

    try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
        gfx.SubmitInfo{
            .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                .p_signal_semaphore_values = &[_]u64{1},
                .signal_semaphore_value_count = 1,
                .p_wait_semaphore_values = null,
                .wait_semaphore_value_count = 0,
            },
            .p_command_buffers = &[_]gfx.CommandBuffer{cmdLists[0]},
            .command_buffer_count = 1,
            .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{.{ .transfer_bit = true }},
            .p_signal_semaphores = &[_]gfx.Semaphore{timelineSemaphore},
            .signal_semaphore_count = 1,
            .p_wait_semaphores = null,
            .wait_semaphore_count = 0,
        },
    }, gfx.Fence.null_handle);

    var imageIndex: u32 = 0;
    var semaphoreValue: u64 = 1;
    var currentRotation: f32 = 0.0;

    var timer = try std.time.Timer.start();
    while (!window._window.shouldClose()) {
        const deltaTime: f32 = @as(f32, @floatFromInt(timer.lap())) / 1_000_000_000.0;
        currentRotation += deltaTime * std.math.degreesToRadians(45.0);

        const width: f32 = @floatFromInt(window.getWidth());
        const height: f32 = @floatFromInt(window.getHeight());
        const aspectRatio: f32 = width / height;
        const projectionwMatrix = math.perspectiveFovRh(std.math.degreesToRadians(90.0), aspectRatio, 0.1, 10000.0);
        const cameraMatrix = math.lookAtRh(math.Vec{ 2.0, 0.0, 2.0, 1.0 }, math.Vec{ 0.0, 0.0, 0.0, 1.0 }, math.Vec{ 0.0, 1.0, 0.0, 0.0 });
        const modelMatrix = math.rotationY(currentRotation);

        var finalMatrix = math.mul(math.mul(modelMatrix, cameraMatrix), projectionwMatrix);

        const data2 = [_][]align(4) const u8{
            std.mem.sliceAsBytes(finalMatrix[0..]),
        };

        _ = try gfx.uploadMemory(gfx.vkAllocator, uniformBuffer, data2[0..1], 0);

        try window.nextFrame(semaphores[imageIndex]);

        const waitValue: u64 = if (1 > semaphoreValue - 1) 1 else semaphoreValue - 1;
        semaphoreValue += 1;

        _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&timelineSemaphore),
            .p_values = &[_]u64{waitValue},
            .semaphore_count = 1,
        }, ~@as(u64, 0));

        try gfx.device.resetCommandPool(cmdPools[imageIndex], .{});

        try gfx.device.beginCommandBuffer(cmdLists[imageIndex], &gfx.CommandBufferBeginInfo{ .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true }, .p_inheritance_info = &gfx.CommandBufferInheritanceInfo{
            .render_pass = renderPass,
            .framebuffer = window.getFramebuffer(),
            .subpass = 0,
            .occlusion_query_enable = gfx.FALSE,
        } });

        const clearValues = [_]gfx.ClearValue{
            gfx.ClearValue{ .color = .{ .float_32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 } } },
            gfx.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = window.getWidth(),
                .height = window.getHeight(),
            },
        };

        const barriers = [_]gfx.BufferMemoryBarrier{
            gfx.BufferMemoryBarrier{
                .buffer = vertexBuffer.buffer,
                .offset = 0,
                .size = @sizeOf(@TypeOf(positions)),
                .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                .src_queue_family_index = gfx.renderFamily,
                .dst_queue_family_index = gfx.renderFamily,
            },
            gfx.BufferMemoryBarrier{
                .buffer = indexBuffer.buffer,
                .offset = 0,
                .size = @sizeOf(@TypeOf(indices)),
                .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                .src_queue_family_index = gfx.renderFamily,
                .dst_queue_family_index = gfx.renderFamily,
            },
        };

        gfx.device.cmdPipelineBarrier(
            cmdLists[imageIndex],
            gfx.PipelineStageFlags{ .transfer_bit = true },
            gfx.PipelineStageFlags{ .vertex_input_bit = true },
            gfx.DependencyFlags{},
            0,
            null,
            2,
            &barriers,
            0,
            null,
        );

        gfx.device.cmdBeginRenderPass(cmdLists[imageIndex], &gfx.RenderPassBeginInfo{
            .render_pass = renderPass,
            .framebuffer = window.getFramebuffer(),
            .render_area = renderArea,
            .p_clear_values = @ptrCast(&clearValues),
            .clear_value_count = @intCast(clearValues.len),
        }, gfx.SubpassContents.@"inline");

        gfx.device.cmdBindPipeline(cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, pipeline);
        gfx.device.cmdSetViewport(cmdLists[imageIndex], 0, 1, @ptrCast(&gfx.Viewport{
            .height = @floatFromInt(window.getHeight()),
            .width = @floatFromInt(window.getWidth()),
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = 0.0,
        }));
        gfx.device.cmdSetScissor(cmdLists[imageIndex], 0, 1, @ptrCast(&renderArea));
        gfx.device.cmdBindVertexBuffers(cmdLists[imageIndex], 0, 1, @ptrCast(&vertexBuffer.buffer), &[_]u64{0});
        gfx.device.cmdBindIndexBuffer(cmdLists[imageIndex], indexBuffer.buffer, 0, gfx.IndexType.uint32);
        gfx.device.cmdBindDescriptorSets(cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, pipelineLayout, 0, 1, @ptrCast(&descriptorSet), 0, null);
        gfx.device.cmdDrawIndexed(cmdLists[imageIndex], indices.len, 1, 0, 0, 0);
        gfx.device.cmdEndRenderPass(cmdLists[imageIndex]);
        try gfx.device.endCommandBuffer(cmdLists[imageIndex]);

        try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
            gfx.SubmitInfo{
                .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                    .p_signal_semaphore_values = @ptrCast(&semaphoreValue),
                    .signal_semaphore_value_count = 2,
                    .p_wait_semaphore_values = null,
                    .wait_semaphore_value_count = 0,
                },
                .p_command_buffers = &[_]gfx.CommandBuffer{cmdLists[imageIndex]},
                .command_buffer_count = 1,
                .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{.{ .color_attachment_output_bit = true }},
                .p_signal_semaphores = &[_]gfx.Semaphore{ timelineSemaphore, semaphores[imageIndex] },
                .signal_semaphore_count = 2,
                .p_wait_semaphores = @ptrCast(&semaphores[imageIndex]),
                .wait_semaphore_count = 1,
            },
        }, gfx.Fence.null_handle);

        try window.presentImage(&semaphores[imageIndex], 1);

        imageIndex = (imageIndex + 1) % window.getImageCount();
    }

    _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
        .p_semaphores = @ptrCast(&timelineSemaphore),
        .p_values = @ptrCast(&semaphoreValue),
        .semaphore_count = 1,
    }, ~@as(u64, 0));
}

pub fn createPipeline(layout: gfx.PipelineLayout, window: viewport.Viewport, vertModule: gfx.ShaderModule, fragModule: gfx.ShaderModule) !gfx.Pipeline {
    const stages = [_]gfx.PipelineShaderStageCreateInfo{
        gfx.PipelineShaderStageCreateInfo{
            .p_name = "main",
            .stage = gfx.ShaderStageFlags{ .vertex_bit = true },
            .module = vertModule,
        },
        gfx.PipelineShaderStageCreateInfo{
            .p_name = "main",
            .stage = gfx.ShaderStageFlags{ .fragment_bit = true },
            .module = fragModule,
        },
    };

    const vertBindings = [_]gfx.VertexInputBindingDescription{
        gfx.VertexInputBindingDescription{
            .binding = 0,
            .stride = 24,
            .input_rate = gfx.VertexInputRate.vertex,
        },
    };
    const vertAttribs = [_]gfx.VertexInputAttributeDescription{
        gfx.VertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .offset = 0,
            .format = gfx.Format.r32g32b32_sfloat,
        },
        //gfx.VertexInputAttributeDescription{
        //    .binding = 0,
        //    .location = 1,
        //    .offset = 16,
        //    .format = gfx.Format.r32g32_sfloat,
        //},
    };

    const viewports = [_]gfx.Viewport{
        gfx.Viewport{
            .height = @floatFromInt(window.getHeight()),
            .width = @floatFromInt(window.getWidth()),
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = 0.0,
        },
    };

    const scissors = [_]gfx.Rect2D{
        gfx.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .height = window.getHeight(), .width = window.getWidth() },
        },
    };

    const stencilOpState = gfx.StencilOpState{
        .pass_op = gfx.StencilOp.keep,
        .fail_op = gfx.StencilOp.keep,
        .depth_fail_op = gfx.StencilOp.keep,
        .compare_op = gfx.CompareOp.always,
        .compare_mask = 0,
        .reference = 0,
        .write_mask = 0,
    };

    const colorBlendAttachments = [_]gfx.PipelineColorBlendAttachmentState{
        gfx.PipelineColorBlendAttachmentState{
            .blend_enable = gfx.FALSE,
            .color_blend_op = gfx.BlendOp.add,
            .alpha_blend_op = gfx.BlendOp.add,
            .color_write_mask = gfx.ColorComponentFlags{ .a_bit = true, .r_bit = true, .g_bit = true, .b_bit = true },
            .src_color_blend_factor = gfx.BlendFactor.one,
            .dst_color_blend_factor = gfx.BlendFactor.zero,
            .src_alpha_blend_factor = gfx.BlendFactor.one,
            .dst_alpha_blend_factor = gfx.BlendFactor.zero,
        },
    };

    const dynamicStates = [_]gfx.DynamicState{
        gfx.DynamicState.viewport,
        gfx.DynamicState.scissor,
    };

    var pipeline: gfx.Pipeline = undefined;

    const createInfo = [_]gfx.GraphicsPipelineCreateInfo{
        gfx.GraphicsPipelineCreateInfo{
            .layout = layout,
            .render_pass = window._renderPass,
            .subpass = 0,
            .base_pipeline_index = 0,
            .base_pipeline_handle = gfx.Pipeline.null_handle,
            .p_stages = &stages,
            .stage_count = @intCast(stages.len),
            .p_vertex_input_state = &gfx.PipelineVertexInputStateCreateInfo{
                .p_vertex_attribute_descriptions = &vertAttribs,
                .vertex_attribute_description_count = @intCast(vertAttribs.len),
                .p_vertex_binding_descriptions = &vertBindings,
                .vertex_binding_description_count = @intCast(vertBindings.len),
            },
            .p_input_assembly_state = &gfx.PipelineInputAssemblyStateCreateInfo{
                .primitive_restart_enable = gfx.FALSE,
                .topology = gfx.PrimitiveTopology.triangle_list,
            },
            .p_tessellation_state = &gfx.PipelineTessellationStateCreateInfo{
                .patch_control_points = 0,
            },
            .p_viewport_state = &gfx.PipelineViewportStateCreateInfo{
                .p_viewports = &viewports,
                .viewport_count = @intCast(viewports.len),
                .p_scissors = &scissors,
                .scissor_count = @intCast(scissors.len),
            },
            .p_rasterization_state = &gfx.PipelineRasterizationStateCreateInfo{
                .polygon_mode = gfx.PolygonMode.fill,
                .cull_mode = gfx.CullModeFlags{ .back_bit = true },
                .front_face = gfx.FrontFace.counter_clockwise,
                .depth_bias_enable = gfx.FALSE,
                .depth_clamp_enable = gfx.FALSE,
                .rasterizer_discard_enable = gfx.FALSE,
                .depth_bias_clamp = 0.0,
                .depth_bias_constant_factor = 0.0,
                .depth_bias_slope_factor = 0.0,
                .line_width = 1.0,
            },
            .p_multisample_state = &gfx.PipelineMultisampleStateCreateInfo{
                .rasterization_samples = gfx.SampleCountFlags{ .@"1_bit" = true },
                .alpha_to_coverage_enable = gfx.FALSE,
                .alpha_to_one_enable = gfx.FALSE,
                .sample_shading_enable = gfx.FALSE,
                .min_sample_shading = 1.0,
                .p_sample_mask = null,
            },
            .p_depth_stencil_state = &gfx.PipelineDepthStencilStateCreateInfo{
                .depth_test_enable = gfx.TRUE,
                .depth_write_enable = gfx.TRUE,
                .depth_bounds_test_enable = gfx.FALSE,
                .stencil_test_enable = gfx.FALSE,
                .depth_compare_op = gfx.CompareOp.less,
                .min_depth_bounds = 0.0,
                .max_depth_bounds = 1.0,
                .front = stencilOpState,
                .back = stencilOpState,
            },
            .p_color_blend_state = &gfx.PipelineColorBlendStateCreateInfo{
                .logic_op_enable = gfx.FALSE,
                .logic_op = gfx.LogicOp.copy,
                .p_attachments = &colorBlendAttachments,
                .attachment_count = @intCast(colorBlendAttachments.len),
                .blend_constants = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            },
            .p_dynamic_state = &gfx.PipelineDynamicStateCreateInfo{
                .p_dynamic_states = &dynamicStates,
                .dynamic_state_count = @intCast(dynamicStates.len),
            },
        },
    };

    _ = try gfx.device.createGraphicsPipelines(gfx.PipelineCache.null_handle, 1, @ptrCast(&createInfo), null, @ptrCast(&pipeline));

    return pipeline;
}
