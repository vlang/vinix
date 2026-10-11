// SPDX-License-Identifier: GPL-2.0-or-later
module openfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>

struct How { mut: flags u64 mode u64 resolve u64 extra u64 }
struct C.stat { st_mode u32 }
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.close(i32) i32
fn C.open(&char, i32, ...) i32
fn C.mkdir(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.fstat(i32, &C.stat) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.fcntl(i32, i32, ...) i32
fn C.pipe(&i32) i32
fn C.getpid() i32
fn C.access(&char, i32) i32
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn open_result(path &char, how voidptr, size usize, expected i32) bool {
	return open_at_result(C.AT_FDCWD, path, how, size, expected)
}

fn open_at_result(dirfd i32, path &char, how voidptr, size usize, expected i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_openat2), isize(dirfd), path, how, isize(size))
		actual_errno := *errno_ptr
		valid := if expected == 0 { result >= 0 } else { result == -1 && actual_errno == expected }
		if result >= 0 { C.close(i32(result)) }
		if !valid { C.printf(c'LINUX OPEN FAIL: dirfd=%d path=%s result=%ld errno=%d expected=%d\n', dirfd, path, result, actual_errno, expected) }
		return valid
	}
}

fn mount_constraints() bool {
	unsafe {
		if C.mkdir(c'/tmp/linux-open-mount', u32(0o700)) != 0
			|| C.mkdir(c'/tmp/linux-open-bind', u32(0o700)) != 0
			|| C.mount(c'tmpfs', c'/tmp/linux-open-mount', c'tmpfs', 0, nil) != 0
			|| C.mount(c'/tmp/linux-open-dir', c'/tmp/linux-open-bind', nil, usize(C.MS_BIND), nil) != 0
			|| C.symlink(c'/tmp/linux-open-target', c'/tmp/linux-open-dir/outside') != 0 { return false }
		fd := C.open(c'/tmp/linux-open-bind', C.O_PATH | C.O_DIRECTORY)
		mountfd := C.open(c'/tmp/linux-open-mount', C.O_PATH | C.O_DIRECTORY)
		if fd < 0 || mountfd < 0 { return false }
		mut how := How{resolve: 1}
		ok := open_result(c'/tmp/linux-open-target', &how, 24, 0)
			&& open_result(c'/tmp/linux-open-mount', &how, 24, C.EXDEV)
			&& open_result(c'/tmp/linux-open-bind/new', &how, 24, C.EXDEV)
			&& open_at_result(fd, c'new', &how, 24, 0)
			&& open_at_result(fd, c'../linux-open-target', &how, 24, C.EXDEV)
			&& open_at_result(fd, c'outside', &how, 24, C.EXDEV)
			&& open_at_result(mountfd, c'.', &how, 24, 0)
			&& open_at_result(mountfd, c'..', &how, 24, C.EXDEV)
		how = How{resolve: 7}
		combined := open_result(c'/tmp/linux-open-target', &how, 24, 0)
			&& open_result(c'/tmp/linux-open-bind', &how, 24, C.EXDEV)
		how = How{flags: u64(C.O_CREAT | C.O_RDWR), mode: 0o600, resolve: 1}
		created := open_at_result(mountfd, c'inside', &how, 24, 0)
			&& open_result(c'/tmp/linux-open-mount/escape', &how, 24, C.EXDEV)
			&& C.access(c'/tmp/linux-open-mount/escape', C.F_OK) == -1
			&& *C.__errno_location() == C.ENOENT
		mut proc_path := [64]u8{}
		C.snprintf(&char(&proc_path[0]), usize(proc_path.len), c'/proc/%d/fd', C.getpid())
		procfd := C.open(&char(&proc_path[0]), C.O_PATH | C.O_DIRECTORY)
		C.snprintf(&char(&proc_path[0]), usize(proc_path.len), c'%d', fd)
		how = How{resolve: 1}
		magic := procfd >= 0 && open_at_result(procfd, &char(&proc_path[0]), &how, 24, C.EXDEV)
		how.flags = u64(C.O_PATH | C.O_NOFOLLOW)
		link_only := procfd >= 0 && open_at_result(procfd, &char(&proc_path[0]), &how, 24, 0)
		if procfd >= 0 { C.close(procfd) }
		C.close(fd); C.close(mountfd)
		return ok && combined && created && magic && link_only
	}
}

fn link_descriptor(path &char, via_openat2 bool, resolve u64) bool {
	unsafe {
		how := How{flags: u64(C.O_PATH | C.O_NOFOLLOW), resolve: resolve}
		fd := if via_openat2 {
			i32(C.syscall(isize(C.SYS_openat2), isize(C.AT_FDCWD), path, &how, isize(24)))
		} else { C.open(path, C.O_PATH | C.O_NOFOLLOW) }
		if fd < 0 { C.puts(c'LINUX OPEN FAIL: link descriptor'); return false }
		mut info := C.stat{}
		mut byte := u8(0)
		ok := C.fstat(fd, &info) == 0 && info.st_mode & u32(C.S_IFMT) == u32(C.S_IFLNK)
			&& C.read(fd, &byte, 1) == -1 && *C.__errno_location() == C.EBADF
		C.close(fd)
		if !ok { C.puts(c'LINUX OPEN FAIL: link inode or descriptor access') }
		return ok
	}
}

