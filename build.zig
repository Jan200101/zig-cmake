const std = @import("std");
const Build = std.Build;
const StringHashMap = std.StringHashMap;
const builtin = std.builtin;

pub fn build(b: *Build) void {
    var cmake = CmakeIntegration.create(b, .{
        .name = "test",
        .path = b.dependency("loggerdb", .{}).path(""),
    });

    cmake.setOption("CMAKE_INSTALL_PREFIX", "/usr");
    cmake.exposeOptions(.{ .advanced = false });

    cmake.configure();
}

pub const CmakeIntegration = struct {
    b: *Build,
    name: []const u8,
    source_dir: Build.LazyPath,
    build_dir: Build.LazyPath,

    targets: StringHashMap(std.Build.Module),
    options: StringHashMap([]const u8),

    pub const Options = struct {
        name: []const u8,
        path: Build.LazyPath,

        target: ?Build.ResolvedTarget = null,
        optimize: ?builtin.OptimizeMode = null,
    };

    pub fn create(b: *Build, options: Options) *CmakeIntegration {
        const target = options.target orelse b.standardTargetOptions(.{});
        const optimize = options.optimize orelse b.standardOptimizeOption(.{});
        const triple = target.result.zigTriple(b.allocator) catch unreachable;

        const cmake = b.allocator.create(CmakeIntegration) catch @panic("OOM");

        var cmake_options = StringHashMap([]const u8).init(b.allocator);
        cmake_options.put("CMAKE_C_COMPILER", b.graph.zig_exe) catch unreachable;
        cmake_options.put("CMAKE_CXX_COMPILER", b.graph.zig_exe) catch unreachable;

        const c_compiler_args = std.fmt.allocPrint(b.allocator, "cc -target {s}", .{triple}) catch unreachable;
        cmake_options.put("CMAKE_C_COMPILER_ARG1", c_compiler_args) catch unreachable;
        const cxx_compiler_args = std.fmt.allocPrint(b.allocator, "c++ -target {s}", .{triple}) catch unreachable;
        cmake_options.put("CMAKE_CXX_COMPILER_ARG1", cxx_compiler_args) catch unreachable;

        const cmake_build_type = switch (optimize) {
            .Debug => "Debug",
            .ReleaseSafe, .ReleaseFast => "Release",
            .ReleaseSmall => "MinSizeRel",
        };
        cmake_options.put("CMAKE_BUILD_TYPE", cmake_build_type) catch unreachable;

        const build_dir_name = std.fmt.allocPrint(b.allocator, "build", .{}) catch unreachable;

        cmake.* = .{
            .b = b,
            .name = options.name,
            .source_dir = options.path,
            .build_dir = options.path.path(b, build_dir_name),
            .targets = StringHashMap(std.Build.Module).init(b.allocator),
            .options = cmake_options,
        };

        return cmake;
    }

    pub fn setOption(self: *@This(), k: []const u8, v: []const u8) void {
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
        std.fs.cwd().deleteTree(temp_build_path) catch unreachable;

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
            tail = std.mem.indexOfPos(u8, output, head, "\n") orelse unreachable;
            const value = output[head + 1 .. tail];

            const gop = self.options.getOrPut(name) catch unreachable;
            if (!gop.found_existing) {
                const option = self.b.option([]const u8, name, comment) orelse value;
                gop.value_ptr.* = option;
            }
        }
    }

    fn configure(self: *@This()) void {
        const source_dir = self.source_dir.getPath2(self.b, null);
        const build_dir = self.build_dir.getPath2(self.b, null);

        var args = std.ArrayList([]const u8).init(self.b.allocator);
        args.append("cmake") catch unreachable;

        // Needed to generate a trace file which we can parse to find out where artifacts will be located
        args.append("--trace") catch unreachable;
        args.append("--trace-expand") catch unreachable;
        args.append("--trace-format=json-v1") catch unreachable;
        const trace_redirect = std.fmt.allocPrint(self.b.allocator, "--trace-redirect={s}", .{self.build_dir.path(self.b, "cmake_trace.txt").getPath2(self.b, null)}) catch @panic("OOM");
        args.append(trace_redirect) catch unreachable;

        args.append("-S") catch unreachable;
        args.append(source_dir) catch unreachable;
        args.append("-B") catch unreachable;
        args.append(build_dir) catch unreachable;

        // Disable some warnings
        args.append("-DCMAKE_POLICY_WARNING_CMP0156=OFF") catch unreachable;

        var it = self.options.iterator();
        while (it.next()) |entry| {
            const flag = std.fmt.allocPrint(self.b.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch @panic("OOM");
            args.append("-D") catch unreachable;
            args.append(flag) catch unreachable;
        }

        std.debug.print("{s}\n", .{build_dir});
        std.debug.print("{s}\n", .{args.items});
        const output = self.b.run(args.items);
        _ = output;
    }
};
