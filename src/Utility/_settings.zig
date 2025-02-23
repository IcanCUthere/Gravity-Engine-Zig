// -- Log Settings --
pub const UsedLogContext = LogContext{
    //.Vulkan = true,
    //.ShaderLoading = true,
    .MeshLoading = true,
};
pub const UsedLogLevel = LogLevel.Verbose;
pub const UsedLogType = LogType.Info;

// -- Memory Settings --
pub const fixedBufferSize = 1_048_576; //1MiB
pub const maxHeapSize = 1_073_741_824; //8GiB

const LogNone = LogContext{};

const LogIO = LogContext{
    .MeshLoading = true,
    .ShaderLoading = true,
};

const LogPerformance = LogContext{
    .FPS = true,
};

const LogMemory = LogContext{
    .Allocations = true,
};

const LogGraphicsAPI = LogContext{
    .Vulkan = true,
};

const LogAll = LogContext{
    .Vulkan = true,
    .MeshLoading = true,
    .ShaderLoading = true,
    .Events = true,
    .FPS = true,
    .Allocations = true,
    .Modules = true,
};

pub const LogContext = packed struct(u32) {
    const Self = @This();

    Vulkan: bool = false,
    MeshLoading: bool = false,
    ShaderLoading: bool = false,
    Events: bool = false,
    FPS: bool = false,
    Allocations: bool = false,
    Modules: bool = false,

    _reserved: u25 = 0,

    pub fn toInt(self: Self) u32 {
        return @bitCast(self);
    }
    pub fn fromInt(flags: u32) Self {
        return @bitCast(flags);
    }

    pub fn merge(one: Self, two: Self) Self {
        return fromInt(toInt(one) | toInt(two));
    }

    pub fn intersect(one: Self, two: Self) Self {
        return fromInt(toInt(one) & toInt(two));
    }
};

pub const LogLevel = enum(u32) {
    None = 0,
    Abstract = 1,
    Verbose = 2,
};

pub const LogType = enum(u32) {
    Info = 0,
    Warning = 1,
    Critical = 2,
};
