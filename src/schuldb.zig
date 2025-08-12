pub const schuldb = struct {
    const std = @import("std");
    const Allocator = *std.mem.Allocator;

    pub const Status = enum(u8) {
        Todo = 0,
        InProgress = 1,
        Done = 2,

        pub fn fromText(s: []const u8) Status {
            const lower = std.ascii.toLower(s);
            if (std.mem.eql(u8, lower, "inprogress")) return .InProgress;
            if (std.mem.eql(u8, lower, "done")) return .Done;
            return .Todo;
        }

        pub fn toText(self: Status) []const u8 {
            switch (self) {
                .Todo => "todo",
                .InProgress => "inprogress",
                .Done => "done",
            }
        }
    };

    pub const Item = struct {
        id: usize,
        title: []u8,
        description: []u8,
        due_iso: ?[]u8,         // optional ISO date string, e.g. "2025-09-01T12:00:00Z"
        importance: u8,        // 0..5
        status: Status,
        tags: std.ArrayList([]u8),
        created_at: []u8,      // ISO timestamp strings
        updated_at: []u8,

        pub fn init(allocator: Allocator) Item {
            return Item{
                .id = 0,
                .title = &[_]u8{},
                .description = &[_]u8{},
                .due_iso = null,
                .importance = 0,
                .status = Status.Todo,
                .tags = std.ArrayList([]u8).init(allocator),
                .created_at = &[_]u8{},
                .updated_at = &[_]u8{},
            };
        }

        pub fn deinit(self: *Item, allocator: Allocator) void {
            // free strings
            if (self.title.len != 0) allocator.free(self.title);
            if (self.description.len != 0) allocator.free(self.description);
            if (self.due_iso) allocator.free(self.due_iso.?);
            if (self.created_at.len != 0) allocator.free(self.created_at);
            if (self.updated_at.len != 0) allocator.free(self.updated_at);

            // free tags
            for (self.tags.items) |tag| {
                if (tag.len != 0) allocator.free(tag);
            }
            self.tags.deinit();
        }
    };

    allocator: Allocator,
    items: std.ArrayList(Item),
    next_id: usize,

    pub fn init(allocator: Allocator) schuldb {
        return schuldb{
            .allocator = allocator,
            .items = std.ArrayList(Item).init(allocator),
            .next_id = 1,
        };
    }

    pub fn deinit(self: *schuldb) void {
        // free each item's heap allocations
        for (self.items.items) |*it| {
            it.deinit(self.allocator);
        }
        self.items.deinit();
    }

    //
    // Utility: allocate copy of a slice
    //
    fn allocCopy(self: *schuldb, src: []const u8) ![]u8 {
        if (src.len == 0) return &[_]u8{};
        const buf = try self.allocator.alloc(u8, src.len);
        std.mem.copy(u8, buf, src);
        return buf;
    }

    //
    // Parse a simple "key=value;key2=value2" input. Keys/values are not trimmed aggressively.
    // Recognized keys:
    //  title, desc, due, importance, tags, status
    // tags: comma separated
    //
    fn parseInput(self: *schuldb, input: []const u8, out_map: *std.HashMap([]const u8, []const u8)) !void {
        // Build a temporary small allocator-backed vector of pairs.
        // We'll perform simple splitting.
        var split_iter = std.mem.split(input, ';');
        var it = split_iter.iterator();
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            const eq_idx = std.mem.indexOf(u8, pair, '=');
            if (eq_idx == null) continue;
            const key = pair[0..eq_idx.?];
            const val = pair[eq_idx.? + 1 .. pair.len];
            // insert into out_map (no copies here; caller must copy to persist)
            _ = try out_map.put(key, val);
        }
    }

    //
    // Add an item using the key=value;... input format described above.
    // Returns the assigned id.
    //
    pub fn add(self: *schuldb, input: []const u8) !usize {
        const gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const ga = &gpa.allocator;
        // small HashMap on the stack to capture fields temporarily
        var arena = std.ArenaAllocator.init(self.allocator);
        var map_alloc = arena.allocator();
        var tmp_map = std.HashMap([]const u8, []const u8).init(map_alloc, 16);

        // parse
        try self.parseInput(input, &tmp_map);

        var it = tmp_map.iterator();
        var new_item = Item.init(self.allocator);
        new_item.id = self.next_id;

        // set title
        if (tmp_map.get("title")) |v| {
            new_item.title = try self.allocCopy(v);
        } else {
            new_item.title = try self.allocCopy("untitled");
        }

        if (tmp_map.get("desc")) |v| {
            new_item.description = try self.allocCopy(v);
        } else {
            new_item.description = try self.allocCopy("");
        }

        if (tmp_map.get("due")) |v| {
            new_item.due_iso = try self.allocCopy(v);
        } else new_item.due_iso = null;

        if (tmp_map.get("importance")) |v| {
            // parse integer safely
            const parsed = std.fmt.parseInt(usize, v, 10) catch 0;
            if (parsed > 5) 
        {new_item.importance = 5; }
            else new_item.importance = @intCast(u8, parsed);
        } else new_item.importance = 0;

        if (tmp_map.get("status")) |v| {
            new_item.status = Status.fromText(v);
        } else new_item.status = .Todo;

        // tags
        if (tmp_map.get("tags")) |v| {
            var tag_iter = std.mem.split(v, ',');
            var iter = tag_iter.iterator();
            while (iter.next()) |raw_tag| {
                const t = try self.allocCopy(raw_tag);
                try new_item.tags.append(t);
            }
        }

        // timestamps: use current UTC time as ISO-ish string (seconds precision)
        const now = std.time.milliTimestamp();
        const ts_str = try std.fmt.allocPrint(self.allocator, "ts:{}", .{now});
        new_item.created_at = ts_str;
        new_item.updated_at = ts_str;

        try self.items.append(new_item);
        self.next_id += 1;

        // cleanup tmp_map
        tmp_map.deinit();
        arena.deinit();

        return self.next_id - 1;
    }

    //
    // Remove an item by id. Returns true if removed.
    //
    pub fn remove(self: *schuldb, id: usize) bool {
        var i: usize = 0;
        while (i < self.items.len) : (i += 1) {
            if (self.items.items[i].id == id) {
                // free internal allocations of item
                self.items.items[i].deinit(self.allocator);
                // remove from arraylist
                // shift items left
                self.items.removeAt(i);
                return true;
            }
        }
        return false;
    }

    //
    // Modify: supply id and a "key=value;..." string. Only provided keys are updated.
    //
    pub fn modify(self: *schuldb, id: usize, input: []const u8) !bool {
        var found: ?*Item = null;
        for (self.items.items) |*it| {
            if (it.id == id) { found = it; break; }
        }
        if (found == null) return false;

        var item = found.?;

        // parse input into temporary map
        var arena = std.ArenaAllocator.init(self.allocator);
        var map_alloc = arena.allocator();
        var tmp_map = std.HashMap([]const u8, []const u8).init(map_alloc, 16);
        try self.parseInput(input, &tmp_map);

        if (tmp_map.get("title")) |v| {
            if (item.title.len != 0) self.allocator.free(item.title);
            item.title = try self.allocCopy(v);
        }
        if (tmp_map.get("desc")) |v| {
            if (item.description.len != 0) self.allocator.free(item.description);
            item.description = try self.allocCopy(v);
        }
        if (tmp_map.get("due")) |v| {
            if (item.due_iso) self.allocator.free(item.due_iso.?);
            item.due_iso = try self.allocCopy(v);
        }
        if (tmp_map.get("importance")) |v| {
            const parsed = std.fmt.parseInt(usize, v, 10) catch 0;
            item.importance = if (parsed > 5) 5 else @intCast(u8, parsed);
        }
        if (tmp_map.get("status")) |v| {
            item.status = Status.fromText(v);
        }
        if (tmp_map.get("tags")) |v| {
            // clear old tags
            for (item.tags.items) |tag| {
                if (tag.len != 0) self.allocator.free(tag);
            }
            item.tags.clear();
            var tag_iter = std.mem.split(tmp_map.get("tags").?, ',');
            var iter = tag_iter.iterator();
            while (iter.next()) |raw_tag| {
                const t = try self.allocCopy(raw_tag);
                try item.tags.append(t);
            }
        }

        // update timestamp
        const now = std.time.milliTimestamp();
        if (item.updated_at.len != 0) self.allocator.free(item.updated_at);
        item.updated_at = try std.fmt.allocPrint(self.allocator, "ts:{}", .{now});

        tmp_map.deinit();
        arena.deinit();
        return true;
    }

    //
    // List: write all items to a writer using a compact textual format.
    //
    pub fn listToWriter(self: *schuldb, w: anytype) !void {
        const out = w;
        var i: usize = 0;
        while (i < self.items.len) : (i += 1) {
            const it = &self.items.items[i];
            try out.print("id: {d} | title: {s} | importance: {d} | status: {s}\n", .{it.id, it.title, it.importance, it.status.toText()});
            if (it.due_iso) try out.print("  due: {s}\n", .{it.due_iso.?});
            if (it.description.len != 0) try out.print("  desc: {s}\n", .{it.description});
            if (it.tags.len != 0) {
                try out.print("  tags: ", .{});
                var ti: usize = 0;
                while (ti < it.tags.len) : (ti += 1) {
                    try out.print("{s}{s}", .{it.tags.items[ti], if (ti + 1 < it.tags.len) "," else "\n"});
                }
            }
            try out.print("\n", .{});
        }
    }

    //
    // Rank: sort items in-place by importance desc, then by due date asc
    //
    pub fn rank(self: *schuldb) void {
        const compare = fn(a: *const Item, b: *const Item) i32 {{
            if (a.importance > b.importance) return -1;
            if (a.importance < b.importance) return 1;
            // both same importance, compare due dates
            const a_due = a.due_iso;
            const b_due = b.due_iso;
            if (a_due and b_due) {
                const cmp = std.mem.eql(u8, a_due.?, b_due.?) catch false;
                if (cmp) return 0;
                // naive lexicographic ISO comparison works for ISO timestamps
                if (std.mem.lexicographicalCompare(u8, a_due.?, b_due.?) < 0) return -1;
                return 1;
            } else if (a_due) {
                return -1; // items with due date come before those without
            } else if (b_due) {
                return 1;
            } else return 0;
        }};

        std.sort.sort(self.items.items[0..self.items.len], compare);
    }

    //
    // Status: write upcoming and important items to writer.
    // upcoming_days: SSE interpret as "if due date within this many days" but because
    // we store due as ISO strings, this function performs a naive lexicographic comparison
    // if you pass absolute ISO 'now' plus days. For simplicity we detect upcoming by comparing
    // due_iso < now_plus_days_iso lexicographically (works for ISO strings).
    //
    pub fn status(self: *schuldb, writer: anytype, now_plus_days_iso: ?[]const u8, important_threshold: u8) !void {
        try writer.print("Status summary:\n", .{});
        try writer.print("Important items (importance >= {d}):\n", .{important_threshold});
        var any_imp = false;
        for (self.items.items) |it| {
            if (it.importance >= important_threshold) {
                any_imp = true;
                try writer.print(" - [{d}] {s} (imp={d})\n", .{it.id, it.title, it.importance});
            }
        }
        if (!any_imp) try writer.print("  (none)\n", .{});

        if (now_plus_days_iso) {
            try writer.print("\nUpcoming items (due <= {s}):\n", .{now_plus_days_iso.?});
            var any_up = false;
            for (self.items.items) |it| {
                if (it.due_iso) {
                    // lex compare
                    if (std.mem.lexicographicalCompare(u8, it.due_iso.?, now_plus_days_iso.?) <= 0) {
                        any_up = true;
                        try writer.print(" - [{d}] {s} due {s}\n", .{it.id, it.title, it.due_iso.?});
                    }
                }
            }
            if (!any_up) try writer.print("  (none)\n", .{});
        }
    }

    //
    // Save to file (JSON). This function builds a JSON string and writes it atomically.
    //
    pub fn saveToFile(self: *schuldb, path: []const u8) !void {
        const fs = std.fs;
        const cwd = fs.cwd();

        // Build JSON string in a single buffer
        var out_buf = std.ArrayList(u8).init(self.allocator);
        defer out_buf.deinit();

        fn escapeAppend(buf: *std.ArrayList(u8), s: []const u8, allocator: Allocator) !void {
            // Minimal string escaper for JSON (\" and \\ and control to \uXXXX - we will replace control with ?)
            var i: usize = 0;
            try buf.append('"');
            while (i < s.len) : (i += 1) {
                const c = s[i];
                switch (c) {
                    0x22 => try buf.appendSlice("\\\""), // "
                    0x5C => try buf.appendSlice("\\\\"), // \
                    0x0A => try buf.appendSlice("\\n"),
                    0x0D => try buf.appendSlice("\\r"),
                    0x09 => try buf.appendSlice("\\t"),
                    else => try buf.append(c),
                }
            }
            try buf.append('"');
        }

        try out_buf.appendSlice("[");
        var first = true;
        var i: usize = 0;
        while (i < self.items.len) : (i += 1) {
            const it = &self.items.items[i];
            if (!first) try out_buf.appendSlice(",");
            first = false;
            try out_buf.appendSlice("{");

            // id
            try out_buf.appendSlice("\"id\":");
            try out_buf.appendSlice(std.fmt.allocPrint(self.allocator, "{}", .{it.id}));
            try out_buf.appendSlice(",");

            // title
            try out_buf.appendSlice("\"title\":");
            try escapeAppend(&out_buf, it.title, self.allocator);
            try out_buf.appendSlice(",");

            // description
            try out_buf.appendSlice("\"description\":");
            try escapeAppend(&out_buf, it.description, self.allocator);
            try out_buf.appendSlice(",");

            // due
            try out_buf.appendSlice("\"due_iso\":");
            if (it.due_iso) try escapeAppend(&out_buf, it.due_iso.?, self.allocator) else try out_buf.appendSlice("null");
            try out_buf.appendSlice(",");

            // importance
            try out_buf.appendSlice("\"importance\":");
            try out_buf.appendSlice(std.fmt.allocPrint(self.allocator, "{}", .{it.importance}));
            try out_buf.appendSlice(",");

            // status
            try out_buf.appendSlice("\"status\":");
            try escapeAppend(&out_buf, it.status.toText(), self.allocator);
            try out_buf.appendSlice(",");

            // tags
            try out_buf.appendSlice("\"tags\":[");
            var ti: usize = 0;
            while (ti < it.tags.len) : (ti += 1) {
                if (ti != 0) try out_buf.appendSlice(",");
                try escapeAppend(&out_buf, it.tags.items[ti], self.allocator);
            }
            try out_buf.appendSlice("],");

            // timestamps
            try out_buf.appendSlice("\"created_at\":");
            try escapeAppend(&out_buf, it.created_at, self.allocator);
            try out_buf.appendSlice(",");

            try out_buf.appendSlice("\"updated_at\":");
            try escapeAppend(&out_buf, it.updated_at, self.allocator);

            try out_buf.appendSlice("}");
        }
        try out_buf.appendSlice("]");

        // write atomically (write to tmp then rename)
        const tmp_path = try std.fmt.allocPrint(self.allocator, "{}.tmp", .{path});
        defer self.allocator.free(tmp_path);

        const file = try cwd.createFile(tmp_path, .{ .create = true, .truncate = true });
        defer file.close();
        try file.writeAll(out_buf.toSlice());

        // rename
        try cwd.rename(tmp_path, path);
    }

    //
    // Load from a file written by saveToFile above.
    // This loader assumes the JSON format produced by saveToFile and will parse it simply.
    // If you want to accept arbitrary JSON, replace this with parsing via `std.json.parse`.
    //
    pub fn loadFromFile(self: *schuldb, path: []const u8) !void {
        const fs = std.fs;
        const cwd = fs.cwd();
        var file = try cwd.openFile(path, .{});
        defer file.close();
        const fileData = try file.readToEndAlloc(self.allocator, 4096);
        defer self.allocator.free(fileData);

        // If file empty -> nothing to do
        if (fileData.len == 0) return;

        // Very small, forgiving parser for the exact format we produce:
        // We look for objects {...} separated by commas, and extract fields by naive search.
        // This is not a full JSON parser. For robust loading, use std.json.parse (left as exercise).
        var i: usize = 0;
        // find first '['
        while (i < fileData.len and fileData[i] != '[') : (i += 1) {}
        if (i >= fileData.len) return;
        i += 1;

        // naive object iteration
        while (i < fileData.len) {
            // skip whitespace/comma
            while (i < fileData.len and (fileData[i] == ' ' or fileData[i] == '\n' or fileData[i] == '\r' or fileData[i] == ',' or fileData[i] == '\t')) : (i += 1) {}

            if (i >= fileData.len) break;
            if (fileData[i] == ']') break;
            if (fileData[i] != '{') break;
            // find matching '}'
            var obj_start = i;
            var depth: usize = 0;
            while (i < fileData.len) {
                if (fileData[i] == '{') depth += 1;
                else if (fileData[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        break;
                    }
                }
                i += 1;
            }
            if (i >= fileData.len) break;
            const obj_end = i;
            const obj_slice = fileData[obj_start .. obj_end+1];

            // now extract fields using simple substring searches
            fn extract_string_field(data: []const u8, key: []const u8) ?[]const u8 {
                const needle = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key}) catch return null;
                defer std.heap.page_allocator.free(needle);
                const pos = std.mem.indexOfSlice(u8, data, needle) catch return null;
                var j = pos.? + needle.len;
                // skip whitespace
                while (j < data.len and std.ascii.isSpace(data[j])) j += 1;
                if (j >= data.len) return null;
                if (data[j] == 'n') return null; // null
                if (data[j] != '"') return null;
                j += 1;
                var start = j;
                while (j < data.len and data[j] != '"') j += 1;
                if (j >= data.len) return null;
                return data[start..j];
            }

            fn extract_number_field(data: []const u8, key: []const u8) ?[]const u8 {
                const needle = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key}) catch return null;
                defer std.heap.page_allocator.free(needle);
                const pos = std.mem.indexOfSlice(u8, data, needle) catch return null;
                var j = pos.? + needle.len;
                // skip whitespace
                while (j < data.len and std.ascii.isSpace(data[j])) j += 1;
                if (j >= data.len) return null;
                var start = j;
                while (j < data.len and ((data[j] >= '0' and data[j] <= '9'))) j += 1;
                return data[start..j];
            }

            const maybe_id = extract_number_field(obj_slice, "id");
            var new_item = Item.init(self.allocator);
            if (maybe_id) {
                const idv = std.fmt.parseInt(usize, maybe_id.?, 10) catch 0;
                new_item.id = idv;
                if (idv >= self.next_id) self.next_id = idv + 1;
            } else {
                new_item.id = self.next_id;
                self.next_id += 1;
            }

            if (extract_string_field(obj_slice, "title")) |v| {
                new_item.title = try self.allocCopy(v);
            } else new_item.title = try self.allocCopy("untitled");

            if (extract_string_field(obj_slice, "description")) |v| {
                new_item.description = try self.allocCopy(v);
            } else new_item.description = try self.allocCopy("");

            if (extract_string_field(obj_slice, "due_iso")) |v| {
                new_item.due_iso = try self.allocCopy(v);
            } else new_item.due_iso = null;

            if (extract_number_field(obj_slice, "importance")) |v| {
                const p = std.fmt.parseInt(usize, v, 10) catch 0;
                new_item.importance = if (p > 5) 5 else @intCast(u8, p);
            } else new_item.importance = 0;

            if (extract_string_field(obj_slice, "status")) |v| {
                new_item.status = Status.fromText(v);
            } else new_item.status = .Todo;

            if (extract_string_field(obj_slice, "created_at")) |v| {
                new_item.created_at = try self.allocCopy(v);
            } else new_item.created_at = try self.allocCopy("");

            if (extract_string_field(obj_slice, "updated_at")) |v| {
                new_item.updated_at = try self.allocCopy(v);
            } else new_item.updated_at = try self.allocCopy("");

            // tags: naive extraction of items between "tags":[ ... ]
            const tag_key = std.fmt.allocPrint(std.heap.page_allocator, "\"tags\":[") catch null;
            if (tag_key != null) {
                const tpos = std.mem.indexOfSlice(u8, obj_slice, tag_key) catch null;
                if (tpos) {
                    var j = tpos.? + tag_key.len;
                    var cur_tag_start: ?usize = null;
                    while (j < obj_slice.len) {
                        if (obj_slice[j] == '"') {
                            if (cur_tag_start == null) {
                                cur_tag_start = j + 1;
                            } else {
                                const start = cur_tag_start.?;
                                const t = obj_slice[start .. j];
                                const tc = try self.allocCopy(t);
                                try new_item.tags.append(tc);
                                cur_tag_start = null;
                            }
                        } else if (obj_slice[j] == ']') {
                            break;
                        }
                        j += 1;
                    }
                }
                std.heap.page_allocator.free(tag_key);
            }

            try self.items.append(new_item);

            i += 1;
        }
    }
};
