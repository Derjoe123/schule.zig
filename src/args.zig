pub const Flag = struct {
    name: []const u8,
    desc: []const u8,
};
pub fn display_args_help(writer: anytype, Struct: anytype, flags: []const Flag) !void {
    const info = @typeInfo(@TypeOf(Struct.*));
    std.debug.assert(info == .@"struct");
    _ = try writer.write("Help Menu:\n");
    _ = try writer.write("Usage: <prog_name> <command> <command input> <flags> <args>\n");
    _ = try writer.write("command example: status\n");
    _ = try writer.write("Command options:\n");
    _ = try writer.write("Flag example: --help\n");
    _ = try writer.write("Flags options:\n");
    for (flags) |flag| {
        try std.fmt.format(writer, "\n\t{s}: \n\tdesc: {s}\n", .{ flag.name, flag.desc });
    }
    _ = try writer.write("Arg example: -directory ~/schule/\n");
    _ = try writer.write("Args options:\n");
    inline for (info.@"struct".fields) |field| {
        switch (field.type) {
            []const u8, []u8 => {
                try std.fmt.format(writer, "\n\t{s}: \n\t\ttype: {s}\n\t\tdefault: \"{s}\"\n", .{ field.name, @typeName(field.type), field.defaultValue() orelse "No Default" });
            },
            else => {
                try std.fmt.format(writer, "\n\t{s}: \n\t\ttype: {s}\n\t\tdefault: {}\n", .{ field.name, @typeName(field.type), field.defaultValue() orelse null });
            },
        }
    }
}
pub fn flag_set(args: [][*:0]u8, flag_name: []const u8) bool {
    for (args) |arg| {
        var arg_slice: []const u8 = undefined;
        arg_slice.len = std.mem.len(arg);
        arg_slice.ptr = arg;
        if (std.mem.eql(u8, arg_slice, flag_name)) {
            return true;
        }
    }
    return false;
}
pub fn parse_args(args: [][*:0]u8, Struct: anytype) !void {
    const info = @typeInfo(@TypeOf(Struct.*));
    std.debug.assert(info == .@"struct");
    inline for (info.@"struct".fields) |field| {
        const fieldname: []const u8 = field.name;
        if (try_get_arg(args, "-" ++ fieldname)) |arg| {
            switch (field.type) {
                bool => {
                    @field(Struct, field.name) = std.mem.eql(u8, arg, "true") or std.mem.eql(u8, arg, "True");
                    // std.debug.print("bool set to {}\n", .{@field(Struct, field.name)});
                },
                []const u8 => {
                    @field(Struct, field.name) = arg;
                },
                i64, i32, i16, i8, u64, u32, u16, u8 => {
                    @field(Struct, field.name) = try std.fmt.parseInt(field.type, arg, 0);
                },
                f64, f32, f16 => {
                    @field(Struct, field.name) = try std.fmt.parseFloat(field.type, arg, 0);
                },
                else => {
                    @compileError("Type of field: " ++ field.name ++ "is unsupported");
                },
            }
        } else {
            // std.debug.print("Arg not supplied: {s}\n", .{fieldname});
        }
    }
}
pub fn get_arg_or_err(args: [][*:0]u8, arg_name: []const u8) ![]const u8 {
    for (0..args.len) |i| {
        var arg: []u8 = undefined;
        arg.len = std.mem.len(args[i]);
        arg.ptr = args[i];
        if (std.mem.eql(u8, arg, arg_name)) {
            if (i == args.len - 1) {
                return error.FlagSetButNoValueProvided;
            }
            var next_arg: []u8 = undefined;
            next_arg.len = std.mem.len(args[i + i]);
            next_arg.ptr = args[i + i];
            return next_arg;
        }
    }
    return error.FlagNotSet;
}
pub fn try_get_arg(args: [][*:0]u8, arg_name: []const u8) ?[]const u8 {
    for (0..args.len) |i| {
        var arg: []u8 = undefined;
        arg.len = std.mem.len(args[i]);
        arg.ptr = args[i];
        if (std.mem.eql(u8, arg, arg_name)) {
            if (i >= args.len - 1) {
                return null;
            }

            var next_arg: []u8 = undefined;
            next_arg.len = std.mem.len(args[i + 1]);
            next_arg.ptr = args[i + 1];
            return next_arg;
        }
    }
    return null;
}
pub fn get_arg_or_default(args: [][*:0]u8, arg_name: []const u8, or_default_val: []const u8) []const u8 {
    for (0..args.len) |i| {
        var arg: []u8 = undefined;
        arg.len = std.mem.len(args[i]);
        arg.ptr = args[i];
        if (std.mem.eql(u8, arg, arg_name)) {
            if (i == args.len - 1) {
                return or_default_val; // maybe return an error here. there was a flag, but no value supplied.
            }

            var next_arg: []u8 = undefined;
            next_arg.len = std.mem.len(args[i + 1]);
            next_arg.ptr = args[i + 1];
            return next_arg;
        }
    }
    return or_default_val;
}

const std = @import("std");
