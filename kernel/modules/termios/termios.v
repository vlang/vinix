// termios.v: Values for termios related ioctl() and syscalls.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module termios

pub const echo = 0x0001

pub const echoe = 0x0002

pub const echok = 0x0004

pub const echonl = 0x0008

pub const icanon = 0x0010

pub const inlcr = 0x0020

pub const icrnl = 0x0002

pub const iexten = 0x0020

pub const isig = 0x0040

pub const noflsh = 0x0080

pub const tostop = 0x0100

pub const echoprt = 0x0200

pub const nccs = 11

pub const veof = 0

pub const veol = 1

pub const verase = 2

pub const vintr = 3

pub const vkill = 4

pub const vmin = 5

pub const vquit = 6

pub const vstart = 7

pub const vstop = 8

pub const vsusp = 9

pub const vtime = 10

pub struct Termios {
pub mut:
	c_iflag u32
	c_oflag u32
	c_cflag u32
	c_lflag u32
	c_cc    [nccs]u32
	ibaud   u32
	obaud   u32
}
