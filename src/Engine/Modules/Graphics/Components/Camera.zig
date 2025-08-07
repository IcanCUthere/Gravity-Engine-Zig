const util = @import("util");
const mem = util.mem;
const math = util.math;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("../Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;

pub const Camera = struct {
    const Self = @This();

    projectionMatrix: util.math.simd.Mat = util.math.simd.identity(),
    cameraMatricesUniform: gfx.BufferAllocation = undefined,

    pub fn setTraits(scene: *flecs.world_t) void {
        flecs.add_pair(
            scene,
            flecs.id(Self),
            flecs.OnInstantiate,
            flecs.Override,
        );
    }

    pub fn init(FOWinDeg: f32, aspectRatio: f32, near: f32, far: f32) !Self {
        const tracy_zone = tracy.ZoneNC(@src(), "Init camera", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self: Self = undefined;
        self.setProjectionMatrix(FOWinDeg, aspectRatio, near, far);

        self.cameraMatricesUniform = try gfx.createBuffer(
            &gfx.BufferCreateInfo{
                .size = 2 * @sizeOf(util.math.simd.Mat) + @sizeOf(util.math.simd.Vec),
                .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{.UniformBufferBit}),
                .sharingMode = gfx.SharingMode.Exclusive,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        try Renderer.addDescriptorUpdate(
            gfx.WriteDescriptorSet{
                .dstSet = Renderer.descriptorSet,
                .dstArrayElement = 0,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = .UniformBuffer,
                .pBufferInfo = &[_]gfx.DescriptorBufferInfo{
                    gfx.DescriptorBufferInfo{
                        .buffer = self.cameraMatricesUniform.buffer,
                        .offset = 0,
                        .range = 2 * @sizeOf(util.math.simd.Mat) + @sizeOf(util.math.simd.Vec),
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
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit camera", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.destroyBuffer(self.cameraMatricesUniform);
    }

    pub fn onUpdate(_: *flecs.iter_t, cameras: []Camera, transforms: []core.Transform) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Update cameras", 0x00_ff_ff_00);
        defer tracy_zone.End();

        for (cameras, transforms) |c, t| {
            const transformMatrix = util.math.simd.mul(t.translationMatrix, t.rotationMatrix);
            const data = mem.toBytes(transformMatrix) ++ mem.toBytes(c.projectionMatrix) ++ mem.toBytes(t.localPosition);

            try Renderer.addStagingData(Renderer.StagingData{
                .data = &data,
                .dstBuffer = c.cameraMatricesUniform,
            });
        }
    }

    pub fn setProjectionMatrix(self: *Self, FOVinDeg: f32, aspectRatio: f32, near: f32, far: f32) void {
        self.projectionMatrix = util.math.simd.perspectiveFovRh(math.degreesToRadians(FOVinDeg), aspectRatio, near, far);
    }
};
