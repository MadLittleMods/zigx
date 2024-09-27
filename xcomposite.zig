const std = @import("std");

const x = @import("x.zig");


pub const ExtOpcode = enum(u8) {
    query_version = 0,
    // redirect_window = 1,
    redirect_subwindows = 2,
    // undirect_window = 3,
    // undirect_subwindows = 4,
    // create_region_from_border_clip = 5,
    
    /// new in version 0.2
    name_window_pixmap = 6,

    /// new in version 0.3
    get_overlay_window = 7,
    release_overlay_window = 8,
};

pub const UpdateType = enum(u8) {
    automatic = 0,
    manual = 1,
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

pub const redirect_subwindows = struct {
    pub const len =
              2 // extension and command opcodes
            + 2 // request length
            + 4 // window_id
            + 1 // update type
            + 3 // unused pad
    ;
    pub const Args = struct {
        window_id: u32,
        update_type: UpdateType,
    };
    pub fn serialize(buf: [*]u8, ext_opcode: u8, args: Args) void {
        buf[0] = ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.redirect_subwindows);
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.window_id);
        x.writeIntNative(u8, buf + 8, @intFromEnum(args.update_type));
        buf[9] = 0; // unused
        buf[10] = 0; // unused
        buf[11] = 0; // unused
    }
};

pub const name_window_pixmap = struct {
    pub const len =
              2 // extension and command opcodes
            + 2 // request length
            + 4 // window_id
            + 4 // pixmap ID
    ;
    pub const Args = struct {
        window_id: u32,
        pixmap_id: u32,
    };
    pub fn serialize(buf: [*]u8, ext_opcode: u8, args: Args) void {
        buf[0] = ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.name_window_pixmap);
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.window_id);
        x.writeIntNative(u32, buf + 8, args.pixmap_id);
    }
};

pub const get_overlay_window = struct {
    pub const len =
              2 // extension and command opcodes
            + 2 // request length
            + 4 // window_id
    ;
    pub const Args = struct {
        window_id: u32,
    };
    pub fn serialize(buf: [*]u8, ext_opcode: u8, args: Args) void {
        buf[0] = ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.get_overlay_window);
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.window_id);
    }

    pub const Reply = extern struct {
        response_type: x.ReplyKind,
        unused_pad: u8,
        sequence: u16,
        word_len: u32, // length in 4-byte words
        overlay_window_id: u32,
        unused_pad2: [20]u8,
    };
    comptime { std.debug.assert(@sizeOf(Reply) == 32); }
};

pub const release_overlay_window = struct {
    pub const len =
              2 // extension and command opcodes
            + 2 // request length
            + 4 // window_id
    ;
    pub const Args = struct {
        overlay_window_id: u32,
    };
    pub fn serialize(buf: [*]u8, ext_opcode: u8, args: Args) void {
        buf[0] = ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.release_overlay_window);
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.overlay_window_id);
    }
};
