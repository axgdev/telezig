const std = @import("std");
const testing = std.testing;

const Client = @import("requestz").Client;

const Update = struct {
    updateId: i64,
    chatId: i64,
    text: []const u8,
};

const GetUpdatesError = error{
    NoMessages
};

export fn runEchoBot() anyerror!void {
    var buffer: [94]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const token_allocator = fba.allocator();

    const token = try getToken(token_allocator);
    defer token_allocator.free(token);

    var updateId: i64 = undefined;

    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var client = try Client.init(allocator);
        defer client.deinit();

        defer std.time.sleep(1e+10);
        var update = try getUpdates(allocator, client, token);
        defer allocator.free(update.text);

        var newUpdateId = update.updateId;
        if (updateId == newUpdateId) {
            continue;
        }

        updateId = newUpdateId;
        try sendMessage(allocator, client, token, update);
    }
}

fn getToken(allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(
        "token.txt",
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

fn getUpdates(allocator: std.mem.Allocator, client: Client, token: []u8) !Update {
    const methodName = "getUpdates?offset=-1";
    const telegramUrlTemplate = "https://api.telegram.org/bot{s}/" ++ methodName;
    const telegramUrl = try std.fmt.allocPrint(allocator, telegramUrlTemplate, .{ token });

    var response = try client.get(telegramUrl, .{});

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
        .text = try allocator.dupe(u8, text.String),
    };
}

fn sendMessage(allocator: std.mem.Allocator, client: Client, token: []u8, update: Update) !void {
    const messageMethod = "sendMessage";
    const sendMessageUrlTemplate = "https://api.telegram.org/bot{s}/" ++ messageMethod;
    const sendMessageUrl = try std.fmt.allocPrint(allocator, sendMessageUrlTemplate, .{ token });

    const rawJson = \\ {{ "chat_id": {d}, "text": "{s}" }}
    ;

    const echoResponseJsonString = try std.fmt.allocPrint(allocator, rawJson, .{ update.chatId, update.text });
    const echoComplete = try std.fmt.allocPrint(allocator, "{s}", .{echoResponseJsonString});
    defer allocator.free(echoResponseJsonString);

    var headers = .{.{ "Content-Type", "application/json" }};

    std.debug.print("\n echoComplete: {s}\n", .{echoComplete});

    var response1 = try client.post(sendMessageUrl, .{ .content = echoComplete, .headers = headers });
    defer response1.deinit();

    std.debug.print("\n{s}\n", .{response1.body});
}

// export fn add(a: i32, b: i32) i32 {
//     return a + b;
// }

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
