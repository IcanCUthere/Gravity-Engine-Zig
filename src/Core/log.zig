const std = @import("std");
const settings = @import("_settings.zig");

inline fn shouldLog(lvl: settings.LogLevel, ctx: settings.LogContext, t: settings.LogType) bool {
    return (@intFromEnum(lvl) <= @intFromEnum(settings.UsedLogLevel) and ctx.intersect(settings.UsedLogContext).toInt() != 0) and @intFromEnum(t) >= @intFromEnum(settings.UsedLogType);
}

pub inline fn log(comptime format: []const u8, args: anytype, logType: settings.LogType, level: settings.LogLevel, context: settings.LogContext) void {
    switch (logType) {
        .Info => if (shouldLog(level, context, logType)) std.log.info(format, args),
        .Warning => if (shouldLog(level, context, logType)) std.log.warn(format, args),
        .Critical => if (shouldLog(level, context, logType)) std.log.err(format, args),
    }
}
