// SPDX-License-Identifier: GPL-2.0-or-later
module lockrangefixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.flock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct Tally { mut: calls [5]u64 failures [5]u64 }
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
fn C.dup3(i32, i32, i32) i32
fn C.lseek(i32, i64, i32) i64
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.unlink(&char) i32
fn C.chown(&char, u32, u32) i32
fn C.pipe(&i32) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.getpid() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.signal(i32, fn (i32)) voidptr
fn C.siginterrupt(i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn call(fd i32, cmd i32, flk &C.flock, raw bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0
		mut ret := isize(0)
		if raw { ret = C.syscall(C.SYS_fcntl, u64(u32(fd)) | u64(0xffffffff00000000), u64(u32(cmd)) | u64(0x8000000000000000), flk) }
		else { ret = isize(C.fcntl(fd, cmd, flk)) }
		return Query{ret, *slot}
	}
}
fn check(tally &Tally, kind i32, good bool, tag &char) {
	unsafe { mut counts := &Tally(tally); counts.calls[kind]++; if !good { counts.failures[kind]++; if counts.failures[kind] <= 8 { C.printf(c'LINUX LOCKRANGE DETAIL: kind=%d call=%lu tag=%s\n', kind, counts.calls[kind], tag); C.fflush(nil) } } }
}
fn change(fd i32, cmd i32, typ i32, start i64, length i64, raw bool) Query {
	unsafe { mut flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{ l_type: i16(typ), l_whence: i16(C.SEEK_SET), l_start: start, l_len: length }; return call(fd, cmd, flk, raw) }
}
fn expect(tally &Tally, kind i32, fd i32, cmd i32, typ i32, start i64, length i64, code i32, raw bool, tag &char) {
	result := change(fd, cmd, typ, start, length, raw); check(tally, kind, result.ret == if code == 0 { 0 } else { -1 } && result.code == code, tag)
}
fn inspect(tally &Tally, kind i32, fd i32, cmd i32, typ i32, start i64, length i64, held i32, held_start i64, held_length i64, pid i32, raw bool, tag &char) {
	unsafe { mut flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{ l_type: i16(typ), l_whence: i16(C.SEEK_SET), l_start: start, l_len: length, l_pid: if cmd == C.F_GETLK { 12345 } else { 0 } }
		result := call(fd, cmd, flk, raw)
		good := result.ret == 0 && result.code == 0 && flk.l_type == held && flk.l_whence == C.SEEK_SET && flk.l_start == held_start && flk.l_len == held_length && flk.l_pid == pid
		check(tally, kind, good, tag)
	}
}
const maximum = i64(0x7fffffffffffffff)
const minimum = i64(-0x7fffffffffffffff - 1)
struct Case { whence i32 start i64 length i64 cursor i64 normalized_start i64 normalized_length i64 code i32 }
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.fstat(i32, &C.stat) i32
fn C.getuid() u32
struct C.stat { st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_size i64 }

