const shaderc = @import("zshaderc");

const gfx = @import("interface.zig");

const util = @import("util");
const fs = util.fs;
const mem = util.mem;

const StorageType = []const u8;
var storage: util.StringHashMap(StorageType) = undefined;
var compiler: shaderc.Compiler = undefined;

const cacheExt = ".cache";
const shaderPath = "resources/shaders/";
const pipelineCachePath = shaderPath ++ "pipeline_cache/";

pub fn init() !void {
    try shaderc.init(mem.heap);
    compiler = shaderc.Compiler.init();
    storage = util.StringHashMap(StorageType).init(mem.heap);

    fs.cwd().makeDir(pipelineCachePath) catch {};
}

pub fn deinit() void {
    var iter = storage.iterator();
    while (iter.next()) |entry| {
        mem.heap.free(entry.key_ptr.*);
        mem.heap.free(entry.value_ptr.*);
    }

    storage.deinit();
    compiler.deinit();
    shaderc.deinit();
}

pub fn getOrAdd(path: []const u8) ![]const u8 {
    if (storage.get(path)) |sh|
        return sh;

    const cachePath = try getCachePath(path);
    defer mem.heap.free(cachePath);

    const meta = try (try fs.cwd().openFile(path, .{})).metadata();

    const shaderCode = try codeFromCache(cachePath, meta.modified()) orelse fromFile: {
        const code = try codeFromFile(path);
        try codeToCache(cachePath, code, meta.modified());
        break :fromFile code;
    };

    const name = try mem.heap.alloc(u8, path.len);
    mem.copyForwards(u8, name, path);

    try storage.put(name, shaderCode);

    return shaderCode;
}

pub fn getPipelineCache(
    name: []const u8,
    vertPath: ?[]const u8,
    fragPath: ?[]const u8,
    compPath: ?[]const u8,
    tescPath: ?[]const u8,
    tesePath: ?[]const u8,
) !?[]const u8 {
    var cacheDir = try fs.cwd().openDir(pipelineCachePath, .{});
    defer cacheDir.close();

    var file = cacheDir.openFile(name, .{}) catch return null;
    defer file.close();

    const reader = file.reader();

    if (try checkShaderModified(vertPath, reader) or
        try checkShaderModified(fragPath, reader) or
        try checkShaderModified(compPath, reader) or
        try checkShaderModified(tescPath, reader) or
        try checkShaderModified(tesePath, reader))
    {
        return null;
    }

    if (try reader.readInt(i128, .little) != 0) {
        return null;
    }

    util.log.print("Reading material cache for {s}", .{name}, .Info, .Verbose, .{ .ShaderLoading = true });

    return try reader.readAllAlloc(mem.heap, util.math.maxInt(u32));
}

pub fn addPipelineCache(
    name: []const u8,
    data: []const u8,
    vertPath: ?[]const u8,
    fragPath: ?[]const u8,
    compPath: ?[]const u8,
    tescPath: ?[]const u8,
    tesePath: ?[]const u8,
) !void {
    util.log.print("Overwriting material cache for {s}", .{name}, .Info, .Verbose, .{ .ShaderLoading = true });

    var cacheDir = try fs.cwd().openDir(pipelineCachePath, .{});
    defer cacheDir.close();

    var file = try cacheDir.createFile(name, .{});
    defer file.close();

    const writer = file.writer();

    var shaderDir = try fs.cwd().openDir(shaderPath, .{});
    defer shaderDir.close();

    try writeShaderModified(vertPath, writer);
    try writeShaderModified(fragPath, writer);
    try writeShaderModified(compPath, writer);
    try writeShaderModified(tescPath, writer);
    try writeShaderModified(tesePath, writer);

    try writer.writeInt(i128, 0, .little);

    _ = try writer.write(data);
}

fn checkShaderModified(shPath: ?[]const u8, reader: fs.File.Reader) !bool {
    if (shPath) |path| {
        var f = try fs.cwd().openFile(path, .{});
        defer f.close();

        const meta = try f.metadata();
        const modifiedOld = try reader.readInt(i128, .little);

        if (modifiedOld != meta.modified())
            return true;
    }

    return false;
}

fn writeShaderModified(shPath: ?[]const u8, writer: fs.File.Writer) !void {
    if (shPath) |path| {
        var f = try fs.cwd().openFile(path, .{});
        defer f.close();
        const meta = try f.metadata();

        try writer.writeInt(i128, meta.modified(), .little);
    }
}

fn getCachePath(subpath: []const u8) ![]const u8 {
    const cachePath = try mem.heap.alloc(u8, subpath.len + cacheExt.len);
    mem.copyForwards(u8, cachePath, subpath);
    mem.copyForwards(u8, cachePath[subpath.len..], cacheExt);

    return cachePath;
}

fn codeToCache(subpath: []const u8, code: []const u8, newLastModified: i128) !void {
    const file = try fs.cwd().createFile(subpath, .{});
    defer file.close();

    var writer = file.writer();
    _ = try writer.writeInt(i128, newLastModified, .little);
    _ = try writer.write(code);
}

fn codeFromCache(subpath: []const u8, lastModified: i128) !?[]const u8 {
    const cacheFile = fs.cwd().openFile(
        subpath,
        .{ .mode = .read_only },
    ) catch return null;

    var reader = cacheFile.reader();
    const oldLastModified = try reader.readInt(i128, .little);

    if (lastModified != oldLastModified) {
        util.log.print("Shader in cache {s} outdated", .{subpath}, .Info, .Verbose, .{ .ShaderLoading = true });
        return null;
    }

    const code = try reader.readAllAlloc(mem.heap, util.math.maxInt(u32));

    util.log.print("Loading shader {s} from cache", .{subpath}, .Info, .Verbose, .{ .ShaderLoading = true });

    return code;
}

fn codeFromFile(subpath: []const u8) ![]const u8 {
    var file = try fs.cwd().openFile(subpath, .{});
    defer file.close();

    util.log.print("Loading shader {s} from file", .{subpath}, .Info, .Verbose, .{ .ShaderLoading = true });

    const shaderCode = try file.readToEndAlloc(mem.heap, util.math.maxInt(u32));
    defer mem.heap.free(shaderCode);

    const res = try compiler.compile(
        shaderCode,
        getShaderType(subpath[subpath.len - 5 ..]),
        subpath,
        "main",
        null,
    );

    const code = try mem.heap.alloc(u8, res.getCode().len);
    mem.copyForwards(u8, code, res.getCode());

    return code;
}

fn getShaderType(ext: []const u8) shaderc.ShaderKind {
    if (mem.eql(u8, ext, ".vert")) {
        return .vertex;
    } else if (mem.eql(u8, ext, ".frag")) {
        return .fragment;
    } else if (mem.eql(u8, ext, ".comp")) {
        return .compute;
    } else if (mem.eql(u8, ext, ".geom")) {
        return .geometry;
    } else if (mem.eql(u8, ext, ".tesc")) {
        return .tessControl;
    } else if (mem.eql(u8, ext, ".tese")) {
        return .tessEval;
    } else {
        unreachable;
    }
}
