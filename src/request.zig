const std = @import("std");
const x509 = @import("iguanaTLS").x509;
const tls = @import("iguanaTLS");

const TypeOfRequest = enum { GET, POST, PUT, DELETE };

pub fn makeGetRequestAlloc(allocator: std.mem.Allocator, host: []const u8, path: []const u8) ![]const u8 {
    return makeRequestAlloc(allocator, host, path, "", "", .GET);
}

pub fn makePostRequestAlloc(allocator: std.mem.Allocator, host: []const u8, path: []const u8, body: []const u8, headers: []const u8) ![]const u8 {
    return makeRequestAlloc(allocator, host, path, body, headers, .POST);
}

fn makeRequestAlloc(allocator: std.mem.Allocator,
                        host: []const u8,
                        path: []const u8,
                        body: []const u8,
                        headers: []const u8,
                        typeOfRequest: TypeOfRequest) ![]const u8 {
    const sock = try std.net.tcpConnectToHost(allocator, host, 443);
    defer sock.close();

    var client = try tls.client_connect(.{
                    .reader = sock.reader(),
                    .writer = sock.writer(),
                    .cert_verifier = .none,
                    .temp_allocator = allocator,
                    .ciphersuites = tls.ciphersuites.all,
                    .protocols = &[_][]const u8{"http/1.1"},
                }, host);
    defer client.close_notify() catch {};
    try std.testing.expectEqualStrings("http/1.1", client.protocol);

    const typeOfRequestStr: []const u8 = switch (typeOfRequest) {
        .GET => "GET",
        .POST => "POST",
        .PUT => "PUT",
        .DELETE => "DELETE"
    };

    var content_length_request: []const u8 = "";
    if (body.len > 0) {
        content_length_request = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n", .{body.len});
    }
    defer allocator.free(content_length_request);
    try client.writer().print("{s} {s} HTTP/1.1\r\nHost: {s}\r\nAccept: */*\r\n{s}\r\n{s}\r\n{s}", 
                                .{typeOfRequestStr, path, host, headers, content_length_request, body});

    {
        const header = try client.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
        try std.testing.expectEqualStrings("HTTP/1.1 200 OK", std.mem.trim(u8, header, &std.ascii.spaces));
        allocator.free(header);
    }

    // Skip the rest of the headers except for Content-Length
    var content_length: ?usize = null;
    hdr_loop: while (true) {
        const header = try client.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
        defer allocator.free(header);

        const hdr_contents = std.mem.trim(u8, header, &std.ascii.spaces);
        if (hdr_contents.len == 0) {
            break :hdr_loop;
        }

        if (std.mem.startsWith(u8, hdr_contents, "Content-Length: ")) {
            content_length = try std.fmt.parseUnsigned(usize, hdr_contents[16..], 10);
        }
    }
    try std.testing.expect(content_length != null);
    const html_contents = try allocator.alloc(u8, content_length.?);

    try client.reader().readNoEof(html_contents);
    std.log.info("{s}", .{html_contents});
    return html_contents;
}

// test "basic test" {
//     try std.testing.expectEqual(10, 3 + 7);
// }
