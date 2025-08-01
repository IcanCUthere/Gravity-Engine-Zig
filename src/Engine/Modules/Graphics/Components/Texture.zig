const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");

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
        const tracy_zone = tracy.ZoneNC(@src(), "Init texture", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self = Self{
            .baseImage = image,
        };

        self.image = try gfx.createImage(
            gfx.vkAllocator,
            &gfx.ImageCreateInfo{
                .imageType = .@"2d",
                .format = .R8g8b8a8Srgb,
                .extent = .{
                    .width = self.baseImage.width,
                    .height = self.baseImage.height,
                    .depth = 1,
                },
                .mipLevels = 1,
                .arrayLayers = 1,
                .samples = .@"1Bit",
                .tiling = .Optimal,
                .initialLayout = .Undefined,
                .usage = gfx.toFlags(&[_]gfx.ImageUsageFlagBits{ .TransferDstBit, .SampledBit }),
                .sharingMode = .Exclusive,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            },
            &gfx.AllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        self.imageView = try gfx.CreateImageView(
            &gfx.ImageViewCreateInfo{
                .image = self.image.image,
                .viewType = .@"2d",
                .format = .R8g8b8a8Srgb,
                .components = .{
                    .a = .A,
                    .r = .R,
                    .g = .G,
                    .b = .B,
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

        self.sampler = try gfx.CreateSampler(
            &gfx.SamplerCreateInfo{
                .magFilter = .Linear,
                .minFilter = .Linear,
                .mipmapMode = .Linear,
                .addressModeU = .Repeat,
                .addressModeV = .Repeat,
                .addressModeW = .Repeat,
                .anisotropyEnable = gfx.TRUE,
                .maxAnisotropy = 1.0,
                .compareEnable = gfx.TRUE,
                .compareOp = gfx.CompareOp.Always,
                .minLod = 0.0,
                .maxLod = 0.0,
                .mipLodBias = 0.0,
                .borderColor = .FloatOpaqueBlack,
                .unnormalizedCoordinates = gfx.FALSE,
            },
        );

        try Renderer.addStagingData(Renderer.StagingData{
            .dstImage = self.image,
            .data = self.baseImage.data,
            .preImageBarrier = gfx.ImageMemoryBarrier{
                .image = self.image.image,
                .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{}),
                .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.TransferWriteBit}),
                .oldLayout = .Undefined,
                .newLayout = .TransferDstOptimal,
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
            .bufferToImage = gfx.BufferImageCopy{
                .bufferOffset = undefined,
                .bufferImageHeight = undefined,
                .bufferRowLength = undefined,
                .imageOffset = .{
                    .x = 0,
                    .y = 0,
                    .z = 0,
                },
                .imageExtent = .{
                    .width = self.baseImage.width,
                    .height = self.baseImage.height,
                    .depth = 1,
                },
                .imageSubresource = .{
                    .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.ColorBit}),
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                    .mipLevel = 0,
                },
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.FragmentShaderBit}),
                .postImageBarrier = gfx.ImageMemoryBarrier{
                    .image = self.image.image,
                    .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.TransferWriteBit}),
                    .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.ShaderReadBit}),
                    .oldLayout = .TransferDstOptimal,
                    .newLayout = .ShaderReadOnlyOptimal,
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
        });

        return self;
    }

    pub fn deinit(self: *Texture) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit texture", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.DestroySampler(self.sampler);
        try gfx.DestroyImageView(self.imageView);
        gfx.destroyImage(gfx.vkAllocator, self.image);
    }

    pub fn onUpdate(_: *flecs.iter_t) void {}
};
