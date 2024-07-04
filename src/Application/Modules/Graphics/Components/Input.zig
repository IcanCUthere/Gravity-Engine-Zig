const flecs = @import("zflecs");
const evnt = @import("Internal/event.zig");

pub const InputSingleton = struct {
    const Self = @This();

    deltaMouseX: f64 = 0,
    deltaMouseY: f64 = 0,

    mouseX: f64 = 0,
    mouseY: f64 = 0,

    keyStates: [400]evnt.KeyState = [1]evnt.KeyState{.{}} ** 400,

    viewportX: u32 = 0,
    viewportY: u32 = 0,

    deltaViewportX: i32 = 0,
    deltaViewportY: i32 = 0,

    pub fn register(scene: *flecs.world_t) void {
        flecs.COMPONENT(scene, Self);
        _ = flecs.singleton_set(scene, Self, .{});
    }

    pub fn consumeInput(self: *Self) InputSingleton {
        defer self.* = .{ .mouseX = self.mouseX, .mouseY = self.mouseY };
        return self.*;
    }

    pub fn clearKey(self: *Self, key: evnt.Key) void {
        self.keyStates[@intFromEnum(key)] = .{};
    }

    pub fn getKeyState(self: Self, key: evnt.Key) evnt.KeyState {
        return self.keyStates[@intFromEnum(key)];
    }
};
