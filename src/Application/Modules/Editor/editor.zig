const flecs = @import("zflecs");
const tracy = @import("ztracy");

const StateManager = @import("Components/StateManager.zig").StateManager;

pub const Editor = struct {
    pub const name: []const u8 = "editor";
    pub const dependencies = [_][]const u8{ "core", "graphics" };

    pub fn init(scene: *flecs.world_t, _: *bool) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        StateManager.register(scene);
    }
    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Editor Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();
    }
};
