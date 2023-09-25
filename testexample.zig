// A working example to test various parts of the API
const std = @import("std");
const x = @import("./x.zig");
const common = @import("common.zig");

const Endian = std.builtin.Endian;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const window_width = 400;
const window_height = 400;

pub const Ids = struct {
    // Base resource ID for the window
    base: u32,
    pub fn window(self: Ids) u32 { return self.base; }
    pub fn bg_gc(self: Ids) u32 { return self.base + 1; }
    pub fn fg_gc(self: Ids) u32 { return self.base + 2; }
    pub fn pixmap(self: Ids) u32 { return self.base + 3; }
    // For the X Render extension part of this example
    pub fn picture_root(self: Ids) u32 { return self.base + 4; }
    pub fn picture_window(self: Ids) u32 { return self.base + 5; }
};

// ZFormat
// depth:
//     bits-per-pixel: 1, 4, 8, 16, 24, 32
//         bpp can be larger than depth, when it is, the
//         least significant bits hold the pixmap data
//         when bpp is 4, order of nibbles in the bytes is the
//         same as the image "byte-order"
//     scanline-pad: 8, 16, 32
const ImageFormat = struct {
    endian: Endian,
    depth: u8,
    bits_per_pixel: u8,
    scanline_pad: u8,
};
fn getImageFormat(
    endian: Endian,
    formats: []const align(4) x.Format,
    root_depth: u8,
) !ImageFormat {
    var opt_match_index: ?usize = null;
    for (formats, 0..) |format, i| {
        if (format.depth == root_depth) {
            if (opt_match_index) |_|
                return error.MultiplePixmapFormatsSameDepth;
            opt_match_index = i;
        }
    }
    const match_index = opt_match_index orelse
        return error.MissingPixmapFormat;
    return ImageFormat {
        .endian = endian,
        .depth = root_depth,
        .bits_per_pixel = formats[match_index].bits_per_pixel,
        .scanline_pad = formats[match_index].scanline_pad,
    };
}

/// Sanity check that we're not running into data integrity (corruption) issues caused
/// by overflowing and wrapping around to the front ofq the buffer.
fn checkMessageLengthFitsInBuffer(message_length: usize, buffer_limit: usize) !void {
    if(message_length > buffer_limit) {
        std.debug.panic("Reply is bigger than our buffer (data corruption will ensue) {} > {}. In order to fix, increase the buffer size.", .{
            message_length,
            buffer_limit,
        });
    }
}

/// Find a picture format that matches the desired attributes like depth.
/// In the future, we might want to match against more things like which screen it came from, etc.
pub fn findMatchingPictureFormat(formats: []const x.render.PictureFormatInfo, desired_depth: u8) !x.render.PictureFormatInfo {
    for (formats) |format| {
        if (format.depth != desired_depth) continue;
        return format;
    }
    return error.VisualTypeNotFound;
}

/// X server extension info.
pub const ExtensionInfo = struct {
    extension_name: []const u8,
    /// The extension opcode is used to identify which X extension a given request is
    /// intended for (used as the major opcode). This essentially namespaces any extension
    /// requests. The extension differentiates its own requests by using a minor opcode.
    opcode: u8,
    /// Extension error codes are added on top of this base error code.
    base_error_code: u8,
};

