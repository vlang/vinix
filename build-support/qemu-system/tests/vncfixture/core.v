// SPDX-License-Identifier: GPL-2.0-or-later
// Independent raw-RFB/Xlib model: exact protocol bytes and resource ownership.
@[translated]
module vncfixture

#define _DEFAULT_SOURCE 1
#define XLIB_ILLEGAL_ACCESS
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
@[typedef]
struct C.Display {
	fd             i32
	default_screen i32
	nscreens       i32
	screens        &C.Screen
}

@[typedef]
struct C.Screen {
	root        u64
	black_pixel u64
	root_depth  i32
	root_visual voidptr
}

struct ImageFunctions {
	destroy_image fn (&C.XImage) i32
}

@[typedef]
struct C.XImage {
	data &char
	f    ImageFunctions
}

@[typedef]
struct C.XKeyEvent {
	@type i32
	state u32
}

@[typedef]
struct C.XMotionEvent {
	@type i32
	state u32
	x     i32
	y     i32
}

@[typedef]
struct C.XButtonEvent {
	@type  i32
	state  u32
	button u32
	x      i32
	y      i32
}

@[typedef]
struct C.XExposeEvent {
	@type i32
	count i32
}

@[typedef]
struct C.XEvent {
	@type   i32
	xkey    C.XKeyEvent
	xmotion C.XMotionEvent
	xbutton C.XButtonEvent
	xexpose C.XExposeEvent
}

@[typedef]
struct C.fd_set {}

struct C.in_addr {
	s_addr u32
}

struct C.sockaddr_in {
	sin_family u16
	sin_port   u16
	sin_addr   C.in_addr
}

@[c_extern]
__global C.errno i32

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.calloc(usize, usize) &char
fn C.free(voidptr)
fn C.printf(&char, ...voidptr) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.htons(u16) u16
fn C.htonl(u32) u32
fn C.FD_ZERO(&C.fd_set)
fn C.FD_SET(i32, &C.fd_set)
fn C.FD_ISSET(i32, &C.fd_set) i32
fn C.vnf_viewer() i32
fn C.vnf_destroy_image(&C.XImage) i32

$if vnc_guest ? {
	fn C.open(&char, i32, ...voidptr) i32
	fn C.dup2(i32, i32) i32
	fn C.close(i32) i32
	fn C.write(i32, voidptr, usize) isize
	fn C.pause() i32
}

struct Model {
mut:
	mode        i32
	input       [65536]u8
	length      usize
	consumed    usize
	writes      usize
	write_hash  u64
	trace_hash  u64
	calls       u32
	failures    u32
	recv_calls  u32
	send_calls  u32
	selects     u32
	events      u32
	displays    i32
	windows     i32
	gcs         i32
	sockets     i32
	allocations i32
	pixels      &char
	pixel_hash  u64
	connects    u32
	sleeps      u32
	paints      u32
	destroys    u32
}

__global vnf_model Model
__global vnf_display C.Display
__global vnf_screen C.Screen
__global vnf_image C.XImage

fn check(ok bool) { if !ok { vnf_model.failures++ } }

fn trace(code u64, a u64, b u64) {
	vnf_model.calls++
	vnf_model.trace_hash = (vnf_model.trace_hash ^ code) * 1099511628211
	vnf_model.trace_hash = (vnf_model.trace_hash ^ a) * 1099511628211
	vnf_model.trace_hash = (vnf_model.trace_hash ^ b) * 1099511628211
}

fn byte(value u8) {
	unsafe {
		vnf_model.input[vnf_model.length] = value
		vnf_model.length++
	}
}

fn word(value u32) {
	byte(u8(value >> 8))
	byte(u8(value))
}

fn long_word(value u32) {
	byte(u8(value >> 24))
	byte(u8(value >> 16))
	byte(u8(value >> 8))
	byte(u8(value))
}

fn bytes(value &char, count usize) {
	unsafe { for i := usize(0); i < count; i++ { byte(u8(value[i])) }
	 }
}

