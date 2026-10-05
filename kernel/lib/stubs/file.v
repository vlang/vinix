@[has_globals]
module stubs

import lib
import kprint

struct C.__file {}

type FILE = C.__file

@[markused]
__global (
	stdin  = &FILE(unsafe { nil })
	stdout = &FILE(unsafe { nil })
	stderr = &FILE(unsafe { nil })
)

@[export: 'fflush']
pub fn fflush(stream &FILE) int {
	return 0
}

@[export: 'getchar']
pub fn getchar() int {
	lib.kpanic(unsafe { nil }, c'getchar is a stub')
}

@[export: 'getc']
pub fn getc(stream &FILE) int {
	lib.kpanic(unsafe { nil }, c'getc is a stub')
}

@[export: 'fgets']
pub fn fgets(str charptr, count u64, stream &FILE) charptr {
	lib.kpanic(unsafe { nil }, c'fgets is a stub')
}

@[export: 'popen']
pub fn popen(command &char, typ &char) &FILE {
	lib.kpanic(unsafe { nil }, c'popen is a stub')
}

@[export: 'pclose']
pub fn pclose(stream &FILE) int {
	lib.kpanic(unsafe { nil }, c'pclose is a stub')
}

@[export: 'write']
pub fn write(fd int, buf voidptr, count u64) i64 {
	if fd != 1 && fd != 2 {
		lib.kpanic(unsafe { nil }, c'write to fd != 1 && fd != 2 is a stub')
	}

	kprint.kwrite(charptr(buf), count)

	return i64(count)
}

@[export: 'isatty']
pub fn isatty(fd int) int {
	return 1
}
