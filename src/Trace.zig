const std = @import("std");

const Writer = std.Io.Writer;

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

pub fn format(self: @This(), writer: *Writer) !void {
    if (self.cmd == null)
        return;

    try writer.writeAll(self.cmd.?);
    if (self.args) |args| {
        try writer.writeAll("(");
        for (args, 0..) |arg, i| {
            if (i != 0)
                try writer.writeAll(", ");
            try writer.print("\"{f}\"", .{std.zig.fmtString(arg)});
        }
        try writer.writeAll(")");
    } else {
        try writer.writeAll("()");
    }
}
