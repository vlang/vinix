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
fn C.abort()

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
