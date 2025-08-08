pub const shellcmd = struct {
    const Self = @This();
    cmd_args: []const []const u8,
    stdout: std.ArrayListUnmanaged(u8) = .empty,
    stderr: std.ArrayListUnmanaged(u8) = .empty,
    pub fn execute_blocking(cwd: []const u8, args: []const []const u8, allocator: std.mem.Allocator, max_output_len: usize) !shellcmd {
        var cmd: shellcmd = undefined;
        cmd.stdout = std.ArrayListUnmanaged(u8){};
        cmd.stderr = std.ArrayListUnmanaged(u8){};

        cmd.cmd_args = args;
        var child = std.process.Child.init(args, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.cwd = cwd;

        try child.spawn();
        try child.collectOutput(allocator, &cmd.stdout, &cmd.stderr, max_output_len);
        const term = try child.wait();

        if (term.Exited != 0) {
            std.log.warn("Command exited with non-zero exit code: {}\n", .{term.Exited});
        }
        return cmd;
    }
    pub fn execute_and_print_output_blocking(writer: anytype, cwd: []const u8, args: []const []const u8, allocator: std.mem.Allocator, max_output_len: usize) !void {
        var cmd: shellcmd = undefined;
        defer cmd.deinit(allocator);
        cmd.stdout = std.ArrayListUnmanaged(u8){};
        cmd.stderr = std.ArrayListUnmanaged(u8){};

        cmd.cmd_args = args;
        var child = std.process.Child.init(args, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.cwd = cwd;

        try std.fmt.format(writer, "Executing Command:\n", .{});
        for (args) |arg| {
            try std.fmt.format(writer, "{s} ", .{arg});
        }
        try child.spawn();
        try child.collectOutput(allocator, &cmd.stdout, &cmd.stderr, max_output_len);
        const term = try child.wait();
        if (cmd.stdout.items.len > 0) {
            try std.fmt.format(writer, "\nOut:\n{s}\n", .{cmd.stdout.items});
        }
        if (cmd.stderr.items.len > 0) {
            try std.fmt.format(writer, "\nErr:\n{s}\n", .{cmd.stderr.items});
        }

        if (term.Exited != 0) {
            std.log.warn("Command exited with non-zero exit code: {}\n", .{term.Exited});
        }
    }
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.stdout.deinit(allocator);
        self.stderr.deinit(allocator);
    }
};
const std = @import("std");
