const shaderc = @import("zshaderc");

const gfx = @import("interface.zig");

const util = @import("util");
const fs = util.fs;
const mem = util.mem;

const StorageType = []const u8;
var storage: util.StringHashMap(StorageType) = undefined;

pub fn init() !void {
    storage = util.StringHashMap(StorageType).init(mem.heap);

    var shaderDir = try fs.cwd().openDir(
        "resources/shaders",
        fs.Dir.OpenDirOptions{
            .access_sub_paths = true,
            .iterate = true,
        },
    );
    defer shaderDir.close();

    try shaderc.init(mem.heap);
    defer shaderc.deinit();

    var compiler = shaderc.Compiler.init();
    defer compiler.deinit();

    var walker = try shaderDir.walk(mem.heap);
    defer walker.deinit();

    while (try walker.next()) |f| {
        if (mem.indexOf(u8, f.path, ".cache.")) |_| {
            continue;
        }

        if (f.kind == .file) {
            const cachePath = try getCachePath(f.path);
            defer mem.heap.free(cachePath);

            const shaderCode = try codeFromCache(shaderDir, cachePath) orelse fromFile: {
                const code = try codeFromFile(shaderDir, f.path, f.basename, compiler);
                try codeToCache(shaderDir, cachePath, code);
                break :fromFile code;
            };

            const name = try mem.heap.allocSentinel(u8, f.basename.len, 0);
            mem.copyForwards(u8, name, f.basename);

            try storage.put(name, shaderCode);
        }
    }
}

pub fn deinit() void {
    var iter = storage.iterator();
    while (iter.next()) |entry| {
        mem.heap.free(@as(*[:0]const u8, @ptrCast(entry.key_ptr)).*);
        mem.heap.free(entry.value_ptr.*);
    }

    storage.deinit();
}

pub fn get(name: []const u8) []const u8 {
    return storage.get(name).?;
}

fn getCachePath(subpath: []const u8) ![]const u8 {
    const name = @as(*[*:0]const u8, @ptrCast(@constCast(&gfx.getGraphicsCardName()))).*;
    const len = mem.indexOfSentinel(u8, 0, name);

    const cachePath = try mem.heap.alloc(u8, subpath.len + 7 + len);
    mem.copyForwards(u8, cachePath, subpath);
    mem.copyForwards(u8, cachePath[subpath.len..], ".cache.");
    mem.copyForwards(u8, cachePath[subpath.len + 7 ..], name[0..len]);

    return cachePath;
}

fn codeToCache(dir: fs.Dir, subpath: []const u8, code: []const u8) !void {
    const file = try dir.createFile(subpath, .{});
    defer file.close();

    var writer = file.writer();
    _ = try writer.writeInt(u32, gfx.getDriverVersion(), .little);
    _ = try writer.write(code);
}

fn codeFromCache(dir: fs.Dir, subpath: []const u8) !?[]const u8 {
    const cacheFile: ?fs.File = dir.openFile(
        subpath,
        .{ .mode = .read_only },
    ) catch null;

    if (cacheFile) |file| {
        var driverVersBytes: [@sizeOf(u32)]u8 = undefined;
        _ = try file.read(&driverVersBytes);

        const driverVersion = @as(*u32, @ptrCast(@alignCast(&driverVersBytes))).*;
        const code = try file.readToEndAlloc(mem.heap, util.math.maxInt(u32));

        if (driverVersion != gfx.getDriverVersion()) {
            util.log.print("Shader in cache {s} has different driver version", .{subpath}, .Info, .Verbose, .{ .ShaderLoading = true });
            mem.heap.free(code);
            return null;
        }

        util.log.print("Loading shader {s} from cache", .{subpath}, .Info, .Verbose, .{ .ShaderLoading = true });

        return code;
    }

    return null;
}

fn codeFromFile(dir: fs.Dir, subpath: []const u8, name: [:0]const u8, compiler: shaderc.Compiler) ![]const u8 {
    var file = try dir.openFile(subpath, .{});
    defer file.close();

    util.log.print("Loading shader {s} from file", .{subpath}, .Info, .Verbose, .{ .ShaderLoading = true });

    const shaderCode = try file.readToEndAlloc(mem.heap, util.math.maxInt(u32));
    defer mem.heap.free(shaderCode);

    const res = try compiler.compile(
        shaderCode,
        getShaderType(name[name.len - 5 ..]),
        name,
        "main",
        null,
    );

    const code = try mem.heap.alloc(u8, res.getCode().len);
    mem.copyForwards(u8, code, res.getCode());

    return code;
}

fn getShaderType(ext: [:0]const u8) shaderc.ShaderKind {
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
