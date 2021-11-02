// Protocol Specification: https://www.x.org/docs/XProtocol/proto.pdf
//
// Request format
// -------------------------
// size | offset | description
// -------------------------
//  1   |    0   | major opcode
//  2   |    1   | total request length (including this header)
//  1   |    3   | data?
//
// Major Opcodes (128 - 255 reserved for extensions)
//
// Every request is implicitly assigned a sequence number, starting with 1, that is used in replies, errors and events
//
//
// Reply Format
// -------------------------
// size | offset | description
// -------------------------
//  4   |    0   | length not including first 32 bytes
//  2   |    4   | sequence number
//
//
// Event Format
// ...todo...
//

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const os = std.os;

const zog = @import("zog");

pub const TcpBasePort = 6000;

pub const BigEndian = 'B';
pub const LittleEndian = 'l';

// TODO: is there another way to do this, is this somewhere in std?
pub fn optEql(optLeft: anytype, optRight: anytype) bool {
    if (optLeft) |left| {
        if (optRight) |right| {
            return left == right;
        } else return false;
    } else {
        if (optRight) |_| {
            return false;
        } else return true;
    }
}

const ParsedDisplay = struct {
    protoLen: u16, // if not specified, then hostIndex will be 0 causing this to be empty
    hostLimit: u16,
    display_num: u32, // TODO: is there a maximum display number?
    preferredScreen: ?u32,

    pub fn protoSlice(self: @This(), ptr: [*]const u8) []const u8 {
        return ptr[0..self.protoLen];
    }
    fn hostIndex(self: @This()) u16 {
        return if (self.protoLen == 0) 0 else (self.protoLen + 1);
    }
    pub fn hostSlice(self: @This(), ptr: [*]const u8) []const u8 {
        return ptr[self.hostIndex()..self.hostLimit];
    }
    pub fn equals(self: @This(), other: @This()) bool {
        return self.protoLen == other.protoLen
            and self.hostLimit == other.hostLimit
            and self.display_num == other.display_num
            and optEql(self.preferredScreen, other.preferredScreen);
    }
};

// I think I can get away without an allocator here and without
// freeing it and without error.
pub fn getDisplay() []const u8 {
    return std.os.getenv("DISPLAY") orelse ":0";
}

// Return: display if set, otherwise the environment variable DISPLAY
//pub fn getDisplay(display: anytype) @TypeOf(display) {
//    if (display.length == 0) {
//        const env = std.os.getenv("DISPLAY");
//        if (@TypeOf(display) == []const u8)
//            return env else "";
//        @compileError("display string type not implemented");
//    }
//}


pub const ParseDisplayError = error {
    EmptyDisplay, // TODO: is this an error?
    MultipleProtocols,
    EmptyProtocol,
    DisplayStringTooLarge,
    NoDisplayNumber,
    BadDisplayNumber,
    BadScreenNumber,
};

// display format: [PROTOCOL/]HOST:DISPLAYNUM[.SCREEN]
// assumption: display.len > 0
pub fn parseDisplay(display: []const u8) ParseDisplayError!ParsedDisplay {
    if (display.len == 0) return ParseDisplayError.EmptyDisplay;
    if (display.len >= std.math.maxInt(u16))
            return ParseDisplayError.DisplayStringTooLarge;

    var parsed : ParsedDisplay = .{
        .protoLen = 0,
        .hostLimit = undefined,
        .display_num = undefined,
        .preferredScreen = undefined,
    };
    var index : u16 = 0;

    // TODO: if launchd supported, check for <path to socket>[.<screen>]

    while (true) {
        const c = display[index];
        if (c == ':') {
            break;
        }
        if (c == '/') {
            if (parsed.protoLen > 0)
                return ParseDisplayError.MultipleProtocols;
            if (index == 0)
                return ParseDisplayError.EmptyProtocol;
            parsed.protoLen = index;
        }
        index += 1;
        if (index == display.len)
            return ParseDisplayError.NoDisplayNumber;
    }

    parsed.hostLimit = index;
    index += 1;
    if (index == display.len)
        return ParseDisplayError.NoDisplayNumber;

    while (true) {
        const c = display[index];
        if (c == '.')
            break;
        index += 1;
        if (index == display.len)
            break;
    }

    //std.debug.warn("num '{}'\n", .{display[parsed.hostLimit + 1..index]});
    parsed.display_num = std.fmt.parseInt(u32, display[parsed.hostLimit + 1..index], 10) catch
        return ParseDisplayError.BadDisplayNumber;
    if (index == display.len) {
        parsed.preferredScreen = null;
    } else {
        index += 1;
        parsed.preferredScreen = std.fmt.parseInt(u32, display[index..], 10) catch
            return ParseDisplayError.BadScreenNumber;
    }
    return parsed;
}

