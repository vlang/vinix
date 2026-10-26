// SPDX-License-Identifier: GPL-2.0-or-later
module fixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

struct C.stat { st_mode u32 st_size i64 }
struct CloneArgs {
	flags u64
	pidfd u64
	child_tid u64
	parent_tid u64
	exit_signal u64
	stack u64
	stack_size u64
	tls u64
	set_tid u64
	set_tid_size u64
	cgroup u64
}
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.fstat(i32, &C.stat) i32
fn C.ftruncate(i32, i64) i32
fn C.readlink(&char, &char, usize) isize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.syscall(isize, ...) isize
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn check(ok bool, label &char) bool {
	if ok { return true }
	unsafe { C.printf(c'PROCFS OVERFLOW FAIL: %s errno=%d\n', label, *C.__errno_location()) }
	C.fflush(unsafe { nil })
	return false
}

fn readable(path &char) bool {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if !check(fd >= 0, c'open value') { return false }
		defer { C.close(fd) }
		mut info := C.stat{}
		if !check(C.fstat(fd, &info) == 0 && info.st_mode & 0o177777 == 0o100444
			&& info.st_size == 6, c'regular file mode 0444 and size 6') { return false }
		mut data := [8]u8{}
		for index in 0 .. 6 {
			if !check(C.read(fd, &data[index], 1) == 1, c'byte reads') { return false }
		}
		if !check(C.memcmp(&data[0], c'65534\n', 6) == 0
			&& C.read(fd, &data[6], 1) == 0 && C.lseek(fd, 0, C.SEEK_CUR) == 6,
			c'exact value and EOF') { return false }
		if !check(C.lseek(fd, 1, C.SEEK_SET) == 1 && C.pread(fd, &data[0], 3, 2) == 3
			&& C.memcmp(&data[0], c'534', 3) == 0 && C.lseek(fd, 0, C.SEEK_CUR) == 1,
			c'pread partial preserves shared offset') { return false }
		if !check(C.pread(fd, &data[0], 1, 6) == 0
			&& C.lseek(fd, -1, C.SEEK_END) == 5 && C.read(fd, &data[0], 2) == 1
			&& data[0] == `\n` && C.lseek(fd, -3, C.SEEK_CUR) == 3
			&& C.read(fd, &data[0], 3) == 3 && C.memcmp(&data[0], c'34\n', 3) == 0,
			c'pread EOF and seek SET/CUR/END') { return false }
		return true
	}
}

fn rejects_descriptor(fd i32) bool {
	unsafe {
		result := C.write(fd, c'0\n', 2)
		code := *C.__errno_location()
		if !check(result == -1 && code == C.EPERM, c'write denied by content policy') { return false }
		positioned := C.pwrite(fd, c'12345\n', 6, 0)
		positioned_code := *C.__errno_location()
		if !check(positioned == -1 && positioned_code == C.EPERM,
			c'pwrite denied by content policy') { return false }
		truncated := C.ftruncate(fd, 0)
		truncate_code := *C.__errno_location()
		return check(truncated == -1 && truncate_code == C.EPERM,
			c'ftruncate denied by content policy')
	}
}

fn guards(ordinary bool) bool {
	unsafe {
		names := [&char(c'/proc/self/ns/user'), &char(c'/proc/self/ns/net'), &char(c'/proc/self/ns/uts')]!
		mut original := [3][64]u8{}
		mut sizes := [3]isize{}
		for i in 0 .. names.len {
			sizes[i] = C.readlink(names[i], &char(&original[i][0]), 64)
			if !check(sizes[i] > 0, c'read namespace identity') { return false }
		}
		for flag in [u64(0x10000000), 0x40000000]! {
			for request in [flag, flag | u64(0x04000000)]! {
				if !check(C.syscall(isize(C.SYS_unshare), request) == -1
					&& *C.__errno_location() == C.EINVAL, c'unsupported user/net unshare remains rejected') { return false }
				args := CloneArgs{flags: request, exit_signal: 17}
				// clone3 checks the caller's mount/network namespace privilege
				// before the shared unsupported-flags gate for non-user requests.
				expected := if ordinary && flag == u64(0x40000000) { C.EPERM } else { C.EINVAL }
				if !check(C.syscall(isize(C.SYS_clone3), &args, usize(sizeof(CloneArgs))) == -1
					&& *C.__errno_location() == expected, c'unsupported user/net clone3 remains rejected') { return false }
			}
			if !check(C.syscall(isize(C.SYS_clone), flag | u64(17), voidptr(nil), voidptr(nil), voidptr(nil), voidptr(nil)) == -1
				&& *C.__errno_location() == C.EINVAL, c'unsupported user/net clone remains rejected') { return false }
		}
		for i in 0 .. names.len {
			mut current := [64]u8{}
			size := C.readlink(names[i], &char(&current[0]), 64)
			if !check(size == sizes[i] && C.memcmp(&current[0], &original[i][0], usize(size)) == 0,
				c'rejected namespace operations preserve identities') { return false }
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if !check(C.getuid() == 0 && C.getgid() == 0, c'initial privileged identity') { return 1 }
		paths := [&char(c'/proc/sys/kernel/overflowuid'), &char(c'/proc/sys/kernel/overflowgid')]!
		mut retained := [2]i32{}
		for i in 0 .. paths.len {
			if !readable(paths[i]) { return 1 }
			retained[i] = C.open(paths[i], C.O_WRONLY)
			if !check(retained[i] >= 0, c'privileged writable descriptor')
				|| !rejects_descriptor(retained[i]) { return 1 }
			truncated := C.open(paths[i], C.O_WRONLY | C.O_TRUNC)
			code := *C.__errno_location()
			if truncated >= 0 { C.close(truncated) }
			if !check(truncated == -1 && code == C.EPERM, c'privileged O_TRUNC rejected') { return 1 }
		}
		for _ in 0 .. 200 { for path in paths { if !readable(path) { return 1 } } }
		if !guards(false) { return 1 }
		C.puts(c'PROCFS OVERFLOW: root reads/writes/truncation/repeat/namespace guards PASS')
		if !check(C.setgroups(0, nil) == 0 && C.setgid(10000) == 0 && C.setuid(10000) == 0
			&& C.getuid() == 10000 && C.getgid() == 10000, c'drop to application UID10000') { return 1 }
		for i in 0 .. paths.len {
			writable := C.open(paths[i], C.O_WRONLY)
			code := *C.__errno_location()
			if writable >= 0 { C.close(writable) }
			if !check(writable == -1 && code == C.EACCES, c'application writable open denied by mode')
				|| !rejects_descriptor(retained[i]) || C.close(retained[i]) != 0 { return 1 }
		}
		for _ in 0 .. 200 { for path in paths { if !readable(path) { return 1 } } }
		if !guards(true) { return 1 }
		C.puts(c'PROCFS OVERFLOW: UID10000 reads/writes/retained descriptors/repeat/namespace guards PASS')
		C.puts(c'PROCFS OVERFLOW: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
