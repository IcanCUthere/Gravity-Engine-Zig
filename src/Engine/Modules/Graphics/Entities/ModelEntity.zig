const util = @import("util");
const mem = util.mem;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("../Components/Internal/interface.zig");
const Model = @import("../Components/Model.zig").Model;
const Material = @import("../Components/Material.zig").Material;
const Renderer = @import("../Components/Renderer.zig").Renderer;

pub const ModelEntity = struct {
    pub fn new(scene: *flecs.world_t, name: [*:0]const u8, model: flecs.entity_t, position: util.math.simd.Vec) !flecs.entity_t {
        const newEntt = flecs.new_entity(scene, name);

        flecs.add_pair(scene, newEntt, flecs.IsA, model);
        _ = flecs.set(scene, newEntt, core.Transform, core.Transform{
            .localPosition = position,
            .translationMatrix = util.math.simd.translation(position[0], position[1], position[2]),
        });

        //_ = flecs.set()

        // _ = flecs.set(scene, newEntt, Self, try init(model));

        return newEntt;
    }
};
