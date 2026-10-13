// SPDX-License-Identifier: GPL-2.0-or-later
module lockaccessfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.flock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct C.stat { st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_size i64 }
struct Tally { mut: calls [3]u64 failures [3]u64 }
struct Query { ret isize code i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.flock(i32, i32) i32
fn C.dup(i32) i32
fn C.lseek(i32, i64, i32) i64
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.unlink(&char) i32
fn C.chown(&char, u32, u32) i32
fn C.fstat(i32, &C.stat) i32
fn C.getuid() u32
fn C.getpid() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn record(fd i32, cmd i32, flk &C.flock, raw bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0
		ret := if raw { C.syscall(C.SYS_fcntl, u64(u32(fd)) | u64(0xffffffff00000000), u64(u32(cmd)) | u64(0x8000000000000000), flk) } else { isize(C.fcntl(fd, cmd, flk)) }
		return Query{ret, *slot}
	}
}
fn whole(fd i32, operation i32, raw bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0
		ret := if raw { C.syscall(C.SYS_flock, u64(u32(fd)) | u64(0x8000000000000000), u64(u32(operation)) | u64(0xffffffff00000000)) } else { isize(C.flock(fd, operation)) }
		return Query{ret, *slot}
	}
}
fn result_ok(value Query, code i32) bool { return value.ret == if code == 0 { 0 } else { -1 } && value.code == code }
fn check(counts &Tally, kind i32, good bool, tag &char) {
	unsafe { mut tally := &Tally(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 8 { C.printf(c'LINUX LOCKACCESS DETAIL: kind=%d call=%lu tag=%s\n', kind, tally.calls[kind], tag); C.fflush(nil) } } }
}
fn change(fd i32, cmd i32, typ i32, start i64, length i64) bool {
	unsafe { flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{l_type: i16(typ), l_start: start, l_len: length}; return result_ok(record(fd, cmd, flk, false), 0) }
}
fn observe(fd i32, cmd i32, start i64, length i64, held i32, held_start i64, held_length i64, pid i32) bool {
	unsafe { flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{l_type: i16(C.F_WRLCK), l_start: start, l_len: length}
		return result_ok(record(fd, cmd, flk, true), 0) && flk.l_type == held && flk.l_whence == C.SEEK_SET && flk.l_start == held_start && flk.l_len == held_length && flk.l_pid == pid
	}
}
fn stable(a i32, alias i32, b i32, access i32, flags i32, status i32, inode u64) bool {
	unsafe { metadata := &C.stat(C.alloca(usize(sizeof(C.stat)))); mut data := [16]char{}
		return C.fstat(a, metadata) == 0 && metadata.st_ino == inode && metadata.st_size == 16 && metadata.st_uid == C.getuid() && metadata.st_gid == C.getuid() && metadata.st_mode == u32(C.S_IFREG | 0o600)
			&& C.fcntl(a, C.F_GETFD) == C.FD_CLOEXEC && C.fcntl(a, C.F_GETFL) == status && C.fcntl(alias, C.F_GETFD) == flags && C.fcntl(alias, C.F_GETFL) == status
			&& (access == C.O_PATH || (C.lseek(a, 7, C.SEEK_CUR) == 10 && C.lseek(alias, -7, C.SEEK_CUR) == 3))
			&& C.lseek(b, 0, C.SEEK_CUR) == 9 && C.pread(b, &data[0], 16, 0) == 16 && C.memcmp(&data[0], c'lock-access-data', 16) == 0
	}
}
fn alias_of(a i32, form i32) i32 {
	return if form == 0 { a } else if form == 1 { C.dup(a) } else { C.fcntl(a, C.F_DUPFD_CLOEXEC, 0) }
}
fn record_case(counts &Tally, path &char, access i32, form i32, cmd i32, typ i32, variant i32, raw bool) {
	unsafe {
		a := C.open(path, access | C.O_CLOEXEC | C.O_NONBLOCK); alias := alias_of(a, form); seed := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR)
		if a < 0 || alias < 0 || seed < 0 || b < 0 { C._exit(1) }
		metadata := &C.stat(C.alloca(usize(sizeof(C.stat)))); if C.fstat(a, metadata) != 0 || C.lseek(b, 9, C.SEEK_SET) != 9 || (access != C.O_PATH && C.lseek(a, 3, C.SEEK_SET) != 3) { C._exit(1) }
		inode := metadata.st_ino; flags := C.fcntl(alias, C.F_GETFD); status := C.fcntl(a, C.F_GETFL)
		getter := cmd == C.F_GETLK || cmd == C.F_OFD_GETLK; ofd := cmd == C.F_OFD_GETLK || cmd == C.F_OFD_SETLK || cmd == C.F_OFD_SETLKW
		seed_ofd := !getter || !ofd; seed_start := if getter { i64(3) } else { i64(12) }; seed_length := if getter { i64(5) } else { i64(2) }
		if !change(seed, if seed_ofd { i32(C.F_OFD_SETLK) } else { i32(C.F_SETLK) }, C.F_WRLCK, seed_start, seed_length) { C._exit(1) }
		flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); before := &C.flock(C.alloca(usize(sizeof(C.flock))))
		*flk = C.flock{l_type: i16(typ), l_start: 3, l_len: 5}
		mut code := i32(0)
		match variant { 1 { flk.l_pid = 1 } 2 { flk.l_whence = 99 } 3 { flk.l_start = i64(0x7fffffffffffffff); flk.l_len = 2 } 4 { flk.l_type = 99 } else {} }
		if access == C.O_PATH { code = C.EBADF }
		else if cmd == C.F_GETLK && typ == C.F_UNLCK { code = C.EINVAL }
		else if variant == 2 || variant == 4 { code = C.EINVAL }
		else if variant == 3 { code = C.EOVERFLOW }
		else if !getter && ((typ == C.F_RDLCK && access != C.O_RDONLY && access != C.O_RDWR) || (typ == C.F_WRLCK && access != C.O_WRONLY && access != C.O_RDWR)) { code = C.EBADF }
		else if ofd && variant == 1 { code = C.EINVAL }
		C.memcpy(before, flk, usize(sizeof(C.flock))); answer := record(alias, cmd, flk, raw)
		mut good := result_ok(answer, code)
		if getter && code == 0 && typ != C.F_UNLCK { before.l_type = i16(C.F_WRLCK); before.l_whence = i16(C.SEEK_SET); before.l_start = seed_start; before.l_len = seed_length; before.l_pid = if seed_ofd { -1 } else { C.getpid() } }
		if C.memcmp(before, flk, usize(sizeof(C.flock))) != 0 { good = false }
		if !good { C.printf(c'LINUX LOCKACCESS DETAIL RESULT: access=%d form=%d cmd=%d type=%d variant=%d raw=%d ret=%ld errno=%d wanted=%d\n', access, form, cmd, typ, variant, i32(raw), answer.ret, answer.code, code) }
		check(counts, 0, good, c'record access errno and complete header')
		mut preserved := observe(b, if seed_ofd { i32(C.F_GETLK) } else { i32(C.F_OFD_GETLK) }, seed_start, 1, C.F_WRLCK, seed_start, seed_length, if seed_ofd { i32(-1) } else { C.getpid() })
		if !getter { acquired := code == 0 && typ != C.F_UNLCK; if !observe(b, if ofd { i32(C.F_GETLK) } else { i32(C.F_OFD_GETLK) }, 3, 1, if acquired { typ } else { i32(C.F_UNLCK) }, 3, if acquired { i64(5) } else { i64(1) }, if !acquired { i32(0) } else if ofd { i32(-1) } else { C.getpid() }) { preserved = false } }
		check(counts, 2, preserved && stable(a, alias, b, access, flags, status, inode), c'record seed ranges bytes metadata flags cursors')
		if alias != a { C.close(alias) }; C.close(a); C.close(seed); C.close(b)
	}
}
fn flock_case(counts &Tally, path &char, access i32, form i32, operation i32, raw bool) {
	unsafe {
		a := C.open(path, access | C.O_CLOEXEC | C.O_NONBLOCK); alias := alias_of(a, form); seed := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR)
		if a < 0 || alias < 0 || seed < 0 || b < 0 { C._exit(1) }
		metadata := &C.stat(C.alloca(usize(sizeof(C.stat)))); if C.fstat(a, metadata) != 0 || C.lseek(b, 9, C.SEEK_SET) != 9 || (access != C.O_PATH && C.lseek(a, 3, C.SEEK_SET) != 3) { C._exit(1) }
		inode := metadata.st_ino; flags := C.fcntl(alias, C.F_GETFD); status := C.fcntl(a, C.F_GETFL)
		kind := operation & ~i32(C.LOCK_NB); valid := kind == C.LOCK_SH || kind == C.LOCK_EX || kind == C.LOCK_UN
		ordinary := access == C.O_RDONLY || access == C.O_WRONLY || access == C.O_RDWR
		seeded := ordinary || !valid || kind == C.LOCK_UN
		if seeded && !result_ok(whole(if ordinary { a } else { seed }, C.LOCK_EX | C.LOCK_NB, false), 0) { C._exit(1) }
		code := if !valid { i32(C.EINVAL) } else if access == C.O_PATH || (!ordinary && kind != C.LOCK_UN) { i32(C.EBADF) } else { i32(0) }
		answer := whole(alias, operation, raw); good := result_ok(answer, code)
		if !good { C.printf(c'LINUX LOCKACCESS DETAIL FLOCK: access=%d form=%d op=%d raw=%d ret=%ld errno=%d wanted=%d\n', access, form, operation, i32(raw), answer.ret, answer.code, code) }
		check(counts, 1, good, c'whole-file access and operation errors')
		retained := seeded && !(ordinary && valid && kind == C.LOCK_UN)
		reader_allowed := !retained || (ordinary && valid && kind == C.LOCK_SH)
		reader := whole(b, C.LOCK_SH | C.LOCK_NB, true); mut preserved := result_ok(reader, if reader_allowed { i32(0) } else { i32(C.EWOULDBLOCK) })
		if reader.ret == 0 { if !result_ok(whole(b, C.LOCK_UN, false), 0) { preserved = false } }
		writer := whole(b, C.LOCK_EX | C.LOCK_NB, true); if !result_ok(writer, if retained || (ordinary && valid && kind != C.LOCK_UN) { i32(C.EWOULDBLOCK) } else { i32(0) }) { preserved = false }
		if writer.ret == 0 { if !result_ok(whole(b, C.LOCK_UN, false), 0) { preserved = false } }
		check(counts, 2, preserved && stable(a, alias, b, access, flags, status, inode), c'whole-file locks bytes metadata flags cursors')
		if alias != a { C.close(alias) }; C.close(a); C.close(seed); C.close(b)
	}
}
fn matrix(counts &Tally, path &char) {
	unsafe { for raw in [false, true]! { for access in [i32(C.O_RDONLY), C.O_WRONLY, C.O_RDWR, 3, C.O_PATH]! { for form in 0 .. 3 {
		for cmd in [i32(C.F_GETLK), C.F_SETLK, C.F_SETLKW, C.F_OFD_GETLK, C.F_OFD_SETLK, C.F_OFD_SETLKW]! { for typ in [i32(C.F_RDLCK), C.F_WRLCK, C.F_UNLCK]! { for variant in 0 .. 5 { record_case(counts, path, access, form, cmd, typ, variant, raw) } } }
		for operation in [i32(C.LOCK_SH), C.LOCK_EX, C.LOCK_UN, C.LOCK_SH | C.LOCK_NB, C.LOCK_EX | C.LOCK_NB, C.LOCK_UN | C.LOCK_NB, C.LOCK_UN | C.LOCK_SH, C.LOCK_UN | C.LOCK_EX, C.LOCK_UN | C.LOCK_SH | C.LOCK_EX, C.LOCK_SH | C.LOCK_EX, 0, C.LOCK_NB, 16, C.LOCK_UN | 16, i32(u32(0x80000000)), i32(u32(0x80000008))]! { flock_case(counts, path, access, i32(form), operation, raw) }
	} } } }
}
fn cycle(path &char) bool {
	unsafe {
		rw := C.open(path, C.O_RDWR); mode3 := C.open(path, 3); pathfd := C.open(path, C.O_PATH); b := C.open(path, C.O_RDWR); alias := C.dup(rw)
		if rw < 0 || mode3 < 0 || pathfd < 0 || b < 0 || alias < 0 { for fd in [rw, mode3, pathfd, b, alias]! { if fd >= 0 { C.close(fd) } }; return false }
		mut good := change(rw, C.F_OFD_SETLK, C.F_WRLCK, 12, 2) && result_ok(whole(alias, C.LOCK_EX | C.LOCK_NB, true), 0)
		flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{l_type: i16(C.F_RDLCK), l_start: 3, l_len: 5}
		if !result_ok(record(mode3, C.F_SETLK, flk, true), C.EBADF) || !result_ok(record(mode3, C.F_OFD_SETLKW, flk, true), C.EBADF) { good = false }
		if !result_ok(whole(mode3, C.LOCK_SH | C.LOCK_NB, true), C.EBADF) || !result_ok(whole(pathfd, C.LOCK_UN, true), C.EBADF) || !result_ok(whole(alias, C.LOCK_UN | C.LOCK_EX, true), C.EINVAL) { good = false }
		if !observe(b, C.F_GETLK, 12, 1, C.F_WRLCK, 12, 2, -1) || !observe(b, C.F_OFD_GETLK, 3, 1, C.F_UNLCK, 3, 1, 0) || !result_ok(whole(b, C.LOCK_SH | C.LOCK_NB, true), C.EWOULDBLOCK) { good = false }
		if !change(alias, C.F_OFD_SETLK, C.F_UNLCK, 0, 0) || !result_ok(whole(alias, C.LOCK_UN, true), 0) { good = false }
		if !result_ok(whole(b, C.LOCK_EX | C.LOCK_NB, true), 0) || !result_ok(whole(b, C.LOCK_UN, true), 0) { good = false }
		for fd in [mode3, pathfd, rw, alias, b]! { if C.close(fd) != 0 { good = false } }; return good
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe { mut counts := &Slabs(destination); *counts = Slabs{}; mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0; mut position := 0; mut large := false
		for position < int(length) { mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 { if counts.rows >= 32 || size != duplicate { return false }; counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++ }
			else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}; return counts.rows > 0 && large
	}
}
fn storage(path &char, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(path) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(path) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX LOCKACCESS SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX LOCKACCESS STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180); if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		path := if ordinary { &char(c'/tmp/linux-lockaccess-user') } else { &char(c'/tmp/linux-lockaccess-root') }
		counts := &Tally(C.alloca(usize(sizeof(Tally)))); *counts = Tally{}; matrix(counts, path); mut good := true
		for kind in 0 .. 3 { C.printf(c'LINUX LOCKACCESS CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(kind), counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(path, ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for path in [&char(c'/tmp/linux-lockaccess-user'), &char(c'/tmp/linux-lockaccess-root')]! { seed := C.open(path, C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600)); if seed < 0 || C.write(seed, c'lock-access-data', 16) != 16 || C.close(seed) != 0 { return 1 } }
		if C.chown(c'/tmp/linux-lockaccess-user', 1000, 1000) != 0 { return 1 }
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		if C.unlink(c'/tmp/linux-lockaccess-user') != 0 || C.unlink(c'/tmp/linux-lockaccess-root') != 0 { good = false }
		if !good { C.puts(c'LINUX LOCKACCESS FAIL: access, operation, state or retention'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX LOCKACCESS REFERENCE: PASS') } else { C.puts(c'LINUX LOCKACCESS: PASS') }; C.fflush(nil); for { C.pause() }
	}; return 0
}
