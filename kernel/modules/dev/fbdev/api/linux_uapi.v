module api

// Field names and layout of those structures match Linux usermode API.
// See the following file for details:
// https://github.com/torvalds/linux/blob/master/include/uapi/linux/fb.h

pub struct FBCMap {
pub mut:
	start  u32
	len    u32
	red    &u16
	green  &u16
	blue   &u16
	transp &u16
}

pub struct FBBitfield {
pub mut:
	offset    u32
	length    u32
	msb_right u32
}

pub struct FBFixScreenInfo {
pub mut:
	id           [16]u8
	smem_start   u64
	smem_len     u32
	@type        u32
	type_aux     u32
	visual       u32
	xpanstep     u16
	ypanstep     u16
	ywrapstep    u16
	line_length  u32
	mmio_start   u64
	mmio_len     u32
	accel        u32
	capabilities u16
	reserved     [2]u16
}

pub struct FBVarScreenInfo {
pub mut:
	xres           u32
	yres           u32
	xres_virtual   u32
	yres_virtual   u32
	xoffset        u32
	yoffset        u32
	bits_per_pixel u32
	grayscale      u32
	red            FBBitfield
	green          FBBitfield
	blue           FBBitfield
	transp         FBBitfield
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

pub const fb_activate_now = 0

pub const fb_activate_nxtopen = 1

pub const fb_activate_test = 2

pub const fb_activate_mask = 15

pub const fb_activate_vbl = 16

pub const fb_change_cmap_vbl = 32

pub const fb_activate_all = 64

pub const fb_activate_force = 128

pub const fb_activate_inv_mode = 256

pub const fb_activate_kd_test = 512

pub const fb_type_packed_pixels = 0

pub const fb_type_planes = 1

pub const fb_type_interleaved_planes = 2

pub const fb_type_text = 3

pub const fb_type_vga_planes = 4

pub const fb_type_fourcc = 5

pub const fb_visual_mono01 = 0

pub const fb_visual_mono10 = 1

pub const fb_visual_truecolor = 2

pub const fb_visual_pseudocolor = 3

pub const fb_visual_directcolor = 4

pub const fb_visual_static_pseudocolor = 5

pub const fb_visual_fourcc = 6

pub const fb_vmode_noninterlaced = 0

pub const fb_vmode_interlaced = 1

pub const fb_vmode_double = 2

pub const fb_vmode_odd_fld_first = 4

pub const fb_vmode_mask = 255

pub const fb_vmode_ywrap = 256

pub const fb_vmode_smooth_xpan = 512

pub const fb_vmode_conupdate = 1024

pub const fb_rotate_ur = 0

pub const fb_rotate_cw = 1

pub const fb_rotate_ud = 2

pub const fb_rotate_ccw = 3
