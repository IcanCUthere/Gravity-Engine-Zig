const std = @import("std");
const math = @import("zmath");
const core = @import("core");
const gfx = @import("graphics");
const Viewport = @import("viewport.zig").Viewport;
const Event = @import("event.zig").Event;

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

pub const Application = struct {
    const Self = @This();
    const BufferedImages = 3;

    var AppInstance: Self = Self{};

    _viewport: Viewport = undefined,
    _renderPass: gfx.RenderPass = undefined,
    _shouldRun: bool = true,
    _cmdPools: []gfx.CommandPool = undefined,
    _cmdLists: []gfx.CommandBuffer = undefined,
    _semaphores: []gfx.Semaphore = undefined,
    _timelineSemaphore: gfx.Semaphore = undefined,
    _semaphoreValue: u64 = 1,
    _vertexModule: gfx.ShaderModule = undefined,
    _fragmentModule: gfx.ShaderModule = undefined,
    _descriptorSetLayout: gfx.DescriptorSetLayout = undefined,
    _pipelineLayout: gfx.PipelineLayout = undefined,
    _pipeline: gfx.Pipeline = undefined,
    _stagingBuffer: gfx.BufferAllocation = undefined,
    _vertexBuffer: gfx.BufferAllocation = undefined,
    _indexBuffer: gfx.BufferAllocation = undefined,
    _uniformBuffer: gfx.BufferAllocation = undefined,
    _descriptorPool: gfx.DescriptorPool = undefined,
    _descriptorSet: gfx.DescriptorSet = undefined,

    pub fn callback(self: *Self, e: Event) void {
        switch (e) {
            .resizeEvent => |re| self._viewport.resize(re.width, re.height),
            .closeEvent => |_| self._shouldRun = false,
        }
    }

    pub fn init() !void {
        try gfx.init();

        AppInstance._viewport = try Viewport.init("Gravity Control", 1000, 1000, 3, 1, Self, &AppInstance);

        AppInstance._renderPass = try gfx.createRenderPass(AppInstance._viewport.getFormat());

        AppInstance._viewport.setRenderPass(AppInstance._renderPass);

        AppInstance._cmdPools = try core.mem.fba.alloc(gfx.CommandPool, BufferedImages);
        AppInstance._cmdLists = try core.mem.fba.alloc(gfx.CommandBuffer, BufferedImages);
        AppInstance._semaphores = try core.mem.fba.alloc(gfx.Semaphore, BufferedImages);

        for (AppInstance._cmdPools, AppInstance._cmdLists, AppInstance._semaphores) |*pool, *list, *sem| {
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

        AppInstance._timelineSemaphore = try gfx.device.createSemaphore(&gfx.SemaphoreCreateInfo{
            .p_next = &gfx.SemaphoreTypeCreateInfo{
                .semaphore_type = gfx.SemaphoreType.timeline,
                .initial_value = 0,
            },
        }, null);

        AppInstance._vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.shader_vert.len,
            .p_code = @ptrCast(&shaders.shader_vert),
        }, null);

        AppInstance._fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.shader_frag.len,
            .p_code = @ptrCast(&shaders.shader_frag),
        }, null);

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

        AppInstance._descriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &descriptorBindings,
            .binding_count = @intCast(descriptorBindings.len),
        }, null);

        AppInstance._pipelineLayout = try gfx.device.createPipelineLayout(&gfx.PipelineLayoutCreateInfo{
            .p_set_layouts = @ptrCast(&AppInstance._descriptorSetLayout),
            .set_layout_count = 1,
            .p_push_constant_ranges = null,
            .push_constant_range_count = 0,
        }, null);

        AppInstance._pipeline = try gfx.createPipeline(AppInstance._pipelineLayout, AppInstance._renderPass, AppInstance._vertexModule, AppInstance._fragmentModule, AppInstance._viewport.getWidth(), AppInstance._viewport.getHeight());

        AppInstance._stagingBuffer = try gfx.createBuffer(
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

        AppInstance._vertexBuffer = try gfx.createBuffer(
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

        AppInstance._indexBuffer = try gfx.createBuffer(
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

        AppInstance._uniformBuffer = try gfx.createBuffer(
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

        var matrix = math.identity();

        const data = [_][]align(4) const u8{
            std.mem.sliceAsBytes(positions[0..]),
            std.mem.sliceAsBytes(indices[0..]),
            std.mem.sliceAsBytes(matrix[0..]),
        };

        _ = try gfx.uploadMemory(gfx.vkAllocator, AppInstance._stagingBuffer, data[0..2], 0);
        _ = try gfx.uploadMemory(gfx.vkAllocator, AppInstance._uniformBuffer, data[2..3], 0);

        const poolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
            },
        };

        AppInstance._descriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &poolSizes,
            .pool_size_count = @intCast(poolSizes.len),
            .max_sets = 10,
        }, null);

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = AppInstance._descriptorPool,
            .p_set_layouts = @ptrCast(&AppInstance._descriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&AppInstance._descriptorSet));

        gfx.device.updateDescriptorSets(1, &[_]gfx.WriteDescriptorSet{
            gfx.WriteDescriptorSet{
                .dst_set = AppInstance._descriptorSet,
                .dst_array_element = 0,
                .dst_binding = 0,
                .descriptor_count = 1,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .p_buffer_info = &[_]gfx.DescriptorBufferInfo{
                    gfx.DescriptorBufferInfo{
                        .buffer = AppInstance._uniformBuffer.buffer,
                        .offset = 0,
                        .range = @sizeOf(math.Mat),
                    },
                },
                .p_image_info = @ptrFromInt(32),
                .p_texel_buffer_view = @ptrFromInt(32),
            },
        }, 0, null);

        try gfx.device.beginCommandBuffer(AppInstance._cmdLists[0], &gfx.CommandBufferBeginInfo{
            .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true },
            .p_inheritance_info = null,
        });

        gfx.device.cmdCopyBuffer(AppInstance._cmdLists[0], AppInstance._stagingBuffer.buffer, AppInstance._vertexBuffer.buffer, 1, &[_]gfx.BufferCopy{
            gfx.BufferCopy{
                .src_offset = 0,
                .dst_offset = 0,
                .size = @sizeOf(@TypeOf(positions)),
            },
        });

        gfx.device.cmdCopyBuffer(AppInstance._cmdLists[0], AppInstance._stagingBuffer.buffer, AppInstance._indexBuffer.buffer, 1, &[_]gfx.BufferCopy{
            gfx.BufferCopy{
                .src_offset = @sizeOf(@TypeOf(positions)),
                .dst_offset = 0,
                .size = @sizeOf(@TypeOf(indices)),
            },
        });

        try gfx.device.endCommandBuffer(AppInstance._cmdLists[0]);

        try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
            gfx.SubmitInfo{
                .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                    .p_signal_semaphore_values = &[_]u64{1},
                    .signal_semaphore_value_count = 1,
                    .p_wait_semaphore_values = null,
                    .wait_semaphore_value_count = 0,
                },
                .p_command_buffers = &[_]gfx.CommandBuffer{AppInstance._cmdLists[0]},
                .command_buffer_count = 1,
                .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{.{ .transfer_bit = true }},
                .p_signal_semaphores = &[_]gfx.Semaphore{AppInstance._timelineSemaphore},
                .signal_semaphore_count = 1,
                .p_wait_semaphores = null,
                .wait_semaphore_count = 0,
            },
        }, gfx.Fence.null_handle);
    }

    pub fn deinit() !void {
        _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&AppInstance._timelineSemaphore),
            .p_values = @ptrCast(&AppInstance._semaphoreValue),
            .semaphore_count = 1,
        }, ~@as(u64, 0));

        gfx.device.destroyDescriptorPool(AppInstance._descriptorPool, null);

        gfx.destroyBuffer(gfx.vkAllocator, AppInstance._uniformBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, AppInstance._indexBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, AppInstance._vertexBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, AppInstance._stagingBuffer);

        gfx.device.destroyPipeline(AppInstance._pipeline, null);
        gfx.device.destroyPipelineLayout(AppInstance._pipelineLayout, null);
        gfx.device.destroyDescriptorSetLayout(AppInstance._descriptorSetLayout, null);
        gfx.device.destroyShaderModule(AppInstance._fragmentModule, null);
        gfx.device.destroyShaderModule(AppInstance._vertexModule, null);

        for (AppInstance._cmdPools, AppInstance._semaphores) |pool, sem| {
            gfx.device.destroySemaphore(sem, null);
            gfx.device.destroyCommandPool(pool, null);
        }

        gfx.device.destroySemaphore(AppInstance._timelineSemaphore, null);

        core.mem.fba.free(AppInstance._semaphores);
        core.mem.fba.free(AppInstance._cmdLists);
        core.mem.fba.free(AppInstance._cmdPools);
        gfx.device.destroyRenderPass(AppInstance._renderPass, null);
        AppInstance._viewport.deinit();
        gfx.deinit();
    }

    pub fn run() !void {
        var imageIndex: u32 = 0;
        AppInstance._semaphoreValue = 1;
        var currentRotation: f32 = 0.0;

        var timer = try std.time.Timer.start();
        while (AppInstance._shouldRun) {
            const deltaTime: f32 = @as(f32, @floatFromInt(timer.lap())) / 1_000_000_000.0;
            currentRotation += deltaTime * std.math.degreesToRadians(45.0);

            const width: f32 = @floatFromInt(AppInstance._viewport.getWidth());
            const height: f32 = @floatFromInt(AppInstance._viewport.getHeight());
            const aspectRatio: f32 = width / height;
            const projectionwMatrix = math.perspectiveFovRh(std.math.degreesToRadians(90.0), aspectRatio, 0.1, 10000.0);
            const cameraMatrix = math.lookAtRh(math.Vec{ 2.0, 0.0, 2.0, 1.0 }, math.Vec{ 0.0, 0.0, 0.0, 1.0 }, math.Vec{ 0.0, 1.0, 0.0, 0.0 });
            const modelMatrix = math.rotationY(currentRotation);

            var finalMatrix = math.mul(math.mul(modelMatrix, cameraMatrix), projectionwMatrix);

            const data2 = [_][]align(4) const u8{
                std.mem.sliceAsBytes(finalMatrix[0..]),
            };

            _ = try gfx.uploadMemory(gfx.vkAllocator, AppInstance._uniformBuffer, data2[0..1], 0);

            try AppInstance._viewport.nextFrame(AppInstance._semaphores[imageIndex]);

            const waitValue: u64 = if (1 > AppInstance._semaphoreValue - 1) 1 else AppInstance._semaphoreValue - 1;
            AppInstance._semaphoreValue += 1;

            _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
                .p_semaphores = @ptrCast(&AppInstance._timelineSemaphore),
                .p_values = &[_]u64{waitValue},
                .semaphore_count = 1,
            }, ~@as(u64, 0));

            try gfx.device.resetCommandPool(AppInstance._cmdPools[imageIndex], .{});

            try gfx.device.beginCommandBuffer(AppInstance._cmdLists[imageIndex], &gfx.CommandBufferBeginInfo{
                .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true },
                .p_inheritance_info = &gfx.CommandBufferInheritanceInfo{
                    .render_pass = AppInstance._renderPass,
                    .framebuffer = AppInstance._viewport.getFramebuffer(),
                    .subpass = 0,
                    .occlusion_query_enable = gfx.FALSE,
                },
            });

            const clearValues = [_]gfx.ClearValue{
                gfx.ClearValue{ .color = .{ .float_32 = [4]f32{ 0.0, 0.0, 0.0, 0.0 } } },
                gfx.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
            };

            const renderArea = gfx.Rect2D{
                .offset = gfx.Offset2D{ .x = 0, .y = 0 },
                .extent = gfx.Extent2D{
                    .width = AppInstance._viewport.getWidth(),
                    .height = AppInstance._viewport.getHeight(),
                },
            };

            const barriers = [_]gfx.BufferMemoryBarrier{
                gfx.BufferMemoryBarrier{
                    .buffer = AppInstance._vertexBuffer.buffer,
                    .offset = 0,
                    .size = @sizeOf(@TypeOf(positions)),
                    .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                    .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                    .src_queue_family_index = gfx.renderFamily,
                    .dst_queue_family_index = gfx.renderFamily,
                },
                gfx.BufferMemoryBarrier{
                    .buffer = AppInstance._indexBuffer.buffer,
                    .offset = 0,
                    .size = @sizeOf(@TypeOf(indices)),
                    .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                    .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                    .src_queue_family_index = gfx.renderFamily,
                    .dst_queue_family_index = gfx.renderFamily,
                },
            };

            gfx.device.cmdPipelineBarrier(
                AppInstance._cmdLists[imageIndex],
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

            gfx.device.cmdBeginRenderPass(AppInstance._cmdLists[imageIndex], &gfx.RenderPassBeginInfo{
                .render_pass = AppInstance._renderPass,
                .framebuffer = AppInstance._viewport.getFramebuffer(),
                .render_area = renderArea,
                .p_clear_values = @ptrCast(&clearValues),
                .clear_value_count = @intCast(clearValues.len),
            }, gfx.SubpassContents.@"inline");

            gfx.device.cmdBindPipeline(AppInstance._cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, AppInstance._pipeline);
            gfx.device.cmdSetViewport(AppInstance._cmdLists[imageIndex], 0, 1, @ptrCast(&gfx.Viewport{
                .height = @floatFromInt(AppInstance._viewport.getHeight()),
                .width = @floatFromInt(AppInstance._viewport.getWidth()),
                .min_depth = 0.0,
                .max_depth = 1.0,
                .x = 0.0,
                .y = 0.0,
            }));
            gfx.device.cmdSetScissor(AppInstance._cmdLists[imageIndex], 0, 1, @ptrCast(&renderArea));
            gfx.device.cmdBindVertexBuffers(AppInstance._cmdLists[imageIndex], 0, 1, @ptrCast(&AppInstance._vertexBuffer.buffer), &[_]u64{0});
            gfx.device.cmdBindIndexBuffer(AppInstance._cmdLists[imageIndex], AppInstance._indexBuffer.buffer, 0, gfx.IndexType.uint32);
            gfx.device.cmdBindDescriptorSets(AppInstance._cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, AppInstance._pipelineLayout, 0, 1, @ptrCast(&AppInstance._descriptorSet), 0, null);
            gfx.device.cmdDrawIndexed(AppInstance._cmdLists[imageIndex], indices.len, 1, 0, 0, 0);
            gfx.device.cmdEndRenderPass(AppInstance._cmdLists[imageIndex]);
            try gfx.device.endCommandBuffer(AppInstance._cmdLists[imageIndex]);

            try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
                gfx.SubmitInfo{
                    .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                        .p_signal_semaphore_values = @ptrCast(&AppInstance._semaphoreValue),
                        .signal_semaphore_value_count = 2,
                        .p_wait_semaphore_values = null,
                        .wait_semaphore_value_count = 0,
                    },
                    .p_command_buffers = &[_]gfx.CommandBuffer{AppInstance._cmdLists[imageIndex]},
                    .command_buffer_count = 1,
                    .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{.{ .color_attachment_output_bit = true }},
                    .p_signal_semaphores = &[_]gfx.Semaphore{ AppInstance._timelineSemaphore, AppInstance._semaphores[imageIndex] },
                    .signal_semaphore_count = 2,
                    .p_wait_semaphores = @ptrCast(&AppInstance._semaphores[imageIndex]),
                    .wait_semaphore_count = 1,
                },
            }, gfx.Fence.null_handle);

            try AppInstance._viewport.presentImage(&AppInstance._semaphores[imageIndex], 1);

            imageIndex = (imageIndex + 1) % BufferedImages;
        }
    }
};
