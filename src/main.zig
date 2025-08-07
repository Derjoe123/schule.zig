var config = struct {
    directory: []const u8 = ".",
    database_file: []const u8 = "schule.sdb", // relative to config.directory
    git_commit_command: []const u8 = "git add . && git commit -m '{}' && git push --set-upstream origin main",
    do_git_pull: bool = true,
}{};
const table = struct {
    data: []const u8,
};
const database = struct {
    tables: []const table,
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            std.debug.print("Memory Leak!", .{});
        }
    }
    const dir_buf = try alloc.alloc(u8, std.fs.max_path_bytes);
    defer alloc.free(dir_buf);
    const cwd = try std.process.getCwd(dir_buf);
    config.directory = cwd;
    const argv = std.os.argv;
    const writer = std.io.getStdOut().writer();

    try args.parse_args(argv, &config);
    if (args.flag_set(argv, "--help")) {
        const flags: []const args.Flag = &[_]args.Flag{
            args.Flag{ .name = "--help", .desc = "show the help menu" },
        };
        try args.display_args_help(writer, &config, flags);
    }

    if (config.directory.ptr[config.directory.len - 1] == '/') {
        config.directory.len -= 1;
    }
    std.debug.assert(config.directory.len + config.database_file.len <= dir_buf.len);
    try writer.print("Working Database: \n{s}/{s}\n", .{ config.directory, config.database_file });
    dir_buf[config.directory.len] = '/';
    @memcpy(dir_buf.ptr + config.directory.len + 1, config.database_file);

    // just so we dont interfere with the heap slice
    const total_len = config.directory.len + 1 + config.database_file.len;
    var dir_buf_view = dir_buf;
    dir_buf_view.len = total_len;
    var cmd = try shellcmd.execute_blocking(dir_buf_view, &[_][]const u8{ "echo", "Hello, World!" }, alloc, 1024);
    std.debug.print("Command StdOut: {s}", .{cmd.stdout.items});
    std.debug.print("Command StdErr: {s}", .{cmd.stderr.items});
    defer cmd.deinit(alloc);

    const db = try simpledb.SimpleDB(database, 1024 * 1024 * 1024).init(dir_buf_view);
    const old_content = try db.get_content(alloc);
    defer old_content.deinit();
    std.debug.print("Old Content: {}\n", .{old_content.value});
    const new_content = database{ .tables = &[_]table{ table{ .data = "test" }, table{ .data = "test2" } } };
    std.debug.print("New Content: {}\n", .{new_content});
    try db.write_content(&new_content);
    defer db.deinit();
}

const std = @import("std");

const schule_lib = @import("schule_zig_lib");
const args = schule_lib.args;
const simpledb = schule_lib.simpledb;
const shellcmd = schule_lib.shellcmd.shellcmd;
