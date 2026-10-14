// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#include <grp.h>

struct C.stat {
	st_dev u64
	st_ino u64
	st_size i64
	st_mode u32
	st_uid u32
	st_gid u32
	st_atim C.timespec
	st_mtim C.timespec
	st_ctim C.timespec
}

fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount2(&char, int) int
fn C.mkdir(&char, u32) int
fn C.symlink(&char, &char) int
fn C.open(&char, int, ...) int
fn C.openat(int, &char, int, ...) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.unlink(&char) int
fn C.stat(&char, &C.stat) int
fn C.fstat(int, &C.stat) int
fn C.chdir(&char) int
fn C.fchdir(int) int
fn C.chroot(&char) int
fn C.syscall(int, ...) isize
fn C.fork() int
fn C.pipe(&i32) int
fn C.unshare(int) int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.waitpid(int, &i32, int) int
fn C.WIFEXITED(i32) int
fn C.WEXITSTATUS(i32) int
fn C._exit(int)
fn C.puts(&char) int
fn C.printf(&char, ...) int
fn C.fflush(voidptr) int
fn C.pause() int
fn C.__errno_location() &i32
fn C.memcmp(voidptr, voidptr, usize) int
fn C.strcmp(&char, &char) int
fn C.snprintf(voidptr, usize, &char, ...) int
fn C.strlen(&char) usize

fn check(ok bool, site int) {
	if ok { return }
	unsafe { C.printf(c'MOUNT LIFECYCLE FAIL: site=%d errno=%d\n', site, *C.__errno_location()) }
	C.fflush(unsafe { nil })
	C._exit(1)
}

fn directory(path &char) { check(C.mkdir(path, 0o755) == 0, 1) }

fn marker(path &char) {
	fd := C.open(path, C.O_CREAT | C.O_EXCL | C.O_WRONLY, u32(0o600))
	check(fd >= 0 && C.write(fd, c'MOUNT-OK', 8) == 8 && C.close(fd) == 0, 2)
}

fn contents(path &char) bool {
	fd := C.open(path, C.O_RDONLY)
	if fd < 0 { return false }
	mut bytes := [8]u8{}
	count := C.read(fd, &bytes[0], 8)
	closed := C.close(fd)
	return count == 8 && closed == 0 && unsafe { C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0 }
}

fn same(path &char, before &C.stat) bool {
	mut after := C.stat{}
	return C.stat(path, &after) == 0 && after.st_dev == before.st_dev && after.st_ino == before.st_ino
}

fn wait_child(child int) {
	mut status := i32(0)
	check(child > 0 && C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0
		&& C.WEXITSTATUS(status) == 0, 3)
}

fn refused_unmount(path &char, flags int, expected int, site int) {
	result := C.umount2(path, flags)
	failure := unsafe { *C.__errno_location() }
	if result != -1 || failure != expected {
		unsafe { C.printf(c'MOUNT UNMOUNT RESULT: flags=%d result=%d errno=%d expected=%d\n',
			flags, result, failure, expected) }
		C.fflush(unsafe { nil })
	}
	check(result == -1 && failure == expected, site)
}

