const flecs = @import("zflecs");
const coreM = @import("CoreModule");

const std = @import("std");
const core = @import("core");

const gfx = @import("Internal/interface.zig");

const Renderer = @import("Renderer.zig").Renderer;

pub const Model = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    var Prefab: flecs.entity_t = undefined;

    baseColor: gfx.ImageAllocation = undefined,
    baseColorView: gfx.ImageView = undefined,
    sampler: gfx.Sampler = undefined,

    modelMatrixUniform: gfx.BufferAllocation = undefined,
    vertexBuffer: gfx.BufferAllocation = undefined,
    indexBuffer: gfx.BufferAllocation = undefined,
    descriptorSet: gfx.DescriptorSet = undefined,

    pub fn register(scene: *flecs.world_t) void {
        _scene = scene;

        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "ModelComponent");
        flecs.add_pair(scene, Prefab, flecs.IsA, coreM.Transform.getPrefab());
        flecs.add(scene, Prefab, Self);
        flecs.add(scene, Prefab, coreM.Mesh);
        flecs.override(scene, Prefab, Self);
        flecs.override(scene, Prefab, coreM.Mesh);

        var setObsDesc = flecs.observer_desc_t{
            .filter = flecs.filter_desc_t{
                .terms = [1]flecs.term_t{
                    flecs.term_t{
                        .id = flecs.id(Self),
                    },
                } ++ ([1]flecs.term_t{.{}} ** 15),
            },
            .events = [_]u64{flecs.OnSet} ++ ([1]u64{0} ** 7),
            .callback = flecs.SystemImpl(onEvent).exec,
        };

        flecs.OBSERVER(scene, "ModelComponentEvent", &setObsDesc);
    }

    fn onEvent(it: *flecs.iter_t, models: []Model) void {
        const event: flecs.entity_t = it.event;

        for (models) |*m| {
            if (event == flecs.OnRemove) {
                m.deinit();
            }
        }
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn new(name: [*:0]const u8, path: [:0]const u8, localPos: core.math.Vec3) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);
        const mesh = try coreM.Mesh.init(path);
        flecs.add_pair(_scene, newEntt, flecs.IsA, getPrefab());
        _ = flecs.set(_scene, newEntt, coreM.Mesh, mesh);
        _ = flecs.set(_scene, newEntt, Self, try init(mesh.data));
        _ = flecs.set(_scene, newEntt, coreM.Transform, coreM.Transform{
            .localPosition = localPos,
            .transformMatrix = core.math.translationV(core.math.vec3ToVec4(localPos)),
        });

        return newEntt;
    }

    pub fn init(mesh: *const coreM.io.Mesh) !Self {
        var self = Self{};

        const vertexData = std.mem.sliceAsBytes(mesh.vertexData);
        const indexData = std.mem.sliceAsBytes(mesh.indexData);

        self.vertexBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = vertexData.len,
                .usage = gfx.BufferUsageFlags{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        self.indexBuffer = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = indexData.len,
                .usage = gfx.BufferUsageFlags{ .index_buffer_bit = true, .transfer_dst_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        self.modelMatrixUniform = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = @sizeOf(core.math.Mat),
                .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = Renderer._descriptorPool,
            .p_set_layouts = @ptrCast(&Renderer.modelDescriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&self.descriptorSet));

        self.baseColor = try gfx.createImage(gfx.vkAllocator, &gfx.ImageCreateInfo{
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

        self.baseColorView = try gfx.device.createImageView(&gfx.ImageViewCreateInfo{
            .image = self.baseColor.image,
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

        self.sampler = try gfx.device.createSampler(&gfx.SamplerCreateInfo{
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

        try Renderer.addDescriptorUpdate(gfx.WriteDescriptorSet{
            .dst_set = self.descriptorSet,
            .dst_array_element = 0,
            .dst_binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_buffer_info = &[_]gfx.DescriptorBufferInfo{
                gfx.DescriptorBufferInfo{
                    .buffer = self.modelMatrixUniform.buffer,
                    .offset = 0,
                    .range = @sizeOf(core.math.Mat),
                },
            },
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        }, true, false);

        try Renderer.addDescriptorUpdate(gfx.WriteDescriptorSet{
            .dst_set = self.descriptorSet,
            .dst_array_element = 0,
            .dst_binding = 1,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_buffer_info = undefined,
            .p_image_info = &[_]gfx.DescriptorImageInfo{
                gfx.DescriptorImageInfo{
                    .image_layout = .shader_read_only_optimal,
                    .image_view = self.baseColorView,
                    .sampler = self.sampler,
                },
            },
            .p_texel_buffer_view = undefined,
        }, false, true);

        try Renderer.addStagingData(Renderer.StagingData{
            .data = vertexData,
            .dstBuffer = self.vertexBuffer,
            .bufferToBuffer = gfx.BufferCopy{
                .src_offset = undefined,
                .dst_offset = 0,
                .size = vertexData.len,
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = gfx.PipelineStageFlags{ .vertex_input_bit = true },
                .postBufferBarrier = gfx.BufferMemoryBarrier{
                    .buffer = self.vertexBuffer.buffer,
                    .offset = 0,
                    .size = vertexData.len,
                    .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                    .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                    .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                    .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                },
            },
        });

        try Renderer.addStagingData(Renderer.StagingData{
            .data = indexData,
            .dstBuffer = self.indexBuffer,
            .bufferToBuffer = gfx.BufferCopy{
                .src_offset = undefined,
                .dst_offset = 0,
                .size = indexData.len,
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = gfx.PipelineStageFlags{ .vertex_input_bit = true },
                .postBufferBarrier = gfx.BufferMemoryBarrier{
                    .buffer = self.indexBuffer.buffer,
                    .offset = 0,
                    .size = indexData.len,
                    .src_access_mask = gfx.AccessFlags{ .memory_write_bit = true },
                    .dst_access_mask = gfx.AccessFlags{ .memory_read_bit = true },
                    .dst_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                    .src_queue_family_index = gfx.QUEUE_FAMILY_IGNORED,
                },
            },
        });

        try Renderer.addStagingData(Renderer.StagingData{
            .dstImage = self.baseColor,
            .data = mesh.material.baseColor.data,
            .preImageBarrier = gfx.ImageMemoryBarrier{
                .image = self.baseColor.image,
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
            .bufferToImage = gfx.BufferImageCopy{
                .buffer_offset = undefined,
                .buffer_image_height = undefined,
                .buffer_row_length = undefined,
                .image_offset = .{ .x = 0, .y = 0, .z = 0 },
                .image_extent = .{ .width = mesh.material.baseColor.width, .height = mesh.material.baseColor.height, .depth = 1 },
                .image_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .mip_level = 0,
                },
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = .{ .fragment_shader_bit = true },
                .postImageBarrier = gfx.ImageMemoryBarrier{
                    .image = self.baseColor.image,
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
        });

        return self;
    }

    pub fn deinit(self: *Self) void {
        gfx.device.destroySampler(self.sampler, null);
        gfx.device.destroyImageView(self.baseColorView, null);
        gfx.destroyImage(gfx.vkAllocator, self.baseColor);
        gfx.destroyBuffer(gfx.vkAllocator, self.modelMatrixUniform);
        gfx.destroyBuffer(gfx.vkAllocator, self.vertexBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, self.indexBuffer);
    }

    pub fn onUpdate(_: *flecs.iter_t, models: []Model, transforms: []coreM.Transform) !void {
        for (models, transforms) |m, t| {
            try Renderer.addStagingData(Renderer.StagingData{
                .data = std.mem.sliceAsBytes(&t.transformMatrix),
                .dstBuffer = m.modelMatrixUniform,
            });
        }
    }
};
