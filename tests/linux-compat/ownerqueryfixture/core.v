// SPDX-License-Identifier: GPL-2.0-or-later
module ownerqueryfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct C.stat { st_dev u64 st_ino u64 st_mode u32 st_uid u32 st_gid u32 st_nlink u64 st_size i64 }
struct Counts { mut: calls [5]u64 failures [5]u64 }
struct State { mut: metadata C.stat flags i32 status i32 cursor i64 signal i32 }
struct Worker { mut: tid i32 release i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
fn C.dup(i32) i32
fn C.lseek(i32, i64, i32) i64
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.unlink(&char) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, u64, ...) i32
fn C.getpid() i32
fn C.getpgrp() i32
fn C.setpgid(i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.unshare(i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn record(counts &Counts, kind i32, good bool, ordinary bool) {
	unsafe { mut tally := &Counts(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX OWNERQUERY DETAIL: ordinary=%d kind=%d call=%lu\n', i32(ordinary), kind, tally.calls[kind]); C.fflush(nil) } } }
}
fn same(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode && left.st_uid == right.st_uid && left.st_gid == right.st_gid && left.st_nlink == right.st_nlink && left.st_size == right.st_size }
fn capture(fd i32, target &State) bool {
	unsafe { mut state := &State(target); state.flags = C.fcntl(fd, C.F_GETFD); state.status = C.fcntl(fd, C.F_GETFL); state.cursor = C.lseek(fd, 0, C.SEEK_CUR); state.signal = C.fcntl(fd, C.F_GETSIG); return C.fstat(fd, &state.metadata) == 0 && state.flags >= 0 && state.status >= 0 }
}
fn stable(fd i32, before &State) bool {
	unsafe { after := &C.stat(C.alloca(usize(sizeof(C.stat)))); return C.fstat(fd, after) == 0 && same(&before.metadata, after) && C.fcntl(fd, C.F_GETFD) == before.flags && C.fcntl(fd, C.F_GETFL) == before.status && C.fcntl(fd, C.F_GETSIG) == before.signal && C.lseek(fd, 0, C.SEEK_CUR) == before.cursor }
}
fn pending(fds &i32) bool {
	unsafe { bytes := &i32(C.alloca(usize(sizeof(i32)))); *bytes = -1; if C.ioctl(fds[3], u64(C.FIONREAD), bytes) != 0 || *bytes != 2 { return false }; *bytes = -1; return C.ioctl(fds[6], u64(C.FIONREAD), bytes) == 0 && *bytes == 2 }
}
fn setting(fd i32, kind i32, target i32, refused bool) bool {
	unsafe { input := &i32(C.alloca(usize(2 * sizeof(i32)))); input[0] = kind; input[1] = target; slot := C.__errno_location(); *slot = 0; result := C.fcntl(fd, C.F_SETOWN_EX, input); code := *slot; return result == if refused { -1 } else { 0 } && code == if refused { i32(C.ESRCH) } else { i32(0) } && input[0] == kind && input[1] == target }
}
fn getter(fd i32, kind i32, wanted i32, form i32) bool {
	unsafe {
		output := &i32(C.alloca(usize(2 * sizeof(i32)))); output[0] = -9; output[1] = -9; slot := C.__errno_location(); *slot = 0; mut result := isize(0)
		if form == 0 { result = isize(C.fcntl(fd, C.F_GETOWN_EX, output)) }
		else if form == 1 { result = C.syscall(C.SYS_fcntl, u64(u32(fd)), u64(C.F_GETOWN_EX), u64(voidptr(output))) }
		else if form == 2 { result = C.syscall(C.SYS_fcntl, u64(u32(fd)) | 0xffffffff00000000, u64(C.F_GETOWN_EX) | 0x8000000000000000, u64(voidptr(output))) }
		else if form == 3 { result = C.syscall(C.SYS_fcntl, u64(u32(fd)) | 0x100000000, u64(C.F_GETOWN) | 0x200000000, u64(-1)) }
		else { result = isize(C.fcntl(fd, C.F_GETOWN)) }
		code := *slot
		if form < 3 { return result == 0 && code == 0 && output[0] == kind && output[1] == wanted }
		value := if kind == C.F_OWNER_PGRP { -isize(wanted) } else { isize(wanted) }
		// Raw libc syscall decoding treats small negative group numbers as errno.
		if form == 3 && value < 0 && value >= -4095 { return result == -1 && code == i32(-value) }
		return result == value && code == 0
	}
}
fn inspect(counts &Counts, category i32, ordinary bool, fds &i32, states &State, class i32, kind i32, wanted i32, setup bool) {
	unsafe { for alias in 0 .. 3 { index := class * 3 + i32(alias); for form in 0 .. 5 { record(counts, category, setup && getter(fds[index], kind, wanted, i32(form)) && stable(fds[index], &states[index]) && pending(fds), ordinary) } } }
}
fn worker(argument voidptr) voidptr {
	unsafe { mut state := &Worker(argument); C.__atomic_store_n(&state.tid, i32(C.syscall(C.SYS_gettid)), 3); for C.__atomic_load_n(&state.release, 2) == 0 { C.sched_yield() } }; return unsafe { nil }
}
fn task_snapshot(tid i32) (bool, bool) {
	unsafe {
		name := &char(C.alloca(64)); length := C.snprintf(name, 64, c'%d', tid)
		if length <= 0 || length >= 64 { return false, false }
		data := &u8(C.alloca(4096)); fd := C.open(c'/proc/self/task', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		if fd < 0 { return false, false }; mut valid := true; mut ended := false; mut found := false
		for _ in 0 .. 32 {
			n := C.syscall(C.SYS_getdents64, fd, data, usize(4096))
			if n == 0 { ended = true; break }; if n < 0 || n > 4096 { valid = false; break }; mut position := 0
			for position < int(n) {
				if int(n) - position < 20 { valid = false; break }
				span := int(data[position + 16]) | (int(data[position + 17]) << 8)
				if span < 20 || span > int(n) - position { valid = false; break }
				mut terminated := false; for index in position + 19 .. position + span { if data[index] == 0 { terminated = true; break } }
				if !terminated { valid = false; break }
				if C.strcmp(&char(data + position + 19), name) == 0 { found = true }; position += span
			}
			if !valid { break }
		}
		closed := C.close(fd) == 0; return valid && ended && closed, found
	}
}
fn task_entry(tid i32, removed bool) bool {
	for attempt in 0 .. 1000 {
		valid, found := task_snapshot(tid); if !valid { return false }; if found != removed { return true }
		if !removed || (attempt < 999 && C.usleep(1000) != 0) { return false }
	}
	return false
}
fn launch_thread(token &C.pthread_t, state &Worker) bool {
	unsafe { mut value := &Worker(state); *value = Worker{}; if C.pthread_create(token, nil, worker, value) != 0 { return false }; for C.__atomic_load_n(&value.tid, 2) == 0 { C.sched_yield() }; if value.tid == C.getpid() || !task_entry(value.tid, false) { C._exit(1) }; return true }
}
fn finish_thread(token C.pthread_t, state &Worker) bool {
	// Linux clears the join futex before detaching its PID entry. Establish
	// removal through fresh procfs listings before zero/ESRCH owner checks.
	unsafe { mut value := &Worker(state); C.__atomic_store_n(&value.release, 1, 3); if C.pthread_join(token, nil) != 0 { C._exit(1) }; return task_entry(value.tid, true) }
}
fn spawn_child(group i32, door &i32, ready &i32) i32 {
	unsafe {
		if C.pipe2(door, C.O_CLOEXEC) != 0 || C.pipe2(ready, C.O_CLOEXEC) != 0 { return -1 }; child := C.fork(); if child < 0 { return -1 }
		if child == 0 { C.close(door[1]); C.close(ready[0]); mut byte := char(0); good := (group == 0 || C.setpgid(0, if group < 0 { 0 } else { group }) == 0) && C.write(ready[1], c'R', 1) == 1 && C.read(door[0], &byte, 1) == 1 && byte == char(`Q`); C.close(door[0]); C.close(ready[1]); C._exit(if good { 0 } else { 1 }) }
		C.close(door[0]); C.close(ready[1]); mut byte := char(0); good := C.read(ready[0], &byte, 1) == 1 && byte == char(`R`); C.close(ready[0]); if !good { C.close(door[1]); C.kill(child, C.SIGKILL); mut status := i32(0); C.waitpid(child, &status, 0); return -1 }; return child
	}
}
fn finish_child(child i32, door &i32) bool {
	unsafe { sent := C.write(door[1], c'Q', 1) == 1; C.close(door[1]); mut status := i32(-1); return C.waitpid(child, &status, 0) == child && status == 0 && sent }
}
fn phases(counts &Counts, ordinary bool, fds &i32, states &State) bool {
	unsafe {
		door := &i32(C.alloca(usize(2 * sizeof(i32)))); ready := &i32(C.alloca(usize(2 * sizeof(i32)))); child := spawn_child(0, door, ready); if child < 0 { return false }
		token := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t)))); state := &Worker(C.alloca(usize(sizeof(Worker)))); if !launch_thread(token, state) { return false }
		for target in [C.getpid(), state.tid, child]! { for kind in 0 .. 3 { for class in 0 .. 3 {
			wanted := if (target == state.tid && kind != 0) || (target == child && kind == 2) { i32(0) } else { target }; accepted := setting(fds[class * 3], i32(kind), target, false); inspect(counts, 0, ordinary, fds, states, i32(class), i32(kind), wanted, accepted)
		} } }
		for class in 0 .. 3 { accepted := setting(fds[class * 3], i32(class), child, false); inspect(counts, 1, ordinary, fds, states, i32(class), i32(class), if class == 2 { 0 } else { child }, accepted) }
		// A running worker borrows this frame until its successful join.
		if !finish_child(child, door) { C._exit(1) }; for class in 0 .. 3 { inspect(counts, 1, ordinary, fds, states, i32(class), i32(class), 0, true); refused := setting(fds[class * 3], i32(class), child, true); inspect(counts, 1, ordinary, fds, states, i32(class), i32(class), 0, refused) }
		for class in 0 .. 3 { accepted := setting(fds[class * 3], i32(class), state.tid, false); inspect(counts, 2, ordinary, fds, states, i32(class), i32(class), if class == 0 { state.tid } else { 0 }, accepted) }
		tid := state.tid; if !finish_thread(*token, state) { return false }; for class in 0 .. 3 { inspect(counts, 2, ordinary, fds, states, i32(class), i32(class), 0, true); refused := setting(fds[class * 3], i32(class), tid, true); inspect(counts, 2, ordinary, fds, states, i32(class), i32(class), 0, refused) }
		leader := spawn_child(-1, door, ready); if leader < 0 { return false }; member_door := &i32(C.alloca(usize(2 * sizeof(i32)))); member := spawn_child(leader, member_door, ready); if member < 0 { return false }
		for class in 0 .. 3 { accepted := setting(fds[class * 3], i32(class), leader, false); inspect(counts, 3, ordinary, fds, states, i32(class), i32(class), leader, accepted) }
		if !finish_child(leader, door) { return false }; for class in 0 .. 3 { wanted := if class == 2 { leader } else { 0 }; inspect(counts, 3, ordinary, fds, states, i32(class), i32(class), wanted, true); accepted := setting(fds[class * 3], i32(class), leader, false); inspect(counts, 3, ordinary, fds, states, i32(class), i32(class), wanted, accepted) }
		if !finish_child(member, member_door) { return false }; for class in 0 .. 3 { inspect(counts, 3, ordinary, fds, states, i32(class), i32(class), 0, true); refused := setting(fds[class * 3], i32(class), leader, true); inspect(counts, 3, ordinary, fds, states, i32(class), i32(class), 0, refused) }
		return true
	}
}
fn namespace_sequence(counts &Counts, ordinary bool, fds &i32, states &State) bool {
	unsafe {
		up := &i32(C.alloca(usize(2 * sizeof(i32)))); down := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(up, C.O_CLOEXEC) != 0 || C.pipe2(down, C.O_CLOEXEC) != 0 || C.setpgid(0, 0) != 0 || C.unshare(C.CLONE_NEWPID) != 0 { return false }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		outer := C.getpid(); for class in 0 .. 3 { if !setting(fds[class * 3], i32(class), outer, false) { return false } }
		child := C.fork(); if child < 0 { return false }; local := &Counts(C.alloca(usize(sizeof(Counts)))); *local = Counts{}
		if child == 0 {
			C.close(up[0]); C.close(down[1]); if C.getpid() != 1 || C.setpgid(0, 0) != 0 { C._exit(1) }; mut byte := char(0)
			for class in 0 .. 3 { inspect(local, 4, ordinary, fds, states, i32(class), i32(class), 0, true); accepted := setting(fds[class * 3], i32(class), 1, false); inspect(local, 4, ordinary, fds, states, i32(class), i32(class), 1, accepted) }
			if C.write(up[1], c'R', 1) != 1 || C.read(down[0], &byte, 1) != 1 || byte != char(`Q`) { C._exit(1) }
			for class in 0 .. 3 { inspect(local, 4, ordinary, fds, states, i32(class), i32(class), 0, true); accepted := setting(fds[class * 3], i32(class), 0, false); inspect(local, 4, ordinary, fds, states, i32(class), i32(class), 0, accepted) }
			if C.write(up[1], local, usize(sizeof(Counts))) != isize(sizeof(Counts)) { C._exit(1) }; C.close(up[1]); C.close(down[0]); C._exit(0)
		}
		C.close(up[1]); C.close(down[0]); mut byte := char(0); if C.read(up[0], &byte, 1) != 1 || byte != char(`R`) { return false }
		for class in 0 .. 3 { inspect(counts, 4, ordinary, fds, states, i32(class), i32(class), child, true); accepted := setting(fds[class * 3], i32(class), outer, false); inspect(counts, 4, ordinary, fds, states, i32(class), i32(class), outer, accepted) }
		if C.write(down[1], c'Q', 1) != 1 || C.read(up[0], local, usize(sizeof(Counts))) != isize(sizeof(Counts)) { return false }
		for class in 0 .. 3 { inspect(counts, 4, ordinary, fds, states, i32(class), i32(class), 0, true) }
		mut tally := &Counts(counts); tally.calls[4] += local.calls[4]; tally.failures[4] += local.failures[4]; C.close(up[0]); C.close(down[1]); mut status := i32(-1); return C.waitpid(child, &status, 0) == child && status == 0
	}
}
fn namespaces(counts &Counts, ordinary bool, fds &i32, states &State) bool {
	unsafe { pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_CLOEXEC) != 0 { return false }; child := C.fork(); if child < 0 { return false }
		if child == 0 { C.close(pipe[0]); local := &Counts(C.alloca(usize(sizeof(Counts)))); *local = Counts{}; good := namespace_sequence(local, ordinary, fds, states); sent := C.write(pipe[1], local, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if good && sent { 0 } else { 1 }) }
		C.close(pipe[1]); local := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(pipe[0], local, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[0]); mut status := i32(-1); good := C.waitpid(child, &status, 0) == child && status == 0; if received { mut tally := &Counts(counts); tally.calls[4] = local.calls[4]; tally.failures[4] = local.failures[4] }; return received && good
	}
}
fn cycle(fds &i32, states &State, tid i32) bool {
	unsafe { for class in 0 .. 3 { alias := C.dup(fds[class * 3]); if alias < 0 { return false }; mut good := true
		for kind in 0 .. 3 { for target in [C.getpid(), tid]! { wanted := if target == tid && kind != 0 { i32(0) } else { target }; if !setting(alias, i32(kind), target, false) || !getter(fds[class * 3], i32(kind), wanted, 2) || !setting(alias, i32(kind), 65536, true) || !getter(fds[class * 3], i32(kind), wanted, 3) { good = false } } }
		reset := setting(alias, C.F_OWNER_PID, C.getpid(), false); closed := C.close(alias) == 0; if !reset || !closed || !good || !stable(fds[class * 3], &states[class * 3]) { return false }
	}; return pending(fds) }
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
fn storage(fds &i32, states &State, tid i32, ordinary bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(fds, states, tid) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(fds, states, tid) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for i in 0 .. int(before.rows) { if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }; C.printf(c'LINUX OWNERQUERY SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i]) }
		C.printf(c'LINUX OWNERQUERY STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}

fn qualify(fds &i32, ordinary bool, reference_run bool) bool {
	unsafe { C.alarm(360); if C.setpgid(0, 0) != 0 { return false }; states := &State(C.alloca(usize(9 * sizeof(State)))); for index in 0 .. 9 { if !capture(fds[index], &states[index]) { return false } }; counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
		mut good := namespaces(counts, ordinary, fds, states)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		if !phases(counts, ordinary, fds, states) { good = false }; for kind in 0 .. 5 { C.printf(c'LINUX OWNERQUERY CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil)
		if good && !reference_run { token := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t)))); worker_state := &Worker(C.alloca(usize(sizeof(Worker)))); if !launch_thread(token, worker_state) { return false }; if !storage(fds, states, worker_state.tid, ordinary) { good = false }; if !finish_thread(*token, worker_state) { good = false } }; C.alarm(0); return good
	}
}


@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; fds := &i32(C.alloca(usize(11 * sizeof(i32)))); for index in 0 .. 11 { fds[index] = -1 }
		fds[0] = C.open(c'/tmp/linux-ownerquery-file', C.O_CREAT | C.O_EXCL | C.O_RDWR | C.O_CLOEXEC, i32(0o644)); pair := &i32(C.alloca(usize(2 * sizeof(i32)))); pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if fds[0] < 0 || C.write(fds[0], c'ownerquery-data!', 16) != 16 || C.lseek(fds[0], 3, C.SEEK_SET) != 3 || C.pipe2(pipe, C.O_NONBLOCK | C.O_CLOEXEC) != 0 || C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK | C.SOCK_CLOEXEC, 0, pair) != 0 { return 1 }
		fds[3] = pipe[0]; fds[6] = pair[0]; fds[9] = pipe[1]; fds[10] = pair[1]; if C.write(fds[9], c'AB', 2) != 2 || C.write(fds[10], c'AB', 2) != 2 { return 1 }
		for class in 0 .. 3 { if C.fcntl(fds[class * 3], C.F_SETSIG, i32(class + 10)) != 0 { return 1 }; fds[class * 3 + 1] = C.dup(fds[class * 3]); fds[class * 3 + 2] = C.fcntl(fds[class * 3], C.F_DUPFD_CLOEXEC, 40); if fds[class * 3 + 1] < 0 || fds[class * 3 + 2] < 0 { return 1 } }
		mut good := true; for ordinary in [true, false]! { C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(fds, ordinary, reference_run) { 0 } else { 1 }) }; mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { good = false } }
		mut data := [16]char{}; if C.pread(fds[0], &data[0], 16, 0) != 16 || C.memcmp(&data[0], c'ownerquery-data!', 16) != 0 || !pending(fds) || C.read(fds[3], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) || C.read(fds[6], &data[0], 2) != 2 || data[0] != char(`A`) || data[1] != char(`B`) { good = false }
		for index in 0 .. 11 { flags := C.fcntl(fds[index], C.F_GETFD); if C.close(fds[index]) != 0 || flags != if index < 9 && index % 3 == 1 { i32(0) } else { i32(C.FD_CLOEXEC) } { good = false } }; if C.unlink(c'/tmp/linux-ownerquery-file') != 0 { good = false }
		if !good { C.puts(c'LINUX OWNERQUERY FAIL: task kinds, lifetime, namespaces, aliases or storage'); C.fflush(nil); return 1 }; C.puts(if reference_run { c'LINUX OWNERQUERY REFERENCE: PASS' } else { c'LINUX OWNERQUERY: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
}
