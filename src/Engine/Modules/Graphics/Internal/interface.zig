const util = @import("util");
const mem = util.mem;

const builtin = @import("builtin");

pub const glfw = @import("zglfw");
pub const vk = @import("vulkanBindings.zig");
pub const vma = @cImport({
    @cInclude("vk_mem_alloc.cpp");
});

pub usingnamespace vk;

pub const Allocator = vma.VmaAllocator;
pub const AllocationCreateInfo = vma.VmaAllocationCreateInfo;
pub const Allocation = vma.VmaAllocation;
pub const AllocationInfo = vma.VmaAllocationInfo;

pub const ImageAllocation = struct {
    image: vk.Image,
    allocation: Allocation,
    //allocationInfo: AllocationInfo,
};

pub const BufferAllocation = struct {
    buffer: vk.Buffer,
    allocation: Allocation,
};

pub var physicalDevice: vk.PhysicalDevice = undefined;
pub var vkAllocator: Allocator = undefined;
pub var renderFamily: u32 = undefined;
pub var renderQueue: vk.Queue = undefined;

var deviceProperties: vk.PhysicalDeviceProperties = undefined;

pub fn init() !void {
    const version = vk.Version14;
    const extensions = [_]type{
        vk.KHRSwapchain,
        vk.KHRGetSurfaceCapabilities2,
        vk.EXTSurfaceMaintenance1,
        vk.EXTSwapchainMaintenance1,
    };
    const validation = if (builtin.mode == .Debug) true else false;

    try version.loadBaseFunctions();

    const glfwExtensionsNames = try glfw.getRequiredInstanceExtensions();

    var instanceExtensionCount: u32 = 0;
    var instanceExtensionsNames: [extensions.len][*:0]const u8 = undefined;
    inline for (extensions) |ext| {
        if (ext.isInstanceExtension) {
            instanceExtensionsNames[instanceExtensionCount] = ext.name;
            instanceExtensionCount += 1;
        }
    }

    const combinedInstanceExtensions = try mem.fixedBuffer.alloc(
        [*:0]const u8,
        instanceExtensionCount + glfwExtensionsNames.len,
    );
    defer mem.fixedBuffer.free(combinedInstanceExtensions);

    for (instanceExtensionsNames, 0..) |name, i| {
        combinedInstanceExtensions[i] = name;
    }
    for (glfwExtensionsNames, instanceExtensionCount..) |name, i| {
        combinedInstanceExtensions[i] = name;
    }

    vk.gInstance = try vk.CreateInstance(&vk.InstanceCreateInfo{
        .enabledExtensionCount = @intCast(combinedInstanceExtensions.len),
        .ppEnabledExtensionNames = combinedInstanceExtensions.ptr,
        .enabledLayerCount = if (validation) 1 else 0,
        .ppEnabledLayerNames = &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"},
        .pApplicationInfo = &vk.ApplicationInfo{
            .apiVersion = vk.apiVersion14,
            .applicationVersion = 0,
            .engineVersion = 0,
            .pApplicationName = "Test",
            .pEngineName = "Test",
        },
    });

    try version.loadInstanceFunctions();
    inline for (extensions) |ext| {
        if (ext.isInstanceExtension) {
            try ext.load();
        }
    }

    const surfaceExtensions = [_]type{
        vk.KHRSurface,
        vk.KHRWin32Surface,
        vk.KHRXlibSurface,
        vk.KHRWaylandSurface,
        vk.KHRXcbSurface,
        vk.KHRAndroidSurface,
    };

    inline for (surfaceExtensions) |surfaceExtension| {
        for (glfwExtensionsNames) |glfwExtensionName| {
            if (mem.eql(u8, mem.span(surfaceExtension.name), mem.span(glfwExtensionName))) {
                try surfaceExtension.load();
            }
        }
    }

    var deviceExtensionCount: u32 = 0;
    var deviceExtensions: [extensions.len][*:0]const u8 = undefined;
    inline for (extensions) |ext| {
        if (!ext.isInstanceExtension) {
            deviceExtensions[deviceExtensionCount] = ext.name;
            deviceExtensionCount += 1;
        }
    }

    physicalDevice = try findBestDevice(deviceExtensions[0..deviceExtensionCount]);
    deviceProperties = try vk.GetPhysicalDeviceProperties(physicalDevice);

    util.log.print(
        "Used Graphics Card: {s}, Driver Version: {d}",
        .{ deviceProperties.deviceName, deviceProperties.driverVersion },
        .Info,
        .Abstract,
        .{ .Vulkan = true },
    );

    renderFamily = try getGraphicsFamily(physicalDevice);

    const queueFamilyProperties = try vk.GetPhysicalDeviceQueueFamilyProperties(
        physicalDevice,
        mem.fixedBuffer,
    );

    const priority = [_]f32{1};
    const queueCreateInfos = try util.mem.fixedBuffer.alloc(
        vk.DeviceQueueCreateInfo,
        queueFamilyProperties.len,
    );
    defer util.mem.fixedBuffer.free(queueCreateInfos);

    for (queueCreateInfos, 0..) |*createInfo, i| {
        createInfo.* = vk.DeviceQueueCreateInfo{
            .queueFamilyIndex = @intCast(i),
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };
    }

    const timelineFeature = vk.PhysicalDeviceTimelineSemaphoreFeatures{
        .timelineSemaphore = vk.TRUE,
    };

    const swapchainMaintainanceFeature = vk.PhysicalDeviceSwapchainMaintenance1FeaturesEXT{
        .pNext = &timelineFeature,
        .swapchainMaintenance1 = vk.TRUE,
    };

    var deviceFeatures: vk.PhysicalDeviceFeatures = try vk.GetPhysicalDeviceFeatures(physicalDevice);
    deviceFeatures.samplerAnisotropy = vk.TRUE;

    var deviceFeatures2 = try vk.GetPhysicalDeviceFeatures2(physicalDevice, deviceFeatures);
    deviceFeatures2.pNext = &swapchainMaintainanceFeature;

    vk.gDevice = try vk.CreateDevice(
        physicalDevice,
        &vk.DeviceCreateInfo{
            .pNext = &deviceFeatures2,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = deviceExtensionCount,
            .ppEnabledExtensionNames = &deviceExtensions,
            .pEnabledFeatures = null,
            .queueCreateInfoCount = @intCast(queueCreateInfos.len),
            .pQueueCreateInfos = queueCreateInfos.ptr,
        },
    );

    try version.loadDeviceFunctions();
    inline for (extensions) |ext| {
        if (!ext.isInstanceExtension) {
            try ext.load();
        }
    }

    renderQueue = try vk.GetDeviceQueue(renderFamily, 0);
    vkAllocator = try createAllocator(
        vk.gInstance,
        vk.gDevice,
        physicalDevice,
        vk.apiVersion14,
    );
}