fn testParseDisplay(display: []const u8, proto: []const u8, host: []const u8, display_num: u32, screen: ?u32) !void {
    const parsed = try parseDisplay(display);
    try testing.expect(std.mem.eql(u8, proto, parsed.protoSlice(display.ptr)));
    try testing.expect(std.mem.eql(u8, host, parsed.hostSlice(display.ptr)));
    try testing.expectEqual(display_num, parsed.display_num);
    try testing.expectEqual(screen, parsed.preferredScreen);
}

test "parseDisplay" {
    // no need to test the empty string case, it triggers an assert and a client passing
    // one is a bug that needs to be fixed
    try testing.expectError(ParseDisplayError.EmptyProtocol, parseDisplay("/"));
    try testing.expectError(ParseDisplayError.MultipleProtocols, parseDisplay("a//"));
    try testing.expectError(ParseDisplayError.NoDisplayNumber, parseDisplay("0"));
    try testing.expectError(ParseDisplayError.NoDisplayNumber, parseDisplay("0/"));
    try testing.expectError(ParseDisplayError.NoDisplayNumber, parseDisplay("0/1"));
    try testing.expectError(ParseDisplayError.NoDisplayNumber, parseDisplay(":"));

    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":a"));
    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":0a"));
    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":0a."));
    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":0a.0"));
    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":1x"));
    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":1x."));
    try testing.expectError(ParseDisplayError.BadDisplayNumber, parseDisplay(":1x.10"));

    try testing.expectError(ParseDisplayError.BadScreenNumber, parseDisplay(":1.x"));
    try testing.expectError(ParseDisplayError.BadScreenNumber, parseDisplay(":1.0x"));
    // TODO: should this be an error or no????
    //try testing.expectError(ParseDisplayError.BadScreenNumber, parseDisplay(":1."));

    try testParseDisplay("proto/host:123.456", "proto", "host", 123, 456);
    try testParseDisplay("host:123.456", "", "host", 123, 456);
    try testParseDisplay(":123.456", "", "", 123, 456);
    try testParseDisplay(":123", "", "", 123, null);
    try testParseDisplay("a/:43", "a", "", 43, null);
}

const ConnectError = error {
    UnsupportedProtocol,
};

pub fn isUnixProtocol(optionalProtocol: ?[]const u8) bool {
    if (optionalProtocol) |protocol| {
        return std.mem.eql(u8, "unix", protocol);
    }
    return false;
}

// The application should probably have access to the DISPLAY
// for logging purposes.  This might be too much abstraction.
//pub fn connect() !std.os.socket_t {
//    const display = std.os.getenv("DISPLAY") orelse
//        return connectExplicit(null, null, 0);
//    return connectDisplay(display);
//}

//pub const ConnectDisplayError = ParseDisplayError;
pub fn connect(display: []const u8) !std.os.socket_t {
    const parsed = try parseDisplay(display);
    const optional_host: ?[]const u8 = blk: {
        const host_slice = parsed.hostSlice(display.ptr);
        break :blk if (host_slice.len == 0) null else host_slice;
    };
    const optional_proto: ?[]const u8 = blk: {
        const proto_slice = parsed.protoSlice(display.ptr);
        break :blk if (proto_slice.len == 0) null else proto_slice;
    };
    return connectExplicit(optional_host, optional_proto, parsed.display_num);
}

//pub const ConnectExplicitError = error{ DisplayNumberOutOfRange };
pub fn connectExplicit(optionalHost: ?[]const u8, optionalProtocol: ?[]const u8, display_num: u32) !std.os.socket_t {
    if (optionalHost) |host| {
        if (!std.mem.eql(u8, host, "unix") and !isUnixProtocol(optionalProtocol)) {
            const port = TcpBasePort + display_num;
            if (port > std.math.maxInt(u16))
                return error.DisplayNumberOutOfRange;
            return connectTcp(host, optionalProtocol, @intCast(u16, port));
        }
    }
    return error.NoHostNotImplemented;
}

pub fn connectTcp(optionalHost: ?[]const u8, optionalProtocol: ?[]const u8, port: u16) !std.os.socket_t {
    var forceIpv6 = false;
    if (optionalProtocol) |protocol| {
        if (std.mem.eql(u8, protocol, "tcp")) { }
        else if (std.mem.eql(u8, protocol, "inet")) { }
        else if (std.mem.eql(u8, protocol, "inet6")) {
            forceIpv6 = true;
        } else {
            return ConnectError.UnsupportedProtocol;
        }
    }
    const host = if (optionalHost) |host| host else "localhost";
    return try tcpConnectToHost(host, port);
}

