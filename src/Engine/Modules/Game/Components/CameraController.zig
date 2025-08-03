const util = @import("util");
const math = util.math;

const flecs = @import("zflecs");
const tracy = @import("ztracy");

const core = @import("CoreModule");
const graphics = @import("GraphicsModule");

pub const CameraController = struct {
    const Self = @This();

    speed: f32 = 5.0,

    moveUp: bool = false,
    moveDown: bool = false,
    moveRight: bool = false,
    moveLeft: bool = false,
    moveForward: bool = false,
    moveBackward: bool = false,

    deltaMousePos: math.simd.Vec = math.videntity(),
    mouseSpeed: math.simd.Vec = @splat(0.1),

    pub fn setTraits(scene: *flecs.world_t) void {
        flecs.add_pair(
            scene,
            flecs.id(Self),
            flecs.OnInstantiate,
            flecs.Override,
        );

        var moveSystem = flecs.system_desc_t{};
        moveSystem.callback = flecs.SystemImpl(onUpdate).exec;
        moveSystem.query.terms[0] = .{ .id = flecs.id(core.Transform), .inout = .InOut };
        moveSystem.query.terms[1] = .{ .id = flecs.id(Self), .inout = .In };
        _ = flecs.SYSTEM(scene, "Move Camera", flecs.OnUpdate, &moveSystem);

        var eventSystem = flecs.system_desc_t{};
        eventSystem.callback = flecs.SystemImpl(onEvent).exec;
        eventSystem.query.terms[0] = .{ .id = flecs.id(Self), .inout = .InOut };

        _ = flecs.SYSTEM(scene, "Update Controllers", flecs.PostLoad, &eventSystem);
    }

    pub fn init() Self {}

    pub fn deinit(_: Self) !void {}

    pub fn onEvent(_: *flecs.iter_t, controllers: []Self) void {
        const input = graphics.InputState;

        for (controllers) |*c| {
            c.deltaMousePos = .{ @floatCast(input.deltaMouseY), @floatCast(input.deltaMouseX), 0.0, 0.0 };

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

    pub fn onUpdate(it: *flecs.iter_t, cameras: []core.Transform, controllers: []const Self) void {
        const tracy_zone = tracy.ZoneNC(@src(), "Update camera controller", 0x00_ff_ff_00);
        defer tracy_zone.End();

        for (cameras, controllers) |*camera, controller| {
            const deltaSplat: math.simd.Vec = @splat(it.delta_time);
            const negativeOne: math.simd.Vec = @splat(-1.0);
            const deltaSpeed = math.simd.splat(math.simd.Vec, controller.speed) * deltaSplat;

            const upVector = core.Transform.getWorldUpVector();
            const rightVector = camera.getLocalRightVectorLocked(false, true, false);
            const forwardVector = camera.getLocalForwardVectorLocked(false, true, false);

            var moveDirection: math.simd.Vec = math.vzero();

            if (controller.moveUp) {
                moveDirection += upVector * negativeOne;
            }
            if (controller.moveDown) {
                moveDirection += upVector;
            }
            if (controller.moveLeft) {
                moveDirection += rightVector;
            }
            if (controller.moveRight) {
                moveDirection += rightVector * negativeOne;
            }
            if (controller.moveForward) {
                moveDirection += forwardVector;
            }
            if (controller.moveBackward) {
                moveDirection += forwardVector * negativeOne;
            }

            if (math.simd.length3(moveDirection)[0] > math.roundingError) {
                moveDirection = util.math.simd.normalize3(moveDirection);
                camera.localPosition += moveDirection * deltaSpeed;
                camera.translationMatrix = math.simd.translationV(camera.localPosition);
            }

            if (math.simd.length2(controller.deltaMousePos)[0] > math.roundingError) {
                camera.localRotation += controller.deltaMousePos * controller.mouseSpeed;
                camera.localRotation[0] = math.clamp(
                    camera.localRotation[0],
                    -90,
                    90,
                );

                camera.rotationMatrix = core.Transform.getLockedRotation(camera.localRotation, true, true, false);
            }
        }
    }
};