fn unmount_modes() {
	unsafe {
		directory(c'/tmp/mount-lifecycle/flags')
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/flags', c'tmpfs', 0, nil) == 0, 10)
		marker(c'/tmp/mount-lifecycle/flags/marker')
		check(C.symlink(c'flags', c'/tmp/mount-lifecycle/link') == 0, 11)
		mut before := C.stat{}
		check(C.stat(c'/tmp/mount-lifecycle/flags', &before) == 0, 12)
		held := C.open(c'/tmp/mount-lifecycle/flags/marker', C.O_RDONLY)
		check(held >= 0, 12)
		for iteration in 0 .. 200 {
			for flags in [int(C.MNT_FORCE), int(C.MNT_EXPIRE), int(C.MNT_FORCE | C.MNT_DETACH),
				int(C.MNT_FORCE | C.UMOUNT_NOFOLLOW), int(C.MNT_EXPIRE | C.UMOUNT_NOFOLLOW)]! {
				refused_unmount(c'/tmp/mount-lifecycle/flags', flags, C.ENOTSUP, 13)
			}
			for flags in [int(C.MNT_EXPIRE | C.MNT_FORCE), int(C.MNT_EXPIRE | C.MNT_DETACH),
				int(C.MNT_EXPIRE | C.MNT_FORCE | C.MNT_DETACH), 16, -1]! {
				refused_unmount(c'/tmp/mount-lifecycle/flags', flags, C.EINVAL, 14)
			}
			check(same(c'/tmp/mount-lifecycle/flags', &before)
				&& contents(c'/tmp/mount-lifecycle/flags/marker'), 15)
		}
		// The capability check still precedes validation of either mode.
		child := C.fork()
		check(child >= 0, 16)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 16)
			for flags in [int(C.MNT_FORCE), int(C.MNT_EXPIRE), 16, 0]! {
				refused_unmount(c'/tmp/mount-lifecycle/flags', flags, C.EPERM, 17)
			}
			C._exit(0)
		}
		wait_child(child)
		refused_unmount(c'/tmp/mount-lifecycle/link', int(C.UMOUNT_NOFOLLOW), C.EINVAL, 18)
		mut bytes := [8]u8{}
		check(C.read(held, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.close(held) == 0, 20)
		check(same(c'/tmp/mount-lifecycle/flags', &before)
			&& C.umount2(c'/tmp/mount-lifecycle/link', 0) == 0, 19)
		check(!same(c'/tmp/mount-lifecycle/flags', &before), 19)
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/flags', c'tmpfs', 0, nil) == 0, 21)
		marker(c'/tmp/mount-lifecycle/flags/marker')
		lazy_held := C.open(c'/tmp/mount-lifecycle/flags/marker', C.O_RDONLY)
		check(lazy_held >= 0
			&& C.umount2(c'/tmp/mount-lifecycle/flags', int(C.MNT_DETACH | C.UMOUNT_NOFOLLOW)) == 0
			&& C.read(lazy_held, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.close(lazy_held) == 0, 21)
		C.puts(c'MOUNT UNMOUNT MODES: PASS')
		C.fflush(nil)
	}
}

fn refused_move(source &char, target &char, site int) {
	result := C.mount(source, target, unsafe { nil }, usize(C.MS_MOVE), unsafe { nil })
	failure := unsafe { *C.__errno_location() }
	if result != -1 || failure != C.ELOOP {
		unsafe { C.printf(c'MOUNT MOVE RESULT: result=%d errno=%d expected=%d\n', result, failure, C.ELOOP) }
		C.fflush(unsafe { nil })
	}
	check(result == -1 && failure == C.ELOOP, site)
}

fn move_refusals() {
	unsafe {
		mut before := C.stat{}
		check(C.stat(c'/tmp/mount-lifecycle/old/source', &before) == 0, 31)
		for iteration in 0 .. 200 {
			refused_move(c'/tmp/mount-lifecycle/old/source', c'/tmp/mount-lifecycle/old/source/inside', 32)
			refused_move(c'/tmp/mount-lifecycle/old/source', c'/tmp/mount-lifecycle/old/source/nested/inside', 33)
			refused_move(c'/tmp/mount-lifecycle/old/source', c'/tmp/mount-lifecycle/old/source', 34)
			check(same(c'/tmp/mount-lifecycle/old/source', &before)
				&& contents(c'/tmp/mount-lifecycle/old/source/marker')
				&& contents(c'/tmp/mount-lifecycle/old/source/nested/marker'), 35)
		}
	}
}