pub fn main() !u8 {
    try x.wsaStartup();
    const conn = try common.connect(allocator);
    defer std.os.shutdown(conn.sock, .both) catch {};

    const conn_setup_result = blk: {
        const fixed = conn.setup.fixed();
        inline for (@typeInfo(@TypeOf(fixed.*)).Struct.fields) |field| {
            std.log.debug("{s}: {any}", .{field.name, @field(fixed, field.name)});
        }
        const image_endian: Endian = switch (fixed.image_byte_order) {
            .lsb_first => .Little,
            .msb_first => .Big,
            else => |order| {
                std.log.err("unknown image-byte-order {}", .{order});
                return 0xff;
            },
        };
        std.log.debug("vendor: {s}", .{try conn.setup.getVendorSlice(fixed.vendor_len)});
        const format_list_offset = x.ConnectSetup.getFormatListOffset(fixed.vendor_len);
        const format_list_limit = x.ConnectSetup.getFormatListLimit(format_list_offset, fixed.format_count);
        std.log.debug("fmt list off={} limit={}", .{format_list_offset, format_list_limit});
        const formats = try conn.setup.getFormatList(format_list_offset, format_list_limit);
        for (formats, 0..) |format, i| {
            std.log.debug("format[{}] depth={:3} bpp={:3} scanpad={:3}", .{i, format.depth, format.bits_per_pixel, format.scanline_pad});
        }
        var screen = conn.setup.getFirstScreenPtr(format_list_limit);
        inline for (@typeInfo(@TypeOf(screen.*)).Struct.fields) |field| {
            std.log.debug("SCREEN 0| {s}: {any}", .{field.name, @field(screen, field.name)});
        }
        break :blk .{
            .screen = screen,
            .image_format = getImageFormat(
                image_endian,
                formats,
                screen.root_depth,
            ) catch |err| {
                std.log.err("can't resolve root depth {} format: {s}", .{screen.root_depth, @errorName(err)});
                return 0xff;
            },
        };
    };
    const screen = conn_setup_result.screen;

    // TODO: maybe need to call conn.setup.verify or something?

    const ids = Ids{ .base = conn.setup.fixed().resource_id_base };
    {
        var msg_buf: [x.create_window.max_len]u8 = undefined;
        const len = x.create_window.serialize(&msg_buf, .{
            .window_id = ids.window(),
            .parent_window_id = screen.root,
            .depth = 0, // we don't care, just inherit from the parent
            .x = 0, .y = 0,
            .width = window_width, .height = window_height,
            .border_width = 0, // TODO: what is this?
            .class = .input_output,
            .visual_id = screen.root_visual,
        }, .{
//            .bg_pixmap = .copy_from_parent,
            .bg_pixel = x.rgb24To(0xbbccdd, screen.root_depth),
//            //.border_pixmap =
//            .border_pixel = 0x01fa8ec9,
//            .bit_gravity = .north_west,
//            .win_gravity = .east,
//            .backing_store = .when_mapped,
//            .backing_planes = 0x1234,
//            .backing_pixel = 0xbbeeeeff,
//            .override_redirect = true,
//            .save_under = true,
            .event_mask =
                  x.event.key_press
                | x.event.key_release
                | x.event.button_press
                | x.event.button_release
                | x.event.enter_window
                | x.event.leave_window
                | x.event.pointer_motion
//                | x.event.pointer_motion_hint WHAT THIS DO?
//                | x.event.button1_motion  WHAT THIS DO?
//                | x.event.button2_motion  WHAT THIS DO?
//                | x.event.button3_motion  WHAT THIS DO?
//                | x.event.button4_motion  WHAT THIS DO?
//                | x.event.button5_motion  WHAT THIS DO?
//                | x.event.button_motion  WHAT THIS DO?
                | x.event.keymap_state
                | x.event.exposure
                | x.event.structure_notify
                ,
//            .dont_propagate = 1,
        });
        try conn.send(msg_buf[0..len]);
    }

    {
        var msg_buf: [x.create_gc.max_len]u8 = undefined;
        const len = x.create_gc.serialize(&msg_buf, .{
            .gc_id = ids.bg_gc(),
            .drawable_id = ids.window(),
        }, .{
            .foreground = screen.black_pixel,
        });
        try conn.send(msg_buf[0..len]);
    }
    {
        var msg_buf: [x.create_gc.max_len]u8 = undefined;
        const len = x.create_gc.serialize(&msg_buf, .{
            .gc_id = ids.fg_gc(),
            .drawable_id = ids.window(),
        }, .{
            .background = screen.black_pixel,
            .foreground = x.rgb24To(0xffaadd, screen.root_depth),
            // prevent NoExposure events when we send CopyArea
            .graphics_exposures = false,
        });
        try conn.send(msg_buf[0..len]);
    }

    // get some font information
    {
        const text_literal = [_]u16 { 'm' };
        const text = x.Slice(u16, [*]const u16) { .ptr = &text_literal, .len = text_literal.len };
        var msg: [x.query_text_extents.getLen(text.len)]u8 = undefined;
        x.query_text_extents.serialize(&msg, ids.fg_gc(), text);
        try conn.send(&msg);
    }

    const double_buf = try x.DoubleBuffer.init(
        std.mem.alignForward(usize, 8000, std.mem.page_size),
        .{ .memfd_name = "ZigX11DoubleBuffer" },
    );
    defer double_buf.deinit(); // not necessary but good to test
    std.log.info("read buffer capacity is {}", .{double_buf.half_len});
    var buf = double_buf.contiguousReadBuffer();
    const buffer_limit = buf.half_len;

    const font_dims: FontDims = blk: {
        const message_length = try x.readOneMsg(conn.reader(), @alignCast(buf.nextReadBuffer()));
        try checkMessageLengthFitsInBuffer(message_length, buffer_limit);
        switch (x.serverMsgTaggedUnion(@alignCast(buf.double_buffer_ptr))) {
            .reply => |msg_reply| {
                const msg: *x.ServerMsg.QueryTextExtents = @ptrCast(msg_reply);
                break :blk .{
                    .width = @intCast(msg.overall_width),
                    .height = @intCast(msg.font_ascent + msg.font_descent),
                    .font_left = @intCast(msg.overall_left),
                    .font_ascent = msg.font_ascent,
                };
            },
            else => |msg| {
                std.log.err("expected a reply but got {}", .{msg});
                return 1;
            },
        }
    };

    {
        const ext_name = comptime x.Slice(u16, [*]const u8).initComptime("RENDER");
        var msg: [x.query_extension.getLen(ext_name.len)]u8 = undefined;
        x.query_extension.serialize(&msg, ext_name);
        try conn.send(&msg);
    }
    {
        const message_length = try x.readOneMsg(conn.reader(), @alignCast(buf.nextReadBuffer()));
        try checkMessageLengthFitsInBuffer(message_length, buffer_limit);
    }
    const opt_render_ext: ?ExtensionInfo = blk: {
        switch (x.serverMsgTaggedUnion(@alignCast(buf.double_buffer_ptr))) {
            .reply => |msg_reply| {
                const msg: *x.ServerMsg.QueryExtension = @ptrCast(msg_reply);
                if (msg.present == 0) {
                    std.log.info("RENDER extension: not present", .{});
                    break :blk null;
                }
                std.debug.assert(msg.present == 1);
                std.log.info("RENDER extension: opcode={} base_error_code={}", .{msg.major_opcode, msg.first_error});
                std.log.info("RENDER extension: {}", .{msg});
                break :blk .{
                    .extension_name = "RENDER",
                    .opcode = msg.major_opcode,
                    .base_error_code = msg.first_error
                };
            },
            else => |msg| {
                std.log.err("expected a reply but got {}", .{msg});
                return 1;
            },
        }
    };
    if (opt_render_ext) |render_ext| {
        {
            var msg: [x.render.query_version.len]u8 = undefined;
            x.render.query_version.serialize(&msg, render_ext.opcode, .{
                .major_version = 0,
                .minor_version = 11,
            });
            try conn.send(&msg);
        }
        {
            const message_length = try x.readOneMsg(conn.reader(), @alignCast(buf.nextReadBuffer()));
            try checkMessageLengthFitsInBuffer(message_length, buffer_limit);
        }
        switch (x.serverMsgTaggedUnion(@alignCast(buf.double_buffer_ptr))) {
            .reply => |msg_reply| {
                const msg: *x.render.query_version.Reply = @ptrCast(msg_reply);
                std.log.info("RENDER extension: version {}.{}", .{msg.major_version, msg.minor_version});
                if (msg.major_version != 0) {
                    std.log.err("xrender extension major version {} too new", .{msg.major_version});
                    return 1;
                }
                if (msg.minor_version < 11) {
                    std.log.err("xrender extension minor version {} too old", .{msg.minor_version});
                    return 1;
                }
            },
            else => |msg| {
                std.log.err("expected a reply but got {}", .{msg});
                return 1;
            },
        }

        // Find some compatible picture formats for use with the X Render extension. We want
        // to find a 24-bit depth format for use with the root and our window.
        {
            var msg: [x.render.query_pict_formats.len]u8 = undefined;
            x.render.query_pict_formats.serialize(&msg, render_ext.opcode);
            try conn.send(&msg);
        }
        {
            const message_length = try x.readOneMsg(conn.reader(), @alignCast(buf.nextReadBuffer()));
            try checkMessageLengthFitsInBuffer(message_length, buffer_limit);
        }
        const pict_formats_data: ?struct { matching_picture_format: x.render.PictureFormatInfo } = blk: {
            switch (x.serverMsgTaggedUnion(@alignCast(buf.double_buffer_ptr))) {
                .reply => |msg_reply| {
                    const msg: *x.render.query_pict_formats.Reply = @ptrCast(msg_reply);
                    std.log.info("RENDER extension: pict formats num_formats={}, num_screens={}, num_depths={}, num_visuals={}", .{
                        msg.num_formats,
                        msg.num_screens,
                        msg.num_depths,
                        msg.num_visuals,
                    });
                    for(msg.getPictureFormats(), 0..) |format, i| {
                        std.log.info("RENDER extension: pict format ({}) {any}", .{
                            i,
                            format,
                        });
                    }
                    break :blk .{
                        .matching_picture_format = try findMatchingPictureFormat(msg.getPictureFormats()[0..], screen.root_depth),
                    };
                },
                else => |msg| {
                    std.log.err("expected a reply but got {}", .{msg});
                    return 1;
                },
            }
        };
        const matching_picture_format = pict_formats_data.?.matching_picture_format;

        // We need to create a picture for every drawable that we want to use with the X
        // Render extension
        // =============================================================================
        //
        // Create a picture for the root window that we will copy from in this example
        {
            var msg: [x.render.create_picture.max_len]u8 = undefined;
            const len = x.render.create_picture.serialize(&msg, render_ext.opcode, .{
                .picture_id = ids.picture_root(),
                .drawable_id = screen.root,
                .format_id = matching_picture_format.picture_format_id,
                .options = .{
                    // We want to include (`.include_inferiors`) and sub-windows when we
                    // copy from the root window. Otherwise, by default, the root window
                    // would be clipped (`.clip_by_children`) by any sub-window on top.
                    .subwindow_mode = .include_inferiors,
                },
            });
            try conn.send(msg[0..len]);
        }

        // Create a picture for the our window that we can copy and composite things onto
        {
            var msg: [x.render.create_picture.max_len]u8 = undefined;
            const len = x.render.create_picture.serialize(&msg, render_ext.opcode, .{
                .picture_id = ids.picture_window(),
                .drawable_id = ids.window(),
                .format_id = matching_picture_format.picture_format_id,
                .options = .{
                    .subwindow_mode = .include_inferiors,
                },
            });
            try conn.send(msg[0..len]);
        }
    }

    {
        var msg: [x.map_window.len]u8 = undefined;
        x.map_window.serialize(&msg, ids.window());
        try conn.send(&msg);
    }

    while (true) {
        {
            const recv_buf = buf.nextReadBuffer();
            if (recv_buf.len == 0) {
                std.log.err("buffer size {} not big enough!", .{buf.half_len});
                return 1;
            }
            const len = try x.readSock(conn.sock, recv_buf, 0);
            if (len == 0) {
                std.log.info("X server connection closed", .{});
                return 0;
            }
            buf.reserve(len);
        }
        while (true) {
            const data = buf.nextReservedBuffer();
            if (data.len < 32)
                break;
            const msg_len = x.parseMsgLen(data[0..32].*);
            if (data.len < msg_len)
                break;
            buf.release(msg_len);
            //buf.resetIfEmpty();
            switch (x.serverMsgTaggedUnion(@alignCast(data.ptr))) {
                .err => |msg| {
                    std.log.err("Received X error: {}", .{msg});
                    return 1;
                },
                .reply => |msg| {
                    // We assume any reply here will be to the `get_image` request but
                    // normally you would want some state machine sequencer to match up
                    // requests with replies.
                    try checkTestImageIsDrawnToWindow(msg, conn_setup_result.image_format);
                },
                .generic_extension_event => |msg| {
                    std.log.info("TODO: handle a generic extension event {}", .{msg});
                    return error.TodoHandleGenericExtensionEvent;
                },
                .key_press => |msg| {
                    std.log.info("key_press: keycode={}", .{msg.keycode});
                },
                .key_release => |msg| {
                    std.log.info("key_release: keycode={}", .{msg.keycode});
                },
                .button_press => |msg| {
                    std.log.info("button_press: {}", .{msg});
                },
                .button_release => |msg| {
                    std.log.info("button_release: {}", .{msg});
                },
                .enter_notify => |msg| {
                    std.log.info("enter_window: {}", .{msg});
                },
                .leave_notify => |msg| {
                    std.log.info("leave_window: {}", .{msg});
                },
                .motion_notify => |msg| {
                    // too much logging
                    _ = msg;
                    //std.log.info("pointer_motion: {}", .{msg});
                },
                .keymap_notify => |msg| {
                    std.log.info("keymap_state: {}", .{msg});
                },
                .expose => |msg| {
                    std.log.info("expose: {}", .{msg});
                    try render(
                        conn.sock,
                        screen.root_depth,
                        conn_setup_result.image_format,
                        ids,
                        font_dims,
                        opt_render_ext,
                    );

                    {
                        var get_image_msg: [x.get_image.len]u8 = undefined;
                        x.get_image.serialize(&get_image_msg, .{
                            .format = .z_pixmap,
                            .drawable_id = ids.window(),
                            // Coords match where we drew the test image
                            .x = 100,
                            .y = 20,
                            .width = test_image.width,
                            .height = test_image.height,
                            .plane_mask = 0xffffffff,
                        });
                        // We handle the reply to this request above (see `checkTestImageIsDrawnToWindow`)
                        try common.send(conn.sock, &get_image_msg);
                    }
                },
                .mapping_notify => |msg| {
                    std.log.info("mapping_notify: {}", .{msg});
                },
                .no_exposure => |msg| std.debug.panic("unexpected no_exposure {}", .{msg}),
                .unhandled => |msg| {
                    std.log.info("todo: server msg {}", .{msg});
                    return error.UnhandledServerMsg;
                },
                .map_notify => |msg| std.log.info("map_notify: {}", .{msg}),
                .reparent_notify => |msg| std.log.info("reparent_notify: {}", .{msg}),
                .configure_notify => |msg| std.log.info("configure_notify: {}", .{msg}),
            }
        }
    }
}

