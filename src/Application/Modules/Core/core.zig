const flecs = @import("zflecs");
const tracy = @import("ztracy");
const msh = @import("zmesh");
const stbi = @import("zstbi");
const core = @import("core");

pub const Mesh = @import("Components/Mesh.zig").Mesh;
pub const Transform = @import("Components/Transform.zig").Transform;
pub const io = @import("Components/Internal/io.zig");
pub const storage = @import("Components/Internal/storage.zig");

const std = @import("std");

pub const Core = struct {
    pub const name: []const u8 = "core";
    pub const dependencies = [_][]const u8{};

    var _scene: *flecs.world_t = undefined;

    const components = [_]type{
        Transform,
        Mesh,
    };

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Core Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        msh.init(core.mem.ha);
        stbi.init(core.mem.ha);
        storage.init();

        inline for (components) |comp| {
            comp.register(scene);
        }
    }

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Core Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try core.moduleHelpers.cleanUpComponent(comp, _scene);
        }

        storage.deinit();
        stbi.deinit();
        msh.deinit();
    }
};