pub fn tcpConnectToHost(name: []const u8, port: u16) !std.os.socket_t {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const list = try std.net.getAddressList(&arena.allocator, name, port);
    defer list.deinit();
    for (list.addrs) |addr| {
        return tcpConnectToAddress(addr) catch |err| switch (err) {
            error.ConnectionRefused => {
                continue;
            },
            else => return err,
        };
    }
    if (list.addrs.len == 0) return error.UnknownHostName;
    return std.os.ConnectError.ConnectionRefused;
}

pub fn tcpConnectToAddress(address: std.net.Address) !std.os.socket_t {
    const nonblock = if (std.io.is_async) os.SOCK.NONBLOCK else 0;
    const sock_flags = os.SOCK.STREAM | nonblock |
        (if (builtin.os.tag == .windows) 0 else os.SOCK.CLOEXEC);
    const sockfd = try os.socket(address.any.family, sock_flags, os.IPPROTO.TCP);
    errdefer os.closeSocket(sockfd);

    if (std.io.is_async) {
        const loop = std.event.Loop.instance orelse return error.WouldBlock;
        try loop.connect(sockfd, &address.any, address.getOsSockLen());
    } else {
        try os.connect(sockfd, &address.any, address.getOsSockLen());
    }

    return sockfd;
}

pub fn disconnect(sock: std.os.socket_t) void {
    std.os.shutdown(sock, .both) catch {}; // ignore any error here
    std.os.close(sock);
}


//pub const ClientHello = packed struct {
//    byte_order : u8 = if (builtin.endian == .Big) BigEndian else LittleEndian,
//    proto_major_version : u16,
//    proto_minor_version : u16,
//};

pub fn Slice(comptime LenType: type, comptime Ptr: type) type { return struct {
    ptr: Ptr,
    len: LenType,
};}

pub fn ArrayPointer(comptime T: type) type {
    const err = "ArrayPointer not implemented for " ++ @typeName(T);
    switch (@typeInfo(T)) {
        .Pointer => |info| {
            switch (info.size) {
                .One => {
                    switch (@typeInfo(info.child)) {
                        .Array => |array_info| {
                            return @Type(std.builtin.TypeInfo { .Pointer = .{
                                .size = .Many,
                                .is_const = true,
                                .is_volatile = false,
                                .alignment = @alignOf(array_info.child),
                                .address_space = info.address_space,
                                .child = array_info.child,
                                .is_allowzero = false,
                                .sentinel = array_info.sentinel,
                            }});
                        },
                        else => @compileError("here"),
                    }
                },
                .Slice => {
                    return @Type(std.builtin.TypeInfo { .Pointer = .{
                        .size = .Many,
                        .is_const = info.is_const,
                        .is_volatile = info.is_volatile,
                        .alignment = info.alignment,
                        .address_space = info.address_space,
                        .child = info.child,
                        .is_allowzero = info.is_allowzero,
                        .sentinel = info.sentinel,
                    }});
                },
                else => @compileError(err),
            }
        },
        else => @compileError(err),
    }
}

pub fn slice(comptime LenType: type, s: anytype) Slice(LenType, ArrayPointer(@TypeOf(s)))  {
    switch (@typeInfo(@TypeOf(s))) {
        .Pointer => |info| {
            switch (info.size) {
                .One => {
                    switch (@typeInfo(info.child)) {
                        .Array => |array_info| {
                            _ = array_info;
                            @compileError("here");
//                            return @Type(std.builtin.TypeInfo { .Pointer = .{
//                                .size = .Many,
//                                .is_const = true,
//                                .is_volatile = false,
//                                .alignment = @alignOf(array_info.child),
//                                .child = array_info.child,
//                                .is_allowzero = false,
//                                .sentinel = array_info.sentinel,
//                            }});
                        },
                        else => @compileError("here"),
                    }
                },
                .Slice => return .{ .ptr = s.ptr, .len = @intCast(LenType, s.len) },
                else => @compileError("cannot slice"),
            }
        },
        else => @compileError("cannot slice"),
    }
}


// returns the number of padding bytes to add to `value` to get to a multiple of 4
// TODO: profile this? is % operator expensive?
// NOTE: using std.mem.alignForward instead
//fn pad4(comptime T: type, value: T) T {
//    return (4 - (value % 4)) % 4;
//}

