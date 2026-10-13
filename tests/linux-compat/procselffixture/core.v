// SPDX-License-Identifier: GPL-2.0-or-later
module procselffixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct C.stat { st_mode u32 st_ino u64 st_dev u64 }
struct Handles { mut: dirs [3]i32 links [6]i32 }
struct Worker { bank &Handles ordinary bool slot i32 mut: tid i32 failed bool }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct NamespaceWorker { outer i32 inner i32 outer_pid i32 mut: failed bool }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.openat(i32, &char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.readlink(&char, voidptr, usize) isize
fn C.readlinkat(i32, &char, voidptr, usize) isize
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.chroot(&char) i32
fn C.unshare(i32) i32
fn C.chdir(&char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getpid() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strstr(&char, &char) &char
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.pause() i32

fn root_path(view i32) &char {
	unsafe { return if view == 0 { &char(c'/proc') } else if view == 1 { &char(c'/tmp/linux-procself/alias') } else { &char(c'/tmp/linux-procself/jail/view') } }
}
fn link_name(kind i32) &char { unsafe { return if kind == 0 { &char(c'self') } else { &char(c'thread-self') } } }
fn cleanup(bank &Handles) {
	unsafe { for fd in bank.links { if fd >= 0 { C.close(fd) } }; for fd in bank.dirs { if fd >= 0 { C.close(fd) } } }
}
fn prepare(bank &Handles) bool {
	unsafe {
		mut handles := &Handles(bank)
		for view in 0 .. 3 {
			handles.dirs[view] = C.open(root_path(i32(view)), C.O_PATH | C.O_DIRECTORY)
			if handles.dirs[view] < 0 { return false }
			for kind in 0 .. 2 {
				handles.links[view * 2 + kind] = C.openat(handles.dirs[view], link_name(i32(kind)), C.O_PATH | C.O_NOFOLLOW)
				if handles.links[view * 2 + kind] < 0 { return false }
			}
		}
		return true
	}
}
fn probe(bank &Handles, view i32, kind i32, form i32, size i32, destination i32, verbose bool) bool {
	unsafe {
		pid := C.getpid(); tid := i32(C.syscall(isize(C.SYS_gettid)))
		mut target := [64]char{}; mut path := [128]char{}
		length := if kind == 0 { C.snprintf(&target[0], 64, c'%d', pid) } else { C.snprintf(&target[0], 64, c'%d/task/%d', pid, tid) }
		if length <= 0 || length >= 64 || C.snprintf(&path[0], 128, c'%s/%s', root_path(view), link_name(kind)) >= 128 { return false }
		mut bytes := [64]u8{}; for index in 0 .. 64 { bytes[index] = 0x5a }
		buf := if destination == 0 { voidptr(&bytes[0]) } else if destination == 1 { voidptr(nil) } else { voidptr(usize(1)) }
		e := C.__errno_location(); *e = 0
		actual := if form == 0 { C.syscall(isize(C.SYS_readlinkat), bank.dirs[view], link_name(kind), buf, size) }
			else if form == 1 { C.readlinkat(bank.dirs[view], link_name(kind), buf, usize(size)) }
			else if form == 2 { C.syscall(isize(C.SYS_readlinkat), bank.links[view * 2 + kind], c'', buf, size) }
			else if form == 3 { C.readlinkat(bank.links[view * 2 + kind], c'', buf, usize(size)) }
			else { C.readlink(&path[0], buf, usize(size)) }; code := *e
		copied := if size < length { size } else { length }
		wanted := if destination == 0 { isize(copied) } else { isize(-1) }; error_code := if destination == 0 { 0 } else { C.EFAULT }
		mut valid := actual == wanted && code == error_code
		for index in 0 .. 64 { if bytes[index] != if destination == 0 && index < copied { u8(target[index]) } else { u8(0x5a) } { valid = false } }
		if !valid && verbose { C.printf(c'LINUX PROCSELF DETAIL: pid=%d tid=%d view=%d kind=%d form=%d size=%d dest=%d result=%ld/%d expected=%ld/%d\n', pid, tid, view, kind, form, size, destination, actual, code, wanted, error_code); C.fflush(nil) }
		return valid
	}
}
fn status(dirfd i32, kind i32) bool {
	unsafe {
		pid := C.getpid(); tid := if kind == 0 { pid } else { i32(C.syscall(isize(C.SYS_gettid))) }
		mut named := [64]char{}; mut numeric := [64]char{}
		C.snprintf(&named[0], 64, c'%s/status', link_name(kind))
		if kind == 0 { C.snprintf(&numeric[0], 64, c'%d/status', pid) } else { C.snprintf(&numeric[0], 64, c'%d/task/%d/status', pid, tid) }
		fd := C.openat(dirfd, &named[0], C.O_RDONLY); if fd < 0 { return false }; defer { C.close(fd) }
		explicit_fd := C.openat(dirfd, &numeric[0], C.O_RDONLY); if explicit_fd < 0 { return false }; defer { C.close(explicit_fd) }
		mut left := C.stat{}; mut right := C.stat{}; mut data := [4096]char{}
		if C.fstat(fd, &left) != 0 || C.fstat(explicit_fd, &right) != 0 || left.st_ino != right.st_ino || left.st_dev != right.st_dev || left.st_mode != right.st_mode { return false }
		length := C.read(fd, &data[0], 4095); if length <= 0 || length >= 4096 { return false }; data[int(length)] = 0
		tgid_line := C.strstr(&data[0], c'\nTgid:'); pid_line := C.strstr(&data[0], c'\nPid:'); ns_line := C.strstr(&data[0], c'\nNSpid:')
		mut actual_tgid := i32(-1); mut actual_pid := i32(-1); mut actual_ns := i32(-1); mut extra := i32(-1)
		return tgid_line != nil && pid_line != nil && ns_line != nil
			&& C.sscanf(tgid_line, c'\nTgid: %d', &actual_tgid) == 1 && actual_tgid == pid
			&& C.sscanf(pid_line, c'\nPid: %d', &actual_pid) == 1 && actual_pid == tid
			&& C.sscanf(ns_line, c'\nNSpid: %d %d', &actual_ns, &extra) == 1 && actual_ns == tid
	}
}
fn matrix(bank &Handles, ordinary bool, slot i32) bool {
	unsafe {
		mut cases := i32(0); mut bad := i32(0)
		for view in 0 .. 3 { for kind in 0 .. 2 { for form in 0 .. 5 { for size in [i32(1), 3, 64]! { for destination in 0 .. 3 {
			cases++; if !probe(bank, i32(view), i32(kind), i32(form), size, i32(destination), true) { bad++ }
		} } } } }
		mut controls := true
		for view in 0 .. 3 { for kind in 0 .. 2 { if !status(bank.dirs[view], i32(kind)) { controls = false } } }
		C.printf(c'LINUX PROCSELF OUTCOMES: ordinary=%d slot=%d pid=%d tid=%ld cases=%d failures=%d status=%d\n', i32(ordinary), slot, C.getpid(), C.syscall(isize(C.SYS_gettid)), cases, bad, i32(controls)); C.fflush(nil)
		return bad == 0 && controls
	}
}
fn worker(arg voidptr) voidptr {
	unsafe { mut state := &Worker(arg); state.tid = i32(C.syscall(isize(C.SYS_gettid))); state.failed = !matrix(state.bank, state.ordinary, state.slot); return nil }
}
fn cycle(bank &Handles) bool {
	unsafe {
		for view in 0 .. 3 { for kind in 0 .. 2 { for form in 0 .. 5 { for size in [i32(1), 64]! { for destination in 0 .. 2 {
			if !probe(bank, i32(view), i32(kind), i32(form), size, i32(destination), false) { return false }
		} } } }; for kind in 0 .. 2 { if !status(bank.dirs[view], i32(kind)) { return false } } }
		return true
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); mut data := [4096]char{}
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
fn storage(bank &Handles, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(bank) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(bank) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX PROCSELF SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX PROCSELF STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn chroot_test() bool {
	unsafe {
		child := C.fork(); if child < 0 { return false }
		if child == 0 {
			if C.chroot(c'/tmp/linux-procself/jail') != 0 || C.chdir(c'/') != 0 { C._exit(1) }
			fd := C.open(c'/view', C.O_PATH | C.O_DIRECTORY); if fd < 0 { C._exit(1) }
			missing := C.open(c'/proc', C.O_PATH); if missing >= 0 { C.close(missing); C.close(fd); C._exit(1) }
			valid := status(fd, 0) && status(fd, 1); C.close(fd)
			C.printf(c'LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status %s\n', if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
			C._exit(if valid { 0 } else { 1 })
		}
		mut outcome := i32(-1); return C.waitpid(child, &outcome, 0) == child && outcome == 0
	}
}
fn namespace_identity(fd i32, local bool, outer_pid i32) bool {
	unsafe {
		mut link := [64]char{}; mut outer_tid := i32(-1); mut parsed_pid := i32(-1)
		length := C.readlinkat(fd, c'thread-self', &link[0], 63)
		if length <= 0 || length >= 64 { return false }; link[int(length)] = 0
		if C.sscanf(&link[0], c'%d/task/%d', &parsed_pid, &outer_tid) != 2 { return false }
		local_tid := i32(C.syscall(isize(C.SYS_gettid)))
		if parsed_pid != if local { 1 } else { outer_pid } || (local && outer_tid != local_tid) { return false }
		status_fd := C.openat(fd, c'thread-self/status', C.O_RDONLY); if status_fd < 0 { return false }; defer { C.close(status_fd) }
		mut data := [4096]char{}; n := C.read(status_fd, &data[0], 4095); if n <= 0 || n >= 4096 { return false }; data[int(n)] = 0
		pid_line := C.strstr(&data[0], c'\nPid:'); tgid_line := C.strstr(&data[0], c'\nTgid:'); ns_line := C.strstr(&data[0], c'\nNSpid:')
		if pid_line == nil || tgid_line == nil || ns_line == nil { return false }
		mut pid := i32(-1); mut tgid := i32(-1); mut first := i32(-1); mut second := i32(-1); mut third := i32(-1)
		if C.sscanf(pid_line, c'\nPid: %d', &pid) != 1 || C.sscanf(tgid_line, c'\nTgid: %d', &tgid) != 1 { return false }
		count := C.sscanf(ns_line, c'\nNSpid: %d %d %d', &first, &second, &third)
		valid := pid == outer_tid && tgid == parsed_pid && first == outer_tid && count == if local { 1 } else { 2 } && (local || second == local_tid)
		C.printf(c'LINUX PROCSELF TASKIDS: local=%d leader=%d pid=%d/%d tgid=%d/%d nspid=%d:%d count=%d expected_count=%d %s\n', i32(local), i32(local_tid == 1), pid, outer_tid, tgid, parsed_pid, first, second, count, if local { 1 } else { 2 }, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn namespace_worker(arg voidptr) voidptr {
	unsafe {
		mut state := &NamespaceWorker(arg)
		if C.getpid() != 1 || C.syscall(isize(C.SYS_gettid)) <= 1 { state.failed = true; return nil }
		outer := namespace_identity(state.outer, false, state.outer_pid); inner := namespace_identity(state.inner, true, state.outer_pid)
		state.failed = !outer || !inner; return nil
	}
}
fn namespace_child(outer i32) i32 {
	unsafe {
		// Keep the inherited proc mount uncovered so its directory descriptor
		// continues to select the root view while testing the new tree.
		if C.getpid() != 1 || C.mkdir(c'/tmp/linux-procself/ns-view', u32(0o755)) != 0
			|| C.mount(c'proc', c'/tmp/linux-procself/ns-view', c'proc', 0, nil) != 0 { return 1 }
		inner := C.open(c'/tmp/linux-procself/ns-view', C.O_PATH | C.O_DIRECTORY); if inner < 0 { return 1 }; defer { C.close(inner) }
		mut link := [64]char{}; n := C.readlinkat(outer, c'self', &link[0], 63); if n <= 0 || n >= 64 { return 1 }; link[int(n)] = 0
		mut outer_pid := i32(-1); if C.sscanf(&link[0], c'%d', &outer_pid) != 1 || outer_pid <= 1 { return 1 }
		mut valid := namespace_identity(outer, false, outer_pid) && namespace_identity(inner, true, outer_pid)
		mut state := NamespaceWorker{outer: outer, inner: inner, outer_pid: outer_pid}; mut helper := C.pthread_t{}
		if C.pthread_create(&helper, nil, namespace_worker, &state) != 0 { return 1 }
		if C.pthread_join(helper, nil) != 0 { C._exit(1) }; if state.failed { valid = false }
		C.printf(c'LINUX PROCSELF PIDVIEW: outer-and-own leader/worker Pid/Tgid/NSpid %s\n', if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return if valid { 0 } else { 1 }
	}
}
fn namespace_test(outer i32) bool {
	unsafe {
		parent := C.fork(); if parent < 0 { return false }
		if parent == 0 {
			if C.unshare(C.CLONE_NEWNS) != 0 || C.unshare(C.CLONE_NEWPID) != 0 { C._exit(1) }
			child := C.fork(); if child < 0 { C._exit(1) }; if child == 0 { C._exit(namespace_child(outer)) }
			mut outcome := i32(-1); C._exit(if C.waitpid(child, &outcome, 0) == child && outcome == 0 { 0 } else { 1 })
		}
		mut outcome := i32(-1); return C.waitpid(parent, &outcome, 0) == parent && outcome == 0
	}
}
fn qualify(bank &Handles, ordinary bool) bool {
	unsafe {
		defer { cleanup(bank) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut good := matrix(bank, ordinary, 0)
		mut states := [Worker{bank: bank, ordinary: ordinary, slot: 1}, Worker{bank: bank, ordinary: ordinary, slot: 2}]!
		mut threads := [2]C.pthread_t{}; mut started := 0
		for index in 0 .. 2 { if C.pthread_create(&threads[index], nil, worker, &states[index]) != 0 { good = false; break }; started++ }
		for index in 0 .. started {
			// A failed join cannot unwind storage that a worker may still use.
			if C.pthread_join(threads[index], nil) != 0 { C._exit(1) }
			if states[index].failed || states[index].tid == C.getpid() { good = false }
		}
		if started != 2 || states[0].tid == states[1].tid { good = false }
		if !ordinary && !chroot_test() { good = false }
		if !ordinary && !namespace_test(bank.dirs[0]) { good = false }
		if !good || !storage(bank, ordinary) { return false }
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-procself', u32(0o755)) != 0 || C.mkdir(c'/tmp/linux-procself/alias', u32(0o755)) != 0
			|| C.mkdir(c'/tmp/linux-procself/jail', u32(0o755)) != 0 || C.mkdir(c'/tmp/linux-procself/jail/view', u32(0o755)) != 0
			|| C.mount(c'proc', c'/tmp/linux-procself/alias', c'proc', 0, nil) != 0 || C.mount(c'proc', c'/tmp/linux-procself/jail/view', c'proc', 0, nil) != 0 { return 1 }
		mut bank := &Handles(C.alloca(usize(sizeof(Handles)))); *bank = Handles{}
		for index in 0 .. 3 { bank.dirs[index] = -1 }; for index in 0 .. 6 { bank.links[index] = -1 }; defer { cleanup(bank) }
		if !prepare(bank) { return 1 }; mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(bank, ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX PROCSELF FAIL: relative target, reader identity, resolution or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX PROCSELF: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
