const util = @import("util");
const mem = util.mem;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Model = @import("Model.zig").Model;
const Material = @import("Material.zig").Material;
const Renderer = @import("Renderer.zig").Renderer;

pub const ModelInstance = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    pub var Prefab: flecs.entity_t = undefined;

    descriptorSet: gfx.DescriptorSet = undefined,
    modelMatrixUniform: gfx.BufferAllocation = undefined,

    pub fn setTraits(scene: *flecs.world_t) void {
        _scene = scene;

        flecs.add_pair(
            scene,
            flecs.id(Self),
            flecs.OnInstantiate,
            flecs.Inherit,
        );
    }

    pub fn setPrefab(_: *flecs.world_t) void {}

    pub fn new(name: [*:0]const u8, model: flecs.entity_t, position: util.math.simd.Vec) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);

        flecs.add_pair(_scene, newEntt, flecs.IsA, model);
        _ = flecs.set(_scene, newEntt, core.Transform, core.Transform{
            .localPosition = position,
            .translationMatrix = util.math.simd.translation(position[0], position[1], position[2]),
        });

        _ = flecs.set(_scene, newEntt, Self, try init(model));

        return newEntt;
    }

    pub fn init(model: flecs.entity_t) !Self {
        const tracy_zone = tracy.ZoneNC(@src(), "Init model instance", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self: Self = undefined;

        const matComp = flecs.get(_scene, model, Material).?;

        self.modelMatrixUniform = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = @sizeOf(util.math.simd.Mat),
                .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{.UniformBufferBit}),
                .sharingMode = gfx.SharingMode.Exclusive,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        try gfx.AllocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptorPool = matComp.instanceDescriptorPool,
            .pSetLayouts = @ptrCast(&matComp.instanceDescriptorSetLayout),
            .descriptorSetCount = 1,
        }, @ptrCast(&self.descriptorSet));

        try Renderer.addDescriptorUpdate(
            gfx.WriteDescriptorSet{
                .dstSet = self.descriptorSet,
                .dstArrayElement = 0,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = .UniformBuffer,
                .pBufferInfo = &[_]gfx.DescriptorBufferInfo{
                    gfx.DescriptorBufferInfo{
                        .buffer = self.modelMatrixUniform.buffer,
                        .offset = 0,
                        .range = @sizeOf(util.math.simd.Mat),
                    },
                },
                .pImageInfo = undefined,
                .pTexelBufferView = undefined,
            },
            true,
            false,
        );

        return self;
    }

    pub fn deinit(self: *Self) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit model instance", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.destroyBuffer(gfx.vkAllocator, self.modelMatrixUniform);
    }

    pub fn onUpdate(_: *flecs.iter_t, models: []ModelInstance, transforms: []core.Transform) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Update model instances", 0x00_ff_ff_00);
        defer tracy_zone.End();

        //TODO: make more performant, no need to update every frame
        for (models, transforms) |m, *t| {
            t.translationMatrix = util.math.simd.translation(
                t.localPosition[0],
                t.localPosition[1],
                t.localPosition[2],
            );

            try Renderer.addStagingData(Renderer.StagingData{
                .data = &mem.toBytes(t.translationMatrix),
                .dstBuffer = m.modelMatrixUniform,
            });
        }
    }
};
