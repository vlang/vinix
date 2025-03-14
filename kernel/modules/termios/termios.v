module termios

pub const brkint = 0o0002

pub const ignpar = 0o0004

pub const echo = 0o0010

pub const echoe = 0o0020

pub const echok = 0o0040

pub const echonl = 0o0100

pub const icanon = 0o0002

pub const inlcr = 0o0100

pub const igncr = 0o0200

pub const icrnl = 0o0400

pub const ixon = 0o2000

pub const imaxbel = 0o20000

pub const iexten = 0o100000

pub const isig = 0o0001

pub const noflsh = 0o0200

pub const tostop = 0o0400

pub const echoctl = 0o1000

pub const echoprt = 0o2000

pub const echoke = 0o4000

pub const opost = 0o0001

pub const onlcr = 0o0004

pub const cs8 = 0o0060

pub const cread = 0o0200

pub const nccs = 32

pub const veof = 4

pub const veol = 11

pub const verase = 2

pub const vintr = 0

pub const vkill = 3

pub const vmin = 6

pub const vquit = 1

pub const vstart = 8

pub const vstop = 9

pub const vsusp = 10

pub const vtime = 5

pub const vdiscard = 13

pub const vreprint = 12

pub const vwerase = 14

pub const vlnext = 15

pub const b38400 = 15

pub struct Termios {
pub mut:
	c_iflag u32
	c_oflag u32
	c_cflag u32
	c_lflag u32
	c_line  u8
	c_cc    [nccs]u8
	ibaud   u32
	obaud   u32
}

pub fn ctrl(c u8) u8 {
	return c & 0o37
}
