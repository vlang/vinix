// SPDX-License-Identifier: GPL-2.0-or-later
module seekerrorfixture

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

struct Handles { mut: primary [12]i32 peer [12]i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct C.stat { st_mode u32 st_size i64 st_ino u64 st_dev u64 }
struct C.pollfd { fd i32 events i16 mut: revents i16 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
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

fn prepare(bank &Handles) bool {
	unsafe {
		mut handles := &Handles(bank)
		for kind in 0 .. 12 {
			if kind == 9 { continue }
			if kind in [2, 3, 5, 6, 7]! {
				mut pair := [i32(-1), i32(-1)]!
				result := if kind in [2, 3]! { C.pipe2(&pair[0], C.O_NONBLOCK) }
					else { C.socketpair(C.AF_UNIX, (if kind == 5 { C.SOCK_STREAM } else if kind == 6 { C.SOCK_DGRAM } else { C.SOCK_SEQPACKET }) | C.SOCK_NONBLOCK, 0, &pair[0]) }
				handles.primary[kind] = pair[if kind == 3 { 1 } else { 0 }]
				handles.peer[kind] = pair[if kind == 3 { 0 } else { 1 }]
				if result != 0 { return false }
			} else {
				path := if kind == 1 { &char(c'/tmp/linux-seekerror-dir') }
					else if kind in [4, 11]! { &char(c'/tmp/linux-seekerror-fifo') }
					else if kind == 8 { &char(c'/dev/null') } else { &char(c'/tmp/linux-seekerror-file') }
				flags := if kind >= 10 { C.O_PATH } else if kind == 1 { C.O_RDONLY | C.O_DIRECTORY } else { C.O_RDWR | C.O_NONBLOCK }
				handles.primary[kind] = C.open(path, flags)
				if handles.primary[kind] < 0 { return false }
			}
			if kind in [0, 1]! && C.lseek(handles.primary[kind], 1, C.SEEK_SET) != 1 { return false }
			if kind >= 2 && kind <= 7 {
				writer := if kind == 3 || kind == 4 { handles.primary[kind] } else { handles.peer[kind] }
				mut bytes := [u8(0x41), 0x42]!
				if C.write(writer, &bytes[0], 2) != 2 { return false }
			}
		}
		return true
	}
}
fn cleanup(bank &Handles) {
	unsafe { for fd in bank.primary { if fd >= 0 { C.close(fd) } }; for fd in bank.peer { if fd >= 0 { C.close(fd) } } }
}
fn refuse(fd i32, kind i32, offset i64, whence i32, fd_high u64, selector_high u64, expected i32, verbose bool) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(C.SYS_lseek), fd_high | u64(u32(fd)), offset, selector_high | u64(u32(whence))); code := *e
		valid := actual == -1 && code == expected
		if !valid && verbose && offset == 0 && whence == 5 && fd_high == 0 && selector_high == 0 {
			C.printf(c'LINUX SEEKERROR DETAIL: kind=%d offset=%ld whence=%d result=%ld/%d expected=-1/%d\n', kind, offset, whence, actual, code, expected); C.fflush(nil)
		}
		return valid
	}
}
fn invalid_selectors(fd i32, kind i32, verbose bool) (i32, i32) {
	unsafe {
		mut cases := i32(0); mut bad := i32(0)
		expected := if kind >= 9 { C.EBADF } else { C.EINVAL }
		for high in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
			for selector_high in [u64(0), 0x8000000000000000, 0xffffffff00000000]! {
				for offset in [i64(0), i64(1) << 32 | 17, i64(-1), -i64(0x7fffffffffffffff) - 1]! {
					for whence in [i32(5), 0x7fffffff, -1]! {
						cases++; if !refuse(fd, kind, offset, whence, high, selector_high, expected, verbose) { bad++ }
					}
				}
			}
		}
		return cases, bad
	}
}
fn controls(fd i32, kind i32) bool {
	unsafe {
		if kind in [0, 1]! {
			if C.lseek(fd, 0, C.SEEK_CUR) != 1 { return false }
			e := C.__errno_location(); *e = 0
			if C.syscall(isize(C.SYS_lseek), u64(0x1234567800000000) | u64(u32(fd)), i64(0), u64(0xffffffff00000001)) != 1 || *e != 0 { return false }
			if kind == 0 {
				mut bytes := [4]u8{}
				if C.pread(fd, &bytes[0], 4, 0) != 4 || bytes != [u8(0x41), 0x42, 0x43, 0x44]! { return false }
				if C.lseek(fd, -1, C.SEEK_END) != 3 || C.lseek(fd, -2, C.SEEK_CUR) != 1 { return false }
				if C.lseek(fd, i64(1) << 32 | 17, C.SEEK_SET) != i64(1) << 32 | 17 || C.lseek(fd, 1, C.SEEK_SET) != 1 { return false }
			}
		} else if kind != 8 {
			expected := if kind >= 9 { C.EBADF } else { C.ESPIPE }
			for whence in [i32(0), 1, 2, 3, 4]! {
				for offset in [i64(0), i64(1) << 32 | 17, i64(-1), -i64(0x7fffffffffffffff) - 1]! {
					if !refuse(fd, kind, offset, whence, 0x1234567800000000, 0xffffffff00000000, expected, false) { return false }
				}
			}
		}
		return true
	}
}
// Prove the queued bytes and readiness survived every refused seek, then
// replenish the same stable endpoints for the next cohort/cycle.
fn queues(bank &Handles) bool {
	unsafe {
		for kind in 2 .. 8 {
			reader := if kind == 3 { bank.peer[kind] } else { bank.primary[kind] }
			writer := if kind in [3, 4]! { bank.primary[kind] } else { bank.peer[kind] }
			mut queued := i32(-1); mut readiness := C.pollfd{fd: reader, events: i16(C.POLLIN)}
			if C.ioctl(reader, usize(C.FIONREAD), &queued) != 0 || queued != 2 || C.poll(&readiness, 1, 0) != 1 || readiness.revents & i16(C.POLLIN) == 0 { return false }
			mut bytes := [4]u8{}
			if C.read(reader, &bytes[0], 4) != 2 || bytes[0] != 0x41 || bytes[1] != 0x42 { return false }
			e := C.__errno_location(); *e = 0
			if C.read(reader, &bytes[0], 4) != -1 || *e != C.EAGAIN || C.write(writer, &bytes[0], 2) != 2 { return false }
		}
		return true
	}
}
fn storage_cycle(bank &Handles) bool {
	unsafe {
		for kind in 0 .. 12 {
			_, bad := invalid_selectors(bank.primary[kind], i32(kind), false)
			if bad != 0 || !controls(bank.primary[kind], i32(kind)) { return false }
		}
		for kind in [0, 4, 5]! {
			copy := C.dup(bank.primary[kind]); if copy < 0 { return false }
			valid := refuse(copy, i32(kind), -1, -1, 0x1234567800000000, 0xffffffff00000000, C.EINVAL, false)
			if C.close(copy) != 0 || !valid { return false }
		}
		return queues(bank)
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
		for _ in 0 .. 32 { if !storage_cycle(bank) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(bank) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX SEEKERROR SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX SEEKERROR STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := i32(0); mut cases := i32(0)
		mut bank := &Handles(C.alloca(usize(sizeof(Handles)))); *bank = Handles{}
		for index in 0 .. 12 { bank.primary[index] = -1; bank.peer[index] = -1 }
		defer { cleanup(bank) }
		if !prepare(bank) || !queues(bank) { return false }
		for kind in 0 .. 12 {
			mut copies := [i32(-1), i32(-1)]!
			if bank.primary[kind] >= 0 {
				copies[0] = C.dup(bank.primary[kind]); if copies[0] < 0 { return false }
				copies[1] = C.fcntl(bank.primary[kind], C.F_DUPFD_CLOEXEC, 0)
				if copies[1] < 0 { C.close(copies[0]); return false }
			}
			mut valid := true
			for index, fd in [bank.primary[kind], copies[0], copies[1]]! {
				mut before := C.stat{}; mut after := C.stat{}
				if fd >= 0 && C.fstat(fd, &before) != 0 { valid = false }
				count, failures := invalid_selectors(fd, i32(kind), true); cases += count; bad += failures
				if !controls(fd, i32(kind)) { valid = false }
				if fd >= 0 && (C.fstat(fd, &after) != 0 || before.st_mode != after.st_mode || before.st_size != after.st_size || before.st_ino != after.st_ino || before.st_dev != after.st_dev || (C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != if index == 2 { C.FD_CLOEXEC } else { 0 })) { valid = false }
			}
			for fd in copies { if fd >= 0 { C.close(fd) } }
			if !valid || !queues(bank) { return false }
		}
		C.printf(c'LINUX SEEKERROR OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), cases, bad)
		C.printf(c'LINUX SEEKERROR CONTROLS: ordinary=%d descriptors/aliases/metadata/cursors/bytes/queues/readiness PASS\n', i32(ordinary)); C.fflush(nil)
		if bad != 0 || !storage(bank, ordinary) { return false }; C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-seekerror-dir', u32(0o755)) != 0 || C.mkfifo(c'/tmp/linux-seekerror-fifo', u32(0o666)) != 0 || C.chmod(c'/tmp/linux-seekerror-fifo', u32(0o666)) != 0 { return 1 }
		fd := C.open(c'/tmp/linux-seekerror-file', C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666)); if fd < 0 { return 1 }
		mut bytes := [u8(0x41), 0x42, 0x43, 0x44]!
		valid := C.write(fd, &bytes[0], 4) == 4; C.close(fd)
		if !valid || C.chmod(c'/tmp/linux-seekerror-file', u32(0o666)) != 0 { return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX SEEKERROR FAIL: invalid selector precedence or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX SEEKERROR PASS: root/UID1000 invalid selectors return EINVAL before pipe/socket/device type errors; invalid and O_PATH descriptors retain EBADF; ordinary/stream seeks, alias flags, metadata, bytes/cursors/queues/readiness and 200-cycle cleanup stay valid')
		C.puts(c'LINUX SEEKERROR: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
