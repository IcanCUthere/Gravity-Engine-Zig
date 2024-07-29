const std = @import("std");

var GenAlloc = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = GenAlloc.allocator();

//Subpaths of SPIRV-Tools/source that we dont need to build shaderc, makes compile faster
//If we include fuzz and wasm files, we get errors
const ignoredSubpaths = [_][]const u8{
    "fuzz",
    "wasm",
    "reduce",
    "diff",
    "lint",
    "link",
};

fn isTestFile(fileName: []const u8) bool {
    if (fileName.len < 4) return false;

    //testfiles end with "test"
    if (!std.mem.eql(u8, fileName[fileName.len - 4 ..], "test"))
        return false;

    return true;
}

fn isIgnored(path: []const u8) bool {
    var iter = std.mem.split(u8, path, "\\");

    while (iter.next()) |subpath| {
        for (ignoredSubpaths) |ignored| {
            if (std.mem.eql(u8, subpath, ignored)) {
                return true;
            }
        }
    }

    return false;
}

fn findCppFilesInPath(comptime subPath: []const u8, ext: []const u8) ![][]const u8 {
    var res = std.ArrayList([]const u8).init(allocator);

    const path = @src().file;
    const trimmed = path[0 .. path.len - 9];

    var dir = try std.fs.openDirAbsolute(
        trimmed ++ subPath,
        .{
            .iterate = true,
        },
    );

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    outer: while (try walker.next()) |next| {
        if (next.basename.len >= ext.len) {
            //Check if file has required extension
            if (!std.mem.eql(u8, ext, next.basename[next.basename.len - ext.len ..]))
                continue :outer;

            //Some files are just for testing, ignore them
            if (isTestFile(next.basename[0 .. next.basename.len - ext.len]))
                continue :outer;

            if (isIgnored(next.path))
                continue :outer;

            const newPath = try allocator.alloc(u8, next.path.len);
            std.mem.copyForwards(u8, newPath, next.path);

            const new = try res.addOne();
            new.* = newPath;
        }
    }

    return try res.toOwnedSlice();
}

const out_dir = "libs/build_out/";
const header_dir = "libs/SPIRV-Headers/include/";

fn coreTable(b: *std.Build) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/generate_grammar_tables.py",
        "--spirv-core-grammar=" ++ header_dir ++ "spirv/unified1/spirv.core.grammar.json",
        "--extinst-debuginfo-grammar=" ++ header_dir ++ "spirv/unified1/extinst.debuginfo.grammar.json",
        "--extinst-cldebuginfo100-grammar=" ++ header_dir ++ "spirv/unified1/extinst.opencl.debuginfo.100.grammar.json",
        "--core-insts-output=" ++ out_dir ++ "core.insts-unified1.inc",
        "--operand-kinds-output=" ++ out_dir ++ "operand.kinds-unified1.inc",
        "--output-language=c++",
    });

    b.getInstallStep().dependOn(&run_py.step);
}

fn enumStringMapping(b: *std.Build) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/generate_grammar_tables.py",
        "--spirv-core-grammar=" ++ header_dir ++ "spirv/unified1/spirv.core.grammar.json",
        "--extinst-debuginfo-grammar=" ++ header_dir ++ "spirv/unified1/extinst.debuginfo.grammar.json",
        "--extinst-cldebuginfo100-grammar=" ++ header_dir ++ "spirv/unified1/extinst.opencl.debuginfo.100.grammar.json",
        "--extension-enum-output=" ++ out_dir ++ "extension_enum.inc",
        "--enum-string-mapping-output=" ++ out_dir ++ "enum_string_mapping.inc",
        "--output-language=c++",
    });

    b.getInstallStep().dependOn(&run_py.step);
}

fn openClTable(b: *std.Build) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/generate_grammar_tables.py",
        "--extinst-opencl-grammar=" ++ header_dir ++ "spirv/unified1/extinst.opencl.std.100.grammar.json",
        "--opencl-insts-output=" ++ out_dir ++ "opencl.std.insts.inc",
    });

    b.getInstallStep().dependOn(&run_py.step);
}

fn glslTable(b: *std.Build) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/generate_grammar_tables.py",
        "--extinst-glsl-grammar=" ++ header_dir ++ "spirv/unified1/extinst.glsl.std.450.grammar.json",
        "--glsl-insts-output=" ++ out_dir ++ "glsl.std.450.insts.inc",
        "--output-language=c++",
    });

    b.getInstallStep().dependOn(&run_py.step);
}

fn vendorTable(b: *std.Build, comptime table: []const u8, comptime kind: []const u8) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/generate_grammar_tables.py",
        "--extinst-vendor-grammar=" ++ header_dir ++ "/spirv/unified1/extinst." ++ table ++ ".grammar.json",
        "--vendor-insts-output=" ++ out_dir ++ table ++ ".insts.inc",
        "--vendor-operand-kind-prefix=" ++ kind,
    });

    b.getInstallStep().dependOn(&run_py.step);
}

fn buildVersion(b: *std.Build) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/update_build_version.py",
        "libs/SPIRV-Tools/CHANGES",
        out_dir ++ "build-version.inc",
    });

    b.getInstallStep().dependOn(&run_py.step);
}

