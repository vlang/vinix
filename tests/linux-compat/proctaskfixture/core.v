// SPDX-License-Identifier: GPL-2.0-or-later
module proctaskfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.siginfo_t {}
struct C.stat { st_dev u64 st_ino u64 st_mode u32 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Worker { mut: tid i32 release i32 }
struct Bank { mut: fds [18]i32 metadata [6]C.stat held [18]i32 held_metadata [6]C.stat }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.openat(i32, &char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
fn C.dup(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pipe2(&i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.waitid(i32, u32, &C.siginfo_t, i32) i32
fn C.getpid() i32
fn C.unshare(i32) i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.usleep(u32) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn root_path(mount i32, ordinary bool, namespace bool) &char {
	if mount == 0 && !namespace { return c'/proc' }
	if namespace {
		if ordinary { return match mount { 0 { c'/tmp/proctask-nu0' } 1 { c'/tmp/proctask-nu1' } else { c'/tmp/proctask-nu2' } } }
		return match mount { 0 { c'/tmp/proctask-nr0' } 1 { c'/tmp/proctask-nr1' } else { c'/tmp/proctask-nr2' } }
	}
	if ordinary { return if mount == 1 { c'/tmp/proctask-u1' } else { c'/tmp/proctask-u2' } }
	return if mount == 1 { c'/tmp/proctask-r1' } else { c'/tmp/proctask-r2' }
}
fn same(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode }
fn leaf_suffix(leaf i32) &char {
	if leaf == 0 { return c'/stat' }
	if leaf == 1 { return c'/status' }
	return c''
}
fn record(counts &Counts, kind i32, good bool, ordinary bool, namespace bool) {
	unsafe { mut tally := &Counts(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX PROCTASK DETAIL: ordinary=%d namespace=%d kind=%d call=%lu\n', i32(ordinary), i32(namespace), kind, tally.calls[kind]); C.fflush(nil) } } }
}
fn fatal() { C.puts(c'LINUX PROCTASK FAIL: setup, worker lifetime or independent signal-zero boundary'); C.fflush(nil); C._exit(1) }
fn worker(argument voidptr) voidptr {
	unsafe { mut state := &Worker(argument); C.__atomic_store_n(&state.tid, i32(C.syscall(C.SYS_gettid)), 3); for C.__atomic_load_n(&state.release, 2) == 0 { C.sched_yield() } }; return unsafe { nil }
}
fn signal_zero(tid i32, removed bool) bool {
	unsafe { slot := C.__errno_location(); for attempt in 0 .. 1000 {
		*slot = 0; result := C.syscall(C.SYS_tgkill, C.getpid(), tid, 0); code := *slot
		if !removed { return result == 0 && code == 0 }; if result == -1 && code == C.ESRCH { return true }
		if result != 0 || code != 0 || (attempt < 999 && C.usleep(1000) != 0) { return false }
	}; return false }
}
fn launch(token &C.pthread_t, state &Worker) {
	unsafe { mut value := &Worker(state); *value = Worker{}; if C.pthread_create(token, nil, worker, value) != 0 { fatal() }; for C.__atomic_load_n(&value.tid, 2) == 0 { C.sched_yield() }; if value.tid <= 0 || value.tid == C.getpid() || !signal_zero(value.tid, false) { fatal() } }
}
fn finish(token C.pthread_t, state &Worker) {
	unsafe { mut value := &Worker(state); C.__atomic_store_n(&value.release, 1, 3); if C.pthread_join(token, nil) != 0 || !signal_zero(value.tid, true) { fatal() } }
}
fn prepare(bank &Bank, ordinary bool, namespace bool) bool {
	unsafe { mut handles := &Bank(bank); for i in 0 .. 18 { handles.fds[i] = -1; handles.held[i] = -1 }
		path := &char(C.alloca(128)); for mount in 0 .. 3 {
			root := root_path(i32(mount), ordinary, namespace)
			if (mount != 0 || namespace) && (C.mkdir(root, 0o755) != 0 || C.mount(c'proc', root, c'proc', 0, nil) != 0) { return false }
			for base in 0 .. 2 {
				length := if base == 0 { C.snprintf(path, 128, c'%s/self/task', root) } else { C.snprintf(path, 128, c'%s/%d/task', root, C.getpid()) }; if length <= 0 || length >= 128 { return false }
				index := (mount * 2 + base) * 3; handles.fds[index] = C.open(path, C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC)
				if handles.fds[index] < 0 || C.fstat(handles.fds[index], &handles.metadata[mount * 2 + base]) != 0 { return false }
				handles.fds[index + 1] = C.dup(handles.fds[index]); handles.fds[index + 2] = C.fcntl(handles.fds[index], C.F_DUPFD_CLOEXEC, 40)
				if handles.fds[index + 1] < 0 || handles.fds[index + 2] < 0 { return false }
			}
		}; return true
	}
}
fn query(bank &Bank, pid i32, tid i32, mount i32, base i32, leaf i32, form i32, present bool, identity &C.stat, ordinary bool, namespace bool) bool {
	unsafe {
		name := &char(C.alloca(64)); path := &char(C.alloca(192)); suffix := leaf_suffix(leaf)
		length := C.snprintf(name, 64, c'%d%s', tid, suffix); if length <= 0 || length >= 64 { return false }
		full := if base == 0 { C.snprintf(path, 192, c'%s/self/task/%s', root_path(mount, ordinary, namespace), name) } else { C.snprintf(path, 192, c'%s/%d/task/%s', root_path(mount, ordinary, namespace), pid, name) }
		if full <= 0 || full >= 192 { return false }; flags := C.O_RDONLY | C.O_CLOEXEC | if leaf == 2 { C.O_DIRECTORY } else { 0 }; parent := (mount * 2 + base) * 3
		slot := C.__errno_location(); *slot = 0; fd := if form == 0 { C.open(path, flags) }
			else if form == 1 { i32(C.syscall(C.SYS_openat, u64(u32(C.AT_FDCWD)) | 0xffffffff00000000, path, u64(u32(flags)) | 0x8000000000000000, 0)) }
			else if form == 2 { C.openat(bank.fds[parent], name, flags) }
			else if form == 3 { i32(C.syscall(C.SYS_openat, u64(u32(bank.fds[parent + 1])) | 0xffffffff00000000, name, u64(u32(flags)) | 0x8000000000000000, 0)) }
			else { C.openat(bank.fds[parent + 2], name, flags) }; code := *slot
		if !present { if fd >= 0 { C.close(fd) }; return fd == -1 && code == C.ENOENT }
		if fd < 0 { return false }; actual := &C.stat(C.alloca(usize(sizeof(C.stat)))); inspected := C.fstat(fd, actual) == 0 && C.fcntl(fd, C.F_GETFD) == C.FD_CLOEXEC
		mut good := code == 0 && inspected; if inspected { if form == 0 { mut original := &C.stat(identity); *original = *actual } else if !same(identity, actual) { good = false } }
		closed := C.close(fd) == 0; return good && closed
	}
}
fn sweep(counts &Counts, kind i32, bank &Bank, tid i32, present bool, ordinary bool, namespace bool) {
	unsafe { mut identity := &C.stat(C.alloca(usize(sizeof(C.stat)))); for mount in 0 .. 3 { for base in 0 .. 2 { for leaf in 0 .. 3 { *identity = C.stat{}; for form in 0 .. 5 {
		record(counts, kind, query(bank, C.getpid(), tid, i32(mount), i32(base), i32(leaf), i32(form), present, identity, ordinary, namespace), ordinary, namespace)
	} } } } }
}
fn descriptors(counts &Counts, bank &Bank, held bool, ordinary bool, namespace bool) {
	unsafe { value := &C.stat(C.alloca(usize(sizeof(C.stat)))); for index in 0 .. 18 { fd := if held { bank.held[index] } else { bank.fds[index] }; original := if held { &bank.held_metadata[index / 3] } else { &bank.metadata[index / 3] }; good := C.fstat(fd, value) == 0 && same(original, value) && C.fcntl(fd, C.F_GETFD) == if index % 3 == 1 { i32(0) } else { i32(C.FD_CLOEXEC) }; record(counts, 5, good, ordinary, namespace) } }
}
fn hold_worker(bank &Bank, tid i32) {
	unsafe { mut handles := &Bank(bank); name := &char(C.alloca(64)); for mount in 0 .. 3 { for leaf in 0 .. 2 {
		length := C.snprintf(name, 64, c'%d%s', tid, leaf_suffix(if leaf == 0 { 0 } else { 2 })); if length <= 0 || length >= 64 { fatal() }
		index := (mount * 2 + leaf) * 3; handles.held[index] = C.openat(handles.fds[mount * 6], name, C.O_RDONLY | C.O_CLOEXEC | if leaf == 1 { C.O_DIRECTORY } else { 0 })
		if handles.held[index] < 0 || C.fstat(handles.held[index], &handles.held_metadata[mount * 2 + leaf]) != 0 { fatal() }; handles.held[index + 1] = C.dup(handles.held[index]); handles.held[index + 2] = C.fcntl(handles.held[index], C.F_DUPFD_CLOEXEC, 40)
		if handles.held[index + 1] < 0 || handles.held[index + 2] < 0 { fatal() }
	} } }
}
fn child_query(child i32, mount i32, leaf i32, present bool, ordinary bool, namespace bool) bool {
	unsafe { path := &char(C.alloca(192)); length := C.snprintf(path, 192, c'%s/%d/task/%d%s', root_path(mount, ordinary, namespace), child, child, leaf_suffix(leaf))
		if length <= 0 || length >= 192 { return false }; error := C.__errno_location(); *error = 0; fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | if leaf == 2 { C.O_DIRECTORY } else { 0 }); code := *error; closed := fd < 0 || C.close(fd) == 0
		return closed && if present { fd >= 0 && code == 0 } else { fd == -1 && code == C.ENOENT }
	}
}
fn child_paths(counts &Counts, kind i32, child i32, present bool, ordinary bool, namespace bool) {
	for mount in 0 .. 3 { for leaf in 0 .. 3 { record(counts, kind, child_query(child, i32(mount), i32(leaf), present, ordinary, namespace), ordinary, namespace) } }
}

fn qualify(counts &Counts, ordinary bool, namespace bool, reference_run bool) bool {
	unsafe {
		C.alarm(360); bank := &Bank(C.alloca(usize(sizeof(Bank)))); if !prepare(bank, ordinary, namespace) { fatal() }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal() }
		gate := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(gate, C.O_CLOEXEC) != 0 { fatal() }; child := C.fork(); if child < 0 { fatal() }
		if child == 0 { C.close(gate[1]); mut byte := char(0); good := C.read(gate[0], &byte, 1) == 1 && byte == char(`Q`); C.close(gate[0]); C._exit(if good { 0 } else { 1 }) }; C.close(gate[0])
		first := &Worker(C.alloca(usize(sizeof(Worker)))); second := &Worker(C.alloca(usize(sizeof(Worker)))); first_token := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t)))); second_token := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t)))); launch(first_token, first); launch(second_token, second)
		for tid in [C.getpid(), first.tid, second.tid]! { sweep(counts, 0, bank, tid, true, ordinary, namespace) }; hold_worker(bank, first.tid); descriptors(counts, bank, false, ordinary, namespace)
		finish(*first_token, first); for _ in 0 .. 2 { sweep(counts, 1, bank, first.tid, false, ordinary, namespace) }; descriptors(counts, bank, false, ordinary, namespace); descriptors(counts, bank, true, ordinary, namespace)
		for tid in [C.getpid(), second.tid]! { sweep(counts, 2, bank, tid, true, ordinary, namespace) }; sweep(counts, 3, bank, child, false, ordinary, namespace); child_paths(counts, 3, child, true, ordinary, namespace)
		if C.write(gate[1], c'Q', 1) != 1 || C.close(gate[1]) != 0 { fatal() }; info := &C.siginfo_t(C.alloca(usize(sizeof(C.siginfo_t)))); if C.waitid(C.P_PID, u32(child), info, C.WEXITED | C.WNOWAIT) != 0 { fatal() }; child_paths(counts, 4, child, true, ordinary, namespace)
		mut status := i32(-1); if C.waitpid(child, &status, 0) != child || status != 0 { fatal() }; for _ in 0 .. 2 { child_paths(counts, 4, child, false, ordinary, namespace) }
		descriptors(counts, bank, false, ordinary, namespace)
		mut good := true; for kind in 0 .. 6 { if counts.failures[kind] != 0 { good = false } }
		if good && !reference_run { if !storage(bank, first.tid, second.tid, child, ordinary, namespace) { good = false } }
		finish(*second_token, second); descriptors(counts, bank, true, ordinary, namespace)
		// Counts are printed by the cohort after all retained-descriptor checks.
		for index in 0 .. 18 { if C.close(bank.held[index]) != 0 || C.close(bank.fds[index]) != 0 { good = false } }; C.alarm(0)
		for kind in 0 .. 6 { C.printf(c'LINUX PROCTASK CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(namespace), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil); return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for namespace in [false, true]! { for ordinary in [true, false]! {
			C.fflush(nil); pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_CLOEXEC) != 0 { return 1 }; outer := C.fork(); if outer < 0 { return 1 }
			if outer == 0 {
				C.close(pipe[0]); if namespace { if C.unshare(C.CLONE_NEWPID) != 0 { fatal() }; init := C.fork(); if init < 0 { fatal() }; if init > 0 { C.close(pipe[1]); mut status := i32(-1); C._exit(if C.waitpid(init, &status, 0) == init && status == 0 { 0 } else { 1 }) }; if C.getpid() != 1 { fatal() } }
				counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts, ordinary, namespace, reference_run); sent := C.write(pipe[1], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(pipe[0], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[0]); mut status := i32(-1); completed := C.waitpid(outer, &status, 0) == outer && status == 0
			if !received || !completed { good = false }; if received { for kind in 0 .. 6 { C.printf(c'LINUX PROCTASK FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(namespace), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		} }
		if !good { C.puts(c'LINUX PROCTASK FAIL: cached task lookup or retained description'); C.fflush(nil); return 1 }
		C.puts(if reference_run { c'LINUX PROCTASK REFERENCE: PASS' } else { c'LINUX PROCTASK: PASS' }); C.fflush(nil); for { C.pause() }
	}; return 0
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
fn cycle(bank &Bank, retired i32, survivor i32, child i32, ordinary bool, namespace bool) bool {
	unsafe { mut identity := &C.stat(C.alloca(usize(sizeof(C.stat)))); for mount in 0 .. 3 { for base in 0 .. 2 {
		for leaf in 0 .. 3 { *identity = C.stat{}; for form in 0 .. 5 {
			if !query(bank, C.getpid(), retired, i32(mount), i32(base), i32(leaf), i32(form), false, identity, ordinary, namespace)
				|| !query(bank, C.getpid(), survivor, i32(mount), i32(base), i32(leaf), i32(form), true, identity, ordinary, namespace) { return false }
		} }
		alias := C.dup(bank.fds[(mount * 2 + base) * 3]); if alias < 0 { return false }; good := C.fstat(alias, identity) == 0 && same(identity, &bank.metadata[mount * 2 + base]); closed := C.close(alias) == 0; if !good || !closed { return false }
	} }; for mount in 0 .. 3 { for leaf in 0 .. 3 { if !child_query(child, i32(mount), i32(leaf), false, ordinary, namespace) { return false } } }; return true }
}
fn storage(bank &Bank, retired i32, survivor i32, child i32, ordinary bool, namespace bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(bank, retired, survivor, child, ordinary, namespace) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(bank, retired, survivor, child, ordinary, namespace) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX PROCTASK SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), i32(namespace), before.sizes[index], before.live[index], after.live[index]) }
		C.printf(c'LINUX PROCTASK STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), i32(namespace), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
