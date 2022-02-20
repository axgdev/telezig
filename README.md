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

- Write a callback function
```zig
fn onMessageReceived(telezig: Telezig, update: Update) void {
    telezig.sendMessage(.{ .update_id = update.update_id, .chat_id = update.chat_id, .text = update.text }) catch unreachable;
}
```

- Write the loop runner
```zig
test "Echobot test" {
    var allocator = std.testing.allocator;
    //Make sure that the token.txt containts the telegram bot token you want to use
    var telezig = try Telezig.init(allocator, "token.txt");
    //This next method will run the loop, it will block until killed
    try telezig.runEchoBot(10, onMessageReceived);
}
```
## Dependencies

- [iguanaTLS](https://github.com/alexnask/iguanaTLS)

## License

*telezig* is released under the [MIT License](https://choosealicense.com/licenses/mit/). 🎉🍻