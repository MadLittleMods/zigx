const std = @import("std");

const x = @import("x.zig");

pub const ExtOpcode = enum(u8) {
    query_version = 0,
    rectangles = 1,
    // mask = 2,
    // combine = 3,
    // offset = 4,
    // query_extents = 5,
    // select_input = 6,
    // input_selected = 7,
    // get_rectangles = 8,
};

pub const Kind = enum(u8) {
    bounding = 0,
    clip = 1,
    input = 2,
};

pub const Operation = enum(u8) {
    set = 0,
    @"union" = 1,
    intersect = 2,
    subtract = 3,
    invert = 4,
};

pub const Ordering = enum(u8) {
    unsorted = 0,
    y_sorted = 1,
    yx_sorted = 1,
    yx_banded = 1,
};

pub const Rectangle = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const query_version = struct {
    pub const len =
              2 // extension and command opcodes
            + 2 // request length
            + 4 // client major version
            + 4 // client minor version
    ;
    pub const Args = struct {
        major_version: u32,
        minor_version: u32,
    };
    pub fn serialize(buf: [*]u8, ext_opcode: u8, args: Args) void {
        buf[0] = ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.query_version);
        std.debug.assert(len & 0x3 == 0);
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.major_version);
        x.writeIntNative(u32, buf + 8, args.minor_version);
    }
    pub const Reply = extern struct {
        response_type: x.ReplyKind,
        unused_pad: u8,
        sequence: u16,
        word_len: u32,
        major_version: u32,
        minor_version: u32,
        reserved: [15]u8,
    };
    comptime { std.debug.assert(@sizeOf(Reply) == 32); }
};


pub const rectangles = struct {
    pub const non_list_len =
              2 // extension and command opcodes
            + 2 // request length
            + 1 // operation
            + 1 // destination kind
            + 1 // ordering
            + 1 // unused
            + 4 // destination window
            + 2 // x offset
            + 2 // y offset
    ;
    pub fn getLen(number_of_rectangles: u16) u16 {
        return non_list_len + (8 * number_of_rectangles);
    }
    pub const Args = struct {
        destination_window_id: u32,
        destination_kind: Kind,
        operation: Operation,
        x_offset: i16,
        y_offset: i16,
        ordering: Ordering,
        rectangles: []const Rectangle,
    };
    pub fn serialize(buf: [*]u8, ext_opcode: u8, args: Args) void {
        buf[0] = ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.rectangles);
        const len = getLen(args.rectangles.len);
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u8, buf + 4, args.operation);
        x.writeIntNative(u8, buf + 5, args.destination_kind);
        x.writeIntNative(u8, buf + 6, args.destination_kind);
    }
};
