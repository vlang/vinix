// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn exec_flags_attempt(fd int, path &char, flags u64, expected int, owner bool) {
	unsafe {
		child := C.fork()
		check(child >= 0, 640)
		if child == 0 {
			if owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 640) }
			arguments := [&char(c'exec-flags'), &char(c'--mount-exec-child'),
				if owner { &char(c'owner') } else { &char(c'root') }, &char(nil)]!
			environment := [&char(nil)]!
			location := C.__errno_location()
			*location = 0
			// Deliberately retain the full register to test the C-int ABI too.
			result := C.syscall(int(C.SYS_execveat), i32(fd), path, &arguments[0], &environment[0], flags)
			failure := *location
			if expected != 0 && result == -1 && failure == expected { C._exit(0) }
			C.printf(c'MOUNT EXECFLAGS RESULT: flags=%lx result=%ld errno=%d expected=%d\n',
				flags, i64(result), failure, i32(expected))
			C.fflush(nil)
			C._exit(1)
		}
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0, 640)
		actual := C.WEXITSTATUS(status)
		wanted := if expected == 0 { 37 } else { 0 }
		if actual != wanted {
			C.printf(c'MOUNT EXECFLAGS STATUS: flags=%lx status=%d expected=%d\n', flags, i32(actual), i32(wanted))
			C.fflush(nil)
			check(false, 640)
		}
	}
}

fn exec_flags_unknown(fd int, path &char, empty bool, owner bool) {
	unsafe {
		for bad in [u64(1), 2, 0x200, 0x400, 0x800, 0x2000, 0x80000000, 0xffffffff]! {
			for valid in [u64(0), u64(C.AT_SYMLINK_NOFOLLOW), u64(C.AT_EMPTY_PATH), u64(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
				if empty && valid & u64(C.AT_EMPTY_PATH) == 0 { continue }
				exec_flags_attempt(fd, path, bad | valid, C.EINVAL, owner)
			}
		}
	}
}

fn exec_flags_case(kind int) {
	unsafe {
		owner := kind % 2 == 1
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 641)
		mut root := [256]char{}
		mut target := [256]char{}
		mut link := [256]char{}
		mut dangling := [256]char{}
		mut middle := [256]char{}
		mut through := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/ef-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0
			&& C.snprintf(&link[0], 256, c'%s/link', &root[0]) > 0
			&& C.snprintf(&dangling[0], 256, c'%s/dangling', &root[0]) > 0
			&& C.snprintf(&middle[0], 256, c'%s/middle', &root[0]) > 0
			&& C.snprintf(&through[0], 256, c'%s/middle/target', &root[0]) > 0, 641)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 641)
		descriptor_exec_copy(&target[0])
		check(C.symlink(c'target', &link[0]) == 0 && C.symlink(c'missing', &dangling[0]) == 0
			&& C.symlink(c'.', &middle[0]) == 0, 641)
		original := C.open(&target[0], if kind == 3 { C.O_PATH } else { C.O_RDONLY })
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		dirfd := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
		linkfd := C.open(&link[0], C.O_PATH | C.O_NOFOLLOW)
		check(original >= 0 && fd >= 0 && dirfd >= 0 && linkfd >= 0 && C.close(original) == 0, 641)
		if kind == 3 { check(C.unlink(&target[0]) == 0, 641) }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0 && (kind != 3 || before.st_nlink == 0), 641)
		match kind {
			0 { exec_flags_unknown(-1234, &target[0], false, owner) }
			1 { exec_flags_unknown(dirfd, c'target', false, owner) }
			2, 3 { exec_flags_unknown(fd, c'', true, owner) }
			4, 5 {
				selected := if kind == 4 { &link[0] } else { &char(c'link') }
				base := if kind == 4 { -1234 } else { dirfd }
				for flags in [u64(C.AT_SYMLINK_NOFOLLOW), u64(C.AT_SYMLINK_NOFOLLOW | C.AT_EMPTY_PATH)]! {
					exec_flags_attempt(base, selected, flags, C.ELOOP, owner)
					exec_flags_attempt(base, if kind == 4 { &through[0] } else { c'middle/target' }, flags, 0, owner)
				}
				exec_flags_attempt(base, selected, 0, 0, owner)
				exec_flags_attempt(base, selected, u64(C.AT_EMPTY_PATH), 0, owner)
			}
			6 {
				exec_flags_attempt(-1234, &dangling[0], u64(C.AT_SYMLINK_NOFOLLOW), C.ELOOP, owner)
				exec_flags_attempt(dirfd, c'dangling', u64(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW), C.ELOOP, owner)
				exec_flags_attempt(dirfd, c'dangling', 0, C.ENOENT, owner)
			}
			7 {
				for flags in [u64(C.AT_EMPTY_PATH), u64(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
					exec_flags_attempt(linkfd, c'', flags, C.ELOOP, owner)
				}
			}
			8 {
				for valid in [u64(0), u64(C.AT_SYMLINK_NOFOLLOW), u64(C.AT_EMPTY_PATH), u64(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
					for high in [u64(0), u64(0x1122334400000000)]! {
						exec_flags_attempt(-1234, &target[0], high | valid, 0, owner)
						exec_flags_attempt(dirfd, c'target', high | valid, 0, owner)
						if valid & u64(C.AT_EMPTY_PATH) != 0 { exec_flags_attempt(fd, c'', high | valid, 0, owner) }
					}
				}
			}
			9 {
				exec_flags_attempt(-1234, c'target', 1, C.EINVAL, owner)
				exec_flags_attempt(dirfd, c'missing', 1, C.EINVAL, owner)
				exec_flags_attempt(fd, c'', 1, C.ENOENT, owner)
				exec_flags_attempt(-1234, nil, 1, C.EFAULT, owner)
				exec_flags_attempt(-1234, c'', u64(C.AT_EMPTY_PATH | 1), C.EINVAL, owner)
				exec_flags_attempt(-1234, c'target', 0, C.EBADF, owner)
				exec_flags_attempt(fd, c'', 0, C.ENOENT, owner)
				exec_flags_attempt(-1234, c'', u64(C.AT_EMPTY_PATH), C.EBADF, owner)
			}
			else { check(false, 642) }
		}
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0 && after.st_nlink == before.st_nlink, 643)
		timestamp_identity(&after, &before)
		check(timestamp_equal(after.st_mtim, before.st_mtim) && timestamp_equal(after.st_ctim, before.st_ctim), 643)
		check(C.close(fd) == 0 && C.close(dirfd) == 0 && C.close(linkfd) == 0, 643)
	}
}

fn exec_flags_cases(selected int) {
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 644)
			if child == 0 { exec_flags_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT EXECFLAGS CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT EXECFLAGS: PASS')
		C.fflush(nil)
	}
}
