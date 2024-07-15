const flecs = @import("zflecs");
const core = @import("core");
const coreM = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;

const std = @import("std");

pub const Camera = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    projectionMatrix: core.math.Mat = core.math.identity(),

    cameraMatricesUniform: gfx.BufferAllocation = undefined,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "CameraPrefab");
        flecs.add_pair(scene, Prefab, flecs.IsA, coreM.Transform.getPrefab());
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn init(FOWinDeg: f32, aspectRatio: f32, near: f32, far: f32) !Self {
        var self: Self = undefined;
        self.setProjectionMatrix(FOWinDeg, aspectRatio, near, far);

        self.cameraMatricesUniform = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = 2 * @sizeOf(core.math.Mat),
                .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        //try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
        //    .descriptor_pool = Renderer.globalDescriptorPool,
        //    .p_set_layouts = @ptrCast(&Renderer.globalDescriptorSetLayout),
        //    .descriptor_set_count = 1,
        //}, @ptrCast(&Renderer.descriptorSet));

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
                    .range = 2 * @sizeOf(core.math.Mat),
                },
            },
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        }, true, false);

        return self;
    }

    pub fn deinit(self: *Self) void {
        gfx.destroyBuffer(gfx.vkAllocator, self.cameraMatricesUniform);
    }

    pub fn onUpdate(_: *flecs.iter_t, cameras: []Camera, transforms: []coreM.Transform) !void {
        for (cameras, transforms) |c, t| {
            const transformMatrix = core.math.mul(t.translationMatrix, t.rotationMatrix);
            const data = std.mem.toBytes(transformMatrix) ++ std.mem.toBytes(c.projectionMatrix);

            try Renderer.addStagingData(Renderer.StagingData{
                .data = &data,
                .dstBuffer = c.cameraMatricesUniform,
            });
        }
    }

    pub fn setProjectionMatrix(self: *Self, FOWinDeg: f32, aspectRatio: f32, near: f32, far: f32) void {
        self.projectionMatrix = core.math.perspectiveFovRh(std.math.degreesToRadians(FOWinDeg), aspectRatio, near, far);
    }
};
