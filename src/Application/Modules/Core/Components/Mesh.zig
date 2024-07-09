const Transform = @import("Transform.zig").Transform;
const core = @import("core");
const flecs = @import("zflecs");
const std = @import("std");
const io = @import("Internal/io.zig");
const storage = @import("Internal/storage.zig");

fn onEvent(it: *flecs.iter_t, meshes: []Mesh) void {
    const event: flecs.entity_t = it.event;

    for (meshes) |*m| {
        if (event == flecs.OnRemove) {
            m.deinit();
        }
    }
}

pub const Mesh = struct {
    const Self = @This();
    var _scene: *flecs.world_t = undefined;
    var Prefab: flecs.entity_t = undefined;

    path: [:0]const u8 = undefined,
    data: *io.Mesh = undefined,

    pub fn register(scene: *flecs.world_t) void {
        _scene = scene;

        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "MeshComponent");
        flecs.add_pair(scene, Prefab, flecs.IsA, Transform.getPrefab());
        _ = flecs.add(scene, Prefab, Self);
        flecs.override(scene, Prefab, Self);

        var setObsDesc = flecs.observer_desc_t{
            .filter = flecs.filter_desc_t{
                .terms = [1]flecs.term_t{
                    flecs.term_t{
                        .id = flecs.id(Self),
                    },
                } ++ ([1]flecs.term_t{.{}} ** 15),
            },
            .events = [_]u64{flecs.OnSet} ++ ([1]u64{0} ** 7),
            .callback = flecs.SystemImpl(onEvent).exec,
        };

        flecs.OBSERVER(scene, "MeshComponentOnEvent", &setObsDesc);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn new(name: [*:0]const u8, path: [:0]const u8) !flecs.entity_t {
        const newEntt = flecs.new_entity(_scene, name);
        flecs.add_pair(_scene, newEntt, flecs.IsA, getPrefab());
        _ = flecs.set(_scene, newEntt, Self, try init(path));

        return newEntt;
    }

    pub fn init(path: [:0]const u8) !Self {
        return Self{
            .path = path,
            .data = try storage.getOrAddMesh(path),
        };
    }

    pub fn deinit(_: *Self) void {}
};
