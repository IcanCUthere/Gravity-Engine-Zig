const builtin = @import("builtin");
const util = @import("util");

const flecs = @import("zflecs");

var loadedNames = util.ArrayList([]const u8).init(util.mem.heap);
var openModules = util.ArrayList(Module).init(util.mem.heap);

pub const Module = struct {
    lib: util.DynLib,

    getName: GetNameFn,
    getDependencies: GetDependenciesFn,
    getDependencyCount: GetDependencyCountFn,

    load: LoadFn,
    start: StartFn,
    stop: StopFn,
    unload: UnloadFn,

    pub fn init(libName: []const u8) !@This() {
        var lib = try util.DynLib.open(libName);
        errdefer lib.close();

        return Module{
            .lib = lib,
            .getName = try GetNameFn.init(&lib, "getName"),
            .getDependencies = try GetDependenciesFn.init(&lib, "getDependencies"),
            .getDependencyCount = try GetDependencyCountFn.init(&lib, "getDependencyCount"),
            .load = try LoadFn.init(&lib, "load"),
            .start = try StartFn.init(&lib, "start"),
            .stop = try StopFn.init(&lib, "stop"),
            .unload = try UnloadFn.init(&lib, "unload"),
        };
    }

    pub fn deinit(self: @This()) void {
        self.lib.close();
    }

    pub fn getZigDependencies(self: @This()) ![]const []const u8 {
        const dependencyCount = self.getDependencyCount.call();
        const dependencies = self.getDependencies.call();

        const zigDependencies = try util.mem.fixedBuffer.alloc([]const u8, dependencyCount);

        for (zigDependencies, dependencies[0..dependencyCount]) |*zigDep, cDep| {
            zigDep.* = util.mem.sliceTo(cDep, 0);
        }

        return zigDependencies;
    }

    fn ModuleFn(T: type) type {
        return struct {
            name: []const u8,
            call: T,

            fn init(lib: *util.DynLib, name: [:0]const u8) !@This() {
                return .{
                    .name = name,
                    .call = lib.*.lookup(T, name) orelse return error.FunctionNotLoadable,
                };
            }
        };
    }

    const GetNameFn = ModuleFn(*const fn () callconv(.c) [*:0]const u8);
    const GetDependenciesFn = ModuleFn(*const fn () callconv(.c) [*]const [*:0]const u8);
    const GetDependencyCountFn = ModuleFn(*const fn () callconv(.c) usize);

    const LoadFn = ModuleFn(*const fn (scene: *flecs.world_t) callconv(.c) bool);
    const StartFn = ModuleFn(*const fn () callconv(.c) bool);
    const StopFn = ModuleFn(*const fn () callconv(.c) bool);
    const UnloadFn = ModuleFn(*const fn () callconv(.c) bool);
};

pub fn ForwardIter(T: type) type {
    return struct {
        order: []const T,

        pub fn init(modules: []const T) @This() {
            return @This(){
                .order = modules,
            };
        }

        pub fn next(self: *@This()) ?T {
            if (self.order.len == 0) {
                return null;
            }

            const nxt = self.order[0];
            self.order = self.order[1..];
            return nxt;
        }
    };
}

pub fn BackwardIter(T: type) type {
    return struct {
        order: []const T,

        pub fn init(modules: []const T) @This() {
            return @This(){
                .order = modules,
            };
        }

        pub fn next(self: *@This()) ?T {
            if (self.order.len == 0) {
                return null;
            }

            const nxt = self.order[self.order.len - 1];
            self.order = self.order[0 .. self.order.len - 1];
            return nxt;
        }
    };
}

pub fn loadDLLs(scene: *flecs.world_t) !void {
    const names = try getLibNames();

    var iter = ForwardIter([]const u8).init(names);
    while (iter.next()) |name| {
        util.log.print(
            "Loading functions from file {s}",
            .{name},
            .Info,
            .Abstract,
            .{ .Modules = true },
        );

        const new = try openModules.addOne();
        new.* = try Module.init(name);
    }

    openModules = try sortModulesOnDependencies(&openModules);

    var moduleIter = ForwardIter(Module).init(openModules.items);
    while (moduleIter.next()) |module| {
        util.log.print(
            "Loading Module {s}",
            .{module.getName.call()},
            .Info,
            .Abstract,
            .{ .Modules = true },
        );

        if (!module.load.call(scene)) {
            return error.FailedToLoadModule;
        }
    }
}

