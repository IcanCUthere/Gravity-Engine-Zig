const util = @import("util");
const mem = util.mem;
const math = util.math;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;

pub const Camera = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    projectionMatrix: util.math.Mat = util.math.identity(),

    cameraMatricesUniform: gfx.BufferAllocation = undefined,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "CameraPrefab");
        flecs.add_pair(scene, Prefab, flecs.IsA, core.Transform.getPrefab());
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn init(FOWinDeg: f32, aspectRatio: f32, near: f32, far: f32) !Self {
        const tracy_zone = tracy.ZoneNC(@src(), "Init camera", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self: Self = undefined;
        self.setProjectionMatrix(FOWinDeg, aspectRatio, near, far);

        self.cameraMatricesUniform = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = 2 * @sizeOf(util.math.Mat) + @sizeOf(util.math.Vec),
                .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        try Renderer.addDescriptorUpdate(gfx.WriteDescriptorSet{
            .dst_set = Renderer.descriptorSet,
            .dst_array_element = 0,
            .dst_binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_buffer_info = &[_]gfx.DescriptorBufferInfo{
                gfx.DescriptorBufferInfo{
                    .buffer = self.cameraMatricesUniform.buffer,
                    .offset = 0,
                    .range = 2 * @sizeOf(util.math.Mat) + @sizeOf(util.math.Vec),
                },
            },
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        }, true, false);

        return self;
    }

    pub fn deinit(self: *Self) void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit camera", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.destroyBuffer(gfx.vkAllocator, self.cameraMatricesUniform);
    }

    pub fn onUpdate(_: *flecs.iter_t, cameras: []Camera, transforms: []core.Transform) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Update cameras", 0x00_ff_ff_00);
        defer tracy_zone.End();

        for (cameras, transforms) |c, t| {
            const transformMatrix = util.math.mulV(t.translationMatrix, t.rotationMatrix);
            const data = mem.toBytes(transformMatrix) ++ mem.toBytes(c.projectionMatrix) ++ mem.toBytes(t.localPosition);

            try Renderer.addStagingData(Renderer.StagingData{
                .data = &data,
                .dstBuffer = c.cameraMatricesUniform,
            });
        }
    }

    pub fn setProjectionMatrix(self: *Self, FOWinDeg: f32, aspectRatio: f32, near: f32, far: f32) void {
        self.projectionMatrix = util.math.perspectiveFovRh(math.degreesToRadians(FOWinDeg), aspectRatio, near, far);
    }
};
