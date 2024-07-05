const core = @import("core");
const std = @import("std");
const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");

const gfx = @import("Components/Internal/interface.zig");
const evnt = @import("Components/Internal/event.zig");

const shaders = @import("shaders");

const coreM = @import("CoreModule");

pub const InputSingleton = @import("Components/Input.zig").InputSingleton;
pub const Camera = @import("Components/Camera.zig").Camera;
pub const Viewport = @import("Components/Viewport.zig").Viewport;

pub const Graphics = struct {
    pub const name: []const u8 = "graphics";
    pub const dependencies = [_][]const u8{"core"};

    var _scene: *flecs.world_t = undefined;

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        try gfx.init();
        stbi.init(core.mem.ha);

        InputSingleton.register(scene);
        Viewport.register(scene);
        Camera.register(scene);

        mainCamera = flecs.new_entity(scene, "Main Camera");
        flecs.add_pair(scene, mainCamera, flecs.IsA, Camera.getPrefab());

        var viewport = try Viewport.init(
            "Gravity Control",
            @intFromFloat(1000),
            @intFromFloat(1000),
            3,
            1,
            onEvent,
        );
        viewport.setCursorEnabled(false);

        _renderPass = try gfx.createRenderPass(viewport.getFormat());

        viewport.setRenderPass(_renderPass);

        mainViewport = flecs.new_entity(scene, "Main Viewport");
        flecs.add_pair(scene, mainViewport, flecs.IsA, Viewport.getPrefab());
        _ = flecs.set(scene, mainViewport, Viewport, viewport);

        var desc = flecs.system_desc_t{};
        desc.callback = flecs.SystemImpl(render).exec;
        desc.query.filter.terms[0] = flecs.term_t{
            .id = flecs.id(coreM.Mesh),
            .inout = .In,
        };
        desc.query.filter.terms[1] = flecs.term_t{
            .id = flecs.id(coreM.Transform),
            .inout = .In,
        };
        desc.query.filter.terms[2] = flecs.term_t{
            .id = flecs.id(Camera),
            .inout = .In,
            .src = flecs.term_id_t{
                .id = mainCamera,
            },
        };
        desc.query.filter.terms[3] = flecs.term_t{
            .id = flecs.id(coreM.Transform),
            .inout = .In,
            .src = flecs.term_id_t{
                .id = mainCamera,
            },
        };
        desc.query.filter.terms[4] = flecs.term_t{
            .id = flecs.id(Viewport),
            .inout = .In,
            .src = flecs.term_id_t{
                .id = mainViewport,
            },
        };
        desc.query.filter.instanced = true;

        var desc2 = flecs.system_desc_t{};
        desc2.callback = flecs.SystemImpl(updateFOW).exec;
        desc2.query.filter.terms[0] = flecs.term_t{
            .id = flecs.id(Camera),
            .inout = .InOut,
            .src = flecs.term_id_t{
                .id = mainCamera,
            },
        };
        desc2.query.filter.terms[1] = flecs.term_t{
            .id = flecs.id(Viewport),
            .inout = .InOut,
            .src = flecs.term_id_t{
                .id = mainViewport,
            },
        };
        desc2.query.filter.terms[2] = flecs.term_t{
            .id = flecs.id(InputSingleton),
            .inout = .In,
        };

        desc2.query.filter.instanced = true;

        flecs.ADD_SYSTEM(scene, "Upload Events", flecs.OnLoad, uploadEvents);
        flecs.ADD_SYSTEM(scene, "Clear Events", flecs.OnStore, clearEvents);
        flecs.SYSTEM(scene, "Render", flecs.OnStore, &desc);
        flecs.SYSTEM(scene, "Update FOV", flecs.PostLoad, &desc2);

        BufferedEventData.mouseX = viewport.getMousePosition()[0];
        BufferedEventData.mouseY = viewport.getMousePosition()[1];
        BufferedEventData.windowSizeX = viewport.getWidth();
        BufferedEventData.windowSizeY = viewport.getHeight();

        try initRenderer();
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try deinitRenderer();

        flecs.delete(_scene, mainViewport);
        flecs.delete(_scene, mainCamera);

        stbi.deinit();
        gfx.deinit();
    }

    const BufferedEventData = struct {
        var deltaMouseX: f64 = 0;
        var deltaMouseY: f64 = 0;

        var mouseX: f64 = 0;
        var mouseY: f64 = 0;

        var keyStates: [400]evnt.KeyState = [1]evnt.KeyState{.{}} ** 400;

        var deltaWindowSizeX: i32 = 0;
        var deltaWindowSizeY: i32 = 0;

        var windowSizeX: u32 = 0;
        var windowSizeY: u32 = 0;
    };

    fn updateFOW(_: *flecs.iter_t, cameras: []Camera, viewports: []Viewport, input: []InputSingleton) void {
        if (input[0].deltaViewportX != 0 or input[0].deltaViewportY != 0) {
            const aspectRatio = @as(f32, @floatFromInt(input[0].viewportX)) / @as(f32, @floatFromInt(input[0].viewportY));
            cameras[0].setProjectionMatrix(45.0, aspectRatio, 1.0, 10000.0);
            viewports[0].resize(input[0].viewportX, input[0].viewportY);
        }
    }

    fn uploadEvents(_: *flecs.iter_t, input: []InputSingleton) !void {
        //calls onEvent
        Viewport.pollEvents();

        input[0].deltaMouseX = BufferedEventData.deltaMouseX;
        input[0].deltaMouseY = BufferedEventData.deltaMouseY;

        input[0].mouseX = BufferedEventData.mouseX;
        input[0].mouseY = BufferedEventData.mouseY;

        input[0].keyStates = BufferedEventData.keyStates;

        input[0].viewportX = BufferedEventData.windowSizeX;
        input[0].viewportY = BufferedEventData.windowSizeY;

        input[0].deltaViewportX = BufferedEventData.deltaWindowSizeX;
        input[0].deltaViewportY = BufferedEventData.deltaWindowSizeY;
    }

    fn clearEvents(_: *flecs.iter_t, input: []InputSingleton) void {
        BufferedEventData.deltaMouseX = 0;
        BufferedEventData.deltaMouseY = 0;

        BufferedEventData.deltaWindowSizeX = 0;
        BufferedEventData.deltaWindowSizeY = 0;

        for (&BufferedEventData.keyStates) |*s| {
            s.isPress = false;
            s.isRelease = false;
            s.isRepeat = false;
        }

        input[0].deltaMouseX = 0;
        input[0].deltaMouseY = 0;

        for (&input[0].keyStates) |*s| {
            s.isPress = false;
            s.isRelease = false;
            s.isRepeat = false;
        }
    }

    fn onEvent(e: evnt.Event) void {
        switch (e) {
            .windowResize => |wre| onWindowResize(wre),
            .windowClose => |wce| onWindowClose(wce),
            .key => |ke| onKey(ke),
            .mousePosition => |mpe| onMousePosition(mpe),
        }
    }

    fn onWindowResize(e: evnt.WindowResizeEvent) void {
        BufferedEventData.deltaWindowSizeX = @as(i32, @intCast(e.width)) - @as(i32, @intCast(BufferedEventData.windowSizeX));
        BufferedEventData.deltaWindowSizeY = @as(i32, @intCast(e.height)) - @as(i32, @intCast(BufferedEventData.windowSizeY));

        BufferedEventData.windowSizeX = e.width;
        BufferedEventData.windowSizeY = e.height;
    }

    fn onWindowClose(_: evnt.WindowCloseEvent) void {
        flecs.quit(_scene);
    }

    fn onKey(e: evnt.KeyEvent) void {
        if (e.action == .Pressed) {
            BufferedEventData.keyStates[@intFromEnum(e.key)].isPress = true;
            BufferedEventData.keyStates[@intFromEnum(e.key)].isHold = true;
        } else if (e.action == .Released) {
            BufferedEventData.keyStates[@intFromEnum(e.key)].isHold = false;
            BufferedEventData.keyStates[@intFromEnum(e.key)].isPress = false;
            BufferedEventData.keyStates[@intFromEnum(e.key)].isRelease = true;
        } else if (e.action == .Repeated) {
            BufferedEventData.keyStates[@intFromEnum(e.key)].isRepeat = true;
        }
    }

    fn onMousePosition(e: evnt.MousePositionEvent) void {
        BufferedEventData.deltaMouseX = e.x - BufferedEventData.mouseX;
        BufferedEventData.deltaMouseY = e.y - BufferedEventData.mouseY;

        BufferedEventData.mouseX = e.x;
        BufferedEventData.mouseY = e.y;
    }

    const BufferedImages = 3;
    var _renderPass: gfx.RenderPass = undefined;
    var _cmdPools: []gfx.CommandPool = undefined;
    var _cmdLists: []gfx.CommandBuffer = undefined;
    var _semaphores: []gfx.Semaphore = undefined;
    var _vertexModule: gfx.ShaderModule = undefined;
    var _fragmentModule: gfx.ShaderModule = undefined;
    var _descriptorSetLayout: gfx.DescriptorSetLayout = undefined;
    var _pipelineLayout: gfx.PipelineLayout = undefined;
    var _pipeline: gfx.Pipeline = undefined;
    var _stagingBuffer: gfx.BufferAllocation = undefined;
    var _vertexBuffer: gfx.BufferAllocation = undefined;
    var _indexBuffer: gfx.BufferAllocation = undefined;
    var _uniformBuffer: gfx.BufferAllocation = undefined;
    var _descriptorPool: gfx.DescriptorPool = undefined;
    var _descriptorSet: gfx.DescriptorSet = undefined;
    var _image: gfx.ImageAllocation = undefined;
    var _imageView: gfx.ImageView = undefined;
    var _sampler: gfx.Sampler = undefined;
    var imageIndex: u32 = 0;
    var _timelineSemaphore: gfx.Semaphore = undefined;
    var _semaphoreValue: u64 = 1;

    pub var mainCamera: flecs.entity_t = undefined;
    pub var mainViewport: flecs.entity_t = undefined;

    fn initRenderer() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Init Renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var mesh = try coreM.io.loadMeshFromFile("resources/DamagedHelmet.glb");
        defer mesh.deinit();

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

        _stagingBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = (mesh.vertexData.len * @sizeOf(coreM.io.Vertex)) + (mesh.indexData.len * @sizeOf(u32)) + (mesh.material.baseColor.width * mesh.material.baseColor.height * 4),
                .usage = gfx.BufferUsageFlags{ .transfer_src_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
            },
        );

        _vertexBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = mesh.vertexData.len * @sizeOf(coreM.io.Vertex),
                .usage = gfx.BufferUsageFlags{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        _indexBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = mesh.indexData.len * @sizeOf(u32),
                .usage = gfx.BufferUsageFlags{ .index_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        _uniformBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = 3 * @sizeOf(core.math.Mat),
                .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        _image = try gfx.createImage(gfx.vkAllocator, &gfx.ImageCreateInfo{
            .image_type = .@"2d",
            .format = .r8g8b8a8_srgb,
            .extent = .{ .width = mesh.material.baseColor.width, .height = mesh.material.baseColor.height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = .{ .transfer_dst_bit = true, .sampled_bit = true },
            .sharing_mode = .exclusive,
        }, &gfx.AllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        });

        _imageView = try gfx.device.createImageView(&gfx.ImageViewCreateInfo{
            .image = _image.image,
            .view_type = .@"2d",
            .format = .r8g8b8a8_srgb,
            .components = .{ .a = .a, .r = .r, .g = .g, .b = .b },
            .subresource_range = gfx.ImageSubresourceRange{
                .aspect_mask = .{ .color_bit = true },
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
        }, null);

        _sampler = try gfx.device.createSampler(&gfx.SamplerCreateInfo{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_mode = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = gfx.TRUE,
            .max_anisotropy = 1.0,
            .compare_enable = gfx.TRUE,
            .compare_op = gfx.CompareOp.always,
            .min_lod = 0.0,
            .max_lod = 0.0,
            .mip_lod_bias = 0.0,
            .border_color = .float_opaque_black,
            .unnormalized_coordinates = gfx.FALSE,
        }, null);

        const data = [_][]const u8{
            std.mem.sliceAsBytes(mesh.vertexData[0..]),
            std.mem.sliceAsBytes(mesh.indexData[0..]),
            mesh.material.baseColor.data[0..],
        };

        _ = try gfx.uploadMemory(gfx.vkAllocator, _stagingBuffer, data[0..], 0);

        _vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = shaders.shader_vert.len,
            .p_code = @ptrCast(&shaders.shader_vert),
        }, null);

        _fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
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
            gfx.DescriptorSetLayoutBinding{
                .binding = 1,
                .descriptor_type = gfx.DescriptorType.combined_image_sampler,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .fragment_bit = true },
            },
        };

        _descriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &descriptorBindings,
            .binding_count = @intCast(descriptorBindings.len),
        }, null);

        _pipelineLayout = try gfx.device.createPipelineLayout(&gfx.PipelineLayoutCreateInfo{
            .p_set_layouts = @ptrCast(&_descriptorSetLayout),
            .set_layout_count = 1,
            .p_push_constant_ranges = null,
            .push_constant_range_count = 0,
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

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = _descriptorPool,
            .p_set_layouts = @ptrCast(&_descriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&_descriptorSet));

        gfx.device.updateDescriptorSets(2, &[_]gfx.WriteDescriptorSet{
            gfx.WriteDescriptorSet{
                .dst_set = _descriptorSet,
                .dst_array_element = 0,
                .dst_binding = 0,
                .descriptor_count = 1,
                .descriptor_type = .uniform_buffer,
                .p_buffer_info = &[_]gfx.DescriptorBufferInfo{
                    gfx.DescriptorBufferInfo{
                        .buffer = _uniformBuffer.buffer,
                        .offset = 0,
                        .range = 3 * @sizeOf(core.math.Mat),
                    },
                },
                .p_image_info = @ptrFromInt(32),
                .p_texel_buffer_view = @ptrFromInt(32),
            },
            gfx.WriteDescriptorSet{
                .dst_set = _descriptorSet,
                .dst_array_element = 0,
                .dst_binding = 1,
                .descriptor_count = 1,
                .descriptor_type = .combined_image_sampler,
                .p_buffer_info = @ptrFromInt(32),
                .p_image_info = &[_]gfx.DescriptorImageInfo{
                    gfx.DescriptorImageInfo{
                        .image_layout = .shader_read_only_optimal,
                        .image_view = _imageView,
                        .sampler = _sampler,
                    },
                },
                .p_texel_buffer_view = @ptrFromInt(32),
            },
        }, 0, null);

        _pipeline = try gfx.createPipeline(_pipelineLayout, _renderPass, _vertexModule, _fragmentModule, 100, 100);

        try gfx.device.beginCommandBuffer(_cmdLists[0], &gfx.CommandBufferBeginInfo{
            .flags = gfx.CommandBufferUsageFlags{ .one_time_submit_bit = true },
            .p_inheritance_info = null,
        });

        gfx.device.cmdPipelineBarrier(
            _cmdLists[0],
            .{ .top_of_pipe_bit = true },
            .{ .transfer_bit = true },
            .{},
            0,
            null,
            0,
            null,
            1,
            &[_]gfx.ImageMemoryBarrier{
                gfx.ImageMemoryBarrier{
                    .image = _image.image,
                    .src_access_mask = .{},
                    .dst_access_mask = .{ .transfer_write_bit = true },
                    .old_layout = .undefined,
                    .new_layout = .transfer_dst_optimal,
                    .subresource_range = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_array_layer = 0,
                        .layer_count = 1,
                        .base_mip_level = 0,
                        .level_count = 1,
                    },
                    .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                    .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                },
            },
        );

        gfx.device.cmdCopyBuffer(
            _cmdLists[0],
            _stagingBuffer.buffer,
            _vertexBuffer.buffer,
            1,
            &[_]gfx.BufferCopy{
                gfx.BufferCopy{
                    .src_offset = 0,
                    .dst_offset = 0,
                    .size = mesh.vertexData.len * @sizeOf(coreM.io.Vertex),
                },
            },
        );

        gfx.device.cmdCopyBuffer(
            _cmdLists[0],
            _stagingBuffer.buffer,
            _indexBuffer.buffer,
            1,
            &[_]gfx.BufferCopy{
                gfx.BufferCopy{
                    .src_offset = mesh.vertexData.len * @sizeOf(coreM.io.Vertex),
                    .dst_offset = 0,
                    .size = mesh.indexData.len * @sizeOf(u32),
                },
            },
        );

        gfx.device.cmdCopyBufferToImage(
            _cmdLists[0],
            _stagingBuffer.buffer,
            _image.image,
            gfx.ImageLayout.transfer_dst_optimal,
            1,
            &[_]gfx.BufferImageCopy{
                gfx.BufferImageCopy{
                    .buffer_offset = mesh.vertexData.len * @sizeOf(coreM.io.Vertex) + mesh.indexData.len * @sizeOf(u32),
                    .buffer_image_height = 0,
                    .buffer_row_length = 0,
                    .image_offset = .{ .x = 0, .y = 0, .z = 0 },
                    .image_extent = .{ .width = mesh.material.baseColor.width, .height = mesh.material.baseColor.height, .depth = 1 },
                    .image_subresource = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_array_layer = 0,
                        .layer_count = 1,
                        .mip_level = 0,
                    },
                },
            },
        );

        gfx.device.cmdPipelineBarrier(
            _cmdLists[0],
            .{ .transfer_bit = true },
            .{ .fragment_shader_bit = true },
            .{},
            0,
            null,
            0,
            null,
            1,
            &[_]gfx.ImageMemoryBarrier{
                gfx.ImageMemoryBarrier{
                    .image = _image.image,
                    .src_access_mask = .{ .transfer_write_bit = true },
                    .dst_access_mask = .{ .shader_read_bit = true },
                    .old_layout = .transfer_dst_optimal,
                    .new_layout = .shader_read_only_optimal,
                    .subresource_range = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_array_layer = 0,
                        .layer_count = 1,
                        .base_mip_level = 0,
                        .level_count = 1,
                    },
                    .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                    .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                },
            },
        );

        try gfx.device.endCommandBuffer(_cmdLists[0]);

        try gfx.device.queueSubmit(gfx.renderQueue, 1, &[_]gfx.SubmitInfo{
            gfx.SubmitInfo{
                .p_next = &gfx.TimelineSemaphoreSubmitInfo{
                    .p_signal_semaphore_values = &[_]u64{1},
                    .signal_semaphore_value_count = 1,
                    .p_wait_semaphore_values = null,
                    .wait_semaphore_value_count = 0,
                },
                .p_command_buffers = &[_]gfx.CommandBuffer{_cmdLists[0]},
                .command_buffer_count = 1,
                .p_wait_dst_stage_mask = &[_]gfx.PipelineStageFlags{.{ .transfer_bit = true }},
                .p_signal_semaphores = &[_]gfx.Semaphore{_timelineSemaphore},
                .signal_semaphore_count = 1,
                .p_wait_semaphores = null,
                .wait_semaphore_count = 0,
            },
        }, gfx.Fence.null_handle);
    }

    fn deinitRenderer() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit renderer", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _ = try gfx.device.waitSemaphores(&gfx.SemaphoreWaitInfo{
            .p_semaphores = @ptrCast(&_timelineSemaphore),
            .p_values = @ptrCast(&_semaphoreValue),
            .semaphore_count = 1,
        }, ~@as(u64, 0));

        gfx.device.destroySemaphore(_timelineSemaphore, null);

        gfx.device.destroyDescriptorPool(_descriptorPool, null);

        gfx.destroyBuffer(gfx.vkAllocator, _uniformBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, _indexBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, _vertexBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, _stagingBuffer);

        gfx.device.destroyPipeline(_pipeline, null);
        gfx.device.destroyPipelineLayout(_pipelineLayout, null);
        gfx.device.destroyDescriptorSetLayout(_descriptorSetLayout, null);
        gfx.device.destroyShaderModule(_fragmentModule, null);
        gfx.device.destroyShaderModule(_vertexModule, null);

        gfx.device.destroySampler(_sampler, null);
        gfx.device.destroyImageView(_imageView, null);
        gfx.destroyImage(gfx.vkAllocator, _image);

        for (_cmdPools, _semaphores) |pool, sem| {
            gfx.device.destroySemaphore(sem, null);
            gfx.device.destroyCommandPool(pool, null);
        }

        core.mem.ha.free(_semaphores);
        core.mem.ha.free(_cmdLists);
        core.mem.ha.free(_cmdPools);
        gfx.device.destroyRenderPass(_renderPass, null);
    }

    fn render(_: *flecs.iter_t, models: []coreM.Mesh, transforms: []coreM.Transform, camera: []Camera, camTransform: []coreM.Transform, viewport: []Viewport) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try viewport[0].nextFrame(_semaphores[imageIndex]);

        const waitValue: u64 = if (1 > _semaphoreValue - 1) 1 else _semaphoreValue - 1;
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

        for (models, transforms) |m, t| {
            const modelMatrix = t.transformMatrix; //flecs.get(scene, meshInst, component.Transform).?.transformMatrix;
            const camTranslation = camTransform[0].transformMatrix; //flecs.get(scene, cam, component.Transform).?.transformMatrix;
            const camProjection = camera[0].projectionMatrix; //flecs.get(scene, cam, component.Camera).?.projectionMatrix;

            const data = [_][]const u8{
                std.mem.sliceAsBytes(modelMatrix[0..]),
                std.mem.sliceAsBytes(camTranslation[0..]),
                std.mem.sliceAsBytes(camProjection[0..]),
            };

            _ = try gfx.uploadMemory(gfx.vkAllocator, _uniformBuffer, data[0..], 0);

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

            const barriers = [_]gfx.BufferMemoryBarrier{
                gfx.BufferMemoryBarrier{
                    .buffer = _vertexBuffer.buffer,
                    .offset = 0,
                    .size = m.mesh.vertexData.len * @sizeOf(coreM.io.Vertex),
                    .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                    .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                    .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                    .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                },
                gfx.BufferMemoryBarrier{
                    .buffer = _indexBuffer.buffer,
                    .offset = 0,
                    .size = m.mesh.indexData.len * @sizeOf(u32),
                    .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                    .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                    .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                    .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                },
            };

            gfx.device.cmdPipelineBarrier(
                _cmdLists[imageIndex],
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
            gfx.device.cmdBindVertexBuffers(_cmdLists[imageIndex], 0, 1, @ptrCast(&_vertexBuffer.buffer), &[_]u64{0});
            gfx.device.cmdBindIndexBuffer(_cmdLists[imageIndex], _indexBuffer.buffer, 0, gfx.IndexType.uint32);
            gfx.device.cmdBindDescriptorSets(_cmdLists[imageIndex], gfx.PipelineBindPoint.graphics, _pipelineLayout, 0, 1, @ptrCast(&_descriptorSet), 0, null);
            gfx.device.cmdDrawIndexed(_cmdLists[imageIndex], @intCast(m.mesh.indexData.len), 1, 0, 0, 0);
            gfx.device.cmdEndRenderPass(_cmdLists[imageIndex]);
        }

        try gfx.device.endCommandBuffer(_cmdLists[imageIndex]);

        //const submitZone = tracy.ZoneNC(@src(), "Submit", 0x00_ff_ff_00);

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

        //submitZone.End();
    }
};
