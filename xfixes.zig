const std = @import("std");
const x = @import("x.zig");

pub const ExtOpcode = enum(u8) {
    query_version = 0,
    // change_save_set = 1,
    // select_selection_input = 2,
    // select_cursor_input = 3,
    // get_cursor_image = 4,
    // Version 2
    create_region = 5,
    // create_region_from_bitmap = 6,
    create_region_from_window = 7,
    // create_region_from_gc = 8,
    create_region_from_picture = 9,
    destroy_region = 10,
    set_region = 11,
    // copy_region = 12,
    union_region = 13,
    intersect_region = 14,
    // subtract_region = 15,
    // invert_region = 16,
    // translate_region = 17,
    // region_extents = 18,
    // fetch_region = 19,
    // set_gc_clip_region = 20,
    // set_window_shape_region = 21,
    set_picture_clip_region = 22,
    // set_cursor_name = 23,
    // get_cursor_name = 24,
    // get_cursor_image_and_name = 25,
    // change_cursor = 26,
    // change_cursor_by_name = 27,
    // Version 3
    // expand_region = 28,
    // Version 4
    hide_cursor = 29,
    show_cursor = 30,
    // Version 5
    // create_pointer_barrier = 31,
    // delete_pointer_barrier = 32,
    // Version 6
    // set_client_disconnect_mode = 33,
    // get_client_disconnect_mode = 34,
};


pub const query_version = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // wanted major version
        + 4 // wanted minor version
        ;
    pub const Args = struct {
        ext_opcode: u8,
        wanted_major_version: u32,
        wanted_minor_version: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.query_version);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.wanted_major_version);
        x.writeIntNative(u32, buf + 8, args.wanted_minor_version);
    }

    pub const Reply = extern struct {
        response_type: x.ReplyKind,
        unused_pad: u8,
        sequence: u16,
        word_len: u32, // length in 4-byte words
        major_version: u32,
        minor_version: u32,
        unused_pad2: [16]u8,
    };
    comptime { std.debug.assert(@sizeOf(Reply) == 32); }
};

pub const create_region = struct {
    pub const non_list_len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // region_id
        ;
    pub fn getLen(rectangle_count: u16) u16 {
        return non_list_len + (rectangle_count * @sizeOf(x.Rectangle));
    }
    pub const Args = struct {
        ext_opcode: u8,
        region_id: u32,
        rectangles: []const x.Rectangle
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.create_region);
        x.writeIntNative(u32, buf + 4, args.damage_id);
        var request_len: u16 = non_list_len;
        for (args.rectangles) |rectangle| {
            x.writeIntNative(i16, buf + request_len + 0, rectangle.x);
            x.writeIntNative(i16, buf + request_len + 2, rectangle.y);
            x.writeIntNative(u16, buf + request_len + 4, rectangle.width);
            x.writeIntNative(u16, buf + request_len + 6, rectangle.height);
            request_len += 8;
        }
        std.debug.assert((request_len & 0x3) == 0);
        x.writeIntNative(u16, buf + 2, request_len >> 2);
        std.debug.assert(getLen(@intCast(args.rectangles.len)) == request_len);
    }
};

pub const create_region_from_window = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // region_id
        + 8 // rectangle
        ;
    pub const Args = struct {
        ext_opcode: u8,
        region_id: u32,
        window_id: u32,
        kind: x.shape.Kind,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.create_region_from_window);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.region_id);
        x.writeIntNative(u32, buf + 8, args.window_id);
        buf[12] = @intFromEnum(args.kind);
        buf[13] = 0; // unused
        buf[14] = 0; // unused
        buf[15] = 0; // unused
    }
};

pub const create_region_from_picture = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // region_id
        + 4 // picture_id
        ;
    pub const Args = struct {
        ext_opcode: u8,
        region_id: u32,
        picture_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.create_region_from_picture);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.region_id);
        x.writeIntNative(u32, buf + 8, args.picture_id);
    }
};

pub const destroy_region = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // region_id
        ;
    pub const Args = struct {
        ext_opcode: u8,
        region_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.destroy_region);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.region_id);
    }
};

pub const set_region = struct {
    pub const non_list_len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // region_id
        ;
    pub fn getLen(rectangle_count: u16) u16 {
        return non_list_len + (rectangle_count * @sizeOf(x.Rectangle));
    }
    pub const Args = struct {
        ext_opcode: u8,
        region_id: u32,
        rectangles: []const x.Rectangle
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.set_region);
        x.writeIntNative(u32, buf + 4, args.region_id);
        var request_len: u16 = non_list_len;
        for (args.rectangles) |rectangle| {
            x.writeIntNative(i16, buf + request_len + 0, rectangle.x);
            x.writeIntNative(i16, buf + request_len + 2, rectangle.y);
            x.writeIntNative(u16, buf + request_len + 4, rectangle.width);
            x.writeIntNative(u16, buf + request_len + 6, rectangle.height);
            request_len += 8;
        }
        std.debug.assert((request_len & 0x3) == 0);
        x.writeIntNative(u16, buf + 2, request_len >> 2);
        std.debug.assert(getLen(@intCast(args.rectangles.len)) == request_len);
    }
};

pub const union_region = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // source1 region
        + 4 // source2 region
        + 4 // destination region
        ;
    pub const Args = struct {
        ext_opcode: u8,
        source_region1: u32,
        source_region2: u32,
        destination_region: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.union_region);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.source_region1);
        x.writeIntNative(u32, buf + 8, args.source_region2);
        x.writeIntNative(u32, buf + 12, args.destination_region);
    }
};

pub const intersect_region = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // source1 region
        + 4 // source2 region
        + 4 // destination region
        ;
    pub const Args = struct {
        ext_opcode: u8,
        source_region1: u32,
        source_region2: u32,
        destination_region: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.intersect_region);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.source_region1);
        x.writeIntNative(u32, buf + 8, args.source_region2);
        x.writeIntNative(u32, buf + 12, args.destination_region);
    }
};

pub const set_picture_clip_region = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // picture
        + 4 // region
        + 2 // x_origin
        + 2 // y_origin
        ;
    pub const Args = struct {
        ext_opcode: u8,
        picture_id: u32,
        region_id: u32,
        x_origin: i16,
        y_origin: i16,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.set_picture_clip_region);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.picture_id);
        x.writeIntNative(u32, buf + 8, args.region_id);
        x.writeIntNative(u32, buf + 10, args.x_origin);
        x.writeIntNative(u32, buf + 12, args.y_origin);
    }
};

/// A client sends this request to indicate that it wants the cursor image to be hidden
/// (i.e. to not be displayed) when the sprite is inside the specified window, or one of
/// its subwindows.
pub const hide_cursor = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // window_id
        ;
    pub const Args = struct {
        ext_opcode: u8,
        window_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.hide_cursor);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.window_id);
    }
};

/// A client sends this request to indicate that it wants the cursor image to be
/// displayed when the sprite is inside the specified window, or one of its subwindows.
pub const show_cursor = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // window_id
        ;
    pub const Args = struct {
        ext_opcode: u8,
        window_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.show_cursor);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.window_id);
    }
};
