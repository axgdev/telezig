# telezig
A telegram bot library written in Zig ⚡

[![License](https://img.shields.io/badge/license-MIT-green)](https://github.com/ducdetronquito/requestz#license)


## Installation

Install telezig using gyro

```
gyro add --src github axgdev/telezig
```

## Usage

Echo bot example:

- Load the bot token to pass it as a string to the library
```zig
fn getToken(token_path: []const u8, buffer: []u8) !void {
    const file = try std.fs.cwd().openFile(token_path, .{ .mode = .read_only });
    defer file.close();
    _ = try file.reader().read(buffer);
}
```

- Example of a echo bot loop
```zig
// windows-only startup
if (builtin.os.tag == std.Target.Os.Tag.windows) _ = try std.os.windows.WSAStartup(2, 0);

var allocator = std.testing.allocator;
var token: [46]u8 = undefined;
// Here we call the function above to load the token from a file,
// but you can decide to load it from an environment variable or any other way
try getToken("token.txt", token[0..]);
var bot = try Telezig.init(allocator, token[0..]);

var update_id: i64 = std.math.minInt(i64);
var sleep_seconds: u8 = 10;
// Here we run an infinite loop to get messages written to the bot and respond with the same text.
// The only way to stop it is to kill the app
while (true) {
    // Get the updates from the Telegram API
    var update = try bot.getUpdates();
    defer bot.allocator.free(update.text);

    // We only send an echo message if someone has sent any new message to the bot
    var new_update_id = update.update_id;
    if (update_id == new_update_id) continue;
    update_id = new_update_id;

    // Send the same message we received
    try bot.sendMessage(update);
    // Sleep some seconds to not make too many requests to the Telegram API
    std.time.sleep(sleep_seconds * std.time.ns_per_s);
}

// windows-only cleanup
if (builtin.os.tag == std.Target.Os.Tag.windows) try std.os.windows.WSACleanup();
```
## Dependencies

- [iguanaTLS](https://github.com/alexnask/iguanaTLS)

## License

*telezig* is released under the [MIT License](https://choosealicense.com/licenses/mit/). 🎉🍻
