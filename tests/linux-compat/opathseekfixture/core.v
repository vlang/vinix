// SPDX-License-Identifier: GPL-2.0-or-later
module opathseekfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Object { path &char kind u32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct C.stat { st_mode u32 st_size i64 st_ino u64 st_dev u64 }
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
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.symlink(&char, &char) i32
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

fn object(index i32) Object {
	return match index {
		0 { Object{&char(c'/tmp/linux-opathseek/normal'), u32(C.S_IFREG)} }
		1 { Object{&char(c'/tmp/linux-opathseek/secret'), u32(C.S_IFREG)} }
		2 { Object{&char(c'/tmp/linux-opathseek'), u32(C.S_IFDIR)} }
		3 { Object{&char(c'/tmp/linux-opathseek/fifo'), u32(C.S_IFIFO)} }
		4 { Object{&char(c'/tmp/linux-opathseek/link'), u32(C.S_IFLNK)} }
		else { Object{&char(c'/dev/null'), u32(C.S_IFCHR)} }
	}
}
fn refuse(fd i32, offset i64, whence i32, verbose bool) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(C.SYS_lseek), isize(fd), offset, isize(whence)); code := *e
		valid := actual == -1 && code == C.EBADF
		if !valid && verbose { C.printf(c'LINUX OPATHSEEK DETAIL: offset=%ld whence=%d result=%ld/%d expected=-1/9\n', offset, whence, actual, code); C.fflush(nil) }
		return valid
	}
}
fn metadata(fd i32, object Object, original &C.stat) bool {
	unsafe {
		mut current := C.stat{}
		return C.fstat(fd, &current) == 0 && current.st_mode & u32(C.S_IFMT) == object.kind
			&& current.st_ino == original.st_ino && current.st_dev == original.st_dev && current.st_size == original.st_size
			&& C.fcntl(fd, C.F_GETFL) & C.O_PATH != 0
	}
}
fn ordinary_seeks(ordinary bool) bool {
	unsafe {
		fd := C.open(c'/tmp/linux-opathseek/normal', C.O_RDWR); if fd < 0 { return false }; defer { C.close(fd) }
		for position in [i64(0), 1, i64(1) << 32 | 17, i64(1) << 33 | 31]! {
			if C.lseek(fd, position, C.SEEK_SET) != position || C.lseek(fd, 0, C.SEEK_CUR) != position { return false }
		}
		if C.lseek(fd, -1, C.SEEK_END) != 3 || C.lseek(fd, -2, C.SEEK_CUR) != 1 { return false }
		e := C.__errno_location(); *e = 0
		if C.lseek(fd, -1, C.SEEK_SET) != -1 || *e != C.EINVAL || C.lseek(fd, 0, C.SEEK_CUR) != 1 { return false }
		*e = 0
		if C.lseek(fd, 0, 0x7fffffff) != -1 || *e != C.EINVAL || C.lseek(fd, 0, C.SEEK_CUR) != 1 { return false }
		mut bytes := [4]u8{}
		if C.pread(fd, &bytes[0], 4, 0) != 4 || bytes[0] != 0x41 || bytes[1] != 0x42 || bytes[2] != 0x43 || bytes[3] != 0x44 { return false }
		if ordinary {
			*e = 0; denied := C.open(c'/tmp/linux-opathseek/secret', C.O_RDONLY)
			if denied >= 0 { C.close(denied); return false }; if *e != C.EACCES { return false }
		}
		if !refuse(-1, -1, -1, false) { return false }
		C.printf(c'LINUX OPATHSEEK CONTROLS: ordinary=%d normal/sparse/negative/invalid/private/metadata PASS\n', i32(ordinary)); C.fflush(nil)
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
fn storage_cycle(fds &i32) bool {
	unsafe {
		for index in 0 .. 12 {
			for offset in [i64(0), 1, 64, i64(1) << 32 | 17, i64(-1), -i64(0x7fffffffffffffff) - 1]! {
				for whence in [i32(0), 1, 2, 3, 4, 0x7fffffff, -1]! { if !refuse(fds[index], offset, whence, false) { return false } }
			}
		}
		for index in 0 .. 6 {
			copy := C.dup(fds[index * 2]); if copy < 0 { return false }
			valid := refuse(copy, -1, -1, false); if C.close(copy) != 0 || !valid { return false }
		}
		return true
	}
}
fn storage(ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		mut fds := [12]i32{}; mut opened := 0; defer { for index in 0 .. opened { C.close(fds[index]) } }
		for index in 0 .. 6 {
			item := object(i32(index)); fds[opened] = C.open(item.path, C.O_PATH | C.O_NOFOLLOW); if fds[opened] < 0 { return false }; opened++
			fds[opened] = C.dup(fds[opened - 1]); if fds[opened] < 0 { return false }; opened++
		}
		for _ in 0 .. 32 { if !storage_cycle(&fds[0]) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(&fds[0]) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX OPATHSEEK SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX OPATHSEEK STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := 0; mut cases := 0
		for index in 0 .. 6 {
			item := object(i32(index))
			for extras in [i32(0), C.O_RDWR, C.O_WRONLY | C.O_TRUNC, C.O_APPEND | C.O_NONBLOCK | C.O_CLOEXEC]! {
				fd := C.open(item.path, C.O_PATH | C.O_NOFOLLOW | extras); if fd < 0 { return false }
				copy := C.dup(fd); if copy < 0 { C.close(fd); return false }
				copy_cloexec := C.fcntl(fd, C.F_DUPFD_CLOEXEC, 0); if copy_cloexec < 0 { C.close(copy); C.close(fd); return false }
				mut original := C.stat{}; mut meta_valid := C.fstat(fd, &original) == 0
				for handle in [fd, copy, copy_cloexec]! {
					if !metadata(handle, item, &original) { meta_valid = false }
					for offset in [i64(0), 1, 64, i64(1) << 32 | 17, i64(-1), -i64(0x7fffffffffffffff) - 1]! {
						for whence in [i32(0), 1, 2, 3, 4, 0x7fffffff, -1]! { cases++; if !refuse(handle, offset, whence, offset == 0 && whence == 0) { bad++ } }
					}
					if !metadata(handle, item, &original) { meta_valid = false }
				}
				if C.fcntl(copy, C.F_GETFD) & C.FD_CLOEXEC != 0 || C.fcntl(copy_cloexec, C.F_GETFD) & C.FD_CLOEXEC == 0 { meta_valid = false }
				C.close(copy_cloexec); C.close(copy); C.close(fd); if !meta_valid { return false }
			}
		}
		C.printf(c'LINUX OPATHSEEK OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), i32(cases), i32(bad)); C.fflush(nil)
		if !ordinary_seeks(ordinary) || bad != 0 || !storage(ordinary) { return false }; C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-opathseek', u32(0o755)) != 0 || C.mkfifo(c'/tmp/linux-opathseek/fifo', u32(0o666)) != 0 || C.symlink(c'secret', c'/tmp/linux-opathseek/link') != 0 { return 1 }
		for path in [&char(c'/tmp/linux-opathseek/normal'), &char(c'/tmp/linux-opathseek/secret')]! {
			fd := C.open(path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666)); if fd < 0 { return 1 }
			mut data := [u8(0x41), 0x42, 0x43, 0x44]!
			valid := C.write(fd, &data[0], 4) == 4; C.close(fd); if !valid { return 1 }
		}
		if C.chmod(c'/tmp/linux-opathseek/normal', u32(0o666)) != 0 || C.chmod(c'/tmp/linux-opathseek/secret', u32(0o600)) != 0 { return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX OPATHSEEK FAIL: pathname seek access or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX OPATHSEEK PASS: root/UID1000 O_PATH lseek rejects files/private files/directories/FIFOs/unfollowed symlinks/devices and aliases before offset/whence/type errors; metadata/duplication/private permissions and ordinary sparse/relative seeks remain usable; 200-cycle seek/alias cleanup retains flat storage')
		C.puts(c'LINUX OPATHSEEK: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
