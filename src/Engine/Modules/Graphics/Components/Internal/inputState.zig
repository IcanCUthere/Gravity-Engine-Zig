const flecs = @import("zflecs");
const evnt = @import("event.zig");

pub const InputState = struct {
    const Self = @This();

    pub var deltaMouseX: f64 = 0;
    pub var deltaMouseY: f64 = 0;

    pub var mouseX: f64 = 0;
    pub var mouseY: f64 = 0;

    pub var keyStates: [400]evnt.KeyState = [1]evnt.KeyState{.{}} ** 400;

    pub var viewportX: u32 = 0;
    pub var viewportY: u32 = 0;

    pub var deltaViewportX: i32 = 0;
    pub var deltaViewportY: i32 = 0;

    pub fn clearKey(key: evnt.Key) void {
        keyStates[@intFromEnum(key)] = .{};
    }

    pub fn getKeyState(key: evnt.Key) evnt.KeyState {
        return keyStates[@intFromEnum(key)];
    }
};
