const std = @import("std");
const request = @import("request.zig");
const builtin = @import("builtin");
const testing = std.testing;

pub const Update = struct {
    update_id: i64,
    chat_id: i64,
    text: []const u8,
};

pub const GetUpdatesError = error{NoMessages};

pub const Telezig = struct {
    allocator: std.mem.Allocator,
    token: [46]u8,

    pub fn init(allocator: std.mem.Allocator, token_path: []const u8) !Telezig {
        var result = Telezig{.allocator = allocator, .token = undefined};
        try getToken(token_path, &result.token);
        return result;
    }

    // pub fn deinit(self: *Telezig) void {
    //     //For future deiniting
    // }

    pub fn runEchoBot(self: Telezig, interval_seconds: u64, onMessageReceived: fn (self: Telezig, update: Update) void) anyerror!void {
        var update_id: i64 = std.math.minInt(i64);

        while (true) {
            defer std.time.sleep(interval_seconds * std.time.ns_per_s);
            var update = try self.getUpdates();
            defer self.allocator.free(update.text);

            var new_update_id = update.update_id;
            if (update_id == new_update_id) {
                continue;
            }

            update_id = new_update_id;
            onMessageReceived(self, update);
        }
    }

    fn getToken(token_path: []const u8, token_buffer: []u8) !void {
        const file = try std.fs.cwd().openFile(token_path, .{ .mode = .read_only });
        defer file.close();
        const bytes_read = try file.reader().read(token_buffer);
        if (bytes_read != token_buffer.len) return error.BadTokenFile;
    }

    fn getUpdates(self: Telezig) !Update {
        const host = "api.telegram.org";
        const path = "/bot{s}" ++ "/getUpdates?offset=-1";
        var buffer = [_]u8{undefined} ** (host.len + path.len + self.token.len);
        const formatted_path = try std.fmt.bufPrint(&buffer, path, .{self.token});

        var response = try request.makeGetRequestAlloc(self.allocator, host, formatted_path);

        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(response);
        defer tree.deinit();

        var result = tree.root.Object.get("result").?.Array;

        if (result.items.len < 1) {
            return GetUpdatesError.NoMessages;
        }

        var lastIndex = result.items.len - 1;
        var update_id = result.items[0].Object.get("update_id").?.Integer;
        var message = result.items[lastIndex].Object.get("message").?;
        var text = message.Object.get("text").?.String;
        defer self.allocator.free(text);
        var chat = message.Object.get("chat").?;
        var chat_id = chat.Object.get("id").?;

        return Update{
            .update_id = update_id,
            .chat_id = chat_id.Integer,
            .text = try self.allocator.dupe(u8, text),
        };
    }

    pub fn sendMessage(self: Telezig, update: Update) !void {
        const host = "api.telegram.org";
        const path = "/bot{s}" ++ "/sendMessage";
        var buffer = [_]u8{undefined} ** (host.len + path.len + self.token.len);
        const formatted_path = try std.fmt.bufPrint(&buffer, path, .{self.token});

        const echo_complete = try std.fmt.allocPrint(self.allocator, "{{ \"chat_id\": {d}, \"text\": \"{s}\" }}", .{ update.chat_id, update.text });
        defer self.allocator.free(echo_complete);

        var response = try request.makePostRequestAlloc(self.allocator, host, formatted_path, echo_complete, "Content-Type: application/json");
        defer self.allocator.free(response);
    }
};

//Test function, do not use for library
fn onMessageReceived1(telezig: Telezig, update: Update) void {
    telezig.sendMessage(.{ .update_id = update.update_id, .chat_id = update.chat_id, .text = update.text }) catch unreachable;
}

test "Echobot test" {
    // windows-only initialization
    if (builtin.os.tag == std.Target.Os.Tag.windows) _ = try std.os.windows.WSAStartup(2, 0);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    //var allocator = std.testing.allocator;
    var telezig = try Telezig.init(allocator, "token.txt");
    try telezig.runEchoBot(10, onMessageReceived1);

    // windows-only cleanup
    if (builtin.os.tag == std.Target.Os.Tag.windows) try std.os.windows.WSACleanup();
}
