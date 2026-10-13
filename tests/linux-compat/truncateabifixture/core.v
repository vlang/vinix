// SPDX-License-Identifier: GPL-2.0-or-later
module truncateabifixture

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

struct C.stat { st_mode u32 st_size i64 st_ino u64 st_dev u64 st_uid u32 st_gid u32 }
struct C.pollfd { fd i32 events i16 mut: revents i16 }
struct Handles { mut: fds [60]i32 peer i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.ftruncate(i32, i64) i32
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn pathname(kind i32) &char {
	unsafe {
	return if kind == 5 { &char(c'/tmp/linux-truncateabi/private') }
		else if kind in [i32(6), 7]! { &char(c'/tmp/linux-truncateabi') }
		else if kind in [i32(11), 12]! { &char(c'/dev/null') }
		else if kind in [i32(17), 19]! { &char(c'/dev/zero') }
		else if kind == 18 { &char(c'/dev/full') }
		else if kind == 14 { &char(c'/tmp/linux-truncateabi/link') }
		else if kind in [i32(15), 16]! { &char(c'/tmp/linux-truncateabi/fifo') }
		else { &char(c'/tmp/linux-truncateabi/normal') }
	}
}
fn is_path(kind i32) bool { unsafe { return kind in [i32(4), 5, 7, 12, 14, 15, 19]! } }
fn restore_file(fd i32) bool {
	unsafe {
		mut bytes := [u8(0x41), 0x42, 0x43, 0x44]!
		return C.ftruncate(fd, 4) == 0 && C.pwrite(fd, &bytes[0], 4, 0) == 4
	}
}
fn prepare(bank &Handles) bool {
	unsafe {
		mut handles := &Handles(bank)
		mut pipe := [i32(-1), i32(-1)]!
		if C.pipe2(&pipe[0], C.O_NONBLOCK) != 0 { return false }
		handles.fds[24] = pipe[0]; handles.fds[27] = pipe[1]
		for kind in 0 .. 20 {
			if kind == 13 { continue }
			slot := kind * 3
			if kind == 10 {
				mut pair := [i32(-1), i32(-1)]!
				result := C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK, 0, &pair[0])
				handles.fds[slot] = pair[0]; handles.peer = pair[1]; if result != 0 { return false }
			} else if kind !in [8, 9]! {
				flags := if is_path(i32(kind)) { C.O_PATH | if kind == 14 { C.O_NOFOLLOW } else { 0 } }
					else if kind in [0, 6]! { C.O_RDONLY } else if kind == 1 { C.O_WRONLY } else if kind == 3 { 3 } else { C.O_RDWR | C.O_NONBLOCK }
				handles.fds[slot] = C.open(pathname(i32(kind)), flags); if handles.fds[slot] < 0 { return false }
			}
			handles.fds[slot + 1] = C.dup(handles.fds[slot]); if handles.fds[slot + 1] < 0 { return false }
			handles.fds[slot + 2] = C.fcntl(handles.fds[slot], C.F_DUPFD_CLOEXEC, 0); if handles.fds[slot + 2] < 0 { return false }
			if kind <= 3 || kind == 6 { if C.lseek(handles.fds[slot], 2, C.SEEK_SET) != 2 { return false } }
		}
		mut bytes := [u8(0x41), 0x42]!
		return C.write(handles.fds[27], &bytes[0], 2) == 2 && C.write(handles.peer, &bytes[0], 2) == 2 && C.write(handles.fds[48], &bytes[0], 2) == 2
	}
}
fn cleanup(bank &Handles) {
	unsafe { for fd in bank.fds { if fd >= 0 { C.close(fd) } }; if bank.peer >= 0 { C.close(bank.peer) } }
}
fn queues(bank &Handles) bool {
	unsafe {
		for reader in [bank.fds[24], bank.fds[30], bank.fds[48]]! {
			mut queued := i32(-1); mut ready := C.pollfd{fd: reader, events: i16(C.POLLIN)}
			if C.ioctl(reader, usize(C.FIONREAD), &queued) != 0 || queued != 2 || C.poll(&ready, 1, 0) != 1 || ready.revents & i16(C.POLLIN) == 0 { return false }
		}
		return true
	}
}
fn probe(bank &Handles, observers &i32, kind i32, alias i32, length i64, raw bool, high u64, verbose bool) bool {
	unsafe {
		observer := observers[if kind == 5 { 1 } else { 0 }]
		if !restore_file(observer) { return false }
		original := bank.fds[kind * 3]; fd := bank.fds[kind * 3 + alias]
		mut before := C.stat{}; mut after := C.stat{}
		if fd >= 0 && C.fstat(fd, &before) != 0 { return false }
		cursor := if kind <= 3 || kind == 6 { C.lseek(original, 0, C.SEEK_CUR) } else { i64(-1) }
		e := C.__errno_location(); *e = 0
		word := high | u64(u32(fd))
		actual := if raw { C.syscall(isize(C.SYS_ftruncate), word, length) } else { isize(C.ftruncate(fd, length)) }; code := *e
		expected := if length < 0 { C.EINVAL } else if kind == 13 || is_path(kind) { C.EBADF } else if kind !in [i32(1), 2]! { C.EINVAL } else { 0 }
		wanted := if expected == 0 { isize(0) } else { isize(-1) }
		mut valid := actual == wanted && code == expected
		if fd >= 0 {
			if C.fstat(fd, &after) != 0 || before.st_mode != after.st_mode || before.st_ino != after.st_ino || before.st_dev != after.st_dev || before.st_uid != after.st_uid || before.st_gid != after.st_gid
				|| after.st_size != if expected == 0 { length } else { before.st_size } { valid = false }
			if C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != if alias == 2 { C.FD_CLOEXEC } else { 0 } { valid = false }
			// Preserve a repeatable baseline after observing an incorrect inode resize.
			// Correct candidates never enter this nonregular restoration path.
			if is_path(kind) && kind >= 7 && before.st_size != after.st_size { C.ftruncate(fd, before.st_size) }
		}
		if cursor >= 0 && (C.lseek(original, 0, C.SEEK_CUR) != cursor || C.lseek(fd, 0, C.SEEK_CUR) != cursor) { valid = false }
		mut metadata := C.stat{}; mut bytes := [64]u8{}
		if C.fstat(observer, &metadata) != 0 || metadata.st_size != if expected == 0 { length } else { i64(4) } { valid = false }
		wanted_bytes := if expected == 0 { length } else { i64(4) }
		if C.pread(observer, &bytes[0], 64, 0) != isize(wanted_bytes) { valid = false }
		for index in 0 .. int(wanted_bytes) { if bytes[index] != if index < 4 { u8(0x41 + index) } else { u8(0) } { valid = false } }
		if !queues(bank) { valid = false }
		if !valid && verbose { C.printf(c'LINUX TRUNCATEABI DETAIL: kind=%d alias=%d raw=%d high=%016lx length=%ld result=%ld/%d expected=%ld/%d size=%ld/%ld\n', kind, alias, i32(raw), high, length, actual, code, wanted, expected, before.st_size, after.st_size); C.fflush(nil) }
		return valid
	}
}
fn private_permissions(ordinary bool) bool {
	unsafe {
		if ordinary {
			e := C.__errno_location(); *e = 0; denied := C.open(c'/tmp/linux-truncateabi/private', C.O_RDONLY)
			if denied >= 0 { C.close(denied); return false }; if *e != C.EACCES { return false }
		}
		return true
	}
}
fn storage_cycle(bank &Handles, observers &i32) bool {
	unsafe {
		for kind in 0 .. 20 { for length in [i64(-1), 0, 3, 8]! {
			if !probe(bank, observers, i32(kind), i32(kind % 3), length, true, u64(0xdeadbeef00000000), false) { return false }
		} }
		for kind in [i32(1), 4, 11]! {
			copy := C.dup(bank.fds[kind * 3]); if copy < 0 { return false }
			e := C.__errno_location(); *e = 0
			actual := C.syscall(isize(C.SYS_ftruncate), u64(0x8000000000000000) | u64(u32(copy)), i64(4)); code := *e
			C.close(copy)
			if actual != if kind == 1 { isize(0) } else { isize(-1) } || code != if kind == 1 { 0 } else if kind == 4 { C.EBADF } else { C.EINVAL } { return false }
		}
		return true
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
fn storage(bank &Handles, observers &i32, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(bank, observers) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(bank, observers) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX TRUNCATEABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX TRUNCATEABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(observers &i32, ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut cases := i32(0); mut bad := i32(0)
		mut bank := &Handles(C.alloca(usize(sizeof(Handles)))); *bank = Handles{peer: -1}
		for index in 0 .. 60 { bank.fds[index] = -1 }; defer { cleanup(bank) }
		if !prepare(bank) || !queues(bank) || !private_permissions(ordinary) { return false }
		patterns := [u64(0), 0x100000000, 0xffffffff00000000, 0x8000000000000000, 0xdeadbeef00000000]!
		for kind in 0 .. 20 {
			aliases := if kind == 13 { 1 } else { 3 }
			for alias in 0 .. aliases { for length in [i64(0), 1, 3, 4, 8, 64, -1, -i64(0x7fffffffffffffff) - 1]! { for variant in 0 .. 6 {
				raw := variant != 5; high := patterns[if raw { variant } else { 0 }]
				cases++; if !probe(bank, observers, i32(kind), i32(alias), length, raw, high, true) { bad++ }
			} } }
		}
		if !restore_file(observers[0]) || !restore_file(observers[1]) || !queues(bank) || !private_permissions(ordinary) { return false }
		C.printf(c'LINUX TRUNCATEABI OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), cases, bad); C.fflush(nil)
		if bad != 0 || !storage(bank, observers, ordinary) { return false }
		if !restore_file(observers[0]) || !restore_file(observers[1]) || !queues(bank) || !private_permissions(ordinary) { return false }
		for slot in [24, 30, 48]! {
			mut bytes := [4]u8{}; if C.read(bank.fds[slot], &bytes[0], 4) != 2 || bytes[0] != 0x41 || bytes[1] != 0x42 { return false }
		}
		C.printf(c'LINUX TRUNCATEABI CONTROLS: ordinary=%d shrink/grow/zero-fill/cursors/metadata/flags/private/queues/readiness PASS\n', i32(ordinary)); C.fflush(nil)
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-truncateabi', u32(0o755)) != 0 || C.mkfifo(c'/tmp/linux-truncateabi/fifo', u32(0o666)) != 0
			|| C.chmod(c'/tmp/linux-truncateabi/fifo', u32(0o666)) != 0 || C.symlink(c'private', c'/tmp/linux-truncateabi/link') != 0 { return 1 }
		mut observers := &i32(C.alloca(usize(2 * sizeof(i32)))); observers[0] = -1; observers[1] = -1
		defer { unsafe { for index in 0 .. 2 { if observers[index] >= 0 { C.close(observers[index]) } } } }
		for index in 0 .. 2 {
			path := if index == 0 { &char(c'/tmp/linux-truncateabi/normal') } else { &char(c'/tmp/linux-truncateabi/private') }
			observers[index] = C.open(path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666))
			if observers[index] < 0 || !restore_file(observers[index]) || C.chmod(path, if index == 0 { u32(0o666) } else { u32(0o600) }) != 0 { return 1 }
		}
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(observers, ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX TRUNCATEABI FAIL: native descriptor words or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX TRUNCATEABI PASS: root/UID1000 raw/musl ftruncate ignores upper descriptor words, retains signed64 lengths, validates negative lengths first, rejects O_PATH with EBADF and nonregular/readonly/mode3 handles with EINVAL, preserves aliases/metadata/bytes/cursors/queues/readiness and private permissions, and permits writable regular-file zero-filled resizing with flat200-cycle storage')
		C.puts(c'LINUX TRUNCATEABI: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
