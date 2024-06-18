const std = @import("std");
const vkgen = @import("vulkan_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    std.log.info("Compiling for: {s}-{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag), @tagName(target.result.abi) });
    std.log.info("Compiling in Mode: {s}", .{@tagName(optimize)});

    const exe = b.addExecutable(.{
        .name = "run",
        .root_source_file = b.path("src/entryPoint.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/tests/OsCompatibility.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zmath = b.dependency("zmath", .{});
    const zglfw = b.dependency("zglfw", .{});
    const zphysics = b.dependency("zphysics", .{
        .use_double_precision = false,
        .enable_cross_platform_determinism = true,
    });
    const vkzig = b.dependency("vulkan_zig", .{
        .registry = @as([]const u8, b.pathFromRoot("libs/vulkan//vk.xml")),
    });
    const zmesh = b.dependency("zmesh", .{});

    const graphics = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/graphics/graphics.zig"),
        .link_libc = true,
        .link_libcpp = true,
    });

    const core = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Core/core.zig"),
    });

    graphics.addImport("vulkan", vkzig.module("vulkan-zig"));
    graphics.addImport("zglfw", zglfw.module("root"));
    graphics.addImport("core", core);
    graphics.addIncludePath(b.path("libs/vulkan/"));
    graphics.linkLibrary(zglfw.artifact("glfw"));
    graphics.addCSourceFile(.{
        .file = b.path("libs/vulkan/vk_mem_alloc.cpp"),
        .flags = &.{ "-std=c++17", "-DVMA_IMPLEMENTATION", "-DVMA_DYNAMIC_VULKAN_FUNCTIONS=0", "-DVMA_STATIC_VULKAN_FUNCTIONS=0" },
    });

    const shader_comp = vkgen.ShaderCompileStep.create(
        b,
        &[_][]const u8{ "glslc", "--target-env=vulkan1.2" },
        "-o",
    );
    shader_comp.add("shader_frag", "resources/fragment_shader.frag", .{});
    shader_comp.add("shader_vert", "resources/vertex_shader.vert", .{});

    for ([_]*std.Build.Step.Compile{ exe, tests }) |cmp| {
        cmp.root_module.addImport("shaders", shader_comp.getModule());

        cmp.root_module.addImport("zphysics", zphysics.module("root"));
        cmp.linkLibrary(zphysics.artifact("joltc"));

        cmp.root_module.addImport("zmath", zmath.module("root"));

        cmp.root_module.addImport("zmesh", zmesh.module("root"));
        cmp.linkLibrary(zmesh.artifact("zmesh"));

        cmp.root_module.addImport("graphics", graphics);
        cmp.root_module.addImport("core", core);

        @import("system_sdk").addLibraryPathsTo(cmp);

        b.installArtifact(cmp);

        const cmd = b.addRunArtifact(cmp);
        cmd.step.dependOn(b.getInstallStep());

        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        if (b.args) |args| {
            cmd.addArgs(args);
        }

        const step = b.step(cmp.name, "");
        step.dependOn(&cmd.step);
    }
}
