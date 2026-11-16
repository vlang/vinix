// SPDX-License-Identifier: GPL-2.0-or-later
// The fixture attribute is serialized in ordinary evidence, not a host input pin.
module winequeryprobe

import os

pub const key = 'org.vinix.wine-read-probe'
pub const value = 'WINE XATTR PROBE\n'

$if macos {
	#include <sys/xattr.h>
	fn C.getxattr(&char, &char, voidptr, uint, u32, int) int
	fn C.listxattr(&char, &char, uint, int) int
	fn C.setxattr(&char, &char, voidptr, uint, u32, int) int
}

pub struct Result {
pub:
	operation string
	path string
	result i64
	error_code int
	data string
}

pub fn seed(path string) ! {
	if os.lstat(path)!.get_filetype() !in [.regular, .directory] { return error('ordinary query fixture required') }
	$if macos {
		if C.setxattr(path.str, key.str, value.str, uint(value.len), 0, 0) != 0 {
			return error('cannot seed query fixture attribute')
		}
	} $else { return error('query fixture requires macOS') }
}

pub fn read(operation string, path string) !Result {
	$if macos {
		mut buffer := [1024]u8{}
		C.errno = 0
		n := match operation {
			'exists' { int(C.access(path.str, 0)) }
			'getxattr' { C.getxattr(path.str, key.str, &buffer[0], 1024, 0, 0) }
			'listxattr' { C.listxattr(path.str, &char(&buffer[0]), 1024, 0) }
			else { return error('unsupported query operation') }
		}
		saved := int(C.errno)
		if n > buffer.len { return error('query result outside fixture bound') }
		return Result{operation: operation, path: path, result: i64(n), error_code: saved,
			data: if n >= 0 && operation != 'exists' { buffer[..n].bytestr() } else { '' }}
	} $else { return error('query fixture requires macOS') }
}

pub fn allowed(result Result) bool {
	if result.result < 0 || result.error_code != 0 { return false }
	return match result.operation {
		'exists' { result.result == 0 && result.data == '' }
		'getxattr' { result.result == value.len && result.data == value }
		'listxattr' { key in result.data.split('\x00') }
		else { false }
	}
}

pub fn denied(result Result) bool {
	return result.result == -1 && result.error_code in [1, 13] && result.data == ''
}
