const flecs = @import("zflecs");
const tracy = @import("ztracy");
const gui = @import("zgui");
const core = @import("core");

const StateManager = @import("Components/StateManager.zig").StateManager;

const graphicsM = @import("GraphicsModule");
const gfx = graphicsM.gfx;

const std = @import("std");

pub const Editor = struct {
    pub const name: []const u8 = "editor";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var _scene: *flecs.world_t = undefined;

    var guiDescriptorPool: gfx.DescriptorPool = undefined;

    const components = [_]type{
        StateManager,
    };

    fn loader(n: [*:0]const u8, handle: *const anyopaque) ?*const anyopaque {
        return @ptrCast(gfx.baseDispatch.dispatch.vkGetInstanceProcAddr(@enumFromInt(@intFromPtr(handle)), n).?);
    }

    fn guiNextFrame(_: *flecs.iter_t, viewport: []graphicsM.Viewport) !void {
        gui.backend.newFrame(viewport[0].getWidth(), viewport[0].getHeight());

        var open: bool = true;
        gui.showDemoWindow(&open);

        gui.backend.draw(@ptrFromInt(@intFromEnum(graphicsM.Renderer.getCurrentCmdList())));

        gui.UpdatePlatformWindows();
        gui.RenderPlatformWindowsDefault();
    }

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        const viewport = flecs.get(_scene, graphicsM.Graphics.mainViewport, graphicsM.Viewport).?;

        const guiPoolSizes = [_]gfx.DescriptorPoolSize{
            gfx.DescriptorPoolSize{
                .type = .combined_image_sampler,
                .descriptor_count = 1,
            },
        };

        guiDescriptorPool = try gfx.device.createDescriptorPool(&gfx.DescriptorPoolCreateInfo{
            .p_pool_sizes = &guiPoolSizes,
            .pool_size_count = @intCast(guiPoolSizes.len),
            .max_sets = 1,
        }, null);

        gui.init(core.mem.heap);
        gui.io.setConfigFlags(gui.ConfigFlags{
            .viewport_enable = true,
            .dock_enable = true,
        });

        _ = gui.backend.loadFunctions(
            loader,
            @ptrFromInt(@as(usize, @intFromEnum(gfx.instance.handle))),
        );

        gui.backend.init(viewport.getWindow(), &gui.backend.VulkanInitInfo{
            .instance = @ptrFromInt(@intFromEnum(gfx.instance.handle)),
            .physical_device = @ptrFromInt(@intFromEnum(gfx.physicalDevice)),
            .device = @ptrFromInt(@intFromEnum(gfx.device.handle)),
            .queueFamily = gfx.renderFamily,
            .queue = @ptrFromInt(@intFromEnum(gfx.renderQueue)),
            .renderPass = @ptrFromInt(@intFromEnum(graphicsM.Renderer._renderPass)),
            .descriptorPool = @ptrFromInt(@intFromEnum(guiDescriptorPool)),
            .minImageCount = 2,
            .imageCount = 3,
        });

        std.log.info("HIER", .{});

        inline for (components) |comp| {
            comp.register(scene);
        }

        flecs.ADD_SYSTEM(_scene, "Gui new frame", flecs.OnStore, guiNextFrame);
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try core.moduleHelpers.cleanUpComponent(comp, _scene);
        }

        gui.backend.deinit();
        gui.deinit();

        gfx.device.destroyDescriptorPool(guiDescriptorPool, null);
    }
};