fn rectangle(x u32, y u32, w u32, h u32, encoding u32) {
	word(x)
	word(y)
	word(w)
	word(h)
	long_word(encoding)
}

fn setup(mode i32) {
	unsafe {
		C.memset(&vnf_model, 0, sizeof(Model))
		C.memset(&vnf_display, 0, sizeof(C.Display))
		C.memset(&vnf_screen, 0, sizeof(C.Screen))
		C.memset(&vnf_image, 0, sizeof(C.XImage))
		vnf_model.mode = mode
		vnf_model.trace_hash = 1469598103934665603
		vnf_model.write_hash = 1469598103934665603
		vnf_display.fd = 7
		vnf_display.nscreens = 1
		vnf_display.screens = &vnf_screen
		vnf_screen.root = 1
		vnf_screen.black_pixel = 0x123456
		vnf_screen.root_depth = 24
		vnf_screen.root_visual = voidptr(usize(17))
		vnf_image.f.destroy_image = C.vnf_destroy_image
		bytes(if mode == 6 { c'RFB 003.007\n' } else { c'RFB 003.008\n' }, 12)
		byte(if mode == 7 { u8(0) } else { u8(3) })
		byte(2)
		byte(if mode == 8 { u8(5) } else { u8(1) })
		byte(9)
		long_word(if mode == 9 { u32(1) } else { u32(0) })
		word(if mode == 10 {
			u32(0)
		} else if mode == 11 {
			u32(1025)
		} else if mode == 27 {
			u32(256)
		} else {
			u32(8)
		})
		word(if mode == 27 { u32(128) } else { u32(4) })
		for _ in 0 .. 16 { byte(0) }
		long_word(if mode == 12 { u32(4096) } else { u32(4) })
		bytes(c'QEMU', 4)
		if mode == 17 {
			byte(42)
		} else if mode == 18 {
			byte(2)
		} else if mode == 19 || mode == 20 {
			byte(3)
			byte(0)
			byte(0)
			byte(0)
			long_word(if mode == 20 { u32(1048577) } else { u32(257) })
			for i in 0 .. 257 { byte(u8(i)) }
		} else {
			byte(0)
			byte(0)
			word(1)
			if mode == 21 || mode == 22 {
				rectangle(0, 0, if mode == 22 { u32(0) } else { u32(6) }, 3, 0xffffff21)
			} else {
				w := if mode == 27 {
					u32(129)
				} else if mode == 14 {
					u32(9)
				} else {
					u32(2)
				}
				h := if mode == 27 { u32(65) } else { u32(2) }
				rectangle(if mode == 15 { u32(1024) } else { u32(1) }, 1, w, h, if mode == 16 {
					u32(1)
				} else {
					u32(0)
				})
				for i := u32(0); i < w * h * 4; i++ { byte(u8(i * 13 + 7)) }
			}
		}
		if mode == 13 { vnf_model.length = 11 }
	}
}

@[export: 'vnf_XOpenDisplay']
pub fn open_display(name &char) &C.Display {
	check(name == nil)
	trace(1, 0, 0)
	if vnf_model.mode == 1 { return unsafe { nil } }
	vnf_model.displays++
	return &vnf_display
}

@[export: 'vnf_XCreateSimpleWindow']
pub fn create_window(display &C.Display, parent u64, x i32, y i32, width u32, height u32, border u32, color u64, background u64) u64 {
	check(usize(display) == usize(&vnf_display) && parent == 1 && x == 0 && y == 0 && width == 1024 && height == 768 && border == 0 && color == 0 && background == 0x123456)
	trace(2, width, height)
	vnf_model.windows++
	return 2
}

@[export: 'vnf_XSelectInput']
pub fn select_input(_display &C.Display, window u64, mask isize) i32 {
	check(window == 2 && mask == C.ExposureMask | C.KeyPressMask | C.KeyReleaseMask | C.ButtonPressMask | C.ButtonReleaseMask | C.PointerMotionMask)
	trace(3, u64(mask), 0)
	return 0
}

