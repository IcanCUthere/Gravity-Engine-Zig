const util = @import("util");
const mem = util.mem;

pub const stbi = @import("zstbi");
pub const msh = @import("zmesh");
pub const gltf = msh.io.zcgltf;

const storage = @import("storage.zig");

pub const Vertex = struct {
    pos: [3]f32,
    normal: [3]f32,
    texCoords: [2]f32,
};

pub const Mesh = struct {
    const Self = @This();

    vertexData: []Vertex,
    indexData: []u32,
};

pub const Image = stbi.Image;

pub const ModelData = struct {
    mesh: Mesh,
    baseColor: Image,
    normals: Image,
    metallicRoughness: Image,
    occlusion: Image,

    pub fn deinit(self: *ModelData) void {
        self.baseColor.deinit();
        self.normals.deinit();
        self.metallicRoughness.deinit();
        self.occlusion.deinit();
        util.mem.heap.free(self.mesh.vertexData);
        util.mem.heap.free(self.mesh.indexData);
    }
};

pub fn loadModelFromFile(path: [:0]const u8) !ModelData {
    util.log.print("Loading model from file: {s}", .{path}, .Info, .Abstract, .{ .MeshLoading = true });

    var model: ModelData = undefined;

    const gltfData = try msh.io.parseAndLoadFile(path);
    defer msh.io.freeData(gltfData);

    if (gltfData.meshes_count == 0) {
        util.log.print("No meshes found", .{}, .Warning, .Abstract, .{ .MeshLoading = true });
        return error.LoadNoMesh;
    }

    util.log.print("Mesh count: {d}", .{gltfData.meshes_count}, .Info, .Verbose, .{ .MeshLoading = true });

    for (0..gltfData.meshes_count) |i| {
        const mesh = gltfData.meshes.?[i];

        util.log.print("Primitive count: {d}", .{mesh.primitives_count}, .Info, .Verbose, .{ .MeshLoading = true });

        for (0..mesh.primitives_count) |j| {
            const primitive = mesh.primitives[j];

            model.mesh.vertexData = try loadVertexData(primitive);
            model.mesh.indexData = try loadIndexData(primitive);

            if (primitive.material) |mat| {
                util.log.print("Metallic: {d}", .{mat.has_pbr_metallic_roughness}, .Info, .Verbose, .{ .MeshLoading = true });
                util.log.print("Specular: {d}", .{mat.has_pbr_specular_glossiness}, .Info, .Verbose, .{ .MeshLoading = true });
                util.log.print("Unlit: {d}", .{mat.unlit}, .Info, .Verbose, .{ .MeshLoading = true });

                if (mat.has_pbr_metallic_roughness != 0) {
                    const metalMat = mat.pbr_metallic_roughness;

                    if (try loadTexture(metalMat.base_color_texture, 4)) |tex| {
                        model.baseColor = tex;
                    } else {
                        util.log.print("Has no base color texture", .{}, .Info, .Verbose, .{ .MeshLoading = true });
                    }

                    if (try loadTexture(metalMat.metallic_roughness_texture, 2)) |tex| {
                        model.metallicRoughness = tex;
                    } else {
                        util.log.print("Has no metallic roughness texture", .{}, .Info, .Verbose, .{ .MeshLoading = true });
                    }

                    if (try loadTexture(mat.normal_texture, 3)) |tex| {
                        model.normals = tex;
                    } else {
                        util.log.print("Has no normal texture", .{}, .Info, .Verbose, .{ .MeshLoading = true });
                    }

                    if (try loadTexture(mat.occlusion_texture, 1)) |tex| {
                        model.occlusion = tex;
                    } else {
                        util.log.print("Has no occlusion texture", .{}, .Info, .Verbose, .{ .MeshLoading = true });
                    }
                }
            } else {
                util.log.print("Has no material", .{}, .Info, .Verbose, .{ .MeshLoading = true });

                model.baseColor = try stbi.Image.loadFromFile("resources/textures/defaultTexture.png", 4);
                model.metallicRoughness = try stbi.Image.loadFromFile("resources/textures/defaultTexture.png", 2);
                model.normals = try stbi.Image.loadFromFile("resources/textures/defaultTexture.png", 3);
                model.occlusion = try stbi.Image.loadFromFile("resources/textures/defaultTexture.png", 1);
            }
        }
    }

    return model;
}

