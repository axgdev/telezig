const std = @import("std");
const testing = std.testing;
const request = @import("request.zig");

pub const Update = struct {
    update_id: i64,
    chat_id: i64,
    text: []const u8,
};

pub const GetUpdatesError = error{
    NoMessages
};

pub const Telezig = struct {
    allocator: std.mem.Allocator,
    token: []const u8,

    pub fn init(allocator: std.mem.Allocator, token_path: []const u8) !Telezig {
        const token = try getToken(allocator, token_path);
        return Telezig { .allocator = allocator, .token = token  };        
    }

    pub fn deinit(self: *Telezig) void {
        self.allocator.free(self.token);
    }

    pub fn runEchoBot(self: Telezig, interval_seconds: u64, onMessageReceived: fn (self: Telezig, update: Update) void) anyerror!void {
        var update_id: i64 = undefined;

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

    fn getToken(allocator: std.mem.Allocator, token_path: []const u8) ![]u8 {
        const file = try std.fs.cwd().openFile(
            token_path,
            .{ .mode = .read_only }
        );
        defer file.close();

        const token_length = 46;

        const token_file = try file.reader().readAllAlloc(
            allocator,
            token_length+1, //The last character should be ignored
        );
        defer allocator.free(token_file);

        const token = allocator.dupe(u8, token_file[0..token_length]);
        return token;
    }

    fn getUpdates(self: Telezig) !Update {
        const host = "api.telegram.org";
        const path = "/bot{s}" ++ "/getUpdates?offset=-1";
        const formatted_path = try std.fmt.allocPrint(self.allocator, path, .{ self.token });
        defer self.allocator.free(formatted_path);

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
        const formatted_path = try std.fmt.allocPrint(self.allocator, path, .{ self.token });
        defer self.allocator.free(formatted_path);

        const raw_json = \\ {{ "chat_id": {d}, "text": "{s}" }}
        ;

        const echo_response_json_string = try std.fmt.allocPrint(self.allocator, raw_json, .{ update.chat_id, update.text });
        const echo_complete = try std.fmt.allocPrint(self.allocator, "{s}", .{echo_response_json_string});
        defer self.allocator.free(echo_response_json_string);
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
    defer telezig.deinit();
    try telezig.runEchoBot(10, onMessageReceived1);
}
