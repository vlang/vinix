// SPDX-License-Identifier: GPL-2.0-only
module tarcore

import os

$if !tarstream_fd_only ? {
	#flag -lz
	#include <zlib.h>
}

fn C.gzdopen(i32, &char) voidptr
fn C.gzwrite(voidptr, voidptr, u32) i32
fn C.gzerror(voidptr, &i32) &char
fn C.gzclose(voidptr) i32

// zlib's default gzip header has no filename and a zero timestamp.
// https://zlib.net/manual.html#Advanced
pub fn create_gzip(path string) !Writer {
	$if tarstream_fd_only ? { return error('gzip writing is unavailable in a descriptor reader') } $else {
	fd := unsafe { C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC, 0o666) }
	if fd < 0 { return os.error_posix() }
	stream := C.gzdopen(fd, c'wb1')
	if stream == unsafe { nil } {
		failure := os.error_posix()
		C.close(fd)
		return failure
	}
	return Writer{ compressed: true, gzip_stream: stream, stream_fd: fd }
	}
}

fn gzip_error(stream voidptr) IError {
	$if tarstream_fd_only ? { return error('gzip writing is unavailable in a descriptor reader') } $else {
	mut code := i32(0)
	message := C.gzerror(stream, &code)
	if code == C.Z_ERRNO { return os.error_posix() }
	if message == unsafe { nil } { return error('cannot write gzip archive') }
	return error(unsafe { message.vstring().clone() })
	}
}
