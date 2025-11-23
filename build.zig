const std = @import("std");
const Build = std.Build;

const cmake = @import("src/cmake.zig");

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const loggerdb_dep = b.dependency("loggerdb", .{});

    var project = cmake.init(b, .{
        .target = target,
        .optimize = optimize,

        .path = loggerdb_dep.path(""),
    });
    defer project.deinit();

    project.setOption("CMAKE_INSTALL_PREFIX", .{ .STRING = "/usr" });
    project.exposeOptions(.{});

    project.configure() catch unreachable;

    const loggerdb_target = project.getTarget("loggerDB") orelse unreachable;

    const translate = b.addTranslateC(.{
        .root_source_file = loggerdb_dep.path(
            b.pathJoin(&.{ "loggerDB", "include", "loggerDB.h" }),
        ),
        .target = target,
        .optimize = optimize,
    });
    translate.addIncludePath(loggerdb_dep.path(
        b.pathJoin(&.{ "loggerDB", "include" }),
    ));

    const loggerdb_translate = b.createModule(.{
        .root_source_file = translate.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "loggerdb", .module = loggerdb_translate },
            },
        }),
    });
    exe.linkLibrary(loggerdb_target);
    b.installArtifact(exe);

    const run_step = b.step("run", "run test program invoking imported cmake project");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
}
