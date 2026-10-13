// SPDX-License-Identifier: GPL-2.0-or-later
module readlinkabifixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_mode u32 st_size i64 st_ino u64 st_dev u64 st_uid u32 st_gid u32 }
struct Handles { mut: fds [6]i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.readlinkat(i32, &char, voidptr, usize) isize
fn C.readlink(&char, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.symlink(&char, &char) i32
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

fn pathname(kind i32, at bool) &char {
	unsafe {
		return if kind == 0 || kind == 2 || kind == 3 { if at && kind == 2 { &char(c'link') } else { &char(c'/tmp/linux-readlinkabi/link') } }
			else if kind == 1 { &char(c'/tmp/linux-readlinkabi/dangling') }
			else if kind == 4 { &char(c'/tmp/linux-readlinkabi/missing') }
			else if kind == 5 { &char(c'') }
			else if kind == 6 { &char(c'/tmp/linux-readlinkabi/file') }
			else if kind == 7 { &char(c'/tmp/linux-readlinkabi') }
			else if kind == 8 { &char(usize(1)) }
			else if kind == 9 { &char(nil) }
			else if kind == 10 { &char(c'/tmp/linux-readlinkabi/private/link') }
			else if kind == 11 { &char(c'/proc/self') }
			else if kind == 12 { &char(c'/proc/self/exe') }
			else if kind == 13 || kind == 14 { if at { &char(c'link') } else { &char(c'/tmp/linux-readlinkabi/link') } }
			else { &char(c'/tmp/linux-readlinkabi/loop/child') }
	}
}
fn at_form(form i32) bool { return form < 2 }
fn prepare(bank &Handles) bool {
	unsafe {
		mut handles := &Handles(bank)
		handles.fds[0] = C.open(c'/tmp/linux-readlinkabi/file', C.O_RDONLY)
		if handles.fds[0] < 0 { return false }
		handles.fds[2] = C.open(c'/tmp/linux-readlinkabi', C.O_PATH | C.O_DIRECTORY)
		if handles.fds[2] < 0 { return false }
		handles.fds[4] = C.open(c'/tmp/linux-readlinkabi/link', C.O_PATH | C.O_NOFOLLOW)
		if handles.fds[4] < 0 { return false }
		for index in [0, 2, 4]! {
			handles.fds[index + 1] = C.fcntl(handles.fds[index], C.F_DUPFD_CLOEXEC, 0)
			if handles.fds[index + 1] < 0 { return false }
		}
		return C.lseek(handles.fds[0], 2, C.SEEK_SET) == 2
	}
}
fn cleanup(bank &Handles) { unsafe { for fd in bank.fds { if fd >= 0 { C.close(fd) } } } }
fn controls(bank &Handles, ordinary bool) bool {
	unsafe {
		mut bytes := [4]u8{}
		if C.pread(bank.fds[0], &bytes[0], 4, 0) != 4 || bytes != [u8(0x41), 0x42, 0x43, 0x44]!
			|| C.lseek(bank.fds[0], 0, C.SEEK_CUR) != 2 || C.lseek(bank.fds[1], 0, C.SEEK_CUR) != 2 { return false }
		for index in 0 .. 6 {
			if C.fcntl(bank.fds[index], C.F_GETFD) & C.FD_CLOEXEC != if index % 2 == 1 { C.FD_CLOEXEC } else { 0 } { return false }
			mut info := C.stat{}; if C.fstat(bank.fds[index], &info) != 0 { return false }
			if index < 2 && (info.st_size != 4 || info.st_mode & u32(C.S_IFMT) != u32(C.S_IFREG)) { return false }
			if index in [2, 3]! && info.st_mode & u32(C.S_IFMT) != u32(C.S_IFDIR) { return false }
			if index >= 4 && (info.st_size != 11 || info.st_mode & u32(C.S_IFMT) != u32(C.S_IFLNK)) { return false }
		}
		if ordinary {
			e := C.__errno_location(); *e = 0
			fd := C.open(c'/tmp/linux-readlinkabi/private/link', C.O_PATH | C.O_NOFOLLOW)
			if fd >= 0 { C.close(fd); return false }; if *e != C.EACCES { return false }
		}
		return true
	}
}
fn probe(bank &Handles, kind i32, word u64, destination i32, form i32, ordinary bool, verbose bool) bool {
	unsafe {
		at := at_form(form)
		path := pathname(kind, at)
		dirfd := if kind == 2 { bank.fds[2] } else if kind == 3 || kind == 13 { i32(-1) } else if kind == 14 { bank.fds[0] } else { i32(C.AT_FDCWD) }
		mut bytes := [64]u8{}; for index in 0 .. 64 { bytes[index] = 0x5a }
		buf := if destination == 0 { voidptr(&bytes[0]) } else if destination == 1 { voidptr(nil) } else { voidptr(usize(1)) }
		size := i32(u32(word))
		mut target := [64]char{}
		length := if kind == 1 { C.snprintf(&target[0], 64, c'missing-target') }
			else if kind == 11 { C.snprintf(&target[0], 64, c'/proc/%d', C.getpid()) }
			else if kind == 12 { C.snprintf(&target[0], 64, c'/sbin/init') }
			else { C.snprintf(&target[0], 64, c'destination') }
		if length <= 0 || length >= 64 { return false }
		// musl substitutes a one-byte scratch buffer for an exact zero size.
		// The raw ABI still rejects zero before lookup or buffer access.
		libc_zero := word == 0 && form in [i32(1), 2]!
		expected := if size <= 0 && !libc_zero { C.EINVAL }
			else if kind in [i32(4), 5]! { C.ENOENT }
			else if kind in [i32(6), 7]! { C.EINVAL }
			else if kind in [i32(8), 9]! { C.EFAULT }
			else if kind == 10 && ordinary { C.EACCES }
			else if kind == 13 && at { C.EBADF }
			else if kind == 14 && at { C.ENOTDIR }
			else if kind == 15 { C.ELOOP }
			else if destination != 0 && !libc_zero { C.EFAULT } else { 0 }
		copied := if size < length { size } else { length }
		wanted := if expected != 0 { isize(-1) } else { isize(copied) }
		e := C.__errno_location(); *e = 0
		mut actual := isize(-2)
		if form == 0 { actual = C.syscall(isize(C.SYS_readlinkat), dirfd, path, buf, word) }
		else if form == 1 { actual = C.readlinkat(dirfd, path, buf, usize(word)) }
		else if form == 2 { actual = C.readlink(path, buf, usize(word)) }
		else { $if amd64 { actual = C.syscall(isize(C.SYS_readlink), path, buf, word) } }
		code := *e; mut valid := actual == wanted && code == expected
		for index in 0 .. 64 {
			byte := if expected == 0 && index < copied { u8(target[index]) } else { u8(0x5a) }
			if bytes[index] != byte { valid = false }
		}
		if !valid && verbose { C.printf(c'LINUX READLINKABI DETAIL: ordinary=%d kind=%d form=%d dest=%d word=%016lx result=%ld/%d expected=%ld/%d\n', i32(ordinary), kind, form, destination, word, actual, code, wanted, expected); C.fflush(nil) }
		return valid
	}
}
fn storage_cycle(bank &Handles, ordinary bool) bool {
	unsafe {
		for kind in [i32(0), 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14]! {
			for word in [u64(0), 1, 0x100000001, 0xffffffff]! {
				if !probe(bank, kind, word, i32(kind % 2), 0, ordinary, false) { return false }
			}
		}
		copy := C.dup(bank.fds[2]); if copy < 0 { return false }
		mut bytes := [4]u8{}; e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(C.SYS_readlinkat), copy, c'link', &bytes[0], u64(0xdeadbeef00000003)); code := *e
		C.close(copy)
		return actual == 3 && code == 0 && bytes == [u8(`d`), `e`, `s`, 0]! && controls(bank, ordinary)
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
			C.printf(c'LINUX READLINKABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX READLINKABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut cases := i32(0); mut bad := i32(0)
		mut bank := &Handles(C.alloca(usize(sizeof(Handles)))); *bank = Handles{}
		for index in 0 .. 6 { bank.fds[index] = -1 }; defer { cleanup(bank) }
		if !prepare(bank) || !controls(bank, ordinary) { return false }
		words := [u64(0), 1, 3, 11, 14, 64, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0x100000001, 0x8000000000000003, 0xffffffff00000040, 0xdeadbeef80000000, 0xffffffffffffffff]!
		mut forms := 3; $if amd64 { forms = 4 }
		for kind in 0 .. 16 { for word in words { for destination in 0 .. 3 { for form in 0 .. forms {
			cases++; if !probe(bank, i32(kind), word, i32(destination), i32(form), ordinary, true) { bad++ }
		} } } }
		C.printf(c'LINUX READLINKABI OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), cases, bad); C.fflush(nil)
		if bad != 0 || !storage(bank, ordinary) || !controls(bank, ordinary) { return false }
		C.printf(c'LINUX READLINKABI CONTROLS: ordinary=%d target-prefix/no-NUL/canaries/aliases/metadata/bytes/cursors/flags/private PASS\n', i32(ordinary)); C.fflush(nil)
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-readlinkabi', u32(0o755)) != 0 || C.mkdir(c'/tmp/linux-readlinkabi/private', u32(0o700)) != 0
			|| C.symlink(c'destination', c'/tmp/linux-readlinkabi/link') != 0
			|| C.symlink(c'missing-target', c'/tmp/linux-readlinkabi/dangling') != 0
			|| C.symlink(c'destination', c'/tmp/linux-readlinkabi/private/link') != 0
			|| C.symlink(c'loop', c'/tmp/linux-readlinkabi/loop') != 0 { return 1 }
		fd := C.open(c'/tmp/linux-readlinkabi/file', C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o644)); if fd < 0 { return 1 }
		mut bytes := [u8(0x41), 0x42, 0x43, 0x44]!
		ready := C.write(fd, &bytes[0], 4) == 4; C.close(fd)
		if !ready || C.chmod(c'/tmp/linux-readlinkabi/private', u32(0o700)) != 0 { return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX READLINKABI FAIL: native signed size or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX READLINKABI PASS: native raw/musl readlinkat and readlink consume signed32 sizes, return EINVAL before path/fd/destination lookup for nonpositive sizes, preserve positive target-prefix/no-NUL/canaries and real lookup/type/permission/copy errors, retain aliases/metadata/bytes/cursors/flags/private permissions, and keep200-cycle storage flat')
		C.puts(c'LINUX READLINKABI: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
