// SPDX-License-Identifier: GPL-2.0-or-later
// Controlled syscall/fault provider, shared by the immutable C and V fixtures.
@[has_globals]
module bigiomodel
#define BIG_IO_MODEL_PROVIDER
#include <big-io-model-abi.h>

@[typedef]
struct C.bgi_const_char {}
@[typedef]
struct C.bgi_const_void {}
fn C.getenv(&char) &char
fn C.strcmp(&char, &char) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.snprintf(voidptr, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.exit(i32)
fn C.BGI_ERRNO() &i32

__global bgi_opens i32
__global bgi_reads i32
__global bgi_writes i32
__global bgi_closes i32
__global bgi_snapshots i32
__global bgi_sleep_seconds u32
__global bgi_zero_reads i32
__global bgi_zero_writes i32

fn fault(name &char) bool {
	unsafe { mode := C.getenv(c'BGI_FAULT'); return mode != nil && C.strcmp(mode, name) == 0 }
}
fn failure() i32 { unsafe { address := C.BGI_ERRNO(); *address = C.EIO }; return -1 }

@[export: 'bgi_open']
pub fn open(path &C.bgi_const_char, flags i32) i32 {
	unsafe {
		bgi_opens++
		if C.strcmp(&char(path), c'/dev/zero') == 0 { if fault(c'open_zero') { return failure() }; return 11 }
		if C.strcmp(&char(path), c'/dev/null') == 0 { if fault(c'open_null') { return failure() }; return 12 }
		if fault(c'open_proc') { return failure() }
		return 13
	}
}

@[export: 'bgi_read']
pub fn read(fd i32, payload voidptr, size usize) isize {
	unsafe {
		bgi_reads++
		if fd == 13 {
			bgi_snapshots++
			if fault(c'read_proc') { return failure() }
			if fault(c'empty_proc') { return 0 }
			if fault(c'missing_large') { return C.snprintf(payload, size, c'not a large row\n') }
			if fault(c'bad_large') { return C.snprintf(payload, size, c'large - - not_a_number\n') }
			pages := if bgi_snapshots == 5 && fault(c'changed_pages') { u32(8) } else { u32(7) }
			return C.snprintf(payload, size, c'header\nlarge - - %u\n', pages)
		}
		if usize(payload) == 1 {
			address := C.BGI_ERRNO()
			*address = if fault(c'bad_read_errno') { C.EIO } else { C.EFAULT }
			return if fault(c'bad_read_return') { isize(0) } else { isize(-1) }
		}
		bgi_zero_reads++
		if bgi_zero_reads == 1 && fault(c'warm_read') { return isize(size - 1) }
		if bgi_zero_reads == 2 && fault(c'round_read') { return isize(size - 1) }
		C.memset(payload, 0, size)
		if bgi_zero_reads == 2 && fault(c'nonzero_payload') { (&u8(payload))[65535] = 1 }
		return isize(size)
	}
}

@[export: 'bgi_write']
pub fn write(fd i32, payload &C.bgi_const_void, size usize) isize {
	unsafe {
		bgi_writes++
		if usize(payload) == 1 {
			address := C.BGI_ERRNO()
			*address = if fault(c'bad_write_errno') { C.EIO } else { C.EFAULT }
			return if fault(c'bad_write_return') { isize(0) } else { isize(-1) }
		}
		bgi_zero_writes++
		if bgi_zero_writes == 1 && fault(c'warm_write') { return isize(size - 1) }
		if bgi_zero_writes == 2 && fault(c'round_write') { return isize(size - 1) }
		return isize(size)
	}
}

@[export: 'bgi_close']
pub fn close(fd i32) i32 {
	bgi_closes++
	if (fd == 13 && fault(c'close_proc')) || (fd == 11 && fault(c'close_zero')) || (fd == 12 && fault(c'close_null')) { return failure() }
	return 0
}
@[export: 'bgi_sleep']
pub fn sleep(seconds u32) u32 { bgi_sleep_seconds += seconds; return if fault(c'interrupted_sleep') { u32(3) } else { u32(0) } }
@[export: 'bgi_pause']
pub fn pause() i32 {
	C.printf(c'BIG IO MODEL: opens=%d reads=%d writes=%d closes=%d snapshots=%d sleep=%u\n', bgi_opens, bgi_reads, bgi_writes, bgi_closes, bgi_snapshots, bgi_sleep_seconds)
	C.exit(0)
	return 0
}