fn observe(fd i32, cmd i32, start i64, length i64, held i32, held_start i64, held_length i64, pid i32, raw bool) bool {
	unsafe {
		flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{l_type: i16(C.F_WRLCK), l_start: start, l_len: length}
		result := call(fd, cmd, flk, raw)
		return result.ret == 0 && result.code == 0 && flk.l_type == held && flk.l_whence == C.SEEK_SET && flk.l_start == held_start && flk.l_len == held_length && flk.l_pid == pid
	}
}
fn stable(a i32, alias i32, b i32, cursor i64, flags i32, status i32) bool {
	unsafe {
		metadata := &C.stat(C.alloca(usize(sizeof(C.stat)))); mut data := [16]char{}
		return C.fstat(a, metadata) == 0 && metadata.st_size == 16 && metadata.st_uid == C.getuid() && metadata.st_gid == C.getuid() && metadata.st_mode == u32(C.S_IFREG | 0o600)
			&& C.fcntl(a, C.F_GETFD) == flags && C.fcntl(a, C.F_GETFL) == status && C.fcntl(alias, C.F_GETFD) == 0 && C.fcntl(alias, C.F_GETFL) == status && C.lseek(a, 0, C.SEEK_CUR) == cursor && C.lseek(alias, 0, C.SEEK_CUR) == cursor && C.lseek(b, 0, C.SEEK_CUR) == 3
			&& C.pread(a, &data[0], 16, 0) == 16 && C.memcmp(&data[0], c'lock-range-data!\n', 16) == 0
	}
}
fn run_case(tally &Tally, path &char, cmd i32, raw bool, spec Case) {
	unsafe {
		a := C.open(path, C.O_RDWR | C.O_CLOEXEC); alias := C.dup(a); b := C.open(path, C.O_RDWR)
		if a < 0 || alias < 0 || b < 0 || C.lseek(a, spec.cursor, C.SEEK_SET) != spec.cursor || C.lseek(b, 3, C.SEEK_SET) != 3 { C._exit(1) }
		flags := C.fcntl(a, C.F_GETFD); status := C.fcntl(a, C.F_GETFL)
		getter := cmd == C.F_GETLK || cmd == C.F_OFD_GETLK
		ofd := cmd == C.F_OFD_GETLK || cmd == C.F_OFD_SETLK || cmd == C.F_OFD_SETLKW
		seed_ofd := if getter { !ofd } else { ofd }
		seed_cmd := if seed_ofd { i32(C.F_OFD_SETLK) } else { i32(C.F_SETLK) }
		observer_cmd := if seed_ofd { i32(C.F_GETLK) } else { i32(C.F_OFD_GETLK) }
		seed_start := if getter && spec.code == 0 { spec.normalized_start } else { i64(10) }
		seed_length := if getter && spec.code == 0 { spec.normalized_length } else { i64(4) }
		owner_pid := if seed_ofd { i32(-1) } else { C.getpid() }
		if change(a, seed_cmd, C.F_WRLCK, seed_start, seed_length, false).ret != 0 { C._exit(1) }
		flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); before := &C.flock(C.alloca(usize(sizeof(C.flock))))
		*flk = C.flock{l_type: i16(C.F_WRLCK), l_whence: i16(spec.whence), l_start: spec.start, l_len: spec.length}; C.memcpy(before, flk, usize(sizeof(C.flock)))
		result := call(if raw { alias } else { a }, cmd, flk, raw)
		mut good := result.ret == if spec.code == 0 { 0 } else { -1 } && result.code == spec.code
		if spec.code != 0 || !getter { if C.memcmp(before, flk, usize(sizeof(C.flock))) != 0 { good = false } }
		else if flk.l_type != C.F_WRLCK || flk.l_whence != C.SEEK_SET || flk.l_start != seed_start || flk.l_len != seed_length || flk.l_pid != owner_pid { good = false }
		kind := if spec.code != 0 { i32(2) } else if getter { i32(1) } else { i32(0) }
		if !good { C.printf(c'LINUX LOCKRANGE DETAIL RESULT: cmd=%d raw=%d whence=%d start=%ld length=%ld ret=%ld errno=%d wanted=%d\n', cmd, i32(raw), spec.whence, spec.start, spec.length, result.ret, result.code, spec.code) }
		check(tally, kind, good, c'range call and complete header')
		post_start := if !getter && spec.code == 0 { spec.normalized_start } else { seed_start }
		post_length := if !getter && spec.code == 0 { spec.normalized_length } else { seed_length }
		check(tally, 3, observe(b, observer_cmd, post_start, if post_length == 0 { i64(0) } else { i64(1) }, C.F_WRLCK, post_start, post_length, owner_pid, raw), c'accepted lock or preserved seed')
		check(tally, 4, stable(a, alias, b, spec.cursor, flags, status), c'bytes metadata flags and shared cursors')
		C.close(alias); C.close(a); C.close(b)
	}
}
fn matrix(tally &Tally, path &char) {
	unsafe {
		valid := [Case{0, maximum, 1, 3, maximum, 0, 0}, Case{0, maximum - 1, 2, 3, maximum - 1, 0, 0}, Case{0, maximum - 8, 9, 3, maximum - 8, 0, 0}, Case{0, 1, maximum, 3, 1, 0, 0}, Case{0, 0, maximum, 3, 0, maximum, 0}, Case{0, maximum, 0, 3, maximum, 0, 0}, Case{0, maximum - 2, 0, 3, maximum - 2, 0, 0}, Case{0, maximum, -1, 3, maximum - 1, 1, 0}, Case{0, maximum, -maximum, 3, 0, maximum, 0}, Case{0, maximum - 1, 1, 3, maximum - 1, 1, 0}, Case{1, maximum - 3, 1, 3, maximum, 0, 0}, Case{2, maximum - 16, 1, 3, maximum, 0, 0}, Case{1, -3, 3, maximum, maximum - 3, 3, 0}, Case{2, -16, maximum, 3, 0, maximum, 0}, Case{1, -3, 1, 3, 0, 1, 0}, Case{2, -15, 0, 3, 1, 0, 0}]!
		invalid := [Case{0, maximum, 2, 3, 0, 0, C.EOVERFLOW}, Case{0, 2, maximum, 3, 0, 0, C.EOVERFLOW}, Case{0, maximum - 1, 3, 3, 0, 0, C.EOVERFLOW}, Case{1, maximum - 2, 1, 3, 0, 0, C.EOVERFLOW}, Case{2, maximum - 15, 1, 3, 0, 0, C.EOVERFLOW}, Case{0, -1, 0, 3, 0, 0, C.EINVAL}, Case{0, maximum, minimum, 3, 0, 0, C.EINVAL}, Case{0, 0, -1, 3, 0, 0, C.EINVAL}, Case{1, minimum, maximum, 3, 0, 0, C.EINVAL}, Case{99, maximum, 1, 3, 0, 0, C.EINVAL}]!
		for raw in [false, true]! { for cmd in [i32(C.F_GETLK), C.F_SETLK, C.F_SETLKW, C.F_OFD_GETLK, C.F_OFD_SETLK, C.F_OFD_SETLKW]! { for spec in valid { run_case(tally, path, cmd, raw, spec) }; for spec in invalid { run_case(tally, path, cmd, raw, spec) } } }
	}
}
fn precedence(tally &Tally, path &char) {
	unsafe {
		readwrite := C.open(path, C.O_RDWR); readonly := C.open(path, C.O_RDONLY); writeonly := C.open(path, C.O_WRONLY); if readwrite < 0 || readonly < 0 || writeonly < 0 { C._exit(1) }
		flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); before := &C.flock(C.alloca(usize(sizeof(C.flock))))
		for raw in [false, true]! { for cmd in [i32(C.F_GETLK), C.F_SETLK, C.F_SETLKW, C.F_OFD_GETLK, C.F_OFD_SETLK, C.F_OFD_SETLKW]! {
			getter := cmd == C.F_GETLK || cmd == C.F_OFD_GETLK
			for variant in 0 .. 7 {
				*flk = C.flock{l_type: i16(C.F_WRLCK), l_start: maximum, l_len: 2}
				mut fd := readwrite; mut code := i32(C.EOVERFLOW)
				match variant {
					0 { flk.l_type = 99; if cmd == C.F_GETLK { code = C.EINVAL } }
					1 { fd = readonly; flk.l_pid = 1 }
					2 { flk.l_pid = 1 }
					3 { flk.l_type = i16(C.F_UNLCK); if cmd == C.F_GETLK { code = C.EINVAL } }
					4 { fd = readonly; flk.l_start = maximum - 1; flk.l_len = 1; flk.l_pid = 1; code = if !getter { i32(C.EBADF) } else if cmd == C.F_OFD_GETLK { i32(C.EINVAL) } else { 0 } }
					5 { fd = writeonly; flk.l_type = i16(C.F_RDLCK); flk.l_start = maximum - 1; flk.l_len = 1; flk.l_pid = 1; code = if !getter { i32(C.EBADF) } else if cmd == C.F_OFD_GETLK { i32(C.EINVAL) } else { 0 } }
					else { flk.l_whence = 99; flk.l_pid = 1; code = C.EINVAL }
				}
				C.memcpy(before, flk, usize(sizeof(C.flock))); result := call(fd, cmd, flk, raw)
				mut good := result.ret == if code == 0 { 0 } else { -1 } && result.code == code
				if code == 0 { before.l_type = i16(C.F_UNLCK) }
				if C.memcmp(before, flk, usize(sizeof(C.flock))) != 0 { good = false }
				if !good { C.printf(c'LINUX LOCKRANGE DETAIL PRECEDENCE: cmd=%d raw=%d variant=%d ret=%ld errno=%d wanted=%d\n', cmd, i32(raw), i32(variant), result.ret, result.code, code) }
				check(tally, 2, good, c'range kind access PID precedence and untouched header')
			}
		} }
		C.close(readwrite); C.close(readonly); C.close(writeonly)
	}
}
fn edges(tally &Tally, path &char, raw bool) {
	unsafe {
		a := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR); alias := C.dup(a); if a < 0 || b < 0 || alias < 0 { C._exit(1) }
		expect(tally, 3, a, C.F_OFD_SETLK, C.F_WRLCK, maximum - 3, 4, 0, raw, c'last-byte range')
		expect(tally, 3, alias, C.F_OFD_SETLK, C.F_UNLCK, maximum - 2, 1, 0, raw, c'last-byte split')
		check(tally, 3, observe(b, C.F_GETLK, maximum - 3, 1, C.F_WRLCK, maximum - 3, 1, -1, raw), c'finite split prefix')
		check(tally, 3, observe(b, C.F_GETLK, maximum - 2, 1, C.F_UNLCK, maximum - 2, 1, 0, raw), c'split gap')
		check(tally, 3, observe(b, C.F_GETLK, maximum, 1, C.F_WRLCK, maximum - 1, 0, -1, raw), c'split suffix reaches maximum')
		expect(tally, 3, alias, C.F_OFD_SETLK, C.F_WRLCK, maximum - 2, 1, 0, raw, c'bridge maximum ranges')
		check(tally, 3, observe(b, C.F_GETLK, maximum, 1, C.F_WRLCK, maximum - 3, 0, -1, raw), c'coalesced maximum extent')
		expect(tally, 3, alias, C.F_OFD_SETLK, C.F_UNLCK, maximum, 1, 0, raw, c'unlock last byte')
		check(tally, 3, observe(b, C.F_GETLK, maximum - 1, 1, C.F_WRLCK, maximum - 3, 3, -1, raw), c'last-byte removal finite prefix')
		check(tally, 3, observe(b, C.F_GETLK, maximum, 1, C.F_UNLCK, maximum, 1, 0, raw), c'last byte clear')
		expect(tally, 3, alias, C.F_OFD_SETLK, C.F_RDLCK, maximum - 1, 2, 0, raw, c'convert maximum suffix')
		check(tally, 3, observe(b, C.F_GETLK, maximum, 1, C.F_RDLCK, maximum - 1, 0, -1, raw), c'converted maximum output')
		C.close(a); check(tally, 3, observe(b, C.F_GETLK, maximum, 1, C.F_RDLCK, maximum - 1, 0, -1, raw), c'alias retains maximum suffix')
		C.close(alias); check(tally, 3, observe(b, C.F_GETLK, maximum, 1, C.F_UNLCK, maximum, 1, 0, raw), c'final alias releases maximum suffix'); C.close(b)
	}
}
fn cycle(path &char) bool {
	unsafe {
		a := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR); alias := C.dup(a); if a < 0 || b < 0 || alias < 0 { if a >= 0 { C.close(a) }; if b >= 0 { C.close(b) }; if alias >= 0 { C.close(alias) }; return false }
		mut good := change(a, C.F_OFD_SETLK, C.F_WRLCK, maximum, 1, true).ret == 0
		if !observe(b, C.F_GETLK, maximum, 1, C.F_WRLCK, maximum, 0, -1, true) { good = false }
		if change(alias, C.F_OFD_SETLK, C.F_UNLCK, maximum, 1, true).ret != 0 { good = false }
		if change(a, C.F_SETLK, C.F_WRLCK, maximum - 1, 2, true).ret != 0 { good = false }
		if !observe(b, C.F_OFD_GETLK, maximum, 1, C.F_WRLCK, maximum - 1, 0, C.getpid(), true) { good = false }
		if C.close(a) != 0 { good = false }
		if !observe(b, C.F_OFD_GETLK, maximum, 1, C.F_UNLCK, maximum, 1, 0, true) { good = false }
		if change(alias, C.F_OFD_SETLK, C.F_WRLCK, maximum, 1, true).ret != 0 { good = false }
		if C.close(alias) != 0 { good = false }
		if !observe(b, C.F_GETLK, maximum, 1, C.F_UNLCK, maximum, 1, 0, true) { good = false }
		if C.close(b) != 0 { good = false }; return good
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
fn storage(path &char, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(path) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(path) { return false } }; C.usleep(13000000)
		if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX LOCKRANGE SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX LOCKRANGE STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180); if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		path := if ordinary { &char(c'/tmp/linux-lockrange-user') } else { &char(c'/tmp/linux-lockrange-root') }
		counts := &Tally(C.alloca(usize(sizeof(Tally)))); *counts = Tally{}; matrix(counts, path); precedence(counts, path); for raw in [false, true]! { edges(counts, path, raw) }
		mut good := true; for kind in 0 .. 5 { C.printf(c'LINUX LOCKRANGE CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(kind), counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(path, ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for path in [&char(c'/tmp/linux-lockrange-user'), &char(c'/tmp/linux-lockrange-root')]! { seed := C.open(path, C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600)); if seed < 0 || C.write(seed, c'lock-range-data!\n', 16) != 16 || C.close(seed) != 0 { return 1 } }
		if C.chown(c'/tmp/linux-lockrange-user', 1000, 1000) != 0 { return 1 }
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		if C.unlink(c'/tmp/linux-lockrange-user') != 0 || C.unlink(c'/tmp/linux-lockrange-root') != 0 { good = false }
		if !good { C.puts(c'LINUX LOCKRANGE FAIL: endpoints, queries, precedence, state or retention'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX LOCKRANGE REFERENCE: PASS') } else { C.puts(c'LINUX LOCKRANGE: PASS') }; C.fflush(nil); for { C.pause() }
	}; return 0
}
