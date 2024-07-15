const std = @import("std");
const builtin = @import("builtin");

const settings = @import("_settings.zig");

const config = .{
    .enable_memory_limit = true,
    .never_unmap = true,
    .retain_metadata = true,
    .verbose_log = if (settings.UsedLogLevel == .Verbose and settings.UsedLogType == .Info and settings.UsedLogContext.Allocations == true) true else false,
    .stack_trace_frames = 100,
};

var buffer: [settings.fixedBufferSize]u8 = undefined;

pub var fixedBufferAllocator = if (builtin.mode == .Debug) std.heap.GeneralPurposeAllocator(config){ .requested_memory_limit = settings.fixedBufferSize } else std.heap.FixedBufferAllocator.init(&buffer);
pub const fixedBuffer = fixedBufferAllocator.allocator();

pub var heapAllocator = std.heap.GeneralPurposeAllocator(config){ .requested_memory_limit = settings.maxHeapSize };
pub const heap = if (builtin.mode == .Debug) heapAllocator.allocator() else std.heap.c_allocator;