fn allowed_move() {
	unsafe {
		mut before := C.stat{}
		check(C.stat(c'/tmp/mount-lifecycle/old/source', &before) == 0, 36)
		held := C.open(c'/tmp/mount-lifecycle/old/source', C.O_PATH | C.O_DIRECTORY)
		check(held >= 0 && C.chdir(c'/tmp/mount-lifecycle/old/source') == 0, 36)
		check(C.mount(c'/tmp/mount-lifecycle/old/source', c'/tmp/mount-lifecycle/new/dest', nil,
			usize(C.MS_MOVE), nil) == 0, 37)
		check(same(c'/tmp/mount-lifecycle/new/dest', &before)
			&& !same(c'/tmp/mount-lifecycle/old/source', &before)
			&& contents(c'/tmp/mount-lifecycle/new/dest/marker')
			&& contents(c'/tmp/mount-lifecycle/new/dest/nested/marker'), 38)
		mut parent := C.stat{}
		check(C.stat(c'/tmp/mount-lifecycle/new', &parent) == 0 && same(c'..', &parent), 39)
		parent_fd := C.openat(held, c'..', C.O_PATH | C.O_DIRECTORY)
		mut fd_parent := C.stat{}
		check(parent_fd >= 0 && C.fstat(parent_fd, &fd_parent) == 0
			&& fd_parent.st_dev == parent.st_dev && fd_parent.st_ino == parent.st_ino
			&& C.close(parent_fd) == 0 && C.close(held) == 0 && C.chdir(c'/') == 0, 40)
		check(C.umount2(c'/tmp/mount-lifecycle/new/dest/nested', 0) == 0
			&& C.umount2(c'/tmp/mount-lifecycle/new/dest', 0) == 0, 41)
	}
}

// A cwd/description opened before reparenting has an old route. Its mount's
// current parent graph must detect newly introduced ancestors and permit a
// destination that was subsequently moved out of the source tree.
fn reparented_cycles() {
	unsafe {
		directory(c'/tmp/mount-lifecycle/tree')
		directory(c'/tmp/mount-lifecycle/carrier')
		directory(c'/tmp/mount-lifecycle/branch')
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/tree', c'tmpfs', 0, nil) == 0
			&& C.mount(c'tmpfs', c'/tmp/mount-lifecycle/carrier', c'tmpfs', 0, nil) == 0, 50)
		directory(c'/tmp/mount-lifecycle/tree/nested')
		directory(c'/tmp/mount-lifecycle/carrier/moved')
		marker(c'/tmp/mount-lifecycle/carrier/marker')
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/tree/nested', c'tmpfs', 0, nil) == 0, 50)
		directory(c'/tmp/mount-lifecycle/tree/nested/inside')
		marker(c'/tmp/mount-lifecycle/tree/nested/marker')
		held := C.open(c'/tmp/mount-lifecycle/tree/nested', C.O_PATH | C.O_DIRECTORY)
		check(held >= 0 && C.chdir(c'/tmp/mount-lifecycle/tree/nested') == 0, 51)
		check(C.mount(c'/tmp/mount-lifecycle/tree', c'/tmp/mount-lifecycle/carrier/moved', nil,
			usize(C.MS_MOVE), nil) == 0, 52)
		mut target := [256]char{}
		check(C.snprintf(&target[0], 256, c'/proc/self/fd/%d/inside', held) > 0, 53)
		for iteration in 0 .. 200 {
			refused_move(c'/tmp/mount-lifecycle/carrier', c'inside', 54)
			refused_move(c'/tmp/mount-lifecycle/carrier', &target[0], 55)
			check(contents(c'marker') && contents(c'/tmp/mount-lifecycle/carrier/marker'), 56)
		}
		check(C.mount(c'/tmp/mount-lifecycle/carrier/moved/nested', c'/tmp/mount-lifecycle/branch', nil,
			usize(C.MS_MOVE), nil) == 0, 57)
		// Both holders still have the former tree/carrier in their saved route.
		check(C.mount(c'/tmp/mount-lifecycle/carrier', c'inside', nil, usize(C.MS_MOVE), nil) == 0, 58)
		check(contents(c'/tmp/mount-lifecycle/branch/inside/marker') && contents(c'marker'), 59)
		mut parent := C.stat{}
		check(C.stat(c'/tmp/mount-lifecycle/branch', &parent) == 0
			&& same(c'/tmp/mount-lifecycle/branch/inside/..', &parent), 59)
		check(C.close(held) == 0 && C.chdir(c'/') == 0, 60)
		check(C.umount2(c'/tmp/mount-lifecycle/branch/inside/moved', 0) == 0
			&& C.umount2(c'/tmp/mount-lifecycle/branch/inside', 0) == 0
			&& C.umount2(c'/tmp/mount-lifecycle/branch', 0) == 0, 61)
		C.puts(c'MOUNT REPARENTED HOLDERS: PASS')
		C.fflush(nil)
	}
}

