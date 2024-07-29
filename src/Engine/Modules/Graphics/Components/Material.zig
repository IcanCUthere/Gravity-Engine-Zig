const util = @import("util");

const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;

const shaders = @import("shaders");

pub const CreateOptions = struct {
    vertexShader: gfx.ShaderModule,
    fragmentShader: gfx.ShaderModule,
    vertexBindings: []gfx.VertexInputBindingDescription,
    vertexAttributes: []gfx.VertexInputAttributeDescription,
    descriptorSetLayouts: []gfx.DescriptorSetLayout,
    depthEnable: bool,
};

pub const Archetype = enum(u8) {
    Unlit,
    PBR,
};

pub fn CreateOptionsFromArchetype(archetype: Archetype) CreateOptions {
    switch (archetype) {
        .Unlit => return CreateOptions{
            .vertexShader = shaders.shader_vert,
            .fragmentShader = shaders.shader_frag,

            .depthEnable = true,
        },
        .PBR => return .{},
    }
}

pub const Material = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    var Prefab: flecs.entity_t = undefined;

    vertexModule: gfx.ShaderModule = undefined,
    fragmentModule: gfx.ShaderModule = undefined,

    materialDescriptorPool: gfx.DescriptorPool = undefined,
    materialDescriptorSetLayout: gfx.DescriptorSetLayout = undefined,
    descriptorSet: gfx.DescriptorSet = undefined,
    materialUniforms: gfx.BufferAllocation = undefined,

    modelDescriptorPool: gfx.DescriptorPool = undefined,
    modelDescriptorSetLayout: gfx.DescriptorSetLayout = undefined,

    instanceDescriptorPool: gfx.DescriptorPool = undefined,
    instanceDescriptorSetLayout: gfx.DescriptorSetLayout = undefined,

    pipelineLayout: gfx.PipelineLayout = undefined,
    pipeline: gfx.Pipeline = undefined,

    pub fn register(scene: *flecs.world_t) void {
        _scene = scene;

        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "MaterialPrefab");
        flecs.add(scene, Prefab, Self);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn new(name: [*:0]const u8, vertexShader: []const u8, fragmentShader: []const u8) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);
        flecs.add_pair(_scene, newEntt, flecs.IsA, getPrefab());
        _ = flecs.set(_scene, newEntt, Self, try init(vertexShader, fragmentShader));

        return newEntt;
    }

    pub fn init(vertexShader: []const u8, fragmentShader: []const u8) !Self {
        const tracy_zone = tracy.ZoneNC(@src(), "Init material", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self: Self = undefined;

        self.vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = vertexShader.len,
            .p_code = @ptrCast(@alignCast(vertexShader.ptr)),
        }, null);

        self.fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = fragmentShader.len,
            .p_code = @ptrCast(@alignCast(fragmentShader.ptr)),
        }, null);

        const globalPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .combined_image_sampler,
                .descriptor_count = 1,
            },
        };

        const globalDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
            },
        };

        self.materialDescriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &globalDescriptorBindings,
            .binding_count = @intCast(globalDescriptorBindings.len),
        }, null);

        self.materialDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &globalPoolSizes,
            .pool_size_count = @intCast(globalPoolSizes.len),
            .max_sets = 1,
        }, null);

        const modelPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .uniform_buffer,
                .descriptor_count = 10,
            },
        };

        self.modelDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &modelPoolSizes,
            .pool_size_count = @intCast(modelPoolSizes.len),
            .max_sets = 10,
        }, null);

        const modelDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.combined_image_sampler,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .fragment_bit = true },
            },
        };

        self.modelDescriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &modelDescriptorBindings,
            .binding_count = @intCast(modelDescriptorBindings.len),
        }, null);

        const instancePoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .uniform_buffer,
                .descriptor_count = 1000,
            },
        };

        self.instanceDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &instancePoolSizes,
            .pool_size_count = @intCast(instancePoolSizes.len),
            .max_sets = 1000,
        }, null);

        const instanceDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_type = gfx.DescriptorType.uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = gfx.ShaderStageFlags{ .vertex_bit = true },
            },
        };

        self.instanceDescriptorSetLayout = try gfx.device.createDescriptorSetLayout(&gfx.DescriptorSetLayoutCreateInfo{
            .p_bindings = &instanceDescriptorBindings,
            .binding_count = @intCast(instanceDescriptorBindings.len),
        }, null);

        const setLayouts = [_]gfx.DescriptorSetLayout{
            Renderer.globalDescriptorSetLayout,
            //self.materialDescriptorSetLayout,
            self.modelDescriptorSetLayout,
            self.instanceDescriptorSetLayout,
        };

        self.pipelineLayout = try gfx.device.createPipelineLayout(&gfx.PipelineLayoutCreateInfo{
            .p_set_layouts = @ptrCast(&setLayouts),
            .set_layout_count = @intCast(setLayouts.len),
            .p_push_constant_ranges = null,
            .push_constant_range_count = 0,
        }, null);

        self.pipeline = try gfx.createPipeline(
            self.pipelineLayout,
            Renderer._renderPass,
            self.vertexModule,
            self.fragmentModule,
            &[_]gfx.VertexInputBindingDescription{
                gfx.VertexInputBindingDescription{
                    .binding = 0,
                    .stride = 32,
                    .input_rate = gfx.VertexInputRate.vertex,
                },
            },
            &[_]gfx.VertexInputAttributeDescription{
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 0,
                    .offset = 0,
                    .format = gfx.Format.r32g32b32_sfloat,
                },
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 1,
                    .offset = 12,
                    .format = gfx.Format.r32g32b32_sfloat,
                },
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 2,
                    .offset = 24,
                    .format = gfx.Format.r32g32_sfloat,
                },
            },
            true,
            null,
        );

        try gfx.device.allocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptor_pool = self.materialDescriptorPool,
            .p_set_layouts = @ptrCast(&self.materialDescriptorSetLayout),
            .descriptor_set_count = 1,
        }, @ptrCast(&self.descriptorSet));

        self.materialUniforms = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = 2 * @sizeOf(util.math.Mat),
                .usage = gfx.BufferUsageFlags{ .uniform_buffer_bit = true },
                .sharing_mode = gfx.SharingMode.exclusive,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        return self;
    }

    pub fn deinit(self: *Self) void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit material", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.device.destroyPipeline(self.pipeline, null);
        gfx.device.destroyPipelineLayout(self.pipelineLayout, null);

        gfx.device.destroyDescriptorSetLayout(self.materialDescriptorSetLayout, null);
        gfx.device.destroyDescriptorPool(self.materialDescriptorPool, null);

        gfx.device.destroyDescriptorSetLayout(self.modelDescriptorSetLayout, null);
        gfx.device.destroyDescriptorPool(self.modelDescriptorPool, null);

        gfx.device.destroyDescriptorSetLayout(self.instanceDescriptorSetLayout, null);
        gfx.device.destroyDescriptorPool(self.instanceDescriptorPool, null);

        gfx.device.destroyShaderModule(self.vertexModule, null);
        gfx.device.destroyShaderModule(self.fragmentModule, null);

        gfx.destroyBuffer(gfx.vkAllocator, self.materialUniforms);
    }

    pub fn onUpdate(_: *flecs.iter_t) void {}
};
