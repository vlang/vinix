// SPDX-License-Identifier: GPL-2.0-or-later
// Independent descriptor/seat model for the production console-mode boundary.
@[translated]
module consolefixture

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

struct C.stat {
	st_mode u32
	st_dev  u64
	st_ino  u64
	st_rdev u64
}

fn C.printf(&char, ...voidptr) i32
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.abort()
fn C.strcmp(&char, &char) i32
fn C.vinix_desktop_set_console_mode(i32)

@[c_extern]
__global C.stderr voidptr

__global scenario i32
__global opens i32
__global closes i32
__global stats i32
__global fstats i32
__global ioctls i32
__global mode_now i32
__global mode_requested i32

fn check(ok bool, message &char) {
	if !ok {
		C.fprintf(C.stderr, c'CONSOLE MODE FAIL case=%d: %s\n', scenario, message)
		C.abort()
	}
}

fn matching_fd() i32 {
	return if scenario == 3 {
		1
	} else if scenario == 4 || scenario == 14 {
		2
	} else {
		0
	}
}

fn rejected() bool { return scenario >= 5 && scenario <= 11 }

fn revoked() bool { return scenario == 1 || scenario == 12 }

@[export: 'gpf_open']
pub fn open(path &char, flags i32) i32 {
	check(C.strcmp(path, c'/dev/console') == 0, c'console pathname')
	check(flags == (C.O_RDWR | C.O_CLOEXEC), c'console open flags')
	opens++
	return if scenario <= 1 { 82 } else { -1 }
}

@[export: 'gpf_close']
pub fn close(fd i32) i32 {
	check(fd == 82 && scenario <= 1 && closes == 0, c'only owned descriptor may be closed')
	closes++
	return 0
}

@[export: 'gpf_stat']
pub fn console_stat(path &char, state &C.stat) i32 {
	check(C.strcmp(path, c'/dev/console') == 0 && scenario >= 2, c'fallback console stat')
	stats++
	if scenario == 9 { return -1 }
	unsafe {
		state.st_mode = if scenario == 10 { 0o100600 } else { 0o020600 }
		state.st_dev = 17
		state.st_ino = 23
		state.st_rdev = 29
	}
	return 0
}

@[export: 'gpf_fstat']
pub fn inherited_stat(fd i32, state &C.stat) i32 {
	check(fd >= 0 && fd <= 2 && fd == fstats, c'bounded standard-stream inspection')
	fstats++
	if scenario == 11 || (scenario == 14 && fd == 0) { return -1 }
	unsafe {
		state.st_mode = if scenario == 8 || fd < matching_fd() { 0o100600 } else { 0o020600 }
		state.st_dev = if scenario == 6 { 18 } else { 17 }
		state.st_ino = if scenario == 7 { 24 } else { 23 }
		state.st_rdev = if scenario == 5 { 30 } else { 29 }
	}
	return 0
}

fn ioctl_model(fd i32, request usize, mode i32) i32 {
	check(request == 0x4b3a && mode == mode_requested, c'KDSETMODE and normalized mode')
	check(!rejected() && fd == if scenario <= 1 { 82 } else { matching_fd() }, c'only exact console receives ioctl')
	ioctls++
	if revoked() { return -1 }
	mode_now = mode
	return 0
}

$if fixture_darwin_arm64 ? {
	@[export: 'gpf_ioctl_body']
	pub fn ioctl(fd i32, request usize, mode i32) i32 { return ioctl_model(fd, request, mode) }
} $else {
	@[export: 'gpf_ioctl']
	pub fn ioctl(fd i32, request usize, mode i32) i32 { return ioctl_model(fd, request, mode) }
}

fn exercise(code i32) {
	scenario = code
	opens = 0
	closes = 0
	stats = 0
	fstats = 0
	ioctls = 0
	mode_requested = if code == 13 { 0 } else { 1 }
	mode_now = if code == 13 { 1 } else { 0 }
	before := mode_now
	C.vinix_desktop_set_console_mode(if code == 15 { -5 } else { mode_requested })
	check(opens == 1 && closes == if code <= 1 { 1 } else { 0 }, c'owned descriptor released; borrowed streams remain open')
	check(stats == if code <= 1 { 0 } else { 1 }, c'console identity inspected only on fallback')
	expected_fstats := if code <= 1 || code == 9 || code == 10 {
		0
	} else if rejected() {
		3
	} else {
		matching_fd() + 1
	}
	check(fstats == expected_fstats, c'exact bounded descriptor search')
	check(ioctls == if rejected() { 0 } else { 1 }, c'no ioctl for unrelated streams and no retry after seat refusal')
	check(mode_now == if rejected() || revoked() { before } else { mode_requested }, c'graphics/text transition honors seat authorization')
}

@[export: 'main']
pub fn run() i32 {
	for code := i32(0); code < 16; code++ { exercise(code) }
	for cycle := 0; cycle < 1000; cycle++ {
		exercise(2)
		exercise(13)
	}
	C.printf(c'CONSOLE MODE 16 cases and 1000 graphics/text cycles PASS\n')
	return 0
}
