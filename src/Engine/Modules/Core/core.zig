const util = @import("util");

const flecs = @import("zflecs");
const tracy = @import("ztracy");
const msh = @import("zmesh");
const stbi = @import("zstbi");

pub const Transform = @import("Components/Transform.zig").Transform;
pub const io = @import("Components/Internal/io.zig");
pub const storage = @import("Components/Internal/storage.zig");

pub const Pipeline = struct {
    pub const onLoad = flecs.OnLoad;
    pub const postLoad = flecs.PostLoad;
    pub const preUpdate = flecs.PreUpdate;
    pub const onUpdate = flecs.OnUpdate;
    pub const onValidate = flecs.OnValidate;
    pub const postUpdate = flecs.PostUpdate;
    pub const preStore = flecs.PreStore;
    pub const onStore = flecs.OnStore;
    pub var postStore: flecs.entity_t = undefined;
};

pub const Core = struct {
    pub const name: []const u8 = "core";
    pub const dependencies = [_][]const u8{};

    var _scene: *flecs.world_t = undefined;

    const components = [_]type{
        Transform,
    };

    pub fn init(scene: *flecs.world_t) !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Core Module Init", 0x00_ff_ff_00);
        defer tracy_zone.End();

        _scene = scene;

        msh.init(util.mem.heap);
        stbi.init(util.mem.heap);
        storage.init();

        Pipeline.postStore = flecs.new_id(_scene);
        flecs.add_pair(_scene, Pipeline.postStore, flecs.DependsOn, flecs.OnStore);

        inline for (components) |comp| {
            comp.register(scene);
        }
    }

    pub fn preDeinit() !void {}

    pub fn deinit() !void {
        const tracy_zone = tracy.ZoneNC(@src(), "Core Module Deinit", 0x00_ff_ff_00);
        defer tracy_zone.End();

        inline for (components) |comp| {
            try util.module.cleanUpComponent(comp, _scene);
        }

        storage.deinit();
        stbi.deinit();
        msh.deinit();
    }
};
