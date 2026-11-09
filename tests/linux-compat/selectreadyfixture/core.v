// SPDX-License-Identifier: GPL-2.0-or-later
module selectreadyfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
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
struct GuardSet { mut: before u64 words [16]u64 after u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows int large u64 tainted u64 }
struct Targets { mut: fds [5]i32 count int }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
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
fn C.unlink(&char) i32
fn C.chmod(&char, u32) i32
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
	C.printf(c'LINUX SELECTREADY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, api int, kind int, layout int, sets int, timed int, stage int) {
	t.checks++
	if !good {
		t.failures++
		C.printf(c'LINUX SELECTREADY MISMATCH: uid=%u api=%d kind=%d layout=%d sets=%d timed=%d stage=%d\n', C.getuid(), api, kind, layout, sets, timed, stage)
	}
}

fn create_file(index int) i32 {
	mut path := [96]char{}
	if C.snprintf(&path[0], sizeof(path), c'/tmp/selectready-%ld-%d', C.syscall(isize(C.SYS_getpid)), index) <= 0 { fatal(1) }
	fd := C.open(&path[0], C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
	if fd < 0 || C.unlink(&path[0]) != 0 { fatal(2) }
	value := u8(0x51)
	if C.write(fd, &value, 1) != 1 { fatal(3) }
	return fd
}
fn targets(kind int) Targets {
	unsafe {
	mut t := Targets{}
	if kind == 0 {
		t.fds[0] = create_file(0)
		t.fds[1] = create_file(1)
		t.count = 2
	} else {
		type_ := if kind == 1 { C.SOCK_STREAM } else if kind == 2 { C.SOCK_DGRAM } else { C.SOCK_SEQPACKET }
		if C.socketpair(C.AF_UNIX, type_, 0, &t.fds[0]) != 0 || C.socketpair(C.AF_UNIX, type_, 0, &t.fds[2]) != 0 { fatal(4) }
		t.count = 4
		value := u8(0x51)
		if C.write(t.fds[1], &value, 1) != 1 || C.write(t.fds[3], &value, 1) != 1 { fatal(5) }
	}
	// Place an alias beyond the first bitmap word, exercising word-sized
	// imports without relying on Linux's unrelated high-nfds truncation.
	t.fds[t.count] = C.fcntl(t.fds[0], C.F_DUPFD_CLOEXEC, 70)
	if t.fds[t.count] < 70 || t.fds[t.count] >= 1024 { fatal(6) }
	t.count++
	return t
	}
}
fn close_targets(t &Targets) { unsafe { for i in 0 .. t.count { C.close(t.fds[i]) } } }
fn selected(t &Targets, kind int, layout int, output &i32) int {
	unsafe {
		output[0] = if layout == 1 { t.fds[t.count - 1] } else { t.fds[0] }
		if layout >= 2 { output[1] = t.fds[t.count - 1] }
		if layout == 3 { output[2] = t.fds[if kind == 0 { 1 } else { 2 }] }
		return if layout == 3 { 3 } else if layout == 2 { 2 } else { 1 }
	}
}
fn call(api int, nfds int, reads &GuardSet, writes &GuardSet, excepts &GuardSet, sets int, timed int) isize {
	unsafe {
		r := if sets & 1 == 0 { &C.fd_set(nil) } else { &C.fd_set(&reads.words[0]) }
		w := if sets & 2 == 0 { &C.fd_set(nil) } else { &C.fd_set(&writes.words[0]) }
		e := if sets & 4 == 0 { &C.fd_set(nil) } else { &C.fd_set(&excepts.words[0]) }
		mut ts := C.timespec{tv_nsec: if timed == 0 { 0 } else { 1_000_000 }}
		mut tv := C.timeval{tv_usec: if timed == 0 { 0 } else { 1000 }}
		errno_pointer := C.__errno_location()
		*errno_pointer = 0
		match api {
			0 { return C.syscall(isize(C.SYS_pselect6), nfds, r, w, e, &ts, nil) }
			1 { return C.pselect(nfds, r, w, e, &ts, nil) }
			2 { return C.select(nfds, r, w, e, &tv) }
			else {
				$if amd64 { return C.syscall(isize(C.SYS_select), nfds, r, w, e, &tv) }
				$else { fatal(7); return -1 }
			}
		}
	}
}
fn make_set(fds &i32, count int, nfds int) GuardSet {
	unsafe {
		mut s := GuardSet{before: 0xabcddcba12344321, after: 0x87654321fedcba98}
		for i in ((nfds + 63) / 64) .. 16 { s.words[i] = 0x1122334455667788 }
		for i in 0 .. count { s.words[fds[i] / 64] |= u64(1) << u64(fds[i] % 64) }
		return s
	}
}
fn output_good(actual &GuardSet, input &GuardSet, fds &i32, count int, nfds int, passed bool, ready bool) bool {
	unsafe {
		if actual.before != input.before || actual.after != input.after { return false }
		for word in 0 .. 16 {
			mut expected := u64(0)
			if !passed || word >= (nfds + 63) / 64 { expected = input.words[word] }
			else if ready { for i in 0 .. count { if fds[i] / 64 == word { expected |= u64(1) << u64(fds[i] % 64) } } }
			if actual.words[word] != expected { return false }
		}
		return true
	}
}
fn probe(t &Targets, api int, kind int, layout int, sets int, timed int, verbose bool) Totals {
	unsafe {
		fds := &i32(C.alloca(usize(3 * sizeof(i32))))
		count := selected(t, kind, layout, fds)
		mut nfds := 0
		for i in 0 .. count { if int(fds[i]) + 1 > nfds { nfds = int(fds[i]) + 1 } }
		input := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
		*input = make_set(fds, count, nfds)
		reads := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
		writes := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
		excepts := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
		*reads = *input; *writes = *input; *excepts = *input
		ret := call(api, nfds, reads, writes, excepts, sets, timed)
		code := *C.__errno_location()
		expected := count * (if sets & 1 != 0 { 1 } else { 0 }) + count * (if sets & 2 != 0 { 1 } else { 0 })
		mut total := Totals{}
		check(mut total, ret == expected, api, kind, layout, sets, timed, 1)
		check(mut total, code == 0, api, kind, layout, sets, timed, 2)
		check(mut total, output_good(reads, input, fds, count, nfds, sets & 1 != 0, true), api, kind, layout, sets, timed, 3)
		check(mut total, output_good(writes, input, fds, count, nfds, sets & 2 != 0, true), api, kind, layout, sets, timed, 4)
		check(mut total, output_good(excepts, input, fds, count, nfds, sets & 4 != 0, false), api, kind, layout, sets, timed, 5)
		if verbose && total.failures != 0 { C.printf(c'LINUX SELECTREADY DETAIL: actual=%ld/%d expected=%d/0\n', ret, code, expected) }
		return total
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
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
		mut wrong := 0
		for api in 0 .. apis {
			fds := &i32(C.alloca(usize(3 * sizeof(i32))))
			count := selected(t, 1, 3, fds)
			nfds := int(t.fds[t.count - 1]) + 1
			input := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
			*input = make_set(fds, count, nfds)
			reads := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
			writes := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
			excepts := &GuardSet(C.alloca(usize(sizeof(GuardSet))))
			*reads = *input; *writes = *input; *excepts = *input
			ret := call(api, nfds, reads, writes, excepts, 7, 0)
			// The original count bug is measured separately; permit its exact
			// result here so retained storage has comparable baseline inputs.
			if ret != 3 && ret != 6 { fatal(8) }
			if *C.__errno_location() != 0 || !output_good(reads, input, fds, count, nfds, true, true) || !output_good(writes, input, fds, count, nfds, true, true) || !output_good(excepts, input, fds, count, nfds, true, false) { fatal(9) }
			if ret == 3 { wrong++ }
		}
		return wrong
	}
}
fn storage(apis int) bool {
	unsafe {
		C.alarm(90)
		t := targets(1)
		defer { close_targets(&t) }
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(10) }
		defer { C.close(fd) }
		for _ in 0 .. 64 { storage_cycle(&t, apis) }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(fd, before) { fatal(11) }
		mut wrong := 0
		for _ in 0 .. 200 { wrong += storage_cycle(&t, apis) }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(12) }
		mut good := before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] { good = false }
			C.printf(c'LINUX SELECTREADY SLAB: uid=%u size=%lu live=%lu/%lu cycles=200\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX SELECTREADY STORAGE: uid=%u cycles=200 wrong_counts=%d big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), wrong, before.large, after.large, before.tainted, after.tainted, if good { &char(c'PASS') } else { &char(c'FAIL') })
		return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		if C.chmod(c'/tmp', 0o1777) != 0 { fatal(22) }
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
				C.close(pipefds[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(15) }
				mut sum := Totals{}
				for kind in 0 .. 4 {
					t := targets(kind)
					for api in 0 .. apis {
						mut group := Totals{}
						for layout in 0 .. 4 { for sets in 1 .. 8 { for timed in 0 .. 2 {
							result := probe(&t, api, kind, layout, sets, timed, true)
							group.checks += result.checks; group.failures += result.failures
						} } }
						C.printf(c'LINUX SELECTREADY CASE: uid=%u gid=%u api=%d kind=%d layouts=4 sets=7 timeouts=2 checks=%d failures=%d\n', C.getuid(), C.getgid(), api, kind, group.checks, group.failures)
						sum.checks += group.checks; sum.failures += group.failures
					}
					close_targets(&t)
				}
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
				if reference { C.printf(c'LINUX SELECTREADY STORAGE: uid=%u SKIP reference\n', C.getuid()); C.fflush(nil); C._exit(0) }
				good := storage(apis)
				C.fflush(nil); C._exit(if good { 0 } else { 1 })
			}
			status = 0
			if C.waitpid(storage_pid, &status, 0) != storage_pid { fatal(21) }
			if status != 0 { storage_good = false }
		}
		C.printf(c'LINUX SELECTREADY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 && storage_good { C.printf(c'LINUX SELECTREADY: PASS\n') } else { C.printf(c'LINUX SELECTREADY: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
