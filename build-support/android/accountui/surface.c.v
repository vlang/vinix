// SPDX-License-Identifier: GPL-2.0-or-later
module main

import sync.stdatomic as _
import desktop.windowfb

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

fn C.fstat(int, &C.stat) int

const source_magic = u32(0x31534656)
const source_header = 48
const no_reader = ~u32(0)

struct Source {
	width       int
	height      int
	stride      int
	buffer_size int
mut:
	mapping voidptr
	size    int
}

fn open_source(fd int) !Source {
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || flags & C.O_ACCMODE != C.O_RDWR {
		return error('account UI surface must be writable for the reader handshake')
	}
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || u32(info.st_mode) & C.S_IFMT != C.S_IFREG
		|| info.st_size < source_header || info.st_size > windowfb.max_surface_bytes {
		return error('invalid account UI surface file')
	}
	size := int(info.st_size)
	mapping := C.mmap(unsafe { nil }, usize(size), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	if mapping == voidptr(-1) { return error('cannot map account UI surface') }
	mut accepted := false
	defer { if !accepted { C.munmap(mapping, usize(size)) } }
	p := unsafe { &u8(mapping) }
	if windowfb.take_u32(p, 0) != source_magic || windowfb.take_u32(p, 4) != 1
		|| windowfb.take_u32(p, 8) != source_header || windowfb.take_u32(p, 24) != 1 {
		return error('invalid account UI surface header')
	}
	width := int(windowfb.take_u32(p, 12))
	height := int(windowfb.take_u32(p, 16))
	stride := int(windowfb.take_u32(p, 20))
	buffer_size := int(windowfb.take_u32(p, 40))
	_ = windowfb.surface_size(width, height)!
	if stride < width * 4 || stride > 8192 * 4 || stride % 4 != 0
		|| i64(stride) * height != buffer_size || i64(source_header) + 2 * i64(buffer_size) != size {
		return error('invalid account UI surface layout')
	}
	if C.atomic_load_u32(unsafe { p + 28 }) > 1
		|| C.atomic_load_u32(unsafe { p + 32 }) != no_reader {
		return error('account UI surface already has a reader or invalid active buffer')
	}
	// Cache all layout values. The producer never controls pointer arithmetic
	// after this validation, even if it subsequently changes its header.
	accepted = true
	return Source{width, height, stride, buffer_size, mapping, size}
}

fn (s &Source) copy_to(destination &windowfb.Surface) !bool {
	if destination.width != s.width || destination.height != s.height {
		return error('account UI framebuffer geometry changed')
	}
	p := unsafe { &u8(s.mapping) }
	active_ptr := unsafe { p + 28 }
	reader_ptr := unsafe { p + 32 }
	// A release/acquire claim matches nativews.ws_render. Bounded retries
	// keep even a rapidly toggling publisher from monopolizing this process.
	for _ in 0 .. 8 {
		active := C.atomic_load_u32(active_ptr)
		if active > 1 { return error('invalid account UI active buffer') }
		C.atomic_store_u32(reader_ptr, active)
		if C.atomic_load_u32(active_ptr) != active {
			C.atomic_store_u32(reader_ptr, no_reader)
			continue
		}
		defer { C.atomic_store_u32(reader_ptr, no_reader) }
		pixels := unsafe { p + source_header + int(active) * s.buffer_size }
		for row in 0 .. s.height {
			unsafe {
				C.memcpy(&u8(destination.back) + row * destination.stride,
					pixels + row * s.stride, usize(s.width * 4))
			}
		}
		return true
	}
	return false
}

fn (mut s Source) close() {
	if s.mapping != unsafe { nil } {
		C.munmap(s.mapping, usize(s.size))
		s.mapping = unsafe { nil }
	}
}
