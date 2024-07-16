const flecs = @import("zflecs");

pub fn cleanUpComponent(T: type, scene: *flecs.world_t) !void {
    var queryDesc = flecs.query_desc_t{};
    queryDesc.filter.terms[0] = flecs.term_t{
        .id = flecs.id(T),
    };

    const query = try flecs.query_init(scene, &queryDesc);

    var iter = flecs.query_iter(scene, query);

    while (flecs.query_next(&iter)) {
        if (flecs.field(&iter, T, 1)) |comps| {
            if (flecs.field_is_self(&iter, 1)) {
                for (comps) |*comp| {
                    comp.deinit();
                }
            }
        }
    }
}
