module ioctl

pub const tcgets = 0x5401
pub const tcsets = 0x5402
pub const tiocsctty = 0x540e
pub const tiocgwinsz = 0x5413

pub struct WinSize {
pub mut:
	ws_row u16
	ws_col u16
	ws_xpixel u16
	ws_ypixel u16
}
