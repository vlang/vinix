// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module wsloader

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

fn C.strnlen(&char, usize) usize
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strlen(&char) usize
fn C.write(i32, voidptr, usize) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.abort()
fn C.dprintf(i32, &char, ...voidptr) i32

fn append_overflow() {
	message := c'FORTIFY: strncat: destination buffer too small\n'
	C.write(2, message, C.strlen(message))
	C.abort()
}

// Bionic's fortified strncat keeps the destination capacity separate from the
// requested source limit. Check the terminator too, without overflowing an
// intermediate length or reading beyond the destination object.
@[export: 'bionic___strncat_chk']
pub fn checked_strncat(destination &char, source &char, limit usize, capacity usize) &char {
	unsafe {
		used := C.strnlen(destination, capacity)
		if used == capacity { append_overflow(); return nil }
		count := C.strnlen(source, limit)
		if count >= capacity - used { append_overflow(); return nil }
		C.memcpy(destination + used, source, count)
		destination[used + count] = 0
		return destination
	}
}

// Android's LP64 pread and pread64 have the same offset ABI. Validate before
// touching the descriptor, including the SSIZE_MAX constraint on I/O counts.
@[export: 'bionic___pread_chk']
pub fn checked_pread(fd i32, buffer voidptr, count usize, offset i64, capacity usize) isize {
	if count > usize(0x7fffffffffffffff) || count > capacity {
		C.dprintf(2, c'FORTIFY: pread: count %zu exceeds buffer %zu or SSIZE_MAX\n', count, capacity)
		C.abort()
		return -1
	}
	return C.pread(fd, buffer, count, offset)
}

@[export: 'bionic___pread64_chk']
pub fn checked_pread64(fd i32, buffer voidptr, count usize, offset i64, capacity usize) isize {
	return checked_pread(fd, buffer, count, offset, capacity)
}

// Fortified positional writes validate the source buffer before entering libc.
// Android's LP64 pwrite64 uses the same signed 64-bit offset ABI as pwrite.
@[export: 'bionic___pwrite_chk']
pub fn checked_pwrite(fd i32, buffer voidptr, count usize, offset i64, capacity usize) isize {
	if count > usize(0x7fffffffffffffff) || count > capacity {
		C.dprintf(2, c'FORTIFY: pwrite: count %zu exceeds buffer %zu or SSIZE_MAX\n', count, capacity)
		C.abort()
		return -1
	}
	return C.pwrite(fd, buffer, count, offset)
}

@[export: 'bionic___pwrite64_chk']
pub fn checked_pwrite64(fd i32, buffer voidptr, count usize, offset i64, capacity usize) isize {
	return checked_pwrite(fd, buffer, count, offset, capacity)
}
