// file.v: Stubs for the generated V code.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module stubs

import lib
import kprint

struct C.__file {}

type FILE = C.__file

__global (
	stdin  = &FILE(voidptr(0))
	stdout = &FILE(voidptr(0))
	stderr = &FILE(voidptr(0))
)

[export: 'fflush']
pub fn fflush(stream &FILE) int {
	return 0
}

[export: 'getchar']
pub fn getchar() int {
	lib.kpanic(voidptr(0), c'getchar is a stub')
}

[export: 'getc']
pub fn getc(stream &FILE) int {
	lib.kpanic(voidptr(0), c'getc is a stub')
}

[export: 'fgets']
pub fn fgets(str charptr, count u64, stream &FILE) charptr {
	lib.kpanic(voidptr(0), c'fgets is a stub')
}

[export: 'popen']
pub fn popen(command &C.char, typ &C.char) &FILE {
	lib.kpanic(voidptr(0), c'popen is a stub')
}

[export: 'pclose']
pub fn pclose(stream &FILE) int {
	lib.kpanic(voidptr(0), c'pclose is a stub')
}

[export: 'write']
pub fn write(fd int, buf &C.void, count u64) i64 {
	if fd != 1 && fd != 2 {
		lib.kpanic(voidptr(0), c'write to fd != 1 && fd != 2 is a stub')
	}

	kprint.kprint(charptr(buf))

	return i64(count)
}

[export: 'isatty']
pub fn isatty(fd int) int {
	return 1
}
