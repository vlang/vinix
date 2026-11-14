// SPDX-License-Identifier: GPL-2.0-or-later
module selectfdsfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[typedef]
struct C.fd_set {}
@[typedef]
struct C.sigset_t {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.timeval { mut: tv_sec i64 tv_usec i64 }
struct Totals { mut: checks int failures int }
struct Guard { mut: before u64 words [16]u64 after u64 }
struct MaskArg { mut: mask voidptr size u64 }
struct Targets { mut: regular i32 directory i32 link i32 anchor i32 peer i32 page voidptr length usize }

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.dup3(i32, i32, i32) i32
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.pipe(&i32) i32
fn C.pselect(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timespec, &C.sigset_t) i32
fn C.select(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timeval) i32

fn fatal(stage int) {
	C.printf(c'LINUX SELECTFDS FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut totals Totals, good bool) {
	totals.checks++
	if !good { totals.failures++ }
}
fn targets() Targets {
	unsafe {
		mut t := Targets{}
		t.regular = C.open(c'/tmp/selectfds/file', C.O_RDONLY)
		t.directory = C.open(c'/tmp/selectfds', C.O_PATH | C.O_DIRECTORY)
		t.link = C.open(c'/tmp/selectfds/link', C.O_PATH | C.O_NOFOLLOW)
		t.anchor = C.open(c'/tmp/selectfds/file', C.O_PATH)
		if t.regular < 0 || t.directory < 0 || t.link < 0 || t.anchor < 0 { fatal(1) }
		if C.dup3(t.regular, 1023, C.O_CLOEXEC) != 1023 { fatal(2) }
		mut sockets := [2]i32{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) != 0 { fatal(3) }
		if C.dup3(sockets[0], 32, C.O_CLOEXEC) != 32 || C.dup3(sockets[0], 1000, C.O_CLOEXEC) != 1000
			|| C.write(sockets[1], c'Q', 1) != 1 { fatal(4) }
		C.close(sockets[0]); t.peer = sockets[1]
		t.length = usize(C.sysconf(C._SC_PAGESIZE))
		t.page = C.mmap(nil, t.length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if t.page == voidptr(isize(-1)) { fatal(5) }
		initial := u64(1) << 14 // SIGTERM stays blocked before and after every call.
		if C.syscall(isize(C.SYS_rt_sigprocmask), 2, &initial, nil, 8) != 0 { fatal(6) }
		return t
	}
}
fn install(t &Targets, kind int, target i32) {
	unsafe {
		source := if kind == 1 { t.anchor } else if kind == 2 { t.directory } else if kind == 3 { t.link } else { t.regular }
		if C.dup3(source, target, C.O_CLOEXEC) != target { fatal(7) }
		if kind in [0, 5] && C.close(target) != 0 { fatal(8) }
	}
}
fn make_guard(target int, live int, nfds int) Guard {
	unsafe {
	mut result := Guard{before: 0xabcddcba12344321, after: 0x87654321fedcba98}
	for word in (nfds + 63) / 64 .. 16 { result.words[word] = 0x1122334455667788 }
	result.words[target / 64] |= u64(1) << u64(target % 64)
	if live >= 0 { result.words[live / 64] |= u64(1) << u64(live % 64) }
	return result
	}
}
fn call(api int, nfds int, reads &Guard, writes &Guard, excepts &Guard, sets int, timed int) isize {
	unsafe {
		r := if sets & 1 != 0 { &C.fd_set(&reads.words[0]) } else { &C.fd_set(nil) }
		w := if sets & 2 != 0 { &C.fd_set(&writes.words[0]) } else { &C.fd_set(nil) }
		e := if sets & 4 != 0 { &C.fd_set(&excepts.words[0]) } else { &C.fd_set(nil) }
		mut ts := C.timespec{tv_nsec: if timed == 1 { 1_000_000 } else { 0 }}
		mut tv := C.timeval{tv_usec: if timed == 1 { 1000 } else { 0 }}
		tsp := if timed == 2 { &C.timespec(nil) } else { &ts }
		tvp := if timed == 2 { &C.timeval(nil) } else { &tv }
		mut mask := [16]u64{}
		mask[0] = u64(1) << 9 // pselect temporarily blocks SIGUSR1 instead.
		pair := MaskArg{mask: &mask[0], size: 8}
		errno_slot := C.__errno_location()
		*errno_slot = 0
		match api {
			0 { return C.syscall(isize(C.SYS_pselect6), nfds, r, w, e, tsp, &pair) }
			1 { return C.pselect(i32(nfds), r, w, e, tsp, &C.sigset_t(&mask[0])) }
			2 { return C.select(i32(nfds), r, w, e, tvp) }
			else {
				$if amd64 { return C.syscall(isize(C.SYS_select), nfds, r, w, e, tvp) }
				$else { fatal(9); return -1 }
			}
		}
	}
}
fn probe(t &Targets, api int, kind int, target int, layout int, sets int, timed int, readonly bool) Totals {
	unsafe {
		live := if layout == 0 { -1 } else if layout == 1 { 32 } else { 1000 }
		nfds := if kind == 5 { 64 } else { if target > live { target } else { live } + 1 }
		input := &Guard(C.alloca(usize(sizeof(Guard))))
		*input = make_guard(target, live, nfds)
		local := &Guard(C.alloca(usize(3 * sizeof(Guard))))
		buffers := if readonly { &Guard(t.page) } else { local }
		for i in 0 .. 3 { buffers[i] = *input }
		if readonly && C.mprotect(t.page, t.length, C.PROT_READ) != 0 { fatal(10) }
		result := call(api, nfds, &buffers[0], &buffers[1], &buffers[2], sets, timed)
		code := *C.__errno_location()
		if readonly && C.mprotect(t.page, t.length, C.PROT_READ | C.PROT_WRITE) != 0 { fatal(11) }
		mut mask := u64(0)
		queried := C.syscall(isize(C.SYS_rt_sigprocmask), 0, nil, &mask, 8)
		mut expected := isize(0)
		if kind == 0 { expected = -1 }
		else {
			for set in 0 .. 3 {
				if sets & (1 << set) == 0 { continue }
				if kind in [1, 2, 3] || (kind == 4 && set != 2) { expected++ }
				if live >= 0 && set != 2 { expected++ }
			}
		}
		mut totals := Totals{}
		check(mut totals, result == expected)
		check(mut totals, code == if kind == 0 { i32(C.EBADF) } else { i32(0) })
		for set in 0 .. 3 {
			wanted := &Guard(C.alloca(usize(sizeof(Guard))))
			*wanted = *input
			if kind != 0 && sets & (1 << set) != 0 {
				for word in 0 .. (nfds + 63) / 64 { wanted.words[word] = 0 }
				if kind in [1, 2, 3] || (kind == 4 && set != 2) {
					wanted.words[target / 64] |= u64(1) << u64(target % 64)
				}
				if live >= 0 && set != 2 { wanted.words[live / 64] |= u64(1) << u64(live % 64) }
			}
			check(mut totals, C.memcmp(&buffers[set], wanted, sizeof(Guard)) == 0)
		}
		check(mut totals, queried == 0 && mask == u64(1) << 14)
		return totals
	}
}
fn qualify(t &Targets, apis int) Totals {
	mut total := Totals{}
	for api in 0 .. apis { for kind in 0 .. 6 { for buffer in 0 .. if kind == 0 { 2 } else { 1 } {
		mut group := Totals{}
		for target_index in 0 .. if kind == 5 { 1 } else { 4 } {
			target := if kind == 5 { 95 } else { match target_index { 0 { 63 } 1 { 64 } 2 { 95 } else { 1022 } } }
			install(t, kind, i32(target))
			for layout in 0 .. 3 { for sets in 1 .. 8 { for timed in 0 .. if kind == 5 { 1 } else { 3 } {
				if kind == 5 && layout != 1 { continue }
				if kind == 4 && sets == 4 && timed == 2 { continue }
				result := probe(t, api, kind, target, layout, sets, timed, buffer == 1)
				if group.failures == 0 && result.failures > 0 {
					C.printf(c'LINUX SELECTFDS FIRST: uid=%u api=%d kind=%d buffer=%d target=%d layout=%d sets=%d timed=%d failures=%d\n', C.getuid(), api, kind, buffer, target, layout, sets, timed, result.failures)
				}
				group.checks += result.checks; group.failures += result.failures
			} } }
			if kind !in [0, 5] && C.close(i32(target)) != 0 { fatal(12) }
		}
		C.printf(c'LINUX SELECTFDS CASE: uid=%u gid=%u api=%d kind=%d buffer=%d checks=%d failures=%d\n', C.getuid(), C.getgid(), api, kind, buffer, group.checks, group.failures)
		total.checks += group.checks; total.failures += group.failures
	} } }
	return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		if C.chmod(c'/tmp', 0o1777) != 0 || C.mkdir(c'/tmp/selectfds', 0o777) != 0
			|| C.chmod(c'/tmp/selectfds', 0o777) != 0 { fatal(13) }
		file := C.open(c'/tmp/selectfds/file', C.O_CREAT | C.O_EXCL | C.O_RDWR, u32(0o666))
		if file < 0 || C.close(file) != 0 || C.chmod(c'/tmp/selectfds/file', 0o666) != 0
			|| C.symlink(c'file', c'/tmp/selectfds/link') != 0 { fatal(14) }
		mut apis := 3
		$if amd64 { apis = 4 }
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false, true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { fatal(15) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(16) }
			if pid == 0 {
				C.close(channel[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(17) }
				t := targets()
				sum := qualify(&t, apis)
				good := if reference { C.printf(c'LINUX SELECTFDS STORAGE: uid=%u SKIP reference\n', C.getuid()); true } else { storage(&t, apis) }
				mut answer := [3]int{init: 0}
				answer[0] = sum.checks; answer[1] = sum.failures; answer[2] = if good { 0 } else { 1 }
				if C.write(channel[1], &answer[0], sizeof(answer)) != isize(sizeof(answer)) { fatal(18) }
				C.fflush(nil); C._exit(0)
			}
			C.close(channel[1]); mut answer := [3]int{}
			if C.read(channel[0], &answer[0], sizeof(answer)) != isize(sizeof(answer)) { fatal(19) }
			C.close(channel[0]); mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(20) }
			total.checks += answer[0]; total.failures += answer[1]
			if answer[2] != 0 { storage_good = false }
		}
		C.printf(c'LINUX SELECTFDS SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		C.printf(c'LINUX SELECTFDS: %s\n', if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
