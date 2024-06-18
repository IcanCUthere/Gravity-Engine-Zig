const std = @import("std");

pub const WindowResizeEvent = struct {
    width: u32,
    height: u32,
};

pub const WindowCloseEvent = struct {};

pub const Event = union(enum) {
    closeEvent: WindowCloseEvent,
    resizeEvent: WindowResizeEvent,

    pub fn getType(self: Event) type {
        switch (self) {
            inline else => |case| return @TypeOf(case),
        }
    }
};

pub const CallbackFunction = fn (*anyopaque, Event) void;