pub const connect_setup = struct {
    pub fn getLen(auth_proto_name_len: u16, auth_proto_data_len: u16) u16 {
        return
              1 // byte-order
            + 1 // unused
            + 2 // proto_major_ver
            + 2 // proto_minor_ver
            + 2 // auth_proto_name_len
            + 2 // auth_proto_data_len
            + 2 // unused
            //+ auth_proto_name_len
            //+ pad4(u16, auth_proto_name_len)
            + @intCast(u16, std.mem.alignForward(auth_proto_name_len, 4))
            //+ auth_proto_data_len
            //+ pad4(u16, auth_proto_data_len)
            + @intCast(u16, std.mem.alignForward(auth_proto_data_len, 4))
            ;
    }
    pub fn serialize(buf: [*]u8, proto_major_ver: u16, proto_minor_ver: u16, auth_proto_name: Slice(u16, [*]const u8), auth_proto_data: Slice(u16, [*]const u8)) void {
        buf[0] = @as(u8, if (builtin.target.cpu.arch.endian() == .Big) BigEndian else LittleEndian);
        buf[1] = 0; // unused
        writeIntNative(u16, buf + 2, proto_major_ver);
        writeIntNative(u16, buf + 4, proto_minor_ver);
        writeIntNative(u16, buf + 6, auth_proto_name.len);
        writeIntNative(u16, buf + 8, auth_proto_data.len);
        writeIntNative(u16, buf + 10, 0); // unused
        @memcpy(buf + 12, auth_proto_name.ptr, auth_proto_name.len);
        //const off = 12 + pad4(u16, auth_proto_name.len);
        const off : u16 = 12 + @intCast(u16, std.mem.alignForward(auth_proto_name.len, 4));
        @memcpy(buf + off, auth_proto_data.ptr, auth_proto_data.len);
        std.debug.assert(
            getLen(auth_proto_name.len, auth_proto_data.len) ==
            off + @intCast(u16, std.mem.alignForward(auth_proto_data.len, 4))
        );
    }
};

test "ConnectSetupMessage" {
    const auth_proto_name = slice(u16, @as([]const u8, "hello"));
    const auth_proto_data = slice(u16, @as([]const u8, "there"));
    const len = comptime connect_setup.getLen(auth_proto_name.len, auth_proto_data.len);
    var buf: [len]u8 = undefined;
    connect_setup.serialize(buf.ptr, 1, 1, auth_proto_name, auth_proto_data);
}

const opcode = struct {
    pub const create_window = 1;
    pub const map_window = 8;
};

pub const BitGravity = enum(u4) {
    forget = 0,
    north_west = 1,
    north = 2,
    north_east = 3,
    west = 4,
    center = 5,
    east = 6,
    south_west = 7,
    south = 8,
    south_east = 9,
    static = 10,
};
pub const WinGravity = enum(u4) {
    unmap = 0,
    north_west = 1,
    north = 2,
    north_east = 3,
    west = 4,
    center = 5,
    east = 6,
    south_west = 7,
    south = 8,
    south_east = 9,
    static = 10,
};

fn isDefaultValue(s: anytype, comptime field: std.builtin.TypeInfo.StructField) bool {
    const default_value = field.default_value orelse
        @compileError("isDefaultValue was called on field '" ++ field.name ++ "' which has no default value");

    switch (@typeInfo(field.field_type)) {
        .Optional => {
            comptime std.debug.assert(default_value == null); // we're assuming all Optionals default to null
            return @field(s, field.name) == null;
        },
        else => {
            return @field(s, field.name) == default_value;
        },
    }
}

