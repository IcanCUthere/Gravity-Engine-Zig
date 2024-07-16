const flecs = @import("zflecs");

const core = @import("CoreModule");
const graphics = @import("GraphicsModule");

pub const StateManager = struct {
    const Self = @This();

    pub var inEditor: bool = false;

    idk: u32 = 0,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);
        _ = flecs.singleton_set(scene, Self, .{});

        var eventSystem = flecs.system_desc_t{};
        eventSystem.callback = flecs.SystemImpl(onEvent).exec;
        eventSystem.query.filter.terms[0] = .{
            .id = flecs.id(Self),
            .inout = .InOut,
        };

        flecs.SYSTEM(scene, "Update Editor State", flecs.PostLoad, &eventSystem);
    }

    pub fn deinit(_: Self) void {}

    pub fn onEvent(it: *flecs.iter_t, _: []Self) void {
        const input = graphics.InputState;

        const viewport = flecs.get(it.world, graphics.Graphics.mainViewport, graphics.Viewport).?;

        if (input.getKeyState(.F1).isPress and !inEditor) {
            inEditor = true;
            viewport.setCursorEnabled(true);
        } else if (input.getKeyState(.F1).isPress and inEditor) {
            inEditor = false;
            viewport.setCursorEnabled(false);
        }

        if (inEditor) {
            input.deltaMouseX = 0;
            input.deltaMouseY = 0;
        }

        input.clearKey(.F1);
    }
};
