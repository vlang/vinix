// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlownerfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct C.rlimit { mut: rlim_cur u64 rlim_max u64 }
struct Counts { mut: calls [5]u64 failures [5]u64 }
struct State { mut: metadata C.stat flags i32 status i32 cursor i64 signal i32 owner i32 owner_kind i32 }
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
fn C.rmdir(&char) i32
fn C.mkdir(&char, u32) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, u64, ...) i32
fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.getpid() i32
fn C.getpgrp() i32
fn C.setpgid(i32, i32) i32
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
	unsafe { mut tally := &Counts(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX FCNTLOWNER DETAIL: ordinary=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), kind, tally.calls[kind], result.ret, result.code); C.fflush(nil) } } }
}

fn owned(fd i32, kind i32, pid i32) bool {
	unsafe { out := &i32(C.alloca(usize(2 * sizeof(i32)))); out[0] = -9; out[1] = -9; slot := C.__errno_location(); *slot = 0; ret := C.fcntl(fd, C.F_GETOWN_EX, out); if kind < 0 { return ret == -1 && *slot == C.EBADF }; return ret == 0 && out[0] == kind && out[1] == pid }
}
fn capture(fd i32, target &State) bool {
	unsafe { mut state := &State(target); state.flags = C.fcntl(fd, C.F_GETFD); state.status = C.fcntl(fd, C.F_GETFL); state.cursor = C.lseek(fd, 0, C.SEEK_CUR); state.signal = C.fcntl(fd, C.F_GETSIG); out := &i32(C.alloca(usize(2 * sizeof(i32)))); state.owner_kind = -1; state.owner = -1; if C.fcntl(fd, C.F_GETOWN_EX, out) == 0 { state.owner_kind = out[0]; state.owner = out[1] }; return C.fstat(fd, &state.metadata) == 0 && state.flags >= 0 && state.status >= 0 }
}
fn equal(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size }
fn stable(fd i32, before &State) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && equal(&before.metadata, after) && C.fcntl(fd, C.F_GETFD) == before.flags && C.fcntl(fd, C.F_GETFL) == before.status && C.lseek(fd, 0, C.SEEK_CUR) == before.cursor }
}
fn pending(fds &i32) bool {
	unsafe { bytes := &i32(C.alloca(usize(sizeof(i32)))); *bytes = -1; if C.ioctl(fds[9], u64(C.FIONREAD), bytes) != 0 || *bytes != 2 { return false }; *bytes = -1; return C.ioctl(fds[15], u64(C.FIONREAD), bytes) == 0 && *bytes == 2 }
}

