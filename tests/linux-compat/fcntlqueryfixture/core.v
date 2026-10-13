// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlqueryfixture

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

const duplicate_query = u64(1027)
struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct C.rlimit { mut: rlim_cur u64 rlim_max u64 }
struct Counts { mut: calls [3]u64 failures [3]u64 }
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
fn C.mkfifo(&char, u32) i32
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

fn query(fd u64, cmd u64, target u64) Query {
	unsafe { slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_fcntl, fd, cmd, target); return Query{ret, *slot} }
}
fn record(counts &Counts, kind i32, good bool, ordinary bool, result Query) {
	unsafe {
		mut tally := &Counts(counts); tally.calls[kind]++
		if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX FCNTLQUERY DETAIL: ordinary=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), kind, tally.calls[kind], result.ret, result.code); C.fflush(nil) } }
	}
}
fn capture(fd i32, target &State) bool {
	unsafe { mut state := &State(target); state.flags = C.fcntl(fd, C.F_GETFD); state.status = C.fcntl(fd, C.F_GETFL); state.cursor = C.lseek(fd, 0, C.SEEK_CUR); return C.fstat(fd, &state.metadata) == 0 && state.flags >= 0 && state.status >= 0 }
}
fn equal(left &C.stat, right &C.stat) bool {
	return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode
		&& left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size
}
fn stable(fd i32, before &State) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && equal(&before.metadata, after) && C.fcntl(fd, C.F_GETFD) == before.flags && C.fcntl(fd, C.F_GETFL) == before.status && C.lseek(fd, 0, C.SEEK_CUR) == before.cursor }
}
fn checked(counts &Counts, kind i32, ordinary bool, source u32, target u32, expected i32, prefix i32) {
	fd := u64(source) | if prefix == 1 { u64(0xffffffff00000000) } else { 0 }
	cmd := duplicate_query | if prefix == 2 { u64(0x8000000000000000) } else { 0 }
	arg := u64(target) | if prefix == 3 { u64(0xabcdef0100000000) } else { 0 }
	result := query(fd, cmd, arg)
	record(counts, kind, result.ret == expected && result.code == if expected < 0 { i32(C.EBADF) } else { i32(0) }, ordinary, result)
}
fn matrix(counts &Counts, sources &i32, independent &i32, ordinary bool, limits &C.rlimit) {
	unsafe {
		for left in 0 .. 24 {
			for right in 0 .. 24 { for prefix in 0 .. 4 { checked(counts, 0, ordinary, u32(sources[left]), u32(sources[right]), if left / 3 == right / 3 { 1 } else { 0 }, i32(prefix)) } }
			for right in 0 .. 8 { for prefix in 0 .. 4 { checked(counts, 0, ordinary, u32(sources[left]), u32(independent[right]), 0, i32(prefix)) } }
			for target in [u32(127), u32(0x80000000), u32(0xffffffff), u32(1048576)]! { for prefix in 0 .. 4 { checked(counts, 1, ordinary, u32(sources[left]), target, -1, i32(prefix)) } }
		}
		for source in [u32(127), u32(0x80000000), u32(0xffffffff), u32(1048576)]! {
			for target in [u32(sources[0]), u32(64), u32(65), u32(0xffffffff), u32(0x80000000)]! { for prefix in 0 .. 4 { checked(counts, 1, ordinary, source, target, -1, i32(prefix)) } }
		}
		mut bound := &C.rlimit(limits)
		for limit in [u64(8), u64(0)]! {
			bound.rlim_cur = limit; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
			for prefix in 0 .. 4 {
				checked(counts, 1, ordinary, u32(sources[0]), 64, 1, i32(prefix)); checked(counts, 1, ordinary, 64, u32(sources[1]), 1, i32(prefix))
				checked(counts, 1, ordinary, 64, 65, 0, i32(prefix)); checked(counts, 1, ordinary, 64, 64, 1, i32(prefix))
				checked(counts, 1, ordinary, 64, 127, -1, i32(prefix)); checked(counts, 1, ordinary, 127, 64, -1, i32(prefix))
			}
		}
		bound.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
		for left in 0 .. 24 {
			for right in 0 .. 24 { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(sources[left], i32(duplicate_query), sources[right]); record(counts, 2, ret == if left / 3 == right / 3 { 1 } else { 0 } && *slot == 0, ordinary, Query{isize(ret), *slot}) }
			for right in 0 .. 8 { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(sources[left], i32(duplicate_query), independent[right]); record(counts, 2, ret == 0 && *slot == 0, ordinary, Query{isize(ret), *slot}) }
			for target in [i32(127), i32(-1), i32(-2147483648), i32(1048576)]! { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(sources[left], i32(duplicate_query), target); record(counts, 2, ret == -1 && *slot == C.EBADF, ordinary, Query{isize(ret), *slot}) }
		}
		for source in [i32(127), i32(-1), i32(-2147483648), i32(1048576)]! { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(source, i32(duplicate_query), 64); record(counts, 2, ret == -1 && *slot == C.EBADF, ordinary, Query{isize(ret), *slot}) }
		// Match the two directory descriptions' live reference counts and
		// flags without turning the separate open into an alias of the source.
		for number in 68 .. 72 { if C.dup3(independent[2], i32(number), C.O_CLOEXEC) != number { C._exit(1) } }
		for prefix in 0 .. 4 { checked(counts, 2, ordinary, u32(sources[6]), u32(independent[2]), 0, i32(prefix)); checked(counts, 2, ordinary, u32(sources[6]), u32(sources[7]), 1, i32(prefix)) }
		for number in 68 .. 72 { if C.close(i32(number)) != 0 { C._exit(1) } }
		// Descriptor number 66 changes identity through real close/replacement.
		for class in [0, 1, 5, 6, 7]! { for prefix in 0 .. 4 {
			checked(counts, 2, ordinary, u32(sources[class * 3]), 66, -1, i32(prefix))
			if C.dup3(sources[class * 3 + 1], 66, C.O_CLOEXEC) != 66 { C._exit(1) }; checked(counts, 2, ordinary, u32(sources[class * 3]), 66, 1, i32(prefix))
			if C.dup3(independent[class], 66, 0) != 66 { C._exit(1) }; checked(counts, 2, ordinary, u32(sources[class * 3]), 66, 0, i32(prefix))
			if C.close(66) != 0 { C._exit(1) }; checked(counts, 2, ordinary, u32(sources[class * 3]), 66, -1, i32(prefix))
		} }
	}
}
fn storage_cycle(source i32) bool {
	unsafe {
	for target in [u64(64), u64(65), u64(127), u64(0xffffffff)]! {
		result := query(u64(source) | 0x100000000, duplicate_query | 0x200000000, target | 0xabcdef0100000000)
		if target < 127 { if result.ret != if target == 64 { 1 } else { 0 } || result.code != 0 { return false } }
		else if result.ret != -1 || result.code != C.EBADF { return false }
	}
	return true
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}
fn storage(source i32, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(source) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(source) { return false } }; C.usleep(13000000)
		if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FCNTLQUERY SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FCNTLQUERY STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}

