const std = @import("std");
const x = @import("x.zig");

pub const ExtOpcode = enum(u8) {
    query_version = 0,
    create = 1,
    destroy = 2,
    subtract = 3,
    add = 4,
};

pub const DamageNotifyEvent = extern struct {
    /// This will end up being the extension opcode
    kind: x.ServerMsgKind,
    /// The level of the damage being reported.
    /// If the 0x80 bit is set, indicates there are subsequent Damage events
    /// being delivered immediately as part of a larger Damage region.
    report_level_and_more_raw: u8,
    sequence: u16,
    /// The drawable for which damage is being reported.
    drawable_id: u32,
    /// The Damage object being used to track the damage.
    damage_id: u32,
    /// Time when the event was generated (in milliseconds).
    timestamp: u32,
    /// Damaged area of the drawable.
    area: x.Rectangle,
    /// Total area of the drawable.
    geometry: x.Rectangle,

    pub fn getReportLevel(self: @This()) ReportLevel {
        return @enumFromInt(self.report_level_and_more_raw & 0x7F);
    }

    pub fn hasMore(self: @This()) bool {
        return (self.report_level_and_more_raw & 0x80) != 0;
    }
};
comptime { std.debug.assert(@sizeOf(DamageNotifyEvent) == 32); }


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
    /// Delivers DamageNotify events each time the screen
    /// is modified with rectangular bounds that circumscribe
    /// the damaged area.  No attempt to compress out overlapping
    /// rectangles is made.
    raw_rectangles = 0,
    /// Delivers DamageNotify events each time damage occurs
    /// which is not included in the damage region.  The
    /// reported rectangles include only the changes to that
    /// area, not the raw damage data.
    delta_rectangles = 1,
    /// Delivers DamageNotify events each time the bounding
    /// box enclosing the damage region increases in size.
    /// The reported rectangle encloses the entire damage region,
    /// not just the changes to that size.
    bounding_box = 2,
    /// Delivers a single DamageNotify event each time the
    /// damage rectangle changes from empty to non-empty, and
    /// also whenever the result of a DamageSubtract request
    /// results in a non-empty region.
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
        /// The region to repair
        repair_region_id: u32,
        /// An output parameter to store the regions that were actually repaired
        parts_region_id: u32,
    };
    pub fn serialize(buf: [*]u8, args: Args) void {
        buf[0] = args.ext_opcode;
        buf[1] = @intFromEnum(ExtOpcode.subtract);
        comptime { std.debug.assert(len & 0x3 == 0); }
        x.writeIntNative(u16, buf + 2, len >> 2);
        x.writeIntNative(u32, buf + 4, args.damage_id);
        x.writeIntNative(u32, buf + 8, args.repair_region_id);
        x.writeIntNative(u32, buf + 12, args.parts_region_id);
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
        x.writeIntNative(u32, buf + 8, args.region_id);
    }
};

