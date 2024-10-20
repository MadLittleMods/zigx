const std = @import("std");
const x = @import("x.zig");

pub const ExtOpcode = enum(u8) {
    query_version = 0,
    create = 1,
    destroy = 2,
    subtract = 3,
    add = 4,
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


pub const ReportLevel = enum(u8) {
    raw_rectangles = 0,
    delta_rectangles = 1,
    bounding_box = 2,
    non_empty = 3,
};

/// Creates a damage object to monitor changes to Drawable
pub const create = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // damage_id
        + 4 // drawable_id
        + 1 // ReportLevel
        + 3 // unused pad
        ;
    pub const Args = struct {
        ext_opcode: u8,
        damage_id: u32,
        drawable_id: u32,
        report_level: ReportLevel,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.create);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.damage_id);
        x.writeIntNative(u32, buf + 8, args.drawable_id);
        buf[12] = @intFromEnum(args.report_level);
        buf[13] = 0; // unused
        buf[14] = 0; // unused
        buf[15] = 0; // unused
    }
};


/// Destroys a previously created Damage object.
pub const destroy = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // damage_id
        ;
    pub const Args = struct {
        ext_opcode: u8,
        damage_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.destroy);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.damage_id);
    }
};

/// Remove regions from a previously created Damage object.
pub const subtract = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // damage_id
        + 4 // repair region
        + 4 // parts region
        ;
    pub const Args = struct {
        ext_opcode: u8,
        damage_id: u32,
        repair_region_id: u32,
        parts_region_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.subtract);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.damage_id);
        x.writeIntNative(u32, buf + 4, args.repair_region_id);
        x.writeIntNative(u32, buf + 4, args.parts_region_id);
    }
};


/// Add a region to a previously created Damage object.
pub const add = struct {
    pub const len =
          2 // extension and command opcodes
        + 2 // request length
        + 4 // damage_id
        + 4 // region
        ;
    pub const Args = struct {
        ext_opcode: u8,
        damage_id: u32,
        region_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.add);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.damage_id);
        x.writeIntNative(u32, buf + 4, args.region_id);
    }
};

