const std = @import("std");
const stbi = @import("zstbi");
const msh = @import("zmesh");
const mem = @import("core").mem;
const gltf = msh.io.zcgltf;

pub const Vertex = struct {
    pos: [3]f32,
    normal: [3]f32,
    texCoords: [2]f32,
};

pub const Material = struct {
    baseColor: stbi.Image,
    normals: stbi.Image,
    occlusion: stbi.Image,
    metallicRoughness: stbi.Image,
};

pub const Mesh = struct {
    const Self = @This();

    vertexData: []Vertex,
    indexData: []u32,
    material: Material,

    pub fn deinit(self: *Self) void {
        self.material.baseColor.deinit();
        self.material.normals.deinit();
        self.material.metallicRoughness.deinit();
        self.material.occlusion.deinit();
    }
};

pub fn loadMeshFromFile(path: [:0]const u8) !Mesh {
    var meshResult: Mesh = undefined;

    const gltfData = try msh.io.parseAndLoadFile(path);
    defer msh.io.freeData(gltfData);

    if (gltfData.meshes_count == 0) {
        std.log.info("No meshes to load", .{});
        return error.LoadNoMesh;
    } else {
        std.log.info("Loading meshes: {s}", .{path});
    }

    std.log.info("Count: {d}", .{gltfData.meshes_count});

    for (0..1) |i| { //testModel.meshes_count) |i| {
        const mesh = gltfData.meshes.?[i];

        std.log.info("Primitives: {d}", .{mesh.primitives_count});

        for (0..mesh.primitives_count) |j| {
            const primitive = mesh.primitives[j];

            meshResult.material = (try loadMaterial(primitive)).?;
            meshResult.vertexData = try loadVertexData(primitive);
            meshResult.indexData = try loadIndexData(primitive);
        }
    }

    return meshResult;
}

fn loadVertexData(primitive: gltf.Primitive) ![]Vertex {
    var vertexData: []Vertex = undefined;

    var positions: ?[]f32 = null;
    var normals: ?[]f32 = null;
    var texCoords: ?[]f32 = null;

    defer mem.ha.free(positions.?);
    defer mem.ha.free(normals.?);
    defer mem.ha.free(texCoords.?);

    for (0..primitive.attributes_count) |k| {
        const attrib = &primitive.attributes[k];
        const vertices = attrib.data;

        std.log.info("{s}", .{@tagName(attrib.type)});

        for (0..3) |l| {
            std.log.info("max[{d}]: {d}", .{ l, vertices.max[l] });
        }

        if (attrib.type == gltf.AttributeType.position) {
            positions = try mem.ha.alloc(f32, vertices.unpackFloatsCount());
            positions = vertices.unpackFloats(positions.?);
        } else if (attrib.type == gltf.AttributeType.normal) {
            normals = try mem.ha.alloc(f32, vertices.unpackFloatsCount());
            normals = vertices.unpackFloats(normals.?);
        } else if (attrib.type == gltf.AttributeType.texcoord) {
            texCoords = try mem.ha.alloc(f32, vertices.unpackFloatsCount());
            texCoords = vertices.unpackFloats(texCoords.?);
        }
    }

    if (positions) |posis| {
        //This just convertex []f32 -> [][3]f32, dont ask, slice casting is not implemented
        const pos: [][3]f32 = @ptrCast(@as([*][3]f32, @ptrCast(@as([*]f32, @ptrCast(posis))[0..posis.len]))[0 .. posis.len / 3]);

        vertexData = try mem.ha.alloc(Vertex, pos.len);

        if (normals == null) {
            normals = try mem.ha.alloc(f32, pos.len);
        }
        if (texCoords == null) {
            texCoords = try mem.ha.alloc(f32, pos.len * 2 / 3);
        }

        const norm: [][3]f32 = @ptrCast(@as([*][3]f32, @ptrCast(@as([*]f32, @ptrCast(normals.?))[0..normals.?.len]))[0 .. normals.?.len / 3]);
        const tex: [][2]f32 = @ptrCast(@as([*][2]f32, @ptrCast(@as([*]f32, @ptrCast(texCoords.?))[0..texCoords.?.len]))[0 .. texCoords.?.len / 2]);

        for (vertexData, pos, norm, tex) |*v, p, n, t| {
            v.pos = p;
            v.normal = n;
            v.texCoords = t;
        }

        return vertexData;
    } else {
        std.log.info("Mesh does not have vertex positions", .{});
        return error.NoVertexPositions;
    }
}

fn loadIndexData(primitive: gltf.Primitive) ![]u32 {
    var indexData: []u32 = undefined;

    if (primitive.indices) |indices| {
        indexData = try mem.ha.alloc(u32, indices.unpackIndicesCount());
        indexData = indices.unpackIndices(indexData);
    } else {
        indexData = try mem.ha.alloc(u32, primitive.attributes[0].data.count);

        for (indexData, 0..) |*l, m| {
            l.* = @intCast(m);
        }
    }

    return indexData;
}

fn loadMaterial(primitive: gltf.Primitive) !?Material {
    var material: Material = undefined;

    if (primitive.material) |mat| {
        std.log.info("Metallic: {d}", .{mat.has_pbr_metallic_roughness});
        std.log.info("Specular: {d}", .{mat.has_pbr_specular_glossiness});
        std.log.info("Unlit: {d}", .{mat.unlit});

        if (mat.has_pbr_metallic_roughness != 0) {
            const metalMat = mat.pbr_metallic_roughness;

            if (try loadTexture(metalMat.base_color_texture, 4)) |tex| {
                material.baseColor = tex;
            }

            if (try loadTexture(metalMat.metallic_roughness_texture, 2)) |tex| {
                material.metallicRoughness = tex;
            }

            if (try loadTexture(mat.normal_texture, 3)) |tex| {
                material.normals = tex;
            }

            if (try loadTexture(mat.occlusion_texture, 1)) |tex| {
                material.occlusion = tex;
            }
        }
    } else {
        return null;
    }

    return material;
}

fn loadTexture(texture: gltf.TextureView, components: u32) !?stbi.Image {
    if (texture.texture) |tex| {
        if (tex.image) |img| {
            if (img.buffer_view) |buf| {
                if (gltf.BufferView.data(buf.*)) |data| {
                    if (img.mime_type) |mime| {
                        if (std.mem.eql(u8, mime[0..9], "image/png") or
                            std.mem.eql(u8, mime[0..10], "image/jpeg"))
                        {
                            return try stbi.Image.loadFromMemory(data[0..buf.size], components);
                        }
                    }
                }
            }
        }
    }

    std.log.info("Texture not found", .{});

    return null;
}
