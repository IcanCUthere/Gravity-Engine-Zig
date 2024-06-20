const std = @import("std");
const math = @import("zmath");
const msh = @import("zmesh");
const core = @import("core");
const gfx = @import("graphics");
const Viewport = @import("viewport.zig").Viewport;
const Camera = @import("camera.zig").Camera;
const evnt = @import("event.zig");

const shaders = @import("shaders");

const Vertex = struct {
    pos: [3]f32,
    normal: [3]f32,
};

pub fn init() !void {
    const AppInstance = &Application.AppInstance;

    try gfx.init();
    msh.init(core.mem.ha);

    const testModel = try msh.io.parseAndLoadFile("resources/Avocado.glb");

    var allocated: bool = false;

    for (0..testModel.meshes_count) |i| {
        for (0..testModel.meshes.?[i].primitives_count) |j| {
            for (0..testModel.meshes.?[i].primitives[j].attributes_count) |k| {
                const attrib = &testModel.meshes.?[i].primitives[j].attributes[k];
                const vertices = attrib.data;

                std.log.info("{s}", .{@tagName(attrib.type)});

                if (attrib.type == msh.io.zcgltf.AttributeType.position) {
                    if (!allocated) {
                        AppInstance.vertecies = try core.mem.ha.alloc(Vertex, vertices.count);
                        allocated = true;
                    }

                    for (0..vertices.count) |l| {
                        //var floats = try core.mem.ha.alloc(f32, vertices.unpackFloatsCount());
                        //defer core.mem.ha.free(floats);
                        //floats = vertices.unpackFloats(floats);

                        _ = vertices.readFloat(l, AppInstance.vertecies[l].pos[0..]);
                        //std.log.info("{d} {d} {d}", .{ AppInstance.vertecies[l].pos[0], AppInstance.vertecies[l].pos[1], AppInstance.vertecies[l].pos[1] });
                    }
                } else if (attrib.type == msh.io.zcgltf.AttributeType.normal) {
                    if (!allocated) {
                        AppInstance.vertecies = try core.mem.ha.alloc(Vertex, vertices.count);
                        allocated = true;
                    }

                    for (0..vertices.count) |l| {
                        _ = vertices.readFloat(l, AppInstance.vertecies[l].normal[0..]);
                        //std.log.info("{d} {d} {d}", .{ AppInstance.vertecies[l].normal[0], AppInstance.vertecies[l].normal[1], AppInstance.vertecies[l].normal[1] });
                    }
                }
            }

            const indices = testModel.meshes.?[i].primitives[j].indices;

            if (indices == null) {
                AppInstance.indices = try core.mem.ha.alloc(u32, AppInstance.vertecies.len);

                for (AppInstance.indices, 0..) |*l, m| {
                    l.* = @intCast(m);
                }
            } else {
                AppInstance.indices = try core.mem.ha.alloc(u32, indices.?.count);

                for (0..indices.?.count / indices.?.type.numComponents()) |l| {
                    const index: usize = indices.?.readIndex(l);

                    AppInstance.indices[l] = @intCast(index);
                }
            }
        }
    }

    for (AppInstance.vertecies) |*v| {
        v.pos[0] *= 100.0;
        v.pos[1] *= 100.0;
        v.pos[2] *= 100.0;
    }

    //var model = msh.Shape.initRock(3452345, 5);
    //model.computeNormals();

    //const vertices = try core.mem.ha.alloc(Vertex, model.positions.len);

    //for (model.positions, model.normals.?, vertices) |p, n, *v| {
    //    v.pos = p;
    //    v.normal = n;
    //}

    const width: f32 = 1000.0;
    const height: f32 = 1000.0;
    const aspectRatio: f32 = width / height;

    AppInstance._camera = Camera.init(.{ 0.0, 0.0, -200.0, 0.0 }, .{ 0.0, 0.0, std.math.degreesToRadians(180.0), 0.0 }, aspectRatio, 45.0, 0.1, 10000.0);

    AppInstance._viewport = try Viewport.init("Gravity Control", @intFromFloat(width), @intFromFloat(height), 3, 1, Application.onEvent);

    AppInstance._lastMouseX = AppInstance._viewport.getMousePosition()[0];
    AppInstance._lastMouseY = AppInstance._viewport.getMousePosition()[1];
    AppInstance._viewport.setCursorEnabled(false);

    AppInstance._renderPass = try gfx.createRenderPass(AppInstance._viewport.getFormat());

    AppInstance._viewport.setRenderPass(AppInstance._renderPass);

    AppInstance._cmdPools = try core.mem.ha.alloc(gfx.CommandPool, Application.BufferedImages);
    AppInstance._cmdLists = try core.mem.ha.alloc(gfx.CommandBuffer, Application.BufferedImages);
    AppInstance._semaphores = try core.mem.ha.alloc(gfx.Semaphore, Application.BufferedImages);

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
            .size = (AppInstance.vertecies.len * @sizeOf(Vertex)) + (AppInstance.indices.len * @sizeOf(u32)),
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
            .size = AppInstance.vertecies.len * @sizeOf(Vertex),
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
            .size = AppInstance.indices.len * @sizeOf(u32),
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
            .size = 3 * @sizeOf(math.Mat),
            .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true, .transfer_dst_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
        },
        &gfx.vma.VmaAllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
        },
    );

    //var matrix1 = math.identity();
    //var matrix2 = math.identity();
    //var matrix3 = math.identity();

    const data = [_][]align(4) const u8{
        std.mem.sliceAsBytes(AppInstance.vertecies[0..]),
        std.mem.sliceAsBytes(AppInstance.indices[0..]),
        //std.mem.sliceAsBytes(matrix1[0..]),
        //std.mem.sliceAsBytes(matrix2[0..]),
        //std.mem.sliceAsBytes(matrix3[0..]),
    };

    _ = try gfx.uploadMemory(gfx.vkAllocator, AppInstance._stagingBuffer, data[0..2], 0);
    //_ = try gfx.uploadMemory(gfx.vkAllocator, AppInstance._uniformBuffer, data[2..], 0);

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
                    .range = 3 * @sizeOf(math.Mat),
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
            .size = AppInstance.vertecies.len * @sizeOf(Vertex),
        },
    });

    gfx.device.cmdCopyBuffer(AppInstance._cmdLists[0], AppInstance._stagingBuffer.buffer, AppInstance._indexBuffer.buffer, 1, &[_]gfx.BufferCopy{
        gfx.BufferCopy{
            .src_offset = AppInstance.vertecies.len * @sizeOf(Vertex),
            .dst_offset = 0,
            .size = AppInstance.indices.len * @sizeOf(u32),
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
    const AppInstance = &Application.AppInstance;

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

    core.mem.ha.free(AppInstance._semaphores);
    core.mem.ha.free(AppInstance._cmdLists);
    core.mem.ha.free(AppInstance._cmdPools);
    gfx.device.destroyRenderPass(AppInstance._renderPass, null);
    AppInstance._viewport.deinit();

    msh.deinit();
    gfx.deinit();
}

pub fn run() !void {
    const AppInstance = &Application.AppInstance;

    var imageIndex: u32 = 0;
    AppInstance._semaphoreValue = 1;
    var currentRotation: f32 = 0.0;

    var timer = try std.time.Timer.start();
    while (AppInstance._shouldRun) {
        try AppInstance._viewport.nextFrame(AppInstance._semaphores[imageIndex]);

        const deltaTime: f32 = @as(f32, @floatFromInt(timer.lap())) / 1_000_000_000.0;
        currentRotation += deltaTime * std.math.degreesToRadians(45.0);

        AppInstance._rel = AppInstance._rel * math.Vec{ deltaTime, deltaTime, deltaTime, deltaTime };
        AppInstance._camera.addRotation(AppInstance._rel);
        AppInstance._rel = @splat(0.0);

        const moveSpeed: math.Vec = @splat(100.0 * deltaTime);

        const negativeOne: math.Vec = @splat(-1.0);

        if (AppInstance._moveUp) {
            AppInstance._camera.addTranslation(AppInstance._camera.getUpVector() * moveSpeed);
        }
        if (AppInstance._moveDown) {
            AppInstance._camera.addTranslation(AppInstance._camera.getUpVector() * negativeOne * moveSpeed);
        }
        if (AppInstance._moveLeft) {
            AppInstance._camera.addTranslation(AppInstance._camera.getRightVector() * moveSpeed);
        }
        if (AppInstance._moveRight) {
            AppInstance._camera.addTranslation(AppInstance._camera.getRightVector() * negativeOne * moveSpeed);
        }
        if (AppInstance._moveForward) {
            AppInstance._camera.addTranslation(AppInstance._camera.getForwardVector() * moveSpeed);
        }
        if (AppInstance._moveBackward) {
            AppInstance._camera.addTranslation(AppInstance._camera.getForwardVector() * negativeOne * moveSpeed);
        }

        const modelMatrix = math.mul(math.matFromRollPitchYaw(currentRotation, currentRotation, currentRotation), math.translation(0.0, 0.0, 0.0));

        const data = [_][]align(4) const u8{
            std.mem.sliceAsBytes(modelMatrix[0..]),
            std.mem.sliceAsBytes(AppInstance._camera._translationMatrix[0..]),
            std.mem.sliceAsBytes(AppInstance._camera._projectionMatrix[0..]),
        };

        _ = try gfx.uploadMemory(gfx.vkAllocator, AppInstance._uniformBuffer, data[0..], 0);

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
                .size = AppInstance.vertecies.len * @sizeOf(Vertex),
                .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                .src_queue_family_index = gfx.renderFamily,
                .dst_queue_family_index = gfx.renderFamily,
            },
            gfx.BufferMemoryBarrier{
                .buffer = AppInstance._indexBuffer.buffer,
                .offset = 0,
                .size = AppInstance.indices.len * @sizeOf(u32),
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
        gfx.device.cmdDrawIndexed(AppInstance._cmdLists[imageIndex], @intCast(AppInstance.indices.len), 1, 0, 0, 0);
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

        imageIndex = (imageIndex + 1) % Application.BufferedImages;
    }
}

const Application = struct {
    const Self = @This();
    const BufferedImages = 3;

    var AppInstance: Self = Self{};

    vertecies: []Vertex = undefined,
    indices: []u32 = undefined,

    _lastMouseX: f64 = undefined,
    _lastMouseY: f64 = undefined,
    _rel: math.Vec = .{ 0.0, 0.0, 0.0, 1.0 },

    _moveUp: bool = false,
    _moveDown: bool = false,
    _moveRight: bool = false,
    _moveLeft: bool = false,
    _moveForward: bool = false,
    _moveBackward: bool = false,

    _camera: Camera = undefined,
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

    fn onEvent(e: evnt.Event) void {
        switch (e) {
            .resizeEvent => |re| Application.onWindowResize(re),
            .closeEvent => |ce| Application.onWindowClose(ce),
            .keyboard => |uie| Application.onKeyboardEvent(uie),
            .mouseButton => |mbe| Application.onMouseButtonEvent(mbe),
            .mousePosition => |mpe| Application.onMousePositionEvent(mpe),
        }
    }

    fn onWindowResize(e: evnt.WindowResizeEvent) void {
        const width: f32 = @floatFromInt(e.width);
        const height: f32 = @floatFromInt(e.height);

        AppInstance._viewport.resize(e.width, e.height);
        AppInstance._camera.setProjectionMatrix(45.0, width / height, 0.1, 100000.0);
    }

    fn onWindowClose(_: evnt.WindowCloseEvent) void {
        AppInstance._shouldRun = false;
    }

    fn onKeyboardEvent(e: evnt.KeyboardEvent) void {
        if (e.key == .left_alt) {
            if (e.action == .Pressed) {
                AppInstance._viewport.setCursorEnabled(true);
                AppInstance._lastMouseX = AppInstance._viewport.getMousePosition()[0];
                AppInstance._lastMouseY = AppInstance._viewport.getMousePosition()[1];
            } else if (e.action == .Released) {
                AppInstance._viewport.setCursorEnabled(false);
            }
        }

        if (e.key == .left_shift) {
            if (e.action == .Pressed) {
                AppInstance._moveUp = true;
            } else if (e.action == .Released) {
                AppInstance._moveUp = false;
            }
        } else if (e.key == .left_control) {
            if (e.action == .Pressed) {
                AppInstance._moveDown = true;
            } else if (e.action == .Released) {
                AppInstance._moveDown = false;
            }
        } else if (e.key == .a) {
            if (e.action == .Pressed) {
                AppInstance._moveLeft = true;
            } else if (e.action == .Released) {
                AppInstance._moveLeft = false;
            }
        } else if (e.key == .d) {
            if (e.action == .Pressed) {
                AppInstance._moveRight = true;
            } else if (e.action == .Released) {
                AppInstance._moveRight = false;
            }
        } else if (e.key == .w) {
            if (e.action == .Pressed) {
                AppInstance._moveForward = true;
            } else if (e.action == .Released) {
                AppInstance._moveForward = false;
            }
        } else if (e.key == .s) {
            if (e.action == .Pressed) {
                AppInstance._moveBackward = true;
            } else if (e.action == .Released) {
                AppInstance._moveBackward = false;
            }
        }
    }

    fn onMouseButtonEvent(_: evnt.MouseButtonEvent) void {}

    fn onMousePositionEvent(e: evnt.MousePositionEvent) void {
        const relX = AppInstance._lastMouseX - e.x;
        const relY = AppInstance._lastMouseY - e.y;

        AppInstance._rel[1] = @floatCast(-relX);
        AppInstance._rel[0] = @floatCast(relY);

        AppInstance._lastMouseX = e.x;
        AppInstance._lastMouseY = e.y;
    }
};
