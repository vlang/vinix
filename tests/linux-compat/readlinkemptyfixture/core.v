// SPDX-License-Identifier: GPL-2.0-or-later
module readlinkemptyfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_mode u32 st_size i64 st_ino u64 st_dev u64 st_uid u32 st_gid u32 st_nlink u64 }
struct C.pollfd { fd i32 events i16 mut: revents i16 }
struct Handles { mut: fds [36]i32 extra [2]i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.readlinkat(i32, &char, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getpid() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn pathname(kind i32) &char {
	unsafe {
		return if kind == 0 { &char(c'/tmp/linux-readlinkempty/link') }
			else if kind == 1 { &char(c'/tmp/linux-readlinkempty/dangling') }
			else if kind == 2 { &char(c'/tmp/linux-readlinkempty/removed') }
			else if kind == 3 { &char(c'/tmp/linux-readlinkempty/private/link') }
			else if kind == 4 { &char(c'/proc/self') }
			else if kind == 5 { &char(c'/proc/self/exe') }
			else if kind == 7 { &char(c'/tmp/linux-readlinkempty') }
			else if kind == 9 { &char(c'/dev/null') }
			else { &char(c'/tmp/linux-readlinkempty/file') }
	}
}
fn aliases(bank &Handles, kind i32) bool {
	unsafe {
		mut handles := &Handles(bank); slot := kind * 3
		handles.fds[slot + 1] = C.dup(handles.fds[slot]); if handles.fds[slot + 1] < 0 { return false }
		handles.fds[slot + 2] = C.fcntl(handles.fds[slot], C.F_DUPFD_CLOEXEC, 0)
		return handles.fds[slot + 2] >= 0
	}
}
fn prepare(bank &Handles) bool {
	unsafe {
		mut handles := &Handles(bank)
		for kind in 0 .. 12 {
			if kind == 5 { continue }
			if kind in [10, 11]! {
				mut pair := [i32(-1), i32(-1)]!
				result := if kind == 10 { C.pipe2(&pair[0], C.O_NONBLOCK) } else { C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK, 0, &pair[0]) }
				handles.fds[kind * 3] = pair[0]; handles.extra[kind - 10] = pair[1]
				if result != 0 { return false }
			} else {
				flags := if kind == 6 { C.O_RDONLY } else if kind == 9 { C.O_RDWR } else { C.O_PATH | C.O_NOFOLLOW }
				handles.fds[kind * 3] = C.open(pathname(i32(kind)), flags)
				if handles.fds[kind * 3] < 0 { return false }
			}
			if !aliases(bank, i32(kind)) { return false }
		}
		mut bytes := [u8(0x41), 0x42]!
		return C.lseek(handles.fds[18], 2, C.SEEK_SET) == 2
			&& C.write(handles.extra[0], &bytes[0], 2) == 2 && C.write(handles.extra[1], &bytes[0], 2) == 2
	}
}
fn cleanup(bank &Handles) {
	unsafe { for fd in bank.fds { if fd >= 0 { C.close(fd) } }; for fd in bank.extra { if fd >= 0 { C.close(fd) } } }
}
fn queues(bank &Handles) bool {
	unsafe {
		for reader in [bank.fds[30], bank.fds[33]]! {
			mut queued := i32(-1); mut ready := C.pollfd{fd: reader, events: i16(C.POLLIN)}
			if C.ioctl(reader, usize(C.FIONREAD), &queued) != 0 || queued != 2 || C.poll(&ready, 1, 0) != 1 || ready.revents & i16(C.POLLIN) == 0 { return false }
		}
		return true
	}
}
fn controls(bank &Handles, ordinary bool) bool {
	unsafe {
		mut bytes := [4]u8{}
		if C.pread(bank.fds[18], &bytes[0], 4, 0) != 4 || bytes != [u8(0x41), 0x42, 0x43, 0x44]!
			|| C.lseek(bank.fds[18], 0, C.SEEK_CUR) != 2 || C.lseek(bank.fds[19], 0, C.SEEK_CUR) != 2 { return false }
		for index in 0 .. 36 {
			if C.fcntl(bank.fds[index], C.F_GETFD) & C.FD_CLOEXEC != if index % 3 == 2 { C.FD_CLOEXEC } else { 0 } { return false }
			mut info := C.stat{}; if C.fstat(bank.fds[index], &info) != 0 { return false }
			if index in [6, 7, 8]! && (info.st_nlink != 0 || info.st_size != 14) { return false }
		}
		e := C.__errno_location(); *e = 0
		missing := C.open(c'/tmp/linux-readlinkempty/removed', C.O_PATH | C.O_NOFOLLOW)
		if missing >= 0 { C.close(missing); return false }; if *e != C.ENOENT { return false }
		*e = 0; private_fd := C.open(c'/tmp/linux-readlinkempty/private/link', C.O_PATH | C.O_NOFOLLOW); code := *e
		if private_fd >= 0 { C.close(private_fd) }
		if ordinary { if private_fd >= 0 || code != C.EACCES { return false } } else if private_fd < 0 { return false }
		return queues(bank)
	}
}
fn probe(bank &Handles, kind i32, alias i32, word u64, destination i32, raw bool, high u64, verbose bool) bool {
	unsafe {
		fd := if kind == 12 { i32(-1) } else if kind == 13 { i32(C.AT_FDCWD) } else { bank.fds[kind * 3 + alias] }
		mut before := C.stat{}; mut after := C.stat{}
		if kind < 12 && C.fstat(fd, &before) != 0 { return false }
		mut bytes := [64]u8{}; for index in 0 .. 64 { bytes[index] = 0x5a }
		buf := if destination == 0 { voidptr(&bytes[0]) } else if destination == 1 { voidptr(nil) } else { voidptr(usize(1)) }
		size := i32(u32(word)); libc_zero := !raw && word == 0
		mut target := [64]char{}
		length := if kind == 1 { C.snprintf(&target[0], 64, c'missing-target') }
			else if kind == 2 { C.snprintf(&target[0], 64, c'removed-target') }
			else if kind == 4 { C.snprintf(&target[0], 64, c'/proc/%d', C.getpid()) }
			else if kind == 5 { C.snprintf(&target[0], 64, c'/sbin/init') }
			else { C.snprintf(&target[0], 64, c'destination') }
		if length <= 0 || length >= 64 { return false }
		expected := if size <= 0 && !libc_zero { C.EINVAL } else if kind == 12 { C.EBADF }
			else if kind >= 6 { C.ENOENT } else if destination != 0 && !libc_zero { C.EFAULT } else { 0 }
		copied := if size < length { size } else { length }
		wanted := if expected != 0 { isize(-1) } else { isize(copied) }
		e := C.__errno_location(); *e = 0
		actual := if raw { C.syscall(isize(C.SYS_readlinkat), high | u64(u32(fd)), c'', buf, word) } else { C.readlinkat(fd, c'', buf, usize(word)) }; code := *e
		mut valid := actual == wanted && code == expected
		for index in 0 .. 64 {
			byte := if expected == 0 && index < copied { u8(target[index]) } else { u8(0x5a) }
			if bytes[index] != byte { valid = false }
		}
		if kind < 12 {
			if C.fstat(fd, &after) != 0 || before.st_mode != after.st_mode || before.st_size != after.st_size || before.st_ino != after.st_ino || before.st_dev != after.st_dev || before.st_uid != after.st_uid || before.st_gid != after.st_gid || before.st_nlink != after.st_nlink { valid = false }
		}
		if !valid && verbose { C.printf(c'LINUX READLINKEMPTY DETAIL: kind=%d alias=%d raw=%d high=%016lx dest=%d word=%016lx result=%ld/%d expected=%ld/%d\n', kind, alias, i32(raw), high, destination, word, actual, code, wanted, expected); C.fflush(nil) }
		return valid
	}
}
fn storage_cycle(bank &Handles, ordinary bool) bool {
	unsafe {
		for kind in 0 .. 14 { for word in [u64(0), 1, 3, 0x100000003]! {
			if !probe(bank, i32(kind), i32(kind % 3), word, i32(kind % 2), true, u64(0xdeadbeef00000000), false) { return false }
		} }
		for kind in [i32(0), 2, 7]! {
			copy := C.dup(bank.fds[kind * 3]); if copy < 0 { return false }
			mut bytes := [4]u8{}; e := C.__errno_location(); *e = 0
			actual := C.syscall(isize(C.SYS_readlinkat), u64(0x8000000000000000) | u64(u32(copy)), c'', &bytes[0], u64(3)); code := *e
			C.close(copy)
			if kind == 7 { if actual != -1 || code != C.ENOENT || bytes != [u8(0), 0, 0, 0]! { return false } }
			else if actual != 3 || code != 0 || bytes != if kind == 0 { [u8(`d`), `e`, `s`, 0]! } else { [u8(`r`), `e`, `m`, 0]! } { return false }
		}
		return controls(bank, ordinary)
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); mut data := [4096]char{}
		length := C.pread(fd, &data[0], usize(data.len - 1), 0)
		if length <= 0 || length >= data.len { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate_size := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate_size, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate_size { return false }
				counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}
fn storage(bank &Handles, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(bank, ordinary) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(bank, ordinary) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX READLINKEMPTY SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX READLINKEMPTY STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(bank &Handles, ordinary bool) bool {
	unsafe {
		defer { cleanup(bank) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		mut handles := &Handles(bank); handles.fds[15] = C.open(c'/proc/self/exe', C.O_PATH | C.O_NOFOLLOW)
		if handles.fds[15] < 0 || !aliases(bank, 5) || !controls(bank, ordinary) { return false }
		C.alarm(300); mut cases := i32(0); mut bad := i32(0)
		words := [u64(0), 1, 3, 14, 64, 0x80000000, 0x100000000, 0x100000003]!
		patterns := [u64(0), 0x100000000, 0xdeadbeef00000000]!
		for kind in 0 .. 14 {
			count := if kind >= 12 { 1 } else { 3 }
			for alias in 0 .. count { for word in words { for destination in 0 .. 3 { for variant in 0 .. 4 {
				raw := variant != 3; high := patterns[if raw { variant } else { 0 }]
				cases++; if !probe(bank, i32(kind), i32(alias), word, i32(destination), raw, high, true) { bad++ }
			} } } }
		}
		C.printf(c'LINUX READLINKEMPTY OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), cases, bad); C.fflush(nil)
		if bad != 0 || !storage(bank, ordinary) || !controls(bank, ordinary) { return false }
		for index in 0 .. 2 {
			mut bytes := [4]u8{}; if C.read(bank.fds[30 + index * 3], &bytes[0], 4) != 2 || bytes[0] != 0x41 || bytes[1] != 0x42 || C.write(bank.extra[index], &bytes[0], 2) != 2 { return false }
		}
		C.printf(c'LINUX READLINKEMPTY CONTROLS: ordinary=%d linked/dangling/unlinked/private/procfs/target-prefix/no-NUL/canaries/aliases/metadata/bytes/cursors/flags/queued-AB PASS\n', i32(ordinary)); C.fflush(nil)
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-readlinkempty', u32(0o755)) != 0 || C.mkdir(c'/tmp/linux-readlinkempty/private', u32(0o700)) != 0
			|| C.symlink(c'destination', c'/tmp/linux-readlinkempty/link') != 0 || C.symlink(c'missing-target', c'/tmp/linux-readlinkempty/dangling') != 0
			|| C.symlink(c'removed-target', c'/tmp/linux-readlinkempty/removed') != 0 || C.symlink(c'destination', c'/tmp/linux-readlinkempty/private/link') != 0 { return 1 }
		fd := C.open(c'/tmp/linux-readlinkempty/file', C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o644)); if fd < 0 { return 1 }
		mut bytes := [u8(0x41), 0x42, 0x43, 0x44]!
		ready := C.write(fd, &bytes[0], 4) == 4; C.close(fd); if !ready { return 1 }
		mut bank := &Handles(C.alloca(usize(sizeof(Handles)))); *bank = Handles{}
		for index in 0 .. 36 { bank.fds[index] = -1 }; for index in 0 .. 2 { bank.extra[index] = -1 }; defer { cleanup(bank) }
		if !prepare(bank) || C.unlink(c'/tmp/linux-readlinkempty/removed') != 0 { return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(bank, ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX READLINKEMPTY FAIL: empty-path target or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX READLINKEMPTY PASS: native raw/musl readlinkat empty paths retain symlink descriptions through lookup/copy after unlink or private-directory denial, include dynamic procfs links and aliases, return real invalid/nonlink/size/copy errors, preserve bytes/metadata/flags/cursors/queued AB and keep200-cycle storage flat')
		C.puts(c'LINUX READLINKEMPTY: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
