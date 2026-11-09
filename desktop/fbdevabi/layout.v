// SPDX-License-Identifier: GPL-2.0-or-later
module fbdevabi

// Linux fbdev uses unsigned long for physical addresses, including on PPC32.
// Keep all other members at their UAPI widths; these are ioctl wire layouts.
pub struct Bitfield {
pub mut:
	offset    u32
	length    u32
	msb_right u32
}

pub struct Variable {
pub mut:
	xres           u32
	yres           u32
	xres_virtual   u32
	yres_virtual   u32
	xoffset        u32
	yoffset        u32
	bits_per_pixel u32
	grayscale      u32
	red            Bitfield
	green          Bitfield
	blue           Bitfield
	transp         Bitfield
	nonstd         u32
	activate       u32
	height         u32
	width          u32
	accel_flags    u32
	pixclock       u32
	left_margin    u32
	right_margin   u32
	upper_margin   u32
	lower_margin   u32
	hsync_len      u32
	vsync_len      u32
	sync           u32
	vmode          u32
	rotate         u32
	colorspace     u32
	reserved       [4]u32
}

pub struct Fixed {
pub mut:
	id           [16]u8
	smem_start   usize
	smem_len     u32
	typ          u32
	type_aux     u32
	visual       u32
	xpanstep     u16
	ypanstep     u16
	ywrapstep    u16
	line_length  u32
	mmio_start   usize
	mmio_len     u32
	accel        u32
	capabilities u16
	reserved     [2]u16
}