const FontDims = struct {
    width: u8,
    height: u8,
    font_left: i16, // pixels to the left of the text basepoint
    font_ascent: i16, // pixels up from the text basepoint to the top of the text
};


const test_image = struct {
    pub const width = 15;
    pub const height = 15;

    pub const max_bytes_per_pixel = 4;
    const max_scanline_pad = 32;
    pub const max_scanline_len = std.mem.alignForward(
        u16,
        max_bytes_per_pixel * width,
        max_scanline_pad / 8, // max scanline pad
    );
    const max_data_len = height * max_scanline_len;
};

fn render(
    sock: std.os.socket_t,
    depth: u8,
    image_format: ImageFormat,
    ids: Ids,
    font_dims: FontDims,
    opt_render_ext: ?ExtensionInfo,
) !void {
    {
        var msg: [x.poly_fill_rectangle.getLen(1)]u8 = undefined;
        x.poly_fill_rectangle.serialize(&msg, .{
            .drawable_id = ids.window(),
            .gc_id = ids.bg_gc(),
        }, &[_]x.Rectangle {
            .{ .x = 100, .y = 100, .width = 200, .height = 200 },
        });
        try common.send(sock, &msg);
    }
    {
        var msg: [x.clear_area.len]u8 = undefined;
        x.clear_area.serialize(&msg, false, ids.window(), .{
            .x = 150, .y = 150, .width = 100, .height = 100,
        });
        try common.send(sock, &msg);
    }

    try changeGcColor(sock, ids.fg_gc(), x.rgb24To(0xffaadd, depth));
    {
        const text_literal: []const u8 = "Hello X!";
        const text = x.Slice(u8, [*]const u8) { .ptr = text_literal.ptr, .len = text_literal.len };
        var msg: [x.image_text8.getLen(text.len)]u8 = undefined;

        const text_width = font_dims.width * text_literal.len;

        x.image_text8.serialize(&msg, text, .{
            .drawable_id = ids.window(),
            .gc_id = ids.fg_gc(),
            .x = @divTrunc((window_width - @as(i16, @intCast(text_width))),  2) + font_dims.font_left,
            .y = @divTrunc((window_height - @as(i16, @intCast(font_dims.height))), 2) + font_dims.font_ascent,
        });
        try common.send(sock, &msg);
    }

    try changeGcColor(sock, ids.fg_gc(), x.rgb24To(0x00ff00, depth));
    {
        const rectangles = [_]x.Rectangle{
            .{ .x = 20, .y = 20, .width = 15, .height = 15 },
            .{ .x = 40, .y = 20, .width = 15, .height = 15 },
        };
        var msg: [x.poly_fill_rectangle.getLen(rectangles.len)]u8 = undefined;
        x.poly_fill_rectangle.serialize(&msg, .{
            .drawable_id = ids.window(),
            .gc_id = ids.fg_gc(),
        }, &rectangles);
        try common.send(sock, &msg);
    }
    try changeGcColor(sock, ids.fg_gc(), x.rgb24To(0x0000ff, depth));
    {
        const rectangles = [_]x.Rectangle{
            .{ .x = 60, .y = 20, .width = 15, .height = 15 },
            .{ .x = 80, .y = 20, .width = 15, .height = 15 },
        };
        var msg: [x.poly_rectangle.getLen(rectangles.len)]u8 = undefined;
        x.poly_rectangle.serialize(&msg, .{
            .drawable_id = ids.window(),
            .gc_id = ids.fg_gc(),
        }, &rectangles);
        try common.send(sock, &msg);
    }


    const test_image_scanline_len = blk: {
        const bytes_per_pixel = image_format.bits_per_pixel / 8;
        std.debug.assert(bytes_per_pixel <= test_image.max_bytes_per_pixel);
        break :blk std.mem.alignForward(
            u16,
            bytes_per_pixel * test_image.width,
            image_format.scanline_pad / 8,
        );
    };
    const test_image_data_len: u18 = @intCast(test_image.height * test_image_scanline_len);
    std.debug.assert(test_image_data_len <= test_image.max_data_len);

    {
        var put_image_msg: [x.put_image.getLen(test_image.max_data_len)]u8 = undefined;
        populateTestImage(
            image_format,
            test_image.width,
            test_image.height,
            test_image_scanline_len,
            put_image_msg[x.put_image.data_offset..],
        );
        x.put_image.serializeNoDataCopy(&put_image_msg, test_image_data_len, .{
            .format = .z_pixmap,
            .drawable_id = ids.window(),
            .gc_id = ids.fg_gc(),
            .width = test_image.width,
            .height = test_image.height,
            .x = 100,
            .y = 20,
            .left_pad = 0,
            .depth = image_format.depth,
        });
        try common.send(sock, put_image_msg[0 .. x.put_image.getLen(test_image_data_len)]);

        // test a pixmap
        {
            var msg: [x.create_pixmap.len]u8 = undefined;
            x.create_pixmap.serialize(&msg, .{
                .id = ids.pixmap(),
                .drawable_id = ids.window(),
                .depth = image_format.depth,
                .width = test_image.width,
                .height = test_image.height,
            });
            try common.send(sock, &msg);
        }
        x.put_image.serializeNoDataCopy(&put_image_msg, test_image_data_len, .{
            .format = .z_pixmap,
            .drawable_id = ids.pixmap(),
            .gc_id = ids.fg_gc(),
            .width = test_image.width,
            .height = test_image.height,
            .x = 0,
            .y = 0,
            .left_pad = 0,
            .depth = image_format.depth,
        });
        try common.send(sock, put_image_msg[0 .. x.put_image.getLen(test_image_data_len)]);

        {
            var msg: [x.copy_area.len]u8 = undefined;
            x.copy_area.serialize(&msg, .{
                .src_drawable_id = ids.pixmap(),
                .dst_drawable_id = ids.window(),
                .gc_id = ids.fg_gc(),
                .src_x = 0,
                .src_y = 0,
                .dst_x = 120,
                .dst_y = 20,
                .width = test_image.width,
                .height = test_image.height,
            });
            try common.send(sock, &msg);
        }

        {
            var msg: [x.free_pixmap.len]u8 = undefined;
            x.free_pixmap.serialize(&msg, ids.pixmap());
            try common.send(sock, &msg);
        }
    }

    if (opt_render_ext) |render_ext| {
        // Capture a small 100x100 screenshot of the top-left of the root window and
        // composite it onto our window.
        {
            var msg: [x.render.composite.len]u8 = undefined;
            x.render.composite.serialize(&msg, render_ext.opcode, .{
                .picture_operation = .over,
                .src_picture_id = ids.picture_root(),
                .mask_picture_id = 0,
                .dst_picture_id = ids.picture_window(),
                .src_x = 0,
                .src_y = 0,
                .mask_x = 0,
                .mask_y = 0,
                .dst_x = 50,
                .dst_y = 50,
                .width = 100,
                .height = 100,
            });
            try common.send(sock, &msg);
        }
    }
}