pub fn deinit() !void {
    vma.vmaDestroyAllocator(vkAllocator);
    try vk.DestroyDevice();
    try vk.DestroyInstance();
}

pub fn createRenderPass(viewportFormat: vk.Format, clear: bool) !vk.RenderPass {
    const attachmentDescriptions = [_]vk.AttachmentDescription{
        vk.AttachmentDescription{
            .format = viewportFormat,
            .samples = .@"1Bit",
            .loadOp = if (clear) vk.AttachmentLoadOp.Clear else vk.AttachmentLoadOp.DontCare,
            .storeOp = vk.AttachmentStoreOp.Store,
            .stencilLoadOp = vk.AttachmentLoadOp.DontCare,
            .stencilStoreOp = vk.AttachmentStoreOp.DontCare,
            .initialLayout = vk.ImageLayout.Undefined,
            .finalLayout = vk.ImageLayout.PresentSrcKhr,
        },
        vk.AttachmentDescription{
            .format = vk.Format.D16Unorm,
            .samples = .@"1Bit",
            .loadOp = vk.AttachmentLoadOp.Clear,
            .storeOp = vk.AttachmentStoreOp.DontCare,
            .stencilLoadOp = vk.AttachmentLoadOp.DontCare,
            .stencilStoreOp = vk.AttachmentStoreOp.DontCare,
            .initialLayout = vk.ImageLayout.Undefined,
            .finalLayout = vk.ImageLayout.DepthStencilAttachmentOptimal,
        },
    };

    const colorReferences = [_]vk.AttachmentReference{
        vk.AttachmentReference{
            .attachment = 0,
            .layout = vk.ImageLayout.ColorAttachmentOptimal,
        },
    };
    const depthRefernce = vk.AttachmentReference{
        .attachment = 1,
        .layout = vk.ImageLayout.DepthStencilAttachmentOptimal,
    };

    const subpasses = [_]vk.SubpassDescription{
        vk.SubpassDescription{
            .pipelineBindPoint = vk.PipelineBindPoint.Graphics,
            .pInputAttachments = null,
            .inputAttachmentCount = 0,
            .pDepthStencilAttachment = &depthRefernce,
            .pColorAttachments = &colorReferences,
            .pResolveAttachments = null,
            .colorAttachmentCount = 1,
            .pPreserveAttachments = null,
            .preserveAttachmentCount = 0,
        },
    };

    const subpassDependencies = [_]vk.SubpassDependency{
        vk.SubpassDependency{
            .srcSubpass = vk.subpassExternal,
            .dstSubpass = 0,
            .srcStageMask = vk.toFlags(&[_]vk.PipelineStageFlagBits{
                .ColorAttachmentOutputBit,
                .EarlyFragmentTestsBit,
            }),
            .dstStageMask = vk.toFlags(&[_]vk.PipelineStageFlagBits{
                .ColorAttachmentOutputBit,
                .EarlyFragmentTestsBit,
            }),
            .srcAccessMask = vk.toFlags(&[_]vk.AccessFlagBits{}),
            .dstAccessMask = vk.toFlags(&[_]vk.AccessFlagBits{
                .ColorAttachmentWriteBit,
                .DepthStencilAttachmentWriteBit,
            }),
            .dependencyFlags = vk.toFlags(&[_]vk.DependencyFlagBits{}),
        },
        vk.SubpassDependency{
            .srcSubpass = 0,
            .dstSubpass = vk.subpassExternal,
            .srcStageMask = vk.toFlags(&[_]vk.PipelineStageFlagBits{
                .LateFragmentTestsBit,
                .ColorAttachmentOutputBit,
            }),
            .dstStageMask = vk.toFlags(&[_]vk.PipelineStageFlagBits{
                .EarlyFragmentTestsBit,
            }),
            .srcAccessMask = vk.toFlags(&[_]vk.AccessFlagBits{
                .DepthStencilAttachmentWriteBit,
                .ColorAttachmentWriteBit,
            }),
            .dstAccessMask = vk.toFlags(&[_]vk.AccessFlagBits{
                //.depth_stencil_attachment_write_bit = true,
            }),
            .dependencyFlags = vk.toFlags(&[_]vk.DependencyFlagBits{}),
        },
    };

    return try vk.CreateRenderPass(&vk.RenderPassCreateInfo{
        .pAttachments = &attachmentDescriptions,
        .attachmentCount = @intCast(attachmentDescriptions.len),
        .pSubpasses = &subpasses,
        .subpassCount = @intCast(subpasses.len),
        .pDependencies = &subpassDependencies,
        .dependencyCount = @intCast(subpassDependencies.len),
    });
}

