const std = @import("std");

const log = std.log;
const Build = std.Build;
const StringHashMap = std.StringHashMap;
const builtin = std.builtin;
const fs = std.fs;
const assert = std.debug.assert;
const cmake = @This();

b: *Build,
target: ?Build.ResolvedTarget,
optimize: ?builtin.OptimizeMode,

name: []const u8,
source_dir: Build.LazyPath,
build_dir: Build.LazyPath,

targets: StringHashMap(*std.Build.Step.Compile),
options: StringHashMap(OptionType),

pub const OptionTypeTag = enum {
    BOOL,
    FILEPATH,
    PATH,
    STRING,
    INTERNAL,
};

pub const OptionType = union(OptionTypeTag) {
    BOOL: bool,
    FILEPATH: []const u8,
    PATH: []const u8,
    STRING: []const u8,
    INTERNAL: []const u8,
};

pub const Options = struct {
    name: []const u8,
    path: Build.LazyPath,

    target: ?Build.ResolvedTarget = null,
    optimize: ?builtin.OptimizeMode = null,
};

pub const Trace = @import("Trace.zig");

pub const Linkage = enum {
    STATIC,
    SHARED,
    MODULE,
    OBJECT,
    INTERFACE,
    UNKNOWN,
};

pub const Commands = enum {
    add_library,
    add_subdirectory,
    block,
    endblock,
    check_c_source_compiles,
    check_include_file,
    cmake_check_source_compiles,
    cmake_initialize_per_config_variable,
    cmake_minimum_required,
    cmake_policy,
    @"else",
    elseif,
    find_package,
    find_package_handle_standard_args,
    find_package_message,
    foreach,
    function,
    get_filename_component,
    get_property,
    @"if",
    include,
    include_guard,
    list,
    macro,
    mark_as_advanced,
    math,
    message,
    option,
    project,
    @"return",
    set,
    set_property,
    string,
    target_compile_definitions,
    target_include_directories,
    target_link_libraries,
    target_sources,
    unset,
    lang,
    execute_process,
    find_program,

    // function:
    //_cmake_record_install_prefix,

    // macros
    //_cmake_common_language_platform_flags,
    //_threads_check_flag_pthread,
    //_threads_check_lib,
    //_threads_check_libc,
    //__compiler_check_default_language_standard,
    //__compiler_clang,
    //__compiler_gnu,
    //__linux_compiler_gnu,
};

pub fn init(b: *Build, options: Options) *cmake {
    return tryinit(b, options) catch unreachable;
}

pub fn tryinit(b: *Build, options: Options) !*cmake {
    const target = options.target orelse b.standardTargetOptions(.{});
    const optimize = options.optimize orelse b.standardOptimizeOption(.{});
    const triple = try target.result.zigTriple(b.allocator);

    var cmake_options = StringHashMap(OptionType).init(b.allocator);
    errdefer cmake_options.deinit();

    try cmake_options.put("CMAKE_C_COMPILER", .{ .STRING = b.graph.zig_exe });
    const c_compiler_args = try std.fmt.allocPrint(b.allocator, "cc -target {s}", .{triple});
    try cmake_options.put("CMAKE_C_COMPILER_ARG1", .{ .STRING = c_compiler_args });

    try cmake_options.put("CMAKE_CXX_COMPILER", .{ .STRING = b.graph.zig_exe });
    const cxx_compiler_args = try std.fmt.allocPrint(b.allocator, "c++ -target {s}", .{triple});
    try cmake_options.put("CMAKE_CXX_COMPILER_ARG1", .{ .STRING = cxx_compiler_args });

    const cmake_build_type = switch (optimize) {
        .Debug => "Debug",
        .ReleaseSafe, .ReleaseFast => "Release",
        .ReleaseSmall => "MinSizeRel",
    };
    cmake_options.put("CMAKE_BUILD_TYPE", .{ .STRING = cmake_build_type }) catch unreachable;

    const build_dir_name = std.fmt.allocPrint(b.allocator, "build", .{}) catch unreachable;
    defer b.allocator.free(build_dir_name);

    const cmake_target = b.allocator.create(cmake) catch @panic("OOM");
    cmake_target.* = .{
        .b = b,
        .target = target,
        .optimize = optimize,

        .name = options.name,
        .source_dir = options.path,
        .build_dir = options.path.path(b, build_dir_name),

        .targets = StringHashMap(*std.Build.Step.Compile).init(b.allocator),
        .options = cmake_options,
    };

    return cmake_target;
}

