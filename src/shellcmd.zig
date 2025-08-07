pub const shellcmd = struct {
    const Self = @This();
    cmd_args: []const []const u8,
    stdout: std.ArrayListUnmanaged(u8) = .empty,
    stderr: std.ArrayListUnmanaged(u8) = .empty,
    pub fn execute_blocking(cwd: []const u8, args: []const []const u8, allocator: std.mem.Allocator, max_output_len: usize) !shellcmd {
        var cmd: shellcmd = undefined;
        cmd.cmd_args = args;
        var child = std.process.Child.init(args, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();
        try child.collectOutput(allocator, &cmd.stdout, &cmd.stderr, max_output_len);
        const term = try child.wait();

        try std.testing.expectEqual(term.Exited, 0);
        child.cwd = cwd;
        return cmd;
    }
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.stdout.deinit(allocator);
        self.stderr.deinit(allocator);
    }
};
const std = @import("std");
