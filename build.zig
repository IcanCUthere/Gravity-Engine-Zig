const std = @import("std");
const vkgen = @import("vulkan_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    std.log.info("Compiling for: {s}-{s}-{s}\n", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag), @tagName(target.result.abi) });

    const exe = b.addExecutable(.{
        .name = "run",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    for ([_]*std.Build.Step.Compile{ exe, tests }) |cmp| {
        const vkzig = b.dependency("vulkan_zig", .{
            .registry = @as([]const u8, b.pathFromRoot("libs/vk.xml")),
        });
        cmp.root_module.addImport("vulkan", vkzig.module("vulkan-zig"));

        const shader_comp = vkgen.ShaderCompileStep.create(
            b,
            &[_][]const u8{ "glslc", "--target-env=vulkan1.2" },
            "-o",
        );
        shader_comp.add("shader_frag", "fragment_shader.frag", .{});
        shader_comp.add("shader_vert", "vertex_shader.vert", .{});
        cmp.root_module.addImport("shaders", shader_comp.getModule());

        const zphysics = b.dependency("zphysics", .{
            .use_double_precision = false,
            .enable_cross_platform_determinism = true,
        });
        cmp.root_module.addImport("zphysics", zphysics.module("root"));
        cmp.linkLibrary(zphysics.artifact("joltc"));

        const zglfw = b.dependency("zglfw", .{});
        cmp.root_module.addImport("zglfw", zglfw.module("root"));
        cmp.linkLibrary(zglfw.artifact("glfw"));

        const zmath = b.dependency("zmath", .{});
        cmp.root_module.addImport("zmath", zmath.module("root"));

        @import("system_sdk").addLibraryPathsTo(cmp);

        cmp.addIncludePath(b.path("libs/vulkan"));

        cmp.linkLibC();
        cmp.linkLibCpp();
        cmp.addCSourceFile(.{
            .file = b.path("libs/vulkan/vk_mem_alloc.cpp"),
            .flags = &.{ "-std=c++17", "-DVMA_IMPLEMENTATION", "-DVMA_DYNAMIC_VULKAN_FUNCTIONS=0", "-DVMA_STATIC_VULKAN_FUNCTIONS=0" },
        });

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
