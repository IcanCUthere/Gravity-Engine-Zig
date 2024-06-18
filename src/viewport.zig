const std = @import("std");
const glfw = @import("zglfw");
const gfx = @import("graphics.zig");
const mem = @import("memory.zig");

pub fn init(title: [:0]const u8, width: u32, height: u32, imageCount: u32, layerCount: u32) !Viewport {
    glfw.windowHint(glfw.WindowHint.client_api, @intFromEnum(glfw.ClientApi.no_api));
    //glfw.windowHint(glfw.WindowHint.decorated, 0);
    var window = try glfw.Window.create(@intCast(width), @intCast(height), title, null);

    _ = window.setFramebufferSizeCallback(struct {
        fn resize(wndw: *glfw.Window, _: i32, _: i32) callconv(.C) void {
            while (glfw.Window.getFramebufferSize(wndw)[0] == 0 or glfw.Window.getFramebufferSize(wndw)[1] == 0) {
                glfw.waitEvents();
            }
        }
    }.resize);

    const surface = try gfx.createSurface(gfx.instance, window);

    var viewport = Viewport{
        ._window = window,
        ._surface = surface,
        ._width = width,
        ._height = height,
        ._imageCount = imageCount,
        ._layerCount = layerCount,
        ._renderQueueIndex = gfx.renderFamily,
    };

    var family_count: u32 = undefined;
    gfx.instance.getPhysicalDeviceQueueFamilyProperties(gfx.physicalDevice, &family_count, null);
    const families = try mem.fba.alloc(gfx.QueueFamilyProperties, family_count);
    defer mem.fba.free(families);
    gfx.instance.getPhysicalDeviceQueueFamilyProperties(gfx.physicalDevice, &family_count, families.ptr);

    if (try gfx.instance.getPhysicalDeviceSurfaceSupportKHR(gfx.physicalDevice, viewport._renderQueueIndex, viewport._surface) == gfx.TRUE) {
        viewport._presentQueue = gfx.device.getDeviceQueue(viewport._renderQueueIndex, 0);
        viewport._presentQueueIndex = viewport._renderQueueIndex;
    } else {
        for (families, 0..) |_, i| {
            if (try gfx.instance.getPhysicalDeviceSurfaceSupportKHR(gfx.physicalDevice, @intCast(i), viewport._surface) == gfx.TRUE) {
                viewport._presentQueue = gfx.device.getDeviceQueue(viewport._renderQueueIndex, 0);
                viewport._presentQueueIndex = @intCast(i);
                break;
            }
        }
    }

    viewport._swapchainData = try mem.fba.alloc(Viewport.SwapchainData, viewport._imageCount);
    for (viewport._swapchainData) |*data| {
        data.* = Viewport.SwapchainData.init();
    }

    viewport._format = (try viewport._pickFormat()).format;

    return viewport;
}

