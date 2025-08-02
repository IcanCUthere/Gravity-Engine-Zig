const flecs = @import("zflecs");
const log = @import("log.zig");

pub fn cleanUpComponent(T: type, scene: *flecs.world_t) !void {
    log.print(
        "Deinit {s}",
        .{@typeName(T)},
        .Info,
        .Verbose,
        .{ .Modules = true },
    );

    var queryDesc = flecs.query_desc_t{};
    queryDesc.terms[0] = flecs.term_t{
        .id = flecs.id(T),
    };

    const query = try flecs.query_init(scene, &queryDesc);

    var iter = flecs.query_iter(scene, query);

    while (flecs.query_next(&iter)) {
        if (flecs.field(&iter, T, 0)) |comps| {
            if (flecs.field_is_self(&iter, 0)) {
                for (comps) |*comp| {
                    try comp.deinit();
                }
            }
        }
    }

    flecs.query_fini(query);
}
