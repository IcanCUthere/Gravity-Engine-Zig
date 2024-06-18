const std = @import("std");
const builtin = @import("builtin");

var buffer: [100000]u8 = undefined;
var fixedBufferAllocator = std.heap.FixedBufferAllocator.init(&buffer);
pub const fba = fixedBufferAllocator.allocator();

var heapAllocator = std.heap.GeneralPurposeAllocator(.{}){};
pub const ha = if (builtin.mode == .Debug) heapAllocator.allocator() else std.heap.c_allocator;
