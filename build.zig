const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    std.log.info("Compiling for: {s}-{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag), @tagName(target.result.abi) });
    std.log.info("Compiling in Mode: {s}\n", .{@tagName(optimize)});

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
    const zgui = b.dependency("zgui", .{
        .shared = false,
        .backend = .glfw_vulkan,
    });
    const zshaderc = b.dependency("zshaderc", .{});
    b.getInstallStep().dependOn(zshaderc.builder.getInstallStep());

    const utils = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Utility/utils.zig"),
    });
    utils.addImport("zmath", zmath.module("root"));
    utils.addImport("zflecs", zflecs.module("root"));

    const coreModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Engine/Modules/Core/core.zig"),
    });
    coreModule.addImport("zflecs", zflecs.module("root"));
    coreModule.addImport("ztracy", ztracy.module("root"));
    coreModule.addImport("zstbi", zstbi.module("root"));
    coreModule.addImport("zmesh", zmesh.module("root"));
    coreModule.addImport("util", utils);

    const graphicsModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Engine/Modules/Graphics/graphics.zig"),
    });
    graphicsModule.addImport("zflecs", zflecs.module("root"));
    graphicsModule.addImport("ztracy", ztracy.module("root"));
    graphicsModule.addImport("zglfw", zglfw.module("root"));
    graphicsModule.addImport("zstbi", zstbi.module("root"));
    graphicsModule.addImport("zshaderc", zshaderc.module("root"));
    graphicsModule.addImport("CoreModule", coreModule);
    graphicsModule.addImport("util", utils);
    graphicsModule.addImport("vulkan", vkzig.module("vulkan-zig"));
    graphicsModule.addIncludePath(b.path("libs/vulkan/"));
    graphicsModule.addCSourceFile(.{
        .file = b.path("libs/vulkan/vk_mem_alloc.cpp"),
        .flags = &.{ "-std=c++17", "-DVMA_IMPLEMENTATION", "-DVMA_DYNAMIC_VULKAN_FUNCTIONS=0", "-DVMA_STATIC_VULKAN_FUNCTIONS=0" },
    });

    const editorModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Engine/Modules/Editor/editor.zig"),
    });
    editorModule.addImport("zflecs", zflecs.module("root"));
    editorModule.addImport("ztracy", ztracy.module("root"));
    editorModule.addImport("zgui", zgui.module("root"));
    editorModule.addImport("CoreModule", coreModule);
    editorModule.addImport("GraphicsModule", graphicsModule);
    editorModule.addImport("util", utils);

    const gameModule = b.createModule(std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/Engine/Modules/Game/game.zig"),
    });
    gameModule.addImport("zflecs", zflecs.module("root"));
    gameModule.addImport("ztracy", ztracy.module("root"));
    gameModule.addImport("CoreModule", coreModule);
    gameModule.addImport("GraphicsModule", graphicsModule);
    gameModule.addImport("util", utils);

    for ([_]*std.Build.Step.Compile{ exe, tests }) |cmp| {
        @import("system_sdk").addLibraryPathsTo(cmp);
        cmp.linkLibrary(ztracy.artifact("tracy"));
        cmp.linkLibrary(zglfw.artifact("glfw"));
        cmp.linkLibrary(zstbi.artifact("zstbi"));
        cmp.linkLibrary(zflecs.artifact("flecs"));
        cmp.linkLibrary(zmesh.artifact("zmesh"));
        cmp.linkLibrary(zphysics.artifact("joltc"));
        cmp.linkLibrary(zgui.artifact("imgui"));

        //Not needed, but helps zls
        cmp.root_module.addImport("vulkan", vkzig.module("vulkan-zig"));
        cmp.root_module.addIncludePath(b.path("libs/vulkan/"));

        cmp.root_module.addImport("zglfw", zglfw.module("root"));
        cmp.root_module.addImport("zstbi", zstbi.module("root"));
        cmp.root_module.addImport("zmath", zmath.module("root"));
        cmp.root_module.addImport("zmesh", zmesh.module("root"));
        cmp.root_module.addImport("zgui", zgui.module("root"));
        cmp.root_module.addImport("zphysics", zphysics.module("root"));
        cmp.root_module.addImport("ztracy", ztracy.module("root"));
        cmp.root_module.addImport("zflecs", zflecs.module("root"));
        cmp.root_module.addImport("zshaderc", zshaderc.module("root"));

        cmp.root_module.addImport("util", utils);
        cmp.root_module.addImport("CoreModule", coreModule);
        cmp.root_module.addImport("GraphicsModule", graphicsModule);
        cmp.root_module.addImport("EditorModule", editorModule);
        cmp.root_module.addImport("GameModule", gameModule);

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
