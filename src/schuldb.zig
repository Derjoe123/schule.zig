const std = @import("std");

pub const Priority = enum {
    Low,
    Medium,
    High,
    Critical,

    pub fn getValue(self: Priority) u8 {
        return switch (self) {
            .Low => 1,
            .Medium => 2,
            .High => 3,
            .Critical => 4,
        };
    }

    pub fn fromString(str: []const u8) ?Priority {
        if (std.mem.eql(u8, str, "low")) return .Low;
        if (std.mem.eql(u8, str, "medium")) return .Medium;
        if (std.mem.eql(u8, str, "high")) return .High;
        if (std.mem.eql(u8, str, "critical")) return .Critical;
        return null;
    }
};

pub const Status = enum {
    NotStarted,
    InProgress,
    Completed,
    Overdue,

    pub fn fromString(str: []const u8) ?Status {
        if (std.mem.eql(u8, str, "not_started")) return .NotStarted;
        if (std.mem.eql(u8, str, "in_progress")) return .InProgress;
        if (std.mem.eql(u8, str, "completed")) return .Completed;
        if (std.mem.eql(u8, str, "overdue")) return .Overdue;
        return null;
    }
};

pub const ItemType = enum {
    Assignment,
    Homework,
    Project,
    Exam,
    Event,

    pub fn fromString(str: []const u8) ?ItemType {
        if (std.mem.eql(u8, str, "assignment")) return .Assignment;
        if (std.mem.eql(u8, str, "homework")) return .Homework;
        if (std.mem.eql(u8, str, "project")) return .Project;
        if (std.mem.eql(u8, str, "exam")) return .Exam;
        if (std.mem.eql(u8, str, "event")) return .Event;
        return null;
    }
};

pub const SchoolItem = struct {
    id: u32,
    title: []const u8,
    description: ?[]const u8,
    subject: []const u8,
    item_type: ItemType,
    priority: Priority,
    status: Status,
    due_date: ?[]const u8, // Format: "YYYY-MM-DD"
    created_date: []const u8, // Format: "YYYY-MM-DD"
    notes: ?[]const u8,
};

// JSON-serializable data structure
pub const SchulDBData = struct {
    items: []SchoolItem,
    next_id: u32,
};