pub fn createPipeline(
    cache: vk.PipelineCache,
    layout: vk.PipelineLayout,
    renderPass: vk.RenderPass,
    vertModule: vk.ShaderModule,
    fragModule: vk.ShaderModule,
    vertexBindings: []const vk.VertexInputBindingDescription,
    vertexAttributes: []const vk.VertexInputAttributeDescription,
    depthEnable: bool,
    comptime viewportSize: ?[2]f32,
) !vk.Pipeline {
    const stages = [_]vk.PipelineShaderStageCreateInfo{
        vk.PipelineShaderStageCreateInfo{
            .pName = "main",
            .stage = .VertexBit,
            .module = vertModule,
        },
        vk.PipelineShaderStageCreateInfo{
            .pName = "main",
            .stage = .FragmentBit,
            .module = fragModule,
        },
    };

    const viewports = [_]vk.Viewport{
        vk.Viewport{
            .width = if (viewportSize) |v| v[0] else 0,
            .height = if (viewportSize) |v| v[1] else 0,
            .minDepth = 0.0,
            .maxDepth = 1.0,
            .x = 0.0,
            .y = 0.0,
        },
    };

    const scissors = [_]vk.Rect2D{
        vk.Rect2D{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = .{
                .width = if (viewportSize) |v| @intFromFloat(v[0]) else 0,
                .height = if (viewportSize) |v| @intFromFloat(v[1]) else 0,
            },
        },
    };

    const stencilOpState = vk.StencilOpState{
        .passOp = vk.StencilOp.Keep,
        .failOp = vk.StencilOp.Keep,
        .depthFailOp = vk.StencilOp.Keep,
        .compareOp = vk.CompareOp.Always,
        .compareMask = 0,
        .reference = 0,
        .writeMask = 0,
    };

    const colorBlendAttachments = [_]vk.PipelineColorBlendAttachmentState{
        vk.PipelineColorBlendAttachmentState{
            .blendEnable = vk.FALSE,
            .colorBlendOp = vk.BlendOp.Add,
            .alphaBlendOp = vk.BlendOp.Add,
            .colorWriteMask = vk.toFlags(&[_]vk.ColorComponentFlagBits{
                .RBit,
                .GBit,
                .BBit,
                .ABit,
            }),
            .srcColorBlendFactor = vk.BlendFactor.One,
            .dstColorBlendFactor = vk.BlendFactor.Zero,
            .srcAlphaBlendFactor = vk.BlendFactor.One,
            .dstAlphaBlendFactor = vk.BlendFactor.Zero,
        },
    };

    const dynamicStates = if (viewportSize == null) [_]vk.DynamicState{
        vk.DynamicState.Viewport,
        vk.DynamicState.Scissor,
    } else [_]vk.DynamicState{};

    const createInfos = [_]vk.GraphicsPipelineCreateInfo{
        vk.GraphicsPipelineCreateInfo{
            .layout = layout,
            .renderPass = renderPass,
            .subpass = 0,
            .basePipelineIndex = 0,
            .basePipelineHandle = null,
            .pStages = &stages,
            .stageCount = @intCast(stages.len),
            .pVertexInputState = &vk.PipelineVertexInputStateCreateInfo{
                .pVertexAttributeDescriptions = vertexAttributes.ptr,
                .vertexAttributeDescriptionCount = @intCast(vertexAttributes.len),
                .pVertexBindingDescriptions = vertexBindings.ptr,
                .vertexBindingDescriptionCount = @intCast(vertexBindings.len),
            },
            .pInputAssemblyState = &vk.PipelineInputAssemblyStateCreateInfo{
                .primitiveRestartEnable = vk.FALSE,
                .topology = vk.PrimitiveTopology.TriangleList,
            },
            .pTessellationState = &vk.PipelineTessellationStateCreateInfo{
                .patchControlPoints = 0,
            },
            .pViewportState = &vk.PipelineViewportStateCreateInfo{
                .pViewports = &viewports,
                .viewportCount = @intCast(viewports.len),
                .pScissors = &scissors,
                .scissorCount = @intCast(scissors.len),
            },
            .pRasterizationState = &vk.PipelineRasterizationStateCreateInfo{
                .polygonMode = vk.PolygonMode.Fill,
                .cullMode = vk.toFlags(&[_]vk.CullModeFlagBits{.BackBit}),
                .frontFace = vk.FrontFace.CounterClockwise,
                .depthBiasEnable = vk.FALSE,
                .depthClampEnable = vk.FALSE,
                .rasterizerDiscardEnable = vk.FALSE,
                .depthBiasClamp = 0.0,
                .depthBiasConstantFactor = 0.0,
                .depthBiasSlopeFactor = 0.0,
                .lineWidth = 1.0,
            },
            .pMultisampleState = &vk.PipelineMultisampleStateCreateInfo{
                .rasterizationSamples = .@"1Bit",
                .alphaToCoverageEnable = vk.FALSE,
                .alphaToOneEnable = vk.FALSE,
                .sampleShadingEnable = vk.FALSE,
                .minSampleShading = 1.0,
                .pSampleMask = null,
            },
            .pDepthStencilState = &vk.PipelineDepthStencilStateCreateInfo{
                .depthTestEnable = if (depthEnable) vk.TRUE else vk.FALSE,
                .depthWriteEnable = if (depthEnable) vk.TRUE else vk.FALSE,
                .depthBoundsTestEnable = vk.FALSE,
                .stencilTestEnable = vk.FALSE,
                .depthCompareOp = vk.CompareOp.Less,
                .minDepthBounds = 0.0,
                .maxDepthBounds = 1.0,
                .front = stencilOpState,
                .back = stencilOpState,
            },
            .pColorBlendState = &vk.PipelineColorBlendStateCreateInfo{
                .logicOpEnable = vk.FALSE,
                .logicOp = vk.LogicOp.Copy,
                .pAttachments = &colorBlendAttachments,
                .attachmentCount = @intCast(colorBlendAttachments.len),
                .blendConstants = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            },
            .pDynamicState = &vk.PipelineDynamicStateCreateInfo{
                .pDynamicStates = &dynamicStates,
                .dynamicStateCount = @intCast(dynamicStates.len),
            },
        },
    };

    const pipelines = try vk.CreateGraphicsPipelines(
        cache,
        &createInfos,
        mem.fixedBuffer,
    );
    defer mem.fixedBuffer.free(pipelines);

    return pipelines[0];
}

