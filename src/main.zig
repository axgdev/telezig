const std = @import("std");
const testing = std.testing;
const request = @import("request.zig");

pub const Update = struct {
    updateId: i64,
    chatId: i64,
    text: []const u8,
};

pub const GetUpdatesError = error{
    NoMessages
};

pub const Telezig = struct {
    allocator: std.mem.Allocator,
    token: []const u8,

    pub fn init(allocator: std.mem.Allocator, tokenPath: []const u8) !Telezig {
        const token = try getToken(allocator, tokenPath);
        return Telezig { .allocator = allocator, .token = token  };        
    }

    pub fn deinit(self: *Telezig) void {
        self.allocator.free(self.token);
    }

    pub fn runEchoBot(self: Telezig, intervalSeconds: u64, onMessageReceived: fn (self: Telezig, update: Update) void) anyerror!void {
        var updateId: i64 = undefined;

        while (true) {
            // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            // defer arena.deinit();
            // const allocator = arena.allocator();

            defer std.time.sleep(intervalSeconds * std.time.ns_per_s);
            // std.log.err("Getting updates", .{});
            var update = try self.getUpdates();
            defer self.allocator.free(update.text);

            var newUpdateId = update.updateId;
            if (updateId == newUpdateId) {
                continue;
            }

            updateId = newUpdateId;
            //try sendMessage(allocator, client, token, update);
            onMessageReceived(self, update);
            //break;
        }
    }

    fn getToken(allocator: std.mem.Allocator, tokenPath: []const u8) ![]u8 {
        const file = try std.fs.cwd().openFile(
            tokenPath,
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
        const formattedPath = try std.fmt.allocPrint(self.allocator, path, .{ self.token });
        defer self.allocator.free(formattedPath);

        var response = try request.makeGetRequestAlloc(self.allocator, host, formattedPath);
        //defer self.allocator.free(response);

        // std.log.err("Response is: {s}", .{response});

        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = try parser.parse(response);
        defer tree.deinit();
        
        var result = tree.root.Object.get("result").?.Array;
        defer result.deinit();

        if (result.items.len < 1) {
            return GetUpdatesError.NoMessages;
        }

        var lastIndex = result.items.len - 1;
        var updateId = result.items[0].Object.get("update_id").?.Integer;
        var message = result.items[lastIndex].Object.get("message").?;
        var text = message.Object.get("text").?.String;
        defer self.allocator.free(text);
        var chat = message.Object.get("chat").?;
        var chatId = chat.Object.get("id").?;

        return Update{
            .updateId = updateId,
            .chatId = chatId.Integer,
            .text = try self.allocator.dupe(u8, text),
        };
    }

    pub fn sendMessage(self: Telezig, update: Update) !void {
        const host = "api.telegram.org";
        const path = "/bot{s}" ++ "/sendMessage";
        const formattedPath = try std.fmt.allocPrint(self.allocator, path, .{ self.token });
        defer self.allocator.free(formattedPath);

        const rawJson = \\ {{ "chat_id": {d}, "text": "{s}" }}
        ;

        const echoResponseJsonString = try std.fmt.allocPrint(self.allocator, rawJson, .{ update.chatId, update.text });
        const echoComplete = try std.fmt.allocPrint(self.allocator, "{s}", .{echoResponseJsonString});
        defer self.allocator.free(echoResponseJsonString);
        defer self.allocator.free(echoComplete);

        //var headers = .{.{ "Content-Type", "application/json" }};

        // std.log.err("\n echoComplete: {s}\n", .{echoComplete});

        var response = try request.makePostRequestAlloc(self.allocator, host, formattedPath, echoComplete, "Content-Type: application/json");
        // var response1 = try self.client.post(sendMessageUrl, .{ .content = echoComplete, .headers = headers });
        defer self.allocator.free(response);

        // std.log.info("\n{s}\n", .{response});
    }
};

//Test function, do not use for library
fn onMessageReceived1(telezig: Telezig, update: Update) void { 
    telezig.sendMessage(.{ .updateId = update.updateId, .chatId = update.chatId, .text = update.text }) catch unreachable;
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

// export fn add(a: i32, b: i32) i32 {
//     return a + b;
// }

// test "basic add functionality" {
//     try testing.expect(add(3, 7) == 10);
// }
