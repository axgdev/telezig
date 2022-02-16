const std = @import("std");
const testing = std.testing;

const Client = @import("requestz").Client;

pub const Update = struct {
    updateId: i64,
    chatId: i64,
    text: []const u8,
};

pub const GetUpdatesError = error{
    NoMessages
};

//Get the token from the user
//Get the loop time (interval)
//Callback function


// const TelezigCallback = struct {
//     allocator: std.mem.Allocator

//     pub fn onMessage(text: []const u8) void {
//         std.debug.print(text);
//     }
// }

pub const Telezig = struct {
    allocator: std.mem.Allocator,
    client: Client,
    token: []const u8,

    pub fn init(allocator: std.mem.Allocator, tokenPath: []const u8) !Telezig {
        const client = try Client.init(allocator);
        const token = try getToken(allocator, tokenPath);
        return Telezig { .allocator = allocator, .client = client, .token = token  };        
    }

    pub fn deinit(self: Telezig) void {
        self.client.deinit();
        self.allocator.free(self.token);
    }

    pub fn runEchoBot(self: Telezig, intervalSeconds: u64, callback: fn (self: Telezig, update: Update) void) anyerror!void {
        var updateId: i64 = undefined;

        while (true) {
            // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            // defer arena.deinit();
            // const allocator = arena.allocator();

            defer std.time.sleep(intervalSeconds * std.time.ns_per_s);
            var update = try self.getUpdates();
            defer self.allocator.free(update.text);

            var newUpdateId = update.updateId;
            if (updateId == newUpdateId) {
                continue;
            }

            updateId = newUpdateId;
            //try sendMessage(allocator, client, token, update);
            callback(self, update);
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
        const methodName = "getUpdates?offset=-1";
        const telegramUrlTemplate = "https://api.telegram.org/bot{s}/" ++ methodName;
        const telegramUrl = try std.fmt.allocPrint(self.allocator, telegramUrlTemplate, .{ self.token });
        defer self.allocator.free(telegramUrl);

        var response = try self.client.get(telegramUrl, .{});

        var tree = try response.json();
        defer tree.deinit();
        
        var result = tree.root.Object.get("result").?;

        if (result.Array.items.len < 1) {
            return GetUpdatesError.NoMessages;
        }

        var lastIndex = result.Array.items.len - 1;
        var updateId = result.Array.items[0].Object.get("update_id").?.Integer;
        var message = result.Array.items[lastIndex].Object.get("message").?;
        var text = message.Object.get("text").?;
        var chat = message.Object.get("chat").?;
        var chatId = chat.Object.get("id").?;

        return Update{
            .updateId = updateId,
            .chatId = chatId.Integer,
            .text = try self.allocator.dupe(u8, text.String),
        };
    }

    pub fn sendMessage(self: Telezig, update: Update) !void {
        const messageMethod = "sendMessage";
        const sendMessageUrlTemplate = "https://api.telegram.org/bot{s}/" ++ messageMethod;
        const sendMessageUrl = try std.fmt.allocPrint(self.allocator, sendMessageUrlTemplate, .{ self.token });
        defer self.allocator.free(sendMessageUrl);

        const rawJson = \\ {{ "chat_id": {d}, "text": "{s}" }}
        ;

        const echoResponseJsonString = try std.fmt.allocPrint(self.allocator, rawJson, .{ update.chatId, update.text });
        const echoComplete = try std.fmt.allocPrint(self.allocator, "{s}", .{echoResponseJsonString});
        defer self.allocator.free(echoResponseJsonString);
        defer self.allocator.free(echoComplete);

        var headers = .{.{ "Content-Type", "application/json" }};

        std.debug.print("\n echoComplete: {s}\n", .{echoComplete});

        var response1 = try self.client.post(sendMessageUrl, .{ .content = echoComplete, .headers = headers });
        defer response1.deinit();

        std.debug.print("\n{s}\n", .{response1.body});
    }
};

// export fn add(a: i32, b: i32) i32 {
//     return a + b;
// }

// test "basic add functionality" {
//     try testing.expect(add(3, 7) == 10);
// }
