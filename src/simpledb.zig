const std = @import("std");
pub fn SimpleDB(comptime DBStructType: type, comptime MaxByteSize: usize) type {
    return struct {
        const Self = @This();
        db_file: std.fs.File = undefined,
        fn get_db_content(self: *const Self, allocator: anytype) ![]u8 {
            const arr = try self.db_file.readToEndAlloc(allocator, MaxByteSize);
            try self.db_file.seekTo(0);
            _ = try self.db_file.readAll(arr);
            return arr;
        }
        pub fn get_content(self: *const Self, allocator: anytype) !std.json.Parsed(DBStructType) {
            const content = try self.get_db_content(allocator);
            defer allocator.free(content);
            return try std.json.parseFromSlice(DBStructType, allocator, content, .{});
        }
        pub fn write_content(self: *const Self, content: *const DBStructType) !void {
            try self.db_file.seekTo(0);
            try self.db_file.setEndPos(0);
            const dbwriter = self.db_file.writer();
            try std.json.stringify(content, .{}, dbwriter);
        }
        pub fn init(db_file_abs_path: []const u8) std.fs.File.OpenError!Self {
            var s: Self = undefined;

            s.db_file = std.fs.openFileAbsolute(db_file_abs_path, .{ .mode = .read_write }) catch |err| blk: {
                std.debug.print("SimpleDB.init: Open File Error: {}", .{err});
                _ = try std.fs.createFileAbsolute(db_file_abs_path, .{ .exclusive = false });
                break :blk try std.fs.openFileAbsolute(db_file_abs_path, .{ .mode = .read_write });
            };

            return s;
        }
        pub fn deinit(self: *const Self) void {
            self.db_file.close();
        }
    };
}
