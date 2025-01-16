const std = @import("std");
const Build = std.Build;
const StringHashMap = std.StringHashMap;
const builtin = std.builtin;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var cmake = CmakeIntegration.create(b, .{
        .name = "test",
        .path = .{ .cwd_relative = "test" },
        .target = target,
        .optimize = optimize,
    });

    cmake.loadOptions(.{ .advanced = true });
}

pub const CmakeIntegration = struct {
    b: *Build,
    name: []const u8,
    path: Build.LazyPath,

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

        var compiler: [255]u8 = undefined;

        var cmake_options = StringHashMap([]const u8).init(b.allocator);
        const c_compiler = std.fmt.bufPrint(&compiler, "{s} cc -target {s}", .{ b.graph.zig_exe, triple }) catch unreachable;
        cmake_options.put("CMAKE_C_COMPILER", c_compiler) catch unreachable;
        std.debug.print("c_compiler {s}\n", .{c_compiler});

        const cxx_compiler = std.fmt.bufPrint(&compiler, "{s} c++ -target {s}", .{ b.graph.zig_exe, triple }) catch unreachable;
        cmake_options.put("CMAKE_CXX_COMPILER", cxx_compiler) catch unreachable;
        std.debug.print("cxx_compiler {s}\n", .{cxx_compiler});

        const cmake_build_type = switch (optimize) {
            .Debug => "Debug",
            .ReleaseSafe, .ReleaseFast => "Release",
            .ReleaseSmall => "MinSizeRel",
        };
        cmake_options.put("CMAKE_BUILD_TYPE", cmake_build_type) catch unreachable;

        cmake.* = .{
            .b = b,
            .name = options.name,
            .path = options.path,
            .targets = StringHashMap(std.Build.Module).init(b.allocator),
            .options = cmake_options,
        };

        return cmake;
    }

    pub const loadFlags = struct {
        advanced: bool = false,
    };

    pub fn loadOptions(self: *@This(), flags: loadFlags) void {
        const cmake_flags = if (flags.advanced)
            "-LAH"
        else
            "-LH";

        const output = self.b.run(&.{ "cmake", cmake_flags, "-S", "loggerDB", "-B", "build" });

        const start = std.mem.indexOf(u8, output, "Cache values") orelse unreachable;
        var head = start;
        var tail = head;

        while (true) {
            head = std.mem.indexOfPos(u8, output, tail, "//") orelse break;
            tail = std.mem.indexOfPos(u8, output, head, "\n") orelse break;
            const comment = output[head + 3 .. tail];

            head = std.mem.indexOfPos(u8, output, tail, "\n") orelse break;
            tail = std.mem.indexOfPos(u8, output, head, ":") orelse break;
            const name = output[head + 1 .. tail];

            head = std.mem.indexOfPos(u8, output, tail, "=") orelse break;
            tail = std.mem.indexOfPos(u8, output, head, "\n") orelse break;
            const value = output[head + 1 .. tail];

            const gop = self.options.getOrPut(name) catch unreachable;
            if (!gop.found_existing) {
                const option = self.b.option([]const u8, name, comment) orelse value;
                gop.value_ptr.* = option;
            }
        }
    }
};
