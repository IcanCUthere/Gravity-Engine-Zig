const util = @import("util");
const mem = util.mem;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const gfx = @import("Internal/interface.zig");
const evnt = @import("Internal/event.zig");

fn onEvent(it: *flecs.iter_t, viewports: []Viewport) !void {
    const event: flecs.entity_t = it.event;

    for (viewports) |*v| {
        if (event == flecs.OnRemove) {
            try v.deinit();
        }
    }
}

pub const Viewport = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "Viewport");
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);

        var setObsDesc = flecs.observer_desc_t{
            .query = flecs.query_desc_t{
                .terms = [1]flecs.term_t{
                    flecs.term_t{
                        .id = flecs.id(Self),
                    },
                } ++ ([1]flecs.term_t{.{}} ** 31),
            },
            .events = [_]u64{flecs.OnSet} ++ ([1]u64{0} ** 7),
            .callback = flecs.SystemImpl(onEvent).exec,
        };

        _ = flecs.OBSERVER(scene, "viewport events", &setObsDesc);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    const SwapchainData = struct {
        swapchain: gfx.SwapchainKHR = null,
        depthBuffer: gfx.ImageAllocation = mem.zeroes(gfx.ImageAllocation),
        imageViews: []gfx.ImageView = ([_]gfx.ImageView{})[0..],
        framebuffers: []gfx.Framebuffer = ([_]gfx.Framebuffer{})[0..],
        presentIndex: u32 = undefined,

        fn zeroed() SwapchainData {
            return mem.zeroes(SwapchainData);
        }

        fn deinit(self: *SwapchainData) !void {
            for (self.imageViews) |view| {
                try gfx.DestroyImageView(view);
            }
            for (self.framebuffers) |frabuf| {
                try gfx.DestroyFramebuffer(frabuf);
            }
            gfx.destroyImage(gfx.vkAllocator, self.depthBuffer);
            try gfx.DestroySwapchainKHR(self.swapchain);

            util.mem.heap.free(self.framebuffers);
            util.mem.heap.free(self.imageViews);

            self.* = SwapchainData.zeroed();
        }
    };

    _window: *gfx.glfw.Window = undefined,
    _renderPass: gfx.RenderPass = undefined,
    _surface: gfx.SurfaceKHR = undefined,
    _format: gfx.Format = undefined,
    _presentQueue: gfx.Queue = undefined,
    _presentQueueIndex: u32 = undefined,
    _renderQueueIndex: u32 = undefined,

    _width: u32 = undefined,
    _height: u32 = undefined,
    _imageCount: u32 = undefined,
    _layerCount: u32 = undefined,
    _resized: bool = true,

    _swapchainData: []SwapchainData = ([_]SwapchainData{})[0..],
    _currentSwapchain: u32 = 0,

    pub fn getSurface(self: *Self) gfx.SurfaceKHR {
        return self._surface;
    }

    pub fn getWindow(self: Self) *const gfx.glfw.Window {
        return self._window;
    }

    pub fn getImageCount(self: Self) u32 {
        return @intCast(self._swapchainData[self._currentSwapchain].imageViews.len);
    }

    pub fn getHeight(self: Self) u32 {
        return self._height;
    }

    pub fn getWidth(self: Self) u32 {
        return self._width;
    }

    pub fn getFormat(self: Self) gfx.Format {
        return self._format;
    }

    //Not available until first nextFrame() call
    pub fn getFramebuffer(self: Self) gfx.Framebuffer {
        return self._swapchainData[self._currentSwapchain].framebuffers[self._swapchainData[self._currentSwapchain].presentIndex];
    }

    //Must be set before first nextFrame() call
    pub fn setRenderPass(self: *Self, renderPass: gfx.RenderPass) void {
        self._renderPass = renderPass;
    }

    pub fn init(title: [:0]const u8, width: u32, height: u32, imageCount: u32, layerCount: u32, callbackFn: evnt.CallbackFunction) !Viewport {
        const tracy_zone = tracy.ZoneNC(@src(), "Init Viewport", 0x00_ff_ff_00);
        defer tracy_zone.End();

        gfx.glfw.windowHint(gfx.glfw.WindowHint.client_api, gfx.glfw.ClientApi.no_api);
        //glfw.windowHint(glfw.WindowHint.decorated, 0);
        var window = try gfx.glfw.Window.create(@intCast(width), @intCast(height), title, null);

        const surface = try gfx.createSurface(window);

        var viewport = Viewport{
            ._window = window,
            ._surface = surface,
            ._width = width,
            ._height = height,
            ._imageCount = imageCount,
            ._layerCount = layerCount,
            ._renderQueueIndex = gfx.renderFamily,
        };

        const queueFamilyProperties = try gfx.GetPhysicalDeviceQueueFamilyProperties(
            gfx.physicalDevice,
            mem.fixedBuffer,
        );
        defer mem.fixedBuffer.free(queueFamilyProperties);

        if (try gfx.GetPhysicalDeviceSurfaceSupportKHR(gfx.physicalDevice, viewport._renderQueueIndex, viewport._surface) == gfx.TRUE) {
            viewport._presentQueue = try gfx.GetDeviceQueue(viewport._renderQueueIndex, 0);
            viewport._presentQueueIndex = viewport._renderQueueIndex;
        } else {
            for (queueFamilyProperties, 0..) |_, i| {
                if (try gfx.GetPhysicalDeviceSurfaceSupportKHR(gfx.physicalDevice, @intCast(i), viewport._surface) == gfx.TRUE) {
                    viewport._presentQueue = try gfx.GetDeviceQueue(viewport._renderQueueIndex, 0);
                    viewport._presentQueueIndex = @intCast(i);
                    break;
                }
            }
        }

        viewport._swapchainData = try util.mem.heap.alloc(Viewport.SwapchainData, viewport._imageCount);
        for (viewport._swapchainData) |*data| {
            data.* = Viewport.SwapchainData.zeroed();
        }

        viewport._format = (try viewport._pickFormat()).format;

        window.setUserPointer(@ptrCast(@constCast(&callbackFn)));

        _ = window.setFramebufferSizeCallback(struct {
            fn resize(wndw: *gfx.glfw.Window, _: i32, _: i32) callconv(.C) void {
                var extent = gfx.glfw.Window.getFramebufferSize(wndw);

                while (extent[0] == 0 or extent[1] == 0) {
                    extent = gfx.glfw.Window.getFramebufferSize(wndw);
                    gfx.glfw.waitEvents();
                }

                wndw.getUserPointer(evnt.CallbackFunction).?(evnt.Event{ .windowResize = evnt.WindowResizeEvent{
                    .width = @intCast(extent[0]),
                    .height = @intCast(extent[1]),
                } });
            }
        }.resize);

        _ = window.setCloseCallback(struct {
            fn close(wndw: *gfx.glfw.Window) callconv(.C) void {
                wndw.getUserPointer(evnt.CallbackFunction).?(evnt.Event{ .windowClose = evnt.WindowCloseEvent{} });
            }
        }.close);

        _ = window.setKeyCallback(struct {
            fn keyInput(wndw: *gfx.glfw.Window, key: gfx.glfw.Key, _: i32, action: gfx.glfw.Action, _: gfx.glfw.Mods) callconv(.C) void {
                if (@intFromEnum(key) == -1) {
                    return;
                }

                wndw.getUserPointer(evnt.CallbackFunction).?(evnt.Event{ .key = evnt.KeyEvent{
                    .key = @enumFromInt(@intFromEnum(key)),
                    .action = @enumFromInt(@intFromEnum(action)),
                } });
            }
        }.keyInput);

        _ = window.setMouseButtonCallback(struct {
            fn keyInput(wndw: *gfx.glfw.Window, key: gfx.glfw.MouseButton, action: gfx.glfw.Action, _: gfx.glfw.Mods) callconv(.C) void {
                if (@intFromEnum(key) == -1) {
                    return;
                }

                wndw.getUserPointer(evnt.CallbackFunction).?(evnt.Event{ .key = evnt.KeyEvent{
                    .key = @enumFromInt(@intFromEnum(key) + 1),
                    .action = @enumFromInt(@intFromEnum(action)),
                } });
            }
        }.keyInput);

        _ = window.setCursorPosCallback(struct {
            fn cureserPos(wndw: *gfx.glfw.Window, x: f64, y: f64) callconv(.C) void {
                wndw.getUserPointer(evnt.CallbackFunction).?(evnt.Event{ .mousePosition = evnt.MousePositionEvent{
                    .x = x,
                    .y = y,
                } });
            }
        }.cureserPos);

        return viewport;
    }

    pub fn deinit(self: *Self) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Deinit viewport", 0x00_ff_ff_00);
        defer tracy_zone.End();

        for (self._swapchainData) |*data| {
            try data.deinit();
        }
        util.mem.heap.free(self._swapchainData);

        try gfx.DestroySurfaceKHR(self._surface);
        self._window.destroy();
    }

    pub fn onUpdate(_: *flecs.iter_t, _: []Viewport) void {}

    pub fn pollEvents() void {
        gfx.glfw.pollEvents();
    }

    pub fn nextFrame(self: *Self, semaphore: gfx.Semaphore) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Acquire next frame", 0x00_ff_ff_00);
        defer tracy_zone.End();

        if (self._resized) {
            const nextIndex: u32 = (self._currentSwapchain + 1) % self._imageCount;
            const lastIndex: u32 = (self._currentSwapchain + self._imageCount - 1) % self._imageCount;

            try self._swapchainData[lastIndex].deinit();
            try self._swapchainData[nextIndex].deinit();
            try self._initSwapchainData(nextIndex);

            self._currentSwapchain = nextIndex;
            self._resized = false;
        }

        try gfx.AcquireNextImageKHR(
            self._swapchainData[self._currentSwapchain].swapchain,
            ~@as(u64, 0),
            semaphore,
            null,
            &self._swapchainData[self._currentSwapchain].presentIndex,
        );
    }

    pub fn presentImage(self: *Self, semaphores: *gfx.Semaphore, count: u32) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Present image", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _ = try gfx.QueuePresentKHR(
            self._presentQueue,
            &gfx.PresentInfoKHR{
                .pSwapchains = &[_]gfx.SwapchainKHR{self._swapchainData[self._currentSwapchain].swapchain},
                .pImageIndices = &[_]u32{self._swapchainData[self._currentSwapchain].presentIndex},
                .swapchainCount = 1,
                .pWaitSemaphores = @ptrCast(semaphores),
                .waitSemaphoreCount = count,
                .pResults = null,
            },
        );
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self._resized = true;
        self._width = width;
        self._height = height;
    }

    pub fn setCursorEnabled(self: Self, enabled: bool) !void {
        if (enabled) {
            try self._window.setInputMode(.cursor, .normal);
        } else {
            try self._window.setInputMode(.cursor, .disabled);
        }
    }

    pub fn getMousePosition(self: Self) [2]f64 {
        return self._window.getCursorPos();
    }

    pub fn close(self: *Self) void {
        self._window.hide();
    }

    fn _initSwapchainData(self: *Self, index: u32) !void {
        try self._swapchainData[index].deinit();

        self._swapchainData[index].swapchain = try self._createSwapchain(self._swapchainData[self._currentSwapchain].swapchain);

        const swapchainImages = try gfx.GetSwapchainImagesKHR(self._swapchainData[index].swapchain, mem.fixedBuffer);
        defer util.mem.fixedBuffer.free(swapchainImages);

        self._swapchainData[index].imageViews = try util.mem.heap.alloc(gfx.ImageView, swapchainImages.len + 1);
        self._swapchainData[index].framebuffers = try util.mem.heap.alloc(gfx.Framebuffer, swapchainImages.len);

        self._swapchainData[index].depthBuffer = try gfx.createImage(
            gfx.vkAllocator,
            &gfx.ImageCreateInfo{
                .imageType = gfx.ImageType.@"2d",
                .format = gfx.Format.D16Unorm,
                .extent = gfx.Extent3D{
                    .width = self._width,
                    .height = self._height,
                    .depth = 1,
                },
                .arrayLayers = self._layerCount,
                .mipLevels = 1,
                .samples = .@"1Bit",
                .tiling = gfx.ImageTiling.Optimal,
                .initialLayout = gfx.ImageLayout.Undefined,
                .usage = gfx.toFlags(&[_]gfx.ImageUsageFlagBits{.DepthStencilAttachmentBit}),
                .sharingMode = gfx.SharingMode.Exclusive,
                .pQueueFamilyIndices = null,
                .queueFamilyIndexCount = 0,
            },
            &.{
                .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
            },
        );

        self._swapchainData[index].imageViews[swapchainImages.len] = try gfx.CreateImageView(
            &.{
                .image = self._swapchainData[index].depthBuffer.image,
                .viewType = gfx.ImageViewType.@"2d",
                .format = gfx.Format.D16Unorm,
                .components = gfx.ComponentMapping{
                    .a = gfx.ComponentSwizzle.A,
                    .r = gfx.ComponentSwizzle.R,
                    .g = gfx.ComponentSwizzle.G,
                    .b = gfx.ComponentSwizzle.B,
                },
                .subresourceRange = gfx.ImageSubresourceRange{
                    .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.DepthBit}),
                    .baseArrayLayer = 0,
                    .layerCount = self._layerCount,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                },
            },
        );

        for (swapchainImages, 0..) |image, i| {
            self._swapchainData[index].imageViews[i] = try gfx.CreateImageView(
                &gfx.ImageViewCreateInfo{
                    .image = image,
                    .viewType = gfx.ImageViewType.@"2d",
                    .format = self._format,
                    .components = gfx.ComponentMapping{
                        .a = gfx.ComponentSwizzle.A,
                        .r = gfx.ComponentSwizzle.R,
                        .g = gfx.ComponentSwizzle.G,
                        .b = gfx.ComponentSwizzle.B,
                    },
                    .subresourceRange = gfx.ImageSubresourceRange{
                        .aspectMask = gfx.toFlags(&[_]gfx.ImageAspectFlagBits{.ColorBit}),
                        .baseArrayLayer = 0,
                        .layerCount = self._layerCount,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                    },
                },
            );

            self._swapchainData[index].framebuffers[i] = try gfx.CreateFramebuffer(
                &gfx.FramebufferCreateInfo{
                    .renderPass = self._renderPass,
                    .pAttachments = &[_]gfx.ImageView{
                        self._swapchainData[index].imageViews[i],
                        self._swapchainData[index].imageViews[swapchainImages.len],
                    },
                    .attachmentCount = 2,
                    .width = self._width,
                    .height = self._height,
                    .layers = self._layerCount,
                },
            );
        }
    }

    fn _pickFormat(self: *Self) !gfx.SurfaceFormatKHR {
        const surfaceFormats = try gfx.GetPhysicalDeviceSurfaceFormatsKHR(
            gfx.physicalDevice,
            self._surface,
            mem.fixedBuffer,
        );
        defer mem.fixedBuffer.free(surfaceFormats);

        return if (surfaceFormats[0].format == gfx.Format.Undefined) gfx.SurfaceFormatKHR{
            .format = gfx.Format.R8g8b8a8Unorm,
            .colorSpace = gfx.ColorSpaceKHR.colorSpaceSrgbNonlinearKhr,
        } else surfaceFormats[0];
    }

    fn _createSwapchain(self: *Self, oldSwapchain: gfx.SwapchainKHR) !gfx.SwapchainKHR {
        const surfaceFormat = try self._pickFormat();

        self._format = surfaceFormat.format;

        const presentModes = try gfx.GetPhysicalDeviceSurfacePresentModesKHR(
            gfx.physicalDevice,
            self._surface,
            mem.fixedBuffer,
        );

        const capabilities = try gfx.GetPhysicalDeviceSurfaceCapabilitiesKHR(
            gfx.physicalDevice,
            self._surface,
        );

        const presentModeOrder = [_]gfx.PresentModeKHR{
            gfx.PresentModeKHR.presentModeMailboxKhr,
            gfx.PresentModeKHR.presentModeImmediateKhr,
            gfx.PresentModeKHR.presentModeFifoKhr,
            gfx.PresentModeKHR.presentModeFifoRelaxedKhr,
            gfx.PresentModeKHR.presentModeSharedDemandRefreshKhr,
            gfx.PresentModeKHR.presentModeSharedContinuousRefreshKhr,
        };

        const alphaFlagOrder = [_]gfx.CompositeAlphaFlagBitsKHR{
            .OpaqueBitKhr,
            .InheritBitKhr,
            .PostMultipliedBitKhr,
            .PreMultipliedBitKhr,
        };

        if (self._imageCount > capabilities.maxImageCount and capabilities.maxImageCount != 0) {
            self._imageCount = capabilities.maxImageCount;
        } else if (self._imageCount < capabilities.minImageCount and capabilities.maxImageCount != 0) {
            self._imageCount = capabilities.minImageCount;
        }

        if (self._layerCount > capabilities.maxImageArrayLayers) {
            self._layerCount = capabilities.maxImageArrayLayers;
        }

        if (capabilities.currentExtent.height == 0xFFFFFFFF) {
            if (self._height > capabilities.maxImageExtent.height) {
                self._height = capabilities.maxImageExtent.height;
            } else if (self._height < capabilities.minImageExtent.height) {
                self._height = capabilities.minImageExtent.height;
            }
        } else {
            self._height = capabilities.currentExtent.height;
        }

        if (capabilities.currentExtent.width == 0xFFFFFFFF) {
            if (self._width > capabilities.maxImageExtent.width) {
                self._width = capabilities.maxImageExtent.width;
            } else if (self._width < capabilities.minImageExtent.width) {
                self._width = capabilities.minImageExtent.width;
            }
        } else {
            self._width = capabilities.currentExtent.width;
        }

        return try gfx.CreateSwapchainKHR(
            &gfx.SwapchainCreateInfoKHR{
                .surface = self._surface,
                .oldSwapchain = oldSwapchain,
                .minImageCount = self._imageCount,
                .imageArrayLayers = self._layerCount,
                .clipped = gfx.TRUE,
                .imageUsage = gfx.toFlags(&[_]gfx.ImageUsageFlagBits{.ColorAttachmentBit}),
                .imageExtent = gfx.Extent2D{ .height = self._height, .width = self._width },
                .imageFormat = self._format,
                .imageColorSpace = surfaceFormat.colorSpace,
                .compositeAlpha = loop: for (alphaFlagOrder) |flag| {
                    if ((gfx.toFlags(&[_]gfx.CompositeAlphaFlagBitsKHR{flag}) | capabilities.supportedCompositeAlpha) > 0) {
                        break :loop flag;
                    }
                } else return error.NoAlphaModeAvailable,
                .queueFamilyIndexCount = if (self._renderQueueIndex == self._presentQueueIndex) 1 else 2,
                .pQueueFamilyIndices = if (self._renderQueueIndex == self._presentQueueIndex) &[_]u32{self._renderQueueIndex} else &[_]u32{ self._renderQueueIndex, self._presentQueueIndex },
                .imageSharingMode = if (self._renderQueueIndex == self._presentQueueIndex) gfx.SharingMode.Exclusive else gfx.SharingMode.Concurrent,
                .preTransform = capabilities.currentTransform,
                .presentMode = loop: for (presentModeOrder) |desiredMode| {
                    for (presentModes) |availableMode| {
                        if (availableMode == desiredMode) {
                            break :loop availableMode;
                        }
                    }
                } else return error.NoPresentModeAvailable,
            },
        );
    }
};
