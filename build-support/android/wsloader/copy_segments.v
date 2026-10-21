// SPDX-License-Identifier: GPL-2.0-or-later
// 4 KiB Android DSOs can have different file/virtual offsets within a 16 KiB
// host page. Copy their segment bytes into the reserved anonymous image; a
// MAP_FIXED file mapping would overwrite neighbouring segments on shared pages.
@[translated]
module wsloader

#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>

fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.__builtin___clear_cache(voidptr, voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.__error() &i32
fn C.__errno_location() &i32

fn segment_errno() i32 {
	unsafe {
		$if macos { return *C.__error() } $else { return *C.__errno_location() }
	}
}

struct SegmentHeader {
	kind     u32
	flags    u32
	offset   u64
	address  u64
	physical u64
	file     u64
	memory   u64
	align    u64
}

const segment_page = usize(16384)

@[export: 'vinix_ws_copy_required']
pub fn copy_required(headers &SegmentHeader, count usize) i32 {
	unsafe {
		for i := usize(0); i < count; i++ {
			p := headers[i]
			if p.kind == 1 && (p.align < segment_page || p.address % segment_page != p.offset % segment_page) { return 1 }
		}
	}
	return 0
}

fn segment_in_image(p SegmentHeader, reserved usize) bool {
	return p.file <= p.memory && p.address <= reserved && p.memory <= reserved - p.address
		&& p.offset <= u64(0x7fffffffffffffff) && p.file <= u64(0x7fffffffffffffff) - p.offset
}

@[export: 'vinix_ws_copy_segments']
pub fn copy_segments(fd i32, headers &SegmentHeader, count usize, base usize, reserved usize,
	dynamic &voidptr, readonly_start &u32, readonly_end &u32, relro_start &usize, relro_length &u32) i32 {
	unsafe {
		mut complete := false
		defer { if !complete { C.munmap(voidptr(base), reserved) } }
		if reserved == 0 || count == 0 || count > 1024 || base % segment_page != 0
			|| reserved % segment_page != 0 || reserved > ~usize(0) - base { return -1 }
		for i := usize(0); i < count; i++ {
			p := headers[i]
			if p.kind in [u32(1), 2, 0x6474e552] && !segment_in_image(p, reserved) { return -1 }
			if p.kind == 1 && p.memory > 0 {
				for j := usize(0); j < i; j++ {
					before := headers[j]
					if before.kind == 1 && before.memory > 0 && before.address < p.address + p.memory
						&& before.address + before.memory > p.address { return -1 }
				}
			}
		}
		if C.mprotect(voidptr(base), reserved, 1 | 2) != 0 { return -1 }
		*dynamic = voidptr(~usize(0))
		*readonly_start = 0xffffffff
		*readonly_end = 0
		// Full host pages inside RELRO are protected by finish_copy_segments.
		// The upstream page rounding would also protect unrelated code/data.
		*relro_start = 0
		*relro_length = 0
		for i := usize(0); i < count; i++ {
			p := headers[i]
			if p.kind == 1 {
				mut used := u64(0)
				for used < p.file {
					n := C.pread(fd, voidptr(base + usize(p.address + used)), usize(p.file - used), i64(p.offset + used))
					if n < 0 && segment_errno() == 4 { continue }
					if n <= 0 { return -1 }
					used += u64(n)
				}
				C.memset(voidptr(base + usize(p.address + p.file)), 0, usize(p.memory - p.file))
			} else if p.kind == 2 {
				*dynamic = voidptr(base + usize(p.address))
			}
		}
		if *dynamic == voidptr(~usize(0)) { return -1 }
		complete = true
		return 0
	}
}

fn segment_page_protection(headers &SegmentHeader, count usize, page usize) i32 {
	unsafe {
		mut protection := i32(0)
		for i := usize(0); i < count; i++ {
			p := headers[i]
			if p.kind == 1 && p.memory > 0 && p.address < page + segment_page && p.address + p.memory > page {
				if p.flags & 4 != 0 { protection |= 1 }
				if p.flags & 2 != 0 { protection |= 2 }
				if p.flags & 1 != 0 { protection |= 4 }
			}
		}
		for i := usize(0); i < count; i++ {
			p := headers[i]
			if p.kind == 0x6474e552 && p.address <= page && p.address + p.memory >= page + segment_page { protection &= ~i32(2) }
		}
		return protection
	}
}

@[export: 'vinix_ws_finish_copy_segments']
pub fn finish_copy_segments(headers &SegmentHeader, count usize, base usize, reserved usize) i32 {
	unsafe {
		for page := usize(0); page < reserved; page += segment_page {
			protection := segment_page_protection(headers, count, page)
			if protection & 4 != 0 { C.__builtin___clear_cache(voidptr(base + page), voidptr(base + page + segment_page)) }
			if C.mprotect(voidptr(base + page), segment_page, protection) != 0 { return -1 }
		}
	}
	return 0
}
