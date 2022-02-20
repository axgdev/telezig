const std = @import("std");
const testing = std.testing;
const request = @import("request.zig");

pub const Update = struct {
    update_id: i64,
    chat_id: i64,
    text: []const u8,
};

pub const GetUpdatesError = error{NoMessages};

pub const TOKEN_LENGTH = 46;

pub const Telezig = struct {
    allocator: std.mem.Allocator,
    token: [TOKEN_LENGTH]u8,

    pub fn init(allocator: std.mem.Allocator, token_path: []const u8) !Telezig {
        var token_buffer = [_]u8{undefined} ** TOKEN_LENGTH;
        try getToken(token_path, &token_buffer);
        return Telezig{ .allocator = allocator, .token = token_buffer };
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

    fn getToken(token_path: []const u8, token_buffer: *[TOKEN_LENGTH]u8) !void {
        const file = try std.fs.cwd().openFile(token_path, .{ .mode = .read_only });
        defer file.close();
        _ = try file.reader().readAll(token_buffer[0..]);
    }

    fn getUpdates(self: Telezig) !Update {
        const host = "api.telegram.org";
        const path = "/bot{s}" ++ "/getUpdates?offset=-1";
        var buffer = [_]u8{undefined} ** (host.len + path.len + TOKEN_LENGTH);
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
        var buffer = [_]u8{undefined} ** (host.len + path.len + TOKEN_LENGTH);
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    //var allocator = std.testing.allocator;
    var telezig = try Telezig.init(allocator, "token.txt");
    try telezig.runEchoBot(10, onMessageReceived1);
}
