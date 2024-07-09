const flecs = @import("zflecs");
const math = @import("core").math;

const coreM = @import("CoreModule");
const graphicsM = @import("GraphicsModule");

pub const CameraController = struct {
    const Self = @This();
    var Prefab: flecs.entity_t = undefined;

    speed: f32 = 5.0,

    moveUp: bool = false,
    moveDown: bool = false,
    moveRight: bool = false,
    moveLeft: bool = false,
    moveForward: bool = false,
    moveBackward: bool = false,

    deltaMousePos: math.Vec3 = math.videntity(),

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);

        Prefab = flecs.new_prefab(scene, "CameraControllerComponent");
        _ = flecs.set(scene, Prefab, Self, .{});
        flecs.override(scene, Prefab, Self);

        var moveSystem = flecs.system_desc_t{};
        moveSystem.callback = flecs.SystemImpl(onUpdate).exec;
        moveSystem.query.filter.terms[0] = .{ .id = flecs.id(coreM.Transform), .inout = .InOut };
        moveSystem.query.filter.terms[1] = .{ .id = flecs.id(Self), .inout = .In };
        flecs.SYSTEM(scene, "Move Camera", flecs.OnUpdate, &moveSystem);

        var eventSystem = flecs.system_desc_t{};
        eventSystem.callback = flecs.SystemImpl(onEvent).exec;
        eventSystem.query.filter.terms[0] = .{ .id = flecs.id(Self), .inout = .InOut };

        flecs.SYSTEM(scene, "Update Controllers", flecs.PostLoad, &eventSystem);
    }

    pub fn getPrefab() flecs.entity_t {
        return Prefab;
    }

    pub fn init() Self {}

    pub fn deinit(_: Self) void {}

    pub fn onEvent(_: *flecs.iter_t, controllers: []Self) void {
        const input = graphicsM.InputState;

        for (controllers) |*c| {
            c.deltaMousePos = .{ @floatCast(input.deltaMouseY), @floatCast(input.deltaMouseX), 0.0 };

            if (input.getKeyState(.w).isPress) {
                c.moveForward = true;
            }
            if (input.getKeyState(.w).isRelease) {
                c.moveForward = false;
            }

            if (input.getKeyState(.a).isPress) {
                c.moveLeft = true;
            }
            if (input.getKeyState(.a).isRelease) {
                c.moveLeft = false;
            }

            if (input.getKeyState(.s).isPress) {
                c.moveBackward = true;
            }
            if (input.getKeyState(.s).isRelease) {
                c.moveBackward = false;
            }

            if (input.getKeyState(.d).isPress) {
                c.moveRight = true;
            }
            if (input.getKeyState(.d).isRelease) {
                c.moveRight = false;
            }

            if (input.getKeyState(.left_control).isPress) {
                c.moveDown = true;
            }
            if (input.getKeyState(.left_control).isRelease) {
                c.moveDown = false;
            }

            if (input.getKeyState(.space).isPress) {
                c.moveUp = true;
            }
            if (input.getKeyState(.space).isRelease) {
                c.moveUp = false;
            }
        }
    }

    pub fn onUpdate(it: *flecs.iter_t, cameras: []coreM.Transform, controllers: []const Self) void {
        for (cameras, controllers) |*camera, controller| {
            const deltaSplat: math.Vec3 = @splat(it.delta_time);
            const negativeOne: math.Vec3 = @splat(-1.0);
            const moveSpeed: math.Vec3 = @splat(controller.speed);
            const deltaSpeed = moveSpeed * deltaSplat;

            camera.localRotation = math.qmul(camera.localRotation, math.quatFromRollPitchYawV(math.vec3ToVec4(controller.deltaMousePos * deltaSplat)));

            if (controller.moveUp) {
                camera.localPosition += (camera.getLocalUpVector() * negativeOne * deltaSpeed);
            }
            if (controller.moveDown) {
                camera.localPosition += (camera.getLocalUpVector() * deltaSpeed);
            }
            if (controller.moveLeft) {
                camera.localPosition += (camera.getLocalRightVector() * deltaSpeed);
            }
            if (controller.moveRight) {
                camera.localPosition += (camera.getLocalRightVector() * negativeOne * deltaSpeed);
            }
            if (controller.moveForward) {
                camera.localPosition += (camera.getLocalForwardVector() * deltaSpeed);
            }
            if (controller.moveBackward) {
                camera.localPosition += (camera.getLocalForwardVector() * negativeOne * deltaSpeed);
            }

            camera.transformMatrix = math.mul(
                math.translationV(math.vec3ToVec4(camera.localPosition)),
                math.matFromQuat(camera.localRotation),
            );
        }
    }
};
