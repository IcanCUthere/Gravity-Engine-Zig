const util = @import("util");

const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");
const glfw = @import("zglfw");

const core = @import("CoreModule");

pub const shaders = @import("Components/Internal/shaderStorage.zig");
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

    pub var baseMaterial: flecs.entity_t = undefined;

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        try glfw.init();
        try gfx.init();
        try shaders.init();

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

        flecs.ADD_SYSTEM(scene, "Begin Frame", flecs.PreStore, Renderer.beginFrame);
        flecs.ADD_SYSTEM(scene, "Transfer Data", flecs.PreStore, Renderer.updateData);

        flecs.ADD_SYSTEM(scene, "Start Rendering", flecs.OnStore, Renderer.startRendering);
        flecs.SYSTEM(scene, "Render", flecs.OnStore, &desc);
        flecs.ADD_SYSTEM(scene, "Stop Rendering", flecs.OnStore, Renderer.stopRendering);

        flecs.ADD_SYSTEM(scene, "End Frame", core.Pipeline.postStore, Renderer.endFrame);
        flecs.ADD_SYSTEM(scene, "Clear Events", core.Pipeline.postStore, clearEvents);

        InputState.mouseX = viewport.getMousePosition()[0];
        InputState.mouseY = viewport.getMousePosition()[1];
        InputState.viewportX = viewport.getWidth();
        InputState.viewportY = viewport.getHeight();

        baseMaterial = try Material.new(
            "BaseMaterial",
            shaders.get("default.vert"),
            shaders.get("default.frag"),
        );
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

        shaders.deinit();
        gfx.deinit();
        glfw.terminate();
    }

    fn updateFOW(_: *flecs.iter_t, cameras: []Camera, viewports: []Viewport) void {
        if (InputState.deltaViewportX != 0 or InputState.deltaViewportY != 0) {
            const aspectRatio = @as(f32, @floatFromInt(InputState.viewportX)) / @as(f32, @floatFromInt(InputState.viewportY));
            cameras[0].setProjectionMatrix(45.0, aspectRatio, 1.0, 10000.0);
            viewports[0].resize(InputState.viewportX, InputState.viewportY);
        }
    }

    fn uploadEvents(_: *flecs.iter_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Poll events", 0x00_ff_ff_00);
        defer tracy_zone.End();

        //calls onEvent
        Viewport.pollEvents();
    }

    fn clearEvents(_: *flecs.iter_t) void {
        InputState.deltaMouseX = 0;
        InputState.deltaMouseY = 0;

        InputState.deltaViewportX = 0;
        InputState.deltaViewportY = 0;

        for (&InputState.keyStates) |*s| {
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
        InputState.deltaViewportX = @as(i32, @intCast(e.width)) - @as(i32, @intCast(InputState.viewportX));
        InputState.deltaViewportY = @as(i32, @intCast(e.height)) - @as(i32, @intCast(InputState.viewportY));

        InputState.viewportX = e.width;
        InputState.viewportY = e.height;
    }

    fn onWindowClose(_: evnt.WindowCloseEvent) void {
        flecs.quit(_scene);
    }

    fn onKey(e: evnt.KeyEvent) void {
        if (e.action == .Pressed) {
            InputState.keyStates[@intFromEnum(e.key)].isPress = true;
            InputState.keyStates[@intFromEnum(e.key)].isHold = true;
        } else if (e.action == .Released) {
            InputState.keyStates[@intFromEnum(e.key)].isHold = false;
            InputState.keyStates[@intFromEnum(e.key)].isPress = false;
            InputState.keyStates[@intFromEnum(e.key)].isRelease = true;
        } else if (e.action == .Repeated) {
            InputState.keyStates[@intFromEnum(e.key)].isRepeat = true;
        }
    }

    fn onMousePosition(e: evnt.MousePositionEvent) void {
        InputState.deltaMouseX = e.x - InputState.mouseX;
        InputState.deltaMouseY = e.y - InputState.mouseY;

        InputState.mouseX = e.x;
        InputState.mouseY = e.y;
    }

    pub var mainCamera: flecs.entity_t = undefined;
    pub var mainViewport: flecs.entity_t = undefined;
};
