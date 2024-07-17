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
    var Prefab: flecs.entity_t = undefined;

    descriptorSet: gfx.DescriptorSet = undefined,
    modelMatrixUniform: gfx.BufferAllocation = undefined,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        _scene = scene;
    }

    pub fn new(name: [*:0]const u8, model: flecs.entity_t, position: util.math.Vec) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);

        flecs.add_pair(_scene, newEntt, flecs.IsA, model);
        _ = flecs.set(_scene, newEntt, core.Transform, core.Transform{
            .localPosition = position,
            .translationMatrix = util.math.translation(position[0], position[1], position[2]),
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
                .size = @sizeOf(util.math.Mat),
                .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = matComp.instanceDescriptorPool,
            .p_set_layouts = @ptrCast(&matComp.instanceDescriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&self.descriptorSet));

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
                    .range = @sizeOf(util.math.Mat),
                },
            },
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        }, true, false);

        return self;
    }

    pub fn deinit(self: *Self) void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit model instance", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.destroyBuffer(gfx.vkAllocator, self.modelMatrixUniform);
    }

    pub fn onUpdate(_: *flecs.iter_t, models: []ModelInstance, transforms: []core.Transform) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Update model instances", 0x00_ff_ff_00);
        defer tracy_zone.End();

        for (models, transforms) |m, t| {
            try Renderer.addStagingData(Renderer.StagingData{
                .data = &mem.toBytes(t.translationMatrix),
                .dstBuffer = m.modelMatrixUniform,
            });
        }
    }
};
