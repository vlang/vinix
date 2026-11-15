// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module initfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

@[typedef]
struct C.jmp_buf {}

fn C.alloca(usize) voidptr
fn C.setjmp(voidptr) i32
fn C.longjmp(voidptr, i32)
@[c_extern]
fn C.perf_init_under_test() i32
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.__errno_location() &i32
@[c_extern]
fn C.__real_open(&char, i32) i32
@[c_extern]
fn C.__real_dup2(i32, i32) i32
@[c_extern]
fn C.__real_close(i32) i32
@[c_extern]
fn C.__real_mkdir(&char, u32) i32
@[c_extern]
fn C.__real_mount(&char, &char, &char, u64, voidptr) i32
@[c_extern]
fn C.__real_access(&char, i32) i32
@[c_extern]
fn C.__real_execv(&char, &&char) i32

__global (
	active   bool
	scenario int
	stage    int
	failures int
	checks   int
	jump     voidptr
)

fn check(ok bool) {
	checks++
	if !ok { failures++ }
}

fn console_fd() i32 {
	return if scenario == 9 {
		1
	} else if scenario == 10 {
		2
	} else {
		9
	}
}

fn error_code(code i32) i32 {
	unsafe {
		location := C.__errno_location()
		*location = code
	}
	return -1
}

@[export: '__wrap_open']
pub fn open(path &char, flags i32) i32 {
	unsafe {
		if !active { return C.__real_open(path, flags) }
		check(stage == 0 && flags == C.O_WRONLY)
		$if arm64 {
			check(C.strcmp(path, c'/dev/console') == 0)
		} $else {
			check(C.strcmp(path, c'/dev/com1') == 0)
		}
		stage = 1
		return if scenario == 0 { error_code(C.EACCES) } else { console_fd() }
	}
}

@[export: '__wrap_dup2']
pub fn dup2(fd i32, target i32) i32 {
	if !active { return C.__real_dup2(fd, target) }
	check((stage == 1 || stage == 2) && fd == console_fd() && target == stage)
	stage++
	return if (scenario == 1 && target == 1) || (scenario == 2 && target == 2) {
		error_code(C.EBADF)
	} else {
		target
	}
}

@[export: '__wrap_close']
pub fn close(fd i32) i32 {
	if !active { return C.__real_close(fd) }
	check(stage == 3 && fd == console_fd() && fd > 2)
	stage = 4
	return 0
}

@[export: '__wrap_mkdir']
pub fn mkdir(path &char, mode u32) i32 {
	if !active { return C.__real_mkdir(path, mode) }
	check(stage == if console_fd() > 2 { 4 } else { 3 })
	check(unsafe { C.strcmp(path, c'/root') == 0 } && mode == 0o755)
	stage = 5
	return if scenario == 3 {
		error_code(C.EACCES)
	} else if scenario == 4 {
		error_code(C.EEXIST)
	} else {
		0
	}
}

@[export: '__wrap_mount']
pub fn mount(source &char, target &char, kind &char, flags u64, data voidptr) i32 {
	unsafe {
		if !active { return C.__real_mount(source, target, kind, flags, data) }
		check(stage == 5 && flags == 0 && data == nil && C.strcmp(target, c'/root') == 0 && C.strcmp(kind, c'ext2') == 0)
		$if arm64 {
			check(C.strcmp(source, c'/dev/vda') == 0)
		} $else {
			check(C.strcmp(source, c'/dev/sd0') == 0)
		}
		stage = 6
		return if scenario in [5, 6]! { error_code(C.EIO) } else { 0 }
	}
}

@[export: '__wrap_access']
pub fn access(path &char, mode i32) i32 {
	unsafe {
		if !active { return C.__real_access(path, mode) }
		check(stage == 6 && mode == C.F_OK)
		$if arm64 {
			check(C.strcmp(path, c'/dev/vda') == 0)
		} $else {
			check(C.strcmp(path, c'/dev/sd0') == 0)
		}
		stage = 7
		return if scenario == 5 { error_code(C.ENOENT) } else { 0 }
	}
}

@[export: '__wrap_execv']
pub fn execv(path &char, argv &&char) i32 {
	unsafe {
		if !active { return C.__real_execv(path, argv) }
		check(stage == 6 && C.strcmp(path, c'/bin/sh') == 0)
		check(argv != nil && argv[0] != nil && argv[1] != nil && argv[2] == nil
			&& C.strcmp(argv[0], c'/bin/sh') == 0 && C.strcmp(argv[1], c'/opt/vinix-perf/perf-init.sh') == 0)
		stage = 8
		if scenario in [4, 8, 9, 10]! { C.longjmp(jump, 1) }
		return error_code(C.ENOENT)
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		jump = C.alloca(sizeof(C.jmp_buf))
		scenario = 0
		for scenario < 11 {
			stage = 0
			before := failures
			active = true
			if C.setjmp(jump) == 0 {
				result := C.perf_init_under_test()
				check(result == 1 && scenario !in [4, 8, 9, 10]!)
			} else {
				check(scenario in [4, 8, 9, 10]!)
			}
			active = false
			expected := match scenario {
				0 { 1 }
				1 { 2 }
				2 { 3 }
				3 { 5 }
				5, 6 { 7 }
				else { 8 }
			}
			check(stage == expected)
			C.printf(c'LINUX PERFINIT CASE: mode=%d stage=%d failures=%d\n', scenario, stage, failures - before)
			scenario++
		}
		C.printf(c'LINUX PERFINIT SUMMARY: cases=11 checks=%d failures=%d\n', checks, failures)
		C.printf(c'LINUX PERFINIT: %s\n', if failures == 0 {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
