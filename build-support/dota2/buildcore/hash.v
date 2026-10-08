// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import crypto.sha256

#include <stdio.h>
#include <errno.h>
fn C.fopen(&char, &char) &C.FILE
fn C.fread(voidptr, usize, usize, &C.FILE) usize
fn C.ferror(&C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.clearerr(&C.FILE)

fn file_hash(path string) !string {
	stream := C.fopen(path.str, c'rb')
	if isnil(stream) { return error('Cannot open runtime library') }
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := sha256.new()
	for {
		count := C.fread(buffer.data, 1, usize(buffer.len), stream)
		number := int(C.errno)
		if count > 0 { digest.write(buffer[..int(count)])! }
		if C.ferror(stream) != 0 {
			if number == C.EINTR {
				C.clearerr(stream)
				continue
			}
			return error('Cannot read runtime library')
		}
		if count == 0 { break }
	}
	closed = true
	if C.fclose(stream) != 0 { return error('Cannot close runtime library') }
	return digest.sum([]u8{}).hex()
}
