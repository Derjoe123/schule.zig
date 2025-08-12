var config = struct {
    directory: []const u8 = ".",
    database_file: []const u8 = "schule.sdb", // relative to config.directory
    do_git_pull: bool = true,
    do_git_commit: bool = true,
    do_git_push: bool = true,
    cmd: ?[]const u8 = null,
    // status_cmd: ?[]const u8 = null,
    // list_cmd: ?[]const u8 = null,
    // new_cmd: ?[]const u8 = null,
    // remove_cmd: ?[]const u8 = null,
}{};

fn status_fn(db: *void) anyerror!void {
    _ = db;
    std.log.info("\nstatus_fn\n", .{});
    // return error.Unimpl;
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            std.log.err("Memory Leak!", .{});
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

    if (config.do_git_commit) {
        try shellcmd.execute_and_print_output_blocking(writer, config.directory, &[_][]const u8{ "git", "add", config.directory }, alloc, 2048);
        try shellcmd.execute_and_print_output_blocking(writer, config.directory, &[_][]const u8{ "git", "commit", "-m'automatic save'" }, alloc, 2048);
    }
    if (config.do_git_pull) {
        try shellcmd.execute_and_print_output_blocking(writer, config.directory, &[_][]const u8{ "git", "pull" }, alloc, 2048);
    }
    // if (config.do_git_push) {
    //     try shellcmd.execute_and_print_output_blocking(writer, config.directory, &[_][]const u8{ "git", "push" }, alloc, 2048);
    // }

    var db_parser = try simpledb.SimpleDB(u64, 1024 * 1024 * 1024).init(dir_buf_view);
    defer db_parser.deinit();
    // var old_content = try db_parser.get_content(alloc);
    // defer old_content.deinit();
    // var db = old_content.value;
    const db: u64 = 123;
    // if (config.cmd) |c_cmd| {
    // try db.status(writer);
    // }
    // try args.exec_commaeds_with_args(@ptrCast(&db), input_cmds, argv);
    try db_parser.write_content(&db);
}

const std = @import("std");

const schule_lib = @import("schule_zig_lib");
const args = schule_lib.args;
const simpledb = schule_lib.simpledb;
const shellcmd = schule_lib.shellcmd.shellcmd;
const schuldb = schule_lib.schuldb;
