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

        self.vertexModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = vertexCode.len,
            .p_code = @ptrCast(@alignCast(vertexCode.ptr)),
        }, null);

        self.fragmentModule = try gfx.device.createShaderModule(&gfx.ShaderModuleCreateInfo{
            .code_size = fragmentCode.len,
            .p_code = @ptrCast(@alignCast(fragmentCode.ptr)),
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

        var cacheData = try shaders.getPipelineCache(name, vertexShaderPath, fragmentShaderPath, null, null, null);

        const cache = try gfx.device.createPipelineCache(&gfx.PipelineCacheCreateInfo{
            .initial_data_size = if (cacheData) |data| data.len else 0,
            .p_initial_data = if (cacheData) |data| data.ptr else null,
        }, null);
        defer gfx.device.destroyPipelineCache(cache, null);

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

        if (cacheData == null) {
            var dataSize: usize = undefined;
            _ = try gfx.device.getPipelineCacheData(cache, &dataSize, null);
            cacheData = try util.mem.heap.alloc(u8, dataSize);
            defer util.mem.heap.free(cacheData.?);
            _ = try gfx.device.getPipelineCacheData(cache, &dataSize, @ptrCast(@constCast(cacheData.?.ptr)));

            try shaders.addPipelineCache(name, cacheData.?, vertexShaderPath, fragmentShaderPath, null, null, null);
        }

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
