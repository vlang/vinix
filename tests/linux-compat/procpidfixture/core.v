// SPDX-License-Identifier: GPL-2.0-or-later
module procpidfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
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
struct C.siginfo_t {}
struct C.stat { st_dev u64 st_ino u64 st_mode u32 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Bank { mut: roots [9]i32 metadata [3]C.stat held [18]i32 held_metadata [6]C.stat }
struct Child { mut: pid i32 writer i32 }
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
fn C.kill(i32, i32) i32
fn C.unshare(i32) i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
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
		if ordinary { return match mount { 0 { c'/tmp/procpid-nu0' } 1 { c'/tmp/procpid-nu1' } else { c'/tmp/procpid-nu2' } } }
		return match mount { 0 { c'/tmp/procpid-nr0' } 1 { c'/tmp/procpid-nr1' } else { c'/tmp/procpid-nr2' } }
	}
	if ordinary { return if mount == 1 { c'/tmp/procpid-u1' } else { c'/tmp/procpid-u2' } }
	return if mount == 1 { c'/tmp/procpid-r1' } else { c'/tmp/procpid-r2' }
}
fn leaf_suffix(leaf i32) &char { if leaf == 0 { return c'/stat' }; if leaf == 1 { return c'/status' }; return c'' }
fn same(left &C.stat, right &C.stat) bool { return left.st_dev == right.st_dev && left.st_ino == right.st_ino && left.st_mode == right.st_mode }
fn fatal() { C.puts(c'LINUX PROCPID FAIL: setup or child protocol'); C.fflush(unsafe { nil }); C._exit(1) }
fn record(counts &Counts, kind i32, good bool, ordinary bool, namespace bool) {
	unsafe { mut tally := &Counts(counts); tally.calls[kind]++; if !good { tally.failures[kind]++; if tally.failures[kind] <= 3 { C.printf(c'LINUX PROCPID DETAIL: ordinary=%d namespace=%d kind=%d call=%lu\n', i32(ordinary), i32(namespace), kind, tally.calls[kind]); C.fflush(nil) } } }
}
fn prepare(bank &Bank, ordinary bool, namespace bool) {
	unsafe { mut value := &Bank(bank); for i in 0 .. 9 { value.roots[i] = -1 }; for i in 0 .. 18 { value.held[i] = -1 }
		for mount in 0 .. 3 {
			root := root_path(i32(mount), ordinary, namespace)
			if (mount != 0 || namespace) && (C.mkdir(root, 0o755) != 0 || C.mount(c'proc', root, c'proc', 0, nil) != 0) { fatal() }
			index := mount * 3; value.roots[index] = C.open(root, C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC)
			if value.roots[index] < 0 || C.fstat(value.roots[index], &value.metadata[mount]) != 0 { fatal() }
			value.roots[index + 1] = C.dup(value.roots[index]); value.roots[index + 2] = C.fcntl(value.roots[index], C.F_DUPFD_CLOEXEC, 40)
			if value.roots[index + 1] < 0 || value.roots[index + 2] < 0 { fatal() }
		}
	}
}
fn fork_child(child &Child) {
	unsafe { mut value := &Child(child); gate := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(gate, C.O_CLOEXEC) != 0 { fatal() }; value.pid = C.fork(); if value.pid < 0 { fatal() }
		if value.pid == 0 { C.close(gate[1]); mut token := char(0); passed := C.read(gate[0], &token, 1) == 1 && token == char(`Q`); C.close(gate[0]); C._exit(if passed { 0 } else { 1 }) }; C.close(gate[0]); value.writer = gate[1]
	}
}
fn release(child &Child) { unsafe { mut value := &Child(child); if C.write(value.writer, c'Q', 1) != 1 || C.close(value.writer) != 0 { fatal() }; value.writer = -1 } }
fn zombie(child &Child) { unsafe { info := &C.siginfo_t(C.alloca(usize(sizeof(C.siginfo_t)))); if C.waitid(C.P_PID, u32(child.pid), info, C.WEXITED | C.WNOWAIT) != 0 { fatal() } } }
fn reap(child &Child) {
	unsafe { mut status := i32(-1); if C.waitpid(child.pid, &status, 0) != child.pid || status != 0 { fatal() }; slot := C.__errno_location(); *slot = 0; if C.kill(child.pid, 0) != -1 || *slot != C.ESRCH { fatal() } }
}
fn opened(bank &Bank, name &char, path &char, flags i32, mount i32, form i32) i32 {
	unsafe { base := mount * 3; if form == 0 { return C.open(path, flags) }
		if form == 1 { return i32(C.syscall(C.SYS_openat, u64(u32(C.AT_FDCWD)) | 0xffffffff00000000, path, u64(u32(flags)) | 0x8000000000000000, 0)) }
		if form == 2 { return C.openat(bank.roots[base], name, flags) }
		if form == 3 { return i32(C.syscall(C.SYS_openat, u64(u32(bank.roots[base + 1])) | 0xffffffff00000000, name, u64(u32(flags)) | 0x8000000000000000, 0)) }
		return C.openat(bank.roots[base + 2], name, flags)
	}
}
fn query(bank &Bank, pid i32, mount i32, leaf i32, form i32, present bool, identity &C.stat, ordinary bool, namespace bool) bool {
	unsafe { name := &char(C.alloca(64)); path := &char(C.alloca(192)); length := C.snprintf(name, 64, c'%d%s', pid, leaf_suffix(leaf)); full := C.snprintf(path, 192, c'%s/%s', root_path(mount, ordinary, namespace), name)
		if length <= 0 || length >= 64 || full <= 0 || full >= 192 { return false }
		flags := C.O_RDONLY | C.O_CLOEXEC | if leaf == 2 { C.O_DIRECTORY } else { 0 }; slot := C.__errno_location(); *slot = 0; fd := opened(bank, name, path, flags, mount, form); code := *slot
		if !present { if fd >= 0 { C.close(fd) }; return fd == -1 && code == C.ENOENT }; if fd < 0 { return false }
		actual := &C.stat(C.alloca(usize(sizeof(C.stat)))); inspected := C.fstat(fd, actual) == 0 && C.fcntl(fd, C.F_GETFD) == C.FD_CLOEXEC; mut good := code == 0 && inspected
		if inspected { if form == 0 { mut original := &C.stat(identity); *original = *actual } else if !same(identity, actual) { good = false } }
		closed := C.close(fd) == 0; return good && closed
	}
}
fn sweep(counts &Counts, kind i32, bank &Bank, pid i32, present bool, ordinary bool, namespace bool) {
	unsafe { mut identity := &C.stat(C.alloca(usize(sizeof(C.stat)))); for mount in 0 .. 3 { for leaf in 0 .. 3 { *identity = C.stat{}; for form in 0 .. 5 { record(counts, kind, query(bank, pid, i32(mount), i32(leaf), i32(form), present, identity, ordinary, namespace), ordinary, namespace) } } } }
}
fn hold_child(bank &Bank, pid i32) {
	unsafe { mut value := &Bank(bank); name := &char(C.alloca(64)); for mount in 0 .. 3 { for leaf in 0 .. 2 {
		length := C.snprintf(name, 64, c'%d%s', pid, leaf_suffix(if leaf == 0 { 0 } else { 2 })); if length <= 0 || length >= 64 { fatal() }
		index := (mount * 2 + leaf) * 3; value.held[index] = C.openat(value.roots[mount * 3], name, C.O_RDONLY | C.O_CLOEXEC | if leaf == 1 { C.O_DIRECTORY } else { 0 })
		if value.held[index] < 0 || C.fstat(value.held[index], &value.held_metadata[mount * 2 + leaf]) != 0 { fatal() }; value.held[index + 1] = C.dup(value.held[index]); value.held[index + 2] = C.fcntl(value.held[index], C.F_DUPFD_CLOEXEC, 40)
		if value.held[index + 1] < 0 || value.held[index + 2] < 0 { fatal() }
	} } }
}
fn descriptors(counts &Counts, bank &Bank, ordinary bool, namespace bool) {
	unsafe { data := &C.stat(C.alloca(usize(sizeof(C.stat)))); for index in 0 .. 27 {
		fd := if index < 9 { bank.roots[index] } else { bank.held[index - 9] }; original := if index < 9 { &bank.metadata[index / 3] } else { &bank.held_metadata[(index - 9) / 3] }
		good := C.fstat(fd, data) == 0 && same(data, original) && C.fcntl(fd, C.F_GETFD) == if index % 3 == 1 { i32(0) } else { i32(C.FD_CLOEXEC) }; record(counts, 5, good, ordinary, namespace)
	} }
}
fn special(counts &Counts, bank &Bank, ordinary bool, namespace bool) {
	unsafe { path := &char(C.alloca(192)); data := &C.stat(C.alloca(usize(sizeof(C.stat)))); for mount in 0 .. 3 {
		for index, name in [&char(c'.'), &char(c'..'), &char(c'self'), &char(c'thread-self'), &char(c'sys'), &char(c'version')]! { for form in 0 .. 5 {
			length := C.snprintf(path, 192, c'%s/%s', root_path(i32(mount), ordinary, namespace), name); if length <= 0 || length >= 192 { fatal() }
			flags := C.O_RDONLY | C.O_CLOEXEC | if index != 5 { C.O_DIRECTORY } else { 0 }; fd := opened(bank, name, path, flags, i32(mount), i32(form))
			mut good := fd >= 0 && C.fstat(fd, data) == 0 && (data.st_mode & u32(C.S_IFMT)) == if index == 5 { u32(C.S_IFREG) } else { u32(C.S_IFDIR) }
			if good && index == 0 { good = same(data, &bank.metadata[mount]) }; if fd >= 0 && C.close(fd) != 0 { good = false }; record(counts, 3, good, ordinary, namespace)
		} }
	} }
}
fn qualify(counts &Counts, ordinary bool, namespace bool, reference_run bool) bool {
	unsafe { C.alarm(600); bank := &Bank(C.alloca(usize(sizeof(Bank)))); prepare(bank, ordinary, namespace)
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { fatal() }
		retired := &Child(C.alloca(usize(sizeof(Child)))); survivor := &Child(C.alloca(usize(sizeof(Child)))); fork_child(retired); fork_child(survivor)
		for pid in [C.getpid(), retired.pid, survivor.pid]! { sweep(counts, 0, bank, pid, true, ordinary, namespace) }; hold_child(bank, retired.pid); descriptors(counts, bank, ordinary, namespace)
		release(retired); zombie(retired); sweep(counts, 1, bank, retired.pid, true, ordinary, namespace); descriptors(counts, bank, ordinary, namespace)
		reap(retired); for _ in 0 .. 2 { sweep(counts, 2, bank, retired.pid, false, ordinary, namespace) }; descriptors(counts, bank, ordinary, namespace)
		for pid in [C.getpid(), survivor.pid]! { sweep(counts, 3, bank, pid, true, ordinary, namespace) }; special(counts, bank, ordinary, namespace)
		for pid in [i32(0), 2147483647]! { sweep(counts, 4, bank, pid, false, ordinary, namespace) }
		mut good := true; for kind in 0 .. 6 { if counts.failures[kind] != 0 { good = false } }; if good && !reference_run && !storage(bank, retired.pid, survivor.pid, ordinary, namespace) { good = false }
		release(survivor); zombie(survivor); reap(survivor); descriptors(counts, bank, ordinary, namespace)
		for index in 0 .. 9 { if C.close(bank.roots[index]) != 0 { good = false } }; for index in 0 .. 18 { if C.close(bank.held[index]) != 0 { good = false } }; C.alarm(0)
		for kind in 0 .. 6 { C.printf(c'LINUX PROCPID CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(namespace), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } }; C.fflush(nil); return good
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe { reference_run := argc == 2 && C.strcmp(argv[1], c'--reference') == 0; mut good := true
		for namespace in [false, true]! { for ordinary in [true, false]! {
			C.fflush(nil); pipe := &i32(C.alloca(usize(2 * sizeof(i32)))); if C.pipe2(pipe, C.O_CLOEXEC) != 0 { return 1 }; outer := C.fork(); if outer < 0 { return 1 }
			if outer == 0 { C.close(pipe[0]); if namespace { if C.unshare(C.CLONE_NEWPID) != 0 { fatal() }; init := C.fork(); if init < 0 { fatal() }; if init > 0 { C.close(pipe[1]); mut status := i32(-1); C._exit(if C.waitpid(init, &status, 0) == init && status == 0 { 0 } else { 1 }) }; if C.getpid() != 1 { fatal() } }
				counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}; passed := qualify(counts, ordinary, namespace, reference_run); sent := C.write(pipe[1], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); received := C.read(pipe[0], counts, usize(sizeof(Counts))) == isize(sizeof(Counts)); C.close(pipe[0]); mut status := i32(-1); completed := C.waitpid(outer, &status, 0) == outer && status == 0
			if !received || !completed { good = false }; if received { for kind in 0 .. 6 { C.printf(c'LINUX PROCPID FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), i32(namespace), kind, counts.calls[kind], counts.failures[kind]); if counts.failures[kind] != 0 { good = false } } }; C.fflush(nil)
		} }
		if !good { C.puts(c'LINUX PROCPID FAIL: cached process root or retained metadata'); C.fflush(nil); return 1 }; C.puts(if reference_run { c'LINUX PROCPID REFERENCE: PASS' } else { c'LINUX PROCPID: PASS' }); C.fflush(nil); for { C.pause() }
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
fn cycle(bank &Bank, retired i32, survivor i32, ordinary bool, namespace bool) bool {
	unsafe { mut identity := &C.stat(C.alloca(usize(sizeof(C.stat)))); for mount in 0 .. 3 { for leaf in 0 .. 3 { *identity = C.stat{}; for form in 0 .. 5 {
		if !query(bank, retired, i32(mount), i32(leaf), i32(form), false, identity, ordinary, namespace) || !query(bank, survivor, i32(mount), i32(leaf), i32(form), true, identity, ordinary, namespace) { return false }
	} }; alias := C.dup(bank.roots[mount * 3]); if alias < 0 { return false }; good := C.fstat(alias, identity) == 0 && same(identity, &bank.metadata[mount]); closed := C.close(alias) == 0; if !good || !closed { return false } }; return true }
}
fn storage(bank &Bank, retired i32, survivor i32, ordinary bool, namespace bool) bool {
	unsafe { observer := C.open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(bank, retired, survivor, ordinary, namespace) { return false } }; C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs)))); if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(bank, retired, survivor, ordinary, namespace) { return false } }; C.usleep(13000000); if !snapshot(observer, after) { return false }; mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) { if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }; C.printf(c'LINUX PROCPID SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), i32(namespace), before.sizes[index], before.live[index], after.live[index]) }
		C.printf(c'LINUX PROCPID STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), i32(namespace), before.large, after.large, if good { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil); return good
	}
}
