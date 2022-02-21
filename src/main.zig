const std = @import("std");
const request = @import("request.zig");
const builtin = @import("builtin");
const testing = std.testing;

pub const Update = struct {
    update_id: i64,
    chat_id: i64,
    text: []const u8,
};

pub const Telezig = struct {
    allocator: std.mem.Allocator,
    token: [46]u8,

    pub fn init(allocator: std.mem.Allocator, token: []const u8) !Telezig {
        if (token.len != 46) return error.BadToken;
        var result = Telezig{.allocator = allocator, .token = undefined};
        std.mem.copy(u8, result.token[0..], token);
        return result;
    }

    // pub fn deinit(self: *Telezig) void {
    //     //For future deiniting
    // }

    pub fn getUpdates(self: Telezig) !Update {
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

        if (result.items.len < 1) return error.NoUpdateMessages;

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


// not related to library, for testing usage only
fn getToken(token_path: []const u8, buffer: []u8) !void {
    const file = try std.fs.cwd().openFile(token_path, .{ .mode = .read_only });
    defer file.close();
    _ = try file.reader().read(buffer);
}

// requires token.txt file in working directory
// checks for message 10 times with 1 second interval
// replies to new messages with same text
test "Echobot test" {
    // windows-only initialization
    if (builtin.os.tag == std.Target.Os.Tag.windows) _ = try std.os.windows.WSAStartup(2, 0);
    
    var allocator = std.testing.allocator;
    var token: [46]u8 = undefined;
    try getToken("token.txt", token[0..]);
    var bot = try Telezig.init(allocator, token[0..]);

    var update_id: i64 = std.math.minInt(i64);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var update = try bot.getUpdates();
        defer bot.allocator.free(update.text);

        var new_update_id = update.update_id;
        if (update_id == new_update_id) continue;
        update_id = new_update_id;

        try bot.sendMessage(update);
        std.time.sleep(1 * std.time.ns_per_s);
    }

    // windows-only cleanup
    if (builtin.os.tag == std.Target.Os.Tag.windows) try std.os.windows.WSACleanup();
}