fn loadVertexData(primitive: gltf.Primitive) ![]Vertex {
    var vertexData: []Vertex = undefined;

    var positions: ?[]f32 = null;
    var normals: ?[]f32 = null;
    var texCoords: ?[]f32 = null;

    defer mem.heap.free(positions.?);
    defer mem.heap.free(normals.?);
    defer mem.heap.free(texCoords.?);

    for (0..primitive.attributes_count) |k| {
        const attrib = &primitive.attributes[k];
        const vertices = attrib.data;

        util.log.print("{s}:", .{@tagName(attrib.type)}, .Info, .Verbose, .{ .MeshLoading = true });

        for (0..3) |l| {
            util.log.print("max[{d}]: {d}", .{ l, vertices.max[l] }, .Info, .Verbose, .{ .MeshLoading = true });
        }

        if (attrib.type == gltf.AttributeType.position) {
            positions = try mem.heap.alloc(f32, vertices.unpackFloatsCount());
            positions = vertices.unpackFloats(positions.?);
        } else if (attrib.type == gltf.AttributeType.normal) {
            normals = try mem.heap.alloc(f32, vertices.unpackFloatsCount());
            normals = vertices.unpackFloats(normals.?);
        } else if (attrib.type == gltf.AttributeType.texcoord) {
            texCoords = try mem.heap.alloc(f32, vertices.unpackFloatsCount());
            texCoords = vertices.unpackFloats(texCoords.?);
        }
    }

    if (positions) |posis| {
        //This just convertex []f32 -> [][3]f32
        const pos: [][3]f32 = @as([*][3]f32, @ptrCast(posis.ptr))[0 .. posis.len / 3];

        vertexData = try mem.heap.alloc(Vertex, pos.len);

        if (normals == null) {
            normals = try mem.heap.alloc(f32, pos.len);
        }
        if (texCoords == null) {
            texCoords = try mem.heap.alloc(f32, pos.len * 2 / 3);
        }

        const norm: [][3]f32 = @as([*][3]f32, @ptrCast(normals.?.ptr))[0 .. normals.?.len / 3];
        const tex: [][2]f32 = @as([*][2]f32, @ptrCast(texCoords.?.ptr))[0 .. texCoords.?.len / 2];

        for (vertexData, pos, norm, tex) |*v, p, n, t| {
            v.pos = p;
            v.normal = n;
            v.texCoords = t;
        }

        return vertexData;
    } else {
        util.log.print("Mesh does not have vertex positions", .{}, .Warning, .Abstract, .{ .MeshLoading = true });
        return error.NoVertexPositions;
    }
}

fn loadIndexData(primitive: gltf.Primitive) ![]u32 {
    var indexData: []u32 = undefined;

    if (primitive.indices) |indices| {
        indexData = try mem.heap.alloc(u32, indices.unpackIndicesCount());
        indexData = indices.unpackIndices(indexData);
    } else {
        indexData = try mem.heap.alloc(u32, primitive.attributes[0].data.count);

        for (indexData, 0..) |*l, m| {
            l.* = @intCast(m);
        }
    }

    return indexData;
}

fn loadTexture(texture: gltf.TextureView, components: u32) !?stbi.Image {
    if (texture.texture) |tex| {
        if (tex.image) |img| {
            if (img.buffer_view) |buf| {
                if (gltf.BufferView.data(buf.*)) |data| {
                    if (img.mime_type) |mime| {
                        if (mem.eql(u8, mime[0..9], "image/png") or
                            mem.eql(u8, mime[0..10], "image/jpeg"))
                        {
                            return try stbi.Image.loadFromMemory(data[0..buf.size], components);
                        }
                    }
                }
            }
        }
    }

    return null;
}
