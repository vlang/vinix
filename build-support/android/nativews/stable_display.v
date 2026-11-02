// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include <sys/ioctl.h>
#include <fcntl.h>

fn C.ioctl(i32, usize, ...) i32

// Linux fbdev copies the entire 160-byte UAPI record, even when the caller
// needs only xres/yres. Keep the color/timing fields and reserved tail present.
struct WsDisplayBitfield {
mut:
	offset u32
	length u32
	msb_right u32
}

struct WsDisplayScreenInfo {
mut:
	xres u32
	yres u32
	xres_virtual u32
	yres_virtual u32
	xoffset u32
	yoffset u32
	bits_per_pixel u32
	grayscale u32
	red WsDisplayBitfield
	green WsDisplayBitfield
	blue WsDisplayBitfield
	transp WsDisplayBitfield
	nonstd u32
	activate u32
	height u32
	width u32
	accel_flags u32
	pixclock u32
	left_margin u32
	right_margin u32
	upper_margin u32
	lower_margin u32
	hsync_len u32
	vsync_len u32
	sync u32
	vmode u32
	rotate u32
	colorspace u32
	reserved [4]u32
}

fn ws_framebuffer_size() (i32, i32) {
	// The guest's framebuffer mode is fixed for this session. Query physical
	// geometry rather than the Android app window, without reading any pixels.
	fd := C.open(c'/dev/fb0', C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 { return 0, 0 }
	defer { C.close(fd) }
	mut info := WsDisplayScreenInfo{}
	if C.ioctl(fd, usize(0x4600), &info) != 0 { return 0, 0 }
	if info.xres == 0 || info.yres == 0 || info.xres > 0x7fffffff || info.yres > 0x7fffffff {
		return 0, 0
	}
	return i32(info.xres), i32(info.yres)
}

fn ws_stable_display_size(e voidptr) voidptr {
	if e == unsafe { nil } || pending(e) { return unsafe { nil } }
	width, height := ws_framebuffer_size()
	c := cls(e, c'android/graphics/Point')
	if c == unsafe { nil } { return unsafe { nil } }
	unsafe {
		defer { Drop(slot(e, 23))(e, c) }
		init := Member(slot(e, 33))(e, c, c'<init>', c'(II)V')
		if init == nil || pending(e) { return nil }
		args := &Value(C.alloca(2 * sizeof(Value)))
		args[0] = Value{i: width}
		args[1] = Value{i: height}
		return ObjectCall(slot(e, 30))(e, c, init, args)
	}
}
