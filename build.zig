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
    const zstbi = b.dependency("zstbi", .{});
    const zflecs = b.dependency("zflecs", .{});
    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = true,
        .enable_fibers = true,
    });

    const core = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Core/core.zig"),
    });
    core.addImport("zmath", zmath.module("root"));

    const coreModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Application/Modules/Core/core.zig"),
    });
    coreModule.addImport("zflecs", zflecs.module("root"));
    coreModule.addImport("ztracy", ztracy.module("root"));
    coreModule.addImport("zstbi", zstbi.module("root"));
    coreModule.addImport("zmesh", zmesh.module("root"));
    coreModule.addImport("core", core);

    const graphicsModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Application/Modules/Graphics/graphics.zig"),
    });
    graphicsModule.addImport("zflecs", zflecs.module("root"));
    graphicsModule.addImport("ztracy", ztracy.module("root"));
    graphicsModule.addImport("CoreModule", coreModule);
    graphicsModule.addImport("core", core);
    graphicsModule.addImport("vulkan", vkzig.module("vulkan-zig"));
    graphicsModule.addImport("zglfw", zglfw.module("root"));
    graphicsModule.addImport("zstbi", zstbi.module("root"));
    graphicsModule.addIncludePath(b.path("libs/vulkan/"));
    graphicsModule.addCSourceFile(.{
        .file = b.path("libs/vulkan/vk_mem_alloc.cpp"),
        .flags = &.{ "-std=c++17", "-DVMA_IMPLEMENTATION", "-DVMA_DYNAMIC_VULKAN_FUNCTIONS=0", "-DVMA_STATIC_VULKAN_FUNCTIONS=0" },
    });

    const editorModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Application/Modules/Editor/editor.zig"),
    });
    editorModule.addImport("zflecs", zflecs.module("root"));
    editorModule.addImport("ztracy", ztracy.module("root"));
    editorModule.addImport("CoreModule", coreModule);
    editorModule.addImport("GraphicsModule", graphicsModule);
    editorModule.addImport("core", core);

    const gameModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Application/Modules/Game/game.zig"),
    });
    gameModule.addImport("zflecs", zflecs.module("root"));
    gameModule.addImport("ztracy", ztracy.module("root"));
    gameModule.addImport("CoreModule", coreModule);
    gameModule.addImport("GraphicsModule", graphicsModule);
    gameModule.addImport("core", core);

    const modulesModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Application/Modules/modules.zig"),
    });
    modulesModule.addImport("CoreModule", coreModule);
    modulesModule.addImport("GraphicsModule", graphicsModule);
    modulesModule.addImport("EditorModule", editorModule);
    modulesModule.addImport("GameModule", gameModule);

    const shader_comp = vkgen.ShaderCompileStep.create(
        b,
        &[_][]const u8{ "glslc", "--target-env=vulkan1.2" },
        "-o",
    );
    shader_comp.add("shader_frag", "resources/fragment_shader.frag", .{});
    shader_comp.add("shader_vert", "resources/vertex_shader.vert", .{});

    graphicsModule.addImport("shaders", shader_comp.getModule());

    for ([_]*std.Build.Step.Compile{ exe, tests }) |cmp| {
        cmp.root_module.addImport("zphysics", zphysics.module("root"));
        cmp.root_module.addImport("ztracy", ztracy.module("root"));
        cmp.root_module.addImport("core", core);
        cmp.root_module.addImport("modules", modulesModule);
        cmp.root_module.addImport("zflecs", zflecs.module("root"));

        @import("system_sdk").addLibraryPathsTo(cmp);
        cmp.linkLibrary(ztracy.artifact("tracy"));
        cmp.linkLibrary(zglfw.artifact("glfw"));
        cmp.linkLibrary(zstbi.artifact("zstbi"));
        cmp.linkLibrary(zflecs.artifact("flecs"));
        cmp.linkLibrary(zmesh.artifact("zmesh"));
        cmp.linkLibrary(zphysics.artifact("joltc"));

        //Not needed, but helps zls
        cmp.root_module.addImport("vulkan", vkzig.module("vulkan-zig"));
        cmp.root_module.addIncludePath(b.path("libs/vulkan/"));
        cmp.root_module.addImport("zglfw", zglfw.module("root"));
        cmp.root_module.addImport("zstbi", zstbi.module("root"));
        cmp.root_module.addImport("zmath", zmath.module("root"));
        cmp.root_module.addImport("core", core);
        cmp.root_module.addImport("CoreModule", coreModule);
        cmp.root_module.addImport("GraphicsModule", graphicsModule);
        cmp.root_module.addImport("EditorModule", editorModule);
        cmp.root_module.addImport("GameModule", gameModule);
        cmp.root_module.addImport("shaders", shader_comp.getModule());

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
