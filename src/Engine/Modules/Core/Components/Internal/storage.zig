const util = @import("util");

const io = @import("io.zig");

var meshStorage = util.StringHashMap(*io.ModelData).init(util.mem.heap);

//pub var defaultTexture: io.Image = undefined;

pub fn init() !void {
    //defaultTexture = try io.stbi.Image.loadFromFile("resources/defaultTexture.png", 4);
}

pub fn deinit() void {
    //defaultTexture.deinit();

    var iter = meshStorage.valueIterator();

    var item = iter.next();
    while (item) |i| {
        i.*.*.deinit();
        util.mem.heap.destroy(i.*);
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
    const new = try util.mem.heap.create(io.ModelData);
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