pub fn getGraphicsCardName() []const u8 {
    return &deviceProperties.device_name;
}

pub fn getDriverVersion() u32 {
    return deviceProperties.driver_version;
}

fn getGraphicsFamily(pdev: vk.PhysicalDevice) !u32 {
    const queueFamilyProperties = try vk.GetPhysicalDeviceQueueFamilyProperties(
        pdev,
        mem.fixedBuffer,
    );
    defer mem.fixedBuffer.free(queueFamilyProperties);

    for (queueFamilyProperties, 0..) |properties, i| {
        if ((properties.queueFlags | @intFromEnum(vk.QueueFlagBits.GraphicsBit)) > 0) {
            return @intCast(i);
        }
    }

    return error.NoRenderFamilyFound;
}

fn findRankingSpot(T: type, ranking: []const T, item: T) u64 {
    for (ranking, 0..) |r, i| {
        if (r == item) {
            return i;
        }
    }

    return 100000;
}

fn getVRamSize(dev: vk.PhysicalDevice) !u64 {
    const memProps = try vk.GetPhysicalDeviceMemoryProperties(dev);

    for (0..memProps.memoryHeapCount) |i| {
        if ((memProps.memoryHeaps[i].flags | @intFromEnum(vk.MemoryHeapFlagBits.DeviceLocalBit)) > 0) {
            return memProps.memoryHeaps[i].size;
        }
    }

    return 0;
}

