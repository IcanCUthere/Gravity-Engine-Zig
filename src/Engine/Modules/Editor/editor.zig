const util = @import("util");

const flecs = @import("zflecs");
const tracy = @import("ztracy");
const gui = @import("zgui");

const graphics = @import("GraphicsModule");

const gfx = graphics.gfx;
const StateManager = @import("Components/StateManager.zig").StateManager;

const shaders = @import("shaders");

pub const Editor = struct {
    pub const name: []const u8 = "editor";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var _scene: *flecs.world_t = undefined;

    var guiDescriptorPool: gfx.DescriptorPool = undefined;

    var renderPass: gfx.RenderPass = undefined;

    var cmdPool: gfx.CommandPool = undefined;
    var cmdList: gfx.CommandBuffer = undefined;

    var readBackBuffer: gfx.BufferAllocation = undefined;

    var depthImage: gfx.ImageAllocation = undefined;
    var depthImageView: gfx.ImageView = undefined;
    var writeToImage: gfx.ImageAllocation = undefined;
    var writeToImageView: gfx.ImageView = undefined;
    var framebuffer: gfx.Framebuffer = undefined;

    var vertexModule: gfx.ShaderModule = undefined;
    var fragmentModule: gfx.ShaderModule = undefined;
    var instanceTransformLayout: gfx.DescriptorSetLayout = undefined;
    var pipelineLayout: gfx.PipelineLayout = undefined;
    var pipeline: gfx.Pipeline = undefined;

    const components = [_]type{
        StateManager,
    };

    fn loader(n: [*:0]const u8, handle: *const anyopaque) ?*const anyopaque {
        return @ptrCast(gfx.baseDispatch.dispatch.vkGetInstanceProcAddr(@enumFromInt(@intFromPtr(handle)), n).?);
    }

    fn guiNextFrame(_: *flecs.iter_t, viewport: []graphics.Viewport) !void {
        gui.backend.newFrame(viewport[0].getWidth(), viewport[0].getHeight());

        var open: bool = true;
        gui.showDemoWindow(&open);

        gui.backend.draw(@ptrFromInt(@intFromEnum(graphics.Renderer.getCurrentCmdList())));

        gui.UpdatePlatformWindows();
        gui.RenderPlatformWindowsDefault();
    }

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        const viewport = flecs.get(_scene, graphics.Graphics.mainViewport, graphics.Viewport).?;

        const guiPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .combined_image_sampler,
                .descriptor_count = 1,
            },
        };

        guiDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &guiPoolSizes,
            .pool_size_count = @intCast(guiPoolSizes.len),
            .max_sets = 1,
        }, null);

        vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.editor_vert.len,
            .p_code = @ptrCast(@alignCast(&shaders.editor_vert)),
        }, null);

        fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.editor_frag.len,
            .p_code = @ptrCast(@alignCast(&shaders.editor_frag)),
        }, null);

        renderPass = try createRenderPass();
        pipelineLayout = try createPipelineLayout();
        pipeline = try gfx.createPipeline(
            pipelineLayout,
            renderPass,
            vertexModule,
            fragmentModule,
            1000,
            1000,
        );

        cmdPool = try gfx.device.createCommandPool(&.{
            .queue_family_index = gfx.renderFamily,
        }, null);

        try gfx.device.allocateCommandBuffers(&.{
            .command_pool = cmdPool,
            .level = gfx.CommandBufferLevel.primary,
            .command_buffer_count = 1,
        }, @ptrCast(&cmdList));

        readBackBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = viewport.getWidth() * viewport.getHeight() * 2 * @sizeOf(u32),
                .usage = gfx.BufferUsageFlags{ .transfer_dst_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
            },
        );

        depthImage = try gfx.createImage(gfx.vkAllocator, &.{
            .image_type = gfx.ImageType.@"2d",
            .format = gfx.Format.d16_unorm,
            .extent = gfx.Extent3D{
                .width = viewport.getWidth(),
                .height = viewport.getHeight(),
                .depth = 1,
            },
            .array_layers = 1,
            .mip_levels = 1,
            .samples = gfx.SampleCountFlags{ .@"1_bit" = true },
            .tiling = gfx.ImageTiling.optimal,
            .initial_layout = gfx.ImageLayout.undefined,
            .usage = gfx.ImageUsageFlags{ .depth_stencil_attachment_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
            .p_queue_family_indices = null,
            .queue_family_index_count = 0,
        }, &.{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        });

        writeToImage = try gfx.createImage(gfx.vkAllocator, &.{
            .image_type = gfx.ImageType.@"2d",
            .format = gfx.Format.r32g32_uint,
            .extent = gfx.Extent3D{
                .width = viewport.getWidth(),
                .height = viewport.getHeight(),
                .depth = 1,
            },
            .array_layers = 1,
            .mip_levels = 1,
            .samples = gfx.SampleCountFlags{ .@"1_bit" = true },
            .tiling = gfx.ImageTiling.optimal,
            .initial_layout = gfx.ImageLayout.undefined,
            .usage = gfx.ImageUsageFlags{
                .color_attachment_bit = true,
                .transfer_src_bit = true,
            },
            .sharing_mode = gfx.SharingMode.exclusive,
            .p_queue_family_indices = null,
            .queue_family_index_count = 0,
        }, &.{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        });

        depthImageView = try gfx.device.createImageView(&.{
            .image = depthImage.image,
            .view_type = gfx.ImageViewType.@"2d",
            .format = gfx.Format.d16_unorm,
            .components = gfx.ComponentMapping{
                .a = gfx.ComponentSwizzle.a,
                .r = gfx.ComponentSwizzle.r,
                .g = gfx.ComponentSwizzle.g,
                .b = gfx.ComponentSwizzle.b,
            },
            .subresource_range = gfx.ImageSubresourceRange{
                .aspect_mask = gfx.ImageAspectFlags{ .depth_bit = true },
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
        }, null);

        writeToImageView = try gfx.device.createImageView(&.{
            .image = writeToImage.image,
            .view_type = gfx.ImageViewType.@"2d",
            .format = gfx.Format.r32g32_uint,
            .components = gfx.ComponentMapping{
                .a = gfx.ComponentSwizzle.a,
                .r = gfx.ComponentSwizzle.r,
                .g = gfx.ComponentSwizzle.g,
                .b = gfx.ComponentSwizzle.b,
            },
            .subresource_range = gfx.ImageSubresourceRange{
                .aspect_mask = gfx.ImageAspectFlags{ .color_bit = true },
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
        }, null);

        framebuffer = try gfx.device.createFramebuffer(&gfx.FramebufferCreateInfo{
            .render_pass = renderPass,
            .p_attachments = &.{
                writeToImageView,
                depthImageView,
            },
            .attachment_count = 2,
            .width = viewport.getWidth(),
            .height = viewport.getHeight(),
            .layers = 1,
        }, null);

        gui.init(util.mem.heap);
        gui.io.setConfigFlags(gui.ConfigFlags{
            .viewport_enable = true,
            .dock_enable = true,
        });

        _ = gui.backend.loadFunctions(
            loader,
            @ptrFromInt(@as(usize, @intFromEnum(gfx.instance.handle))),
        );

        gui.backend.init(viewport.getWindow(), &gui.backend.VulkanInitInfo{
            .instance = @ptrFromInt(@intFromEnum(gfx.instance.handle)),
            .physical_device = @ptrFromInt(@intFromEnum(gfx.physicalDevice)),
            .device = @ptrFromInt(@intFromEnum(gfx.device.handle)),
            .queueFamily = gfx.renderFamily,
            .queue = @ptrFromInt(@intFromEnum(gfx.renderQueue)),
            .renderPass = @ptrFromInt(@intFromEnum(graphics.Renderer._renderPass)),
            .descriptorPool = @ptrFromInt(@intFromEnum(guiDescriptorPool)),
            .minImageCount = 2,
            .imageCount = 3,
        });

        inline for (components) |comp| {
            comp.register(scene);
        }

        var desc = flecs.system_desc_t{};
        desc.callback = flecs.SystemImpl(render).exec;
        desc.query.filter.terms[0] = flecs.term_t{
            .id = flecs.id(graphics.ModelInstance),
            .inout = .In,
        };
        desc.query.filter.terms[1] = flecs.term_t{
            .id = flecs.id(graphics.Model),
            .inout = .In,
        };
        desc.query.filter.terms[2] = flecs.term_t{
            .id = flecs.id(graphics.Viewport),
            .inout = .In,
            .src = flecs.term_id_t{
                .id = graphics.Graphics.mainViewport,
            },
        };
        desc.query.filter.instanced = true;

        flecs.SYSTEM(scene, "Render IDs", flecs.PreStore, &desc);

        flecs.ADD_SYSTEM(_scene, "Gui new frame", flecs.OnStore, guiNextFrame);
    }

    pub fn preDeinit() !void {}

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try util.module.cleanUpComponent(comp, _scene);
        }

        gui.backend.deinit();
        gui.deinit();

        gfx.device.destroyDescriptorPool(guiDescriptorPool, null);

        gfx.device.destroyRenderPass(renderPass, null);
        gfx.device.destroyCommandPool(cmdPool, null);

        gfx.device.destroyFramebuffer(framebuffer, null);

        gfx.device.destroyImageView(depthImageView, null);
        gfx.device.destroyImageView(writeToImageView, null);

        gfx.destroyImage(gfx.vkAllocator, depthImage);
        gfx.destroyImage(gfx.vkAllocator, writeToImage);
        gfx.destroyBuffer(gfx.vkAllocator, readBackBuffer);

        gfx.device.destroyPipeline(pipeline, null);
        gfx.device.destroyPipelineLayout(pipelineLayout, null);
        gfx.device.destroyDescriptorSetLayout(instanceTransformLayout, null);
        gfx.device.destroyShaderModule(vertexModule, null);
        gfx.device.destroyShaderModule(fragmentModule, null);
    }

    pub fn render(
        it: *flecs.iter_t,
        modelInstances: []const graphics.ModelInstance,
        model: []const graphics.Model,
        viewport: []const graphics.Viewport,
    ) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.device.resetCommandPool(cmdPool, .{});

        try gfx.device.beginCommandBuffer(cmdList, &gfx.CommandBufferBeginInfo{
            .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true },
            .p_inheritance_info = &gfx.CommandBufferInheritanceInfo{
                .render_pass = renderPass,
                .framebuffer = framebuffer,
                .subpass = 0,
                .occlusion_query_enable = gfx.FALSE,
            },
        });

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = viewport[0].getWidth(),
                .height = viewport[0].getHeight(),
            },
        };

        const clearValues = [_]gfx.ClearValue{
            gfx.ClearValue{ .color = .{ .uint_32 = [4]u32{ 0.0, 0.0, 0.0, 0.0 } } },
            gfx.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };

        gfx.device.cmdBeginRenderPass(cmdList, &gfx.RenderPassBeginInfo{
            .render_pass = renderPass,
            .framebuffer = framebuffer,
            .render_area = renderArea,
            .p_clear_values = @ptrCast(&clearValues),
            .clear_value_count = @intCast(clearValues.len),
        }, gfx.SubpassContents.@"inline");

        gfx.device.cmdBindPipeline(cmdList, gfx.PipelineBindPoint.graphics, pipeline);
        gfx.device.cmdSetViewport(cmdList, 0, 1, @ptrCast(&gfx.Viewport{
            .width = @floatFromInt(viewport[0].getWidth()),
            .height = -@as(f32, @floatFromInt(viewport[0].getHeight())),
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = @floatFromInt(viewport[0].getHeight()),
        }));
        gfx.device.cmdSetScissor(cmdList, 0, 1, @ptrCast(&renderArea));

        gfx.device.cmdBindVertexBuffers(cmdList, 0, 1, @ptrCast(&model[0].vertexBuffer.buffer), &[_]u64{0});
        gfx.device.cmdBindIndexBuffer(cmdList, model[0].indexBuffer.buffer, 0, gfx.IndexType.uint32);

        const setsToBind = [_]gfx.DescriptorSet{
            graphics.Renderer.descriptorSet,
        };

        gfx.device.cmdBindDescriptorSets(cmdList, gfx.PipelineBindPoint.graphics, pipelineLayout, 0, setsToBind.len, @ptrCast(&setsToBind), 0, null);

        for (modelInstances, it.entities()) |intance, e| {
            gfx.device.cmdPushConstants(
                cmdList,
                pipelineLayout,
                gfx.ShaderStageFlags{ .fragment_bit = true },
                0,
                2 * @sizeOf(u32),
                @ptrCast(&e),
            );

            gfx.device.cmdBindDescriptorSets(
                cmdList,
                gfx.PipelineBindPoint.graphics,
                pipelineLayout,
                1,
                1,
                @ptrCast(&intance.descriptorSet),
                0,
                null,
            );

            gfx.device.cmdDrawIndexed(
                cmdList,
                @intCast(model[0].mesh.indexData.len),
                1,
                0,
                0,
                0,
            );
        }

        gfx.device.cmdEndRenderPass(cmdList);

        gfx.device.cmdPipelineBarrier(
            cmdList,
            gfx.PipelineStageFlags{ .color_attachment_output_bit = true },
            gfx.PipelineStageFlags{ .transfer_bit = true },
            gfx.DependencyFlags{},
            0,
            undefined,
            0,
            undefined,
            1,
            @ptrCast(&gfx.ImageMemoryBarrier{
                .image = writeToImage.image,
                .src_access_mask = .{},
                .dst_access_mask = .{
                    .transfer_read_bit = true,
                },
                .old_layout = .transfer_src_optimal,
                .new_layout = .transfer_src_optimal,
                .subresource_range = .{
                    .aspect_mask = .{
                        .color_bit = true,
                    },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .base_mip_level = 0,
                    .level_count = 1,
                },
                .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
            }),
        );

        gfx.device.cmdCopyImageToBuffer(
            cmdList,
            writeToImage.image,
            gfx.ImageLayout.transfer_src_optimal,
            readBackBuffer.buffer,
            1,
            @ptrCast(&gfx.BufferImageCopy{
                .buffer_image_height = 0,
                .buffer_offset = 0,
                .buffer_row_length = 0,
                .image_offset = gfx.Offset3D{
                    .x = 0,
                    .y = 0,
                    .z = 0,
                },
                .image_extent = gfx.Extent3D{
                    .width = viewport[0].getWidth(),
                    .height = viewport[0].getHeight(),
                    .depth = 1,
                },
                .image_subresource = gfx.ImageSubresourceLayers{
                    .aspect_mask = .{ .color_bit = true },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .mip_level = 0,
                },
            }),
        );

        try gfx.device.endCommandBuffer(cmdList);

        const signalValue = graphics.Renderer._semaphoreValue + 1;
        var waitValue = graphics.Renderer._semaphoreValue;
        graphics.Renderer._semaphoreValue += 1;

        try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
            gfx.SubmitInfo{
                .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                    .p_signal_semaphore_values = @ptrCast(&signalValue),
                    .signal_semaphore_value_count = 1,
                    .p_wait_semaphore_values = @ptrCast(&waitValue),
                    .wait_semaphore_value_count = 1,
                },
                .p_command_buffers = &[_]gfx.CommandBuffer{cmdList},
                .command_buffer_count = 1,
                .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{ .{ .color_attachment_output_bit = true }, .{ .color_attachment_output_bit = true } },
                .p_signal_semaphores = &[_]gfx.Semaphore{graphics.Renderer._timelineSemaphore},
                .signal_semaphore_count = 1,
                .p_wait_semaphores = &[_]gfx.Semaphore{graphics.Renderer._timelineSemaphore},
                .wait_semaphore_count = 1,
            },
        }, gfx.Fence.null_handle);

        waitValue = signalValue;

        _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&graphics.Renderer._timelineSemaphore),
            .p_values = &[_]u64{waitValue},
            .semaphore_count = 1,
        }, ~@as(u64, 0));

        const data = try gfx.startReadMemory(
            gfx.vkAllocator,
            readBackBuffer,
            viewport[0].getWidth() * viewport[0].getHeight() * 2 * @sizeOf(u32),
        );
        defer gfx.stopReadMemory(gfx.vkAllocator, readBackBuffer);

        if (StateManager.inEditor and
            graphics.InputState.mouseX - 1 >= 0 and
            graphics.InputState.mouseY - 1 >= 0)
        {
            const mouseX: u32 = @intFromFloat(graphics.InputState.mouseX - 1);
            const mouseY: u32 = @intFromFloat(graphics.InputState.mouseY - 1);

            if (mouseX < viewport[0].getWidth() and
                mouseY < viewport[0].getHeight())
            {
                const pixelReadPos = mouseY * viewport[0].getWidth() + mouseX;
                const idData = @as([*]u64, @ptrCast(@alignCast(data.ptr)))[0 .. data.len / 4];

                const id = idData[pixelReadPos];
                if (id != 0) {
                    const enttName: [*:0]const u8 = flecs.get_name(_scene, id).?;

                    util.log.info("{s}", .{enttName});
                }
            }
        }
    }

    fn createPipelineLayout() !gfx.PipelineLayout {
        const instanceDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
            },
        };

        instanceTransformLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &instanceDescriptorBindings,
            .binding_count = @intCast(instanceDescriptorBindings.len),
        }, null);

        const setLayouts = [_]gfx.DescriptorSetLayout{
            graphics.Renderer.globalDescriptorSetLayout,
            instanceTransformLayout,
        };

        const pushConstantRanges = gfx.PushConstantRange{
            .offset = 0,
            .size = 2 * @sizeOf(u32),
            .stage_flags = .{ .fragment_bit = true },
        };

        pipelineLayout = try gfx.device.createPipelineLayout(&gfx.PipelineLayoutCreateInfo{
            .p_set_layouts = @ptrCast(&setLayouts),
            .set_layout_count = @intCast(setLayouts.len),
            .p_push_constant_ranges = @ptrCast(&pushConstantRanges),
            .push_constant_range_count = 1,
        }, null);

        return pipelineLayout;
    }

    fn createRenderPass() !gfx.RenderPass {
        const attachmentDescriptions = [_]gfx.AttachmentDescription{
            gfx.AttachmentDescription{
                .format = gfx.Format.r32g32_uint, //u64 of our entity id
                .samples = gfx.SampleCountFlags{ .@"1_bit" = true },
                .load_op = gfx.AttachmentLoadOp.clear,
                .store_op = gfx.AttachmentStoreOp.store,
                .stencil_load_op = gfx.AttachmentLoadOp.dont_care,
                .stencil_store_op = gfx.AttachmentStoreOp.dont_care,
                .initial_layout = gfx.ImageLayout.undefined,
                .final_layout = gfx.ImageLayout.transfer_src_optimal,
            },
            gfx.AttachmentDescription{
                .format = gfx.Format.d16_unorm,
                .samples = gfx.SampleCountFlags{ .@"1_bit" = true },
                .load_op = gfx.AttachmentLoadOp.clear,
                .store_op = gfx.AttachmentStoreOp.dont_care,
                .stencil_load_op = gfx.AttachmentLoadOp.dont_care,
                .stencil_store_op = gfx.AttachmentStoreOp.dont_care,
                .initial_layout = gfx.ImageLayout.undefined,
                .final_layout = gfx.ImageLayout.depth_stencil_attachment_optimal,
            },
        };

        const colorReferences = [_]gfx.AttachmentReference{
            gfx.AttachmentReference{
                .attachment = 0,
                .layout = gfx.ImageLayout.color_attachment_optimal,
            },
        };
        const depthRefernce = gfx.AttachmentReference{
            .attachment = 1,
            .layout = gfx.ImageLayout.depth_stencil_attachment_optimal,
        };

        const subpasses = [_]gfx.SubpassDescription{
            gfx.SubpassDescription{
                .pipeline_bind_point = gfx.PipelineBindPoint.graphics,
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

        const subpassDependencies = [_]gfx.SubpassDependency{
            gfx.SubpassDependency{
                .src_subpass = gfx.SUBPASS_EXTERNAL,
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
            gfx.SubpassDependency{
                .src_subpass = 0,
                .dst_subpass = gfx.SUBPASS_EXTERNAL,
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

        return try gfx.device.createRenderPass(&gfx.RenderPassCreateInfo{
            .p_attachments = &attachmentDescriptions,
            .attachment_count = @intCast(attachmentDescriptions.len),
            .p_subpasses = &subpasses,
            .subpass_count = @intCast(subpasses.len),
            .p_dependencies = &subpassDependencies,
            .dependency_count = @intCast(subpassDependencies.len),
        }, null);
    }
};
