// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlabifixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct C.rlimit { rlim_cur u64 rlim_max u64 }
struct C.flock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct Counts { mut: calls [5]u64 failures [5]u64 }
struct State { mut: metadata C.stat flags i32 status i32 cursor i64 }
struct Packet { mut: before u64 lock C.flock after u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Query { ret isize code i32 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
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
	unsafe {
		mut tally := &Counts(counts); tally.calls[kind]++
		if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX FCNTLABI DETAIL: ordinary=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), kind, tally.calls[kind], result.ret, result.code); C.fflush(nil) } }
	}
}
fn capture(fd i32, target &State) bool {
	unsafe { mut state := &State(target); state.flags = C.fcntl(fd, C.F_GETFD); state.status = C.fcntl(fd, C.F_GETFL); state.cursor = C.lseek(fd, 0, C.SEEK_CUR); return C.fstat(fd, &state.metadata) == 0 && state.flags >= 0 && state.status >= 0 }
}
fn equal(left &C.stat, right &C.stat) bool {
	return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode
		&& left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size
}
fn stable(fd i32, before &State, flags i32, status i32, cursor i64) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && equal(&before.metadata, after) && C.fcntl(fd, C.F_GETFD) == flags && C.fcntl(fd, C.F_GETFL) == status && C.lseek(fd, 0, C.SEEK_CUR) == cursor }
}
fn getters(counts &Counts, source i32, ordinary bool, fp u64, cp u64, ap u64) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }
		for cmd in [i32(C.F_GETFD), i32(C.F_GETFL)]! {
			result := query(u64(source) | fp, u64(cmd) | cp, ap | 0x1234)
			wanted := if cmd == C.F_GETFD { before.flags } else { before.status }
			record(counts, 0, result.ret == wanted && stable(source, before, before.flags, before.status, before.cursor), ordinary, result)
		}
	}
}
fn duplicate(counts &Counts, source i32, ordinary bool, fp u64, cp u64, ap u64, cmd i32, minimum u32, expected i32) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); seed := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) || !capture(64, seed) { C._exit(1) }
		result := query(u64(source) | fp, u64(cmd) | cp, u64(minimum) | ap)
		mut good := if expected == 0 { result.ret >= isize(minimum) && result.ret < 128 } else { result.ret == -1 && result.code == expected }
		if result.ret >= 0 {
			alias := i32(result.ret); wanted := if cmd == C.F_DUPFD_CLOEXEC { i32(C.FD_CLOEXEC) } else { i32(0) }
			good = good && stable(alias, before, wanted, before.status, before.cursor)
			if before.cursor >= 0 && before.metadata.st_mode & u32(C.S_IFMT) == u32(C.S_IFREG) {
				good = good && C.lseek(alias, before.cursor + 1, C.SEEK_SET) == before.cursor + 1 && C.lseek(source, 0, C.SEEK_CUR) == before.cursor + 1
				if C.lseek(source, before.cursor, C.SEEK_SET) != before.cursor { good = false }
			}
			if C.close(alias) != 0 { good = false }
		}
		good = good && stable(source, before, before.flags, before.status, before.cursor) && stable(64, seed, seed.flags, seed.status, seed.cursor)
		record(counts, 1, good, ordinary, result)
	}
}
fn set_descriptor(counts &Counts, source i32, ordinary bool, fp u64, cp u64, ap u64, value u32) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }
		wanted := i32(value & u32(C.FD_CLOEXEC)); if C.fcntl(source, C.F_SETFD, i32(1 - wanted)) != 0 { C._exit(1) }
		result := query(u64(source) | fp, u64(C.F_SETFD) | cp, u64(value) | ap)
		good := result.ret == 0 && stable(source, before, wanted, before.status, before.cursor)
		if C.fcntl(source, C.F_SETFD, before.flags) != 0 { C._exit(1) }; record(counts, 2, good, ordinary, result)
	}
}
fn set_status(counts &Counts, source i32, ordinary bool, fp u64, cp u64, ap u64, value u32) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }
		mask := i32(C.O_APPEND | C.O_NONBLOCK); wanted := (before.status & ~mask) | (i32(value) & mask)
		result := query(u64(source) | fp, u64(C.F_SETFL) | cp, u64(value) | ap)
		good := result.ret == 0 && stable(source, before, before.flags, wanted, before.cursor)
		if C.fcntl(source, C.F_SETFL, before.status) != 0 { C._exit(1) }; record(counts, 2, good, ordinary, result)
	}
}
fn set_signal(counts &Counts, source i32, ordinary bool, fp u64, cp u64, ap u64, value u32) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }; saved := C.fcntl(source, C.F_GETSIG)
		if saved < 0 || C.fcntl(source, C.F_SETSIG, i32(10)) != 0 { C._exit(1) }
		result := query(u64(source) | fp, u64(C.F_SETSIG) | cp, u64(value) | ap)
		good := (if value <= 64 { result.ret == 0 && C.fcntl(source, C.F_GETSIG) == i32(value) } else { result.ret == -1 && result.code == C.EINVAL && C.fcntl(source, C.F_GETSIG) == 10 }) && stable(source, before, before.flags, before.status, before.cursor)
		if C.fcntl(source, C.F_SETSIG, saved) != 0 { C._exit(1) }; record(counts, 2, good, ordinary, result)
	}
}
fn pipe_size(counts &Counts, source i32, ordinary bool, fp u64, cp u64, ap u64) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }; capacity := C.fcntl(source, C.F_GETPIPE_SZ); if capacity <= 0 { C._exit(1) }
		result := query(u64(source) | fp, u64(C.F_SETPIPE_SZ) | cp, u64(capacity) | ap)
		record(counts, 2, result.ret == capacity && C.fcntl(source, C.F_GETPIPE_SZ) == capacity && stable(source, before, before.flags, before.status, before.cursor), ordinary, result)
	}
}
fn pointer(counts &Counts, source i32, ordinary bool, fp u64, cp u64, invalid bool) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }
		mut packet := &Packet(C.alloca(usize(sizeof(Packet)))); *packet = Packet{before: 0x1234567812345678, after: 0x8765432187654321, lock: C.flock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_start: 0, l_len: 1, l_pid: -1}}
		address := u64(&packet.lock); if address <= 0xffffffff { C._exit(1) }
		result := query(u64(source) | fp, u64(C.F_GETLK) | cp, if invalid { u64(0) } else { address })
		good := (if invalid { result.ret == -1 && result.code == C.EFAULT && packet.lock.l_type == C.F_WRLCK } else { result.ret == 0 && packet.lock.l_type == C.F_UNLCK })
			&& packet.before == 0x1234567812345678 && packet.after == 0x8765432187654321 && stable(source, before, before.flags, before.status, before.cursor)
		record(counts, 3, good, ordinary, result)
	}
}
fn error_query(counts &Counts, source i32, ordinary bool, fd u32, cmd u32, fp u64, cp u64, expected i32) {
	unsafe {
		before := &State(C.alloca(usize(sizeof(State)))); if !capture(source, before) { C._exit(1) }
		result := query(u64(fd) | fp, u64(cmd) | cp, 128)
		record(counts, 4, result.ret == -1 && result.code == expected && stable(source, before, before.flags, before.status, before.cursor), ordinary, result)
	}
}
fn pressure(counts &Counts, source i32, ordinary bool, limits &C.rlimit) {
	unsafe {
		mut held := [64]i32{}; mut bound := &C.rlimit(limits); bound.rlim_cur = 64; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
		for fd in 0 .. 64 { if C.fcntl(i32(fd), C.F_GETFD) < 0 { if C.dup3(64, i32(fd), 0) != fd { C._exit(1) }; held[fd] = 1 } }
		for prefix in [u64(0), u64(0x100000000), u64(0xffffffff00000000)]! {
			for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! {
				for minimum in [u64(0), u64(63), u64(64)]! { result := query(u64(source) | prefix, u64(cmd), minimum); record(counts, 4, result.ret == -1 && result.code == if minimum < 64 { C.EMFILE } else { C.EINVAL }, ordinary, result); if result.ret >= 0 { C.close(i32(result.ret)) } }
			}
			slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_dup, u64(source) | prefix); record(counts, 4, ret == -1 && *slot == C.EMFILE, ordinary, Query{ret, *slot}); if ret >= 0 { C.close(i32(ret)) }
		}
		bound.rlim_cur = 0; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
		for prefix in [u64(0), u64(0x100000000), u64(0xffffffff00000000)]! {
			for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! { result := query(u64(source) | prefix, u64(cmd), 0); record(counts, 4, result.ret == -1 && result.code == C.EINVAL, ordinary, result); if result.ret >= 0 { C.close(i32(result.ret)) } }
			slot := C.__errno_location(); *slot = 0; ret := C.syscall(C.SYS_dup, u64(source) | prefix); record(counts, 4, ret == -1 && *slot == C.EMFILE, ordinary, Query{ret, *slot}); if ret >= 0 { C.close(i32(ret)) }
		}
		bound.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, bound) != 0 { C._exit(1) }
		for fd in 0 .. 64 { if held[fd] != 0 && C.close(i32(fd)) != 0 { C._exit(1) } }
	}
}
fn matrix(counts &Counts, sources &i32, ordinary bool, limits &C.rlimit) {
	unsafe {
		for fp in [u64(0), u64(0x100000000), u64(0xffffffff00000000)]! {
			for cp in [u64(0), u64(0x200000000), u64(0x8000000000000000)]! {
				for index in 0 .. 6 {
					source := sources[index]
					for ap in [u64(0), u64(0x400000000), u64(0xabcdef0100000000)]! {
						getters(counts, source, ordinary, fp, cp, ap)
						for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! {
							for minimum in [u32(0), u32(63), u32(127)]! { duplicate(counts, source, ordinary, fp, cp, ap, cmd, minimum, 0) }
							for minimum in [u32(128), u32(129), u32(0x7fffffff), u32(0x80000000), u32(0xffffffff)]! { duplicate(counts, source, ordinary, fp, cp, ap, cmd, minimum, i32(C.EINVAL)) }
						}
						for value in [u32(0), u32(1), u32(2), u32(0xffffffff)]! { set_descriptor(counts, source, ordinary, fp, cp, ap, value) }
						if index == 0 || index >= 3 {
							for value in [u32(0), u32(C.O_NONBLOCK), u32(C.O_NONBLOCK | C.O_APPEND)]! { set_status(counts, source, ordinary, fp, cp, ap, value) }
						}
						if index == 0 || index == 3 { for value in [u32(0), u32(1), u32(64), u32(65), u32(0x80000000), u32(0xffffffff)]! { set_signal(counts, source, ordinary, fp, cp, ap, value) } }
						if index >= 4 { pipe_size(counts, source, ordinary, fp, cp, ap) }
					}
					if index == 0 || index == 3 { pointer(counts, source, ordinary, fp, cp, false); pointer(counts, source, ordinary, fp, cp, true) }
				}
				for fd in [u32(127), u32(128), u32(0x80000000), u32(0xffffffff)]! { for cmd in [u32(C.F_GETFD), u32(C.F_DUPFD), u32(C.F_DUPFD_CLOEXEC)]! { error_query(counts, sources[0], ordinary, fd, cmd, fp, cp, i32(C.EBADF)) } }
				for cmd in [u32(0x7fffffff), u32(0xffffffff)]! { error_query(counts, sources[0], ordinary, u32(sources[0]), cmd, fp, cp, i32(C.EINVAL)) }
			}
		}
		// Ordinary libc minimum controls must agree with the raw native ABI.
		for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! { for minimum in [i32(-1), i32(128), i32(129)]! { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(sources[0], cmd, minimum); record(counts, 4, ret == -1 && *slot == C.EINVAL, ordinary, Query{ret, *slot}); if ret >= 0 { C.close(ret) } } }
		pressure(counts, sources[0], ordinary, limits)
	}
}
fn storage_cycle(source i32) bool {
	unsafe {
		for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! {
			result := query(u64(source) | 0x100000000, u64(cmd) | 0x200000000, u64(63) | 0x400000000)
			if result.ret != 63 { if result.ret >= 0 { C.close(i32(result.ret)) }; return false }
			good := C.fcntl(63, C.F_GETFD) == if cmd == C.F_DUPFD { 0 } else { C.FD_CLOEXEC }; if C.close(63) != 0 || !good { return false }
			for minimum in [u64(128), u64(0xffffffff)]! { rejected := query(u64(source), u64(cmd), minimum); if rejected.ret != -1 || rejected.code != C.EINVAL { if rejected.ret >= 0 { C.close(i32(rejected.ret)) }; return false } }
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
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FCNTLABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FCNTLABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(sources &i32, ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		mut limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }
		counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; matrix(counts, sources, ordinary, limits)
		mut good := true
		for kind in 0 .. 5 { C.printf(c'LINUX FCNTLABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(sources[0], ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut sources := &i32(C.alloca(usize(6 * sizeof(i32)))); for i in 0 .. 6 { sources[i] = -1 }
		sources[0] = C.open(c'/tmp/linux-fcntl-file', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644))
		if sources[0] < 0 || C.write(sources[0], c'fcntl-data-ok!!!', 16) != 16 || C.lseek(sources[0], 3, C.SEEK_SET) != 3 || C.mkdir(c'/tmp/linux-fcntl-dir', u32(0o755)) != 0 { return 1 }
		sources[1] = C.open(c'/tmp/linux-fcntl-file', C.O_PATH | C.O_CLOEXEC); sources[2] = C.open(c'/tmp/linux-fcntl-dir', C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC)
		sources[3] = C.open(c'/tmp/linux-fcntl-unlinked', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); if sources[1] < 0 || sources[2] < 0 || sources[3] < 0 { return 1 }
		if C.write(sources[3], c'fcntl-data-ok!!!', 16) != 16 || C.lseek(sources[3], 5, C.SEEK_SET) != 5 || C.unlink(c'/tmp/linux-fcntl-unlinked') != 0 || C.pipe2(&sources[4], C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.write(sources[5], c'AB', 2) != 2 { return 1 }
		seed := C.open(c'/tmp/linux-fcntl-seed', C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o644)); if seed < 0 || C.write(seed, c'fcntl-seed-ok!!!', 16) != 16 || C.lseek(seed, 7, C.SEEK_SET) != 7 || C.dup3(seed, 64, C.O_CLOEXEC) != 64 { return 1 }
		mut good := true
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(sources, ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut data := [16]char{}; for index in [0, 3]! { if C.pread(sources[index], &data[0], 16, 0) != 16 || C.lseek(sources[index], 0, C.SEEK_CUR) != if index == 0 { 3 } else { 5 } { good = false }; for i in 0 .. 16 { if data[i] != c'fcntl-data-ok!!!'[i] { good = false } }; if C.fcntl(sources[index], C.F_GETSIG) != 0 { good = false } }
		if C.pread(seed, &data[0], 16, 0) != 16 || C.lseek(seed, 0, C.SEEK_CUR) != 7 || C.fcntl(seed, C.F_GETFD) != 0 || C.fcntl(64, C.F_GETFD) != C.FD_CLOEXEC { good = false }; for i in 0 .. 16 { if data[i] != c'fcntl-seed-ok!!!'[i] { good = false } }
		if C.read(sources[4], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) { good = false }
		for i in 0 .. 6 { if C.fcntl(sources[i], C.F_GETFD) != C.FD_CLOEXEC { good = false }; C.close(sources[i]) }; C.close(64); C.close(seed)
		if !good { C.puts(c'LINUX FCNTLABI FAIL: native words, limits, pointer or state controls'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX FCNTLABI REFERENCE: PASS') } else { C.puts(c'LINUX FCNTLABI: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
