const flecs = @import("zflecs");
const stbi = @import("zstbi");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;
const Material = @import("Material.zig").Material;
const Model = @import("Model.zig").Model;

pub const Texture = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    var Prefab: flecs.entity_t = undefined;

    baseImage: *const core.io.Image = undefined,

    image: gfx.ImageAllocation = undefined,
    imageView: gfx.ImageView = undefined,
    sampler: gfx.Sampler = undefined,

    pub fn register(scene: *flecs.world_t) void {
        _scene = scene;

        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "TexturePrefab");
        flecs.add(scene, Prefab, Self);
        flecs.override(scene, Prefab, Self);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn new(name: [*:0]const u8, image: *const core.io.Image) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);
        _ = flecs.set(_scene, newEntt, Self, try init(image));

        return newEntt;
    }

    pub fn init(image: *const core.io.Image) !Texture {
        var self = Self{
            .baseImage = image,
        };

        self.image = try gfx.createImage(gfx.vkAllocator, &gfx.ImageCreateInfo{
            .image_type = .@"2d",
            .format = .r8g8b8a8_srgb,
            .extent = .{
                .width = self.baseImage.width,
                .height = self.baseImage.height,
                .depth = 1,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{
                .@"1_bit" = true,
            },
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = .{
                .transfer_dst_bit = true,
                .sampled_bit = true,
            },
            .sharing_mode = .exclusive,
        }, &gfx.AllocationCreateInfo{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        });

        self.imageView = try gfx.device.createImageView(&gfx.ImageViewCreateInfo{
            .image = self.image.image,
            .view_type = .@"2d",
            .format = .r8g8b8a8_srgb,
            .components = .{
                .a = .a,
                .r = .r,
                .g = .g,
                .b = .b,
            },
            .subresource_range = gfx.ImageSubresourceRange{
                .aspect_mask = .{
                    .color_bit = true,
                },
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

        try Renderer.addStagingData(Renderer.StagingData{
            .dstImage = self.image,
            .data = self.baseImage.data,
            .preImageBarrier = gfx.ImageMemoryBarrier{
                .image = self.image.image,
                .src_access_mask = .{},
                .dst_access_mask = .{
                    .transfer_write_bit = true,
                },
                .old_layout = .undefined,
                .new_layout = .transfer_dst_optimal,
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
            },
            .bufferToImage = gfx.BufferImageCopy{
                .buffer_offset = undefined,
                .buffer_image_height = undefined,
                .buffer_row_length = undefined,
                .image_offset = .{
                    .x = 0,
                    .y = 0,
                    .z = 0,
                },
                .image_extent = .{
                    .width = self.baseImage.width,
                    .height = self.baseImage.height,
                    .depth = 1,
                },
                .image_subresource = .{
                    .aspect_mask = .{
                        .color_bit = true,
                    },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .mip_level = 0,
                },
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = .{
                    .fragment_shader_bit = true,
                },
                .postImageBarrier = gfx.ImageMemoryBarrier{
                    .image = self.image.image,
                    .src_access_mask = .{
                        .transfer_write_bit = true,
                    },
                    .dst_access_mask = .{
                        .shader_read_bit = true,
                    },
                    .old_layout = .transfer_dst_optimal,
                    .new_layout = .shader_read_only_optimal,
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
                },
            },
        });

        return self;
    }

    pub fn deinit(self: *Texture) void {
        gfx.device.destroySampler(self.sampler, null);
        gfx.device.destroyImageView(self.imageView, null);
        gfx.destroyImage(gfx.vkAllocator, self.image);
    }

    pub fn onUpdate(_: *flecs.iter_t) void {}
};
