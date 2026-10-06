// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed-size raw RFB viewer. Native Xlib owns its layouts and image lifetime.
@[translated]
module vnccore

#define _DEFAULT_SOURCE 1
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
@[typedef]
struct C.Display {}

@[typedef]
struct C.XImage {
	data &char
}

@[typedef]
struct C.XKeyEvent {
	state u32
}

@[typedef]
struct C.XMotionEvent {
	state u32
	x     i32
	y     i32
}

@[typedef]
struct C.XButtonEvent {
	state  u32
	button u32
	x      i32
	y      i32
}

@[typedef]
struct C.XExposeEvent {
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

@[c_extern]
__global C.stderr voidptr

fn C.recv(i32, voidptr, usize, i32) isize
fn C.send(i32, voidptr, usize, i32) isize
fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.close(i32) i32
fn C.htons(u16) u16
fn C.htonl(u32) u32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.perror(&char)
fn C.calloc(usize, usize) &char
fn C.usleep(u32) i32
fn C.select(i32, &C.fd_set, voidptr, voidptr, voidptr) i32
fn C.FD_ZERO(&C.fd_set)
fn C.FD_SET(i32, &C.fd_set)
fn C.FD_ISSET(i32, &C.fd_set) i32
fn C.XOpenDisplay(&char) &C.Display
fn C.DefaultScreen(&C.Display) i32
fn C.RootWindow(&C.Display, i32) u64
fn C.BlackPixel(&C.Display, i32) u64
fn C.XCreateSimpleWindow(&C.Display, u64, i32, i32, u32, u32, u32, u64, u64) u64
fn C.XSelectInput(&C.Display, u64, isize) i32
fn C.XStoreName(&C.Display, u64, &char) i32
fn C.XMapWindow(&C.Display, u64) i32
fn C.XCreateGC(&C.Display, u64, u64, voidptr) voidptr
fn C.DefaultVisual(&C.Display, i32) voidptr
fn C.DefaultDepth(&C.Display, i32) i32
fn C.XCreateImage(&C.Display, voidptr, u32, i32, i32, &char, u32, u32, i32, i32) &C.XImage
fn C.XPutImage(&C.Display, u64, voidptr, &C.XImage, i32, i32, i32, i32, u32, u32) i32
fn C.XFlush(&C.Display) i32
fn C.XPending(&C.Display) i32
fn C.XNextEvent(&C.Display, &C.XEvent) i32
fn C.XLookupKeysym(&C.XKeyEvent, i32) u64
fn C.ConnectionNumber(&C.Display) i32
fn C.XDestroyImage(&C.XImage) i32
fn C.XFreeGC(&C.Display, voidptr) i32
fn C.XDestroyWindow(&C.Display, u64) i32
fn C.XCloseDisplay(&C.Display) i32

const view_width = u32(1024)
const view_height = u32(768)
const tile_width = u32(128)
const tile_height = u32(64)

fn read_all(fd i32, buffer voidptr, size usize) i32 {
	unsafe {
		mut out := &u8(buffer)
		mut remaining := size
		for remaining != 0 {
			count := C.recv(fd, out, remaining, 0)
			if count <= 0 {
				if count < 0 && C.errno == C.EINTR { continue }
				return -1
			}
			out += count
			remaining -= usize(count)
		}
		return 0
	}
}

fn write_all(fd i32, buffer voidptr, size usize) i32 {
	unsafe {
		mut input := &u8(buffer)
		mut remaining := size
		for remaining != 0 {
			count := C.send(fd, input, remaining, 0)
			if count <= 0 {
				if count < 0 && C.errno == C.EINTR { continue }
				return -1
			}
			input += count
			remaining -= usize(count)
		}
		return 0
	}
}

fn be16(bytes &u8) u32 {
	unsafe { return u32(bytes[0]) << 8 | u32(bytes[1])
	 }
}

fn be32(bytes &u8) u32 {
	unsafe { return u32(bytes[0]) << 24 | u32(bytes[1]) << 16 | u32(bytes[2]) << 8 | u32(bytes[3])
	 }
}

fn put16(out &u8, value u32) {
	unsafe {
		mut p := &u8(voidptr(out))
		p[0] = u8(value >> 8)
		p[1] = u8(value)
	}
}

fn put32(out &u8, value u32) {
	unsafe {
		mut p := &u8(voidptr(out))
		p[0] = u8(value >> 24)
		p[1] = u8(value >> 16)
		p[2] = u8(value >> 8)
		p[3] = u8(value)
	}
}

fn connect_vnc() i32 {
	unsafe {
		fd := C.socket(C.AF_INET, C.SOCK_STREAM, 0)
		if fd < 0 { return -1 }
		mut address := C.sockaddr_in{}
		C.memset(&address, 0, sizeof(address))
		address.sin_family = u16(C.AF_INET)
		address.sin_port = C.htons(5901)
		address.sin_addr.s_addr = C.htonl(C.INADDR_LOOPBACK)
		if C.connect(fd, voidptr(&address), u32(sizeof(address))) != 0 {
			C.close(fd)
			return -1
		}
		return fd
	}
}

fn negotiate(fd i32, width &u32, height &u32) i32 {
	unsafe {
		mut version := [12]u8{}
		mut count := u8(0)
		mut types := [255]u8{}
		mut result := [4]u8{}
		mut setup := [24]u8{}
		mut name := [4096]char{}
		pixel_format := [u8(0), 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0,
			0]!
		encodings := [u8(2), 0, 0, 2, 0, 0, 0, 0, 255, 255, 255, 33]!
		if read_all(fd, &version[0], sizeof(version)) != 0 || C.memcmp(&version[0], c'RFB 003.008\n', sizeof(version)) != 0
			|| write_all(fd, c'RFB 003.008\n', 12) != 0 || read_all(fd, &count, 1) != 0 || count == 0 || read_all(fd, &types[0], count) != 0 {
			return -1
		}
		mut supports_none := false
		for i := u32(0); i < u32(count); i++ { supports_none = supports_none || types[i] == 1 }
		if !supports_none { return -1 }
		count = 1
		if write_all(fd, &count, 1) != 0 || read_all(fd, &result[0], 4) != 0 || be32(&result[0]) != 0 {
			return -1
		}
		count = 1
		if write_all(fd, &count, 1) != 0 || read_all(fd, &setup[0], sizeof(setup)) != 0 {
			return -1
		}
		*width = be16(&setup[0])
		*height = be16(&setup[2])
		name_length := be32(&setup[20])
		if *width == 0 || *height == 0 || *width > view_width || *height > view_height || name_length >= sizeof(name)
			|| read_all(fd, &name[0], name_length) != 0 || write_all(fd, &pixel_format[0], sizeof(pixel_format)) != 0 || write_all(fd, &encodings[0], sizeof(encodings)) != 0 {
			return -1
		}
		name[name_length] = 0
		C.fprintf(C.stderr, c'vinix-vnc-window: connected to %s (%ux%u)\n', &name[0], *width, *height)
		return 0
	}
}

fn request_update(fd i32, width u32, height u32, incremental i32) i32 {
	unsafe {
		mut request := [u8(3), 0, 0, 0, 0, 0, 0, 0, 0, 0]!
		request[1] = u8(incremental)
		put16(&request[6], width)
		put16(&request[8], height)
		return write_all(fd, &request[0], sizeof(request))
	}
}

fn paint(display &C.Display, window u64, gc voidptr, image &C.XImage, x u32, y u32, width u32, height u32) {
	end_x := x + width
	end_y := y + height
	for row := y; row < end_y; row += tile_height {
		height_left := end_y - row
		height_tile := if height_left < tile_height { height_left } else { tile_height }
		for column := x; column < end_x; column += tile_width {
			width_left := end_x - column
			width_tile := if width_left < tile_width { width_left } else { tile_width }
			C.XPutImage(display, window, gc, image, i32(column), i32(row), i32(column), i32(row), width_tile, height_tile)
		}
	}
	C.XFlush(display)
}

fn receive_update(fd i32, display &C.Display, window u64, gc voidptr, image &C.XImage, width &u32, height &u32, resized &i32) i32 {
	unsafe {
		mut kind := u8(0)
		mut header := [3]u8{}
		mut rect := [12]u8{}
		if read_all(fd, &kind, 1) != 0 { return -1 }
		if kind == 2 { return 0 }
		if kind == 3 {
			mut text_header := [7]u8{}
			mut discard := [256]u8{}
			if read_all(fd, &text_header[0], sizeof(text_header)) != 0 { return -1 }
			mut left := be32(&text_header[3])
			if left > 1024 * 1024 { return -1 }
			for left != 0 {
				chunk := if left > sizeof(discard) { u32(sizeof(discard)) } else { left }
				if read_all(fd, &discard[0], chunk) != 0 { return -1 }
				left -= chunk
			}
			return 0
		}
		if kind != 0 || read_all(fd, &header[0], sizeof(header)) != 0 { return -1 }
		rectangles := be16(&header[1])
		for i := u32(0); i < rectangles; i++ {
			if read_all(fd, &rect[0], sizeof(rect)) != 0 { return -1 }
			x := be16(&rect[0])
			y := be16(&rect[2])
			w := be16(&rect[4])
			h := be16(&rect[6])
			encoding := be32(&rect[8])
			if encoding == u32(0xffffff21) {
				if w == 0 || h == 0 || w > view_width || h > view_height { return -1 }
				*width = w
				*height = h
				*resized = 1
				C.fprintf(C.stderr, c'vinix-vnc-window: framebuffer %ux%u\n', w, h)
				continue
			}
			if encoding != 0 || w == 0 || h == 0 || x + w > view_width || y + h > view_height || x + w > *width || y + h > *height {
				return -1
			}
			for row := u32(0); row < h; row++ {
				dest := &u8(image.data) + ((usize(y + row) * view_width + x) * 4)
				if read_all(fd, dest, usize(w) * 4) != 0 { return -1 }
			}
			paint(display, window, gc, image, x, y, w, h)
		}
		return 0
	}
}

fn send_key(fd i32, symbol u64, down i32) i32 {
	unsafe {
		mut event := [u8(4), 0, 0, 0, 0, 0, 0, 0]!
		event[1] = u8(down)
		put32(&event[4], u32(symbol))
		return write_all(fd, &event[0], sizeof(event))
	}
}

fn send_pointer(fd i32, mask u32, x i32, y i32) i32 {
	unsafe {
		mut event := [u8(5), 0, 0, 0, 0, 0]!
		final_x := if x < 0 {
			0
		} else if x >= i32(view_width) {
			i32(view_width) - 1
		} else {
			x
		}
		final_y := if y < 0 {
			0
		} else if y >= i32(view_height) {
			i32(view_height) - 1
		} else {
			y
		}
		event[1] = u8(mask)
		put16(&event[2], u32(final_x))
		put16(&event[4], u32(final_y))
		return write_all(fd, &event[0], sizeof(event))
	}
}

fn buttons(state u32) u32 {
	return (if state & u32(C.Button1Mask) != 0 { u32(1) } else { u32(0) }) |
		(if state & u32(C.Button2Mask) != 0 { u32(2) } else { u32(0) }) |
		(if state & u32(C.Button3Mask) != 0 { u32(4) } else { u32(0) })
}

fn process_events(fd i32, display &C.Display, window u64, gc voidptr, image &C.XImage) bool {
	unsafe {
		for C.XPending(display) != 0 {
			mut event := C.XEvent{}
			C.XNextEvent(display, &event)
			if event.@type == C.Expose && event.xexpose.count == 0 {
				paint(display, window, gc, image, 0, 0, view_width, view_height)
			} else if event.@type == C.KeyPress || event.@type == C.KeyRelease {
				symbol := C.XLookupKeysym(&event.xkey, 0)
				if symbol != C.NoSymbol && send_key(fd, symbol, i32(event.@type == C.KeyPress)) != 0 {
					return false
				}
			} else if event.@type == C.MotionNotify {
				if send_pointer(fd, buttons(event.xmotion.state), event.xmotion.x, event.xmotion.y) != 0 {
					return false
				}
			} else if event.@type == C.ButtonPress || event.@type == C.ButtonRelease {
				mut mask := buttons(event.xbutton.state)
				bit := if event.xbutton.button == C.Button1 {
					u32(1)
				} else if event.xbutton.button == C.Button2 {
					u32(2)
				} else if event.xbutton.button == C.Button3 {
					u32(4)
				} else {
					u32(0)
				}
				mask = if event.@type == C.ButtonPress { mask | bit } else { mask & ~bit }
				if send_pointer(fd, mask, event.xbutton.x, event.xbutton.y) != 0 { return false }
			}
		}
		return true
	}
}

@[export: 'main']
pub fn viewer() i32 {
	unsafe {
		display := C.XOpenDisplay(nil)
		if display == nil {
			C.fprintf(C.stderr, c'vinix-vnc-window: cannot open X11 display\n')
			return 1
		}
		screen := C.DefaultScreen(display)
		window := C.XCreateSimpleWindow(display, C.RootWindow(display, screen), 0, 0, view_width, view_height, 0, 0, C.BlackPixel(display, screen))
		C.XSelectInput(display, window, C.ExposureMask | C.KeyPressMask | C.KeyReleaseMask | C.ButtonPressMask | C.ButtonReleaseMask | C.PointerMotionMask)
		C.XStoreName(display, window, c'Vinix in QEMU')
		C.XMapWindow(display, window)
		gc := C.XCreateGC(display, window, 0, nil)
		pixels := C.calloc(usize(view_width) * view_height, 4)
		if pixels == nil { return 1 }
		image := C.XCreateImage(display, C.DefaultVisual(display, screen), u32(C.DefaultDepth(display, screen)), C.ZPixmap, 0, pixels, view_width, view_height, 32, i32(view_width) * 4)
		if image == nil { return 1 }
		mut fd := i32(-1)
		for attempt := u32(0); attempt < 100; attempt++ {
			fd = connect_vnc()
			if fd >= 0 { break }
			C.usleep(100000)
		}
		if fd < 0 {
			C.perror(c'vinix-vnc-window: connect')
			return 1
		}
		mut width := u32(0)
		mut height := u32(0)
		if negotiate(fd, &width, &height) != 0 || request_update(fd, width, height, 0) != 0 {
			C.fprintf(C.stderr, c'vinix-vnc-window: RFB handshake failed\n')
			return 1
		}
		for {
			if !process_events(fd, display, window, gc, image) { break }
			mut readable := C.fd_set{}
			C.FD_ZERO(&readable)
			C.FD_SET(fd, &readable)
			C.FD_SET(C.ConnectionNumber(display), &readable)
			max_fd := if fd > C.ConnectionNumber(display) {
				fd
			} else {
				C.ConnectionNumber(display)
			}
			ready := C.select(max_fd + 1, &readable, nil, nil, nil)
			if ready < 0 {
				if C.errno == C.EINTR { continue }
				break
			}
			if C.FD_ISSET(fd, &readable) != 0 {
				mut resized := i32(0)
				if receive_update(fd, display, window, gc, image, &width, &height, &resized) != 0 || request_update(fd, width, height, i32(resized == 0)) != 0 {
					break
				}
			}
		}
		C.fprintf(C.stderr, c'vinix-vnc-window: disconnected\n')
		C.close(fd)
		C.XDestroyImage(image)
		C.XFreeGC(display, gc)
		C.XDestroyWindow(display, window)
		C.XCloseDisplay(display)
		return 0
	}
}
