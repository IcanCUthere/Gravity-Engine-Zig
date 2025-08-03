const util = @import("util");
const mem = util.mem;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("../Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;
const Material = @import("Material.zig").Material;
const Texture = @import("Texture.zig").Texture;

pub const Model = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;

    mesh: *const core.io.Mesh = undefined,

    descriptorSet: gfx.DescriptorSet = undefined,
    vertexBuffer: gfx.BufferAllocation = undefined,
    indexBuffer: gfx.BufferAllocation = undefined,

    pub fn setTraits(scene: *flecs.world_t) void {
        _scene = scene;
        flecs.add_pair(
            scene,
            flecs.id(Self),
            flecs.OnInstantiate,
            flecs.Inherit,
        );
    }

    pub fn new(name: [*:0]const u8, path: [:0]const u8, material: flecs.entity_t) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);
        const data = try core.storage.getOrAddMesh(path);

        flecs.add_pair(_scene, newEntt, flecs.IsA, material);
        _ = flecs.set(_scene, newEntt, Texture, try Texture.init(
            &data.baseColor,
        ));

        const matComp = flecs.get(_scene, material, Material).?;
        const texComp = flecs.get(_scene, newEntt, Texture).?;

        _ = flecs.set(_scene, newEntt, Self, try init(&data.mesh, matComp, texComp));

        return newEntt;
    }

    pub fn init(mesh: *const core.io.Mesh, material: *const Material, texture: *const Texture) !Self {
        const tracy_zone = tracy.ZoneNC(@src(), "Init model", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self = Self{
            .mesh = mesh,
        };

        const vertexData = mem.sliceAsBytes(mesh.vertexData);
        const indexData = mem.sliceAsBytes(mesh.indexData);

        self.vertexBuffer = try gfx.createBuffer(
            &gfx.BufferCreateInfo{
                .size = vertexData.len,
                .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{
                    .VertexBufferBit,
                    .TransferDstBit,
                }),
                .sharingMode = gfx.SharingMode.Exclusive,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        self.indexBuffer = try gfx.createBuffer(
            &gfx.BufferCreateInfo{
                .size = indexData.len,
                .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{
                    .IndexBufferBit,
                    .TransferDstBit,
                }),
                .sharingMode = gfx.SharingMode.Exclusive,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        try Renderer.addStagingData(Renderer.StagingData{
            .data = vertexData,
            .dstBuffer = self.vertexBuffer,
            .bufferToBuffer = gfx.BufferCopy{
                .srcOffset = undefined,
                .dstOffset = 0,
                .size = vertexData.len,
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.VertexInputBit}),
                .postBufferBarrier = gfx.BufferMemoryBarrier{
                    .buffer = self.vertexBuffer.buffer,
                    .offset = 0,
                    .size = vertexData.len,
                    .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.MemoryWriteBit}),
                    .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.MemoryReadBit}),
                    .dstQueueFamilyIndex = gfx.queueFamilyIgnored,
                    .srcQueueFamilyIndex = gfx.queueFamilyIgnored,
                },
            },
        });

        try Renderer.addStagingData(Renderer.StagingData{
            .data = indexData,
            .dstBuffer = self.indexBuffer,
            .bufferToBuffer = gfx.BufferCopy{
                .srcOffset = undefined,
                .dstOffset = 0,
                .size = indexData.len,
            },
            .postBarrier = Renderer.PipelineBarrierData{
                .firstUseStages = gfx.toFlags(&[_]gfx.PipelineStageFlagBits{.VertexInputBit}),
                .postBufferBarrier = gfx.BufferMemoryBarrier{
                    .buffer = self.indexBuffer.buffer,
                    .offset = 0,
                    .size = indexData.len,
                    .srcAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.MemoryWriteBit}),
                    .dstAccessMask = gfx.toFlags(&[_]gfx.AccessFlagBits{.MemoryReadBit}),
                    .dstQueueFamilyIndex = gfx.queueFamilyIgnored,
                    .srcQueueFamilyIndex = gfx.queueFamilyIgnored,
                },
            },
        });

        try gfx.AllocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptorPool = material.modelDescriptorPool,
            .pSetLayouts = @ptrCast(&material.modelDescriptorSetLayout),
            .descriptorSetCount = 1,
        }, @ptrCast(&self.descriptorSet));

        try Renderer.addDescriptorUpdate(
            gfx.WriteDescriptorSet{
                .dstSet = self.descriptorSet,
                .dstArrayElement = 0,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = .CombinedImageSampler,
                .pBufferInfo = undefined,
                .pImageInfo = &[_]gfx.DescriptorImageInfo{
                    gfx.DescriptorImageInfo{
                        .imageLayout = .ShaderReadOnlyOptimal,
                        .imageView = texture.imageView,
                        .sampler = texture.sampler,
                    },
                },
                .pTexelBufferView = undefined,
            },
            false,
            true,
        );

        return self;
    }

    pub fn deinit(self: *Self) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit model", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.destroyBuffer(self.vertexBuffer);
        gfx.destroyBuffer(self.indexBuffer);
    }

    pub fn onUpdate(_: *flecs.iter_t) !void {}
};