pub const Viewport = struct {
    const Self = @This();
    const SwapchainData = struct {
        swapchain: gfx.SwapchainKHR = gfx.SwapchainKHR.null_handle,
        depthBuffer: gfx.ImageAllocation = std.mem.zeroes(gfx.ImageAllocation),
        imageViews: []gfx.ImageView = ([_]gfx.ImageView{})[0..],
        framebuffers: []gfx.Framebuffer = ([_]gfx.Framebuffer{})[0..],
        presentIndex: u32 = undefined,

        fn init() SwapchainData {
            return std.mem.zeroes(SwapchainData);
        }

        fn deinit(self: *SwapchainData) void {
            for (self.imageViews) |view| {
                gfx.device.destroyImageView(view, null);
            }
            for (self.framebuffers) |frabuf| {
                gfx.device.destroyFramebuffer(frabuf, null);
            }
            gfx.destroyImage(gfx.vkAllocator, self.depthBuffer);
            gfx.device.destroySwapchainKHR(self.swapchain, null);

            mem.fba.free(self.framebuffers);
            mem.fba.free(self.imageViews);
        }
    };

    _window: *glfw.Window = undefined,
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

    pub fn getWindow(self: *Self) glfw.Window {
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

    //Not available until first nextFram() call
    pub fn getFramebuffer(self: Self) gfx.Framebuffer {
        return self._swapchainData[self._currentSwapchain].framebuffers[self._swapchainData[self._currentSwapchain].presentIndex];
    }

    //Must be set before first nextFrame() call
    pub fn setRenderPass(self: *Self, renderPass: gfx.RenderPass) void {
        self._renderPass = renderPass;
    }

    pub fn deinit(self: *Self) void {
        for (self._swapchainData) |*data| {
            data.deinit();
        }
        mem.fba.free(self._swapchainData);

        gfx.instance.destroySurfaceKHR(self._surface, null);
        self._window.destroy();
    }

    pub fn nextFrame(self: *Self, semaphore: gfx.Semaphore) !void {
        glfw.pollEvents();

        if (self._resized) {
            const nextIndex: u32 = (self._currentSwapchain + 1) % self._imageCount;

            self._swapchainData[nextIndex].deinit();
            try self._initSwapchainData(nextIndex);

            self._currentSwapchain = nextIndex;
            self._resized = false;
        }

        const res = try gfx.device.acquireNextImageKHR(self._swapchainData[self._currentSwapchain].swapchain, ~@as(u64, 0), semaphore, gfx.Fence.null_handle);
        self._swapchainData[self._currentSwapchain].presentIndex = res.image_index;
    }

    pub fn presentImage(self: *Self, semaphores: *gfx.Semaphore, count: u32) !void {
        _ = try gfx.device.queuePresentKHR(self._presentQueue, &.{
            .p_swapchains = &.{self._swapchainData[self._currentSwapchain].swapchain},
            .p_image_indices = &.{self._swapchainData[self._currentSwapchain].presentIndex},
            .swapchain_count = 1,
            .p_wait_semaphores = @ptrCast(semaphores),
            .wait_semaphore_count = count,
            .p_results = null,
        });
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self._resized = true;
        self._width = width;
        self._height = height;
    }

    fn _initSwapchainData(self: *Self, index: u32) !void {
        self._swapchainData[index].deinit();

        self._swapchainData[index].swapchain = try self._createSwapchain(gfx.SwapchainKHR.null_handle);

        var imageCount: u32 = undefined;
        _ = try gfx.device.getSwapchainImagesKHR(self._swapchainData[index].swapchain, &imageCount, null);
        const swapchainImages = try mem.fba.alloc(gfx.Image, imageCount);
        self._swapchainData[index].imageViews = try mem.fba.alloc(gfx.ImageView, imageCount + 1);
        self._swapchainData[index].framebuffers = try mem.fba.alloc(gfx.Framebuffer, imageCount);
        defer mem.fba.free(swapchainImages);
        _ = try gfx.device.getSwapchainImagesKHR(self._swapchainData[index].swapchain, &imageCount, swapchainImages.ptr);

        self._swapchainData[index].depthBuffer = try gfx.createImage(gfx.vkAllocator, &.{
            .image_type = gfx.ImageType.@"2d",
            .format = gfx.Format.d16_unorm,
            .extent = gfx.Extent3D{ .width = self._width, .height = self._height, .depth = 1 },
            .array_layers = self._layerCount,
            .mip_levels = 1,
            .samples = gfx.SampleCountFlags{ .@"1_bit" = true },
            .tiling = gfx.ImageTiling.optimal,
            .initial_layout = gfx.ImageLayout.undefined,
            .usage = gfx.ImageUsageFlags{ .depth_stencil_attachment_bit = true },
            .sharing_mode = gfx.SharingMode.exclusive,
            .p_queue_family_indices = null,
            .queue_family_index_count = 0,
        }, &.{
            .usage = gfx.vma.VMA_MEMORY_USAGE_GPU_ONLY,
        });

        self._swapchainData[index].imageViews[imageCount] = try gfx.device.createImageView(&.{
            .image = self._swapchainData[index].depthBuffer.image,
            .view_type = gfx.ImageViewType.@"2d",
            .format = gfx.Format.d16_unorm,
            .components = gfx.ComponentMapping{
                .a = gfx.ComponentSwizzle.a,
                .r = gfx.ComponentSwizzle.r,
                .g = gfx.ComponentSwizzle.g,
                .b = gfx.ComponentSwizzle.b,
            },
            .subresource_range = gfx.ImageSubresourceRange{
                .aspect_mask = gfx.ImageAspectFlags{ .depth_bit = true },
                .base_array_layer = 0,
                .layer_count = self._layerCount,
                .base_mip_level = 0,
                .level_count = 1,
            },
        }, null);

        for (swapchainImages, 0..) |image, i| {
            self._swapchainData[index].imageViews[i] = try gfx.device.createImageView(&.{
                .image = image,
                .view_type = gfx.ImageViewType.@"2d",
                .format = self._format,
                .components = gfx.ComponentMapping{
                    .a = gfx.ComponentSwizzle.a,
                    .r = gfx.ComponentSwizzle.r,
                    .g = gfx.ComponentSwizzle.g,
                    .b = gfx.ComponentSwizzle.b,
                },
                .subresource_range = gfx.ImageSubresourceRange{
                    .aspect_mask = gfx.ImageAspectFlags{ .color_bit = true },
                    .base_array_layer = 0,
                    .layer_count = self._layerCount,
                    .base_mip_level = 0,
                    .level_count = 1,
                },
            }, null);

            self._swapchainData[index].framebuffers[i] = try gfx.device.createFramebuffer(&.{
                .render_pass = self._renderPass,
                .p_attachments = &.{
                    self._swapchainData[index].imageViews[i],
                    self._swapchainData[index].imageViews[imageCount],
                },
                .attachment_count = 2,
                .width = self._width,
                .height = self._height,
                .layers = self._layerCount,
            }, null);
        }
    }

    fn _pickFormat(self: *Self) !gfx.SurfaceFormatKHR {
        var formatCount: u32 = undefined;
        _ = try gfx.instance.getPhysicalDeviceSurfaceFormatsKHR(gfx.physicalDevice, self._surface, &formatCount, null);
        const surfaceFormats = try mem.fba.alloc(gfx.SurfaceFormatKHR, formatCount);
        defer mem.fba.free(surfaceFormats);
        _ = try gfx.instance.getPhysicalDeviceSurfaceFormatsKHR(gfx.physicalDevice, self._surface, &formatCount, surfaceFormats.ptr);
        return if (surfaceFormats[0].format == gfx.Format.undefined) gfx.SurfaceFormatKHR{ .format = gfx.Format.r8g8b8a8_unorm, .color_space = gfx.ColorSpaceKHR.srgb_nonlinear_khr } else surfaceFormats[0];
    }

    fn _createSwapchain(self: *Self, oldSwapchain: gfx.SwapchainKHR) !gfx.SwapchainKHR {
        const surfaceFormat = try self._pickFormat();

        self._format = surfaceFormat.format;

        var presentModeCount: u32 = undefined;
        _ = try gfx.instance.getPhysicalDeviceSurfacePresentModesKHR(gfx.physicalDevice, self._surface, &presentModeCount, null);
        const presentModes = try mem.fba.alloc(gfx.PresentModeKHR, presentModeCount);
        defer mem.fba.free(presentModes);
        _ = try gfx.instance.getPhysicalDeviceSurfacePresentModesKHR(gfx.physicalDevice, self._surface, &presentModeCount, presentModes.ptr);

        const capabilities = try gfx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(gfx.physicalDevice, self._surface);

        const presentModeOrder = [_]gfx.PresentModeKHR{
            gfx.PresentModeKHR.mailbox_khr,
            gfx.PresentModeKHR.immediate_khr,
            gfx.PresentModeKHR.fifo_khr,
            gfx.PresentModeKHR.fifo_relaxed_khr,
            gfx.PresentModeKHR.shared_demand_refresh_khr,
            gfx.PresentModeKHR.shared_continuous_refresh_khr,
        };

        const desiredAlphaFlags = gfx.CompositeAlphaFlagsKHR{ .opaque_bit_khr = true };

        if (self._imageCount > capabilities.max_image_count and capabilities.max_image_count != 0) {
            self._imageCount = capabilities.max_image_count;
        } else if (self._imageCount < capabilities.min_image_count and capabilities.max_image_count != 0) {
            self._imageCount = capabilities.min_image_count;
        }

        if (self._layerCount > capabilities.max_image_array_layers) {
            self._layerCount = capabilities.max_image_array_layers;
        }

        if (capabilities.current_extent.height == 0xFFFFFFFF) {
            if (self._height > capabilities.max_image_extent.height) {
                self._height = capabilities.max_image_extent.height;
            } else if (self._height < capabilities.min_image_extent.height) {
                self._height = capabilities.min_image_extent.height;
            }
        } else {
            self._height = capabilities.current_extent.height;
        }

        if (capabilities.current_extent.width == 0xFFFFFFFF) {
            if (self._width > capabilities.max_image_extent.width) {
                self._width = capabilities.max_image_extent.width;
            } else if (self._width < capabilities.min_image_extent.width) {
                self._width = capabilities.min_image_extent.width;
            }
        } else {
            self._width = capabilities.current_extent.width;
        }

        return try gfx.device.createSwapchainKHR(&.{
            .surface = self._surface,
            .old_swapchain = oldSwapchain,
            .min_image_count = self._imageCount,
            .image_array_layers = self._layerCount,
            .clipped = gfx.TRUE,
            .image_usage = gfx.ImageUsageFlags{ .color_attachment_bit = true },
            .image_extent = gfx.Extent2D{ .height = self._height, .width = self._width },
            .image_format = self._format,
            .image_color_space = surfaceFormat.color_space,
            .composite_alpha = desiredAlphaFlags.intersect(capabilities.supported_composite_alpha),
            .queue_family_index_count = if (self._renderQueueIndex == self._presentQueueIndex) 1 else 2,
            .p_queue_family_indices = if (self._renderQueueIndex == self._presentQueueIndex) &.{self._renderQueueIndex} else &.{ self._renderQueueIndex, self._presentQueueIndex },
            .image_sharing_mode = if (self._renderQueueIndex == self._presentQueueIndex) gfx.SharingMode.exclusive else gfx.SharingMode.concurrent,
            .pre_transform = capabilities.current_transform,
            .present_mode = loop: for (presentModeOrder) |desiredMode| {
                for (presentModes) |availableMode| {
                    if (availableMode == desiredMode) {
                        break :loop availableMode;
                    }
                }
            } else return error.NoPresentModeAvailable,
        }, null);
    }
};