fn changeGcColor(sock: std.os.socket_t, gc_id: u32, color: u32) !void {
    var msg_buf: [x.change_gc.max_len]u8 = undefined;
    const len = x.change_gc.serialize(&msg_buf, gc_id, .{
        .foreground = color,
    });
    try common.send(sock, msg_buf[0..len]);
}

fn populateTestImage(
    image_format: ImageFormat,
    width: u16,
    height: u16,
    stride: usize,
    data: []u8,
) void {
    var row: usize = 0;
    while (row < height) : (row += 1) {
        var data_off: usize = row * stride;

        var color: u24 = 0;
        if (row < 5) { color |= 0xff0000; }
        else if (row < 10) { color |= 0xff00; }
        else { color |= 0xff; }

        var col: usize = 0;
        while (col < width) : (col += 1) {
            switch (image_format.depth) {
                16 => std.mem.writeInt(
                    u16,
                    data[data_off..][0 .. 2],
                    x.rgb24To16(color),
                    image_format.endian,
                ),
                24 => std.mem.writeInt(
                    u24,
                    data[data_off..][0 .. 3],
                    color,
                    image_format.endian,
                ),
                32 => std.mem.writeInt(
                    u32,
                    data[data_off..][0 .. 4],
                    color,
                    image_format.endian,
                ),
                else => std.debug.panic("TODO: implement image depth {}", .{image_format.depth}),
            }
            data_off += (image_format.bits_per_pixel / 8);
        }
    }
}

