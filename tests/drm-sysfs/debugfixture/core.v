// SPDX-License-Identifier: GPL-2.0-or-later
module debugfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat {
	st_mode u32
	st_uid  u32
	st_gid  u32
}

fn C.stat(&char, &C.stat) i32
fn C.S_ISDIR(u32) bool
fn C.S_ISREG(u32) bool
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.strlen(&char) u64
fn C.memcmp(voidptr, voidptr, u64) i32
fn C.__errno_location() &i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.reboot(i32) i32
fn C.pause() i32

fn can_list(path &char) bool {
	fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY)
	if fd < 0 { return false }
	C.close(fd)
	return true
}

fn has_debugfs_mode() bool {
	mut metadata := C.stat{}
	return C.stat(c'/sys/kernel/debug', &metadata) == 0
		&& C.S_ISDIR(metadata.st_mode) && metadata.st_mode & 0o777 == 0o700
		&& metadata.st_uid == 0 && metadata.st_gid == 0
}

fn has_drm_class_version() bool {
	path := c'/sys/class/drm/version'
	mut metadata := C.stat{}
	if C.stat(path, &metadata) != 0 || !C.S_ISREG(metadata.st_mode) || metadata.st_mode & 0o777 != 0o444 {
		return false
	}
	fd := C.open(path, C.O_RDONLY)
	if fd < 0 { return false }
	mut bytes := [32]u8{}
	count := C.read(fd, &bytes[0], sizeof(bytes))
	C.close(fd)
	expected := c'drm 1.1.0 20060810\n'
	length := C.strlen(expected)
	return count == i64(length) && C.memcmp(&bytes[0], expected, length) == 0
}

fn unprivileged_checks() i32 {
	if C.setgid(65534) != 0 || C.setuid(65534) != 0 { return 1 }
	if !can_list(c'/sys/kernel') || !can_list(c'/sys/class/drm') { return 2 }
	if can_list(c'/sys/kernel/debug') || unsafe { *C.__errno_location() } != C.EACCES {
		return 3
	}
	mut metadata := C.stat{}
	if C.stat(c'/sys/kernel/debug/dri', &metadata) != -1
		|| unsafe { *C.__errno_location() } != C.EACCES {
		return 4
	}
	if !has_drm_class_version() { return 5 }
	return 0
}

@[export: 'main']
pub fn run() i32 {
	root_access := can_list(c'/sys/kernel/debug')
	root_mode := has_debugfs_mode()
	root_version := has_drm_class_version()
	child := C.fork()
	if child == 0 { C._exit(unprivileged_checks()) }
	mut status := i32(0)
	child_passed := child > 0 && C.waitpid(child, &status, 0) == child && status == 0
	if root_version && child_passed {
		C.puts(c'VINIX DRM CLASS VERSION: PASS')
	} else if !root_version {
		C.puts(c'DRM CLASS FAIL: expected the read-only class version')
	}
	if root_access && root_mode && child_passed {
		C.puts(c'VINIX DRM DEBUGFS MODE: PASS')
	} else {
		if !root_access { C.puts(c'DRM DEBUGFS FAIL: root could not open the directory') }
		if !root_mode { C.puts(c'DRM DEBUGFS FAIL: expected mode 0700 and owner 0:0') }
		if !child_passed { C.printf(c'DRM DEBUGFS FAIL: unprivileged access checks (wait status %d)\n', status) }
	}
	C.fflush(unsafe { nil })
	C.reboot(C.RB_POWER_OFF)
	for { C.pause() }
	return 1
}
