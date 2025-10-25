const std = @import("std");
const Build = std.Build;

const cmake = @import("src/cmake.zig");

pub fn build(b: *Build) void {
    var project = cmake.create(b, .{
        .name = "loggerdb",
        .path = b.dependency("loggerdb", .{}).path(""),
    });

    project.setOption("CMAKE_INSTALL_PREFIX", .{ .STRING = "/usr" });
    project.exposeOptions(.{ .advanced = false });

    project.configure() catch unreachable;
}
