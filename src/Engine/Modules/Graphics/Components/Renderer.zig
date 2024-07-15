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
const Material = @import("Material.zig").Material;
const Texture = @import("Texture.zig").Texture;
const ModelInstance = @import("ModelInstance.zig").ModelInstance;

pub const Renderer = struct {
    pub const BufferedImages = 2;

    pub var _renderPass: gfx.RenderPass = undefined;
    var _cmdPools: []gfx.CommandPool = undefined;
    var _cmdLists: []gfx.CommandBuffer = undefined;
    var _semaphores: []gfx.Semaphore = undefined;
    var _timelineSemaphore: gfx.Semaphore = undefined;
    var _semaphoreValue: u64 = 0;
    var imageIndex: u32 = 0;

    var _stagingBuffers: [BufferedImages]gfx.BufferAllocation = .{undefined} ** BufferedImages;
    var _stagingBufferSizes: [BufferedImages]u64 = .{0} ** BufferedImages;

    var stageData = std.ArrayList(StagingData).init(core.mem.heap);
    pub var descriptorWrites = std.ArrayList(DescriptorWriteData).init(core.mem.heap);
    var descriptorBufferWrites = std.ArrayList(gfx.DescriptorBufferInfo).init(core.mem.heap);
    var descriptorImageWrites = std.ArrayList(gfx.DescriptorImageInfo).init(core.mem.heap);

    pub var globalDescriptorPool: gfx.DescriptorPool = undefined;
    pub var globalDescriptorSetLayout: gfx.DescriptorSetLayout = undefined;
    pub var descriptorSet: gfx.DescriptorSet = undefined;

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
        bufferBarriers: std.ArrayList(gfx.BufferMemoryBarrier) = std.ArrayList(gfx.BufferMemoryBarrier).init(core.mem.heap),
        imageBarriers: std.ArrayList(gfx.ImageMemoryBarrier) = std.ArrayList(gfx.ImageMemoryBarrier).init(core.mem.heap),
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

    pub fn getCurrentCmdList() gfx.CommandBuffer {
        return _cmdLists[imageIndex];
    }

    pub fn init(format: gfx.Format) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Init Renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _renderPass = try gfx.createRenderPass(format, true);

        _cmdPools = try core.mem.heap.alloc(gfx.CommandPool, BufferedImages);
        _cmdLists = try core.mem.heap.alloc(gfx.CommandBuffer, BufferedImages);
        _semaphores = try core.mem.heap.alloc(gfx.Semaphore, BufferedImages);

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

        const globalPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .uniform_buffer,
                .descriptor_count = 1,
            },
        };

        globalDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &globalPoolSizes,
            .pool_size_count = @intCast(globalPoolSizes.len),
            .max_sets = 1,
        }, null);

        const globalDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
            },
        };

        globalDescriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &globalDescriptorBindings,
            .binding_count = @intCast(globalDescriptorBindings.len),
        }, null);

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = globalDescriptorPool,
            .p_set_layouts = @ptrCast(&globalDescriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&descriptorSet));
    }

    pub fn deinit() void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _ = gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&_timelineSemaphore),
            .p_values = @ptrCast(&_semaphoreValue),
            .semaphore_count = 1,
        }, ~@as(u64, 0)) catch gfx.Result.error_unknown;

        stageData.deinit();
        descriptorWrites.deinit();
        descriptorBufferWrites.deinit();
        descriptorImageWrites.deinit();

        gfx.device.destroyDescriptorPool(globalDescriptorPool, null);
        gfx.device.destroyDescriptorSetLayout(globalDescriptorSetLayout, null);
        gfx.device.destroySemaphore(_timelineSemaphore, null);

        for (_stagingBuffers) |b| {
            gfx.destroyBuffer(gfx.vkAllocator, b);
        }

        for (_cmdPools, _semaphores) |pool, sem| {
            gfx.device.destroySemaphore(sem, null);
            gfx.device.destroyCommandPool(pool, null);
        }

        core.mem.heap.free(_semaphores);
        core.mem.heap.free(_cmdLists);
        core.mem.heap.free(_cmdPools);
        gfx.device.destroyRenderPass(_renderPass, null);
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
        var writes = try std.ArrayList(gfx.WriteDescriptorSet).initCapacity(core.mem.heap, descriptorWrites.items.len);
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

        var datas = try std.ArrayList([]const u8).initCapacity(core.mem.heap, stageData.items.len);
        defer datas.deinit();

        var preImageBarriers = try std.ArrayList(gfx.ImageMemoryBarrier).initCapacity(core.mem.heap, stageData.items.len);
        defer preImageBarriers.deinit();

        var preBufferBarriers = try std.ArrayList(gfx.BufferMemoryBarrier).initCapacity(core.mem.heap, stageData.items.len);
        defer preBufferBarriers.deinit();

        var postBarriers = std.ArrayList(BarrierUploadData).init(core.mem.heap);
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

    pub fn startRendering(_: *flecs.iter_t, viewport: []const Viewport) void {
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
    }

    pub fn render(_: *flecs.iter_t, modelInstances: []const ModelInstance, model: []const Model, material: []const Material, viewport: []const Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer tracy_zone.End();

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = viewport[0].getWidth(),
                .height = viewport[0].getHeight(),
            },
        };

        for (modelInstances) |intance| {
            gfx.device.cmdBindPipeline(_cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, material[0].pipeline);
            gfx.device.cmdSetViewport(_cmdLists[imageIndex], 0, 1, @ptrCast(&gfx.Viewport{
                .width = @floatFromInt(viewport[0].getWidth()),
                .height = -@as(f32, @floatFromInt(viewport[0].getHeight())),
                .min_depth = 0.0,
                .max_depth = 1.0,
                .x = 0.0,
                .y = @floatFromInt(viewport[0].getHeight()),
            }));
            gfx.device.cmdSetScissor(_cmdLists[imageIndex], 0, 1, @ptrCast(&renderArea));

            const setsToBind = [_]gfx.DescriptorSet{
                Renderer.descriptorSet,
                //material[0].descriptorSet,
                model[0].descriptorSet,
                intance.descriptorSet,
            };

            gfx.device.cmdBindVertexBuffers(_cmdLists[imageIndex], 0, 1, @ptrCast(&model[0].vertexBuffer.buffer), &[_]u64{0});
            gfx.device.cmdBindIndexBuffer(_cmdLists[imageIndex], model[0].indexBuffer.buffer, 0, gfx.IndexType.uint32);
            gfx.device.cmdBindDescriptorSets(_cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, material[0].pipelineLayout, 0, setsToBind.len, @ptrCast(&setsToBind), 0, null);
            gfx.device.cmdDrawIndexed(_cmdLists[imageIndex], @intCast(model[0].mesh.indexData.len), 1, 0, 0, 0);
        }
    }

    pub fn stopRendering(_: *flecs.iter_t) void {
        gfx.device.cmdEndRenderPass(_cmdLists[imageIndex]);
    }

    pub fn endFrame(_: *flecs.iter_t, viewport: []Viewport) !void {
        try gfx.device.endCommandBuffer(_cmdLists[imageIndex]);

        const signalValue = _semaphoreValue + 1;
        const waitValue = _semaphoreValue;
        _semaphoreValue += 1;

        try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
            gfx.SubmitInfo{
                .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                    .p_signal_semaphore_values = @ptrCast(&signalValue),
                    .signal_semaphore_value_count = 2,
                    .p_wait_semaphore_values = @ptrCast(&waitValue),
                    .wait_semaphore_value_count = 2,
                },
                .p_command_buffers = &[_]gfx.CommandBuffer{_cmdLists[imageIndex]},
                .command_buffer_count = 1,
                .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{ .{ .color_attachment_output_bit = true }, .{ .color_attachment_output_bit = true } },
                .p_signal_semaphores = &[_]gfx.Semaphore{ _timelineSemaphore, _semaphores[imageIndex] },
                .signal_semaphore_count = 2,
                .p_wait_semaphores = &[_]gfx.Semaphore{ _timelineSemaphore, _semaphores[imageIndex] },
                .wait_semaphore_count = 2,
            },
        }, gfx.Fence.null_handle);

        try viewport[0].presentImage(&_semaphores[imageIndex], 1);

        imageIndex = (imageIndex + 1) % BufferedImages;
    }
};
