const gfx = @import("Internal/interface.zig");
const tracy = @import("ztracy");
const flecs = @import("zflecs");

const coreM = @import("CoreModule");

const std = @import("std");
const core = @import("core");

const shaders = @import("shaders");

const Camera = @import("Camera.zig").Camera;
const Viewport = @import("Viewport.zig").Viewport;
const Model = @import("Model.zig").Model;

pub const Renderer = struct {
    const BufferedImages = 3;

    pub var _renderPass: gfx.RenderPass = undefined;
    var _cmdPools: []gfx.CommandPool = undefined;
    var _cmdLists: []gfx.CommandBuffer = undefined;
    var _semaphores: []gfx.Semaphore = undefined;
    var _timelineSemaphore: gfx.Semaphore = undefined;
    var _semaphoreValue: u64 = 0;
    var imageIndex: u32 = 0;

    var _stagingBuffers: [BufferedImages]gfx.BufferAllocation = .{ undefined, undefined, undefined };
    var _stagingBufferSizes: [BufferedImages]u64 = .{ 0, 0, 0 };

    var stageData = std.ArrayList(StagingData).init(core.mem.ha);
    var imageStageData = std.ArrayList(gfx.BufferImageCopy).init(core.mem.ha);
    pub var descriptorWrites = std.ArrayList(DescriptorWriteData).init(core.mem.ha);
    var descriptorBufferWrites = std.ArrayList(gfx.DescriptorBufferInfo).init(core.mem.ha);
    var descriptorImageWrites = std.ArrayList(gfx.DescriptorImageInfo).init(core.mem.ha);

    pub var _vertexModule: gfx.ShaderModule = undefined;
    pub var _fragmentModule: gfx.ShaderModule = undefined;
    pub var _descriptorPool: gfx.DescriptorPool = undefined;
    pub var modelDescriptorSetLayout: gfx.DescriptorSetLayout = undefined;
    pub var cameraDescriptorSetLayout: gfx.DescriptorSetLayout = undefined;
    pub var _pipelineLayout: gfx.PipelineLayout = undefined;
    pub var _pipeline: gfx.Pipeline = undefined;

    const DescriptorWriteData = struct {
        write: gfx.WriteDescriptorSet,
        bufIndex: ?usize = null,
        imgIndex: ?usize = null,
    };

    pub const PipelineBarrierData = struct {
        postBufferBarrier: ?gfx.BufferMemoryBarrier = null,
        postImageBarrier: ?gfx.ImageMemoryBarrier = null,
        firstUseStages: gfx.PipelineStageFlags = .{},
    };

    pub const BarrierUploadData = struct {
        stage: gfx.PipelineStageFlags = gfx.PipelineStageFlags{},
        bufferBarriers: std.ArrayList(gfx.BufferMemoryBarrier) = std.ArrayList(gfx.BufferMemoryBarrier).init(core.mem.ha),
        imageBarriers: std.ArrayList(gfx.ImageMemoryBarrier) = std.ArrayList(gfx.ImageMemoryBarrier).init(core.mem.ha),
    };

    pub const StagingData = struct {
        data: []const u8,

        dstBuffer: ?gfx.BufferAllocation = null,
        bufferToBuffer: ?gfx.BufferCopy = null,
        preBufferBarrier: ?gfx.BufferMemoryBarrier = null,

        dstImage: ?gfx.ImageAllocation = null,
        bufferToImage: ?gfx.BufferImageCopy = null,
        preImageBarrier: ?gfx.ImageMemoryBarrier = null,

        postBarrier: ?PipelineBarrierData = null,
    };

    pub fn init(format: gfx.Format) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Init Renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _renderPass = try gfx.createRenderPass(format);

        _cmdPools = try core.mem.ha.alloc(gfx.CommandPool, BufferedImages);
        _cmdLists = try core.mem.ha.alloc(gfx.CommandBuffer, BufferedImages);
        _semaphores = try core.mem.ha.alloc(gfx.Semaphore, BufferedImages);

        for (_cmdPools, _cmdLists, _semaphores) |*pool, *list, *sem| {
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

        _timelineSemaphore = try gfx.device.createSemaphore(&gfx.SemaphoreCreateInfo{
            .p_next = &gfx.SemaphoreTypeCreateInfo{
                .semaphore_type = gfx.SemaphoreType.timeline,
                .initial_value = 0,
            },
        }, null);

        _vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.shader_vert.len,
            .p_code = @ptrCast(&shaders.shader_vert),
        }, null);

        _fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.shader_frag.len,
            .p_code = @ptrCast(&shaders.shader_frag),
        }, null);

        const poolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .uniform_buffer,
                .descriptor_count = 1,
            },
            gfx.DescriptorPoolSize{
                .type = .combined_image_sampler,
                .descriptor_count = 1,
            },
        };

        _descriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &poolSizes,
            .pool_size_count = @intCast(poolSizes.len),
            .max_sets = 10,
        }, null);

        //model layout
        const modelDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
            },
            gfx.DescriptorSetLayoutBinding{
                .binding = 1,
                .descriptor_type = gfx.DescriptorType.combined_image_sampler,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .fragment_bit = true },
            },
        };

        modelDescriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &modelDescriptorBindings,
            .binding_count = @intCast(modelDescriptorBindings.len),
        }, null);

        const cameraDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
            },
        };

        cameraDescriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &cameraDescriptorBindings,
            .binding_count = @intCast(cameraDescriptorBindings.len),
        }, null);

        const setLayouts = [_]gfx.DescriptorSetLayout{
            modelDescriptorSetLayout,
            cameraDescriptorSetLayout,
        };

        _pipelineLayout = try gfx.device.createPipelineLayout(&gfx.PipelineLayoutCreateInfo{
            .p_set_layouts = @ptrCast(&setLayouts),
            .set_layout_count = @intCast(setLayouts.len),
            .p_push_constant_ranges = null,
            .push_constant_range_count = 0,
        }, null);

        _pipeline = try gfx.createPipeline(_pipelineLayout, _renderPass, _vertexModule, _fragmentModule, 100, 100);
    }

    pub fn deinit() void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _ = gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&_timelineSemaphore),
            .p_values = @ptrCast(&_semaphoreValue),
            .semaphore_count = 1,
        }, ~@as(u64, 0)) catch gfx.Result.error_unknown;

        gfx.device.destroySemaphore(_timelineSemaphore, null);

        for (_stagingBuffers) |b| {
            gfx.destroyBuffer(gfx.vkAllocator, b);
        }

        gfx.device.destroyPipeline(_pipeline, null);
        gfx.device.destroyPipelineLayout(_pipelineLayout, null);
        gfx.device.destroyDescriptorSetLayout(modelDescriptorSetLayout, null);
        gfx.device.destroyDescriptorSetLayout(cameraDescriptorSetLayout, null);

        for (_cmdPools, _semaphores) |pool, sem| {
            gfx.device.destroySemaphore(sem, null);
            gfx.device.destroyCommandPool(pool, null);
        }

        core.mem.ha.free(_semaphores);
        core.mem.ha.free(_cmdLists);
        core.mem.ha.free(_cmdPools);
        gfx.device.destroyRenderPass(_renderPass, null);

        gfx.device.destroyDescriptorPool(_descriptorPool, null);
        gfx.device.destroyShaderModule(_vertexModule, null);
        gfx.device.destroyShaderModule(_fragmentModule, null);
    }

    pub fn addDescriptorUpdate(write: gfx.WriteDescriptorSet, useBufferInfo: bool, useImageInfo: bool) !void {
        const new = try descriptorWrites.addOne();
        new.write = write;

        if (useBufferInfo) {
            const newBufInfo = try descriptorBufferWrites.addOne();
            newBufInfo.* = write.p_buffer_info[0];
            new.bufIndex = descriptorBufferWrites.items.len - 1;
            new.imgIndex = null;
        } else if (useImageInfo) {
            const newImgInfo = try descriptorImageWrites.addOne();
            newImgInfo.* = write.p_image_info[0];
            new.imgIndex = descriptorImageWrites.items.len - 1;
            new.bufIndex = null;
        }
    }

    fn updateDescriptorSets() !void {
        var writes = try std.ArrayList(gfx.WriteDescriptorSet).initCapacity(core.mem.ha, descriptorWrites.items.len);
        defer writes.deinit();

        for (descriptorWrites.items) |item| {
            var new = try writes.addOne();
            new.* = item.write;

            if (item.bufIndex) |i| {
                new.p_buffer_info = @ptrCast(&descriptorBufferWrites.items[i]);
            } else if (item.imgIndex) |i| {
                new.p_image_info = @ptrCast(&descriptorImageWrites.items[i]);
            }
        }

        gfx.device.updateDescriptorSets(
            @intCast(writes.items.len),
            writes.items.ptr,
            0,
            null,
        );

        try descriptorWrites.resize(0);
        try descriptorImageWrites.resize(0);
        try descriptorBufferWrites.resize(0);
    }

    pub fn addStagingData(stagingData: StagingData) !void {
        if (stagingData.bufferToBuffer != null or stagingData.bufferToImage != null) {
            const new = try stageData.addOne();
            new.* = stagingData;
        } else {
            const toUpload = [_][]const u8{stagingData.data};
            _ = try gfx.uploadMemory(gfx.vkAllocator, stagingData.dstBuffer.?, &toUpload, 0);
        }
    }

    fn uploadStagingData() !void {
        var size: usize = 0;
        for (stageData.items) |data| {
            size += data.data.len;
        }

        if (size == 0) {
            return;
        }

        if (_stagingBufferSizes[imageIndex] < size) {
            if (_stagingBufferSizes[imageIndex] != 0) {
                gfx.destroyBuffer(gfx.vkAllocator, _stagingBuffers[imageIndex]);
            }

            _stagingBuffers[imageIndex] = try gfx.createBuffer(
                gfx.vkAllocator,
                &gfx.BufferCreateInfo{
                    .size = size,
                    .usage = gfx.BufferUsageFlags{ .transfer_src_bit = true },
                    .sharing_mode = gfx.SharingMode.exclusive,
                },
                &gfx.vma.VmaAllocationCreateInfo{
                    .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
                },
            );

            _stagingBufferSizes[imageIndex] = size;
        }

        var datas = try std.ArrayList([]const u8).initCapacity(core.mem.ha, stageData.items.len);
        defer datas.deinit();

        var preImageBarriers = try std.ArrayList(gfx.ImageMemoryBarrier).initCapacity(core.mem.ha, stageData.items.len);
        defer preImageBarriers.deinit();

        //const postImageBarriers = try std.ArrayList(gfx.ImageMemoryBarrier).initCapacity(core.mem.ha, stageData.items.len);
        //defer postImageBarriers.deinit();

        var preBufferBarriers = try std.ArrayList(gfx.BufferMemoryBarrier).initCapacity(core.mem.ha, stageData.items.len);
        defer preBufferBarriers.deinit();

        var postBarriers = std.ArrayList(BarrierUploadData).init(core.mem.ha);
        defer postBarriers.deinit();

        defer for (postBarriers.items) |data| {
            data.bufferBarriers.deinit();
            data.imageBarriers.deinit();
        };

        for (stageData.items) |d| {
            const newData = try datas.addOne();
            newData.* = d.data;

            if (d.preImageBarrier) |pib| {
                const new = try preImageBarriers.addOne();
                new.* = pib;
            }

            if (d.preBufferBarrier) |pib| {
                const new = try preBufferBarriers.addOne();
                new.* = pib;
            }

            if (d.postBarrier) |postBarrier| {
                const found = for (postBarriers.items) |*existingBarrier| {
                    if (existingBarrier.stage.toInt() == postBarrier.firstUseStages.toInt()) {
                        if (postBarrier.postBufferBarrier) |bufferBarrier| {
                            const new: *gfx.BufferMemoryBarrier = try existingBarrier.bufferBarriers.addOne();
                            new.* = bufferBarrier;
                        } else if (postBarrier.postImageBarrier) |imageBarrier| {
                            const new: *gfx.ImageMemoryBarrier = try existingBarrier.imageBarriers.addOne();
                            new.* = imageBarrier;
                        }

                        break true;
                    }
                } else false;

                if (!found) {
                    const new = try postBarriers.addOne();
                    new.* = BarrierUploadData{};
                    new.stage = postBarrier.firstUseStages;

                    if (postBarrier.postBufferBarrier) |bufBarr| {
                        const newBufBarr = try new.bufferBarriers.addOne();
                        newBufBarr.* = bufBarr;
                    }
                    if (postBarrier.postImageBarrier) |imgBarr| {
                        const newImgBarr = try new.imageBarriers.addOne();
                        newImgBarr.* = imgBarr;
                    }
                }
            }
        }

        _ = try gfx.uploadMemory(gfx.vkAllocator, _stagingBuffers[imageIndex], datas.items, 0);

        gfx.device.cmdPipelineBarrier(
            _cmdLists[imageIndex],
            .{ .top_of_pipe_bit = true },
            .{ .transfer_bit = true },
            .{},
            0,
            null,
            @intCast(preBufferBarriers.items.len),
            preBufferBarriers.items.ptr,
            @intCast(preImageBarriers.items.len),
            preImageBarriers.items.ptr,
        );

        var srcOffset: usize = 0;

        for (stageData.items) |data| {
            if (data.dstBuffer) |dstBuffer| {
                var bufCopy = data.bufferToBuffer.?;
                bufCopy.src_offset = srcOffset;

                gfx.device.cmdCopyBuffer(
                    _cmdLists[imageIndex],
                    _stagingBuffers[imageIndex].buffer,
                    dstBuffer.buffer,
                    1,
                    &[_]gfx.BufferCopy{
                        bufCopy,
                    },
                );
            } else if (data.dstImage) |dstImage| {
                var imgCopy = data.bufferToImage.?;
                imgCopy.buffer_offset = srcOffset;
                imgCopy.buffer_image_height = 0;
                imgCopy.buffer_row_length = 0;

                gfx.device.cmdCopyBufferToImage(
                    _cmdLists[imageIndex],
                    _stagingBuffers[imageIndex].buffer,
                    dstImage.image,
                    gfx.ImageLayout.transfer_dst_optimal,
                    1,
                    &[_]gfx.BufferImageCopy{
                        imgCopy,
                    },
                );
            }

            srcOffset += data.data.len;
        }

        for (postBarriers.items) |barrier| {
            gfx.device.cmdPipelineBarrier(
                _cmdLists[imageIndex],
                .{ .transfer_bit = true },
                barrier.stage,
                .{},
                0,
                null,
                @intCast(barrier.bufferBarriers.items.len),
                barrier.bufferBarriers.items.ptr,
                @intCast(barrier.imageBarriers.items.len),
                barrier.imageBarriers.items.ptr,
            );
        }

        try stageData.resize(0);
    }

    pub fn updateData(_: *flecs.iter_t) !void {
        try uploadStagingData();
        try updateDescriptorSets();
    }

    pub fn beginFrame(_: *flecs.iter_t, viewport: []Viewport) !void {
        try viewport[0].nextFrame(_semaphores[imageIndex]);

        const waitValue: u64 = _semaphoreValue;
        _semaphoreValue += 1;

        _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&_timelineSemaphore),
            .p_values = &[_]u64{waitValue},
            .semaphore_count = 1,
        }, ~@as(u64, 0));

        try gfx.device.resetCommandPool(_cmdPools[imageIndex], .{});

        try gfx.device.beginCommandBuffer(_cmdLists[imageIndex], &gfx.CommandBufferBeginInfo{
            .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true },
            .p_inheritance_info = &gfx.CommandBufferInheritanceInfo{
                .render_pass = _renderPass,
                .framebuffer = viewport[0].getFramebuffer(),
                .subpass = 0,
                .occlusion_query_enable = gfx.FALSE,
            },
        });
    }

    pub fn endFrame(_: *flecs.iter_t, viewport: []Viewport) !void {
        try gfx.device.endCommandBuffer(_cmdLists[imageIndex]);

        try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
            gfx.SubmitInfo{
                .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                    .p_signal_semaphore_values = @ptrCast(&_semaphoreValue),
                    .signal_semaphore_value_count = 2,
                    .p_wait_semaphore_values = null,
                    .wait_semaphore_value_count = 0,
                },
                .p_command_buffers = &[_]gfx.CommandBuffer{_cmdLists[imageIndex]},
                .command_buffer_count = 1,
                .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{.{ .color_attachment_output_bit = true }},
                .p_signal_semaphores = &[_]gfx.Semaphore{ _timelineSemaphore, _semaphores[imageIndex] },
                .signal_semaphore_count = 2,
                .p_wait_semaphores = @ptrCast(&_semaphores[imageIndex]),
                .wait_semaphore_count = 1,
            },
        }, gfx.Fence.null_handle);

        try viewport[0].presentImage(&_semaphores[imageIndex], 1);

        imageIndex = (imageIndex + 1) % BufferedImages;
    }

    pub fn render(_: *flecs.iter_t, models: []Model, meshes: []coreM.Mesh, cameras: []Camera, viewport: []Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer tracy_zone.End();

        const clearValues = [_]gfx.ClearValue{
            gfx.ClearValue{ .color = .{ .float_32 = [4]f32{ 0.0, 0.0, 0.0, 0.0 } } },
            gfx.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = viewport[0].getWidth(),
                .height = viewport[0].getHeight(),
            },
        };

        gfx.device.cmdBeginRenderPass(_cmdLists[imageIndex], &gfx.RenderPassBeginInfo{
            .render_pass = _renderPass,
            .framebuffer = viewport[0].getFramebuffer(),
            .render_area = renderArea,
            .p_clear_values = @ptrCast(&clearValues),
            .clear_value_count = @intCast(clearValues.len),
        }, gfx.SubpassContents.@"inline");

        gfx.device.cmdBindPipeline(_cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, _pipeline);
        gfx.device.cmdSetViewport(_cmdLists[imageIndex], 0, 1, @ptrCast(&gfx.Viewport{
            .width = @floatFromInt(viewport[0].getWidth()),
            .height = -@as(f32, @floatFromInt(viewport[0].getHeight())),
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = @floatFromInt(viewport[0].getHeight()),
        }));
        gfx.device.cmdSetScissor(_cmdLists[imageIndex], 0, 1, @ptrCast(&renderArea));

        for (models, meshes) |model, mesh| {
            const setsToBind = [_]gfx.DescriptorSet{ model.descriptorSet, cameras[0].descriptorSet };

            gfx.device.cmdBindVertexBuffers(_cmdLists[imageIndex], 0, 1, @ptrCast(&model.vertexBuffer.buffer), &[_]u64{0});
            gfx.device.cmdBindIndexBuffer(_cmdLists[imageIndex], model.indexBuffer.buffer, 0, gfx.IndexType.uint32);
            gfx.device.cmdBindDescriptorSets(_cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, _pipelineLayout, 0, 2, @ptrCast(&setsToBind), 0, null);
            gfx.device.cmdDrawIndexed(_cmdLists[imageIndex], @intCast(mesh.data.indexData.len), 1, 0, 0, 0);
        }

        gfx.device.cmdEndRenderPass(_cmdLists[imageIndex]);
    }
};
