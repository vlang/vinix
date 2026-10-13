// SPDX-License-Identifier: GPL-2.0-or-later
module ofdlocksfixture

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
	unsafe { mut counts := &Tally(tally); counts.calls[kind]++; if !good { counts.failures[kind]++; if counts.failures[kind] <= 8 { C.printf(c'LINUX OFDLOCKS DETAIL: kind=%d call=%lu tag=%s\n', kind, counts.calls[kind], tag); C.fflush(nil) } } }
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
fn identity(tally &Tally, path &char, raw bool) {
	unsafe {
		a := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR); alias := C.dup(a); extra := C.fcntl(a, C.F_DUPFD_CLOEXEC, 50)
		if a < 0 || b < 0 || alias < 0 || extra < 0 || C.dup3(a, 64, C.O_CLOEXEC) != 64 { C._exit(1) }
		expect(tally, 0, a, C.F_OFD_SETLK, C.F_WRLCK, 10, 20, 0, raw, c'owner write')
		inspect(tally, 0, a, C.F_OFD_GETLK, C.F_UNLCK, 0, 100, C.F_WRLCK, 10, 20, -1, raw, c'query own writer')
		inspect(tally, 0, b, C.F_OFD_GETLK, C.F_UNLCK, 0, 100, C.F_UNLCK, 0, 100, 0, raw, c'own query excludes other owners')
		for fd in [a, alias, extra, i32(64)]! { inspect(tally, 0, fd, C.F_OFD_GETLK, C.F_WRLCK, 10, 20, C.F_UNLCK, 10, 20, 0, raw, c'alias ignores own lock') }
		inspect(tally, 0, b, C.F_OFD_GETLK, C.F_WRLCK, 0, 100, C.F_WRLCK, 10, 20, -1, raw, c'reopened OFD conflict')
		inspect(tally, 0, a, C.F_GETLK, C.F_WRLCK, 0, 100, C.F_WRLCK, 10, 20, -1, raw, c'POSIX query sees OFD')
		expect(tally, 0, b, C.F_OFD_SETLK, C.F_WRLCK, 10, 20, C.EAGAIN, raw, c'reopen write refused')
		expect(tally, 0, a, C.F_SETLK, C.F_WRLCK, 10, 20, C.EAGAIN, raw, c'POSIX same-handle conflict')
		expect(tally, 0, alias, C.F_OFD_SETLK, C.F_RDLCK, 10, 20, 0, raw, c'alias conversion')
		inspect(tally, 0, extra, C.F_OFD_GETLK, C.F_UNLCK, 10, 20, C.F_RDLCK, 10, 20, -1, raw, c'query own reader through alias')
		expect(tally, 0, b, C.F_OFD_SETLK, C.F_RDLCK, 10, 20, 0, raw, c'compatible readers')
		expect(tally, 0, a, C.F_OFD_SETLK, C.F_WRLCK, 10, 20, C.EAGAIN, raw, c'upgrade conflicts with reader')
		expect(tally, 0, b, C.F_OFD_SETLK, C.F_UNLCK, 0, 0, 0, raw, c'reopen unlock')
		expect(tally, 0, extra, C.F_OFD_SETLK, C.F_UNLCK, 0, 0, 0, raw, c'alias unlock')
		expect(tally, 0, a, C.F_SETLK, C.F_WRLCK, 40, 10, 0, raw, c'POSIX owner write')
		inspect(tally, 0, b, C.F_GETLK, C.F_WRLCK, 40, 10, C.F_UNLCK, 40, 10, 12345, raw, c'POSIX query preserves absent fields')
		inspect(tally, 0, a, C.F_OFD_GETLK, C.F_WRLCK, 40, 10, C.F_WRLCK, 40, 10, C.getpid(), raw, c'OFD query sees process PID')
		expect(tally, 0, alias, C.F_OFD_SETLK, C.F_WRLCK, 40, 10, C.EAGAIN, raw, c'OFD conflicts with own POSIX')
		expect(tally, 0, b, C.F_SETLK, C.F_UNLCK, 0, 0, 0, raw, c'POSIX same-process unlock')
		expect(tally, 0, a, C.F_OFD_SETLK, C.F_WRLCK, 60, 10, 0, raw, c'close owner seed')
		for fd in [a, alias, extra]! { check(tally, 0, C.close(fd) == 0, c'close alias'); inspect(tally, 0, b, C.F_OFD_GETLK, C.F_WRLCK, 60, 10, C.F_WRLCK, 60, 10, -1, raw, c'nonfinal close retains') }
		// Closing an unrelated description must not discard an OFD lock.
		unrelated := C.open(path, C.O_RDONLY); check(tally, 0, unrelated >= 0 && C.close(unrelated) == 0, c'close unrelated')
		inspect(tally, 0, b, C.F_GETLK, C.F_WRLCK, 60, 10, C.F_WRLCK, 60, 10, -1, raw, c'unrelated close retains')
		check(tally, 0, C.flock(b, C.LOCK_EX | C.LOCK_NB) == 0, c'flock separate conflict domain')
		inspect(tally, 0, b, C.F_OFD_GETLK, C.F_WRLCK, 60, 10, C.F_WRLCK, 60, 10, -1, raw, c'flock acquire retains OFD')
		check(tally, 0, C.flock(b, C.LOCK_UN) == 0 && C.flock(64, C.LOCK_SH | C.LOCK_NB) == 0 && C.flock(64, C.LOCK_UN) == 0, c'flock conversion unlock')
		inspect(tally, 0, b, C.F_OFD_GETLK, C.F_WRLCK, 60, 10, C.F_WRLCK, 60, 10, -1, raw, c'flock unlock retains OFD')
		check(tally, 0, C.close(64) == 0, c'close final'); expect(tally, 0, b, C.F_OFD_SETLK, C.F_WRLCK, 60, 10, 0, raw, c'final close releases'); C.close(b)
	}
}
fn ranges(tally &Tally, path &char, raw bool) {
	unsafe {
		a := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR); if a < 0 || b < 0 { C._exit(1) }
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_WRLCK, 10, 30, 0, raw, c'range seed')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_UNLCK, 20, 10, 0, raw, c'middle unlock')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 10, 1, C.F_WRLCK, 10, 10, -1, raw, c'left split')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 20, 10, C.F_UNLCK, 20, 10, 0, raw, c'unlocked middle')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 30, 1, C.F_WRLCK, 30, 10, -1, raw, c'right split')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_WRLCK, 20, 10, 0, raw, c'bridge ranges')
		inspect(tally, 1, b, C.F_GETLK, C.F_WRLCK, 25, 1, C.F_WRLCK, 10, 30, -1, raw, c'coalesced bridge')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_RDLCK, 20, 10, 0, raw, c'middle downgrade')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 25, 1, C.F_RDLCK, 20, 10, -1, raw, c'middle converted')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_RDLCK, 20, 10, C.F_UNLCK, 20, 10, 0, raw, c'reader compatible')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_UNLCK, 0, 0, 0, raw, c'clear splits')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_WRLCK, 80, -10, 0, raw, c'negative length')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 70, 10, C.F_WRLCK, 70, 10, -1, raw, c'normalized negative length')
		flk := &C.flock(C.alloca(usize(sizeof(C.flock)))); *flk = C.flock{ l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_CUR), l_start: -5, l_len: 5 }
		check(tally, 1, C.lseek(a, 100, C.SEEK_SET) == 100 && call(a, C.F_OFD_SETLK, flk, raw).ret == 0, c'relative cursor')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 95, 5, C.F_WRLCK, 95, 5, -1, raw, c'normalized cursor')
		*flk = C.flock{ l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_END), l_start: 4, l_len: 6 }
		check(tally, 1, call(a, C.F_OFD_SETLK, flk, raw).ret == 0, c'relative EOF')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, 20, 6, C.F_WRLCK, 20, 6, -1, raw, c'normalized EOF')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_WRLCK, i64(0x100000010), 9, 0, raw, c'64-bit range')
		inspect(tally, 1, b, C.F_OFD_GETLK, C.F_WRLCK, i64(0x100000010), 1, C.F_WRLCK, i64(0x100000010), 9, -1, raw, c'64-bit query')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_UNLCK, 0, 0, 0, raw, c'clear ranges')
		expect(tally, 1, a, C.F_OFD_SETLK, C.F_WRLCK, 1000, 0, 0, raw, c'unbounded range')
		inspect(tally, 1, b, C.F_GETLK, C.F_WRLCK, i64(0x200000000), 1, C.F_WRLCK, 1000, 0, -1, raw, c'unbounded query')
		C.close(a); C.close(b)
	}
}
fn errors(tally &Tally, path &char, raw bool) {
	unsafe {
		a := C.open(path, C.O_RDWR); rd := C.open(path, C.O_RDONLY); wr := C.open(path, C.O_WRONLY); opath := C.open(path, C.O_PATH); if a < 0 || rd < 0 || wr < 0 || opath < 0 { C._exit(1) }
		flk := &C.flock(C.alloca(usize(sizeof(C.flock))))
		for cmd in [i32(C.F_OFD_GETLK), C.F_OFD_SETLK, C.F_OFD_SETLKW]! {
			for pid in [i32(1), -1, i32(-2147483647 - 1)]! { *flk = C.flock{l_type: i16(C.F_WRLCK), l_len: 1, l_pid: pid}; result := call(a, cmd, flk, raw); check(tally, 2, result.ret == -1 && result.code == C.EINVAL, c'nonzero OFD PID') }
			for invalid in [i32(0), 1]! { result := call(a, cmd, &C.flock(usize(invalid)), raw); check(tally, 2, result.ret == -1 && result.code == C.EFAULT, c'invalid pointer') }
			*flk = C.flock{l_type: 99, l_len: 1}; invalid_type := call(a, cmd, flk, raw); check(tally, 2, invalid_type.ret == -1 && invalid_type.code == C.EINVAL, c'invalid type')
			*flk = C.flock{l_type: i16(C.F_WRLCK), l_whence: 99, l_len: 1}; whence := call(a, cmd, flk, raw); check(tally, 2, whence.ret == -1 && whence.code == C.EINVAL, c'invalid whence')
			for start in [i64(-1), i64(-0x7fffffffffffffff - 1)]! { *flk = C.flock{l_type: i16(C.F_WRLCK), l_start: start, l_len: 1}; result := call(a, cmd, flk, raw); check(tally, 2, result.ret == -1 && result.code == C.EINVAL, c'negative range') }
			*flk = C.flock{l_type: i16(C.F_WRLCK), l_start: i64(0x7fffffffffffffff), l_len: 2}; overflow := call(a, cmd, flk, raw); check(tally, 2, overflow.ret == -1 && overflow.code == C.EOVERFLOW, c'range overflow')
			for fd in [i32(-1), i32(127), opath]! { result := call(fd, cmd, &C.flock(usize(1)), raw); check(tally, 2, result.ret == -1 && result.code == C.EBADF, c'descriptor refusal before pointer') }
		}
		for cmd in [i32(C.F_OFD_SETLK), C.F_OFD_SETLKW]! { expect(tally, 2, rd, cmd, C.F_WRLCK, 0, 1, C.EBADF, raw, c'readonly write refusal'); expect(tally, 2, wr, cmd, C.F_RDLCK, 0, 1, C.EBADF, raw, c'writeonly read refusal') }
		inspect(tally, 2, rd, C.F_OFD_GETLK, C.F_WRLCK, 0, 1, C.F_UNLCK, 0, 1, 0, raw, c'readonly query permitted')
		inspect(tally, 2, wr, C.F_GETLK, C.F_RDLCK, 0, 1, C.F_UNLCK, 0, 1, 12345, raw, c'writeonly POSIX query permitted')
		expect(tally, 2, a, C.F_OFD_GETLK, C.F_UNLCK, 0, 1, 0, raw, c'empty own-lock query')
		expect(tally, 2, a, C.F_GETLK, C.F_UNLCK, 0, 1, C.EINVAL, raw, c'POSIX unlock query refused')
		C.close(opath); C.close(wr); C.close(rd); C.close(a)
	}
}
fn sleeping(pid i32) bool {
	unsafe { mut path := [128]char{}; mut data := [4096]char{}; if C.snprintf(&path[0], 128, c'/proc/%d/status', pid) <= 0 { return false }
		for _ in 0 .. 100 { fd := C.open(&path[0], C.O_RDONLY); if fd < 0 { return false }; n := C.read(fd, &data[0], 4095); C.close(fd); if n > 0 { data[int(n)] = 0; if C.strstr(&data[0], c'State:\tS') != nil { return true } }; C.usleep(10000) }; return false
	}
}
fn caught(_ i32) {}
// Independent child opens really block. Parent releases, downgrades, or sends
// a non-restarting signal only after observing the blocked child in procfs.
fn blocking(tally &Tally, path &char, mode i32) {
	unsafe {
		a := C.open(path, C.O_RDWR); if a < 0 || change(a, C.F_OFD_SETLK, C.F_WRLCK, 0, 16, false).ret != 0 { C._exit(1) }
		ready := &i32(C.alloca(usize(2 * sizeof(i32)))); done := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe(ready) != 0 || C.pipe(done) != 0 { C._exit(1) }
		child := C.fork(); if child < 0 { C._exit(1) }
		if child == 0 {
			C.alarm(15); C.close(ready[0]); C.close(done[0]); C.close(a); b := C.open(path, C.O_RDWR); if b < 0 { C._exit(1) }
			if mode == 1 { C.signal(C.SIGUSR1, caught); if C.siginterrupt(C.SIGUSR1, 1) != 0 { C._exit(1) } }
			if C.write(ready[1], c'R', 1) != 1 { C._exit(1) }
			result := &Query(C.alloca(usize(sizeof(Query)))); *result = change(b, C.F_OFD_SETLKW, if mode == 2 { C.F_RDLCK } else { C.F_WRLCK }, 0, 16, true)
			if C.write(done[1], result, usize(sizeof(Query))) != isize(sizeof(Query)) { C._exit(1) }; C.close(b); C._exit(0)
		}
		C.close(ready[1]); C.close(done[1]); mut byte := char(0); result := &Query(C.alloca(usize(sizeof(Query)))); poll := &C.pollfd(C.alloca(usize(sizeof(C.pollfd)))); *poll = C.pollfd{fd: done[0], events: i16(C.POLLIN)}
		blocked := C.read(ready[0], &byte, 1) == 1 && byte == char(`R`) && sleeping(child) && C.poll(poll, 1, 0) == 0
		check(tally, 3, blocked, c'waiter sleeps before intervention')
		if mode == 1 { check(tally, 3, C.kill(child, C.SIGUSR1) == 0, c'interrupt waiter') }
		else { expect(tally, 3, a, C.F_OFD_SETLK, if mode == 2 { C.F_RDLCK } else { C.F_UNLCK }, 0, 16, 0, false, c'release or downgrade') }
		finished := C.poll(poll, 1, 10000) == 1 && C.read(done[0], result, usize(sizeof(Query))) == isize(sizeof(Query))
		check(tally, 3, finished && result.ret == if mode == 1 { -1 } else { 0 } && result.code == if mode == 1 { i32(C.EINTR) } else { 0 }, c'waiter result')
		if !finished { C.kill(child, C.SIGKILL) }; mut status := i32(-1); check(tally, 3, C.waitpid(child, &status, 0) == child && status == 0, c'waiter exit')
		C.close(ready[0]); C.close(done[0]); C.close(a)
	}
}
fn inheritance(tally &Tally, path &char) {
	unsafe {
		a := C.open(path, C.O_RDWR); alias := C.dup(a); b := C.open(path, C.O_RDWR); if a < 0 || alias < 0 || b < 0 { C._exit(1) }
		expect(tally, 4, a, C.F_OFD_SETLK, C.F_WRLCK, 0, 16, 0, true, c'fork lock seed')
		ready := &i32(C.alloca(usize(2 * sizeof(i32)))); command := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe(ready) != 0 || C.pipe(command) != 0 { C._exit(1) }
		child := C.fork(); if child < 0 { C._exit(1) }
		if child == 0 { C.alarm(15); C.close(ready[0]); C.close(command[1]); C.close(b); C.close(a)
			result := change(alias, C.F_OFD_SETLK, C.F_WRLCK, 0, 16, true); mut byte := char(0)
			if result.ret != 0 || C.write(ready[1], c'R', 1) != 1 || C.read(command[0], &byte, 1) != 1 || byte != char(`X`) { C._exit(1) }
			// Exit closes the child's last alias without an explicit unlock.
			C._exit(0)
		}
		C.close(ready[1]); C.close(command[0]); mut byte := char(0)
		check(tally, 4, C.read(ready[0], &byte, 1) == 1 && byte == char(`R`), c'fork shares lock owner')
		check(tally, 4, C.close(a) == 0 && C.close(alias) == 0, c'parent closes all aliases')
		inspect(tally, 4, b, C.F_GETLK, C.F_WRLCK, 0, 16, C.F_WRLCK, 0, 16, -1, true, c'child keeps inherited lock')
		expect(tally, 4, b, C.F_OFD_SETLK, C.F_WRLCK, 0, 16, C.EAGAIN, true, c'inherited conflict remains')
		check(tally, 4, C.write(command[1], c'X', 1) == 1, c'ask child to exit'); mut status := i32(-1)
		check(tally, 4, C.waitpid(child, &status, 0) == child && status == 0, c'last inheritor exits')
		expect(tally, 4, b, C.F_OFD_SETLK, C.F_WRLCK, 0, 16, 0, true, c'child final close releases')
		C.close(ready[0]); C.close(command[1]); C.close(b)
	}
}
fn cycle(path &char) bool {
	unsafe {
		a := C.open(path, C.O_RDWR); b := C.open(path, C.O_RDWR); alias := C.dup(a)
		if a < 0 || b < 0 || alias < 0 { if a >= 0 { C.close(a) }; if b >= 0 { C.close(b) }; if alias >= 0 { C.close(alias) }; return false }
		mut good := change(a, C.F_OFD_SETLK, C.F_WRLCK, 10, 30, true).ret == 0
		if change(a, C.F_OFD_SETLK, C.F_UNLCK, 20, 10, true).ret != 0 { good = false }
		if change(alias, C.F_OFD_SETLK, C.F_WRLCK, 20, 10, true).ret != 0 { good = false }
		if change(b, C.F_OFD_SETLK, C.F_WRLCK, 20, 10, true).code != C.EAGAIN { good = false }
		if C.close(a) != 0 { good = false }
		if change(b, C.F_OFD_SETLK, C.F_RDLCK, 20, 10, true).code != C.EAGAIN { good = false }
		if C.close(alias) != 0 { good = false }
		if change(b, C.F_OFD_SETLK, C.F_WRLCK, 20, 10, true).ret != 0 { good = false }
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
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX OFDLOCKS SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX OFDLOCKS STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
fn qualify(ordinary bool, reference_run bool) bool {
	unsafe {
		C.alarm(180); if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		path := if ordinary { &char(c'/tmp/linux-ofdlocks-user') } else { &char(c'/tmp/linux-ofdlocks-root') }
		seed := C.open(path, C.O_RDWR); if seed < 0 || C.close(seed) != 0 { return false }
		counts := &Tally(C.alloca(usize(sizeof(Tally)))); *counts = Tally{}
		for raw in [false, true]! { identity(counts, path, raw); ranges(counts, path, raw); errors(counts, path, raw) }
		mut good := true
		for kind in 0 .. 3 { if counts.failures[kind] != 0 { good = false } }
		// A failing shortcut must never enter an unbounded blocking test.
		if good { for mode in 0 .. 3 { blocking(counts, path, i32(mode)) }; inheritance(counts, path) }
		for kind in 0 .. 5 { C.printf(c'LINUX OFDLOCKS CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(kind), counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		fd := C.open(path, C.O_RDONLY); mut data := [16]char{}; if fd < 0 || C.pread(fd, &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'ofd-lock-bytes!\n', 16) != 0 || C.close(fd) != 0 { good = false }
		if good && !reference_run && !storage(path, ordinary) { good = false }; C.alarm(0); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for path in [&char(c'/tmp/linux-ofdlocks-user'), &char(c'/tmp/linux-ofdlocks-root')]! {
			seed := C.open(path, C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600)); if seed < 0 || C.write(seed, c'ofd-lock-bytes!\n', 16) != 16 || C.close(seed) != 0 { return 1 }
		}
		if C.chown(c'/tmp/linux-ofdlocks-user', 1000, 1000) != 0 { return 1 }
		for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		if C.unlink(c'/tmp/linux-ofdlocks-user') != 0 || C.unlink(c'/tmp/linux-ofdlocks-root') != 0 { good = false }
		if !good { C.puts(c'LINUX OFDLOCKS FAIL: ownership, ranges, errors, blocking or storage'); C.fflush(nil); return 1 }
		if reference_run { C.puts(c'LINUX OFDLOCKS REFERENCE: PASS') } else { C.puts(c'LINUX OFDLOCKS: PASS') }; C.fflush(nil); for { C.pause() }
	}; return 0
}