pub fn deinit(self: *@This()) void {
    self.targets.deinit();
    self.options.deinit();
}

pub fn setOption(self: *@This(), k: []const u8, v: OptionType) void {
    self.options.put(k, v) catch unreachable;
}

pub fn removeOption(self: *@This(), k: []const u8) void {
    _ = self.options.remove(k);
}

pub fn getTarget(self: *@This(), k: []const u8) ?*std.Build.Step.Compile {
    return self.targets.get(k);
}

pub const ExposeOptions = struct {
    advanced: bool = false,
};

/// expose cmake options directly as string options
pub fn exposeOptions(self: *@This(), flags: ExposeOptions) void {
    const cmake_flags = if (flags.advanced)
        "-LAH"
    else
        "-LH";

    const source_path = self.source_dir.getPath2(self.b, null);
    // listing all options requires configuration and if we already configured we will get what we previously set
    const temp_build_path = self.source_dir.path(self.b, "temp_build").getPath2(self.b, null);

    const output = self.b.run(&.{ "cmake", cmake_flags, "-S", source_path, "-B", temp_build_path });
    fs.cwd().deleteTree(temp_build_path) catch unreachable;

    const start = std.mem.indexOf(u8, output, "Cache values") orelse unreachable;
    var head = start;
    var tail = head;

    while (true) {
        head = std.mem.indexOfPos(u8, output, tail, "//") orelse break;
        tail = std.mem.indexOfPos(u8, output, head, "\n") orelse unreachable;
        const comment = output[head + 3 .. tail];

        head = std.mem.indexOfPos(u8, output, tail, "\n") orelse unreachable;
        tail = std.mem.indexOfPos(u8, output, head, ":") orelse unreachable;
        const name = output[head + 1 .. tail];

        head = std.mem.indexOfPos(u8, output, tail, "=") orelse unreachable;
        const vartype = std.meta.stringToEnum(OptionTypeTag, output[tail + 1 .. head]) orelse @panic("invalid type");

        tail = std.mem.indexOfPos(u8, output, head, "\n") orelse unreachable;
        const value: OptionType = switch (vartype) {
            .BOOL => .{ .BOOL = std.ascii.eqlIgnoreCase("ON", output[head + 1 .. tail]) },
            else => .{ .STRING = output[head + 1 .. tail] },
        };

        const gop = self.options.getOrPut(name) catch unreachable;
        if (!gop.found_existing) {
            const option: OptionType = switch (vartype) {
                .BOOL => .{ .BOOL = self.b.option(bool, name, comment) orelse value.BOOL },
                else => .{ .STRING = self.b.option([]const u8, name, comment) orelse value.STRING },
            };
            gop.value_ptr.* = option;
        }
    }
}

