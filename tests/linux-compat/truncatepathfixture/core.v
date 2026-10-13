// SPDX-License-Identifier: GPL-2.0-or-later
module truncatepathfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_mode u32 st_size i64 st_blocks i64 st_ino u64 st_dev u64 st_uid u32 st_gid u32 }
struct C.pollfd { fd i32 events i16 mut: revents i16 }
struct C.sockaddr_un { mut: sun_family u16 sun_path [108]char }
struct Handles { mut: fds [10]i32 }
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
fn C.truncate(&char, i64) i32
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.fstatat(i32, &char, &C.stat, i32) i32
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.socket(i32, i32, i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strlen(&char) usize
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
		return match kind {
			0 { &char(c'/tmp/linux-truncatepath/normal') }
			1 { &char(c'/tmp/linux-truncatepath/normal-link') }
			2 { &char(c'/tmp/linux-truncatepath/public-dir') }
			3 { &char(c'/tmp/linux-truncatepath/dir-link') }
			4 { &char(c'/tmp/linux-truncatepath/fifo') }
			5 { &char(c'/tmp/linux-truncatepath/fifo-link') }
			6 { &char(c'/dev/null') }
			7 { &char(c'/tmp/linux-truncatepath/null-link') }
			8 { &char(c'/dev/zero') }
			9 { &char(c'/tmp/linux-truncatepath/zero-link') }
			10 { &char(c'/dev/full') }
			11 { &char(c'/tmp/linux-truncatepath/full-link') }
			12 { &char(c'/tmp/linux-truncatepath/private') }
			13 { &char(c'/tmp/linux-truncatepath/private-link') }
			14 { &char(c'/tmp/linux-truncatepath/private-dir') }
			15 { &char(c'/tmp/linux-truncatepath/private-dir-link') }
			16 { &char(c'/tmp/linux-truncatepath/private-fifo') }
			17 { &char(c'/tmp/linux-truncatepath/private-fifo-link') }
			18 { &char(c'/tmp/linux-truncatepath/missing') }
			19 { &char(c'') }
			20 { &char(c'/tmp/linux-truncatepath/loop') }
			21 { &char(usize(1)) }
			22 { &char(c'/tmp/linux-truncatepath/socket') }
			else { &char(c'/tmp/linux-truncatepath/socket-link') }
		}
	}
}
fn restore(fd i32) bool {
	unsafe { mut bytes := [u8(0x41), 0x42, 0x43, 0x44]!; return C.ftruncate(fd, 4) == 0 && C.pwrite(fd, &bytes[0], 4, 0) == 4 }
}
fn cleanup(book &Handles) { unsafe { for fd in book.fds { if fd >= 0 { C.close(fd) } } } }
fn setup(book &Handles) bool {
	unsafe {
		mut bank := &Handles(book)
		if C.mkdir(c'/tmp/linux-truncatepath', u32(0o755)) != 0 { return false }
		for index in 0 .. 2 {
			file_kind := if index == 0 { i32(0) } else { i32(12) }; dir_kind := if index == 0 { i32(2) } else { i32(14) }; fifo_kind := if index == 0 { i32(4) } else { i32(16) }
			mode := if index == 0 { u32(0o666) } else { u32(0o600) }; directory_mode := if index == 0 { u32(0o755) } else { u32(0o700) }
			bank.fds[index] = C.open(pathname(file_kind), C.O_CREAT | C.O_TRUNC | C.O_RDWR, mode)
			if bank.fds[index] < 0 || !restore(bank.fds[index]) || C.chmod(pathname(file_kind), mode) != 0 { return false }
			bank.fds[index + 2] = C.fcntl(bank.fds[index], C.F_DUPFD_CLOEXEC, 0)
			if bank.fds[index + 2] < 0 || C.lseek(bank.fds[index], 2, C.SEEK_SET) != 2 { return false }
			if C.mkfifo(pathname(fifo_kind), mode) != 0 || C.chmod(pathname(fifo_kind), mode) != 0 { return false }
			bank.fds[index + 4] = C.open(pathname(fifo_kind), C.O_RDWR | C.O_NONBLOCK); if bank.fds[index + 4] < 0 { return false }
			if C.mkdir(pathname(dir_kind), directory_mode) != 0 || C.chmod(pathname(dir_kind), directory_mode) != 0 { return false }
			bank.fds[index + 6] = C.open(pathname(dir_kind), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC); if bank.fds[index + 6] < 0 { return false }
		}
		mut address := &C.sockaddr_un(C.alloca(usize(sizeof(C.sockaddr_un)))); *address = C.sockaddr_un{sun_family: u16(C.AF_UNIX)}
		C.memcpy(voidptr(&address.sun_path[0]), c'/tmp/linux-truncatepath/socket', C.strlen(c'/tmp/linux-truncatepath/socket') + 1)
		bank.fds[8] = C.socket(C.AF_UNIX, C.SOCK_DGRAM | C.SOCK_NONBLOCK, 0); if bank.fds[8] < 0 || C.bind(bank.fds[8], voidptr(address), u32(sizeof(C.sockaddr_un))) != 0 { return false }
		bank.fds[9] = C.socket(C.AF_UNIX, C.SOCK_DGRAM | C.SOCK_NONBLOCK, 0); if bank.fds[9] < 0 || C.connect(bank.fds[9], voidptr(address), u32(sizeof(C.sockaddr_un))) != 0 { return false }
		for kind in [i32(1), 3, 5, 7, 9, 11, 13, 15, 17, 20, 23]! {
			target := match kind { 1 { &char(c'normal') } 3 { &char(c'public-dir') } 5 { &char(c'fifo') } 13 { &char(c'private') } 15 { &char(c'private-dir') } 17 { &char(c'private-fifo') } 20 { &char(c'loop') } else { pathname(kind - 1) } }
			if C.symlink(target, pathname(kind)) != 0 { return false }
		}
		mut bytes := [u8(0x41), 0x42]!
		return C.write(bank.fds[4], &bytes[0], 2) == 2 && C.write(bank.fds[5], &bytes[0], 2) == 2 && C.write(bank.fds[9], &bytes[0], 2) == 2
	}
}
fn queues(book &Handles) bool {
	unsafe {
		for slot in [4, 5, 8]! {
			mut available := i32(-1); mut ready := C.pollfd{fd: book.fds[slot], events: i16(C.POLLIN)}
			if C.ioctl(book.fds[slot], usize(C.FIONREAD), &available) != 0 || available != 2 || C.poll(&ready, 1, 0) != 1 || ready.revents & i16(C.POLLIN) == 0 { return false }
		}
		return true
	}
}
fn probe(book &Handles, ordinary bool, kind i32, length i64, raw bool, verbose bool) bool {
	unsafe {
		if !restore(book.fds[0]) || !restore(book.fds[1]) { return false }
		private := kind in [i32(12), 13]!
		observer := book.fds[if private { 1 } else { 0 }]
		path := pathname(kind); mut before := C.stat{}; mut after := C.stat{}
		metadata := kind < 18 || kind >= 22
		if metadata && C.fstatat(C.AT_FDCWD, path, &before, 0) != 0 { return false }
		code := if length < 0 { C.EINVAL } else if kind in [i32(2), 3, 14, 15]! { C.EISDIR }
			else if kind == 18 || kind == 19 { C.ENOENT } else if kind == 20 { C.ELOOP } else if kind == 21 { C.EFAULT }
			else if kind in [i32(0), 1, 12, 13]! { if ordinary && private { C.EACCES } else { 0 } } else { C.EINVAL }
		wanted := if code == 0 { isize(0) } else { isize(-1) }
		// Failed resource hooks must not borrow a previous kernel errno.
		e := C.__errno_location(); *e = 0; seed := C.open(pathname(18), C.O_RDONLY)
		if seed >= 0 { C.close(seed); return false }; if *e != C.ENOENT { return false }; *e = 0
		actual := if raw { C.syscall(isize(C.SYS_truncate), path, length) } else { isize(C.truncate(path, length)) }; actual_code := *e
		mut valid := actual == wanted && actual_code == code
		if metadata {
			if C.fstatat(C.AT_FDCWD, path, &after, 0) != 0 || before.st_mode != after.st_mode || before.st_ino != after.st_ino || before.st_dev != after.st_dev || before.st_uid != after.st_uid || before.st_gid != after.st_gid
				|| after.st_size != if code == 0 { length } else { before.st_size } || (code != 0 && before.st_blocks != after.st_blocks) { valid = false }
			// Observe incorrect baseline metadata changes before restoring repeatability.
			// Correct candidates never resize a refused nonregular pathname.
			if code != 0 && before.st_size != after.st_size { C.truncate(path, before.st_size) }
		}
		mut info := C.stat{}; mut bytes := [64]u8{}
		want_size := if code == 0 { length } else { i64(4) }
		if C.fstat(observer, &info) != 0 || info.st_size != want_size || C.pread(observer, &bytes[0], 64, 0) != isize(want_size) { valid = false }
		for index in 0 .. int(want_size) { if bytes[index] != if index < 4 { u8(0x41 + index) } else { u8(0) } { valid = false } }
		for index in 0 .. 4 { if C.lseek(book.fds[index], 0, C.SEEK_CUR) != 2 { valid = false } }
		for index in 0 .. 10 { if C.fcntl(book.fds[index], C.F_GETFD) & C.FD_CLOEXEC != if index in [2, 3, 6, 7]! { C.FD_CLOEXEC } else { 0 } { valid = false } }
		if !queues(book) { valid = false }
		if !valid && verbose { C.printf(c'LINUX TRUNCATEPATH DETAIL: kind=%d raw=%d length=%ld result=%ld/%d expected=%ld/%d size=%ld/%ld\n', kind, i32(raw), length, actual, actual_code, wanted, code, before.st_size, after.st_size); C.fflush(nil) }
		return valid
	}
}
fn private_permissions(ordinary bool) bool {
	unsafe {
		if ordinary { e := C.__errno_location(); *e = 0; fd := C.open(pathname(12), C.O_RDONLY)
			if fd >= 0 { C.close(fd); return false }; if *e != C.EACCES { return false }
		}
		return true
	}
}
fn storage_cycle(book &Handles, ordinary bool) bool {
	unsafe {
		for kind in 0 .. 24 { if kind == 20 || kind == 21 { continue }; for length in [i64(-1), 0, 3, 8]! {
			if !probe(book, ordinary, i32(kind), length, true, false) { return false }
		} }
		for slot in [0, 1, 4]! {
			copy := C.dup(book.fds[slot]); if copy < 0 { return false }
			mut before := C.stat{}; mut after := C.stat{}
			before_result := C.fstat(copy, &before); actual := C.truncate(pathname(0), 4); after_result := C.fstat(copy, &after); C.close(copy)
			if before_result != 0 || actual != 0 || after_result != 0 || before.st_size != after.st_size || before.st_ino != after.st_ino || before.st_mode != after.st_mode { return false }
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
fn storage(book &Handles, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(book, ordinary) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(book, ordinary) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX TRUNCATEPATH SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX TRUNCATEPATH STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(book &Handles, ordinary bool) bool {
	unsafe {
		defer { cleanup(book) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut cases := i32(0); mut bad := i32(0)
		if !queues(book) || !private_permissions(ordinary) { return false }
		for kind in 0 .. 24 { for length in [i64(0), 1, 3, 4, 8, 64, -1, -i64(0x7fffffffffffffff) - 1]! { for raw in [true, false]! {
			cases++; if !probe(book, ordinary, i32(kind), length, raw, true) { bad++ }
		} } }
		if !restore(book.fds[0]) || !restore(book.fds[1]) || !queues(book) || !private_permissions(ordinary) { return false }
		C.printf(c'LINUX TRUNCATEPATH OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), cases, bad); C.fflush(nil)
		if bad != 0 || !storage(book, ordinary) { return false }
		if !restore(book.fds[0]) || !restore(book.fds[1]) || !queues(book) || !private_permissions(ordinary) { return false }
		for slot in [4, 5, 8]! {
			mut bytes := [4]u8{}; if C.read(book.fds[slot], &bytes[0], 4) != 2 || bytes[0] != 0x41 || bytes[1] != 0x42 { return false }
			writer := if slot == 8 { 9 } else { slot }; if C.write(book.fds[writer], &bytes[0], 2) != 2 { return false }
		}
		C.printf(c'LINUX TRUNCATEPATH CONTROLS: ordinary=%d symlink-targets/shrink/grow/zero-fill/metadata/blocks/flags/aliases/cursors/private/queued-bytes/readiness PASS\n', i32(ordinary)); C.fflush(nil)
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut book := &Handles(C.alloca(usize(sizeof(Handles)))); *book = Handles{}
		for index in 0 .. 10 { book.fds[index] = -1 }; defer { cleanup(book) }
		if !setup(book) { C.puts(c'LINUX TRUNCATEPATH FAIL: setup'); return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(book, ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX TRUNCATEPATH FAIL: pathname type errors or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX TRUNCATEPATH PASS: root/UID1000 raw/musl truncate preserves negative/path-lookup errors, rejects directories with EISDIR and other nonregular targets with EINVAL before policy/growth, follows symlink targets, retains real bytes/metadata/blocks/flags/aliases/cursors/private permissions/queued bytes/readiness, and permits zero-filled regular resizing with flat200-cycle storage')
		C.puts(c'LINUX TRUNCATEPATH: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