pub const create_window = struct {
    pub const option_flag = struct {
        pub const bg_pixmap         : u32 = (1 <<  0);
        pub const bg_pixel          : u32 = (1 <<  1);
        pub const border_pixmap     : u32 = (1 <<  2);
        pub const border_pixel      : u32 = (1 <<  3);
        pub const bit_gravity       : u32 = (1 <<  4);
        pub const win_gravity       : u32 = (1 <<  5);
        pub const backing_store     : u32 = (1 <<  6);
        pub const backing_planes    : u32 = (1 <<  7);
        pub const backing_pixel     : u32 = (1 <<  8);
        pub const override_redirect : u32 = (1 <<  9);
        pub const save_under        : u32 = (1 << 10);
        pub const event_mask        : u32 = (1 << 11);
        pub const dont_propagate    : u32 = (1 << 12);
        pub const colormap          : u32 = (1 << 13);
        pub const cursor            : u32 = (1 << 14);
    };

    pub const non_option_len =
              2 // opcode and depth
            + 2 // request length
            + 4 // window id
            + 4 // parent window id
            + 10 // 2 bytes each for x, y, width, height and border-width
            + 2 // window class
            + 4 // visual id
            + 4 // window option mask
            ;
    pub const max_len = non_option_len + (14 * 4);  // 14 possible 4-byte options

    pub const Class = enum(u8) {
        copy_from_parent = 0,
        input_output = 1,
        input_only = 2,
    };
    pub const event_mask = struct {
        pub const key_press          = (1 <<  0);
        pub const key_release        = (1 <<  1);
        pub const button_press       = (1 <<  2);
        pub const button_release     = (1 <<  3);
        pub const enter_window       = (1 <<  4);
        pub const leave_window       = (1 <<  5);
        pub const pointer_motion     = (1 <<  6);
        pub const pointer_motion_hint= (1 <<  7);
        pub const button1_motion     = (1 <<  8);
        pub const button2_motion     = (1 <<  9);
        pub const button3_motion     = (1 << 10);
        pub const button4_motion     = (1 << 11);
        pub const button5_motion     = (1 << 12);
        pub const button_motion      = (1 << 13);
        pub const keymap_state       = (1 << 14);
        pub const exposure           = (1 << 15);
        pub const visibility_change  = (1 << 16);
        pub const structure_notify   = (1 << 17);
        pub const resize_redirect    = (1 << 18);
        pub const substructure_notify= (1 << 19);
        pub const substructure_redirect= (1 << 20);
        pub const focus_change       = (1 << 21);
        pub const property_change    = (1 << 22);
        pub const colormap_change    = (1 << 23);
        pub const owner_grab_button  = (1 << 24);
        pub const unused_mask: u32   = (0x7f << 25);
    };

    pub const Args = struct {
        window_id: u32,
        parent_window_id: u32,
        x: u16,
        y: u16,
        width: u16,
        height: u16,
        border_width: u16,
        class: Class,
        visual_id: u32,
    };
    pub const BgPixmap = enum(u32) { none = 0, copy_from_parent = 1 };
    pub const BorderPixmap = enum(u32) { copy_from_parent = 0 };
    pub const BackingStore = enum(u32) { not_useful = 0, when_mapped = 1, always = 2 };
    pub const Colormap = enum(u32) { copy_from_parent = 0 };
    pub const Cursor = enum(u32) { none = 0 };
    pub const Options = struct {
        bg_pixmap: BgPixmap = .none,
        bg_pixel: ?u32 = null,
        border_pixmap: BorderPixmap = .copy_from_parent,
        border_pixel: ?u32 = null,
        bit_gravity: BitGravity = .forget,
        win_gravity: WinGravity = .north_west,
        backing_store: BackingStore = .not_useful,
        backing_planes: u32 = 0xffffffff,
        backing_pixel: u32 = 0,
        override_redirect: bool = false,
        save_under: bool = false,
        event_mask: u32 = 0,
        dont_propagate: u32 = 0,
        colormap: Colormap = .copy_from_parent,
        cursor: Cursor = .none,
    };

    fn optionToU32(value: anytype) u32 {
        const T = @TypeOf(value);
        if (
               T == BgPixmap
            or T == BorderPixmap
            or T == BitGravity
            or T == WinGravity
            or T == BackingStore
            or T == Colormap
            or T == Cursor
        ) return @enumToInt(value);

        if (T == bool) return @boolToInt(value);
        if (T == u32) return value;
        if (T == ?u32) return value.?;

        @compileError("TODO: implement optionToU32 for type: " ++ @typeName(T));
    }

    pub fn serialize(buf: [*]u8, args: Args, options: Options) u16 {
        buf[0] = opcode.create_window;
        buf[1] = 0; // depth? what is this?

        // buf[2-3] is the len, set at the end of the function

        writeIntNative(u32, buf + 4, args.window_id);
        writeIntNative(u32, buf + 8, args.parent_window_id);
        writeIntNative(u16, buf + 12, args.x);
        writeIntNative(u16, buf + 14, args.y);
        writeIntNative(u16, buf + 16, args.width);
        writeIntNative(u16, buf + 18, args.height);
        writeIntNative(u16, buf + 20, args.border_width);
        writeIntNative(u16, buf + 22, @enumToInt(args.class));
        writeIntNative(u32, buf + 24, args.visual_id);

        var request_len: u16 = non_option_len;
        var option_mask: u32 = 0;

        inline for (std.meta.fields(Options)) |field| {
            if (!isDefaultValue(options, field)) {
                writeIntNative(u32, buf + request_len, optionToU32(@field(options, field.name)));
                option_mask |= @field(create_window.option_flag, field.name);
                request_len += 4;
            }
        }

        writeIntNative(u32, buf + 28, option_mask);
        std.debug.assert((request_len & 0x3) == 0);
        writeIntNative(u16, buf + 2, request_len >> 2);
        return request_len;
    }
};

pub const map_window = struct {
    pub const len = 8;
    pub fn serialize(buf: [*]u8, window_id: u32) void {
        buf[0] = opcode.map_window;
        buf[1] = 0; // unused
        writeIntNative(u16, buf + 2, len >> 2);
        writeIntNative(u32, buf + 4, window_id);
    }
};

