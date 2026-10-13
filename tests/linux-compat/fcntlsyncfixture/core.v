// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlsyncfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct C.rlimit { mut: rlim_cur u64 rlim_max u64 }
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct State { mut: metadata C.stat flags i32 status i32 cursor i64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
fn C.dup(i32) i32
fn C.dup3(i32, i32, i32) i32
fn C.lseek(i32, i64, i32) i64
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.unlink(&char) i32
fn C.mkdir(&char, u32) i32
fn C.pipe2(&i32, i32) i32
fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn query(fd u64, cmd u64, arg u64) Query {
	unsafe { slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_fcntl, fd, cmd, arg); return Query{ret, *slot} }
}
fn record(counts &Counts, kind i32, good bool, ordinary bool, result Query) {
	unsafe { mut tally := &Counts(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX FCNTLSYNC DETAIL: ordinary=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), kind, tally.calls[kind], result.ret, result.code); C.fflush(nil) } } }
}
fn capture(fd i32, target &State) bool {
	unsafe { mut state := &State(target); state.flags = C.fcntl(fd, C.F_GETFD); state.status = C.fcntl(fd, C.F_GETFL); state.cursor = C.lseek(fd, 0, C.SEEK_CUR); return C.fstat(fd, &state.metadata) == 0 && state.flags >= 0 && state.status >= 0 }
}
fn equal(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size }
fn stable(fd i32, before &State, status i32) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && equal(&before.metadata, after) && C.fcntl(fd, C.F_GETFD) == before.flags && C.fcntl(fd, C.F_GETFL) == status && C.lseek(fd, 0, C.SEEK_CUR) == before.cursor }
}
fn state_check(fds &i32, states &State, changed i32, wanted i32) bool {
	unsafe {
		mut good := true
		for index in 0 .. 35 {
			class := if index < 27 { i32(index / 3) } else if index == 33 { 3 } else if index == 34 { 4 } else { -2 }
			if !stable(fds[index], &states[index], if class == changed && changed >= 0 { wanted } else { states[index].status }) { good = false }
		}; return good
	}
}
fn checked(counts &Counts, kind i32, ordinary bool, fds &i32, states &State, source u32, class i32, arg u64, prefix i32, libc bool) {
	unsafe {
		if source == 66 && class >= 0 && !capture(66, &states[35]) { C._exit(1) }
		fd := u64(source) | if prefix == 1 { u64(0xffffffff00000000) } else { 0 }
		cmd := u64(C.F_SETFL) | if prefix == 2 { u64(0x8000000000000000) } else { 0 }
		value := arg | if prefix == 3 { u64(0xabcdef0100000000) } else { 0 }
		mut result := Query{}
		if libc { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(i32(source), C.F_SETFL, value); result = Query{isize(ret), *slot} }
		else { result = query(fd, cmd, value) }
		wanted := if class >= 0 { (states[class * 3].status & ~i32(C.O_APPEND | C.O_NONBLOCK)) | (i32(u32(arg)) & i32(C.O_APPEND | C.O_NONBLOCK)) } else { i32(0) }
		mut good := result.ret == if class >= 0 { 0 } else { -1 } && result.code == if class >= 0 { i32(0) } else { i32(C.EBADF) }
		if !state_check(fds, states, class, wanted) { good = false }
		if class >= 0 {
			if source == 66 && !stable(66, &states[35], wanted) { good = false }
			if C.fcntl(i32(source), C.F_SETFL, states[class * 3].status) != 0 { C._exit(1) }
			if !state_check(fds, states, -1, 0) { good = false }
		}
		record(counts, kind, good, ordinary, result)
	}
}
fn matrix(counts &Counts, fds &i32, states &State, ordinary bool, limits &C.rlimit) {
	unsafe {
		args := [u64(0), u64(C.O_DSYNC), u64(C.O_SYNC), u64(C.O_DSYNC | C.O_APPEND), u64(C.O_SYNC | C.O_NONBLOCK), u64(C.O_SYNC | C.O_APPEND | C.O_NONBLOCK), u64(C.O_DSYNC | C.O_CREAT | C.O_EXCL | C.O_TRUNC | C.O_CLOEXEC | C.O_WRONLY | C.O_NOFOLLOW), u64(C.O_CREAT | C.O_DIRECTORY | C.O_EXCL | C.O_TRUNC | C.O_CLOEXEC | C.O_RDWR | C.O_APPEND)]!
		for index in 0 .. 27 { for arg in args { for prefix in 0 .. 4 { checked(counts, 0, ordinary, fds, states, u32(fds[index]), i32(index / 3), arg, i32(prefix), false) }; checked(counts, 2, ordinary, fds, states, u32(fds[index]), i32(index / 3), arg, 0, true) } }
		for source in [u32(127), u32(0x80000000), u32(0xffffffff), u32(1048576)]! { for arg in args { for prefix in 0 .. 4 { checked(counts, 1, ordinary, fds, states, source, -1, arg, i32(prefix), false) }; checked(counts, 2, ordinary, fds, states, source, -1, arg, 0, true) } }
		for index in 27 .. 33 { for arg in args { for prefix in 0 .. 4 { checked(counts, 1, ordinary, fds, states, u32(fds[index]), -1, arg, i32(prefix), false) }; checked(counts, 2, ordinary, fds, states, u32(fds[index]), -1, arg, 0, true) } }
		mut bound := &C.rlimit(limits)
		for limit in [u64(8), u64(0)]! {
			bound.rlim_cur = limit; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
			for arg in args { for prefix in 0 .. 4 { checked(counts, 3, ordinary, fds, states, 64, 3, arg, i32(prefix), false); checked(counts, 3, ordinary, fds, states, 65, 4, arg, i32(prefix), false) } }
		}
		bound.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
		for arg in args { for prefix in 0 .. 4 {
			checked(counts, 3, ordinary, fds, states, 66, -1, arg, i32(prefix), false)
			if C.dup3(fds[10], 66, C.O_CLOEXEC) != 66 { C._exit(1) }; checked(counts, 3, ordinary, fds, states, 66, 3, arg, i32(prefix), false)
			if C.dup3(fds[13], 66, 0) != 66 { C._exit(1) }; checked(counts, 3, ordinary, fds, states, 66, 4, arg, i32(prefix), false)
			if C.close(66) != 0 { C._exit(1) }; checked(counts, 3, ordinary, fds, states, 66, -1, arg, i32(prefix), false)
		} }
	}
}
fn storage_cycle() bool {
	unsafe {
		for source in [i32(64), i32(65)]! {
			before := C.fcntl(source, C.F_GETFL); if before < 0 { return false }
			result := query(u64(source) | 0x100000000, u64(C.F_SETFL) | 0x200000000, u64(C.O_SYNC | C.O_NONBLOCK) | 0xabcdef0100000000)
			wanted := (before & ~i32(C.O_APPEND | C.O_NONBLOCK)) | i32(C.O_NONBLOCK)
			good := result.ret == 0 && result.code == 0 && C.fcntl(source, C.F_GETFL) == wanted
			if C.fcntl(source, C.F_SETFL, before) != 0 || !good { return false }
		}
		invalid := query(127, u64(C.F_SETFL), u64(C.O_SYNC)); return invalid.ret == -1 && invalid.code == C.EBADF
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 { if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++ }
			else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}; return counts.rows > 0 && large
	}
}
fn storage(ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle() { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle() { return false } }; C.usleep(13000000)
		if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FCNTLSYNC SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FCNTLSYNC STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(fds &i32, ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }
		states := &State(C.alloca(usize(36 * sizeof(State)))); for index in 0 .. 35 { if !capture(fds[index], &states[index]) { return false } }
		for index in 0 .. 35 {
			class := if index < 27 { i32(index / 3) } else if index == 33 { 3 } else if index == 34 { 4 } else { -1 }
			sync := if class == 1 || class == 2 { i32(C.O_DSYNC) } else if class == 3 || class == 5 || class == 8 { i32(C.O_SYNC) } else { i32(0) }
			access := if class == -1 { i32(C.O_PATH & C.O_ACCMODE) } else if class == 1 || class == 7 { i32(C.O_WRONLY) } else if class == 2 || class == 3 || class == 4 || class == 8 { i32(C.O_RDWR) } else { i32(C.O_RDONLY) }
			if states[index].status & i32(C.O_SYNC) != sync || states[index].status & i32(C.O_ACCMODE) != access { C.printf(c'LINUX FCNTLSYNC FAIL: initial index=%d class=%d status=%x sync=%x access=%x\n', i32(index), class, states[index].status, sync, access); C.fflush(nil); return false }
		}
		C.printf(c'LINUX FCNTLSYNC INITIAL: ordinary=%d descriptors=35 PASS\n', i32(ordinary)); C.fflush(nil)
		counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; matrix(counts, fds, states, ordinary, limits)
		mut good := state_check(fds, states, -1, 0)
		for kind in 0 .. 4 { C.printf(c'LINUX FCNTLSYNC CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if C.lseek(fds[10], 4, C.SEEK_SET) != 4 || C.lseek(fds[9], 0, C.SEEK_CUR) != 4 || C.lseek(fds[12], 0, C.SEEK_CUR) != 3 || C.lseek(fds[9], 3, C.SEEK_SET) != 3 { good = false }
		if good && !reference_run && !storage(ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut fds := &i32(C.alloca(usize(35 * sizeof(i32)))); for index in 0 .. 35 { fds[index] = -1 }
		seed := C.open(c'/tmp/linux-fcntlsync-file', C.O_CREAT | C.O_EXCL | C.O_WRONLY, i32(0o644)); if seed < 0 || C.write(seed, c'fcntl-sync-data!', 16) != 16 || C.close(seed) != 0 || C.mkdir(c'/tmp/linux-fcntlsync-dir', u32(0o755)) != 0 { return 1 }
		for class in 0 .. 6 {
			flags := match class { 0 { C.O_RDONLY } 1 { C.O_WRONLY | C.O_DSYNC } 2 { C.O_RDWR | C.O_DSYNC } 3 { C.O_RDWR | C.O_SYNC } 4 { C.O_RDWR } else { C.O_RDONLY | C.O_DIRECTORY | C.O_SYNC } }
			fds[class * 3] = C.open(if class == 5 { &char(c'/tmp/linux-fcntlsync-dir') } else { &char(c'/tmp/linux-fcntlsync-file') }, flags | C.O_CLOEXEC)
			if fds[class * 3] < 0 || (class != 5 && C.lseek(fds[class * 3], 3, C.SEEK_SET) != 3) { return 1 }
		}
		mut pipe := [2]i32{}; if C.pipe2(&pipe[0], C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.write(pipe[1], c'AB', 2) != 2 { return 1 }; fds[18] = pipe[0]; fds[21] = pipe[1]
		fds[24] = C.open(c'/tmp/linux-fcntlsync-gone', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_SYNC | C.O_CLOEXEC, i32(0o644)); if fds[24] < 0 || C.write(fds[24], c'fcntl-sync-data!', 16) != 16 || C.lseek(fds[24], 3, C.SEEK_SET) != 3 || C.unlink(c'/tmp/linux-fcntlsync-gone') != 0 { return 1 }
		for class in 0 .. 9 { fds[class * 3 + 1] = C.dup(fds[class * 3]); fds[class * 3 + 2] = C.fcntl(fds[class * 3], C.F_DUPFD_CLOEXEC, 40); if fds[class * 3 + 1] < 0 || fds[class * 3 + 2] < 0 { return 1 } }
		for class in 0 .. 2 { fds[27 + class * 3] = C.open(if class == 0 { &char(c'/tmp/linux-fcntlsync-file') } else { &char(c'/tmp/linux-fcntlsync-dir') }, C.O_PATH | C.O_CLOEXEC); fds[28 + class * 3] = C.dup(fds[27 + class * 3]); fds[29 + class * 3] = C.fcntl(fds[27 + class * 3], C.F_DUPFD_CLOEXEC, 40); if fds[27 + class * 3] < 0 || fds[28 + class * 3] < 0 || fds[29 + class * 3] < 0 { return 1 } }
		if C.dup3(fds[9], 64, C.O_CLOEXEC) != 64 || C.dup3(fds[12], 65, 0) != 65 { return 1 }; fds[33] = 64; fds[34] = 65
		mut good := true
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(fds, ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut data := [16]char{}; for index in [0, 6, 9, 12, 24]! { if C.pread(fds[index], &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'fcntl-sync-data!', 16) != 0 { good = false } }
		if C.read(fds[18], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) { good = false }
		for index in 0 .. 35 {
			flags := C.fcntl(fds[index], C.F_GETFD); wanted := if (index < 33 && index % 3 == 1) || index == 34 { 0 } else { C.FD_CLOEXEC }
			if C.close(fds[index]) != 0 || flags != wanted { good = false }
		}
		if !good { C.puts(c'LINUX FCNTLSYNC FAIL: synchronization, status, word, error or state controls'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX FCNTLSYNC REFERENCE: PASS') } else { C.puts(c'LINUX FCNTLSYNC: PASS') }; C.fflush(nil); for { C.pause() }
	}; return 0
}
