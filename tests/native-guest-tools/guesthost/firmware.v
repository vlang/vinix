// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, int, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, int) i64
fn C.fstat(i32, &C.stat) int
fn C.ftruncate(i32, u64) i32
fn C.close(i32) int
fn C.unlink(&char) int

// Preserve every byte and the logical length, without allocating disk blocks
// for zero padding. The guest gets a fresh inode rather than sharing a writable
// template. Failed copies remove only the destination this call created.
fn copy_firmware_variables(source string, destination string) ! {
	input := C.open(source.str, C.O_RDONLY)
	if input < 0 { return error('cannot open firmware template: ' + source) }
	defer { C.close(input) }
	mut info := C.stat{}
	if C.fstat(input, &info) != 0 || info.st_size < 0
		|| info.st_mode & u32(C.S_IFMT) != u32(C.S_IFREG) {
		return error('firmware template must be a regular file: ' + source)
	}
	output := C.open(destination.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
	if output < 0 { return error('cannot create private firmware image: ' + destination) }
	mut closed := false
	mut complete := false
	defer {
		if !closed { C.close(output) }
		if !complete { C.unlink(destination.str) }
	}
	mut buffer := [65536]u8{}
	mut total := i64(0)
	for {
		read := C.read(input, unsafe { &buffer[0] }, usize(buffer.len))
		if read < 0 {
			if C.errno == C.EINTR { continue }
			return error('cannot read firmware template: ' + source)
		}
		if read == 0 { break }
		if i64(read) > info.st_size - total { return error('firmware template size changed: ' + source) }
		mut zero := true
		for i in 0 .. int(read) { if buffer[i] != 0 { zero = false; break } }
		if zero {
			if C.lseek(output, i64(read), C.SEEK_CUR) < 0 { return error('cannot seek private firmware image') }
		} else {
			mut written := 0
			for written < int(read) {
				count := C.write(output, unsafe { &buffer[written] }, usize(int(read) - written))
				if count < 0 && C.errno == C.EINTR { continue }
				if count <= 0 { return error('cannot write private firmware image') }
				written += int(count)
			}
		}
		total += i64(read)
	}
	// Seeking over a zero tail does not extend the file by itself.
	if total != info.st_size { return error('firmware template size changed: ' + source) }
	if C.ftruncate(output, u64(total)) != 0 { return error('cannot size private firmware image') }
	result := C.close(output)
	closed = true
	if result != 0 { return error('cannot close private firmware image') }
	complete = true
}