fn generators(b: *std.Build) void {
    const run_py = b.addSystemCommand(&[_][]const u8{
        "python3",
        "libs/SPIRV-Tools/utils/generate_registry_tables.py",
        "--xml=" ++ header_dir ++ "spirv/spir-v.xml",
        "--generator-output=" ++ out_dir ++ "generators.inc",
    });

    b.getInstallStep().dependOn(&run_py.step);
}

pub fn build(b: *std.Build) !void {
    //Same as in SPIRV-Tools/CMakeLists.txt
    //Runs python commands, that output files that are needed for compilation
    coreTable(b);
    enumStringMapping(b);
    openClTable(b);
    glslTable(b);
    vendorTable(b, "spv-amd-shader-explicit-vertex-parameter", "");
    vendorTable(b, "spv-amd-shader-trinary-minmax", "");
    vendorTable(b, "spv-amd-gcn-shader", "");
    vendorTable(b, "spv-amd-shader-ballot", "");
    vendorTable(b, "debuginfo", "");
    vendorTable(b, "opencl.debuginfo.100", "CLDEBUG100_");
    vendorTable(b, "nonsemantic.shader.debuginfo.100", "SHDEBUG100_");
    vendorTable(b, "nonsemantic.clspvreflection", "");
    vendorTable(b, "nonsemantic.vkspreflection", "");
    buildVersion(b);
    generators(b);

    var outDir = try std.fs.openDirAbsolute(b.path(out_dir).getPath(b), .{});
    defer outDir.close();

    outDir.makeDir("glslang") catch {};
    var file = try outDir.createFile("glslang\\build_info.h", .{});
    defer file.close();

    _ = try file.write("#define GLSLANG_VERSION_MAJOR 0\n");
    _ = try file.write("#define GLSLANG_VERSION_MINOR 0\n");
    _ = try file.write("#define GLSLANG_VERSION_PATCH 0\n");
    _ = try file.write("#define GLSLANG_VERSION_FLAVOR \"0\"\n");

    const zshaderc = b.addModule("root", .{
        .root_source_file = b.path("src/main.zig"),
    });

    zshaderc.addIncludePath(b.path("libs/libshaderc/include"));
    zshaderc.addIncludePath(b.path("libs/libshaderc_util/include"));
    zshaderc.addIncludePath(b.path("libs/SPIRV-Tools/include"));
    zshaderc.addIncludePath(b.path("libs/glslang"));
    zshaderc.addIncludePath(b.path("libs/SPIRV-Headers/include"));
    zshaderc.addIncludePath(b.path("libs/SPIRV-Headers/include/spirv/unified1"));
    zshaderc.addIncludePath(b.path("libs/SPIRV-Tools"));
    zshaderc.addIncludePath(b.path(out_dir));

    const glslangSpv = try findCppFilesInPath("libs/glslang/SPIRV", ".cpp");
    defer allocator.free(glslangSpv);

    zshaderc.addCSourceFiles(.{
        .root = b.path("libs/glslang/SPIRV"),
        .files = glslangSpv,
        .flags = &.{},
    });

    const glslangMachInd = try findCppFilesInPath("libs/glslang/glslang/MachineIndependent", ".cpp");
    defer allocator.free(glslangMachInd);

    zshaderc.addCSourceFiles(.{
        .root = b.path("libs/glslang/glslang/MachineIndependent"),
        .files = glslangMachInd,
        .flags = &.{"-DENABLE_HLSL"},
    });

    const hlsl = try findCppFilesInPath("libs/glslang/glslang/HLSL", ".cpp");
    defer allocator.free(hlsl);

    zshaderc.addCSourceFiles(.{
        .root = b.path("libs/glslang/glslang/HLSL"),
        .files = hlsl,
        .flags = &.{"-DENABLE_HLSL"},
    });

    const genCodeGen = try findCppFilesInPath("libs/glslang/glslang/GenericCodeGen", ".cpp");
    defer allocator.free(genCodeGen);

    zshaderc.addCSourceFiles(.{
        .root = b.path("libs/glslang/glslang/GenericCodeGen/"),
        .files = genCodeGen,
        .flags = &.{"-DENABLE_HLSL"},
    });

    const shadercUtil = try findCppFilesInPath("libs/libshaderc_util/src", ".cc");
    defer allocator.free(shadercUtil);

    zshaderc.addCSourceFiles(.{
        .root = b.path("libs/libshaderc_util/src"),
        .files = shadercUtil,
        .flags = &.{"-DENABLE_HLSL"},
    });

    const spirvTools = try findCppFilesInPath("libs/SPIRV-Tools/source", ".cpp");
    defer allocator.free(spirvTools);

    zshaderc.addCSourceFiles(.{
        .root = b.path("libs/SPIRV-Tools/source"),
        .files = spirvTools,
        .flags = &.{"-DENABLE_HLSL"},
    });

    zshaderc.addCSourceFile(.{
        .file = b.path("libs/libshaderc/src/shaderc.cc"),
        .flags = &.{},
    });
}
