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

const db_parser_t = simpledb.SimpleDB(schuldb_mod.SchulDBData, 1024 * 1024 * 1024);
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
    var db_parser = try db_parser_t.init(dir_buf_view);
    defer db_parser.deinit();

    // Load existing data or create new
    var school_db = if (loadExistingData(&db_parser, alloc)) |existing_data|
        try schuldb.fromData(alloc, existing_data.value)
    else
        schuldb.init(alloc);
    defer school_db.deinit();

    try writer.print("schulddb: {}", .{school_db});

    const data = school_db.toData();
    try db_parser.write_content(&data);
}

fn loadExistingData(db: *db_parser_t, allocator: std.mem.Allocator) ?std.json.Parsed(schuldb_mod.SchulDBData) {
    return db.get_content(allocator) catch |err| switch (err) {
        // error.EndOfStream => {
        //     // Empty file, return null to create new database
        //     return null;
        // },
        else => {
            std.debug.print("Error loading database: {}\n", .{err});
            return null;
        },
    };
}
const std = @import("std");

const schule_lib = @import("schule_zig_lib");
const args = schule_lib.args;
const simpledb = schule_lib.simpledb;
const shellcmd = schule_lib.shellcmd.shellcmd;
const schuldb = schule_lib.schuldb.schuldb;
const schuldb_mod = schule_lib.schuldb;
