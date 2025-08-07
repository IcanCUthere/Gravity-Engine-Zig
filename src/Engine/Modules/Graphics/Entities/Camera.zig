const util = @import("util");
const mem = util.mem;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");

const gfx = @import("../Internal/interface.zig");
const Model = @import("../Components/Model.zig").Model;
const Material = @import("../Components/Material.zig").Material;
const Renderer = @import("../Components/Renderer.zig").Renderer;
const CameraComponent = @import("../Components/Camera.zig").Camera;

pub const Camera = struct {
    pub fn init(scene: *flecs.world_t, name: [*:0]const u8) !flecs.entity_t {
        const entity = flecs.new_entity(scene, name);

        _ = flecs.set(scene, entity, CameraComponent, try CameraComponent.init(
            45.0,
            1.0,
            1.0,
            10000.0,
        ));
        util.log.info("HIIIIEIR", .{});
        _ = flecs.set(scene, entity, core.Transform, core.Transform.init());
        util.log.info("HIIIIEIR", .{});

        return entity;
    }
};
