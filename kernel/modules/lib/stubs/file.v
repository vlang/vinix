module stubs

import lib
import kprint

struct C.__mlibc_file_base {}

type FILE = C.__mlibc_file_base

__global (
	stdin = &FILE(voidptr(0))
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
pub fn popen(const_command &C.char, const_typ &C.char) &FILE {
	lib.kpanic(voidptr(0), c'popen is a stub')
}

[export: 'pclose']
pub fn pclose(stream &FILE) int {
	lib.kpanic(voidptr(0), c'pclose is a stub')
}

[export: 'write']
pub fn write(fd int, const_buf &C.void, count u64) i64 {
	if fd != 1 && fd != 2 {
		lib.kpanic(voidptr(0), c'write to fd != 1 && fd != 2 is a stub')
	}

	kprint.kprint(charptr(const_buf))

	return i64(count)
}

[export: 'isatty']
pub fn isatty(fd int) int {
	return 1
}