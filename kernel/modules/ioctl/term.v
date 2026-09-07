module ioctl

pub const tcgets = 0x5401

pub const tcsets = 0x5402

pub const tcsetsw = 0x5403

pub const tcsetsf = 0x5404

pub const tcsbrk = 0x5409

pub const tcxonc = 0x540a

pub const tcflsh = 0x540b

pub const tiocexcl = 0x540c

pub const tiocnxcl = 0x540d

pub const tiocsctty = 0x540e

pub const tiocgpgrp = 0x540f

pub const tiocspgrp = 0x5410

pub const tiocoutq = 0x5411

pub const tiocgwinsz = 0x5413

pub const tiocswinsz = 0x5414

pub const tiocnotty = 0x5422

pub const tiocgsid = 0x5429

// Unix98 pseudo-terminal allocation and peer discovery.
pub const tiocgptn = u64(0x80045430)

pub const tiocsptlck = 0x40045431

pub const tiocgptlck = u64(0x80045439)

pub const tiocgptpeer = 0x5441

// tcflush(3) selectors, the argument to TCFLSH.
pub const tciflush = 0

pub const tcoflush = 1

pub const tcioflush = 2

pub struct WinSize {
pub mut:
	ws_row    u16
	ws_col    u16
	ws_xpixel u16
	ws_ypixel u16
}

// Linux console mode ioctls (linux/kd.h). KD_GRAPHICS tells the kernel that a
// program owns the framebuffer and the text console must stop drawing.
pub const kdgetmode = 0x4b3b

pub const kdsetmode = 0x4b3a

pub const kd_text = 0

pub const kd_graphics = 1
