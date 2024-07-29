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
                .type = .combined_image_sampler,
                .descriptor_count = 1,
            },
        };

        guiDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &guiPoolSizes,
            .pool_size_count = @intCast(guiPoolSizes.len),
            .max_sets = 1,
        }, null);

        const vertexCode = graphics.shaders.get("id.vert");
        vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = vertexCode.len,
            .p_code = @ptrCast(@alignCast(vertexCode.ptr)),
        }, null);

        const fragmentCode = graphics.shaders.get("id.frag");
        fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = fragmentCode.len,
            .p_code = @ptrCast(@alignCast(fragmentCode.ptr)),
        }, null);

        renderPass = try createRenderPass();
        pipelineLayout = try createPipelineLayout();
        idPipeline = try gfx.createPipeline(
            pipelineLayout,
            renderPass,
            vertexModule,
            fragmentModule,
            &[_]gfx.VertexInputBindingDescription{
                gfx.VertexInputBindingDescription{
                    .binding = 0,
                    .stride = 32,
                    .input_rate = gfx.VertexInputRate.vertex,
                },
            },
            &[_]gfx.VertexInputAttributeDescription{
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 0,
                    .offset = 0,
                    .format = gfx.Format.r32g32b32_sfloat,
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

        const rubikFont = gui.io.addFontFromFile("resources/Rubik/static/Rubik-Light.ttf", 36);
        gui.io.setDefaultFont(rubikFont);

        const style = gui.getStyle();
        gui.Style.scaleAllSizes(style, 2);

        inline for (components) |comp| {
            comp.register(scene);
        }

        flecs.ADD_SYSTEM(_scene, "Editor onEvent", flecs.PostLoad, onEvent);

        flecs.ADD_SYSTEM(_scene, "Update selected ID", flecs.PreUpdate, updateSelectedID);

        flecs.ADD_SYSTEM(_scene, "Start Render IDs", flecs.OnStore, startRenderIDs);
        flecs.ADD_SYSTEM(scene, "Render IDs", flecs.OnStore, renderIDs);
        flecs.ADD_SYSTEM(_scene, "Stop render IDs", flecs.OnStore, stopRenderIDs);
        flecs.ADD_SYSTEM(_scene, "Gui new frame", flecs.OnStore, guiNextFrame);

        //const gizmoMat = try graphics.Material.new(
        //    "GizmoMat",
        //    graphics.shaders.get("gizmo.vert"),
        //    graphics.shaders.get("gizmo.frag"),
        //);

        //const gizmo = try graphics.Model.new(
        //    "Gizmo",
        //    "resources/models/Gizmo.glb",
        //    gizmoMat,
        //);

        //_ = try graphics.ModelInstance.new(
        //    "GizmoInstance",
        //    gizmo,
        //    util.math.videntity(),
        //);
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

        destroyReadBackData();

        gfx.device.destroyPipeline(idPipeline, null);
        gfx.device.destroyPipelineLayout(pipelineLayout, null);
        gfx.device.destroyDescriptorSetLayout(instanceTransformLayout, null);
        gfx.device.destroyShaderModule(vertexModule, null);
        gfx.device.destroyShaderModule(fragmentModule, null);
    }

    pub fn onEvent(it: *flecs.iter_t) void {
        const input = graphics.InputState;

        const viewport = flecs.get(it.world, graphics.Graphics.mainViewport, graphics.Viewport).?;

        if (input.getKeyState(.F1).isPress and !inEditor) {
            inEditor = true;
            viewport.setCursorEnabled(true);
        } else if (input.getKeyState(.F1).isPress and inEditor) {
            inEditor = false;
            viewport.setCursorEnabled(false);
        }

        if (inEditor) {
            input.deltaMouseX = 0;
            input.deltaMouseY = 0;
        }

        input.clearKey(.F1);
    }

    fn loader(n: [*:0]const u8, handle: *const anyopaque) ?*const anyopaque {
        return @ptrCast(gfx.baseDispatch.dispatch.vkGetInstanceProcAddr(@enumFromInt(@intFromPtr(handle)), n).?);
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

        gui.backend.draw(@ptrFromInt(@intFromEnum(graphics.Renderer.getCurrentCmdList())));

        gui.UpdatePlatformWindows();
        gui.RenderPlatformWindowsDefault();
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
            destroyReadBackData();
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
            gfx.ClearValue{ .color = .{ .uint_32 = [4]u32{ 0.0, 0.0, 0.0, 0.0 } } },
            gfx.ClearValue{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };

        gfx.device.cmdBeginRenderPass(graphics.Renderer.getCurrentCmdList(), &gfx.RenderPassBeginInfo{
            .render_pass = renderPass,
            .framebuffer = framebuffer,
            .render_area = renderArea,
            .p_clear_values = @ptrCast(&clearValues),
            .clear_value_count = @intCast(clearValues.len),
        }, gfx.SubpassContents.@"inline");
    }

    pub fn renderIDs(
        it: *flecs.iter_t,
        modelInstances: []const graphics.ModelInstance,
        model: []const graphics.Model,
    ) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render IDs", 0x00_ff_ff_00);
        defer tracy_zone.End();

        const renderArea = gfx.Rect2D{
            .offset = gfx.Offset2D{ .x = 0, .y = 0 },
            .extent = gfx.Extent2D{
                .width = graphics.InputState.viewportX,
                .height = graphics.InputState.viewportY,
            },
        };

        gfx.device.cmdBindPipeline(graphics.Renderer.getCurrentCmdList(), gfx.PipelineBindPoint.graphics, idPipeline);
        gfx.device.cmdSetViewport(graphics.Renderer.getCurrentCmdList(), 0, 1, @ptrCast(&gfx.Viewport{
            .width = @floatFromInt(graphics.InputState.viewportX),
            .height = -@as(f32, @floatFromInt(graphics.InputState.viewportY)),
            .min_depth = 0.0,
            .max_depth = 1.0,
            .x = 0.0,
            .y = @floatFromInt(graphics.InputState.viewportY),
        }));
        gfx.device.cmdSetScissor(graphics.Renderer.getCurrentCmdList(), 0, 1, @ptrCast(&renderArea));

        gfx.device.cmdBindVertexBuffers(graphics.Renderer.getCurrentCmdList(), 0, 1, @ptrCast(&model[0].vertexBuffer.buffer), &[_]u64{0});
        gfx.device.cmdBindIndexBuffer(graphics.Renderer.getCurrentCmdList(), model[0].indexBuffer.buffer, 0, gfx.IndexType.uint32);

        const setsToBind = [_]gfx.DescriptorSet{
            graphics.Renderer.descriptorSet,
        };

        gfx.device.cmdBindDescriptorSets(graphics.Renderer.getCurrentCmdList(), gfx.PipelineBindPoint.graphics, pipelineLayout, 0, setsToBind.len, @ptrCast(&setsToBind), 0, null);

        for (modelInstances, it.entities()) |intance, e| {
            gfx.device.cmdPushConstants(
                graphics.Renderer.getCurrentCmdList(),
                pipelineLayout,
                gfx.ShaderStageFlags{ .fragment_bit = true },
                0,
                2 * @sizeOf(u32),
                @ptrCast(&e),
            );

            gfx.device.cmdBindDescriptorSets(
                graphics.Renderer.getCurrentCmdList(),
                gfx.PipelineBindPoint.graphics,
                pipelineLayout,
                1,
                1,
                @ptrCast(&intance.descriptorSet),
                0,
                null,
            );

            gfx.device.cmdDrawIndexed(
                graphics.Renderer.getCurrentCmdList(),
                @intCast(model[0].mesh.indexData.len),
                1,
                0,
                0,
                0,
            );
        }
    }

    fn stopRenderIDs(_: *flecs.iter_t) void {
        gfx.device.cmdEndRenderPass(graphics.Renderer.getCurrentCmdList());

        gfx.device.cmdPipelineBarrier(
            graphics.Renderer.getCurrentCmdList(),
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
            graphics.Renderer.getCurrentCmdList(),
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
                    .width = graphics.InputState.viewportX,
                    .height = graphics.InputState.viewportY,
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

        gfx.device.cmdPipelineBarrier(
            graphics.Renderer.getCurrentCmdList(),
            gfx.PipelineStageFlags{ .transfer_bit = true },
            gfx.PipelineStageFlags{ .transfer_bit = true },
            gfx.DependencyFlags{},
            0,
            undefined,
            1,
            @ptrCast(&gfx.BufferMemoryBarrier{
                .buffer = readBackBuffer.buffer,
                .offset = 0,
                .size = graphics.InputState.viewportX * graphics.InputState.viewportY * 2 * @sizeOf(u32),
                .src_access_mask = .{ .transfer_write_bit = true },
                .dst_access_mask = .{ .transfer_write_bit = true },
                .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
            }),
            0,
            undefined,
        );
    }

    fn createReadBackData(width: u32, height: u32) !void {
        readBackBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = width * height * 2 * @sizeOf(u32),
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
                .width = width,
                .height = height,
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
                .width = width,
                .height = height,
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
            .width = width,
            .height = height,
            .layers = 1,
        }, null);
    }

    fn destroyReadBackData() void {
        gfx.device.destroyFramebuffer(framebuffer, null);

        gfx.device.destroyImageView(depthImageView, null);
        gfx.device.destroyImageView(writeToImageView, null);

        gfx.destroyImage(gfx.vkAllocator, depthImage);
        gfx.destroyImage(gfx.vkAllocator, writeToImage);
        gfx.destroyBuffer(gfx.vkAllocator, readBackBuffer);
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