pub fn writeIntNative(comptime T: type, buf: [*]u8, value: T) void {
    @ptrCast(*align(1) T, buf).* = value;
}
pub fn readIntNative(comptime T: type, buf: [*]const u8) T {
    return @ptrCast(*const align(1) T, buf).*;
}


pub fn recvFull(sock: std.os.socket_t, buf: []u8) !void {
    std.debug.assert(buf.len > 0);
    var total_received : usize = 0;
    while (true) {
        const last_received = try std.os.recv(sock, buf[total_received..], 0);
        if (last_received == 0)
            return error.ConnectionResetByPeer;
        total_received += last_received;
        if (total_received == buf.len)
            break;
    }
}

pub const EventKind = enum(u8) {
    key_press = 2,
    _,
};
// NOTE: can't used packed because of compiler bugs
pub const Event = extern union {
    generic: Generic,
    key_press: KeyOrButton,
    key_release: KeyOrButton,
    button_press: KeyOrButton,
    button_release: KeyOrButton,

    // NOTE: can't used packed because of compiler bugs
    pub const Generic = extern struct {
        code: EventCode,
        detail: u8,
        sequence: u16,
        data: [28]u8,
    };
    comptime { std.debug.assert(@sizeOf(Generic) == 32); }

    // NOTE: can't used packed because of compiler bugs
    pub const KeyOrButton = extern struct {
        code: u8,
        detail: u8,
        sequence: u16,
        time: u32,
        root: u32,
        event: u32,
        child: u32,
        root_x: i16,
        root_y: i16,
        event_x: i16,
        event_y: i16,
        state: u16,
        same_screen: u8,
        unused: u8,
    };
    comptime { std.debug.assert(@sizeOf(KeyOrButton) == 32); }
};
comptime { std.debug.assert(@sizeOf(Event) == 32); }


pub const ErrorCode = enum(u8) {
    request = 1,
    value = 2,
    window = 3,
    pixmap = 4,
    atom = 5,
    cursor = 6,
    font = 7,
    match = 8,
    drawable = 9,
    access = 10,
    alloc = 11,
    colormap = 12,
    gcontext = 13,
    id_choice = 14,
    name = 15,
    length = 16,
    implementation = 17,
    _, // allow unknown errors
};

// NOTE: can't used packed struct because of compiler bugs
pub const ErrorReply = extern struct {
    reponse_type: u8, // should be 0
    code: ErrorCode,
    sequence: u16,
    data: [28]u8,
};
comptime { std.debug.assert(@sizeOf(ErrorReply) == 32); }

// NOTE: can't used packed struct because of compiler bugs
pub const ErrorReplyLength = extern struct {
    reponse_type: u8, // should be 0
    code: ErrorCode, // should be .length
    sequence: u16,
    unused1: u32,
    minor_opcode: u16,
    major_opcode: u8,
    unused2: [21]u8,
};
comptime { std.debug.assert(@sizeOf(ErrorReplyLength) == 32); }

pub const EventCode = enum(u8) {
    key_press = 2,
    key_release = 3,
    button_press = 4,
    button_release = 5,
    motion_notify = 6,
    enter_notify = 7,
    leave_notify = 8,
    focus_in = 9,
    focus_out = 10,
    keymap_notify = 11,
    expose = 12,
    graphics_exposure = 13,
    no_exposure = 14,
    visibility_notify = 15,
    create_notify = 16,
    destroy_notify = 17,
    unmap_notify = 18,
    map_notify = 19,
    map_request = 20,
    reparent_notify = 21,
    configure_notify = 22,
    configure_request = 23,
    gravity_notify = 24,
    resize_request = 25,
    circulate_notify = 26,
    ciculate_request = 27,
    property_notify = 28,
    selection_clear = 29,
    selection_request = 30,
    selection_notify = 31,
    colormap_notify = 32,
    client_message = 33,
    mapping_notify = 34,
};