pub fn configure(self: *@This()) !void {
    const source_dir = self.source_dir.getPath2(self.b, null);
    const build_dir = self.build_dir.getPath2(self.b, null);

    fs.cwd().makeDir(build_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => unreachable,
    };

    var cmake_args = std.array_list.Managed([]const u8).init(self.b.allocator);
    try cmake_args.append("cmake");

    try cmake_args.append("-S");
    try cmake_args.append(source_dir);
    try cmake_args.append("-B");
    try cmake_args.append(build_dir);

    // Needed to generate a trace file which we can parse to find out where artifacts will be located
    const trace_path = self.build_dir.path(self.b, "cmake_trace.txt").getPath2(self.b, null);
    try cmake_args.append("--trace");
    try cmake_args.append("--trace-expand");
    try cmake_args.append("--trace-format=json-v1");
    const trace_redirect = std.fmt.allocPrint(self.b.allocator, "--trace-redirect={s}", .{trace_path}) catch @panic("OOM");
    try cmake_args.append(trace_redirect);

    // Disable some warnings
    try cmake_args.append("-DCMAKE_POLICY_WARNING_CMP0156=OFF");

    var it = self.options.iterator();
    while (it.next()) |entry| {
        const value = switch (entry.value_ptr.*) {
            .BOOL => if (entry.value_ptr.*.BOOL == true) "ON" else "OFF",
            else => entry.value_ptr.*.STRING,
        };

        const valtype = switch (entry.value_ptr.*) {
            .BOOL => "BOOL",
            else => "STRING",
        };

        const flag = std.fmt.allocPrint(self.b.allocator, "{s}:{s}={s}", .{ entry.key_ptr.*, valtype, value }) catch @panic("OOM");

        try cmake_args.append("-D");
        try cmake_args.append(flag);
    }

    //std.debug.print("{s}\n", .{build_dir});
    //std.debug.print("{s}\n", .{cmake_args.items});
    _ = self.b.run(cmake_args.items);

    //std.debug.print("{s}\n", .{trace_path});

    const file = try fs.cwd().openFile(trace_path, .{});
    defer file.close();

    var buffer: [1024 * 1024]u8 = undefined;
    var file_reader = file.reader(&buffer);
    var reader = &file_reader.interface;

    var line: std.Io.Writer.Allocating = .init(self.b.allocator);
    defer line.deinit();
    const writer = &line.writer;

    var function_list: std.array_list.Managed([]const u8) = .init(self.b.allocator);

    outer: while (reader.streamDelimiter(writer, '\n')) |_| {
        // Clear the line so we can reuse it.
        defer line.clearRetainingCapacity();
        defer reader.toss(1);

        const line_buffer = writer.buffer[0..writer.end];

        //std.debug.print("{s}\n", .{line_buffer});

        const parsed = try std.json.parseFromSlice(
            Trace,
            self.b.allocator,
            line_buffer,
            .{},
        );
        defer parsed.deinit();
        const trace = parsed.value;

        if (trace.version) |version| {
            std.debug.print("trace version: {}.{}\n", .{ version.major, version.minor });
            continue;
        }

        if (trace.cmd) |cmd_string| {
            for (function_list.items) |ignored_cmd| {
                const lowercase_cmd_string = try std.ascii.allocLowerString(self.b.allocator, cmd_string);
                if (std.mem.eql(u8, ignored_cmd, lowercase_cmd_string)) continue :outer;
            }

            const cmd = std.meta.stringToEnum(Commands, cmd_string) orelse {
                std.debug.print("unhandled command: {f}\n", .{trace});
                @panic("unhandled command");
            };

            switch (cmd) {
                // No need to handle this ourselves, just ignore them when they are invoked
                .add_subdirectory,
                .block,
                .endblock,
                .include,
                .find_package,
                .check_c_source_compiles,
                .check_include_file,
                .cmake_check_source_compiles,
                .cmake_initialize_per_config_variable,
                .cmake_minimum_required,
                .cmake_policy,
                .@"else",
                .elseif,
                .find_package_handle_standard_args,
                .find_package_message,
                .foreach,
                .get_filename_component,
                .get_property,
                .@"if",
                .include_guard,
                .list,
                .mark_as_advanced,
                .math,
                .message,
                .option,
                .project,
                .set,
                .set_property,
                .string,
                .target_link_libraries,
                .unset,
                .lang,
                .execute_process,
                .@"return",
                .find_program,
                => {
                    //log.debug("{f}", .{trace});
                },

                // macros and functions are already evaluated, just ignore any invocation of them
                .macro, .function => {
                    const method_name = std.ascii.allocLowerString(self.b.allocator, trace.args.?[0]) catch unreachable;
                    try function_list.append(method_name);
                },

                .add_library => {
                    //log.debug("{f}", .{trace});

                    const name, const libtype, const sources = blk: {
                        var target_name: ?[]const u8 = null;
                        var libtype: Linkage = .STATIC;
                        var sources: ?[]const []const u8 = null;

                        if (trace.args) |args| {
                            for (args, 0..) |arg, i| {
                                switch (i) {
                                    0 => target_name = arg,
                                    1 => libtype = std.meta.stringToEnum(Linkage, arg) orelse unreachable,
                                    else => {
                                        sources = args[i..];
                                        break;
                                    },
                                }
                            }

                            if (target_name) |real_name|
                                break :blk .{ real_name, libtype, sources };

                            unreachable;
                        }

                        unreachable;
                    };

                    //log.info("adding library {s}", .{name});

                    const mod = self.b.createModule(.{
                        .target = self.target,
                        .optimize = self.optimize,
                    });

                    const compile_step = if (libtype == .OBJECT)
                        self.b.addObject(.{
                            .name = name,
                            .root_module = mod,
                        })
                    else
                        self.b.addLibrary(.{
                            .name = name,
                            .linkage = switch (libtype) {
                                .STATIC,
                                .MODULE,
                                .INTERFACE,
                                => .static,

                                .SHARED,
                                => .dynamic,

                                else => unreachable,
                            },
                            .root_module = mod,
                        });

                    compile_step.linkLibC();

                    if (sources) |real_sources| {
                        for (real_sources) |source| {
                            // TODO
                            //log.debug("source {s}", .{source});
                            _ = source;
                        }
                    }

                    try self.targets.put(compile_step.name, compile_step);
                },

                .target_sources => {
                    //log.debug("{f}", .{trace});

                    var compile_step: ?*std.Build.Step.Compile = null;
                    var target_type: ?Linkage = null;

                    if (trace.args) |args| {
                        for (args, 0..) |arg, i| {
                            if (i == 0) {
                                //log.debug("looking for {s}", .{arg});
                                compile_step = self.getTarget(arg);
                                continue;
                            }

                            target_type = std.meta.stringToEnum(Linkage, arg) orelse {
                                if (compile_step) |real_step| {
                                    const trace_cwd: Build.LazyPath = .{
                                        .cwd_relative = fs.path.dirname(trace.file orelse unreachable) orelse unreachable,
                                    };

                                    //log.debug("adding {s} to {s}", .{ arg, real_step.name });

                                    real_step.addCSourceFile(.{
                                        .file = try trace_cwd.join(self.b.allocator, arg),
                                        .language = null,
                                    });
                                } else unreachable;
                                continue;
                            };
                        }
                    } else unreachable;
                },

                .target_compile_definitions => {
                    //log.debug("{f}", .{trace});

                    var compile_step: ?*std.Build.Step.Compile = null;
                    var target_type: ?Linkage = null;

                    if (trace.args) |args| {
                        for (args, 0..) |arg, i| {
                            if (i == 0) {
                                //log.debug("looking for {s}", .{arg});
                                compile_step = self.getTarget(arg);
                                continue;
                            }

                            target_type = std.meta.stringToEnum(Linkage, arg) orelse {
                                if (compile_step) |real_step| {
                                    const key_end = std.mem.indexOf(u8, arg, "=") orelse unreachable;
                                    const key = arg[0..key_end];
                                    const value = arg[key_end + 1 ..];

                                    //log.debug("setting {s}={s}", .{ key, value });

                                    real_step.root_module.addCMacro(key, value);
                                } else unreachable;
                                continue;
                            };
                        }
                    } else unreachable;
                },

                .target_include_directories => {
                    //log.debug("{f}", .{trace});

                    var compile_step: ?*std.Build.Step.Compile = null;
                    var target_type: ?Linkage = null;

                    if (trace.args) |args| {
                        for (args, 0..) |arg, i| {
                            if (i == 0) {
                                //log.debug("looking for {s}", .{arg});
                                compile_step = self.getTarget(arg);
                                continue;
                            }

                            target_type = std.meta.stringToEnum(Linkage, arg) orelse {
                                if (compile_step) |real_step| {
                                    const trace_cwd: Build.LazyPath = .{
                                        .cwd_relative = fs.path.dirname(trace.file orelse unreachable) orelse unreachable,
                                    };

                                    //log.debug("adding {s} to {s}", .{ arg, real_step.name });

                                    real_step.addIncludePath(try trace_cwd.join(self.b.allocator, arg));
                                } else unreachable;
                                continue;
                            };
                        }
                    } else unreachable;
                },
            }

            continue;
        }

        log.debug("unhandled trace: {s}", .{line_buffer});
        unreachable;
    } else |err| switch (err) {
        error.EndOfStream => assert(writer.end == 0),
        error.ReadFailed => unreachable,
        error.WriteFailed => unreachable,
    }

    log.info("configured cmake project", .{});
}
