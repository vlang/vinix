// SPDX-License-Identifier: GPL-2.0-or-later
module fcntlpathfixture

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
struct C.rlimit { rlim_cur u64 rlim_max u64 }
struct C.flock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct Packet { mut: before u64 lock C.flock after u64 }
struct Counts { mut: calls [3]u64 failures [3]u64 }
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
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.unlink(&char) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
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
	unsafe {
		mut tally := &Counts(counts); tally.calls[kind]++
		if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX FCNTLPATH DETAIL: ordinary=%d kind=%d call=%lu ret=%ld errno=%d\n', i32(ordinary), kind, tally.calls[kind], result.ret, result.code); C.fflush(nil) } }
	}
}
fn equal(left &C.stat, right &C.stat) bool {
	return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode
		&& left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size
}
fn stable(fd i32, before &C.stat, flags i32, status i32) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && equal(before, after) && C.fcntl(fd, C.F_GETFD) == flags && C.fcntl(fd, C.F_GETFL) == status }
}
fn refused(counts &Counts, source i32, ordinary bool, fd u32, cmd u32, prefix i32, arg_kind i32, kind i32) {
	unsafe {
		before := &C.stat(C.alloca(usize(sizeof(C.stat)))); if C.fstat(source, before) != 0 { C._exit(1) }
		flags := C.fcntl(source, C.F_GETFD); status := C.fcntl(source, C.F_GETFL)
		mut packet := &Packet(C.alloca(usize(sizeof(Packet)))); saved := &Packet(C.alloca(usize(sizeof(Packet))))
		C.memset(packet, 0xa5, usize(sizeof(Packet))); packet.lock.l_type = i16(C.F_RDLCK); packet.lock.l_whence = i16(C.SEEK_SET); packet.lock.l_start = 0; packet.lock.l_len = 1; packet.lock.l_pid = 0
		C.memcpy(saved, packet, usize(sizeof(Packet)))
		arg := match arg_kind { 0 { u64(0) } 1 { u64(&packet.lock) } else { u64(1) } }
		result := query(u64(fd) | if prefix == 1 { u64(0xffffffff00000000) } else { 0 }, u64(cmd) | if prefix == 2 { u64(0x8000000000000000) } else { 0 }, arg)
		good := result.ret == -1 && result.code == C.EBADF && C.memcmp(packet, saved, usize(sizeof(Packet))) == 0 && stable(source, before, flags, status)
		// A failing baseline may have changed status flags. Restore them so
		// later cases still exercise the original pathname-only description.
		if C.fcntl(source, C.F_GETFL) != status && C.fcntl(source, C.F_SETFL, status) != 0 { C._exit(1) }
		record(counts, kind, good, ordinary, result)
	}
}
fn allowed(counts &Counts, source i32, ordinary bool, prefix i32) {
	unsafe {
		before := &C.stat(C.alloca(usize(sizeof(C.stat)))); if C.fstat(source, before) != 0 { C._exit(1) }
		flags := C.fcntl(source, C.F_GETFD); status := C.fcntl(source, C.F_GETFL)
		fp := if prefix == 1 { u64(0xffffffff00000000) } else { u64(0) }; cp := if prefix == 2 { u64(0x8000000000000000) } else { u64(0) }
		for cmd in [i32(C.F_GETFD), i32(C.F_GETFL)]! { result := query(u64(source) | fp, u64(cmd) | cp, 1); record(counts, 1, result.ret == if cmd == C.F_GETFD { flags } else { status } && stable(source, before, flags, status), ordinary, result) }
		for value in [u32(0), u32(1), u32(2), u32(0xffffffff)]! {
			result := query(u64(source) | fp, u64(C.F_SETFD) | cp, u64(value) | 0xabcdef0100000000)
			good := result.ret == 0 && stable(source, before, i32(value & 1), status)
			if C.fcntl(source, C.F_SETFD, flags) != 0 { C._exit(1) }; record(counts, 1, good, ordinary, result)
		}
		for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! {
			for minimum in [u64(0), u64(63), u64(127)]! {
				result := query(u64(source) | fp, u64(cmd) | cp, minimum | 0x400000000)
				mut good := result.ret >= isize(minimum) && result.ret < 128
				if result.ret >= 0 { good = good && stable(i32(result.ret), before, if cmd == C.F_DUPFD { 0 } else { i32(C.FD_CLOEXEC) }, status); if C.close(i32(result.ret)) != 0 { good = false } }
				record(counts, 1, good && stable(source, before, flags, status), ordinary, result)
			}
		}
	}
}
fn matrix(counts &Counts, sources &i32, normal i32, ordinary bool) {
	unsafe {
		// Numeric Linux command values keep the fixture independent of the
		// particular musl header's optional command-name extensions.
		for cmd in [u32(4), 5, 6, 7, 8, 9, 10, 11, 15, 16, 36, 37, 38, 1024, 1025, 1026, 1031, 1032, 1033, 1034, 1035, 1036, 0x7fffffff, 0xffffffff]! {
			for index in 0 .. 18 { for prefix in 0 .. 3 { for arg in 0 .. 3 { refused(counts, sources[index], ordinary, u32(sources[index]), cmd, i32(prefix), i32(arg), 0) } } }
			for fd in [u32(127), u32(0xffffffff)]! { for prefix in 0 .. 3 { for arg in 0 .. 3 { refused(counts, sources[0], ordinary, fd, cmd, i32(prefix), i32(arg), 2) } } }
			for index in 0 .. 18 { slot := C.__errno_location(); *slot = 0; ret := C.fcntl(sources[index], i32(cmd), 0); record(counts, 2, ret == -1 && *slot == C.EBADF, ordinary, Query{ret, *slot}) }
		}
		for index in 0 .. 18 { for prefix in 0 .. 3 { allowed(counts, sources[index], ordinary, i32(prefix)) } }
		// Ordinary file controls retain real status changes and argument errors.
		status := C.fcntl(normal, C.F_GETFL); result := query(u64(normal), u64(C.F_SETFL), u64(status | C.O_NONBLOCK))
		record(counts, 2, result.ret == 0 && C.fcntl(normal, C.F_GETFL) == status | C.O_NONBLOCK, ordinary, result)
		if C.fcntl(normal, C.F_SETFL, status) != 0 { C._exit(1) }
		for cmd in [u64(C.F_GETLK), u64(C.F_GETOWN_EX)]! { rejected := query(u64(normal), cmd, 0); record(counts, 2, rejected.ret == -1 && rejected.code == C.EFAULT, ordinary, rejected) }
		rejected := query(u64(normal), 0x7fffffff, 0); record(counts, 2, rejected.ret == -1 && rejected.code == C.EINVAL, ordinary, rejected)
		mut data := [16]char{}; record(counts, 2, C.pread(normal, &data[0], 16, 0) == 16 && C.memcmp(&data[0], c'pathname-data-ok', 16) == 0, ordinary, Query{})
		slot := C.__errno_location(); *slot = 0; fd := C.open(c'/tmp/linux-fcntlpath-private', C.O_RDONLY); code := *slot
		record(counts, 2, if ordinary { fd == -1 && code == C.EACCES } else { fd >= 0 }, ordinary, Query{isize(fd), code}); if fd >= 0 { C.close(fd) }
	}
}
fn storage_cycle(source i32) bool {
	unsafe {
		for cmd in [i32(C.F_DUPFD), i32(C.F_DUPFD_CLOEXEC)]! {
			result := query(u64(source) | 0x100000000, u64(cmd) | 0x200000000, 63)
			if result.ret != 63 { if result.ret >= 0 { C.close(i32(result.ret)) }; return false }
			good := C.fcntl(63, C.F_GETFD) == if cmd == C.F_DUPFD { 0 } else { C.FD_CLOEXEC }; if C.close(63) != 0 || !good { return false }
		}
		for cmd in [u64(C.F_SETFL), u64(C.F_GETOWN_EX), u64(C.F_GETLK), u64(C.F_ADD_SEALS)]! { rejected := query(u64(source), cmd, 0); if rejected.ret != -1 || rejected.code != C.EBADF { return false } }
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
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FCNTLPATH SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FCNTLPATH STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}

fn qualify(sources &i32, normal i32, ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		mut limits := &C.rlimit(C.alloca(usize(sizeof(C.rlimit)))); if C.getrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }; limits.rlim_cur = 128; if C.setrlimit(C.RLIMIT_NOFILE, limits) != 0 { return false }
		counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; matrix(counts, sources, normal, ordinary)
		mut good := true
		for kind in 0 .. 3 { C.printf(c'LINUX FCNTLPATH CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(sources[0], ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		normal := C.open(c'/tmp/linux-fcntlpath-file', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644))
		if normal < 0 || C.write(normal, c'pathname-data-ok', 16) != 16 { return 1 }
		private := C.open(c'/tmp/linux-fcntlpath-private', C.O_CREAT | C.O_EXCL | C.O_WRONLY, i32(0o600)); if private < 0 || C.write(private, c'P', 1) != 1 || C.close(private) != 0 { return 1 }
		if C.mkdir(c'/tmp/linux-fcntlpath-dir', u32(0o755)) != 0 || C.mkfifo(c'/tmp/linux-fcntlpath-fifo', u32(0o644)) != 0 || C.symlink(c'/tmp/linux-fcntlpath-file', c'/tmp/linux-fcntlpath-link') != 0 { return 1 }
		removed := C.open(c'/tmp/linux-fcntlpath-unlinked', C.O_CREAT | C.O_EXCL | C.O_WRONLY, i32(0o644)); if removed < 0 || C.write(removed, c'pathname-data-ok', 16) != 16 || C.close(removed) != 0 { return 1 }
		mut sources := &i32(C.alloca(usize(18 * sizeof(i32)))); for i in 0 .. 18 { sources[i] = -1 }
		for index in 0 .. 6 {
			path := match index { 0 { &char(c'/tmp/linux-fcntlpath-file') } 1 { &char(c'/tmp/linux-fcntlpath-private') } 2 { &char(c'/tmp/linux-fcntlpath-dir') } 3 { &char(c'/tmp/linux-fcntlpath-fifo') } 4 { &char(c'/tmp/linux-fcntlpath-link') } else { &char(c'/tmp/linux-fcntlpath-unlinked') } }
			fd := C.open(path, C.O_PATH | C.O_CLOEXEC | if index == 4 { C.O_NOFOLLOW } else { 0 }); if fd < 0 { return 1 }
			sources[index * 3] = fd; sources[index * 3 + 1] = C.dup(fd); sources[index * 3 + 2] = C.fcntl(fd, C.F_DUPFD_CLOEXEC, 32)
			if sources[index * 3 + 1] < 0 || sources[index * 3 + 2] < 0 { return 1 }
		}
		if C.unlink(c'/tmp/linux-fcntlpath-unlinked') != 0 { return 1 }
		mut good := true
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { good = false; break }; if child == 0 { C._exit(if qualify(sources, normal, ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut data := [16]char{}; if C.pread(normal, &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'pathname-data-ok', 16) != 0 { good = false }
		for i in 0 .. 18 { if C.fcntl(sources[i], C.F_GETFD) != if i % 3 == 1 { 0 } else { C.FD_CLOEXEC } || C.fcntl(sources[i], C.F_GETFL) & C.O_PATH == 0 { good = false }; C.close(sources[i]) }; C.close(normal)
		if !good { C.puts(c'LINUX FCNTLPATH FAIL: pathname commands, aliases, pointer or state controls'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX FCNTLPATH REFERENCE: PASS') } else { C.puts(c'LINUX FCNTLPATH: PASS') }; C.fflush(nil); for { C.pause() }
	}
	return 0
}
