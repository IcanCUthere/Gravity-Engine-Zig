const Application = @import("Application/application.zig").Application;

pub fn main() !void {
    try Application.init();

    try Application.run();

    try Application.deinit();
}
