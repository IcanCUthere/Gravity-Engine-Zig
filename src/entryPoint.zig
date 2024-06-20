const Application = @import("Application/application.zig");

pub fn main() !void {
    try Application.init();

    try Application.run();

    try Application.deinit();
}
