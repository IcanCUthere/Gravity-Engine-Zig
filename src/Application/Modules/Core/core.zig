const flecs = @import("zflecs");
const tracy = @import("ztracy");
const msh = @import("zmesh");
const core = @import("core");

pub const Mesh = @import("Components/Mesh.zig").Mesh;
pub const Transform = @import("Components/Transform.zig").Transform;
pub const io = @import("Components/Internal/io.zig");

const std = @import("std");

pub const Core = struct {
    pub const name: []const u8 = "core";
    pub const dependencies = [_][]const u8{};

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Core Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        msh.init(core.mem.ha);

        _ = Transform.register(scene);
        _ = Mesh.register(scene);
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Core Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        msh.deinit();
    }
};