fn link_constraints(pipe_fd i32) bool {
	unsafe {
		mut how := How{resolve: 2}
		if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, 0)
			|| !open_result(c'/proc/self/status', &how, 24, 0) { return false }
		for constraint in [u64(2), 4, 6]! {
			how = How{resolve: constraint}
			if !open_result(c'/tmp/linux-open-target', &how, 24, 0)
				|| !open_result(c'/proc/self/exe', &how, 24, C.ELOOP)
				|| !open_result(c'/proc/self/cwd/linux-open-target', &how, 24, C.ELOOP)
				|| !open_result(c'/proc/self/ns/mnt', &how, 24, C.ELOOP) { return false }
			mut magic_path := [64]u8{}
			C.snprintf(&char(&magic_path[0]), usize(magic_path.len), c'/proc/%d/exe', C.getpid())
			if !link_descriptor(&char(&magic_path[0]), true, constraint) { return false }
			C.snprintf(&char(&magic_path[0]), usize(magic_path.len), c'/proc/%d/fd/%d', C.getpid(), pipe_fd)
			if !open_result(&char(&magic_path[0]), &how, 24, C.ELOOP)
				|| !link_descriptor(&char(&magic_path[0]), true, constraint) { return false }
			if constraint & 4 != 0 {
				if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, C.ELOOP)
					|| !open_result(c'/tmp/linux-open-dangling', &how, 24, C.ELOOP)
					|| !link_descriptor(c'/tmp/linux-open-dangling', true, constraint) { return false }
			}
		}
		if C.symlink(c'/proc/self/exe', c'/tmp/linux-open-magic') != 0 { return false }
		how = How{resolve: 2}
		if !open_result(c'/tmp/linux-open-magic', &how, 24, C.ELOOP) { return false }
		how = How{flags: u64(C.O_CREAT | C.O_RDWR), mode: 0o600, resolve: 4}
		if !open_result(c'/tmp/linux-open-dir/new', &how, 24, 0)
			|| !open_result(c'/tmp/linux-open-dir/link/linux-open-escape', &how, 24, C.ELOOP)
			|| C.access(c'/tmp/linux-open-escape', C.F_OK) != -1
			|| *C.__errno_location() != C.ENOENT { return false }
		return true
	}
}

fn trailing_slashes() bool {
	unsafe {
		mut how := How{}
		for flags in [u64(0), u64(C.O_PATH | C.O_NOFOLLOW)]! {
			how = How{flags: flags}
			if !open_result(c'/tmp/linux-open-target/', &how, 24, C.ENOTDIR)
				|| !open_result(c'/tmp/linux-open-dir/link/', &how, 24, 0)
				|| !open_result(c'/tmp/linux-open-dangling/', &how, 24, C.ENOENT) { return false }
		}
		how.resolve = 4
		if !open_result(c'/tmp/linux-open-dir/link/', &how, 24, C.ELOOP) { return false }
		how = How{flags: u64(C.O_CREAT | C.O_RDWR), mode: 0o600}
		if !open_result(c'/tmp/linux-open-created-slash/', &how, 24, C.EISDIR)
			|| !open_result(c'/tmp/linux-open-missing-prefix/child/', &how, 24, C.ENOENT)
			|| C.access(c'/tmp/linux-open-created-slash', C.F_OK) != -1
			|| *C.__errno_location() != C.ENOENT { return false }
		fd := C.open(c'/tmp/linux-open-dir/link/', C.O_PATH | C.O_NOFOLLOW)
		mut info := C.stat{}
		ok := fd >= 0 && C.fstat(fd, &info) == 0 && info.st_mode & u32(C.S_IFMT) == u32(C.S_IFDIR)
		if fd >= 0 { C.close(fd) }
		return ok
	}
}

fn exclusive_creation() bool {
	unsafe {
		for constraint in [u64(0), 2, 4, 6]! {
			how := How{flags: u64(C.O_CREAT | C.O_EXCL | C.O_RDWR), mode: 0o600, resolve: constraint}
			if !open_result(c'/tmp/linux-open-target', &how, 24, C.EEXIST)
				|| !open_result(c'/tmp/linux-open-dangling', &how, 24, C.EEXIST)
				|| !open_result(c'/tmp/linux-open-dir/link', &how, 24, C.EEXIST) { return false }
		}
		fd := C.open(c'/tmp/linux-open-dangling', C.O_CREAT | C.O_EXCL | C.O_RDWR, u32(0o600))
		if fd >= 0 { C.close(fd); return false }
		return *C.__errno_location() == C.EEXIST
			&& C.access(c'/tmp/linux-open-missing', C.F_OK) == -1
			&& *C.__errno_location() == C.ENOENT
	}
}