fn hasBetterProperties(new: vk.PhysicalDevice, old: vk.PhysicalDevice) !bool {
    const newProps = try vk.GetPhysicalDeviceProperties(new);
    const oldProps = try vk.GetPhysicalDeviceProperties(old);

    const typeRanking = [_]vk.PhysicalDeviceType{
        .DiscreteGpu,
        .IntegratedGpu,
        .VirtualGpu,
        .Cpu,
        .Other,
    };

    const newRanking = findRankingSpot(vk.PhysicalDeviceType, typeRanking[0..], newProps.deviceType);
    const oldRanking = findRankingSpot(vk.PhysicalDeviceType, typeRanking[0..], oldProps.deviceType);
    if (newRanking < oldRanking) {
        return true;
    } else if (newRanking > oldRanking) {
        return false;
    }

    const newVramSize = try getVRamSize(new);
    const oldVramSize = try getVRamSize(old);

    if (newVramSize > oldVramSize) {
        return true;
    } else if (newVramSize < oldVramSize) {
        return false;
    }

    return false;
}

fn findBestDevice(requiredExtensionNames: [][*:0]const u8) !vk.PhysicalDevice {
    const physicalDevices = try vk.EnumeratePhysicalDevices(mem.fixedBuffer);
    defer mem.fixedBuffer.free(physicalDevices);

    var bestDev: ?vk.PhysicalDevice = null;
    for (physicalDevices) |dev| {
        if (try checkExtensionSupport(dev, requiredExtensionNames)) {
            if (bestDev == null or try hasBetterProperties(dev, bestDev.?)) {
                bestDev = dev;
            }
        }
    }

    if (bestDev) |d| {
        return d;
    } else {
        return error.NoSuitibleGPU;
    }
}

