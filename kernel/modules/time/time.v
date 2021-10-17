module time

pub struct TimeSpec {
pub mut:
	tv_sec  i64
	tv_nsec i64
}

pub fn syscall_clock_gettime(which int, mut tp TimeSpec) i64 {
	C.printf(c'\n\e[32mstrace\e[m: clock_gettime(%d, 0x%llx)\n',
			 which, voidptr(tp))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	C.printf(c'clock_gettime() is a stub\n')

	tp.tv_sec = 0
	tp.tv_nsec = 0

	return 0
}
