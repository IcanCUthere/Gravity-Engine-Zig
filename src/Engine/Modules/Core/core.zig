const util = @import("util");

const flecs = @import("zflecs");
const tracy = @import("ztracy");
const msh = @import("zmesh");
const stbi = @import("zstbi");

pub const Transform = @import("Components/Transform.zig").Transform;
pub const io = @import("Internal/io.zig");
pub const storage = @import("Internal/storage.zig");

pub const name: [*:0]const u8 = "core";
pub const dependencies = [_][*:0]const u8{};

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
    Transform,
};

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
    const tracy_zone = tracy.ZoneNC(@src(), "Core Module Init", 0x00_ff_ff_00);
    defer tracy_zone.End();

    _ = flecs.init();
    _scene = scene;

    msh.init(util.mem.heap);
    stbi.init(util.mem.heap);
    storage.init() catch return false;

    Pipeline.postStore = flecs.new_id(_scene);
    flecs.add_pair(_scene, Pipeline.postStore, flecs.DependsOn, flecs.OnStore);

    util.module.registerComponents(scene, &components) catch return false;

    return true;
}

fn start() callconv(.c) bool {
    return true;
}

fn stop() callconv(.c) bool {
    return true;
}

fn unload() callconv(.c) bool {
    const tracy_zone = tracy.ZoneNC(@src(), "Core Module Deinit", 0x00_ff_ff_00);
    defer tracy_zone.End();

    util.module.unregisterComponents(_scene, &components) catch return false;

    storage.deinit();
    stbi.deinit();
    msh.deinit();

    return true;
}
