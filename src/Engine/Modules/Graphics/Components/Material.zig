const util = @import("util");
const mem = util.mem;
const ArrayList = util.ArrayList;

const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("Internal/interface.zig");
const Renderer = @import("Renderer.zig").Renderer;

const shaders = @import("Internal/shaderStorage.zig");

pub const Archetype = enum(u8) {
    Unlit,
    PBR,
};

pub const CreateOptions = struct {
    vertexShader: []const u8,
    fragmentShader: []const u8,
    tessControlShader: ?[]const u8,
    tessEvalShader: ?[]const u8,

    vertexBindings: ArrayList(gfx.VertexInputBindingDescription),
    vertexAttributes: ArrayList(gfx.VertexInputAttributeDescription),

    depthEnable: bool,

    pub fn initFromArchetype(archetype: Archetype) CreateOptions {
        switch (archetype) {
            .Unlit => return CreateOptions{
                .vertexShader = try shaders.getOrAdd("resources/shaders/unlit/unlit.vert"),
                .fragmentShader = try shaders.getOrAdd("resources/shaders/unlit/unlit.frag"),
                .tessControlShader = null,
                .tessEvalShader = null,
                .vertexBindings = list: {
                    var bindings = ArrayList(gfx.VertexInputBindingDescription).init(mem.heap);
                    const arr = try bindings.addManyAsArray(1);
                    arr.* = [_]gfx.VertexInputBindingDescription{
                        gfx.VertexInputBindingDescription{
                            .binding = 0,
                            .stride = 20,
                            .input_rate = gfx.VertexInputRate.vertex,
                        },
                    };
                    break :list bindings;
                },
                .vertexAttributes = list: {
                    var attribs = ArrayList(gfx.VertexInputAttributeDescription).init(mem.heap);
                    const arr = try attribs.addManyAsArray(2);
                    arr.* = [_]gfx.VertexInputAttributeDescription{
                        //position
                        gfx.VertexInputAttributeDescription{
                            .binding = 0,
                            .location = 0,
                            .offset = 0,
                            .format = gfx.Format.r32g32b32_sfloat,
                        },
                        //texCoords
                        gfx.VertexInputAttributeDescription{
                            .binding = 0,
                            .location = 1,
                            .offset = 12,
                            .format = gfx.Format.r32g32_sfloat,
                        },
                    };
                    break :list attribs;
                },
                .depthEnable = true,
            },
            .PBR => return .{},
        }
    }

    pub fn deinit(self: CreateOptions) void {
        self.vertexAttributes.deinit();
        self.vertexBindings.deinit();
    }
};

