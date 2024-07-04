const flecs = @import("zflecs");

const coreM = @import("CoreModule");
const graphicsM = @import("GraphicsModule");

const std = @import("std");

pub const StateManager = struct {
    const Self = @This();

    inEditor: bool = false,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);
        _ = flecs.singleton_set(scene, Self, .{});

        var eventSystem = flecs.system_desc_t{};
        eventSystem.callback = flecs.SystemImpl(onEvent).exec;
        eventSystem.query.filter.terms[0] = .{
            .id = flecs.id(Self),
            .inout = .InOut,
        };
        eventSystem.query.filter.terms[1] = .{
            .id = flecs.id(graphicsM.InputSingleton),
            .src = flecs.term_id_t{ .id = flecs.id(graphicsM.InputSingleton) },
            .inout = .InOut,
        };
        eventSystem.query.filter.instanced = true;
        flecs.SYSTEM(scene, "Update Editor State", flecs.PostLoad, &eventSystem);
    }

    pub fn onEvent(it: *flecs.iter_t, stateMangs: []Self, inputComps: []graphicsM.InputSingleton) void {
        const stateManager = &stateMangs[0];
        const input = &inputComps[0];

        const viewport = flecs.get(it.world, graphicsM.Graphics.mainViewport, graphicsM.Viewport).?;

        if (input.getKeyState(.F1).isPress and !stateManager.inEditor) {
            stateManager.inEditor = true;
            viewport.setCursorEnabled(true);
        } else if (input.getKeyState(.F1).isPress and stateManager.inEditor) {
            stateManager.inEditor = false;
            viewport.setCursorEnabled(false);
        }

        if (stateManager.inEditor) {
            input.deltaMouseX = 0;
            input.deltaMouseY = 0;
        }

        input.clearKey(.F1);
    }
};