@[export: 'vnf_XStoreName']
pub fn name_window(_display &C.Display, window u64, name &char) i32 {
	check(window == 2 && C.strcmp(name, c'Vinix in QEMU') == 0)
	trace(4, 0, 0)
	return 0
}

@[export: 'vnf_XMapWindow']
pub fn map_window(_display &C.Display, _window u64) i32 {
	trace(5, 0, 0)
	return 0
}

@[export: 'vnf_XCreateGC']
pub fn create_gc(_display &C.Display, _window u64, mask u64, values voidptr) voidptr {
	check(mask == 0 && values == nil)
	trace(6, 0, 0)
	vnf_model.gcs++
	return voidptr(usize(19))
}

@[export: 'vnf_calloc']
pub fn allocate(n usize, size usize) &char {
	check(n == 1024 * 768 && size == 4)
	trace(7, n, size)
	if vnf_model.mode == 2 { return unsafe { nil } }
	vnf_model.pixels = C.calloc(n, size)
	check(vnf_model.pixels != nil)
	vnf_model.allocations++
	return vnf_model.pixels
}

@[export: 'vnf_XCreateImage']
pub fn create_image(_display &C.Display, visual voidptr, depth u32, format i32, offset i32, data &char, width u32, height u32, pad i32, stride i32) &C.XImage {
	check(visual == voidptr(usize(17)) && depth == 24 && format == C.ZPixmap && offset == 0 && data == vnf_model.pixels && width == 1024 && height == 768 && pad == 32 && stride == 4096)
	trace(8, width, height)
	if vnf_model.mode == 3 { return unsafe { nil } }
	vnf_image.data = data
	return &vnf_image
}

@[export: 'vnf_socket']
pub fn socket(domain i32, kind i32, protocol i32) i32 {
	check(domain == C.AF_INET && kind == C.SOCK_STREAM && protocol == 0)
	trace(9, 0, 0)
	if vnf_model.mode == 4 {
		C.errno = C.ECONNREFUSED
		return -1
	}
	vnf_model.sockets++
	return 9
}

@[export: 'vnf_connect']
pub fn connect(fd i32, address voidptr, length u32) i32 {
	unsafe {
		p := &C.sockaddr_in(address)
		check(fd == 9 && length == sizeof(C.sockaddr_in) && p.sin_family == C.AF_INET && p.sin_port == C.htons(5901) && p.sin_addr.s_addr == C.htonl(C.INADDR_LOOPBACK))
	}
	trace(10, 0, 0)
	vnf_model.connects++
	if vnf_model.mode == 5 || (vnf_model.mode == 28 && vnf_model.connects < 3) {
		C.errno = C.ECONNREFUSED
		return -1
	}
	return 0
}

@[export: 'vnf_close']
pub fn close(fd i32) i32 {
	check(fd == 9 && vnf_model.sockets == 1)
	trace(11, 0, 0)
	vnf_model.sockets--
	return 0
}

@[export: 'vnf_usleep']
pub fn sleep(usec u32) i32 {
	check(usec == 100000)
	trace(12, 0, 0)
	vnf_model.sleeps++
	return 0
}

@[export: 'vnf_recv']
pub fn recv(fd i32, buffer voidptr, size usize, flags i32) isize {
	check(fd == 9 && flags == 0)
	vnf_model.recv_calls++
	if vnf_model.mode == 23 && vnf_model.recv_calls % 3 == 1 {
		C.errno = C.EINTR
		return -1
	}
	if vnf_model.consumed == vnf_model.length { return 0 }
	mut n := vnf_model.length - vnf_model.consumed
	if n > size { n = size }
	if (vnf_model.mode == 23 || vnf_model.mode == 29) && n > 7 { n = 7 }
	unsafe { C.memcpy(buffer, &vnf_model.input[vnf_model.consumed], n) }
	vnf_model.consumed += n
	return isize(n)
}