pub const ReplyType = enum(u8) {
    err = 0,
    normal = 1,
    key_press         = @enumToInt(EventCode.key_press),
    key_release       = @enumToInt(EventCode.key_release),
    button_press      = @enumToInt(EventCode.button_press),
    button_release    = @enumToInt(EventCode.button_release),
    motion_notify     = @enumToInt(EventCode.motion_notify),
    enter_notify      = @enumToInt(EventCode.enter_notify),
    leave_notify      = @enumToInt(EventCode.leave_notify),
    focus_in          = @enumToInt(EventCode.focus_in),
    focus_out         = @enumToInt(EventCode.focus_out),
    keymap_notify     = @enumToInt(EventCode.keymap_notify),
    expose            = @enumToInt(EventCode.expose),
    graphics_exposure = @enumToInt(EventCode.graphics_exposure),
    no_exposure       = @enumToInt(EventCode.no_exposure),
    visibility_notify = @enumToInt(EventCode.visibility_notify),
    create_notify     = @enumToInt(EventCode.create_notify),
    destroy_notify    = @enumToInt(EventCode.destroy_notify),
    unmap_notify      = @enumToInt(EventCode.unmap_notify),
    map_notify        = @enumToInt(EventCode.map_notify),
    map_request       = @enumToInt(EventCode.map_request),
    reparent_notify   = @enumToInt(EventCode.reparent_notify),
    configure_notify  = @enumToInt(EventCode.configure_notify),
    configure_request = @enumToInt(EventCode.configure_request),
    gravity_notify    = @enumToInt(EventCode.gravity_notify),
    resize_request    = @enumToInt(EventCode.resize_request),
    circulate_notify  = @enumToInt(EventCode.circulate_notify),
    ciculate_request  = @enumToInt(EventCode.ciculate_request),
    property_notify   = @enumToInt(EventCode.property_notify),
    selection_clear   = @enumToInt(EventCode.selection_clear),
    selection_request = @enumToInt(EventCode.selection_request),
    selection_notify  = @enumToInt(EventCode.selection_notify),
    colormap_notify   = @enumToInt(EventCode.colormap_notify),
    client_message    = @enumToInt(EventCode.client_message),
    mapping_notify    = @enumToInt(EventCode.mapping_notify),
    _,
};

pub const ReplyReader = struct {
    buf: []align(4) u8, // NOTE: should never be smaller than 32 bytes
    offset: usize,
    limit: usize,

    fn consume(self: *ReplyReader, len: usize) void {
        self.offset += len;
        if (self.offset == self.limit) {
            self.offset = 0;
            self.limit = 0;
        } else std.debug.assert(self.offset < self.limit);
    }

    // on error.ParitalXMsg, buf will be completely filled with a partial message
    pub fn read(self: *ReplyReader, sock: std.os.socket_t) ![]u8 {
        std.debug.assert(self.buf.len >= 32);
        while (true) {
            if (self.limit >= self.offset + 32) {
                //switch (@intToEnum(ReplyType, self.buf[self.offset])) {
                switch (self.buf[self.offset]) {
                    @enumToInt(ReplyType.err) => {
                        const off = self.offset;
                        self.consume(32);
                        return self.buf[off .. off + 32];
                    },
                    @enumToInt(ReplyType.normal) => {
                        const full_len = 32 + (4 * readIntNative(u32, self.buf.ptr + self.offset + 4));
                        if (self.limit >= self.offset + full_len) {
                            const off = self.offset;
                            self.consume(full_len);
                            return self.buf[off .. off + full_len];
                        }
                    },
                    2 ... 63 => {
                    //.event => {
                        const off = self.offset;
                        self.consume(32);
                        return self.buf[off .. off + 32];
                    },
                    else => std.debug.panic("handle reply type {}", .{self.buf[self.offset]}),
                }
            }

            if (self.limit == self.buf.len)
                return error.PartialXMsg;

            if (self.offset > 0) {
                @panic("todo: move memory");
            }
            const last_received = try std.os.recv(sock, self.buf[self.limit..], 0);
            if (last_received == 0)
                return error.ConnectionResetByPeer;
            self.limit += last_received;
        }
    }
};

pub const Format = packed struct {
    depth: u8,
    bits_per_pixel: u8,
    scanline_pad: u8,
    // can't do [5]u8 because of https://github.com/ziglang/zig/issues/2627
    _: u8,
    __: [4]u8,
};
comptime { if (@sizeOf(Format) != 8) @compileError("Format size is wrong"); }

pub const Screen = packed struct {
    root: u32,
    colormap: u32,
    white_pixel: u32,
    black_pixel: u32,
    input_masks: u32,
    pixel_width: u16,
    pixel_height: u16,
    mm_width: u16,
    mm_height: u16,
    min_installed_maps: u16,
    max_installed_maps: u16,
    root_visual: u32,
    backing_stores: u8,
    save_unders: u8,
    root_depth: u8,
    allowed_depth_count: u8,
};

pub const ScreenDepth = packed struct {
    depth: u8,
    unused0: u8,
    visual_type_count: u16,
    unused1: u32,
};

pub const VisualType = packed struct {
    pub const Class = enum(u8) {
        static_gray = 0,
        gray_scale = 1,
        static_color = 2,
        psuedo_color = 3,
        true_color = 4,
        direct_color = 5,
    };

    id: u32,
    class: Class,
    bits_per_rgb_value: u8,
    colormap_entries: u16,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
    unused: u32,
};

