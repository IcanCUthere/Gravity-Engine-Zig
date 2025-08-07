const util = @import("util");

const flecs = @import("zflecs");
const stbi = @import("zstbi");
const tracy = @import("ztracy");
const glfw = @import("zglfw");

const core = @import("CoreModule");

pub const shaders = @import("Internal/shaderStorage.zig");
pub const gfx = @import("Internal/interface.zig");
pub const evnt = @import("Internal/event.zig");
pub const InputState = @import("Internal/inputState.zig").InputState;

pub const Camera = @import("Components/Camera.zig").Camera;
pub const Viewport = @import("Components/Viewport.zig").Viewport;
pub const Renderer = @import("Components/Renderer.zig").Renderer;
pub const Model = @import("Components/Model.zig").Model;
pub const Material = @import("Components/Material.zig").Material;
pub const Texture = @import("Components/Texture.zig").Texture;
pub const ModelInstance = @import("Components/ModelInstance.zig").ModelInstance;

pub const ModelEntity = @import("Entities/Model.zig").Model;
pub const CameraEntity = @import("Entities/Camera.zig").Camera;

pub const name: [*:0]const u8 = "graphics";
pub const dependencies = [_][*:0]const u8{"core"};

comptime {
    // We only want to export functions in from the actual module
    // Name clashes with other importet modules occur otherwise
    if (util.mem.eql(u8, util.mem.sliceTo(@import("root").name, 0), util.mem.sliceTo(name, 0))) {
        @export(&getName, .{ .name = "getName", .linkage = .strong });
        @export(&getDependencies, .{ .name = "getDependencies", .linkage = .strong });
        @export(&getDependencyCount, .{ .name = "getDependencyCount", .linkage = .strong });

        @export(&load, .{ .name = "load", .linkage = .strong });
        @export(&start, .{ .name = "start", .linkage = .strong });
        @export(&stop, .{ .name = "stop", .linkage = .strong });
        @export(&unload, .{ .name = "unload", .linkage = .strong });
    }
}

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

fn getName() callconv(.c) [*:0]const u8 {
    return name;
}

fn getDependencies() callconv(.c) [*]const [*:0]const u8 {
    return (&dependencies).ptr;
}

fn getDependencyCount() callconv(.c) usize {
    return dependencies.len;
}

fn load(scene: *flecs.world_t) callconv(.c) bool {
    const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Init", 0x00_ff_ff_00);
    defer tracy_zone.End();

    _ = flecs.init();
    _scene = scene;

    glfw.init() catch return false;
    gfx.init() catch return false;
    shaders.init() catch return false;

    try util.module.registerComponents(scene, &components);

    util.log.info("Model: {d}", .{flecs.id(Model)});
    util.log.info("ModelInstance: {d}", .{flecs.id(ModelInstance)});
    util.log.info("Viewport: {d}", .{flecs.id(Viewport)});
    util.log.info("Transform: {d}", .{flecs.id(core.Transform)});

    var viewport = Viewport.init(
        "Gravity Control",
        1000,
        1000,
        3,
        1,
        onEvent,
    ) catch return false;
    viewport.setCursorEnabled(false) catch return false;

    Renderer.init(viewport.getFormat()) catch return false;

    viewport.setRenderPass(Renderer._renderPass);

    mainViewport = flecs.new_entity(scene, "Main Viewport");

    _ = flecs.set(scene, mainViewport, Viewport, viewport);

    mainCamera = CameraEntity.init(scene, "MainCamera") catch return false;

    var desc = flecs.system_desc_t{};

    desc.callback = flecs.SystemImpl(Renderer.render).exec;

    desc.query.terms[0] = flecs.term_t{
        .id = flecs.id(ModelInstance),
        .inout = .In,
    };
    desc.query.terms[1] = flecs.term_t{
        .id = flecs.id(Model),
        .inout = .In,
    };
    desc.query.terms[2] = flecs.term_t{
        .id = flecs.id(Material),
        .inout = .In,
    };
    desc.query.terms[3] = flecs.term_t{
        .id = flecs.id(Viewport),
        .inout = .In,
        .src = flecs.term_ref_t{
            .id = mainViewport,
        },
    };

    util.log.info("HIIIIEIR", .{});

    //TODO: Is this right?
    desc.query.flags = flecs.EcsIterIsInstanced;

    var desc2 = flecs.system_desc_t{};
    desc2.callback = flecs.SystemImpl(updateFOW).exec;
    desc2.query.terms[0] = flecs.term_t{
        .id = flecs.id(Camera),
        .inout = .InOut,
        .src = flecs.term_ref_t{
            .id = mainCamera,
        },
    };
    desc2.query.terms[1] = flecs.term_t{
        .id = flecs.id(Viewport),
        .inout = .InOut,
    };

    desc2.query.flags = flecs.EcsIterIsInstanced;

    util.log.info("HIIIIEIR", .{});

    _ = flecs.ADD_SYSTEM(scene, "Upload Events", flecs.OnLoad, uploadEvents);
    _ = flecs.SYSTEM(scene, "Update FOV", flecs.PostLoad, &desc2);

    inline for (components) |comp| {
        _ = flecs.ADD_SYSTEM(scene, "Update " ++ @typeName(comp), flecs.PreStore, comp.onUpdate);
    }

    _ = flecs.ADD_SYSTEM(scene, "Begin Frame", flecs.PreStore, Renderer.beginFrame);
    _ = flecs.ADD_SYSTEM(scene, "Transfer Data", flecs.PreStore, Renderer.updateData);

    _ = flecs.ADD_SYSTEM(scene, "Start Rendering", flecs.OnStore, Renderer.startRendering);
    _ = flecs.SYSTEM(scene, "Render", flecs.OnStore, &desc);
    _ = flecs.ADD_SYSTEM(scene, "Stop Rendering", flecs.OnStore, Renderer.stopRendering);

    _ = flecs.ADD_SYSTEM(scene, "End Frame", core.Pipeline.postStore, Renderer.endFrame);
    _ = flecs.ADD_SYSTEM(scene, "Clear Events", core.Pipeline.postStore, clearEvents);

    InputState.mouseX = viewport.getMousePosition()[0];
    InputState.mouseY = viewport.getMousePosition()[1];
    InputState.viewportX = viewport.getWidth();
    InputState.viewportY = viewport.getHeight();

    baseMaterial = Material.new(
        "BaseMaterial",
        "resources/shaders/default/default.vert",
        "resources/shaders/default/default.frag",
    ) catch return false;

    return true;
}

fn start() callconv(.c) bool {
    return true;
}

fn stop() callconv(.c) bool {
    Renderer.waitFinishRendering() catch return false;

    return true;
}

fn unload() callconv(.c) bool {
    const tracy_zone = tracy.ZoneNC(@src(), "Graphics Module Deinit", 0x00_ff_ff_00);
    defer tracy_zone.End();

    Renderer.deinit() catch return false;

    util.module.unregisterComponents(_scene, &components) catch return false;

    shaders.deinit();
    gfx.deinit() catch return false;
    glfw.terminate();

    return true;
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
