const std = @import("std");
const io = @import("io.zig");
const core = @import("core");

var meshStorage = std.StringHashMap(*io.ModelData).init(core.mem.heap);

pub fn init() void {}

pub fn deinit() void {
    var iter = meshStorage.valueIterator();

    var item = iter.next();
    while (item) |i| {
        i.*.*.deinit();
        core.mem.heap.destroy(i.*);
        item = iter.next();
    }

    meshStorage.deinit();
}

pub fn getMeshOrNull(path: [:0]const u8) ?*io.ModelData {
    if (meshStorage.contains(path)) {
        return meshStorage.get(path).?;
    }

    return null;
}

pub fn getOrAddMesh(path: [:0]const u8) !*io.ModelData {
    if (meshStorage.contains(path)) {
        return meshStorage.get(path).?;
    }

    return addMesh(path);
}

pub fn addMesh(path: [:0]const u8) !*io.ModelData {
    const new = try core.mem.heap.create(io.ModelData);
    new.* = try io.loadModelFromFile(path);

    try meshStorage.put(path, new);

    return new;
}

pub fn removeMesh(path: [:0]const u8) ?*io.Mesh {
    const toDel = getMeshOrNull(path);

    _ = meshStorage.remove(path);

    return toDel;
}

pub fn removeAndDeleteMesh(path: [:0]const u8) void {
    const toDel = getMeshOrNull(path);
    if (toDel) |td| {
        td.deinit();
    }

    _ = meshStorage.remove(path);
}
