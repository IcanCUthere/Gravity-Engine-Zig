const GravityEngine = @import("Engine/GravityEngine.zig").GravityEngine;

pub fn main() !void {
    try GravityEngine.init();

    try GravityEngine.run();

    try GravityEngine.deinit();
}
