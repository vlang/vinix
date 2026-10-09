// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn darwin_assert_rtn(function &char, file &char, line i32, expression &char) {
	stream := C.ios_host_stdio(2)
	if function == unsafe { nil } {
		mut slots := [u64(expression), u64(file), u64(line)]!
		C.ios_vfprintf(stream, c'Assertion failed: (%s), file %s, line %d.\n', unsafe { &slots[0] })
	} else {
		mut slots := [u64(expression), u64(function), u64(file), u64(line)]!
		C.ios_vfprintf(stream, c'Assertion failed: (%s), function %s, file %s, line %d.\n', unsafe { &slots[0] })
	}
	C.fflush(stream)
	C.abort()
}