fn checkExtensionSupport(pdev: vk.PhysicalDevice, requiredExtensionNames: [][*:0]const u8) !bool {
    const extensionProperties = try vk.EnumerateDeviceExtensionProperties(
        pdev,
        null,
        mem.fixedBuffer,
    );
    defer mem.fixedBuffer.free(extensionProperties);

    for (requiredExtensionNames) |ext| {
        for (extensionProperties) |props| {
            if (mem.eql(u8, mem.span(ext), mem.sliceTo(&props.extensionName, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

pub inline fn createSurface(window: *glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    if (@as(vk.Result, @enumFromInt(glfw.createWindowSurface(
        vk.gInstance,
        window,
        null,
        &surface,
    ))) != vk.Result.SUCCESS) {
        return error.CreateSurfaceError;
    }

    return surface;
}

pub inline fn createAllocator(instance: vk.Instance, device: vk.Device, physDev: vk.PhysicalDevice, apiVersion: u32) !Allocator {
    var allocator: Allocator = undefined;

    const res = vma.vmaCreateAllocator(&.{
        .instance = @ptrCast(instance),
        .device = @ptrCast(device),
        .physicalDevice = @ptrCast(physDev),
        .vulkanApiVersion = apiVersion,
        .pVulkanFunctions = &vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(vk.vkGetInstanceProcAddr),

            .vkGetDeviceProcAddr = @ptrCast(vk.vkGetDeviceProcAddr),
            .vkGetPhysicalDeviceProperties = @ptrCast(vk.vkGetPhysicalDeviceProperties),
            .vkGetPhysicalDeviceMemoryProperties = @ptrCast(vk.vkGetPhysicalDeviceMemoryProperties),
            .vkGetPhysicalDeviceMemoryProperties2KHR = @ptrCast(vk.vkGetPhysicalDeviceMemoryProperties2),

            .vkAllocateMemory = @ptrCast(vk.vkAllocateMemory),
            .vkFreeMemory = @ptrCast(vk.vkFreeMemory),
            .vkBindBufferMemory = @ptrCast(vk.vkBindBufferMemory),
            .vkBindBufferMemory2KHR = @ptrCast(vk.vkBindBufferMemory2),
            .vkBindImageMemory = @ptrCast(vk.vkBindImageMemory),
            .vkBindImageMemory2KHR = @ptrCast(vk.vkBindImageMemory2),
            .vkCmdCopyBuffer = @ptrCast(vk.vkCmdCopyBuffer),
            .vkCreateBuffer = @ptrCast(vk.vkCreateBuffer),
            .vkDestroyBuffer = @ptrCast(vk.vkDestroyBuffer),
            .vkCreateImage = @ptrCast(vk.vkCreateImage),
            .vkDestroyImage = @ptrCast(vk.vkDestroyImage),
            .vkGetBufferMemoryRequirements = @ptrCast(vk.vkGetBufferMemoryRequirements),
            .vkGetBufferMemoryRequirements2KHR = @ptrCast(vk.vkGetBufferMemoryRequirements2),
            .vkGetImageMemoryRequirements = @ptrCast(vk.vkGetImageMemoryRequirements),
            .vkGetImageMemoryRequirements2KHR = @ptrCast(vk.vkGetImageMemoryRequirements2),
            .vkMapMemory = @ptrCast(vk.vkMapMemory),
            .vkUnmapMemory = @ptrCast(vk.vkUnmapMemory),
            .vkInvalidateMappedMemoryRanges = @ptrCast(vk.vkInvalidateMappedMemoryRanges),
            .vkFlushMappedMemoryRanges = @ptrCast(vk.vkFlushMappedMemoryRanges),
            //.vkGetDeviceBufferMemoryRequirements = @ptrCast(vk.vkGetDeviceBufferMemoryRequirements),
            //.vkGetDeviceImageMemoryRequirements = @ptrCast(vk.vkGetDeviceImageMemoryRequirements),
        },
    }, &allocator);

    if (@as(vk.Result, @enumFromInt(res)) != vk.Result.SUCCESS) {
        return error.AllocatorCreateError;
    }

    return allocator;
}

pub inline fn createImage(imageCreateInfo: *const vk.ImageCreateInfo, allocationCreateInfo: *const AllocationCreateInfo) !ImageAllocation {
    var im: vk.Image = undefined;
    var all: vma.VmaAllocation = undefined;
    var allInfo: vma.VmaAllocationInfo = undefined;

    if (vma.vmaCreateImage(
        vkAllocator,
        @ptrCast(imageCreateInfo),
        allocationCreateInfo,
        @ptrCast(&im),
        &all,
        &allInfo,
    ) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.ImageAllocationFailed;
    }

    return ImageAllocation{ .image = im, .allocation = all };
    //image.allInfo = allInfo;
}

pub inline fn destroyImage(image: ImageAllocation) void {
    vma.vmaDestroyImage(vkAllocator, @ptrCast(image.image), image.allocation);
}

pub inline fn createBuffer(bufferCreateInfo: *const vk.BufferCreateInfo, allocationCreateInfo: *const AllocationCreateInfo) !BufferAllocation {
    var buf: vk.Buffer = undefined;
    var all: vma.VmaAllocation = undefined;
    var allInfo: vma.VmaAllocationInfo = undefined;

    if (vma.vmaCreateBuffer(
        vkAllocator,
        @ptrCast(bufferCreateInfo),
        allocationCreateInfo,
        @ptrCast(&buf),
        &all,
        &allInfo,
    ) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.BufferAllocationFailed;
    }

    return BufferAllocation{ .buffer = buf, .allocation = all };
}

pub inline fn destroyBuffer(buffer: BufferAllocation) void {
    vma.vmaDestroyBuffer(vkAllocator, @ptrCast(buffer.buffer), buffer.allocation);
}

pub inline fn uploadMemory(buffer: BufferAllocation, datas: []const []const u8, initialOffset: u32) !u32 {
    var deviceMemory: *anyopaque = undefined;
    if (vma.vmaMapMemory(vkAllocator, buffer.allocation, @ptrCast(&deviceMemory)) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.MemoryMapFailed;
    }

    var offset: u32 = initialOffset;
    for (datas) |d| {
        const destMemory = @as([*]u8, @ptrCast(deviceMemory))[offset .. offset + d.len];
        mem.copyForwards(u8, destMemory, d);
        offset += @intCast(d.len);
    }

    vma.vmaUnmapMemory(vkAllocator, buffer.allocation);

    return offset;
}

pub inline fn startReadMemory(buffer: BufferAllocation, size: usize) ![]u8 {
    var deviceMemory: *anyopaque = undefined;
    if (vma.vmaMapMemory(vkAllocator, buffer.allocation, @ptrCast(&deviceMemory)) != @intFromEnum(vk.Result.SUCCESS)) {
        return error.MemoryMapFailed;
    }

    return @as([*]u8, @ptrCast(deviceMemory))[0..size];
}

pub inline fn stopReadMemory(buffer: BufferAllocation) void {
    vma.vmaUnmapMemory(vkAllocator, buffer.allocation);
}
