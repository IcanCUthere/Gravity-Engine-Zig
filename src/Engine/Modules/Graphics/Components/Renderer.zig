const util = @import("util");
const ArrayList = util.ArrayList;

const tracy = @import("ztracy");
const flecs = @import("zflecs");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Camera = @import("Camera.zig").Camera;
const Viewport = @import("Viewport.zig").Viewport;
const Model = @import("Model.zig").Model;
const Material = @import("Material.zig").Material;
const Texture = @import("Texture.zig").Texture;
const ModelInstance = @import("ModelInstance.zig").ModelInstance;

pub const Renderer = struct {
    pub const BufferedImages = 2;

    pub var _renderPass: gfx.RenderPass = undefined;

    var renderCmdPools: []gfx.CommandPool = undefined;
    var renderCmdLists: []gfx.CommandBuffer = undefined;

    var _semaphores: []gfx.Semaphore = undefined;
    pub var _timelineSemaphore: gfx.Semaphore = undefined;
    pub var _semaphoreValue: u64 = 0;
    var waitValues: []u64 = undefined;
    pub var imageIndex: u32 = 0;

    var _stagingBuffers: [BufferedImages]gfx.BufferAllocation = .{undefined} ** BufferedImages;
    var _stagingBufferSizes: [BufferedImages]u64 = .{0} ** BufferedImages;

    var stageData = ArrayList(StagingData).init(util.mem.heap);
    pub var descriptorWrites = ArrayList(DescriptorWriteData).init(util.mem.heap);
    var descriptorBufferWrites = ArrayList(gfx.DescriptorBufferInfo).init(util.mem.heap);
    var descriptorImageWrites = ArrayList(gfx.DescriptorImageInfo).init(util.mem.heap);

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
        firstUseStages: gfx.PipelineStageFlags = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{}),
    };

    pub const BarrierUploadData = struct {
        stage: gfx.PipelineStageFlags = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{}),
        bufferBarriers: ArrayList(gfx.BufferMemoryBarrier) = ArrayList(gfx.BufferMemoryBarrier).init(util.mem.heap),
        imageBarriers: ArrayList(gfx.ImageMemoryBarrier) = ArrayList(gfx.ImageMemoryBarrier).init(util.mem.heap),
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
        return renderCmdLists[imageIndex];
    }

    pub fn init(format: gfx.Format) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Init Renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _renderPass = try gfx.createRenderPass(format, true);

        renderCmdPools = try util.mem.heap.alloc(gfx.CommandPool, BufferedImages);
        renderCmdLists = try util.mem.heap.alloc(gfx.CommandBuffer, BufferedImages);

        _semaphores = try util.mem.heap.alloc(gfx.Semaphore, BufferedImages);
        waitValues = try util.mem.heap.alloc(u64, BufferedImages);

        for (
            renderCmdPools,
            renderCmdLists,
            _semaphores,
            waitValues,
        ) |
            *rpool,
            *rlist,
            *sem,
            *wv,
        | {
            wv.* = 0;

            rpool.* = try gfx.CreateCommandPool(&.{
                .queueFamilyIndex = gfx.renderFamily,
            });

            try gfx.AllocateCommandBuffers(&.{
                .commandPool = rpool.*,
                .level = gfx.CommandBufferLevel.Primary,
                .commandBufferCount = 1,
            }, @ptrCast(rlist));

            sem.* = try gfx.CreateSemaphore(&.{});
        }

        _timelineSemaphore = try gfx.CreateSemaphore(&gfx.SemaphoreCreateInfo{
            .pNext = &gfx.SemaphoreTypeCreateInfo{
                .semaphoreType = gfx.SemaphoreType.Timeline,
                .initialValue = 0,
            },
        });

        const globalPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .UniformBuffer,
                .descriptorCount = 1,
            },
        };

        globalDescriptorPool = try gfx.CreateDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .pPoolSizes = &globalPoolSizes,
            .poolSizeCount = @intCast(globalPoolSizes.len),
            .maxSets = 1,
        });

        const globalDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorType = gfx.DescriptorType.UniformBuffer,
                .descriptorCount = 1,
                .stageFlags = gfx.toFlags(&[_]gfx.ShaderStageFlagBits{
                    .VertexBit,
                }),
            },
        };

        globalDescriptorSetLayout = try gfx.CreateDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .pBindings = &globalDescriptorBindings,
            .bindingCount = @intCast(globalDescriptorBindings.len),
        });

        try gfx.AllocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptorPool = globalDescriptorPool,
            .pSetLayouts = @ptrCast(&globalDescriptorSetLayout),
            .descriptorSetCount = 1,
        }, @ptrCast(&descriptorSet));
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _ = try gfx.WaitSemaphores(&gfx.SemaphoreWaitInfo{
            .pSemaphores = @ptrCast(&_timelineSemaphore),
            .pValues = @ptrCast(&_semaphoreValue),
            .semaphoreCount = 1,
        }, ~@as(u64, 0));

        stageData.deinit();
        descriptorWrites.deinit();
        descriptorBufferWrites.deinit();
        descriptorImageWrites.deinit();

        try gfx.DestroyDescriptorPool(globalDescriptorPool);
        try gfx.DestroyDescriptorSetLayout(globalDescriptorSetLayout);
        try gfx.DestroySemaphore(_timelineSemaphore);

        for (_stagingBuffers) |b| {
            gfx.destroyBuffer(gfx.vkAllocator, b);
        }

        for (renderCmdPools, _semaphores) |rpool, sem| {
            try gfx.DestroySemaphore(sem);
            try gfx.DestroyCommandPool(rpool);
        }

        util.mem.heap.free(waitValues);
        util.mem.heap.free(_semaphores);
        util.mem.heap.free(renderCmdLists);
        util.mem.heap.free(renderCmdPools);

        try gfx.DestroyRenderPass(_renderPass);
    }

    pub fn addDescriptorUpdate(write: gfx.WriteDescriptorSet, useBufferInfo: bool, useImageInfo: bool) !void {
        const new = try descriptorWrites.addOne();
        new.write = write;

        if (useBufferInfo) {
            const newBufInfo = try descriptorBufferWrites.addOne();
            newBufInfo.* = write.pBufferInfo[0];
            new.bufIndex = descriptorBufferWrites.items.len - 1;
            new.imgIndex = null;
        } else if (useImageInfo) {
            const newImgInfo = try descriptorImageWrites.addOne();
            newImgInfo.* = write.pImageInfo[0];
            new.imgIndex = descriptorImageWrites.items.len - 1;
            new.bufIndex = null;
        }
    }

    fn updateDescriptorSets() !void {
        var writes = try ArrayList(gfx.WriteDescriptorSet).initCapacity(util.mem.heap, descriptorWrites.items.len);
        defer writes.deinit();

        for (descriptorWrites.items) |item| {
            var new = try writes.addOne();
            new.* = item.write;

            if (item.bufIndex) |i| {
                new.pBufferInfo = @ptrCast(&descriptorBufferWrites.items[i]);
            } else if (item.imgIndex) |i| {
                new.pImageInfo = @ptrCast(&descriptorImageWrites.items[i]);
            }
        }

        try gfx.UpdateDescriptorSets(
            writes.items,
            0, //TODO: y and ie in ending fucks it up
            &[_]gfx.CopyDescriptorSet{},
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
                    .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{.TransferSrcBit}),
                    .sharingMode = gfx.SharingMode.Exclusive,
                    .pQueueFamilyIndices = null,
                },
                &gfx.vma.VmaAllocationCreateInfo{
                    .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
                },
            );

            _stagingBufferSizes[imageIndex] = size;
        }

        var datas = try ArrayList([]const u8).initCapacity(util.mem.heap, stageData.items.len);
        defer datas.deinit();

        var preImageBarriers = try ArrayList(gfx.ImageMemoryBarrier).initCapacity(util.mem.heap, stageData.items.len);
        defer preImageBarriers.deinit();

        var preBufferBarriers = try ArrayList(gfx.BufferMemoryBarrier).initCapacity(util.mem.heap, stageData.items.len);
        defer preBufferBarriers.deinit();

        var postBarriers = ArrayList(BarrierUploadData).init(util.mem.heap);
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
                    if (existingBarrier.stage == postBarrier.firstUseStages) {
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

        try gfx.CmdPipelineBarrier(
            renderCmdLists[imageIndex],
            gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.TopOfPipeBit}),
            gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.TransferBit}),
            gfx.toFlags(&[_]gfx.DependencyFlagBits{}),
            &[_]gfx.MemoryBarrier{},
            preBufferBarriers.items,
            preImageBarriers.items,
        );

        var srcOffset: usize = 0;

        for (stageData.items) |data| {
            if (data.dstBuffer) |dstBuffer| {
                var bufCopy = data.bufferToBuffer.?;
                bufCopy.srcOffset = srcOffset;

                try gfx.CmdCopyBuffer(
                    renderCmdLists[imageIndex],
                    _stagingBuffers[imageIndex].buffer,
                    dstBuffer.buffer,
                    &[_]gfx.BufferCopy{
                        bufCopy,
                    },
                );
            } else if (data.dstImage) |dstImage| {
                var imgCopy = data.bufferToImage.?;
                imgCopy.bufferOffset = srcOffset;
                imgCopy.bufferImageHeight = 0;
                imgCopy.bufferRowLength = 0;

                try gfx.CmdCopyBufferToImage(
                    renderCmdLists[imageIndex],
                    _stagingBuffers[imageIndex].buffer,
                    dstImage.image,
                    gfx.ImageLayout.TransferDstOptimal,
                    &[_]gfx.BufferImageCopy{
                        imgCopy,
                    },
                );
            }

            srcOffset += data.data.len;
        }

        for (postBarriers.items) |barrier| {
            try gfx.CmdPipelineBarrier(
                renderCmdLists[imageIndex],
                gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.TransferBit}),
                barrier.stage,
                gfx.toFlags(&[_]gfx.DependencyFlagBits{}),
                &[_]gfx.MemoryBarrier{},
                barrier.bufferBarriers.items,
                barrier.imageBarriers.items,
            );
        }

        try stageData.resize(0);
    }

    pub fn beginFrame(_: *flecs.iter_t, viewport: []Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Begin frame", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _ = try gfx.WaitSemaphores(&gfx.SemaphoreWaitInfo{
            .pSemaphores = @ptrCast(&_timelineSemaphore),
            .pValues = &[_]u64{waitValues[imageIndex]},
            .semaphoreCount = 1,
        }, ~@as(u64, 0));

        try viewport[0].nextFrame(_semaphores[imageIndex]);

        try gfx.ResetCommandPool(
            renderCmdPools[imageIndex],
            gfx.toFlags(&[_]gfx.CommandPoolResetFlagBits{}),
        );

        try gfx.BeginCommandBuffer(
            renderCmdLists[imageIndex],
            &gfx.CommandBufferBeginInfo{
                .flags = gfx.toFlags(&[_]gfx.CommandBufferUsageFlagBits{.OneTimeSubmitBit}),
                .pInheritanceInfo = &gfx.CommandBufferInheritanceInfo{
                    .renderPass = _renderPass,
                    .framebuffer = viewport[0].getFramebuffer(),
                    .subpass = 0,
                    .occlusionQueryEnable = gfx.FALSE,
                },
            },
        );
    }

    pub fn updateData(_: *flecs.iter_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Upload data", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try uploadStagingData();
        try updateDescriptorSets();
    }

    pub fn startRendering(_: *flecs.iter_t, viewport: []const Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Start rendering", 0x00_ff_ff_00);
        defer tracy_zone.End();

        const clearValues = [_]gfx.ClearValue{
            gfx.ClearValue{
                .color = .{
                    .float32 = [4]f32{
                        0.0,
                        0.0,
                        0.0,
                        0.0,
                    },
                },
            },
            gfx.ClearValue{
                .depthStencil = .{
                    .depth = 1.0,
                    .stencil = 0,
                },
            },
        };

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = viewport[0].getWidth(),
                .height = viewport[0].getHeight(),
            },
        };

        try gfx.CmdBeginRenderPass(renderCmdLists[imageIndex], &gfx.RenderPassBeginInfo{
            .renderPass = _renderPass,
            .framebuffer = viewport[0].getFramebuffer(),
            .renderArea = renderArea,
            .pClearValues = @ptrCast(&clearValues),
            .clearValueCount = @intCast(clearValues.len),
        }, gfx.SubpassContents.Inline);
    }

    pub fn render(_: *flecs.iter_t, modelInstances: []const ModelInstance, model: []const Model, material: []const Material, viewport: []const Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.CmdBindPipeline(
            renderCmdLists[imageIndex],
            gfx.PipelineBindPoint.Graphics,
            material[0].pipeline,
        );

        try gfx.CmdSetViewport(
            renderCmdLists[imageIndex],
            0,
            &[_]gfx.Viewport{
                gfx.Viewport{
                    .width = @floatFromInt(viewport[0].getWidth()),
                    .height = -@as(f32, @floatFromInt(viewport[0].getHeight())),
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                    .x = 0.0,
                    .y = @floatFromInt(viewport[0].getHeight()),
                },
            },
        );

        try gfx.CmdSetScissor(
            renderCmdLists[imageIndex],
            0,
            &[_]gfx.Rect2D{gfx.Rect2D{
                .offset = gfx.Offset2D{ .x = 0, .y = 0 },
                .extent = gfx.Extent2D{
                    .width = viewport[0].getWidth(),
                    .height = viewport[0].getHeight(),
                },
            }},
        );

        try gfx.CmdBindVertexBuffers(
            renderCmdLists[imageIndex],
            0,
            1,
            @ptrCast(&model[0].vertexBuffer.buffer),
            &[_]u64{0},
        );
        try gfx.CmdBindIndexBuffer(
            renderCmdLists[imageIndex],
            model[0].indexBuffer.buffer,
            0,
            gfx.IndexType.Uint32,
        );

        try gfx.CmdBindDescriptorSets(
            renderCmdLists[imageIndex],
            gfx.PipelineBindPoint.Graphics,
            material[0].pipelineLayout,
            0,
            &[_]gfx.DescriptorSet{
                Renderer.descriptorSet,
                //material[0].descriptorSet,
                model[0].descriptorSet,
            },
            &[_]u32{},
        );

        for (modelInstances) |intance| {
            try gfx.CmdBindDescriptorSets(
                renderCmdLists[imageIndex],
                gfx.PipelineBindPoint.Graphics,
                material[0].pipelineLayout,
                2,
                &[_]gfx.DescriptorSet{intance.descriptorSet},
                &[_]u32{},
            );

            try gfx.CmdDrawIndexed(
                renderCmdLists[imageIndex],
                @intCast(model[0].mesh.indexData.len),
                1,
                0,
                0,
                0,
            );
        }
    }

    pub fn stopRendering(_: *flecs.iter_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Stop rendering", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.CmdEndRenderPass(renderCmdLists[imageIndex]);
    }

    pub fn endFrame(_: *flecs.iter_t, viewport: []Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "End frame", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.EndCommandBuffer(renderCmdLists[imageIndex]);

        const signalValue = _semaphoreValue + 1;
        const waitValue = _semaphoreValue;
        _semaphoreValue += 1;

        waitValues[imageIndex] = signalValue;

        try gfx.QueueSubmit(
            gfx.renderQueue,
            &[_]gfx.SubmitInfo{
                gfx.SubmitInfo{
                    .pNext = &gfx.TimelineSemaphoreSubmitInfo{
                        .pSignalSemaphoreValues = @ptrCast(&signalValue),
                        .signalSemaphoreValueCount = 2,
                        .pWaitSemaphoreValues = @ptrCast(&waitValue),
                        .waitSemaphoreValueCount = 2,
                    },
                    .pCommandBuffers = &[_]gfx.CommandBuffer{renderCmdLists[imageIndex]},
                    .commandBufferCount = 1,
                    .pWaitDstStageMask = &[_]gfx.PipelineStageFlags{
                        gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.ColorAttachmentOutputBit}),
                        gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.ColorAttachmentOutputBit}),
                    },
                    .pSignalSemaphores = &[_]gfx.Semaphore{ _timelineSemaphore, _semaphores[imageIndex] },
                    .signalSemaphoreCount = 2,
                    .pWaitSemaphores = &[_]gfx.Semaphore{ _timelineSemaphore, _semaphores[imageIndex] },
                    .waitSemaphoreCount = 2,
                },
            },
            null,
        );

        try viewport[0].presentImage(&_semaphores[imageIndex], 1);

        imageIndex = (imageIndex + 1) % BufferedImages;
    }
};