fn move_depth_limit() {
	unsafe {
		directory(c'/tmp/mount-lifecycle/depth')
		directory(c'/tmp/mount-lifecycle/depth-source')
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/depth-source', c'tmpfs', 0, nil) == 0, 70)
		marker(c'/tmp/mount-lifecycle/depth-source/marker')
		mut path := [512]char{}
		check(C.snprintf(&path[0], 512, c'/tmp/mount-lifecycle/depth') > 0, 70)
		for level in 0 .. 63 {
			if level != 0 {
				length := int(C.strlen(&path[0]))
				path[length] = char(`/`)
				path[length + 1] = char(`d`)
				path[length + 2] = 0
				directory(&path[0])
			}
			check(C.mount(c'tmpfs', &path[0], c'tmpfs', 0, nil) == 0, 71)
		}
		mut before := C.stat{}
		check(C.stat(&path[0], &before) == 0, 72)
		refused_move(c'/tmp/mount-lifecycle/depth-source', &path[0], 73)
		check(same(&path[0], &before) && contents(c'/tmp/mount-lifecycle/depth-source/marker'), 74)
		// This destination fits the moved root but would place its deepest
		// child beyond the cursor. Refusal must preserve both trees.
		refused_move(c'/tmp/mount-lifecycle/depth', c'/tmp/mount-lifecycle/depth-source', 76)
		check(same(&path[0], &before) && contents(c'/tmp/mount-lifecycle/depth-source/marker'), 77)
		check(C.umount2(&path[0], 0) == 0, 78)
		path[int(C.strlen(&path[0])) - 2] = 0
		check(C.stat(&path[0], &before) == 0, 78)
		mut marker_path := [512]char{}
		check(C.snprintf(&marker_path[0], 512, c'%s/marker', &path[0]) > 0, 78)
		marker(&marker_path[0])
		// Removing one descendant makes the complete result exactly 64 steps.
		check(C.mount(c'/tmp/mount-lifecycle/depth', c'/tmp/mount-lifecycle/depth-source', nil,
			usize(C.MS_MOVE), nil) == 0, 79)
		check(C.snprintf(&path[0], 512, c'/tmp/mount-lifecycle/depth-source') > 0, 79)
		for level in 0 .. 61 {
			length := int(C.strlen(&path[0]))
			path[length] = char(`/`)
			path[length + 1] = char(`d`)
			path[length + 2] = 0
		}
		check(same(&path[0], &before) && C.snprintf(&marker_path[0], 512, c'%s/marker', &path[0]) > 0
			&& contents(&marker_path[0]), 80)
		for level in 0 .. 62 {
			check(C.umount2(&path[0], 0) == 0, 75)
			if level != 61 { path[int(C.strlen(&path[0])) - 2] = 0 }
		}
		check(C.umount2(c'/tmp/mount-lifecycle/depth-source', 0) == 0, 75)
		C.puts(c'MOUNT MOVE DEPTH: PASS')
		C.fflush(nil)
	}
}