@[export: 'vnf_send']
pub fn send(fd i32, buffer voidptr, size usize, flags i32) isize {
	check(fd == 9 && flags == 0)
	vnf_model.send_calls++
	if vnf_model.mode == 30 && vnf_model.send_calls % 3 == 1 {
		C.errno = C.EINTR
		return -1
	}
	if vnf_model.mode == 31 || (vnf_model.mode == 24 && vnf_model.send_calls > 6) {
		C.errno = C.EPIPE
		return -1
	}
	mut n := size
	if (vnf_model.mode == 30 || vnf_model.mode == 29) && n > 5 { n = 5 }
	unsafe {
		p := &u8(buffer)
		for i := usize(0); i < n; i++ {
			vnf_model.write_hash = (vnf_model.write_hash ^ p[i]) * 1099511628211
		}
	}
	vnf_model.writes += n
	return isize(n)
}

@[export: 'vnf_select']
pub fn select(n i32, read &C.fd_set, write voidptr, except voidptr, timeout voidptr) i32 {
	check(n == 10 && C.FD_ISSET(9, read) != 0 && C.FD_ISSET(7, read) != 0 && write == nil && except == nil && timeout == nil)
	vnf_model.selects++
	if vnf_model.mode == 32 && vnf_model.selects == 1 {
		C.errno = C.EINTR
		return -1
	}
	if vnf_model.mode == 33 {
		C.errno = C.EINVAL
		return -1
	}
	C.FD_ZERO(read)
	C.FD_SET(9, read)
	return 1
}

@[export: 'vnf_XPutImage']
pub fn put_image(_display &C.Display, window u64, gc voidptr, image &C.XImage, sx i32, sy i32, dx i32, dy i32, width u32, height u32) i32 {
	check(window == 2 && gc == voidptr(usize(19)) && usize(image) == usize(&vnf_image) && sx == dx && sy == dy && width <= 128 && height <= 64)
	trace(13, u64(u32(sx)) << 32 | u32(sy), u64(width) << 32 | height)
	vnf_model.paints++
	return 0
}

@[export: 'vnf_XFlush']
pub fn flush(_display &C.Display) i32 {
	trace(14, 0, 0)
	return 0
}

@[export: 'vnf_XPending']
pub fn pending(_display &C.Display) i32 {
	return if (vnf_model.mode == 0 || vnf_model.mode == 24 || vnf_model.mode == 25 || vnf_model.mode == 26) && vnf_model.events < 7 {
		i32(1)
	} else {
		i32(0)
	}
}

@[export: 'vnf_XNextEvent']
pub fn event(_display &C.Display, out &C.XEvent) i32 {
	unsafe {
		C.memset(out, 0, sizeof(C.XEvent))
		mut p := &C.XEvent(voidptr(out))
		match vnf_model.events {
			0 {
				p.xexpose.@type = C.Expose
				p.xexpose.count = 1
			}
			1 {
				p.xexpose.@type = C.Expose
				p.xexpose.count = 0
			}
			2 { p.xkey.@type = C.KeyPress }
			3 { p.xkey.@type = C.KeyRelease }
			4 {
				p.xmotion.@type = C.MotionNotify
				p.xmotion.state = C.Button1Mask | C.Button3Mask
				p.xmotion.x = -7
				p.xmotion.y = 9999
			}
			5 {
				p.xbutton.@type = C.ButtonPress
				p.xbutton.button = C.Button2
				p.xbutton.state = C.Button1Mask
				p.xbutton.x = 12
				p.xbutton.y = 34
			}
			else {
				p.xbutton.@type = C.ButtonRelease
				p.xbutton.button = C.Button1
				p.xbutton.state = C.Button1Mask | C.Button2Mask
				p.xbutton.x = 1024
				p.xbutton.y = -1
			}
		}
		vnf_model.events++
		return 0
	}
}

@[export: 'vnf_XLookupKeysym']
pub fn keysym(_event &C.XKeyEvent, index i32) u64 {
	check(index == 0)
	return if vnf_model.mode == 25 { u64(C.NoSymbol) } else { u64(0x10020ac) }
}