fn state_check(fds &i32, states &State, changed i32, wanted_kind i32, wanted_pid i32) bool {
	unsafe { mut good := pending(fds)
		for index in 0 .. 27 {
			class := if index < 18 { i32(index / 3) } else if index == 24 { 1 } else if index == 25 { 5 } else { -1 }
			kind := if class == changed && changed >= 0 { wanted_kind } else { states[index].owner_kind }; pid := if class == changed && changed >= 0 { wanted_pid } else { states[index].owner }
			if !owned(fds[index], kind, pid) || C.fcntl(fds[index], C.F_GETSIG) != states[index].signal || C.fcntl(fds[index], C.F_GETFD) != states[index].flags || C.fcntl(fds[index], C.F_GETFL) != states[index].status { good = false }
			if (index % 3 == 0 || index >= 24) && !stable(fds[index], &states[index]) { good = false }
		}; return good
	}
}
fn checked(counts &Counts, kind i32, ordinary bool, fds &i32, states &State, source u32, class i32, arg u64, prefix i32, libc bool) {
	unsafe {
		if source == 66 && class >= 0 && !capture(66, &states[27]) { C._exit(1) }
		fd := u64(source) | if prefix == 1 || prefix == 4 { u64(0xffffffff00000000) } else { 0 }; cmd := u64(C.F_SETOWN) | if prefix == 2 || prefix == 4 { u64(0x8000000000000000) } else { 0 }; value := arg | if prefix == 3 { u64(0xabcdef0100000000) } else if prefix == 4 { u64(0xffffffff00000000) } else { 0 }
		id := i32(u32(arg)); valid := class >= 0 && (id == 0 || id == C.getpid() || id == -C.getpgrp()); wanted_kind := if valid { if id < 0 { i32(C.F_OWNER_PGRP) } else { i32(C.F_OWNER_PID) } } else if class >= 0 { states[class * 3].owner_kind } else { -1 }; wanted_pid := if valid { if id < 0 { -id } else { id } } else if class >= 0 { states[class * 3].owner } else { -1 }
		mut result := Query{}; if libc { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(i32(source), C.F_SETOWN, id); result = Query{isize(ret), *slot} } else { result = query(fd, cmd, value) }
		expected := if valid { i32(0) } else if class < 0 { i32(C.EBADF) } else if id == i32(-2147483648) { i32(C.EINVAL) } else { i32(C.ESRCH) }; mut good := result.ret == if valid { 0 } else { -1 } && result.code == expected
		if !state_check(fds, states, class, wanted_kind, wanted_pid) { good = false }
		if class >= 0 { slot := C.__errno_location(); *slot = 0; gotten := C.fcntl(i32(source), C.F_GETOWN); if gotten != if wanted_kind == C.F_OWNER_PGRP { -wanted_pid } else { wanted_pid } || *slot != 0 { good = false } }
		if class >= 0 { if source == 66 && (!stable(66, &states[27]) || !owned(66, wanted_kind, wanted_pid)) { good = false }; owner := &i32(C.alloca(usize(2 * sizeof(i32)))); owner[0] = states[class * 3].owner_kind; owner[1] = states[class * 3].owner; if C.fcntl(i32(source), C.F_SETOWN_EX, owner) != 0 || !state_check(fds, states, -1, 0, 0) { C._exit(1) } }
		record(counts, kind, good, ordinary, result)
	}
}
fn extended(counts &Counts, ordinary bool, fds &i32, states &State, index i32, kind i32, pid i32, prefix i32, badptr u64) {
	unsafe {
		owner := &i32(C.alloca(usize(2 * sizeof(i32)))); owner[0] = kind; owner[1] = pid
		source := if index < 24 { u32(fds[index]) } else if index == 24 { u32(127) } else if index == 25 { u32(0x80000000) } else { u32(0xffffffff) }; fd := u64(source) | if prefix == 1 { u64(0xffffffff00000000) } else { 0 }; cmd := u64(C.F_SETOWN_EX) | if prefix == 2 { u64(0x8000000000000000) } else { 0 }; ptr := if badptr == 0 { u64(voidptr(owner)) } else if badptr == 1 { u64(0) } else if badptr == 2 { u64(1) } else { u64(0x8000000000000001) }
		class := if index < 18 { index / 3 } else { -1 }; valid := class >= 0 && badptr == 0 && kind >= 0 && kind <= 2 && (pid == 0 || pid == if kind == 2 { C.getpgrp() } else { C.getpid() }); expected := if class < 0 { i32(C.EBADF) } else if badptr != 0 { i32(C.EFAULT) } else if kind < 0 || kind > 2 { i32(C.EINVAL) } else if !valid { i32(C.ESRCH) } else { i32(0) }
		result := query(fd, cmd, ptr); wanted_kind := if valid { kind } else if class >= 0 { states[class * 3].owner_kind } else { -1 }; wanted_pid := if valid { pid } else if class >= 0 { states[class * 3].owner } else { -1 }; mut good := result.ret == if valid { 0 } else { -1 } && result.code == expected && state_check(fds, states, class, wanted_kind, wanted_pid)
		if badptr == 0 && (owner[0] != kind || owner[1] != pid) { good = false }
		if class >= 0 { owner[0] = states[class * 3].owner_kind; owner[1] = states[class * 3].owner; if C.fcntl(fds[index], C.F_SETOWN_EX, owner) != 0 || !state_check(fds, states, -1, 0, 0) { C._exit(1) } }; record(counts, 3, good, ordinary, result)
	}
}
fn getters(counts &Counts, ordinary bool, fds &i32, states &State) {
	unsafe { out := &i32(C.alloca(usize(2 * sizeof(i32)))); for index in 0 .. 27 { for prefix in 0 .. 7 {
		out[0] = -9; out[1] = -9; fd := u64(u32(fds[index])) | if prefix == 1 || prefix == 3 { u64(0xffffffff00000000) } else { 0 }; cmd := u64(C.F_GETOWN_EX) | if prefix == 2 || prefix == 3 { u64(0x8000000000000000) } else { 0 }; ptr := if prefix < 4 { u64(voidptr(out)) } else if prefix == 4 { u64(0) } else if prefix == 5 { u64(1) } else { u64(0x8000000000000001) }; normal := index < 18 || index >= 24; expected := if !normal { i32(C.EBADF) } else if prefix >= 4 { i32(C.EFAULT) } else { i32(0) }; result := query(fd, cmd, ptr)
		record(counts, 4, result.ret == if expected == 0 { 0 } else { -1 } && result.code == expected && (expected != 0 || (out[0] == states[index].owner_kind && out[1] == states[index].owner)) && stable(fds[index], &states[index]) && pending(fds), ordinary, result)
	}
		for prefix in 0 .. 4 {
			fd := u64(u32(fds[index])) | if prefix == 1 || prefix == 3 { u64(0xffffffff00000000) } else { 0 }; cmd := u64(C.F_GETOWN) | if prefix == 2 || prefix == 3 { u64(0x8000000000000000) } else { 0 }; arg := [u64(0), 1, 0x8000000000000000, u64(-1)]![prefix]; normal := index < 18 || index >= 24; result := query(fd, cmd, arg)
			record(counts, 4, result.ret == if normal { isize(states[index].owner) } else { -1 } && result.code == if normal { i32(0) } else { i32(C.EBADF) } && state_check(fds, states, -1, 0, 0), ordinary, result)
			if normal { out[0] = states[index].owner_kind; out[1] = states[index].owner; if C.fcntl(fds[index], C.F_SETOWN_EX, out) != 0 || !state_check(fds, states, -1, 0, 0) { C._exit(1) } }
		}
	} }
}
fn matrix(counts &Counts, fds &i32, states &State, ordinary bool, limits &C.rlimit) {
	unsafe {
		args := [u64(0), u64(u32(C.getpid())), u64(u32(-C.getpgrp())), u64(60000), u64(u32(-60000)), u64(0x7fffffff), u64(0x80000000)]!
		for index in 0 .. 18 { for arg in args { for prefix in 0 .. 5 { checked(counts, 0, ordinary, fds, states, u32(fds[index]), i32(index / 3), arg, i32(prefix), false) }; checked(counts, 2, ordinary, fds, states, u32(fds[index]), i32(index / 3), arg, 0, true) } }
		for source in [u32(127), u32(0x80000000), u32(0xffffffff)]! { for arg in args { for prefix in 0 .. 5 { checked(counts, 1, ordinary, fds, states, source, -1, arg, i32(prefix), false) }; checked(counts, 2, ordinary, fds, states, source, -1, arg, 0, true) } }
		for index in 18 .. 24 { for arg in args { for prefix in 0 .. 5 { checked(counts, 1, ordinary, fds, states, u32(fds[index]), -1, arg, i32(prefix), false) }; checked(counts, 2, ordinary, fds, states, u32(fds[index]), -1, arg, 0, true) } }
		for index in 0 .. 27 { for kind in [i32(-1), 0, 1, 2, 3]! { for pid in [i32(0), if kind == 2 { C.getpgrp() } else { C.getpid() }, 65536, -1, -2147483648]! { for prefix in 0 .. 3 { extended(counts, ordinary, fds, states, i32(index), kind, pid, i32(prefix), 0) } } }; for badptr in [u64(1), 2, 3]! { extended(counts, ordinary, fds, states, i32(index), -1, -1, 0, badptr) }
		}
		getters(counts, ordinary, fds, states); mut bound := &C.rlimit(limits)
		for limit in [u64(8), 0]! { bound.rlim_cur = limit; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }; for arg in args { checked(counts, 4, ordinary, fds, states, 64, 1, arg, 4, false); checked(counts, 4, ordinary, fds, states, 65, 5, arg, 4, false) } }
		bound.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }; for arg in args { checked(counts, 4, ordinary, fds, states, 66, -1, arg, 4, false); if C.dup3(fds[3], 66, C.O_CLOEXEC) != 66 { C._exit(1) }; checked(counts, 4, ordinary, fds, states, 66, 1, arg, 4, false); if C.dup3(fds[15], 66, 0) != 66 { C._exit(1) }; checked(counts, 4, ordinary, fds, states, 66, 5, arg, 4, false); if C.close(66) != 0 { C._exit(1) }; checked(counts, 4, ordinary, fds, states, 66, -1, arg, 4, false) }
		for class in 0 .. 2 { good := C.lseek(fds[class * 3 + 1], 4, C.SEEK_CUR) == 7 && C.lseek(fds[class * 3], 0, C.SEEK_CUR) == 7 && C.lseek(fds[class * 3 + 2], -4, C.SEEK_CUR) == 3 && C.lseek(fds[class * 3], 0, C.SEEK_CUR) == 3; record(counts, 4, good, ordinary, Query{}) }
	}
}
fn cycle(fds &i32) bool {
	unsafe { owner := &i32(C.alloca(usize(2 * sizeof(i32)))); for source in [fds[3], fds[15]]! { alias := C.dup(source); if alias < 0 { return false }; mut good := true
		for arg in [u64(u32(C.getpid())), u64(65536), u64(0x80000000), u64(0)]! { result := query(u64(u32(alias)) | 0x100000000, u64(C.F_SETOWN) | 0x200000000, arg | 0xabcdef0100000000); valid := arg == 0 || arg == u64(u32(C.getpid())); if result.ret != if valid { 0 } else { -1 } || result.code != if valid { 0 } else if arg == 0x80000000 { C.EINVAL } else { C.ESRCH } || !owned(source, C.F_OWNER_PID, if arg == 0 { 0 } else { C.getpid() }) { good = false } }
		for kind in 0 .. 3 { owner[0] = i32(kind); owner[1] = if kind == 2 { C.getpgrp() } else { C.getpid() }; if C.fcntl(alias, C.F_SETOWN_EX, owner) != 0 || !owned(source, owner[0], owner[1]) { good = false }; owner[1] = -1; result := query(u64(u32(alias)), u64(C.F_SETOWN_EX), u64(voidptr(owner))); if result.ret != -1 || result.code != C.ESRCH || !owned(source, i32(kind), if kind == 2 { C.getpgrp() } else { C.getpid() }) { good = false } }
		if C.fcntl(alias, C.F_SETOWN, C.getpid()) != 0 || C.close(alias) != 0 { good = false }; if !good { return false }
	}; missing := query(127, u64(C.F_SETOWN), u64(0x100000001)); return missing.ret == -1 && missing.code == C.EBADF && pending(fds) }
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe { mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0; mut position := 0; mut large := false
		for position < int(length) { mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 { if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++ }
			else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }; for position < int(length) && data[position] != char(10) { position++ }; position++
		}; return counts.rows > 0 && large
	}
}
fn storage(fds &i32, ordinary bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(fds) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(fds) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FCNTLOWNER SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FCNTLOWNER STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(fds &i32, ordinary bool, reference_run bool) bool {
	unsafe { C.alarm(300); if C.setpgid(0, 0) != 0 { return false }; if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }
		states := &State(C.alloca(usize(28 * sizeof(State)))); for index in 0 .. 27 { if (index < 18 || index >= 24) && C.fcntl(fds[index], C.F_SETOWN, C.getpid()) != 0 { return false }; if !capture(fds[index], &states[index]) { return false } }
		counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; matrix(counts, fds, states, ordinary, limits); mut good := state_check(fds, states, -1, 0, 0)
		for kind in 0 .. 5 { C.printf(c'LINUX FCNTLOWNER CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(fds, ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		fds := &i32(C.alloca(usize(27 * sizeof(i32)))); for index in 0 .. 27 { fds[index] = -1 }
		seed := C.open(c'/tmp/linux-fcntlowner-file', C.O_CREAT | C.O_EXCL | C.O_WRONLY, i32(0o644)); if seed < 0 || C.write(seed, c'fcntl-own-data!!', 16) != 16 || C.close(seed) != 0 || C.mkdir(c'/tmp/linux-fcntlowner-dir', 0o755) != 0 { return 1 }
		fds[0] = C.open(c'/tmp/linux-fcntlowner-file', C.O_RDONLY | C.O_CLOEXEC); fds[3] = C.open(c'/tmp/linux-fcntlowner-file', C.O_RDWR | C.O_CLOEXEC); fds[6] = C.open(c'/tmp/linux-fcntlowner-dir', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); pair := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK | C.SOCK_CLOEXEC, 0, pair) != 0 { return 1 }
		fds[9] = pipe[0]; fds[12] = pipe[1]; fds[15] = pair[0]; fds[26] = pair[1]; if C.write(pipe[1], c'AB', 2) != 2 || C.write(pair[1], c'AB', 2) != 2 { return 1 }
		for class in 0 .. 6 { principal := fds[class * 3]; if principal < 0 || C.fcntl(principal, C.F_SETSIG, i32(class + 10)) != 0 || (class < 2 && C.lseek(principal, 3, C.SEEK_SET) != 3) { return 1 }; fds[class * 3 + 1] = C.dup(principal); fds[class * 3 + 2] = C.fcntl(principal, C.F_DUPFD_CLOEXEC, 40); if fds[class * 3 + 1] < 0 || fds[class * 3 + 2] < 0 { return 1 } }
		for class in 0 .. 2 { fds[18 + class * 3] = C.open(if class == 0 { &char(c'/tmp/linux-fcntlowner-file') } else { &char(c'/tmp/linux-fcntlowner-dir') }, C.O_PATH | C.O_CLOEXEC); fds[19 + class * 3] = C.dup(fds[18 + class * 3]); fds[20 + class * 3] = C.fcntl(fds[18 + class * 3], C.F_DUPFD_CLOEXEC, 40); if fds[18 + class * 3] < 0 || fds[19 + class * 3] < 0 || fds[20 + class * 3] < 0 { return 1 } }
		if C.dup3(fds[3], 64, C.O_CLOEXEC) != 64 || C.dup3(fds[15], 65, 0) != 65 { return 1 }; fds[24] = 64; fds[25] = 65
		mut good := true; for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(fds, ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut data := [16]char{}; for index in [0, 3]! { if C.pread(fds[index], &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'fcntl-own-data!!', 16) != 0 { good = false } }
		if !pending(fds) || C.read(fds[9], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) || C.read(fds[15], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) { good = false }
		for index in 0 .. 27 { flags := C.fcntl(fds[index], C.F_GETFD); wanted := if (index < 24 && index % 3 == 1) || index == 25 { 0 } else { C.FD_CLOEXEC }; if C.close(fds[index]) != 0 || flags != wanted { good = false } }
		if C.unlink(c'/tmp/linux-fcntlowner-file') != 0 || C.rmdir(c'/tmp/linux-fcntlowner-dir') != 0 { good = false }
		if !good { C.puts(c'LINUX FCNTLOWNER FAIL: owner targets, alias state, errors, queues or retention'); C.fflush(nil); return 1 }; if reference_run { C.puts(c'LINUX FCNTLOWNER REFERENCE: PASS') } else { C.puts(c'LINUX FCNTLOWNER: PASS') }; C.fflush(nil); for { C.pause() }
	}; return 0
}
