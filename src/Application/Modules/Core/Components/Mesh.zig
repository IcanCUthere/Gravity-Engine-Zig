const Transform = @import("Transform.zig").Transform;
const core = @import("core");
const flecs = @import("zflecs");
const std = @import("std");
const io = @import("Internal/io.zig");

fn onEvent(it: *flecs.iter_t, meshes: []Mesh) void {
    const event: flecs.entity_t = it.event;

    std.log.info("COUNT: {d}", .{it.count()});

    for (meshes) |*m| {
        if (event == flecs.OnSet) {
            m.mesh = io.loadMeshFromFile(m.path) catch {
                std.log.err("Mesh could not be loaded", .{});
                continue;
            };

            std.log.info("Mesh successfully loaded", .{});
        } else if (event == flecs.OnRemove) {
            m.mesh.deinit();
            std.log.info("Mesh successfully unloaded", .{});
        }
    }
}

pub const Mesh = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    path: [:0]const u8 = undefined,
    mesh: io.Mesh = undefined,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "MeshComponent");
        flecs.add_pair(scene, Prefab, flecs.IsA, Transform.getPrefab());
        _ = flecs.set(scene, Prefab, Self, .{});
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

        flecs.OBSERVER(scene, "load model", &setObsDesc);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }
};