pub fn readFull(reader: anytype, buf: []u8) (@TypeOf(reader).Error || error{EndOfStream})!void {
    std.debug.assert(buf.len > 0);
    var total_received : usize = 0;
    while (true) {
        const last_received = try reader.read(buf[total_received..]);
        if (last_received == 0)
            return error.EndOfStream;
        total_received += last_received;
        if (total_received == buf.len)
            break;
    }
}

pub const ReadConnectSetupHeaderOptions = struct {
    read_timeout_ms: i32 = -1,
};

pub fn readConnectSetupHeader(reader: anytype, options: ReadConnectSetupHeaderOptions) !ConnectSetup.Header {
    var header : ConnectSetup.Header = undefined;
    if (options.read_timeout_ms == -1) {
        try readFull(reader, header.asBuf());
        return header;
    }
    @panic("read timeout not implemented");
}

pub const FailReason = struct {
    buf: [256]u8,
    len: u8,
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        _ = fmt; _ = options;
        try writer.writeAll(self.buf[0 .. self.len]);
    }
};

pub const ConnectSetup = struct {
    // because X makes an effort to align things to 4-byte bounaries, we
    // should get some better codegen by ensuring that our buffer is aligned
    // to 4-bytes
    buf: []align(4) u8,

    pub fn deinit(self: ConnectSetup, allocator: *std.mem.Allocator) void {
        allocator.free(self.buf);
    }

    pub const Header = packed struct {
        pub const Status = enum(u8) {
            failed = 0,
            success = 1,
            authenticate = 2,
            _
        };

        status: Status,
        status_opt: u8, // length of 'reason' in Failed case
        proto_major_ver: u16,
        proto_minor_ver: u16,
        reply_u32_len: u16,

        pub fn asBuf(self: *@This()) []u8 {
            return @ptrCast([*]u8, self)[0..@sizeOf(@This())];
        }

        pub fn getReplyLen(self: @This()) u16 {
            return 4 * self.reply_u32_len;
        }

        pub fn readFailReason(self: @This(), reader: anytype) FailReason {
            var result: FailReason = undefined;
            result.len = @intCast(u8, reader.readAll(result.buf[0 .. self.status_opt]) catch |read_err|
                (std.fmt.bufPrint(&result.buf, "failed to read failure reason: {s}", .{@errorName(read_err)}) catch |err| switch (err) {
                    error.NoSpaceLeft => unreachable,
                }).len);
            return result;
        }
    };

    /// All the connect setup fields that are at fixed offsets
    pub const Fixed = packed struct {
        release_number: u32,
        resource_id_base: u32,
        resource_id_mask: u32,
        motion_buffer_size: u32,
        vendor_len: u16,
        max_request_len: u16,
        root_screen_count: u8,
        format_count: u8,
        image_byte_order: u8,
        bitmap_format_bit_order: u8,
        bitmap_format_scanline_unit: u8,
        bitmap_format_scanline_pad: u8,
        min_keycode: u8,
        max_keycode: u8,
        unused: u32,
    };
    pub fn fixed(self: @This()) *Fixed {
        return @ptrCast(*Fixed, self.buf.ptr);
    }

    pub const VendorOffset = 32;
    pub fn getVendorSlice(self: @This(), vendor_len: u16) ![]align(4) u8 {
        const vendor_limit = VendorOffset + vendor_len;
        if (vendor_limit > self.buf.len)
            return error.XMalformedReply_VendorLenTooBig;
        return self.buf[VendorOffset..vendor_limit];
    }

    pub fn getFormatListOffset(vendor_len: u16) u32 {
        return VendorOffset + @intCast(u32, std.mem.alignForward(vendor_len, 4));
    }
    pub fn getFormatListLimit(format_list_offset: u32, format_count: u32) u32 {
        return format_list_offset + (@sizeOf(Format) * format_count);
    }
    pub fn getFormatListPtr(self: @This(), format_list_offset: u32) [*]align(4) Format {
        return @ptrCast([*]align(4) Format, @alignCast(4, self.buf.ptr + format_list_offset));
    }
    pub fn getFormatList(self: @This(), format_list_offset: u32, format_list_limit: u32) ![]align(4) Format {
        if (format_list_limit > self.buf.len)
            return error.XMalformedReply_FormatCountTooBig;
        return self.getFormatListPtr(format_list_offset)[0..@divExact(format_list_limit - format_list_offset, @sizeOf(Format))];
    }

    pub fn getFirstScreenPtr(self: @This(), format_list_limit: u32) *align(4) Screen {
        return @ptrCast(*align(4) Screen, @alignCast(4, self.buf.ptr + format_list_limit));
    }
};