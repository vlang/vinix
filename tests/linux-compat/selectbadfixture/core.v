// SPDX-License-Identifier: GPL-2.0-or-later
module selectbadfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
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
struct GuardSet { mut: before u64 words [16]u64 after u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows int large u64 tainted u64 }
struct Targets { mut: sockets [2]i32 alias i32 bad i32 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.alloca(usize) voidptr
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.pipe(&i32) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.usleep(u32) i32
fn C.pselect(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timespec, &C.sigset_t) i32
fn C.select(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timeval) i32

fn fatal(stage int) {
	C.printf(c'LINUX SELECTBAD FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, api int, layout int, sets int, timed int, stage int) {
	t.checks++
	if !good {
		t.failures++
		C.printf(c'LINUX SELECTBAD MISMATCH: uid=%u api=%d layout=%d sets=%d timed=%d stage=%d\n', C.getuid(), api, layout, sets, timed, stage)
	}
}
fn targets() Targets {
	unsafe {
		mut t := Targets{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &t.sockets[0]) != 0 { fatal(1) }
		value := u8(0x51)
		if C.write(t.sockets[1], &value, 1) != 1 { fatal(2) }
		t.alias = C.fcntl(t.sockets[0], C.F_DUPFD_CLOEXEC, 70)
		if t.alias < 70 || t.alias >= 1024 { fatal(3) }
		t.bad = C.fcntl(t.sockets[0], C.F_DUPFD_CLOEXEC, 0)
		if t.bad < 0 || t.bad >= t.alias || C.close(t.bad) != 0 { fatal(4) }
		// A surviving higher descriptor prevents Linux from ignoring a bit
		// beyond its allocated descriptor-table capacity.
		if C.fcntl(t.bad, C.F_GETFD) != -1 || *C.__errno_location() != C.EBADF || C.fcntl(t.alias, C.F_GETFD) != C.FD_CLOEXEC { fatal(5) }
		return t
	}
}
fn close_targets(t &Targets) { unsafe { C.close(t.sockets[0]); C.close(t.sockets[1]); C.close(t.alias) } }
fn call(api int, nfds int, reads &GuardSet, writes &GuardSet, excepts &GuardSet, sets int, timed int) isize {
	unsafe {
		r := if sets & 1 == 0 { &C.fd_set(nil) } else { &C.fd_set(&reads.words[0]) }
		w := if sets & 2 == 0 { &C.fd_set(nil) } else { &C.fd_set(&writes.words[0]) }
		e := if sets & 4 == 0 { &C.fd_set(nil) } else { &C.fd_set(&excepts.words[0]) }
		mut ts := C.timespec{tv_nsec: if timed == 0 { 0 } else { 1_000_000 }}
		mut tv := C.timeval{tv_usec: if timed == 0 { 0 } else { 1000 }}
		tsp := if timed == 2 { &C.timespec(nil) } else { &ts }
		tvp := if timed == 2 { &C.timeval(nil) } else { &tv }
		errno_pointer := C.__errno_location(); *errno_pointer = 0
		match api {
			0 { return C.syscall(isize(C.SYS_pselect6), nfds, r, w, e, tsp, nil) }
			1 { return C.pselect(nfds, r, w, e, tsp, nil) }
			2 { return C.select(nfds, r, w, e, tvp) }
			else {
				$if amd64 { return C.syscall(isize(C.SYS_select), nfds, r, w, e, tvp) }
				$else { fatal(6); return -1 }
			}
		}
	}
}
fn make_set(t &Targets, layout int) GuardSet {
	unsafe {
		mut s := GuardSet{before: 0xabcddcba12344321, after: 0x87654321fedcba98}
		for i in ((int(t.alias) + 64) / 64) .. 16 { s.words[i] = 0x1122334455667788 }
		s.words[t.bad / 64] |= u64(1) << u64(t.bad % 64)
		if layout in [1, 3]! { s.words[t.sockets[0] / 64] |= u64(1) << u64(t.sockets[0] % 64) }
		if layout in [2, 3]! { s.words[t.alias / 64] |= u64(1) << u64(t.alias % 64) }
		return s
	}
}
fn same_set(actual &GuardSet, expected &GuardSet) bool {
	unsafe {
		if actual.before != expected.before || actual.after != expected.after { return false }
		for word in 0 .. 16 { if actual.words[word] != expected.words[word] { return false } }
		return true
	}
}
fn probe(t &Targets, api int, layout int, sets int, timed int) Totals {
	unsafe {
		input := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *input = make_set(t, layout)
		reads := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *reads = *input
		writes := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *writes = *input
		excepts := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *excepts = *input
		ret := call(api, int(t.alias) + 1, reads, writes, excepts, sets, timed)
		code := *C.__errno_location()
		mut total := Totals{}
		check(mut total, ret == -1, api, layout, sets, timed, 1)
		check(mut total, code == C.EBADF, api, layout, sets, timed, 2)
		check(mut total, same_set(reads, input), api, layout, sets, timed, 3)
		check(mut total, same_set(writes, input), api, layout, sets, timed, 4)
		check(mut total, same_set(excepts, input), api, layout, sets, timed, 5)
		if total.failures != 0 { C.printf(c'LINUX SELECTBAD DETAIL: actual=%ld/%d expected=-1/%d\n', ret, code, C.EBADF) }
		return total
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); *counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0; mut large := false; mut guarded := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			else if C.sscanf(&data[position], c'# written after free %lu', &counts.tainted) == 1 { guarded = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large && guarded
	}
}
fn storage_cycle(t &Targets, apis int) int {
	unsafe {
		mut refused := 0
		for api in 0 .. apis {
			input := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *input = make_set(t, 3)
			reads := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *reads = *input
			writes := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *writes = *input
			excepts := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *excepts = *input
			ret := call(api, int(t.alias) + 1, reads, writes, excepts, 7, 2)
			code := *C.__errno_location()
			if ret == -1 && code == C.EBADF {
				if !same_set(reads, input) || !same_set(writes, input) || !same_set(excepts, input) { fatal(7) }
				refused++
			} else {
				// Keep the original incorrect result as a comparable storage
				// baseline; every semantic case above still requires EBADF.
				expected := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *expected = *input
				expected.words[t.bad / 64] &= ~(u64(1) << u64(t.bad % 64))
				empty := &GuardSet(C.alloca(usize(sizeof(GuardSet)))); *empty = *expected
				for word in 0 .. ((int(t.alias) + 64) / 64) { empty.words[word] = 0 }
				if ret !in [isize(2), 4]! || code != 0 || !same_set(reads, expected) || !same_set(writes, expected) || !same_set(excepts, empty) { fatal(8) }
			}
		}
		return refused
	}
}
fn storage(apis int) bool {
	unsafe {
		C.alarm(90)
		t := targets()
		defer { close_targets(&t) }
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(9) }
		defer { C.close(fd) }
		// /proc/slabinfo may reuse the original closed slot. Choose a fresh
		// lower slot after opening it and keep all descriptors stable.
		measured := &Targets(C.alloca(usize(sizeof(Targets)))); *measured = t
		measured.bad = C.fcntl(t.sockets[0], C.F_DUPFD_CLOEXEC, 0)
		if measured.bad < 0 || measured.bad >= t.alias || C.close(measured.bad) != 0 { fatal(10) }
		for _ in 0 .. 64 { storage_cycle(measured, apis) }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(fd, before) { fatal(11) }
		mut refused := 0
		for _ in 0 .. 200 { refused += storage_cycle(measured, apis) }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(12) }
		mut good := before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] { good = false }
			C.printf(c'LINUX SELECTBAD SLAB: uid=%u size=%lu live=%lu/%lu cycles=200\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX SELECTBAD STORAGE: uid=%u cycles=200 refused=%d big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), refused, before.large, after.large, before.tainted, after.tainted, if good { &char(c'PASS') } else { &char(c'FAIL') })
		return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut apis := 3
		$if amd64 { apis = 4 }
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false, true]! {
			mut pipefds := [2]i32{}
			if C.pipe(&pipefds[0]) != 0 { fatal(13) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(14) }
			if pid == 0 {
				C.alarm(30)
				C.close(pipefds[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(15) }
				t := targets()
				mut sum := Totals{}
				for api in 0 .. apis { for layout in 0 .. 4 {
					mut group := Totals{}
					for sets in 1 .. 8 { for timed in 0 .. 3 {
						result := probe(&t, api, layout, sets, timed)
						group.checks += result.checks; group.failures += result.failures
					} }
					C.printf(c'LINUX SELECTBAD CASE: uid=%u gid=%u api=%d layout=%d sets=7 timeouts=3 bad=%d highest=%d checks=%d failures=%d\n', C.getuid(), C.getgid(), api, layout, t.bad, t.alias, group.checks, group.failures)
					sum.checks += group.checks; sum.failures += group.failures
				} }
				close_targets(&t)
				if C.write(pipefds[1], &sum, sizeof(sum)) != sizeof(sum) { fatal(16) }
				C.fflush(nil); C._exit(0)
			}
			C.close(pipefds[1])
			mut sum := Totals{}
			if C.read(pipefds[0], &sum, sizeof(sum)) != sizeof(sum) { fatal(17) }
			C.close(pipefds[0])
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(18) }
			total.checks += sum.checks; total.failures += sum.failures
			C.fflush(nil)
			storage_pid := C.fork()
			if storage_pid < 0 { fatal(19) }
			if storage_pid == 0 {
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(20) }
				if reference { C.printf(c'LINUX SELECTBAD STORAGE: uid=%u SKIP reference\n', C.getuid()); C.fflush(nil); C._exit(0) }
				good := storage(apis)
				C.fflush(nil); C._exit(if good { 0 } else { 1 })
			}
			status = 0
			if C.waitpid(storage_pid, &status, 0) != storage_pid { fatal(21) }
			if status != 0 { storage_good = false }
		}
		C.printf(c'LINUX SELECTBAD SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 && storage_good { C.printf(c'LINUX SELECTBAD: PASS\n') } else { C.printf(c'LINUX SELECTBAD: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
