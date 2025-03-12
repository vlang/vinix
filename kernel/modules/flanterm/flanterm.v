module flanterm

fn C.flanterm_fb_init(_malloc voidptr, _free voidptr,
	framebuffer &u32, width u64, height u64, pitch u64,
	red_mask_size u8, red_mask_shift u8,
	green_mask_size u8, green_mask_shift u8,
	blue_mask_size u8, blue_mask_shift u8,
	canvas &u32,
	ansi_colours &u32, ansi_bright_colours &u32,
	default_bg &u32, default_fg &u32,
	default_bg_bright &u32, default_fg_bright &u32,
	font voidptr, font_width u64, font_height u64, font_spacing u64,
	font_scale_x u64, font_scale_y u64,
	margin u64) voidptr

fn C.flanterm_write(voidptr Context, buf charptr, count u64)
fn C.flanterm_get_dimensions(voidptr Context, cols &u64, rows &u64)
fn C.flanterm_set_callback(voidptr Context, voidptr callback)
