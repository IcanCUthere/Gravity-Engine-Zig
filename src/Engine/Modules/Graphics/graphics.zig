const util = @import("util");

const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");
const glfw = @import("zglfw");

const core = @import("CoreModule");

pub const gfx = @import("Components/Internal/interface.zig");
pub const evnt = @import("Components/Internal/event.zig");
pub const InputState = @import("Components/Internal/inputState.zig").InputState;
pub const Camera = @import("Components/Camera.zig").Camera;
pub const Viewport = @import("Components/Viewport.zig").Viewport;
pub const Renderer = @import("Components/Renderer.zig").Renderer;
pub const Model = @import("Components/Model.zig").Model;
pub const Material = @import("Components/Material.zig").Material;
pub const Texture = @import("Components/Texture.zig").Texture;
pub const ModelInstance = @import("Components/ModelInstance.zig").ModelInstance;

pub const Graphics = struct {
    pub const name: []const u8 = "graphics";
    pub const dependencies = [_][]const u8{"core"};

    var _scene: *flecs.world_t = undefined;

    const components = [_]type{
        Viewport,
        Camera,
        Material,
        Texture,
        Model,
        ModelInstance,
    };

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try glfw.init();
        try gfx.init();

        _scene = scene;

        inline for (components) |comp| {
            comp.register(scene);
        }

        mainCamera = flecs.new_entity(scene, "Main Camera");
        flecs.add_pair(scene, mainCamera, flecs.IsA, Camera.getPrefab());

        var viewport = try Viewport.init(
            "Gravity Control",
            1000,
            1000,
            3,
            1,
            onEvent,
        );
        viewport.setCursorEnabled(false);

        try Renderer.init(viewport.getFormat());

        viewport.setRenderPass(Renderer._renderPass);

        mainViewport = flecs.new_entity(scene, "Main Viewport");
        flecs.add_pair(scene, mainViewport, flecs.IsA, Viewport.getPrefab());
        _ = flecs.set(scene, mainViewport, Viewport, viewport);

        var desc = flecs.system_desc_t{};
        desc.callback = flecs.SystemImpl(Renderer.render).exec;
        desc.query.filter.terms[0] = flecs.term_t{
            .id = flecs.id(ModelInstance),
            .inout = .In,
        };
        desc.query.filter.terms[1] = flecs.term_t{
            .id = flecs.id(Model),
            .inout = .In,
        };
        desc.query.filter.terms[2] = flecs.term_t{
            .id = flecs.id(Material),
            .inout = .In,
        };
        desc.query.filter.terms[3] = flecs.term_t{
            .id = flecs.id(Viewport),
            .inout = .In,
            .src = flecs.term_id_t{
                .id = mainViewport,
            },
        };
        desc.query.filter.instanced = true;

        var desc2 = flecs.system_desc_t{};
        desc2.callback = flecs.SystemImpl(updateFOW).exec;
        desc2.query.filter.terms[0] = flecs.term_t{
            .id = flecs.id(Camera),
            .inout = .InOut,
            .src = flecs.term_id_t{
                .id = mainCamera,
            },
        };
        desc2.query.filter.terms[1] = flecs.term_t{
            .id = flecs.id(Viewport),
            .inout = .InOut,
        };

        desc2.query.filter.instanced = true;

        flecs.ADD_SYSTEM(scene, "Upload Events", flecs.OnLoad, uploadEvents);
        flecs.SYSTEM(scene, "Update FOV", flecs.PostLoad, &desc2);

        inline for (components) |comp| {
            flecs.ADD_SYSTEM(scene, "Update " ++ @typeName(comp), flecs.PreStore, comp.onUpdate);
        }

        flecs.ADD_SYSTEM(scene, "Transfer Data", flecs.PreStore, Renderer.updateData);
        flecs.ADD_SYSTEM(scene, "Begin Frame", flecs.PreStore, Renderer.beginFrame);
        flecs.ADD_SYSTEM(scene, "Start Rendering", flecs.PreStore, Renderer.startRendering);

        flecs.SYSTEM(scene, "Render", flecs.OnStore, &desc);

        flecs.ADD_SYSTEM(scene, "Stop Rendering", core.Pipeline.postStore, Renderer.stopRendering);
        flecs.ADD_SYSTEM(scene, "End Frame", core.Pipeline.postStore, Renderer.endFrame);

        flecs.ADD_SYSTEM(scene, "Clear Events", core.Pipeline.postStore, clearEvents);

        BufferedEventData.mouseX = viewport.getMousePosition()[0];
        BufferedEventData.mouseY = viewport.getMousePosition()[1];
        BufferedEventData.windowSizeX = viewport.getWidth();
        BufferedEventData.windowSizeY = viewport.getHeight();
    }

    pub fn preDeinit() !void {
        try Renderer.deinit();
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try util.module.cleanUpComponent(comp, _scene);
        }

        gfx.deinit();
        glfw.terminate();
    }

    const BufferedEventData = struct {
        var deltaMouseX: f64 = 0;
        var deltaMouseY: f64 = 0;

        var mouseX: f64 = 0;
        var mouseY: f64 = 0;

        var keyStates: [400]evnt.KeyState = [1]evnt.KeyState{.{}} ** 400;

        var deltaWindowSizeX: i32 = 0;
        var deltaWindowSizeY: i32 = 0;

        var windowSizeX: u32 = 0;
        var windowSizeY: u32 = 0;
    };

    fn updateFOW(_: *flecs.iter_t, cameras: []Camera, viewports: []Viewport) void {
        if (InputState.deltaViewportX != 0 or InputState.deltaViewportY != 0) {
            const aspectRatio = @as(f32, @floatFromInt(InputState.viewportX)) / @as(f32, @floatFromInt(InputState.viewportY));
            cameras[0].setProjectionMatrix(45.0, aspectRatio, 1.0, 10000.0);
            viewports[0].resize(InputState.viewportX, InputState.viewportY);
        }
    }

    fn uploadEvents(_: *flecs.iter_t) !void {
        //calls onEvent
        Viewport.pollEvents();

        InputState.deltaMouseX = BufferedEventData.deltaMouseX;
        InputState.deltaMouseY = BufferedEventData.deltaMouseY;

        InputState.mouseX = BufferedEventData.mouseX;
        InputState.mouseY = BufferedEventData.mouseY;

        InputState.keyStates = BufferedEventData.keyStates;

        InputState.viewportX = BufferedEventData.windowSizeX;
        InputState.viewportY = BufferedEventData.windowSizeY;

        InputState.deltaViewportX = BufferedEventData.deltaWindowSizeX;
        InputState.deltaViewportY = BufferedEventData.deltaWindowSizeY;
    }

    fn clearEvents(_: *flecs.iter_t) void {
        BufferedEventData.deltaMouseX = 0;
        BufferedEventData.deltaMouseY = 0;

        BufferedEventData.deltaWindowSizeX = 0;
        BufferedEventData.deltaWindowSizeY = 0;

        for (&BufferedEventData.keyStates) |*s| {
            s.isPress = false;
            s.isRelease = false;
            s.isRepeat = false;
        }

        InputState.deltaMouseX = 0;
        InputState.deltaMouseY = 0;

        for (&InputState.keyStates) |*s| {
            s.isPress = false;
            s.isRelease = false;
            s.isRepeat = false;
        }
    }

    fn onEvent(e: evnt.Event) void {
        switch (e) {
            .windowResize => |wre| onWindowResize(wre),
            .windowClose => |wce| onWindowClose(wce),
            .key => |ke| onKey(ke),
            .mousePosition => |mpe| onMousePosition(mpe),
        }
    }

    fn onWindowResize(e: evnt.WindowResizeEvent) void {
        BufferedEventData.deltaWindowSizeX = @as(i32, @intCast(e.width)) - @as(i32, @intCast(BufferedEventData.windowSizeX));
        BufferedEventData.deltaWindowSizeY = @as(i32, @intCast(e.height)) - @as(i32, @intCast(BufferedEventData.windowSizeY));

        BufferedEventData.windowSizeX = e.width;
        BufferedEventData.windowSizeY = e.height;
    }

    fn onWindowClose(_: evnt.WindowCloseEvent) void {
        flecs.quit(_scene);
    }

    fn onKey(e: evnt.KeyEvent) void {
        if (e.action == .Pressed) {
            BufferedEventData.keyStates[@intFromEnum(e.key)].isPress = true;
            BufferedEventData.keyStates[@intFromEnum(e.key)].isHold = true;
        } else if (e.action == .Released) {
            BufferedEventData.keyStates[@intFromEnum(e.key)].isHold = false;
            BufferedEventData.keyStates[@intFromEnum(e.key)].isPress = false;
            BufferedEventData.keyStates[@intFromEnum(e.key)].isRelease = true;
        } else if (e.action == .Repeated) {
            BufferedEventData.keyStates[@intFromEnum(e.key)].isRepeat = true;
        }
    }

    fn onMousePosition(e: evnt.MousePositionEvent) void {
        BufferedEventData.deltaMouseX = e.x - BufferedEventData.mouseX;
        BufferedEventData.deltaMouseY = e.y - BufferedEventData.mouseY;

        BufferedEventData.mouseX = e.x;
        BufferedEventData.mouseY = e.y;
    }

    pub var mainCamera: flecs.entity_t = undefined;
    pub var mainViewport: flecs.entity_t = undefined;
};