pub const Material = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    pub var Prefab: flecs.entity_t = undefined;

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

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn new(name: []const u8, vertexShaderPath: []const u8, fragmentShaderPath: []const u8) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, @ptrCast(name.ptr));
        flecs.add_pair(_scene, newEntt, flecs.IsA, getPrefab());
        _ = flecs.set(_scene, newEntt, Self, try init(name, vertexShaderPath, fragmentShaderPath));

        return newEntt;
    }

    pub fn init(name: []const u8, vertexShaderPath: []const u8, fragmentShaderPath: []const u8) !Self {
        const tracy_zone = tracy.ZoneNC(@src(), "Init material", 0x00_ff_ff_00);
        defer tracy_zone.End();

        var self: Self = undefined;

        const vertexCode = try shaders.getOrAdd(vertexShaderPath);
        const fragmentCode = try shaders.getOrAdd(fragmentShaderPath);

        self.vertexModule = try gfx.CreateShaderModule(&gfx.ShaderModuleCreateInfo{
            .codeSize = vertexCode.len,
            .pCode = @ptrCast(@alignCast(vertexCode.ptr)),
        });

        self.fragmentModule = try gfx.CreateShaderModule(&gfx.ShaderModuleCreateInfo{
            .codeSize = fragmentCode.len,
            .pCode = @ptrCast(@alignCast(fragmentCode.ptr)),
        });

        const materialPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .UniformBuffer,
                .descriptorCount = 1,
            },
        };

        const materialDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorType = gfx.DescriptorType.UniformBuffer,
                .descriptorCount = 1,
                .stageFlags = gfx.toFlags(&[_]gfx.ShaderStageFlagBits{.VertexBit}),
            },
        };

        self.materialDescriptorSetLayout = try gfx.CreateDescriptorSetLayout(
            &gfx.DescriptorSetLayoutCreateInfo{
                .pBindings = &materialDescriptorBindings,
                .bindingCount = @intCast(materialDescriptorBindings.len),
            },
        );

        self.materialDescriptorPool = try gfx.CreateDescriptorPool(
            &gfx.DescriptorPoolCreateInfo{
                .pPoolSizes = &materialPoolSizes,
                .poolSizeCount = @intCast(materialPoolSizes.len),
                .maxSets = 1,
            },
        );

        const modelPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .CombinedImageSampler,
                .descriptorCount = 10,
            },
        };

        self.modelDescriptorPool = try gfx.CreateDescriptorPool(
            &gfx.DescriptorPoolCreateInfo{
                .pPoolSizes = &modelPoolSizes,
                .poolSizeCount = @intCast(modelPoolSizes.len),
                .maxSets = 10,
            },
        );

        const modelDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorType = gfx.DescriptorType.CombinedImageSampler,
                .descriptorCount = 1,
                .stageFlags = gfx.toFlags(&[_]gfx.ShaderStageFlagBits{.FragmentBit}),
            },
        };

        self.modelDescriptorSetLayout = try gfx.CreateDescriptorSetLayout(
            &gfx.DescriptorSetLayoutCreateInfo{
                .pBindings = &modelDescriptorBindings,
                .bindingCount = @intCast(modelDescriptorBindings.len),
            },
        );

        const instancePoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .UniformBuffer,
                .descriptorCount = 1000,
            },
        };

        self.instanceDescriptorPool = try gfx.CreateDescriptorPool(
            &gfx.DescriptorPoolCreateInfo{
                .pPoolSizes = &instancePoolSizes,
                .poolSizeCount = @intCast(instancePoolSizes.len),
                .maxSets = 1000,
            },
        );

        const instanceDescriptorBindings = [_]gfx.DescriptorSetLayoutBinding{
            gfx.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorType = gfx.DescriptorType.UniformBuffer,
                .descriptorCount = 1,
                .stageFlags = gfx.toFlags(&[_]gfx.ShaderStageFlagBits{.VertexBit}),
            },
        };

        self.instanceDescriptorSetLayout = try gfx.CreateDescriptorSetLayout(
            &gfx.DescriptorSetLayoutCreateInfo{
                .pBindings = &instanceDescriptorBindings,
                .bindingCount = @intCast(instanceDescriptorBindings.len),
            },
        );

        const setLayouts = [_]gfx.DescriptorSetLayout{
            Renderer.globalDescriptorSetLayout,
            //self.materialDescriptorSetLayout,
            self.modelDescriptorSetLayout,
            self.instanceDescriptorSetLayout,
        };

        self.pipelineLayout = try gfx.CreatePipelineLayout(
            &gfx.PipelineLayoutCreateInfo{
                .pSetLayouts = @ptrCast(&setLayouts),
                .setLayoutCount = @intCast(setLayouts.len),
                .pPushConstantRanges = null,
                .pushConstantRangeCount = 0,
            },
        );

        var cacheData = try shaders.getPipelineCache(name, vertexShaderPath, fragmentShaderPath, null, null, null);

        const cache = try gfx.CreatePipelineCache(
            &gfx.PipelineCacheCreateInfo{
                .initialDataSize = if (cacheData) |data| data.len else 0,
                .pInitialData = if (cacheData) |data| data.ptr else null,
            },
        );

        self.pipeline = try gfx.createPipeline(
            cache,
            self.pipelineLayout,
            Renderer._renderPass,
            self.vertexModule,
            self.fragmentModule,
            &[_]gfx.VertexInputBindingDescription{
                gfx.VertexInputBindingDescription{
                    .binding = 0,
                    .stride = 32,
                    .inputRate = gfx.VertexInputRate.Vertex,
                },
            },
            &[_]gfx.VertexInputAttributeDescription{
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 0,
                    .offset = 0,
                    .format = gfx.Format.R32g32b32Sfloat,
                },
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 1,
                    .offset = 12,
                    .format = gfx.Format.R32g32b32Sfloat,
                },
                gfx.VertexInputAttributeDescription{
                    .binding = 0,
                    .location = 2,
                    .offset = 24,
                    .format = gfx.Format.R32g32Sfloat,
                },
            },
            true,
            null,
        );

        if (cacheData == null) {
            cacheData = try gfx.GetPipelineCacheData(cache, mem.heap);
            defer util.mem.heap.free(cacheData.?);

            try shaders.addPipelineCache(name, cacheData.?, vertexShaderPath, fragmentShaderPath, null, null, null);
        }

        try gfx.AllocateDescriptorSets(&gfx.DescriptorSetAllocateInfo{
            .descriptorPool = self.materialDescriptorPool,
            .pSetLayouts = @ptrCast(&self.materialDescriptorSetLayout),
            .descriptorSetCount = 1,
        }, @ptrCast(&self.descriptorSet));

        self.materialUniforms = try gfx.createBuffer(
            gfx.vkAllocator,
            &gfx.BufferCreateInfo{
                .size = 2 * @sizeOf(util.math.simd.Mat),
                .usage = gfx.toFlags(&[_]gfx.BufferUsageFlagBits{.UniformBufferBit}),
                .sharingMode = gfx.SharingMode.Exclusive,
                .pQueueFamilyIndices = null,
            },
            &gfx.vma.VmaAllocationCreateInfo{
                .usage = gfx.vma.VMA_MEMORY_USAGE_CPU_ONLY,
            },
        );

        try gfx.DestroyPipelineCache(cache);

        return self;
    }

    pub fn deinit(self: *Self) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit material", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try gfx.DestroyPipeline(self.pipeline);
        try gfx.DestroyPipelineLayout(self.pipelineLayout);

        try gfx.DestroyDescriptorSetLayout(self.materialDescriptorSetLayout);
        try gfx.DestroyDescriptorPool(self.materialDescriptorPool);

        try gfx.DestroyDescriptorSetLayout(self.modelDescriptorSetLayout);
        try gfx.DestroyDescriptorPool(self.modelDescriptorPool);

        try gfx.DestroyDescriptorSetLayout(self.instanceDescriptorSetLayout);
        try gfx.DestroyDescriptorPool(self.instanceDescriptorPool);

        try gfx.DestroyShaderModule(self.vertexModule);
        try gfx.DestroyShaderModule(self.fragmentModule);

        gfx.destroyBuffer(gfx.vkAllocator, self.materialUniforms);
    }

    pub fn onUpdate(_: *flecs.iter_t) void {}
};