fn sortModulesOnDependencies(modules: *util.ArrayList(Module)) !util.ArrayList(Module) {
    var result = util.ArrayList(Module).init(util.mem.heap);

    var loadedDependencies = util.ArrayList([]const u8).init(util.mem.fixedBuffer);
    defer loadedDependencies.deinit();

    var hasAddedModule = true;
    while (hasAddedModule) {
        hasAddedModule = false;

        // Iterate backward, so removing elements doesnt mess up iteration
        var iter = BackwardIter(Module).init(modules.items);
        var index: usize = modules.items.len;
        while (iter.next()) |module| : (index -= 1) {
            const zigDeps = try module.getZigDependencies();
            defer util.mem.fixedBuffer.free(zigDeps);

            if (!dependenciesLoaded(
                zigDeps,
                loadedDependencies.items,
            )) {
                continue;
            }

            const newDep = try loadedDependencies.addOne();
            newDep.* = util.mem.sliceTo(module.getName.call(), 0);

            const newMod = try result.addOne();
            newMod.* = modules.orderedRemove(index - 1);

            hasAddedModule = true;
        }
    }

    if (modules.items.len > 0) {
        // Error
    }

    modules.deinit();
    return result;
}

fn dependenciesLoaded(requiredDep: []const []const u8, loadedDep: []const []const u8) bool {
    for (requiredDep) |required| {
        _ = for (loadedDep) |loaded| {
            if (util.mem.eql(u8, required, loaded)) {
                break;
            }
        } else return false;
    }

    return true;
}

fn getLibNames() ![][]const u8 {
    var result = util.ArrayList([]const u8).init(util.mem.heap);

    // Get the path to the running executable
    const exe_path = try util.fs.selfExePathAlloc(util.mem.fixedBuffer);
    defer util.mem.fixedBuffer.free(exe_path);

    // Get the directory the executable is in
    const exe_dir = util.fs.path.dirname(exe_path) orelse ".";

    // Open that directory
    var dir = try util.fs.openDirAbsolute(exe_dir, .{
        .iterate = true,
    });
    defer dir.close();

    // Start iterating over the files
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            if (!isDynamicLibrary(entry)) {
                continue;
            }

            const nameCopy = try util.mem.heap.alloc(u8, entry.name.len);
            util.mem.copyForwards(u8, nameCopy, entry.name);

            const new = try result.addOne();
            new.* = stripFileEnding(nameCopy);
        }
    }

    return result.items;
}

fn isDynamicLibrary(file: util.fs.Dir.Entry) bool {
    if (util.mem.endsWith(u8, file.name, ".dll")) {
        return true;
    }
    if (util.mem.endsWith(u8, file.name, ".so")) {
        return true;
    }
    if (util.mem.endsWith(u8, file.name, ".dylib")) {
        return true;
    }

    return false;
}

fn stripFileEnding(fileName: []const u8) []const u8 {
    const ext = util.fs.path.extension(fileName);
    return fileName[0 .. fileName.len - ext.len];
}

pub fn loadStatic(scene: *flecs.world_t, modules: []const type) !void {
    comptime var iter = ForwardIter(type).init(modules);

    inline while (iter.next()) |module| {
        util.log.print(
            "Loading Module {s}",
            .{module.name},
            .Info,
            .Abstract,
            .{ .Modules = true },
        );

        if (isModuleLoaded(module.name)) {
            util.log.print(
                "Module {s} already loaded",
                .{module.name},
                .Critical,
                .Abstract,
                .{ .Modules = true },
            );

            return error.ModuleAlreadyLoaded;
        }

        for (module.dependencies) |d| {
            if (!isModuleLoaded(d)) {
                util.log.print(
                    "Module {s} depends on module {s}, but was not loaded",
                    .{ module.name, d },
                    .Critical,
                    .Abstract,
                    .{ .Modules = true },
                );

                return error.ModuleDependencyNotLoaded;
            }
        }

        _ = module.load(scene);
        try loadedNames.append(module.name);
    }
}

pub fn startStatic(modules: []const type) !void {
    comptime var iter = ForwardIter(type).init(modules);
    inline while (iter.next()) |module| {
        util.log.print(
            "Starting Module {s}",
            .{module.name},
            .Info,
            .Abstract,
            .{ .Modules = true },
        );

        _ = module.start();
    }
}

pub fn stopStatic(modules: []const type) !void {
    comptime var iter = BackwardIter(type).init(modules);

    inline while (iter.next()) |module| {
        util.log.print(
            "Stopping Module {s}",
            .{module.name},
            .Info,
            .Abstract,
            .{ .Modules = true },
        );

        _ = module.stop();
    }
}

pub fn unloadStatic(modules: []const type) !void {
    comptime var iter = BackwardIter(type).init(modules);

    inline while (iter.next()) |module| {
        util.log.print(
            "Unloading Module {s}",
            .{module.name},
            .Info,
            .Abstract,
            .{ .Modules = true },
        );

        _ = module.unload();
    }

    loadedNames.deinit();
}

fn isModuleLoaded(name: []const u8) bool {
    for (loadedNames.items) |m| {
        if (util.mem.eql(u8, name, m)) {
            return true;
        }
    }

    return false;
}
