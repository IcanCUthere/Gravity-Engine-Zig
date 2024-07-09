const flecs = @import("zflecs");
const tracy = @import("ztracy");
const core = @import("core");

const StateManager = @import("Components/StateManager.zig").StateManager;

pub const Editor = struct {
    pub const name: []const u8 = "editor";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    var _scene: *flecs.world_t = undefined;

    const components = [_]type{
        StateManager,
    };

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        inline for (components) |comp| {
            comp.register(scene);
        }
    }
    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try core.moduleHelpers.cleanUpComponent(comp, _scene);
        }
    }
};
