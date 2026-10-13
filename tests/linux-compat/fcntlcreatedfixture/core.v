// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlcreatedfixture

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

const created_query = u64(1028)
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
fn C.chown(&char, u32, u32) i32
fn C.chdir(&char) i32
fn C.symlink(&char, &char) i32
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
fn expected(class i32) i32 { return if class == 0 || class == 2 || class == 8 || class == 12 || class == 13 { 1 } else { 0 } }
fn record(counts &Counts, kind i32, good bool, ordinary bool, result Query) {
	unsafe {
		mut tally := &Counts(counts); tally.calls[kind]++
		if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX FCNTLCREATED DETAIL: ordinary=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), kind, tally.calls[kind], result.ret, result.code); C.fflush(nil) } }
	}
}
fn checked(counts &Counts, kind i32, ordinary bool, source u32, arg u64, want i32, prefix i32) {
	fd := u64(source) | if prefix == 1 { u64(0xffffffff00000000) } else { 0 }
	cmd := created_query | if prefix == 2 { u64(0x8000000000000000) } else { 0 }
	result := query(fd, cmd, arg)
	record(counts, kind, result.ret == want && result.code == if want < 0 { i32(C.EBADF) } else { i32(0) }, ordinary, result)
}
fn libc_check(counts &Counts, ordinary bool, source i32, arg u64, want i32) {
	unsafe { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(source, i32(created_query), arg); record(counts, 2, ret == want && *slot == if want < 0 { i32(C.EBADF) } else { i32(0) }, ordinary, Query{isize(ret), *slot}) }
}
fn matrix(counts &Counts, sources &i32, ordinary bool, limits &C.rlimit) {
	unsafe {
		arguments := [u64(0), u64(1), u64(0xffffffff), u64(0x100000000), u64(0xffffffffffffffff), u64(0x8000000000000000), u64(0xabcdef0100000000), u64(0x7ffffffff000)]!
		for left in 0 .. 48 { for arg in arguments { for prefix in 0 .. 3 { checked(counts, 0, ordinary, u32(sources[left]), arg, expected(i32(left / 3)), i32(prefix)) }; libc_check(counts, ordinary, sources[left], arg, expected(i32(left / 3))) } }
		for source in [u32(127), u32(0x80000000), u32(0xffffffff), u32(1048576)]! { for arg in arguments { for prefix in 0 .. 3 { checked(counts, 1, ordinary, source, arg, -1, i32(prefix)) }; libc_check(counts, ordinary, i32(source), arg, -1) } }
		mut bound := &C.rlimit(limits)
		for limit in [u64(8), u64(0)]! {
			bound.rlim_cur = limit; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
			for arg in arguments { for prefix in 0 .. 3 { checked(counts, 1, ordinary, 64, arg, 1, i32(prefix)); checked(counts, 1, ordinary, 65, arg, 0, i32(prefix)); checked(counts, 1, ordinary, 127, arg, -1, i32(prefix)) } }
		}
		bound.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
		for arg in arguments { for prefix in 0 .. 3 {
			checked(counts, 3, ordinary, 66, arg, -1, i32(prefix))
			if C.dup3(sources[1], 66, C.O_CLOEXEC) != 66 { C._exit(1) }; checked(counts, 3, ordinary, 66, arg, 1, i32(prefix))
			if C.dup3(sources[3], 66, 0) != 66 { C._exit(1) }; checked(counts, 3, ordinary, 66, arg, 0, i32(prefix))
			if C.close(66) != 0 { C._exit(1) }; checked(counts, 3, ordinary, 66, arg, -1, i32(prefix))
		} }
	}
}
fn capture(fd i32, target &State) bool {
	unsafe { mut state := &State(target); state.flags = C.fcntl(fd, C.F_GETFD); state.status = C.fcntl(fd, C.F_GETFL); state.cursor = C.lseek(fd, 0, C.SEEK_CUR); return C.fstat(fd, &state.metadata) == 0 && state.flags >= 0 && state.status >= 0 }
}
fn equal(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size }
fn stable(fd i32, before &State) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && equal(&before.metadata, after) && C.fcntl(fd, C.F_GETFD) == before.flags && C.fcntl(fd, C.F_GETFL) == before.status && C.lseek(fd, 0, C.SEEK_CUR) == before.cursor }
}
fn storage_cycle() bool {
	unsafe {
		for source in [u64(64), u64(65), u64(127)]! { result := query(source | 0x100000000, created_query | 0x200000000, 0xffffffffffffffff); if result.ret != if source == 64 { 1 } else if source == 65 { 0 } else { -1 } || result.code != if source == 127 { i32(C.EBADF) } else { i32(0) } { return false } }; return true
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
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FCNTLCREATED SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FCNTLCREATED STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(inherited &i32, ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		if C.chdir(if ordinary { &char(c'/tmp/linux-fcntlcreated-user') } else { &char(c'/tmp/linux-fcntlcreated-root') }) != 0 { return false }
		limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }
		mut sources := &i32(C.alloca(usize(48 * sizeof(i32)))); for i in 0 .. 48 { sources[i] = -1 }; sources[0] = inherited[0]; sources[3] = inherited[1]
		sources[6] = C.open(c'file', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); sources[9] = C.open(c'file', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); sources[12] = C.open(c'file', C.O_RDWR | C.O_CLOEXEC); sources[15] = C.open(c'file', C.O_CREAT | C.O_TRUNC | C.O_RDWR | C.O_CLOEXEC, i32(0o644))
		sources[18] = C.open(c'file', C.O_PATH | C.O_CREAT | C.O_EXCL | C.O_TRUNC | C.O_CLOEXEC, i32(0o644))
		if C.symlink(c'file', c'link') != 0 || C.symlink(c'target', c'dangling') != 0 { return false }
		sources[21] = C.open(c'link', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); sources[24] = C.open(c'dangling', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); sources[27] = C.open(c'dangling', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, i32(0o644))
		sources[30] = C.open(c'dangling', C.O_PATH | C.O_NOFOLLOW | C.O_CLOEXEC); sources[33] = C.open(c'.', C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC)
		sources[36] = C.open(c'gone', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); if C.unlink(c'gone') != 0 { return false }; sources[39] = C.open(c'gone', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644))
		mut pipe := [2]i32{}; if C.pipe2(&pipe[0], C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.write(pipe[1], c'AB', 2) != 2 { return false }; sources[42] = pipe[0]; sources[45] = pipe[1]
		for class in 0 .. 16 { if sources[class * 3] < 0 { C.puts(c'LINUX FCNTLCREATED FAIL: setup open'); return false }; sources[class * 3 + 1] = C.dup(sources[class * 3]); sources[class * 3 + 2] = C.fcntl(sources[class * 3], C.F_DUPFD_CLOEXEC, 40); if sources[class * 3 + 1] < 0 || sources[class * 3 + 2] < 0 { return false } }
		if C.dup3(sources[0], 64, C.O_CLOEXEC) != 64 || C.dup3(sources[3], 65, 0) != 65 { return false }
		// Failed exclusive creates and missing O_PATH names cannot create data.
		mut good := C.open(c'file', C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o644)) == -1 && *C.__errno_location() == C.EEXIST
		if C.open(c'absent', C.O_PATH | C.O_CREAT, i32(0o644)) != -1 || *C.__errno_location() != C.ENOENT { good = false }
		for fd in [sources[6], sources[24], sources[36], sources[39]]! { if C.write(fd, c'created-data-ok!', 16) != 16 || C.lseek(fd, 3, C.SEEK_SET) != 3 { good = false } }
		if C.lseek(sources[9], 9, C.SEEK_SET) != 9 { good = false }
		states := &State(C.alloca(usize(50 * sizeof(State)))); for i in 0 .. 48 { if !capture(sources[i], &states[i]) { return false } }; if !capture(64, &states[48]) || !capture(65, &states[49]) { return false }
		if !equal(&states[6].metadata, &states[9].metadata) || !equal(&states[24].metadata, &states[27].metadata) || states[36].metadata.st_nlink != 0 || states[36].metadata.st_ino == states[39].metadata.st_ino { good = false }
		counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; matrix(counts, sources, ordinary, limits)
		for kind in 0 .. 4 { C.printf(c'LINUX FCNTLCREATED CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		for i in 0 .. 48 { if !stable(sources[i], &states[i]) { good = false } }; if !stable(64, &states[48]) || !stable(65, &states[49]) { good = false }
		if C.lseek(sources[7], 4, C.SEEK_SET) != 4 || C.lseek(sources[6], 0, C.SEEK_CUR) != 4 || C.lseek(sources[9], 0, C.SEEK_CUR) != 9 || C.lseek(sources[6], 3, C.SEEK_SET) != 3 { good = false }
		mut data := [16]char{}; for fd in [sources[6], sources[9], sources[24], sources[27], sources[36], sources[39]]! { if C.pread(fd, &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'created-data-ok!', 16) != 0 { good = false } }
		if C.read(sources[42], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) { good = false }
		if good && !reference_run && !storage(ordinary) { good = false }
		for i in 0 .. 48 { if C.close(sources[i]) != 0 { good = false } }; if C.close(64) != 0 || C.close(65) != 0 { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut inherited := [2]i32{}; inherited[0] = C.open(c'/tmp/linux-fcntlcreated-parent', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); inherited[1] = C.open(c'/tmp/linux-fcntlcreated-parent', C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); if inherited[0] < 0 || inherited[1] < 0 { return 1 }
		if C.mkdir(c'/tmp/linux-fcntlcreated-user', u32(0o755)) != 0 || C.chown(c'/tmp/linux-fcntlcreated-user', 1000, 1000) != 0 || C.mkdir(c'/tmp/linux-fcntlcreated-root', u32(0o755)) != 0 { return 1 }
		mut good := true
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(&inherited[0], ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		if C.fcntl(inherited[0], C.F_GETFD) != C.FD_CLOEXEC || C.fcntl(inherited[1], C.F_GETFD) != C.FD_CLOEXEC || C.close(inherited[0]) != 0 || C.close(inherited[1]) != 0 { good = false }
		if !good { C.puts(c'LINUX FCNTLCREATED FAIL: creation, word, error or state controls'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX FCNTLCREATED REFERENCE: PASS') } else { C.puts(c'LINUX FCNTLCREATED: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
