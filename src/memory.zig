const std = @import("std");

var buffer: [100000]u8 = undefined;
var fixedBufferAllocator = std.heap.FixedBufferAllocator.init(&buffer);
pub const fba = fixedBufferAllocator.allocator();