fn move_cycles(check_depth bool) {
	unsafe {
		directory(c'/tmp/mount-lifecycle/old')
		directory(c'/tmp/mount-lifecycle/new')
		directory(c'/tmp/mount-lifecycle/old/source')
		directory(c'/tmp/mount-lifecycle/new/dest')
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/old/source', c'tmpfs', 0, nil) == 0, 30)
		marker(c'/tmp/mount-lifecycle/old/source/marker')
		directory(c'/tmp/mount-lifecycle/old/source/inside')
		directory(c'/tmp/mount-lifecycle/old/source/nested')
		check(C.mount(c'tmpfs', c'/tmp/mount-lifecycle/old/source/nested', c'tmpfs', 0, nil) == 0, 30)
		directory(c'/tmp/mount-lifecycle/old/source/nested/inside')
		marker(c'/tmp/mount-lifecycle/old/source/nested/marker')
		move_refusals()
		child := C.fork()
		check(child >= 0, 42)
		if child == 0 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 42)
			move_refusals()
			allowed_move()
			C._exit(0)
		}
		wait_child(child)
		check(contents(c'/tmp/mount-lifecycle/old/source/marker')
			&& contents(c'/tmp/mount-lifecycle/old/source/nested/marker'), 43)
		marker(c'/tmp/mount-lifecycle/new/file')
		check(C.mount(c'/tmp/mount-lifecycle/old/source', c'/tmp/mount-lifecycle/new/file', nil,
			usize(C.MS_MOVE), nil) == -1 && *C.__errno_location() == C.EINVAL, 44)
		allowed_move()
		reparented_cycles()
		if check_depth { move_depth_limit() }
		C.puts(c'MOUNT MOVE CYCLES: PASS')
		C.fflush(nil)
	}
}