@[export: 'vnf_destroy_image']
pub fn destroy_image(image &C.XImage) i32 {
	check(usize(image) == usize(&vnf_image) && image.data == vnf_model.pixels && vnf_model.allocations == 1)
	trace(15, 0, 0)
	vnf_model.pixel_hash = image_hash()
	C.free(vnf_model.pixels)
	vnf_model.pixels = unsafe { nil }
	vnf_model.allocations--
	vnf_model.destroys++
	return 0
}

@[export: 'vnf_XFreeGC']
pub fn free_gc(_display &C.Display, gc voidptr) i32 {
	check(gc == voidptr(usize(19)) && vnf_model.gcs == 1)
	trace(16, 0, 0)
	vnf_model.gcs--
	return 0
}

@[export: 'vnf_XDestroyWindow']
pub fn destroy_window(_display &C.Display, window u64) i32 {
	check(window == 2 && vnf_model.windows == 1)
	trace(17, 0, 0)
	vnf_model.windows--
	return 0
}

@[export: 'vnf_XCloseDisplay']
pub fn close_display(display &C.Display) i32 {
	check(usize(display) == usize(&vnf_display) && vnf_model.displays == 1)
	trace(18, 0, 0)
	vnf_model.displays--
	return 0
}

fn image_hash() u64 {
	mut value := u64(1469598103934665603)
	mode := vnf_model.mode
	raw := mode == 0 || mode == 23 || (mode >= 25 && mode <= 30) || mode == 32
	w := if mode == 27 { i32(129) } else { i32(2) }
	h := if mode == 27 { i32(65) } else { i32(2) }
	unsafe {
		for i in 0 .. 1024 * 768 * 4 {
			b := u8(vnf_model.pixels[i])
			value = (value ^ b) * 1099511628211
			x := i32((i / 4) % 1024)
			y := i32(i / 4096)
			expected := if raw && x >= 1 && x < 1 + w && y >= 1 && y < 1 + h {
				u8((((y - 1) * w + x - 1) * 4 + i32(i % 4)) * 13 + 7)
			} else {
				u8(0)
			}
			check(b == expected)
		}
	}
	return value
}

fn run_cases() i32 {
	mut failed := false
	for mode := i32(0); mode < 34; mode++ {
		setup(mode)
		result := C.vnf_viewer()
		mut pixel_hash := vnf_model.pixel_hash
		if vnf_model.pixels != nil { pixel_hash = image_hash() }
		expected := if (mode >= 1 && mode <= 13) || mode == 31 { i32(1) } else { i32(0) }
		check(result == expected)
		if result == 0 {
			check(vnf_model.displays == 0 && vnf_model.windows == 0 && vnf_model.gcs == 0 && vnf_model.sockets == 0 && vnf_model.allocations == 0 && vnf_model.destroys == 1)
		}
		C.printf(c'CASE %d result=%d calls=%u trace=%lx writes=%lu bytes=%lx read=%lu recv=%u send=%u select=%u events=%u paint=%u retry=%u sleep=%u owned=%d,%d,%d,%d,%d errors=%u pixels=%lx\n', mode, result, vnf_model.calls, usize(vnf_model.trace_hash), vnf_model.writes, usize(vnf_model.write_hash), vnf_model.consumed, vnf_model.recv_calls, vnf_model.send_calls, vnf_model.selects, vnf_model.events, vnf_model.paints, vnf_model.connects, vnf_model.sleeps, vnf_model.displays, vnf_model.windows, vnf_model.gcs, vnf_model.sockets, vnf_model.allocations, vnf_model.failures, usize(pixel_hash))
		if vnf_model.failures != 0 { failed = true }
		if vnf_model.pixels != nil { C.free(vnf_model.pixels) }
	}
	if !failed { C.printf(c'VNC MODEL PASS\n') }
	return i32(failed)
}

@[export: 'main']
pub fn main_entry() i32 {
	$if vnc_guest ? {
		unsafe {
			fd := C.open(c'/dev/com1', 2)
			if fd >= 0 {
				C.dup2(fd, 1)
				C.dup2(fd, 2)
				C.close(fd)
			}
		}
	}
	result := run_cases()
	$if vnc_guest ? {
		C.fflush(unsafe { nil })
		for { C.pause() }
	}
	return result
}