/// Grab the pixels from the window after we've rendered to it using `get_image` and
/// check that the test image pattern was *actually* drawn to the window.
fn checkTestImageIsDrawnToWindow(
    msg_reply: *x.ServerMsg.Reply,
    image_format: ImageFormat,
) !void {
    const msg: *x.get_image.Reply = @ptrCast(msg_reply);
    const image_data = msg.getData();

    // Given our request for an image with the width/height specified,
    // make sure we got at least the right amount of data back to
    // represent that size of image (there may also be padding at the
    // end).
    std.debug.assert(image_data.len >= (test_image.width * test_image.height * x.get_image.Reply.scanline_pad_bytes));
    // Currently, we only support one image format that matches the root window depth
    std.debug.assert(msg.depth == image_format.depth);

    const bytes_per_pixel_in_data = x.get_image.Reply.scanline_pad_bytes;

    var width_index: u16 = 0;
    var height_index: u16 = 0;
    var image_data_index: u32 = 0;
    while ((image_data_index + bytes_per_pixel_in_data) < image_data.len) : (image_data_index += bytes_per_pixel_in_data) {
        if (width_index >= test_image.width) {
            // For Debugging: Print a newline after each row
            // std.debug.print("\n", .{});
            width_index = 0;
            height_index += 1;
        }

        //  The image data might have padding on the end so make sure to stop when we expect the image to end
        if (height_index >= test_image.height) {
            break;
        }

        const padded_pixel_value = image_data[image_data_index..(image_data_index + bytes_per_pixel_in_data)];
        const pixel_value = std.mem.readVarInt(
            u32,
            padded_pixel_value,
            image_format.endian,
        );
        // For Debugging: Print out the pixels
        // std.debug.print("0x{x} ", .{pixel_value});

        // Assert test image pattern
        if (height_index < 5) { std.debug.assert(pixel_value == 0xffff0000); }
        else if (height_index < 10) { std.debug.assert(pixel_value == 0xff00ff00); }
        else { std.debug.assert(pixel_value == 0xff0000ff); }

        width_index += 1;
    }
}