@[export: 'main']
pub fn run() int {
	unsafe {
		check(C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 4)
		directory(c'/tmp/mount-lifecycle')
		fd := C.open(c'/mount-case', C.O_RDONLY)
		mut name := [32]u8{}
		count := C.read(fd, &name[0], 31)
		check(fd >= 0 && count > 0 && C.close(fd) == 0, 4)
		selected := &char(&name[0])
		identity := if count == 4 && name[0] == `i` && name[1] == `d` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `6` { int(name[3] - `0`) } else { -1 }
		admission := if count == 4 && name[0] == `a` && name[1] == `d` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `7` { int(name[3] - `0`) } else { -1 }
		propagation := if count == 4 && name[0] == `p` && name[1] == `r` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `4` { int(name[3] - `0`) } else { -1 }
		pivot := if count == 4 && name[0] == `p` && name[1] == `v` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `6` { int(name[3] - `0`) } else { -1 }
		lifecycle := if count == 4 && name[0] == `p` && name[1] == `l` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `3` { int(name[3] - `0`) } else { -1 }
		alias := if count == 4 && name[0] == `p` && name[1] == `a` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `4` { int(name[3] - `0`) } else { -1 }
		thread_case := if count == 4 && name[0] == `p` && name[1] == `t` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `6` { int(name[3] - `0`) } else { -1 }
		bind_case := if count == 4 && name[0] == `b` && name[1] == `p` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `4` { int(name[3] - `0`) } else { -1 }
		truncate_case := if count == 4 && name[0] == `t` && name[1] == `r` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `5` { int(name[3] - `0`) } else { -1 }
		metadata_case := if count == 4 && name[0] == `m` && name[1] == `p` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `6` { int(name[3] - `0`) } else { -1 }
		timestamp_case := if count == 4 && name[0] == `t` && name[1] == `p` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `7` { int(name[3] - `0`) } else { -1 }
		xattr_case := if count == 4 && name[0] == `x` && name[1] == `p` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `7` { int(name[3] - `0`) } else { -1 }
		inode_flags_case := if count == 4 && name[0] == `i` && name[1] == `p` && name[2] == `-`
			&& name[3] >= `0` && name[3] <= `7` { int(name[3] - `0`) } else { -1 }
		check(C.strcmp(selected, c'flags') == 0 || C.strcmp(selected, c'move') == 0
			|| C.strcmp(selected, c'move-reference') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'identities') == 0 || identity >= 0
			|| C.strcmp(selected, c'admission') == 0 || admission >= 0
			|| C.strcmp(selected, c'propagation') == 0 || propagation >= 0
			|| C.strcmp(selected, c'pivot') == 0 || pivot >= 0
			|| C.strcmp(selected, c'pivot-life') == 0 || lifecycle >= 0
			|| C.strcmp(selected, c'pivot-alias') == 0 || alias >= 0
			|| C.strcmp(selected, c'pivot-threads') == 0 || thread_case >= 0
			|| C.strcmp(selected, c'bind-policy') == 0 || bind_case >= 0
			|| C.strcmp(selected, c'truncate') == 0 || truncate_case >= 0
			|| C.strcmp(selected, c'metadata') == 0 || metadata_case >= 0
			|| C.strcmp(selected, c'times') == 0 || timestamp_case >= 0
			|| C.strcmp(selected, c'xattrs') == 0 || xattr_case >= 0
			|| C.strcmp(selected, c'inode-flags') == 0 || inode_flags_case >= 0, 4)
		if C.strcmp(selected, c'flags') == 0 || C.strcmp(selected, c'all') == 0 { unmount_modes() }
		if C.strcmp(selected, c'move') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { move_cycles(C.strcmp(selected, c'move-reference') != 0) }
		if C.strcmp(selected, c'identities') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { identity_cases(-1) }
		if identity >= 0 { identity_cases(identity) }
		if C.strcmp(selected, c'admission') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { admission_cases(-1) }
		if admission >= 0 { admission_cases(admission) }
		if C.strcmp(selected, c'propagation') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { propagation_cases(-1) }
		if propagation >= 0 { propagation_cases(propagation) }
		if C.strcmp(selected, c'pivot') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { pivot_cases(-1) }
		if pivot >= 0 { pivot_cases(pivot) }
		if C.strcmp(selected, c'pivot-life') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { pivot_lifecycle_cases(-1) }
		if lifecycle >= 0 { pivot_lifecycle_cases(lifecycle) }
		if C.strcmp(selected, c'pivot-alias') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { pivot_alias_cases(-1) }
		if alias >= 0 { pivot_alias_cases(alias) }
		if C.strcmp(selected, c'pivot-threads') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { pivot_thread_cases(-1) }
		if thread_case >= 0 { pivot_thread_cases(thread_case) }
		if C.strcmp(selected, c'bind-policy') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { bind_policy_cases(-1) }
		if bind_case >= 0 { bind_policy_cases(bind_case) }
		if C.strcmp(selected, c'truncate') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { truncate_cases(-1) }
		if truncate_case >= 0 { truncate_cases(truncate_case) }
		if C.strcmp(selected, c'metadata') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { metadata_cases(-1) }
		if metadata_case >= 0 { metadata_cases(metadata_case) }
		if C.strcmp(selected, c'times') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { timestamp_cases(-1) }
		if timestamp_case >= 0 { timestamp_cases(timestamp_case) }
		if C.strcmp(selected, c'xattrs') == 0 || C.strcmp(selected, c'all') == 0
			|| C.strcmp(selected, c'move-reference') == 0 { mount_xattr_cases(-1) }
		if xattr_case >= 0 { mount_xattr_cases(xattr_case) }
		if C.strcmp(selected, c'inode-flags') == 0 || C.strcmp(selected, c'all') == 0 { mount_flags_cases(-1) }
		if inode_flags_case >= 0 { mount_flags_cases(inode_flags_case) }
		C.puts(c'MOUNT LIFECYCLE: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