fn path_flags() bool {
	unsafe {
		file := C.open(c'/tmp/linux-open-path-flags', C.O_CREAT | C.O_RDWR, u32(0o600))
		if file < 0 { return false }
		written := C.write(file, c'kept', 4)
		C.close(file)
		if written != 4 { return false }
		pathfd := C.open(c'/tmp/linux-open-path-flags', C.O_PATH | C.O_CLOEXEC
			| C.O_CREAT | C.O_EXCL | C.O_TRUNC | C.O_WRONLY, u32(0o600))
		if pathfd < 0 { return false }
		mut byte := u8(0)
		ok := C.fcntl(pathfd, C.F_GETFL) == C.O_PATH
			&& C.fcntl(pathfd, C.F_GETFD) == C.FD_CLOEXEC
			&& C.read(pathfd, &byte, 1) == -1 && *C.__errno_location() == C.EBADF
		C.close(pathfd)
		if !ok { return false }
		readfd := C.open(c'/tmp/linux-open-path-flags', C.O_RDONLY)
		if readfd < 0 { return false }
		mut content := [4]u8{}
		length := C.read(readfd, &content[0], content.len)
		C.close(readfd)
		if length != 4 || content != [u8(`k`), `e`, `p`, `t`]! { return false }
		dirfd := C.open(c'/tmp/linux-open-dir', C.O_PATH | C.O_RDWR | C.O_TRUNC)
		if dirfd < 0 { return false }
		C.close(dirfd)
		missing := C.open(c'/tmp/linux-open-path-missing', C.O_PATH | C.O_CREAT, u32(0o600))
		if missing >= 0 { C.close(missing); return false }
		if *C.__errno_location() != C.ENOENT { return false }
		for ignored in [C.O_CREAT, C.O_EXCL, C.O_TRUNC, C.O_WRONLY, C.O_RDWR]! {
			how := How{flags: u64(C.O_PATH | ignored)}
			if !open_result(c'/tmp/linux-open-path-flags', &how, 24, C.EINVAL) { return false }
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/tmp/linux-open-target', C.O_CREAT | C.O_RDWR, u32(0o600))
		if fd < 0 { C.puts(c'LINUX OPEN FAIL: create'); return 1 }
		C.close(fd)
		if C.mkdir(c'/tmp/linux-open-dir', u32(0o700)) != 0
			|| C.symlink(c'/tmp', c'/tmp/linux-open-dir/link') != 0
			|| C.symlink(c'/tmp/linux-open-missing', c'/tmp/linux-open-dangling') != 0 { return 1 }
		for via_openat2 in [false, true]! {
			if !link_descriptor(c'/tmp/linux-open-dir/link', via_openat2, 0)
				|| !link_descriptor(c'/tmp/linux-open-dangling', via_openat2, 0)
				|| !link_descriptor(c'/proc/self/exe', via_openat2, 0) { return 1 }
		}
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 { return 1 }
		mut pipe_path := [64]u8{}
		C.snprintf(&char(&pipe_path[0]), usize(pipe_path.len), c'/proc/self/fd/%d', pipes[0])
		if !link_descriptor(&char(&pipe_path[0]), false, 0)
			|| !link_descriptor(&char(&pipe_path[0]), true, 0)
			|| !link_constraints(pipes[0]) || !trailing_slashes()
			|| !exclusive_creation() || !path_flags() || !mount_constraints() { return 1 }
		C.close(pipes[0]); C.close(pipes[1])
		mut how := How{}
		if !open_result(c'/tmp/linux-open-target', &how, 24, 0)
			|| !open_result(c'/tmp/linux-open-target', &how, sizeof(how), 0)
			|| !open_result(c'/tmp/linux-open-target', &how, 8, C.EINVAL)
			|| !open_result(c'/tmp/linux-open-target', voidptr(1), 24, C.EFAULT) { return 1 }
		how.extra = 1
		if !open_result(c'/tmp/linux-open-target', &how, sizeof(how), C.E2BIG) { return 1 }
		how.extra = 0; how.flags = u64(1) << 63
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		how.flags = 0; how.mode = 0o600
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		how.mode = 0; how.flags = u64(C.O_PATH)
		if !open_result(c'/tmp/linux-open-target', &how, 24, 0) { return 1 }
		how.flags = 0; how.resolve = 0x40
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		how.resolve = 0x18
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		for constraint in [u64(8), 16, 32, 9, 10, 20, 38]! {
			how.resolve = constraint
			if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, C.EOPNOTSUPP) { return 1 }
		}
		C.puts(c'LINUX OPEN: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