fn qualify(sources &i32, independent &i32, ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }
		states := &State(C.alloca(usize(34 * sizeof(State))))
		for i in 0 .. 24 { if !capture(sources[i], &states[i]) { return false } }
		for i in 0 .. 8 { if !capture(independent[i], &states[24 + i]) { return false } }; if !capture(64, &states[32]) || !capture(65, &states[33]) { return false }
		for class in 0 .. 6 { if !equal(&states[class * 3].metadata, &states[24 + class].metadata) { return false } }
		counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; matrix(counts, sources, independent, ordinary, limits)
		mut good := true
		for kind in 0 .. 3 { C.printf(c'LINUX FCNTLQUERY CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		for i in 0 .. 24 { if !stable(sources[i], &states[i]) { good = false } }; for i in 0 .. 8 { if !stable(independent[i], &states[24 + i]) { good = false } }
		if !stable(64, &states[32]) || !stable(65, &states[33]) { good = false }
		// The queried alias shares a cursor while a separate open does not.
		if C.lseek(sources[1], 4, C.SEEK_SET) != 4 || C.lseek(sources[0], 0, C.SEEK_CUR) != 4 || C.lseek(independent[0], 0, C.SEEK_CUR) != 9 { good = false }
		if C.lseek(sources[0], 3, C.SEEK_SET) != 3 { good = false }
		if good && !reference_run && !storage(sources[0], ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut sources := &i32(C.alloca(usize(24 * sizeof(i32)))); mut independent := &i32(C.alloca(usize(8 * sizeof(i32)))); for i in 0 .. 24 { sources[i] = -1 }; for i in 0 .. 8 { independent[i] = -1 }
		sources[0] = C.open(c'/tmp/linux-fcntlquery-file', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); if sources[0] < 0 || C.write(sources[0], c'query-data-ok!!!', 16) != 16 || C.lseek(sources[0], 3, C.SEEK_SET) != 3 { return 1 }
		independent[0] = C.open(c'/tmp/linux-fcntlquery-file', C.O_RDWR); if independent[0] < 0 || C.lseek(independent[0], 9, C.SEEK_SET) != 9 { return 1 }
		private := C.open(c'/tmp/linux-fcntlquery-private', C.O_CREAT | C.O_EXCL | C.O_WRONLY, i32(0o600)); if private < 0 || C.write(private, c'P', 1) != 1 || C.close(private) != 0 { return 1 }
		if C.mkdir(c'/tmp/linux-fcntlquery-dir', u32(0o755)) != 0 || C.mkfifo(c'/tmp/linux-fcntlquery-fifo', u32(0o644)) != 0 || C.symlink(c'/tmp/linux-fcntlquery-file', c'/tmp/linux-fcntlquery-link') != 0 { return 1 }
		for class in 1 .. 5 {
			path := match class { 1 { &char(c'/tmp/linux-fcntlquery-private') } 2 { &char(c'/tmp/linux-fcntlquery-dir') } 3 { &char(c'/tmp/linux-fcntlquery-fifo') } else { &char(c'/tmp/linux-fcntlquery-link') } }
			flags := C.O_PATH | if class == 4 { C.O_NOFOLLOW } else { 0 }
			sources[class * 3] = C.open(path, flags | C.O_CLOEXEC); independent[class] = C.open(path, flags | C.O_CLOEXEC)
			if sources[class * 3] < 0 || independent[class] < 0 { return 1 }
		}
		sources[15] = C.open(c'/tmp/linux-fcntlquery-unlinked', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); if sources[15] < 0 || C.write(sources[15], c'query-data-ok!!!', 16) != 16 || C.lseek(sources[15], 5, C.SEEK_SET) != 5 { return 1 }
		independent[5] = C.open(c'/tmp/linux-fcntlquery-unlinked', C.O_RDWR); if independent[5] < 0 || C.lseek(independent[5], 9, C.SEEK_SET) != 9 || C.unlink(c'/tmp/linux-fcntlquery-unlinked') != 0 { return 1 }
		mut pipe := [2]i32{}; if C.pipe2(&pipe[0], C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.write(pipe[1], c'AB', 2) != 2 { return 1 }; sources[18] = pipe[0]; sources[21] = pipe[1]
		if C.pipe2(&independent[6], C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.write(independent[7], c'CD', 2) != 2 { return 1 }
		for class in 0 .. 8 { sources[class * 3 + 1] = C.dup(sources[class * 3]); sources[class * 3 + 2] = C.fcntl(sources[class * 3], C.F_DUPFD_CLOEXEC, 40); if sources[class * 3 + 1] < 0 || sources[class * 3 + 2] < 0 { return 1 } }
		if C.dup3(sources[0], 64, C.O_CLOEXEC) != 64 || C.dup3(independent[0], 65, 0) != 65 { return 1 }
		mut good := true
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(sources, independent, ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut data := [16]char{}; for fd in [sources[0], sources[15], independent[0], independent[5]]! { if C.pread(fd, &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'query-data-ok!!!', 16) != 0 { good = false } }
		if C.read(sources[18], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) || C.read(independent[6], &data[0], 2) != 2 || data[0] != char(`C`) || data[1] != char(`D`) { good = false }
		for i in 0 .. 24 { if C.fcntl(sources[i], C.F_GETFD) != if i % 3 == 1 { 0 } else { C.FD_CLOEXEC } { good = false }; C.close(sources[i]) }; for i in 0 .. 8 { C.close(independent[i]) }; C.close(64); C.close(65)
		if !good { C.puts(c'LINUX FCNTLQUERY FAIL: description identity, word, error or state controls'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX FCNTLQUERY REFERENCE: PASS') } else { C.puts(c'LINUX FCNTLQUERY: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
