const std = @import("std");
const network = @import("network");
const hzzp = @import("hzzp");

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;

    try network.init();
    defer network.deinit();

    var server = try network.Socket.create(.ipv4, .tcp);
    defer server.close();

    try server.bind(.{
        .address = .{ .ipv4 = network.Address.IPv4.any },
        .port = 8080,
    });

    try server.listen();
    std.log.info("listening at {}\n", .{try server.getLocalEndPoint()});
    while (true) {
        //std.debug.print("Waiting for connection\n", .{});
        const client = try allocator.create(Client);
        client.* = Client{
            .allocator = allocator,
            .conn = try server.accept(),
            .handle_frame = async client.handle(),
        };
    }
}

const Client = struct {
    allocator: std.mem.Allocator,
    conn: network.Socket,
    handle_frame: @Frame(Client.handle),

    fn handle(self: *Client) !void {
        defer self.conn.close();
        var buf: [8192]u8 = undefined;
        var reader = self.conn.reader();
        var parser = hzzp.parser.request.create(&buf, reader);
        while (true) {
            var close = true;
            var payload: []const u8 = undefined;
            var status: hzzp.parser.request.StatusEvent = undefined;
            while (true) {
                var actual = try parser.next();
                if (actual == null) {
                    break;
                }
                switch (actual.?) {
                    .header => |v| {
                        if (std.ascii.eqlIgnoreCase(v.name, "Connection") and
                            std.ascii.eqlIgnoreCase(v.value, "keep-alive"))
                        {
                            close = false;
                        }
                    },
                    .status => |v| {
                        status = v;
                    },
                    .payload => |_| {
                        //payload = v;
                    },
                    else => {},
                }
            }
            payload =
                "HTTP/1.1 200 OK\r\n" ++
                "Connection: keepalive\r\n" ++
                "Content-Length: 13\r\n" ++
                "\r\n" ++
                "Hello World\r\n";
            _ = try self.conn.send(payload);
            if (close) break;
        }
    }
};
