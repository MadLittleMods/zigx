pub const Latin1 = @import("charset/latin1.zig").Latin1;
pub const Latin2 = @import("charset/latin2.zig").Latin2;
pub const Latin3 = @import("charset/latin3.zig").Latin3;
pub const Latin4 = @import("charset/latin4.zig").Latin4;
pub const Kana = @import("charset/kana.zig").Kana;
pub const Arabic = @import("charset/arabic.zig").Arabic;
pub const Cyrillic = @import("charset/cyrillic.zig").Cyrillic;
pub const Greek = @import("charset/greek.zig").Greek;
pub const Technical = @import("charset/technical.zig").Technical;
pub const Special = @import("charset/special.zig").Special;
pub const Publish = @import("charset/publish.zig").Publish;
pub const Apl = @import("charset/apl.zig").Apl;
pub const Hebrew = @import("charset/hebrew.zig").Hebrew;
pub const Thai = @import("charset/thai.zig").Thai;
pub const Korean = @import("charset/korean.zig").Korean;
pub const Latin9 = @import("charset/latin9.zig").Latin9;
pub const Currency = @import("charset/currency.zig").Currency;
pub const _3270 = @import("charset/_3270.zig")._3270;
pub const Keyboardxkb = @import("charset/keyboardxkb.zig").Keyboardxkb;
pub const Keyboard = @import("charset/keyboard.zig").Keyboard;
pub const Combined = @import("charset/combined.zig").Combined;

pub const Charset = enum(u8) {
    latin1 = 0,
    latin2 = 1,
    latin3 = 2,
    latin4 = 3,
    kana = 4,
    arabic = 5,
    cyrillic = 6,
    greek = 7,
    technical = 8,
    special = 9,
    publish = 10,
    apl = 11,
    hebrew = 12,
    thai = 13,
    korean = 14,
    latin9 = 19,
    currency = 32,
    _3270 = 253,
    keyboardxkb = 254,
    keyboard = 255,

    pub fn fromInt(value_int: u8) ?Charset {
        return inline for (@typeInfo(Charset).Enum.fields) |f| {
            if (value_int == f.value) break @enumFromInt(f.value);
        } else null;
    }

    pub fn Enum(comptime self: Charset) type {
        return switch (self) {
            .latin1 => Latin1,
            .latin2 => Latin2,
            .latin3 => Latin3,
            .latin4 => Latin4,
            .kana => Kana,
            .arabic => Arabic,
            .cyrillic => Cyrillic,
            .greek => Greek,
            .technical => Technical,
            .special => Special,
            .publish => Publish,
            .apl => Apl,
            .hebrew => Hebrew,
            .thai => Thai,
            .korean => Korean,
            .latin9 => Latin9,
            .currency => Currency,
            ._3270 => _3270,
            .keyboardxkb => Keyboardxkb,
            .keyboard => Keyboard,
        };
    }
};
