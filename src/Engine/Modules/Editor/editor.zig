const util = @import("util");

const flecs = @import("zflecs");
const tracy = @import("ztracy");
const gui = @import("zgui");

const graphics = @import("GraphicsModule");
const core = @import("CoreModule");

const gfx = graphics.gfx;

pub const Editor = struct {
    pub const name: []const u8 = "editor";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var inEditor: bool = false;
    var selectedEntity: u64 = 0;
    var entityWindowOpen: bool = false;

    var val3: @Vector(3, f32) = .{ 0, 0, 0 };

    var _scene: *flecs.world_t = undefined;

    var guiDescriptorPool: gfx.DescriptorPool = undefined;

    var renderPass: gfx.RenderPass = undefined;

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
    var idPipeline: gfx.Pipeline = undefined;

    const components = [_]type{};

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        const viewport = flecs.get(_scene, graphics.Graphics.mainViewport, graphics.Viewport).?;

        const guiPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .CombinedImageSampler,
                .descriptorCount = 1,
            },
        };

        guiDescriptorPool = try gfx.CreateDescriptorPool(
            &gfx.DescriptorPoolCreateInfo{
                .pPoolSizes = &guiPoolSizes,
                .poolSizeCount = @intCast(guiPoolSizes.len),
                .maxSets = 1,
            },
        );

        const vertexCode = try graphics.shaders.getOrAdd("resources/shaders/id/id.vert");
        vertexModule = try gfx.CreateShaderModule(
            &gfx.ShaderModuleCreateInfo{
                .codeSize = vertexCode.len,
                .pCode = @ptrCast(@alignCast(vertexCode.ptr)),
            },
        );

        const fragmentCode = try graphics.shaders.getOrAdd("resources/shaders/id/id.frag");
        fragmentModule = try gfx.CreateShaderModule(
            &gfx.ShaderModuleCreateInfo{
                .codeSize = fragmentCode.len,
                .pCode = @ptrCast(@alignCast(fragmentCode.ptr)),
            },
        );

        renderPass = try createRenderPass();
        pipelineLayout = try createPipelineLayout();
        idPipeline = try gfx.createPipeline(
            null,
            pipelineLayout,
            renderPass,
            vertexModule,
            fragmentModule,
            &[_]gfx.VertexInputBindingDescription{
                gfx.VertexInputBindingDescription{
                    .binding = 0,
                    .stride = 32,
                    .inputRate = gfx.VertexInputRate.Vertex,
                },
            },
            &[_]gfx.VertexInputAttributeDescription{
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 0,
                    .offset = 0,
                    .format = gfx.Format.R32g32b32Sfloat,
                },
            },
            true,
            null,
        );

        try createReadBackData(graphics.InputState.viewportX, graphics.InputState.viewportY);

        gui.init(util.mem.heap);
        gui.io.setConfigFlags(gui.ConfigFlags{
            .viewport_enable = true,
            .dock_enable = true,
        });

        _ = gui.backend.loadFunctions(
            loader,
            gfx.gInstance,
        );

        gui.backend.init(
            gui.backend.ImGui_ImplVulkan_InitInfo{
                .instance = gfx.gInstance,
                .physical_device = gfx.physicalDevice,
                .device = gfx.gDevice,
                .queue_family = gfx.renderFamily,
                .queue = gfx.renderQueue,
                .render_pass = graphics.Renderer._renderPass,
                .descriptor_pool = guiDescriptorPool,
                .min_image_count = 2,
                .image_count = 3,
            },
            viewport.getWindow(),
        );

        //const rubikFont = gui.io.addFontFromFile("resources/Rubik/static/Rubik-Light.ttf", 36);
        //gui.io.setDefaultFont(rubikFont);

        //const style = gui.getStyle();
        //gui.Style.scaleAllSizes(style, 2);

        inline for (components) |comp| {
            comp.register(scene);
        }

        _ = flecs.ADD_SYSTEM(_scene, "Editor onEvent", flecs.PostLoad, onEvent);

        _ = flecs.ADD_SYSTEM(_scene, "Update selected ID", flecs.PreUpdate, updateSelectedID);

        _ = flecs.ADD_SYSTEM(_scene, "Start Render IDs", flecs.OnStore, startRenderIDs);
        _ = flecs.ADD_SYSTEM(scene, "Render IDs", flecs.OnStore, renderIDs);
        _ = flecs.ADD_SYSTEM(_scene, "Stop render IDs", flecs.OnStore, stopRenderIDs);
        _ = flecs.ADD_SYSTEM(_scene, "Gui new frame", flecs.OnStore, guiNextFrame);

        //const gizmoMat = try graphics.Material.new(
        //    "GizmoMat",
        //    graphics.shaders.get("gizmo.vert"),
        //    graphics.shaders.get("gizmo.frag"),
        //);

        const gizmo = try graphics.Model.new(
            "Gizmo",
            "resources/models/Gizmo.glb",
            graphics.Graphics.baseMaterial,
        );

        _ = try graphics.ModelInstance.new(
            "GizmoInstance",
            gizmo,
            util.math.videntity(),
        );
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

        try gfx.DestroyDescriptorPool(guiDescriptorPool);

        try gfx.DestroyRenderPass(renderPass);

        try destroyReadBackData();

        try gfx.DestroyPipeline(idPipeline);
        try gfx.DestroyPipelineLayout(pipelineLayout);
        try gfx.DestroyDescriptorSetLayout(instanceTransformLayout);
        try gfx.DestroyShaderModule(vertexModule);
        try gfx.DestroyShaderModule(fragmentModule);
    }

    pub fn onEvent(it: *flecs.iter_t) !void {
        const input = graphics.InputState;

        const viewport = flecs.get(it.world, graphics.Graphics.mainViewport, graphics.Viewport).?;

        if (input.getKeyState(.F1).isPress and !inEditor) {
            inEditor = true;
            try viewport.setCursorEnabled(true);
        } else if (input.getKeyState(.F1).isPress and inEditor) {
            inEditor = false;
            try viewport.setCursorEnabled(false);
        }

        if (inEditor) {
            input.deltaMouseX = 0;
            input.deltaMouseY = 0;
        }

        input.clearKey(.F1);
    }

    fn loader(fnName: [*:0]const u8, handle: ?*anyopaque) callconv(.c) ?*anyopaque {
        return @constCast(@ptrCast(gfx.vkGetInstanceProcAddr.?(@ptrCast(handle), fnName).?));
    }

    fn entitySelected() bool {
        return selectedEntity != 0;
    }

    fn guiNextFrame(_: *flecs.iter_t, viewport: []graphics.Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render gui", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gui.backend.newFrame(viewport[0].getWidth(), viewport[0].getHeight());

        gui.setNextWindowSize(.{
            .h = 1000,
            .w = 600,
            .cond = .once,
        });

        if (entitySelected()) {
            //const entityName: [*:0]const u8 = flecs.get_name(_scene, selectedEntity).?;
            var transform: core.Transform = flecs.get(_scene, selectedEntity, core.Transform).?.*;

            _ = gui.begin(
                "Selection",
                .{
                    .flags = .{
                        .no_saved_settings = true,
                        .no_collapse = true,
                    },
                    .popen = &entityWindowOpen,
                },
            );

            //gui.showDemoWindow(null);

            if (gui.collapsingHeader("Transform", .{})) {
                if (gui.beginTable("LocalTransform", .{
                    .column = 4,
                    .flags = gui.TableFlags{
                        .borders = gui.TableBorderFlags{
                            .inner_h = true,
                            .outer_h = true,
                            .inner_v = true,
                            .outer_v = true,
                        },
                    },
                })) {
                    gui.tableSetupColumn("Local", .{
                        .flags = gui.TableColumnFlags{
                            .width_fixed = true,
                        },
                    });
                    gui.tableSetupColumn("x", .{
                        .flags = gui.TableColumnFlags{
                            .width_stretch = true,
                        },
                    });
                    gui.tableSetupColumn("y", .{
                        .flags = gui.TableColumnFlags{
                            .width_stretch = true,
                        },
                    });
                    gui.tableSetupColumn("z", .{
                        .flags = gui.TableColumnFlags{
                            .width_stretch = true,
                        },
                    });
                    gui.tableHeadersRow();

                    gui.tableNextRow(.{});
                    _ = gui.tableSetColumnIndex(0);
                    gui.pushItemWidth(-gui.f32_min);
                    _ = gui.tableSetColumnIndex(1);
                    gui.pushItemWidth(-gui.f32_min);
                    _ = gui.tableSetColumnIndex(2);
                    gui.pushItemWidth(-gui.f32_min);
                    _ = gui.tableSetColumnIndex(3);
                    gui.pushItemWidth(-gui.f32_min);

                    gui.tableNextRow(.{});

                    //gui.pushIntId(0);
                    _ = gui.tableSetColumnIndex(0);
                    gui.text("Position", .{});
                    _ = gui.tableSetColumnIndex(1);
                    _ = gui.dragFloat("##x", .{
                        .v = &transform.localPosition[0],
                        .speed = 10000,
                        .cfmt = "%.3f",
                        .max = 100000000.0,
                        .min = -100000000.0,
                        .flags = .{
                            .logarithmic = true,
                            .no_round_to_format = true,
                        },
                    });
                    _ = gui.tableSetColumnIndex(2);
                    _ = gui.dragFloat("##y", .{
                        .v = &transform.localPosition[1],
                        .speed = 10000,
                        .cfmt = "%.3f",
                        .max = 100000000.0,
                        .min = -100000000.0,
                        .flags = .{
                            .logarithmic = true,
                            .no_round_to_format = true,
                        },
                    });
                    _ = gui.tableSetColumnIndex(3);
                    _ = gui.dragFloat("##z", .{
                        .v = &transform.localPosition[2],
                        .speed = 10000,
                        .cfmt = "%.3f",
                        .max = 100000000.0,
                        .min = -100000000.0,
                        .flags = .{
                            .logarithmic = true,
                            .no_round_to_format = true,
                        },
                    });
                    //gui.popId();

                    gui.endTable();
                }
            }

            gui.end();

            _ = flecs.set(_scene, selectedEntity, core.Transform, transform);
        }

        gui.backend.render(graphics.Renderer.getCurrentCmdList());

        gui.updatePlatformWindows();
        gui.renderPlatformWindowsDefault();
    }

    pub fn updateSelectedID(_: *flecs.iter_t) !void {
        const data = try gfx.startReadMemory(
            gfx.vkAllocator,
            readBackBuffer,
            graphics.InputState.viewportX * graphics.InputState.viewportY * 2 * @sizeOf(u32),
        );
        defer gfx.stopReadMemory(gfx.vkAllocator, readBackBuffer);

        if (inEditor and
            graphics.InputState.getKeyState(.Mouseleft).isPress and
            !gui.isWindowHovered(.{ .any_window = true }) and
            graphics.InputState.mouseX - 1 >= 0 and
            graphics.InputState.mouseY - 1 >= 0)
        {
            const mouseX: u32 = @intFromFloat(graphics.InputState.mouseX - 1);
            const mouseY: u32 = @intFromFloat(graphics.InputState.mouseY - 1);

            if (mouseX < graphics.InputState.viewportX and
                mouseY < graphics.InputState.viewportY)
            {
                const pixelReadPos = mouseY * graphics.InputState.viewportX + mouseX;
                const idData = @as([*]u64, @ptrCast(@alignCast(data.ptr)))[0 .. data.len / 4];

                selectedEntity = idData[pixelReadPos];
            }
        }
    }

    pub fn startRenderIDs(_: *flecs.iter_t) !void {
        if (graphics.InputState.deltaViewportX != 0 or graphics.InputState.deltaViewportY != 0) {
            try destroyReadBackData();
            try createReadBackData(graphics.InputState.viewportX, graphics.InputState.viewportY);
        }

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = graphics.InputState.viewportX,
                .height = graphics.InputState.viewportY,
            },
        };

        const clearValues = [_]gfx.ClearValue{
            gfx.ClearValue{
                .color = .{
                    .uint32 = [4]u32{
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

        try gfx.CmdBeginRenderPass(graphics.Renderer.getCurrentCmdList(), &gfx.RenderPassBeginInfo{
            .renderPass = renderPass,
            .framebuffer = framebuffer,
            .renderArea = renderArea,
            .pClearValues = @ptrCast(&clearValues),
            .clearValueCount = @intCast(clearValues.len),
        }, gfx.SubpassContents.Inline);
    }

    pub fn renderIDs(
        it: *flecs.iter_t,
        modelInstances: []const graphics.ModelInstance,
        model: []const graphics.Model,
    ) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render IDs", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.CmdBindPipeline(
            graphics.Renderer.getCurrentCmdList(),
            gfx.PipelineBindPoint.Graphics,
            idPipeline,
        );

        try gfx.CmdSetViewport(
            graphics.Renderer.getCurrentCmdList(),
            0,
            &[_]gfx.Viewport{
                gfx.Viewport{
                    .width = @floatFromInt(graphics.InputState.viewportX),
                    .height = -@as(f32, @floatFromInt(graphics.InputState.viewportY)),
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                    .x = 0.0,
                    .y = @floatFromInt(graphics.InputState.viewportY),
                },
            },
        );

        try gfx.CmdSetScissor(
            graphics.Renderer.getCurrentCmdList(),
            0,
            &[_]gfx.Rect2D{
                gfx.Rect2D{
                    .offset = gfx.Offset2D{ .x = 0, .y = 0 },
                    .extent = gfx.Extent2D{
                        .width = graphics.InputState.viewportX,
                        .height = graphics.InputState.viewportY,
                    },
                },
            },
        );

        try gfx.CmdBindVertexBuffers(
            graphics.Renderer.getCurrentCmdList(),
            0,
            1,
            @ptrCast(&model[0].vertexBuffer.buffer),
            &[_]u64{0},
        );
        try gfx.CmdBindIndexBuffer(
            graphics.Renderer.getCurrentCmdList(),
            model[0].indexBuffer.buffer,
            0,
            gfx.IndexType.Uint32,
        );

        try gfx.CmdBindDescriptorSets(
            graphics.Renderer.getCurrentCmdList(),
            gfx.PipelineBindPoint.Graphics,
            pipelineLayout,
            0,
            &[_]gfx.DescriptorSet{
                graphics.Renderer.descriptorSet,
            },
            &[_]u32{},
        );

        for (modelInstances, it.entities()) |intance, e| {
            try gfx.CmdPushConstants(
                graphics.Renderer.getCurrentCmdList(),
                pipelineLayout,
                gfx.toFlags(&[_]gfx.ShaderStageFlagBits{.FragmentBit}),
                0,
                2 * @sizeOf(u32),
                @ptrCast(&e),
            );

            try gfx.CmdBindDescriptorSets(
                graphics.Renderer.getCurrentCmdList(),
                gfx.PipelineBindPoint.Graphics,
                pipelineLayout,
                1,
                &[_]gfx.DescriptorSet{
                    intance.descriptorSet,
                },
                &[_]u32{},
            );

            try gfx.CmdDrawIndexed(
                graphics.Renderer.getCurrentCmdList(),
                @intCast(model[0].mesh.indexData.len),
                1,
                0,
                0,
                0,
            );
        }
    }

    fn stopRenderIDs(_: *flecs.iter_t) !void {
        try gfx.CmdEndRenderPass(graphics.Renderer.getCurrentCmdList());

        try gfx.CmdPipelineBarrier(
            graphics.Renderer.getCurrentCmdList(),
            gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.ColorAttachmentOutputBit}),
            gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.TransferBit}),
            gfx.toFlags(&[_]gfx.DependencyFlagBits{}),
            &[_]gfx.MemoryBarrier{},
            &[_]gfx.BufferMemoryBarrier{},
            &[_]gfx.ImageMemoryBarrier{
                gfx.ImageMemoryBarrier{
                    .image = writeToImage.image,
                    .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{}),
                    .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.TransferReadBit}),
                    .oldLayout = .TransferSrcOptimal,
                    .newLayout = .TransferSrcOptimal,
                    .subresourceRange = .{
                        .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.ColorBit}),
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                    },
                    .dstQueueFamilyIndex = gfx.queueFamilyIgnored,
                    .srcQueueFamilyIndex = gfx.queueFamilyIgnored,
                },
            },
        );

        try gfx.CmdCopyImageToBuffer(
            graphics.Renderer.getCurrentCmdList(),
            writeToImage.image,
            gfx.ImageLayout.TransferSrcOptimal,
            readBackBuffer.buffer,
            &[_]gfx.BufferImageCopy{
                gfx.BufferImageCopy{
                    .bufferImageHeight = 0,
                    .bufferOffset = 0,
                    .bufferRowLength = 0,
                    .imageOffset = gfx.Offset3D{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                    .imageExtent = gfx.Extent3D{
                        .width = graphics.InputState.viewportX,
                        .height = graphics.InputState.viewportY,
                        .depth = 1,
                    },
                    .imageSubresource = gfx.ImageSubresourceLayers{
                        .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.ColorBit}),
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                        .mipLevel = 0,
                    },
                },
            },
        );

        try gfx.CmdPipelineBarrier(
            graphics.Renderer.getCurrentCmdList(),
            gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.TransferBit}),
            gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.TransferBit}),
            gfx.toFlags(&[_]gfx.DependencyFlagBits{}),
            &[_]gfx.MemoryBarrier{},
            &[_]gfx.BufferMemoryBarrier{
                gfx.BufferMemoryBarrier{
                    .buffer = readBackBuffer.buffer,
                    .offset = 0,
                    .size = graphics.InputState.viewportX * graphics.InputState.viewportY * 2 * @sizeOf(u32),
                    .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.TransferWriteBit}),
                    .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.TransferWriteBit}),
                    .srcQueueFamilyIndex = gfx.queueFamilyIgnored,
                    .dstQueueFamilyIndex = gfx.queueFamilyIgnored,
                },
            },
            &[_]gfx.ImageMemoryBarrier{},
        );
    }

    fn createReadBackData(width: u32, height: u32) !void {
        readBackBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = width * height * 2 * @sizeOf(u32),
                .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{.TransferDstBit}),
                .sharingMode = gfx.SharingMode.Exclusive,
                .pQueueFamilyIndices = null,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
            },
        );

        depthImage = try gfx.createImage(
            gfx.vkAllocator,
            &gfx.ImageCreateInfo{
                .imageType = gfx.ImageType.@"2d",
                .format = gfx.Format.D16Unorm,
                .extent = gfx.Extent3D{
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                .arrayLayers = 1,
                .mipLevels = 1,
                .samples = .@"1Bit",
                .tiling = gfx.ImageTiling.Optimal,
                .initialLayout = gfx.ImageLayout.Undefined,
                .usage = gfx.toFlags(&[_]gfx.ImageUsageFlagBits{.DepthStencilAttachmentBit}),
                .sharingMode = gfx.SharingMode.Exclusive,
                .pQueueFamilyIndices = null,
                .queueFamilyIndexCount = 0,
            },
            &.{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        writeToImage = try gfx.createImage(gfx.vkAllocator, &.{
            .imageType = gfx.ImageType.@"2d",
            .format = gfx.Format.R32g32Uint,
            .extent = gfx.Extent3D{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .arrayLayers = 1,
            .mipLevels = 1,
            .samples = .@"1Bit",
            .tiling = gfx.ImageTiling.Optimal,
            .initialLayout = gfx.ImageLayout.Undefined,
            .usage = gfx.toFlags(&[_]gfx.ImageUsageFlagBits{
                .ColorAttachmentBit,
                .TransferSrcBit,
            }),
            .sharingMode = gfx.SharingMode.Exclusive,
            .pQueueFamilyIndices = null,
            .queueFamilyIndexCount = 0,
        }, &.{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        });

        depthImageView = try gfx.CreateImageView(
            &gfx.ImageViewCreateInfo{
                .image = depthImage.image,
                .viewType = gfx.ImageViewType.@"2d",
                .format = gfx.Format.D16Unorm,
                .components = gfx.ComponentMapping{
                    .a = gfx.ComponentSwizzle.A,
                    .r = gfx.ComponentSwizzle.R,
                    .g = gfx.ComponentSwizzle.G,
                    .b = gfx.ComponentSwizzle.B,
                },
                .subresourceRange = gfx.ImageSubresourceRange{
                    .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.DepthBit}),
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                },
            },
        );

        writeToImageView = try gfx.CreateImageView(
            &gfx.ImageViewCreateInfo{
                .image = writeToImage.image,
                .viewType = gfx.ImageViewType.@"2d",
                .format = gfx.Format.R32g32Uint,
                .components = gfx.ComponentMapping{
                    .a = gfx.ComponentSwizzle.A,
                    .r = gfx.ComponentSwizzle.R,
                    .g = gfx.ComponentSwizzle.G,
                    .b = gfx.ComponentSwizzle.B,
                },
                .subresourceRange = gfx.ImageSubresourceRange{
                    .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.ColorBit}),
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                },
            },
        );

        framebuffer = try gfx.CreateFramebuffer(
            &gfx.FramebufferCreateInfo{
                .renderPass = renderPass,
                .pAttachments = &[_]gfx.ImageView{
                    writeToImageView,
                    depthImageView,
                },
                .attachmentCount = 2,
                .width = width,
                .height = height,
                .layers = 1,
            },
        );
    }

    fn destroyReadBackData() !void {
        try gfx.DestroyFramebuffer(framebuffer);

        try gfx.DestroyImageView(depthImageView);
        try gfx.DestroyImageView(writeToImageView);

        gfx.destroyImage(gfx.vkAllocator, depthImage);
        gfx.destroyImage(gfx.vkAllocator, writeToImage);
        gfx.destroyBuffer(gfx.vkAllocator, readBackBuffer);
    }

    fn createPipelineLayout() !gfx.PipelineLayout {
        const instanceDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorType = gfx.DescriptorType.UniformBuffer,
                .descriptorCount = 1,
                .stageFlags = gfx.toFlags(&[_]gfx.ShaderStageFlagBits{.VertexBit}),
            },
        };

        instanceTransformLayout = try gfx.CreateDescriptorSetLayout(
            &gfx.DescriptorSetLayoutCreateInfo{
                .pBindings = &instanceDescriptorBindings,
                .bindingCount = @intCast(instanceDescriptorBindings.len),
            },
        );

        const setLayouts = [_]gfx.DescriptorSetLayout{
            graphics.Renderer.globalDescriptorSetLayout,
            instanceTransformLayout,
        };

        const pushConstantRanges = gfx.PushConstantRange{
            .offset = 0,
            .size = 2 * @sizeOf(u32),
            .stageFlags = gfx.toFlags(&[_]gfx.ShaderStageFlagBits{.FragmentBit}),
        };

        pipelineLayout = try gfx.CreatePipelineLayout(
            &gfx.PipelineLayoutCreateInfo{
                .pSetLayouts = @ptrCast(&setLayouts),
                .setLayoutCount = @intCast(setLayouts.len),
                .pPushConstantRanges = @ptrCast(&pushConstantRanges),
                .pushConstantRangeCount = 1,
            },
        );

        return pipelineLayout;
    }

    fn createRenderPass() !gfx.RenderPass {
        const attachmentDescriptions = [_]gfx.AttachmentDescription{
            gfx.AttachmentDescription{
                .format = gfx.Format.R32g32Uint, //u64 of our entity id
                .samples = .@"1Bit",
                .loadOp = gfx.AttachmentLoadOp.Clear,
                .storeOp = gfx.AttachmentStoreOp.Store,
                .stencilLoadOp = gfx.AttachmentLoadOp.DontCare,
                .stencilStoreOp = gfx.AttachmentStoreOp.DontCare,
                .initialLayout = gfx.ImageLayout.Undefined,
                .finalLayout = gfx.ImageLayout.TransferSrcOptimal,
            },
            gfx.AttachmentDescription{
                .format = gfx.Format.D16Unorm,
                .samples = .@"1Bit",
                .loadOp = gfx.AttachmentLoadOp.Clear,
                .storeOp = gfx.AttachmentStoreOp.DontCare,
                .stencilLoadOp = gfx.AttachmentLoadOp.DontCare,
                .stencilStoreOp = gfx.AttachmentStoreOp.DontCare,
                .initialLayout = gfx.ImageLayout.Undefined,
                .finalLayout = gfx.ImageLayout.DepthStencilAttachmentOptimal,
            },
        };

        const colorReferences = [_]gfx.AttachmentReference{
            gfx.AttachmentReference{
                .attachment = 0,
                .layout = gfx.ImageLayout.ColorAttachmentOptimal,
            },
        };
        const depthRefernce = gfx.AttachmentReference{
            .attachment = 1,
            .layout = gfx.ImageLayout.DepthStencilAttachmentOptimal,
        };

        const subpasses = [_]gfx.SubpassDescription{
            gfx.SubpassDescription{
                .pipelineBindPoint = gfx.PipelineBindPoint.Graphics,
                .pInputAttachments = null,
                .inputAttachmentCount = 0,
                .pDepthStencilAttachment = &depthRefernce,
                .pColorAttachments = &colorReferences,
                .pResolveAttachments = null,
                .colorAttachmentCount = 1,
                .pPreserveAttachments = null,
                .preserveAttachmentCount = 0,
            },
        };

        const subpassDependencies = [_]gfx.SubpassDependency{
            gfx.SubpassDependency{
                .srcSubpass = gfx.subpassExternal,
                .dstSubpass = 0,
                .srcStageMask = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{
                    .ColorAttachmentOutputBit,
                    .EarlyFragmentTestsBit,
                }),
                .dstStageMask = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{
                    .ColorAttachmentOutputBit,
                    .EarlyFragmentTestsBit,
                }),
                .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{}),
                .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{
                    .ColorAttachmentWriteBit,
                    .DepthStencilAttachmentWriteBit,
                }),
                .dependencyFlags = gfx.toFlags(&[_]gfx.DependencyFlagBits{}),
            },
            gfx.SubpassDependency{
                .srcSubpass = 0,
                .dstSubpass = gfx.subpassExternal,
                .srcStageMask = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{
                    .LateFragmentTestsBit,
                    .ColorAttachmentOutputBit,
                }),
                .dstStageMask = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{
                    .EarlyFragmentTestsBit,
                }),
                .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{
                    .DepthStencilAttachmentWriteBit,
                    .ColorAttachmentWriteBit,
                }),
                .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{
                    //.depth_stencil_attachment_write_bit = true,
                }),
                .dependencyFlags = gfx.toFlags(&[_]gfx.DependencyFlagBits{}),
            },
        };

        return try gfx.CreateRenderPass(
            &gfx.RenderPassCreateInfo{
                .pAttachments = &attachmentDescriptions,
                .attachmentCount = @intCast(attachmentDescriptions.len),
                .pSubpasses = &subpasses,
                .subpassCount = @intCast(subpasses.len),
                .pDependencies = &subpassDependencies,
                .dependencyCount = @intCast(subpassDependencies.len),
            },
        );
    }
};
