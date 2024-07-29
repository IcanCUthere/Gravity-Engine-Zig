const std = @import("std");

const shaderc = @cImport(
    @cInclude("shaderc/shaderc.h"),
);

var _allocator: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    _allocator = allocator;
}

pub fn deinit() void {}

pub const ShaderKind = enum(u8) {
    vertex = shaderc.shaderc_vertex_shader,
    fragment = shaderc.shaderc_fragment_shader,
    compute = shaderc.shaderc_compute_shader,
    geometry = shaderc.shaderc_geometry_shader,
    tessControl = shaderc.shaderc_tess_control_shader,
    tessEval = shaderc.shaderc_tess_evaluation_shader,

    inferFromSource = shaderc.shaderc_glsl_infer_from_source,
    defaultVertex = shaderc.shaderc_glsl_default_vertex_shader,
    defaultFragment = shaderc.shaderc_glsl_default_fragment_shader,
    defaultCompute = shaderc.shaderc_glsl_default_compute_shader,
    defaultGeometry = shaderc.shaderc_glsl_default_geometry_shader,
    defaultTessControl = shaderc.shaderc_glsl_default_tess_control_shader,
    defaultTessEval = shaderc.shaderc_glsl_default_tess_evaluation_shader,
    spirvAssembly = shaderc.shaderc_spirv_assembly,

    raygen = shaderc.shaderc_raygen_shader,
    anyhit = shaderc.shaderc_anyhit_shader,
    closesthit = shaderc.shaderc_closesthit_shader,
    miss = shaderc.shaderc_miss_shader,
    intersection = shaderc.shaderc_intersection_shader,
    callable = shaderc.shaderc_callable_shader,

    defaultRaygen = shaderc.shaderc_glsl_default_raygen_shader,
    defaultAnyhit = shaderc.shaderc_glsl_default_anyhit_shader,
    defaultClosesthit = shaderc.shaderc_glsl_default_closesthit_shader,
    defaultMiss = shaderc.shaderc_glsl_default_miss_shader,
    defaultIntersection = shaderc.shaderc_glsl_default_intersection_shader,
    defaultCallable = shaderc.shaderc_glsl_default_callable_shader,

    task = shaderc.shaderc_task_shader,
    mesh = shaderc.shaderc_mesh_shader,

    defaultTask = shaderc.shaderc_glsl_default_task_shader,
    defaultMesh = shaderc.shaderc_glsl_default_mesh_shader,
};

pub const CompileOptions = struct {
    const Self = @This();
    const InternalSelf = *shaderc.struct_shaderc_compile_options;

    _options: InternalSelf,

    pub fn init() Self {
        return Self{
            ._options = shaderc.shaderc_compile_options_initialize().?,
        };
    }

    pub fn deinit(self: Self) void {
        shaderc.shaderc_compile_options_release(self._options);
    }
};

pub const CompileResult = struct {
    const Self = @This();
    const InternalSelf = *shaderc.struct_shaderc_compilation_result;

    _result: InternalSelf,

    fn init(iself: InternalSelf) Self {
        return Self{
            ._result = iself,
        };
    }

    pub fn deinit(self: Self) void {
        shaderc.shaderc_result_release(self._result);
    }

    pub fn getErrors(self: Self) !?[][*c]const u8 {
        const numErrors = shaderc.shaderc_result_get_num_errors(self._result);

        if (numErrors == 0) {
            return null;
        }

        const errors = try _allocator.alloc([*c]const u8, shaderc.shaderc_result_get_num_errors(self._result));

        for (errors) |*err| {
            const msg = shaderc.shaderc_result_get_error_message(self._result);
            err.* = msg;
        }

        return errors;
    }

    pub fn getCode(self: Self) []const u8 {
        const bytes = shaderc.shaderc_result_get_bytes(self._result);
        const len = shaderc.shaderc_result_get_length(self._result);

        return bytes[0..len];
    }
};

pub const Compiler = struct {
    const Self = @This();
    const InternalSelf = *shaderc.struct_shaderc_compiler;

    _compiler: InternalSelf,

    pub fn init() Self {
        return Self{
            ._compiler = shaderc.shaderc_compiler_initialize().?,
        };
    }

    pub fn deinit(self: Self) void {
        shaderc.shaderc_compiler_release(self._compiler);
    }

    pub fn compile(
        self: Self,
        code: []const u8,
        kind: ShaderKind,
        fileName: []const u8,
        entryPointName: []const u8,
        options: ?CompileOptions,
    ) !CompileResult {
        const res = shaderc.shaderc_compile_into_spv(
            self._compiler,
            code.ptr,
            code.len,
            @intFromEnum(kind),
            fileName.ptr,
            entryPointName.ptr,
            if (options) |opts| opts._options else null,
        ).?;

        const status = shaderc.shaderc_result_get_compilation_status(res);
        switch (status) {
            shaderc.shaderc_compilation_status_compilation_error => return error.ShaderCompileError,
            shaderc.shaderc_compilation_status_configuration_error => return error.CompilerConfigurationError,
            shaderc.shaderc_compilation_status_invalid_stage => return error.InvalidStage,
            shaderc.shaderc_compilation_status_internal_error => return error.InternalCompileError,
            shaderc.shaderc_compilation_status_null_result_object => return error.NullResultObject,
            shaderc.shaderc_compilation_status_invalid_assembly => return error.InvalidAssembly,
            shaderc.shaderc_compilation_status_validation_error => return error.ValidationError,
            shaderc.shaderc_compilation_status_transformation_error => return error.TransformationError,
            shaderc.shaderc_compilation_status_success => {},
            else => unreachable,
        }

        return CompileResult.init(res);
    }

    pub fn compileIntoPreprocessedText(self: Self, code: []const u8, kind: ShaderKind, fileName: []const u8, entryPointName: []const u8, options: ?CompileOptions) void {
        const res = shaderc.shaderc_compile_into_preprocessed_text(
            self._compiler,
            code.ptr,
            code.len,
            @intFromEnum(kind),
            fileName.ptr,
            entryPointName.ptr,
            if (options) |opts| opts._options else null,
        ).?;

        return CompileResult.init(res);
    }
};
