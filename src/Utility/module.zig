const flecs = @import("zflecs");
const log = @import("log.zig");

pub fn registerComponents(scene: *flecs.world_t, components: []const type) !void {
    inline for (components) |component| {
        try registerComponent(scene, component);
    }
}

fn registerComponent(scene: *flecs.world_t, T: type) !void {
    log.print(
        "Register {s}",
        .{@typeName(T)},
        .Info,
        .Verbose,
        .{ .Modules = true },
    );

    flecs.COMPONENT(scene, T);
    T.setTraits(scene);
    flecs.set_hooks_id(
        scene,
        flecs.id(T),
        &flecs.type_hooks_t{
            .dtor = makeDtor(T),
        },
    );

    T.Prefab = flecs.new_prefab(scene, @typeName(T) ++ "Prefab");
    flecs.add(scene, T.Prefab, T);
    T.setPrefab(scene);
}

pub fn unregisterComponents(scene: *flecs.world_t, components: []const type) !void {
    inline for (components) |component| {
        try unregisterComponent(scene, component);
    }
}

fn unregisterComponent(scene: *flecs.world_t, T: type) !void {
    log.print(
        "Unregister {s}",
        .{@typeName(T)},
        .Info,
        .Verbose,
        .{ .Modules = true },
    );

    flecs.remove_all(scene, flecs.id(T));
}

fn makeDtor(comptime T: type) fn (*anyopaque, i32, *const flecs.type_info_t) callconv(.c) void {
    return struct {
        fn dtor(ptr: *anyopaque, count: i32, _: *const flecs.type_info_t) callconv(.c) void {
            const components: []T = @as([*]T, @alignCast(@ptrCast(ptr)))[0..@intCast(count)];

            for (components) |*component| {
                component.*.deinit() catch {}; //TODO:
            }
        }
    }.dtor;
}