pub const schuldb = struct {
    const Self = @This();

    items: std.ArrayList(SchoolItem),
    next_id: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .items = std.ArrayList(SchoolItem).init(allocator),
            .next_id = 1,
            .allocator = allocator,
        };
    }

    pub fn fromData(allocator: std.mem.Allocator, data: SchulDBData) !Self {
        var self = Self.init(allocator);
        self.next_id = data.next_id;

        for (data.items) |item| {
            try self.items.append(item);
        }

        return self;
    }

    pub fn toData(self: *const Self) SchulDBData {
        return SchulDBData{
            .items = self.items.items,
            .next_id = self.next_id,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free memory for strings in items
        for (self.items.items) |item| {
            self.allocator.free(item.title);
            if (item.description) |desc| self.allocator.free(desc);
            self.allocator.free(item.subject);
            self.allocator.free(item.created_date);
            if (item.due_date) |due| self.allocator.free(due);
            if (item.notes) |notes| self.allocator.free(notes);
        }
        self.items.deinit();
    }

    // Command: add <title> <subject> <type> <priority> [due_date] [description]
    pub fn add(self: *Self, args: []const u8) !void {
        std.debug.print("args: {s}\n", .{args});
        var parts = std.mem.splitScalar(u8, args, ' ');

        const title = parts.next() orelse return error.MissingTitle;
        const subject = parts.next() orelse return error.MissingSubject;
        const type_str = parts.next() orelse return error.MissingType;
        const priority_str = parts.next() orelse return error.MissingPriority;

        const item_type = ItemType.fromString(type_str) orelse return error.InvalidType;
        const priority = Priority.fromString(priority_str) orelse return error.InvalidPriority;

        const due_date = parts.next();
        const description = parts.next();

        // Get current date (simplified - you might want to use a proper date library)
        const created_date = try self.allocator.dupe(u8, "2024-08-12"); // You should implement proper date handling

        const new_item = SchoolItem{
            .id = self.next_id,
            .title = try self.allocator.dupe(u8, title),
            .description = if (description) |desc| try self.allocator.dupe(u8, desc) else null,
            .subject = try self.allocator.dupe(u8, subject),
            .item_type = item_type,
            .priority = priority,
            .status = .NotStarted,
            .due_date = if (due_date) |due| try self.allocator.dupe(u8, due) else null,
            .created_date = created_date,
            .notes = null,
        };

        try self.items.append(new_item);
        self.next_id += 1;

        std.debug.print("Added item '{any}' with ID {any}\n", .{ title, new_item.id });
    }

    // Command: remove <id>
    pub fn remove(self: *Self, args: []const u8) !void {
        const id = std.fmt.parseInt(u32, std.mem.trim(u8, args, " "), 10) catch return error.InvalidId;

        for (self.items.items, 0..) |item, i| {
            if (item.id == id) {
                const removed_item = self.items.swapRemove(i);

                // Free memory
                self.allocator.free(removed_item.title);
                if (removed_item.description) |desc| self.allocator.free(desc);
                self.allocator.free(removed_item.subject);
                self.allocator.free(removed_item.created_date);
                if (removed_item.due_date) |due| self.allocator.free(due);
                if (removed_item.notes) |notes| self.allocator.free(notes);

                std.debug.print("Removed item with ID {}\n", .{id});
                return;
            }
        }
        return error.ItemNotFound;
    }

    // Command: list [filter]
    pub fn list(self: *Self, args: []const u8, writer: anytype) !void {
        const filter = std.mem.trim(u8, args, " ");

        try writer.print("ID\tTitle\t\t\tSubject\t\tType\t\tPriority\tStatus\t\tDue Date\n", .{});
        try writer.print("--------------------------------------------------------------------\n", .{});

        for (self.items.items) |item| {
            // Apply filter if provided
            if (filter.len > 0) {
                if (!std.mem.containsAtLeast(u8, item.subject, 1, filter) and
                    !std.mem.containsAtLeast(u8, item.title, 1, filter))
                {
                    continue;
                }
            }

            const due_str = if (item.due_date) |due| due else "None";
            try writer.print("{}\t{s:<20}\t{s:<10}\t{s:<10}\t{s:<10}\t{s:<10}\t{s}\n", .{ item.id, item.title, item.subject, @tagName(item.item_type), @tagName(item.priority), @tagName(item.status), due_str });
        }
    }

    // Command: status
    pub fn status(self: *Self, args: []const u8, writer: anytype) !void {
        _ = args; // unused

        try writer.print("=== SCHOOL STATUS REPORT ===\n\n", .{});

        // Show overdue items
        try writer.print("OVERDUE ITEMS:\n", .{});
        var has_overdue = false;
        for (self.items.items) |item| {
            if (item.status == .Overdue) {
                has_overdue = true;
                const due_str = if (item.due_date) |due| due else "No due date";
                try writer.print("  [{}] {s} ({s}) - Due: {s}\n", .{ item.id, item.title, item.subject, due_str });
            }
        }
        if (!has_overdue) try writer.print("  None\n", .{});

        // Show high priority items
        try writer.print("\nHIGH PRIORITY ITEMS:\n", .{});
        var has_high_priority = false;
        for (self.items.items) |item| {
            if (item.priority == .High or item.priority == .Critical) {
                has_high_priority = true;
                const due_str = if (item.due_date) |due| due else "No due date";
                try writer.print("  [{}] {s} ({s}) - Priority: {s}, Due: {s}\n", .{ item.id, item.title, item.subject, @tagName(item.priority), due_str });
            }
        }
        if (!has_high_priority) try writer.print("  None\n", .{});

        // Show upcoming items (items with due dates in the next 7 days)
        try writer.print("\nUPCOMING ITEMS:\n", .{});
        var has_upcoming = false;
        for (self.items.items) |item| {
            if (item.due_date != null and item.status != .Completed) {
                has_upcoming = true;
                try writer.print("  [{}] {s} ({s}) - Due: {s}\n", .{ item.id, item.title, item.subject, item.due_date.? });
            }
        }
        if (!has_upcoming) try writer.print("  None\n", .{});
    }

    // Command: modify <id> <field> <value>
    pub fn modify(self: *Self, args: []const u8, writer: anytype) !void {
        var parts = std.mem.splitScalar(u8, args, ' ');

        const id_str = parts.next() orelse return error.MissingId;
        const field = parts.next() orelse return error.MissingField;
        const value = parts.next() orelse return error.MissingValue;

        const id = std.fmt.parseInt(u32, id_str, 10) catch return error.InvalidId;

        for (self.items.items) |*item| {
            if (item.id == id) {
                if (std.mem.eql(u8, field, "status")) {
                    item.status = Status.fromString(value) orelse return error.InvalidStatus;
                } else if (std.mem.eql(u8, field, "priority")) {
                    item.priority = Priority.fromString(value) orelse return error.InvalidPriority;
                } else if (std.mem.eql(u8, field, "due_date")) {
                    if (item.due_date) |old_due| self.allocator.free(old_due);
                    item.due_date = try self.allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, field, "notes")) {
                    if (item.notes) |old_notes| self.allocator.free(old_notes);
                    item.notes = try self.allocator.dupe(u8, value);
                } else {
                    return error.InvalidField;
                }

                try writer.print("Modified item {any} - set {any} to {any}\n", .{ id, field, value });
                return;
            }
        }
        return error.ItemNotFound;
    }

    // Command: rank [by_priority|by_due]
    pub fn rank(self: *Self, args: []const u8, writer: anytype) !void {
        const sort_type = std.mem.trim(u8, args, " ");

        if (std.mem.eql(u8, sort_type, "by_priority") or sort_type.len == 0) {
            std.mem.sort(SchoolItem, self.items.items, {}, compareByPriority);
            try writer.print("Items sorted by priority (highest first):\n", .{});
        } else if (std.mem.eql(u8, sort_type, "by_due")) {
            std.mem.sort(SchoolItem, self.items.items, {}, compareByDueDate);
            try writer.print("Items sorted by due date (earliest first):\n", .{});
        } else {
            return error.InvalidSortType;
        }

        try self.list("", writer);
    }

    // Command: search <query>
    pub fn search(self: *Self, args: []const u8, writer: anytype) !void {
        const query = std.mem.trim(u8, args, " ");
        if (query.len == 0) return error.EmptyQuery;

        try writer.print("Search results for '{s}':\n", .{query});
        try writer.print("ID\tTitle\t\t\tSubject\t\tType\t\tPriority\tStatus\t\tDue Date\n", .{});
        try writer.print("--------------------------------------------------------------------\n", .{});

        var found = false;
        for (self.items.items) |item| {
            if (std.mem.containsAtLeast(u8, item.title, 1, query) or
                std.mem.containsAtLeast(u8, item.subject, 1, query) or
                (item.description != null and std.mem.containsAtLeast(u8, item.description.?, 1, query)) or
                (item.notes != null and std.mem.containsAtLeast(u8, item.notes.?, 1, query)))
            {
                found = true;
                const due_str = if (item.due_date) |due| due else "None";
                std.debug.print("{}\t{s:<20}\t{s:<10}\t{s:<10}\t{s:<10}\t{s:<10}\t{s}\n", .{ item.id, item.title, item.subject, @tagName(item.item_type), @tagName(item.priority), @tagName(item.status), due_str });
            }
        }

        if (!found) {
            std.debug.print("No items found matching '{s}'\n", .{query});
        }
    }

    fn compareByPriority(context: void, a: SchoolItem, b: SchoolItem) bool {
        _ = context;
        return a.priority.getValue() > b.priority.getValue();
    }

    fn compareByDueDate(context: void, a: SchoolItem, b: SchoolItem) bool {
        _ = context;
        // Items without due dates go to the end
        if (a.due_date == null and b.due_date == null) return false;
        if (a.due_date == null) return false;
        if (b.due_date == null) return true;

        // Simple string comparison works for YYYY-MM-DD format
        return std.mem.lessThan(u8, a.due_date.?, b.due_date.?);
    }
};
