// SPDX-License-Identifier: GPL-2.0-or-later
module flocksamefixture
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

struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct C.stat { st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_size i64 }
struct Tally { mut: calls [4]u64 failures [4]u64 }
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
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.unlink(&char) i32
fn C.rmdir(&char) i32
fn C.mkdir(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.fstat(i32, &C.stat) i32
fn C.getuid() u32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.kill(i32, i32) i32
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

fn whole(fd i32, operation i32, raw bool) Query {
	unsafe { slot := C.__errno_location(); *slot = 0; ret := if raw { C.syscall(C.SYS_flock, u64(u32(fd)) | u64(0x8000000000000000), u64(u32(operation)) | u64(0xffffffff00000000)) } else { isize(C.flock(fd, operation)) }; return Query{ret, *slot} }
}
fn ok(value Query, code i32) bool { return value.ret == if code == 0 { 0 } else { -1 } && value.code == code }
fn check(counts &Tally, kind i32, good bool, tag &char) {
	unsafe { mut tally := &Tally(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 8 { C.printf(c'LINUX FLOCKSAME DETAIL: kind=%d call=%lu tag=%s\n', kind, tally.calls[kind], tag); C.fflush(nil) } } }
}
fn flags(directory bool) i32 { return if directory { i32(C.O_RDONLY | C.O_DIRECTORY) } else { i32(C.O_RDWR) } }
fn selected(a i32, form i32) i32 { return if form == 0 { a } else if form == 1 { C.dup(a) } else { C.fcntl(a, C.F_DUPFD_CLOEXEC, 0) } }
fn sleeping(pid i32) bool {
	unsafe { mut path := [128]char{}; mut data := [4096]char{}; if C.snprintf(&path[0], 128, c'/proc/%d/status', pid) <= 0 { return false }
		for _ in 0 .. 100 { fd := C.open(&path[0], C.O_RDONLY); if fd < 0 { return false }; n := C.read(fd, &data[0], 4095); C.close(fd); if n > 0 { data[int(n)] = 0; if C.strstr(&data[0], c'State:\tS') != nil { return true } }; C.usleep(10000) }; return false
	}
}
fn stable(a i32, alias i32, b i32, directory bool, inode u64, descriptor i32, status i32) bool {
	unsafe { metadata := &C.stat(C.alloca(usize(sizeof(C.stat)))); mut data := [16]char{}
		return C.fstat(a, metadata) == 0 && metadata.st_ino == inode && metadata.st_uid == C.getuid() && metadata.st_gid == C.getuid() && metadata.st_mode == u32(if directory { C.S_IFDIR | 0o700 } else { C.S_IFREG | 0o600 })
			&& C.fcntl(a, C.F_GETFD) == C.FD_CLOEXEC && C.fcntl(alias, C.F_GETFD) == descriptor && C.fcntl(a, C.F_GETFL) == status && C.fcntl(alias, C.F_GETFL) == status
			&& (directory || (metadata.st_size == 16 && C.lseek(a, 7, C.SEEK_CUR) == 10 && C.lseek(alias, -7, C.SEEK_CUR) == 3 && C.lseek(b, 0, C.SEEK_CUR) == 9 && C.pread(b, &data[0], 16, 0) == 16 && C.memcmp(&data[0], c'flock-same-data!', 16) == 0))
	}
}
fn racing(counts &Tally, path &char, directory bool, form i32, held i32, raw bool) {
	unsafe {
		a := C.open(path, flags(directory) | C.O_CLOEXEC); alias := selected(a, form); b := C.open(path, flags(directory))
		if a < 0 || alias < 0 || b < 0 { C._exit(1) }
		metadata := &C.stat(C.alloca(usize(sizeof(C.stat)))); if C.fstat(a, metadata) != 0 || (!directory && (C.lseek(a, 3, C.SEEK_SET) != 3 || C.lseek(b, 9, C.SEEK_SET) != 9)) { C._exit(1) }
		inode := metadata.st_ino; descriptor := C.fcntl(alias, C.F_GETFD); status := C.fcntl(a, C.F_GETFL)
		seed := whole(a, held | C.LOCK_NB, false); check(counts, 2, ok(seed, 0), c'initial lock'); if seed.ret != 0 { C._exit(1) }
		ready := &i32(C.alloca(usize(2 * sizeof(i32)))); done := &i32(C.alloca(usize(2 * sizeof(i32)))); command := &i32(C.alloca(usize(2 * sizeof(i32))))
		if C.pipe(ready) != 0 || C.pipe(done) != 0 || C.pipe(command) != 0 { C._exit(1) }
		child := C.fork(); if child < 0 { C._exit(1) }
		if child == 0 {
			C.alarm(20); C.close(ready[0]); C.close(done[0]); C.close(command[1]); if alias != a { C.close(alias) }; C.close(a); C.close(b)
			other := C.open(path, flags(directory)); if other < 0 || C.write(ready[1], c'R', 1) != 1 { C._exit(1) }
			value := &Query(C.alloca(usize(sizeof(Query)))); *value = whole(other, C.LOCK_EX, raw); if C.write(done[1], value, usize(sizeof(Query))) != isize(sizeof(Query)) { C._exit(1) }
			mut byte := char(0); if C.read(command[0], &byte, 1) != 1 || byte != char(`X`) || !ok(whole(other, C.LOCK_UN, raw), 0) || C.close(other) != 0 { C._exit(1) }; C._exit(0)
		}
		C.close(ready[1]); C.close(done[1]); C.close(command[0]); mut byte := char(0)
		poll := &C.pollfd(C.alloca(usize(sizeof(C.pollfd)))); *poll = C.pollfd{fd: done[0], events: i16(C.POLLIN)}
		check(counts, 2, C.read(ready[0], &byte, 1) == 1 && byte == char(`R`) && sleeping(child) && C.poll(poll, 1, 0) == 0, c'queued independent contender')
		for _ in 0 .. 8 { answer := whole(alias, held | C.LOCK_NB, raw); check(counts, 0, ok(answer, 0), c'same kind retains ownership'); check(counts, 1, C.poll(poll, 1, 10) == 0, c'waiter remains blocked') }
		reader := whole(b, C.LOCK_SH | C.LOCK_NB, raw); check(counts, 2, ok(reader, if held == C.LOCK_SH { i32(0) } else { i32(C.EWOULDBLOCK) }), c'peer observes original kind'); if reader.ret == 0 { C.flock(b, C.LOCK_UN) }
		writer := whole(b, C.LOCK_EX | C.LOCK_NB, raw); check(counts, 2, ok(writer, C.EWOULDBLOCK), c'writer still conflicts'); if writer.ret == 0 { C.flock(b, C.LOCK_UN) }
		check(counts, 2, stable(a, alias, b, directory, inode, descriptor, status), c'bytes metadata flags shared cursor')
		check(counts, 2, ok(whole(alias, C.LOCK_UN, raw), 0), c'explicit unlock wakes waiter')
		value := &Query(C.alloca(usize(sizeof(Query)))); *value = Query{-2, -2}; finished := C.poll(poll, 1, 10000) == 1 && C.read(done[0], value, usize(sizeof(Query))) == isize(sizeof(Query))
		check(counts, 2, finished && ok(*value, 0), c'contender acquires after explicit unlock')
		check(counts, 2, C.write(command[1], c'X', 1) == 1, c'release contender'); if !finished { C.kill(child, C.SIGKILL) }
		mut exit_status := i32(-1); check(counts, 2, C.waitpid(child, &exit_status, 0) == child && exit_status == 0, c'contender exits cleanly')
		check(counts, 2, stable(a, alias, b, directory, inode, descriptor, status), c'completed file state')
		C.close(ready[0]); C.close(done[0]); C.close(command[1]); if alias != a { C.close(alias) }; C.close(a); C.close(b)
	}
}
fn controls(counts &Tally, path &char, directory bool, held i32, raw bool) {
	unsafe {
		a := C.open(path, flags(directory) | C.O_CLOEXEC); alias := C.dup(a); clo := C.fcntl(a, C.F_DUPFD_CLOEXEC, 0); b := C.open(path, flags(directory)); if a < 0 || alias < 0 || clo < 0 || b < 0 { C._exit(1) }
		check(counts, 3, ok(whole(a, held | C.LOCK_NB, raw), 0), c'control seed')
		for fd in [a, alias, clo]! { for nb in [i32(0), C.LOCK_NB]! { for _ in 0 .. 4 { check(counts, 3, ok(whole(fd, held | nb, raw), 0), c'blocking and NB alias repetition') } } }
		check(counts, 3, ok(whole(b, C.LOCK_SH | C.LOCK_NB, raw), if held == C.LOCK_SH { i32(0) } else { i32(C.EWOULDBLOCK) }), c'control initial reader'); check(counts, 3, ok(whole(b, C.LOCK_UN, raw), 0), c'clear peer reader')
		check(counts, 3, ok(whole(b, C.LOCK_EX | C.LOCK_NB, raw), C.EWOULDBLOCK), c'control initial writer'); check(counts, 3, ok(whole(b, C.LOCK_UN, raw), 0), c'clear peer writer')
		other := if held == C.LOCK_SH { i32(C.LOCK_EX) } else { i32(C.LOCK_SH) }; check(counts, 3, ok(whole(alias, other | C.LOCK_NB, raw), 0), c'actual conversion')
		check(counts, 3, ok(whole(b, C.LOCK_SH | C.LOCK_NB, raw), if other == C.LOCK_SH { i32(0) } else { i32(C.EWOULDBLOCK) }), c'converted reader'); check(counts, 3, ok(whole(b, C.LOCK_UN, raw), 0), c'clear converted peer')
		check(counts, 3, ok(whole(b, C.LOCK_EX | C.LOCK_NB, raw), C.EWOULDBLOCK), c'converted writer'); check(counts, 3, ok(whole(b, C.LOCK_UN, raw), 0), c'clear converted writer')
		check(counts, 3, ok(whole(clo, held | C.LOCK_NB, raw), 0), c'convert back')
		check(counts, 3, C.close(a) == 0, c'nonfinal principal close'); check(counts, 3, ok(whole(b, C.LOCK_EX | C.LOCK_NB, raw), C.EWOULDBLOCK), c'alias retains after close')
		check(counts, 3, C.close(alias) == 0, c'nonfinal alias close'); check(counts, 3, ok(whole(b, C.LOCK_EX | C.LOCK_NB, raw), C.EWOULDBLOCK), c'final alias retains')
		check(counts, 3, C.close(clo) == 0, c'final close'); check(counts, 3, ok(whole(b, C.LOCK_EX | C.LOCK_NB, raw), 0), c'final close releases'); check(counts, 3, ok(whole(b, C.LOCK_UN, raw), 0), c'observer unlock'); check(counts, 3, C.close(b) == 0, c'observer close')
	}
}
fn cycle(path &char, directory bool) bool {
	unsafe { a := C.open(path, flags(directory)); alias := C.dup(a); b := C.open(path, flags(directory)); if a < 0 || alias < 0 || b < 0 { for fd in [a, alias, b]! { if fd >= 0 { C.close(fd) } }; return false }
		mut good := ok(whole(a, C.LOCK_EX | C.LOCK_NB, true), 0)
		for _ in 0 .. 4 { if !ok(whole(alias, C.LOCK_EX | C.LOCK_NB, true), 0) { good = false } }
		if !ok(whole(b, C.LOCK_SH | C.LOCK_NB, true), C.EWOULDBLOCK) || !ok(whole(alias, C.LOCK_SH | C.LOCK_NB, true), 0) || !ok(whole(b, C.LOCK_SH | C.LOCK_NB, true), 0) { good = false }
		if !ok(whole(b, C.LOCK_UN, true), 0) || !ok(whole(alias, C.LOCK_UN, true), 0) || !ok(whole(b, C.LOCK_EX | C.LOCK_NB, true), 0) { good = false }
		for fd in [a, alias, b]! { if C.close(fd) != 0 { good = false } }; return good
	}
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
fn storage(file &char, directory &char, ordinary bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(file, false) || !cycle(directory, true) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(file, false) || !cycle(directory, true) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX FLOCKSAME SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX FLOCKSAME STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(ordinary bool, reference_run bool) bool {
	unsafe { C.alarm(180); if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		file := if ordinary { &char(c'/tmp/linux-flocksame-user') } else { &char(c'/tmp/linux-flocksame-root') }; directory := if ordinary { &char(c'/tmp/linux-flocksame-user-dir') } else { &char(c'/tmp/linux-flocksame-root-dir') }
		counts := &Tally(C.alloca(usize(sizeof(Tally)))); *counts = Tally{}
		for raw in [false, true]! { for dir in [false, true]! { path := if dir { directory } else { file }; for held in [i32(C.LOCK_SH), C.LOCK_EX]! { for form in 0 .. 3 { racing(counts, path, dir, i32(form), held, raw) }; controls(counts, path, dir, held, raw) } } }
		mut good := true; for kind in 0 .. 4 { C.printf(c'LINUX FLOCKSAME CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run && !storage(file, directory, ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for path in [&char(c'/tmp/linux-flocksame-user'), &char(c'/tmp/linux-flocksame-root')]! { seed := C.open(path, C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600)); if seed < 0 || C.write(seed, c'flock-same-data!', 16) != 16 || C.close(seed) != 0 { return 1 } }
		for path in [&char(c'/tmp/linux-flocksame-user-dir'), &char(c'/tmp/linux-flocksame-root-dir')]! { if C.mkdir(path, 0o700) != 0 { return 1 } }
		if C.chown(c'/tmp/linux-flocksame-user', 1000, 1000) != 0 || C.chown(c'/tmp/linux-flocksame-user-dir', 1000, 1000) != 0 { return 1 }
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		if C.unlink(c'/tmp/linux-flocksame-user') != 0 || C.unlink(c'/tmp/linux-flocksame-root') != 0 || C.rmdir(c'/tmp/linux-flocksame-user-dir') != 0 || C.rmdir(c'/tmp/linux-flocksame-root-dir') != 0 { good = false }
		if !good { C.puts(c'LINUX FLOCKSAME FAIL: ownership, waiter, conversion, state or retention'); C.fflush(nil); return 1 }; if reference_run { C.puts(c'LINUX FLOCKSAME REFERENCE: PASS') } else { C.puts(c'LINUX FLOCKSAME: PASS') }; C.fflush(nil); for { C.pause() }
	}; return 0
}
