// SPDX-License-Identifier: MIT
module windowfb

import os as _

#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.munmap(voidptr, usize) int
fn C.fstat(int, &C.stat) int

pub const surface_header_size = 48
pub const max_surface_bytes = 128 * 1024 * 1024

pub fn surface_size(width int, height int) !int {
	if width < 64 || height < 64 || width > 8192 || height > 8192 {
		return error('invalid framebuffer dimensions')
	}
	size := i64(surface_header_size) + i64(width) * height * 8
	if size > max_surface_bytes { return error('framebuffer is too large') }
	return int(size)
}

// The client draws only in the back buffer. PRESENT copies it to the front;
// FRAME_DONE releases the back buffer for its next frame. No client-side
// atomics, toolkit, or compiler-specific struct layout are needed.
pub struct Surface {
pub:
	width  int
	height int
	stride int
	back   &u32 = unsafe { nil }
mut:
	mapping voidptr
	size    int
}

fn map_fd(fd int, width int, height int) !Surface {
	size := surface_size(width, height)!
	mapping := C.mmap(unsafe { nil }, usize(size), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	if mapping == voidptr(-1) { return error('cannot map framebuffer') }
	return Surface{
		width:   width
		height:  height
		stride:  width * 4
		mapping: mapping
		size:    size
		back:    unsafe { &u32(usize(mapping) + usize(surface_header_size + width * height * 4)) }
	}
}

pub fn create_surface(path string, width int, height int) !Surface {
	size := surface_size(width, height)!
	fd := C.open(&char(path.str), C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot create framebuffer') }
	defer { C.close(fd) }
	if C.ftruncate(fd, i64(size)) != 0 {
		C.unlink(&char(path.str))
		return error('cannot size framebuffer')
	}
	mut surface := map_fd(fd, width, height) or {
		C.unlink(&char(path.str))
		return err
	}
	surface.initialize()
	return surface
}

pub fn open_surface(path string, width int, height int) !Surface {
	size := surface_size(width, height)!
	fd := C.open(&char(path.str), C.O_RDWR | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open framebuffer') }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_size != size {
		return error('invalid framebuffer file size')
	}
	return map_fd(fd, width, height)
}

fn (mut s Surface) initialize() {
	p := unsafe { &u8(s.mapping) }
	put_u32(p, 0, 0x31534656) // Existing compositor VSF1 image reader.
	put_u32(p, 4, 1)
	put_u32(p, 8, surface_header_size)
	put_u32(p, 12, u32(s.width))
	put_u32(p, 16, u32(s.height))
	put_u32(p, 20, u32(s.stride))
	put_u32(p, 24, 1)
	put_u32(p, 28, 0)
	put_u32(p, 32, ~u32(0))
	put_u32(p, 36, 0)
	put_u32(p, 40, u32(s.stride * s.height))
	put_u32(p, 44, 0)
}

pub fn (mut s Surface) copy_frame() {
	if s.mapping == unsafe { nil } { return }
	s.initialize()
	unsafe { C.memcpy(&u8(usize(s.mapping) + surface_header_size), s.back, usize(s.stride * s.height)) }
}

pub fn (mut s Surface) close() {
	if s.mapping != unsafe { nil } {
		C.munmap(s.mapping, usize(s.size))
		s.mapping = unsafe { nil }
	}
}
