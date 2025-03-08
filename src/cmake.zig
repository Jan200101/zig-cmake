const std = @import("std");
const Build = std.Build;
const StringHashMap = std.StringHashMap;
const builtin = std.builtin;
const fs = std.fs;
const assert = std.debug.assert;
const cmake = @This();

b: *Build,
name: []const u8,
source_dir: Build.LazyPath,
build_dir: Build.LazyPath,

targets: StringHashMap(std.Build.Module),
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

pub const Trace = struct {
    version: ?struct {
        major: u8,
        minor: u8,
    } = null,
    args: ?[]const []const u8 = null,
    cmd: ?[]const u8 = null,
    file: ?[]const u8 = null,
    frame: ?u32 = null,
    global_frame: ?u32 = null,
    line: ?u32 = null,
    line_end: ?u32 = null,
    time: ?f32 = null,
};

pub const Commands = enum {
    add_library,
    add_subdirectory,
    block,
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

pub fn create(b: *Build, options: Options) *cmake {
    const target = options.target orelse b.standardTargetOptions(.{});
    const optimize = options.optimize orelse b.standardOptimizeOption(.{});
    const triple = target.result.zigTriple(b.allocator) catch unreachable;

    var cmake_options = StringHashMap(OptionType).init(b.allocator);
    cmake_options.put("CMAKE_C_COMPILER", .{ .STRING = b.graph.zig_exe }) catch unreachable;
    cmake_options.put("CMAKE_CXX_COMPILER", .{ .STRING = b.graph.zig_exe }) catch unreachable;

    const c_compiler_args = std.fmt.allocPrint(b.allocator, "cc -target {s}", .{triple}) catch unreachable;
    cmake_options.put("CMAKE_C_COMPILER_ARG1", .{ .STRING = c_compiler_args }) catch unreachable;
    const cxx_compiler_args = std.fmt.allocPrint(b.allocator, "c++ -target {s}", .{triple}) catch unreachable;
    cmake_options.put("CMAKE_CXX_COMPILER_ARG1", .{ .STRING = cxx_compiler_args }) catch unreachable;

    const cmake_build_type = switch (optimize) {
        .Debug => "Debug",
        .ReleaseSafe, .ReleaseFast => "Release",
        .ReleaseSmall => "MinSizeRel",
    };
    cmake_options.put("CMAKE_BUILD_TYPE", .{ .STRING = cmake_build_type }) catch unreachable;

    const build_dir_name = std.fmt.allocPrint(b.allocator, "build", .{}) catch unreachable;

    const cmake_target = b.allocator.create(cmake) catch @panic("OOM");
    cmake_target.* = .{
        .b = b,
        .name = options.name,
        .source_dir = options.path,
        .build_dir = options.path.path(b, build_dir_name),
        .targets = StringHashMap(std.Build.Module).init(b.allocator),
        .options = cmake_options,
    };

    return cmake_target;
}

pub fn setOption(self: *@This(), k: []const u8, v: OptionType) void {
    self.options.put(k, v) catch unreachable;
}

pub fn removeOption(self: *@This(), k: []const u8) void {
    _ = self.options.remove(k);
}

pub const exposeFlags = struct {
    advanced: bool = false,
};

/// expose cmake options directly as string options
pub fn exposeOptions(self: *@This(), flags: exposeFlags) void {
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

pub fn configure(self: *@This()) void {
    const source_dir = self.source_dir.getPath2(self.b, null);
    const build_dir = self.build_dir.getPath2(self.b, null);

    fs.cwd().makeDir(build_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => unreachable,
    };

    var args = std.ArrayList([]const u8).init(self.b.allocator);
    args.append("cmake") catch unreachable;

    args.append("-S") catch unreachable;
    args.append(source_dir) catch unreachable;
    args.append("-B") catch unreachable;
    args.append(build_dir) catch unreachable;

    // Needed to generate a trace file which we can parse to find out where artifacts will be located
    const trace_path = self.build_dir.path(self.b, "cmake_trace.txt").getPath2(self.b, null);
    args.append("--trace") catch unreachable;
    args.append("--trace-expand") catch unreachable;
    args.append("--trace-format=json-v1") catch unreachable;
    const trace_redirect = std.fmt.allocPrint(self.b.allocator, "--trace-redirect={s}", .{trace_path}) catch @panic("OOM");
    args.append(trace_redirect) catch unreachable;

    // Disable some warnings
    args.append("-DCMAKE_POLICY_WARNING_CMP0156=OFF") catch unreachable;

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

        args.append("-D") catch unreachable;
        args.append(flag) catch unreachable;
    }

    //std.debug.print("{s}\n", .{build_dir});
    //std.debug.print("{s}\n", .{args.items});
    _ = self.b.run(args.items);

    const file = fs.cwd().openFile(trace_path, .{}) catch unreachable;
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = std.ArrayList(u8).init(self.b.allocator);
    defer line.deinit();

    var cmd_ignore_list = std.ArrayList([]const u8).init(self.b.allocator);

    const writer = line.writer();
    outer: while (reader.streamUntilDelimiter(writer, '\n', null)) {
        // Clear the line so we can reuse it.
        defer line.clearRetainingCapacity();

        const parsed = std.json.parseFromSlice(
            Trace,
            self.b.allocator,
            line.items,
            .{},
        ) catch unreachable;
        defer parsed.deinit();
        const trace = parsed.value;

        if (trace.cmd) |cmd_string| {
            for (cmd_ignore_list.items) |ignored_cmd| {
                const lowercase_cmd_string = std.ascii.allocLowerString(self.b.allocator, cmd_string) catch unreachable;
                if (std.mem.eql(u8, ignored_cmd, lowercase_cmd_string)) continue :outer;
            }

            const cmd = std.meta.stringToEnum(Commands, cmd_string) orelse {
                std.debug.print("unhandled command: {s}({s})\n", .{ cmd_string, trace.args.? });
                @panic("unhandled command");
            };
            switch (cmd) {
                // No need to handle this ourselves, just ignore them when they are invoked
                .add_library,
                .add_subdirectory,
                .block,
                .check_c_source_compiles,
                .check_include_file,
                .cmake_check_source_compiles,
                .cmake_initialize_per_config_variable,
                .cmake_minimum_required,
                .cmake_policy,
                .@"else",
                .elseif,
                .find_package,
                .find_package_handle_standard_args,
                .find_package_message,
                .foreach,
                .get_filename_component,
                .get_property,
                .@"if",
                .include,
                .include_guard,
                .list,
                .mark_as_advanced,
                .math,
                .message,
                .option,
                .project,
                .@"return",
                .set,
                .set_property,
                .string,
                .target_compile_definitions,
                .target_include_directories,
                .target_link_libraries,
                .target_sources,
                .unset,
                .lang,
                => {},

                // macros and functions are already evaluated, just ignore any invocation of them
                .macro, .function => {
                    const method_name = std.ascii.allocLowerString(self.b.allocator, trace.args.?[0]) catch unreachable;
                    cmd_ignore_list.append(method_name) catch unreachable;
                },
            }
        }
    } else |err| switch (err) {
        error.EndOfStream => assert(line.items.len == 0),
        else => unreachable,
    }

    std.debug.print("configured cmake project", .{});
}
