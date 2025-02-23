const util = @import("util");
const mem = util.mem;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;
const Material = @import("Material.zig").Material;
const Texture = @import("Texture.zig").Texture;

pub const Model = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    var Prefab: flecs.entity_t = undefined;

    mesh: *const core.io.Mesh = undefined,

    descriptorSet: gfx.DescriptorSet = undefined,
    vertexBuffer: gfx.BufferAllocation = undefined,
    indexBuffer: gfx.BufferAllocation = undefined,

    pub fn register(scene: *flecs.world_t) void {
        _scene = scene;

        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "ModelPrefab");
        flecs.add_pair(scene, Prefab, flecs.IsA, core.Transform.getPrefab());
        flecs.add(scene, Prefab, Self);
        flecs.add(scene, Prefab, Texture);

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

    pub fn new(name: [*:0]const u8, path: [:0]const u8, material: flecs.entity_t) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);
        const data = try core.storage.getOrAddMesh(path);

        flecs.add_pair(_scene, newEntt, flecs.IsA, getPrefab());
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

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = material.modelDescriptorPool,
            .p_set_layouts = @ptrCast(&material.modelDescriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&self.descriptorSet));

        try Renderer.addDescriptorUpdate(gfx.WriteDescriptorSet{
            .dst_set = self.descriptorSet,
            .dst_array_element = 0,
            .dst_binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_buffer_info = undefined,
            .p_image_info = &[_]gfx.DescriptorImageInfo{
                gfx.DescriptorImageInfo{
                    .image_layout = .shader_read_only_optimal,
                    .image_view = texture.imageView,
                    .sampler = texture.sampler,
                },
            },
            .p_texel_buffer_view = undefined,
        }, false, true);

        return self;
    }

    pub fn deinit(self: *Self) void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit model", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.destroyBuffer(gfx.vkAllocator, self.vertexBuffer);
        gfx.destroyBuffer(gfx.vkAllocator, self.indexBuffer);
    }

    pub fn onUpdate(_: *flecs.iter_t) !void {}
};
