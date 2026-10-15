// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn exec_relative_entry(argc i32, argv &&char) {
	unsafe {
		if argc < 5 || C.strcmp(argv[argc - 4], c'--mount-relative-child') != 0 { return }
		C.puts(c'MOUNT EXECREL CHILD: START')
		C.fflush(nil)
		owner := C.strcmp(argv[argc - 3], c'owner') == 0
		uid := if owner { u32(1000) } else { u32(0) }
		elf := C.strcmp(argv[argc - 2], c'elf') == 0
		chain := C.strcmp(argv[argc - 2], c'chain') == 0
		check(C.getuid() == uid && C.geteuid() == uid && C.getgid() == uid && C.getegid() == uid
			&& argc == if elf { 5 } else if chain { 7 } else { 6 }, 670)
		if elf {
			location := C.__errno_location()
			*location = 0
			check(C.syscall(int(C.SYS_fcntl), C.atoi(argv[argc - 1]), i32(C.F_GETFD), i32(0)) == -1
				&& *location == C.EBADF, 670)
		} else {
			mut proc_name := [512]char{}
			mut dev_name := [512]char{}
			derived := chain || C.strcmp(argv[argc - 2], c'fd') == 0
			actual := argv[if chain { 2 } else { 1 }]
			if chain { check(C.strcmp(argv[1], c'/tmp/mount-lifecycle/er-2/chain-helper') == 0, 670) }
			check(C.snprintf(&proc_name[0], 512, if derived { c'/proc/self/fd/%s' } else { c'%s' }, argv[argc - 1]) > 0
				&& C.snprintf(&dev_name[0], 512, if derived { c'/dev/fd/%s' } else { c'%s' }, argv[argc - 1]) > 0, 670)
			if C.strcmp(actual, &proc_name[0]) != 0 && C.strcmp(actual, &dev_name[0]) != 0 {
				C.printf(c'MOUNT EXECREL NAME: actual=%s expected=%s\n', actual, &proc_name[0])
				C.fflush(nil)
				check(false, 670)
			}
			opened := C.open(actual, C.O_RDONLY)
			mut bytes := [512]u8{}
			count := C.read(opened, &bytes[0], 511)
			check(opened >= 0 && count >= 7 && count <= 511
				&& C.memcmp(&bytes[count - 7], c'\nRIGHT\n', 7) == 0 && C.close(opened) == 0, 670)
		}
		C._exit(43)
	}
}

fn exec_relative_attempt(fd u64, path &char, flags int, expected int, owner bool, form int) {
	unsafe {
		child := C.fork()
		check(child >= 0, 671)
		if child == 0 {
			if owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 671) }
			mut name := [512]char{}
			check(match form {
				0, 3 { C.snprintf(&name[0], 512, c'%d/%s', i32(fd), path) }
				1 { C.snprintf(&name[0], 512, c'%s', path) }
				else { C.snprintf(&name[0], 512, c'%d', i32(fd)) }
			} > 0, 671)
			arguments := [&char(c'exec-relative'), &char(c'--mount-relative-child'),
				if owner { &char(c'owner') } else { &char(c'root') },
				match form { 0 { &char(c'fd') } 1 { &char(c'path') } 3 { &char(c'chain') } else { &char(c'elf') } },
				&name[0], &char(nil)]!
			environment := [&char(nil)]!
			location := C.__errno_location()
			*location = 0
			result := C.syscall(int(C.SYS_execveat), fd, path, &arguments[0], &environment[0], i32(flags))
			failure := *location
			if expected != 0 && result == -1 && failure == expected { C._exit(0) }
			C.printf(c'MOUNT EXECREL RESULT: result=%ld errno=%d expected=%d\n', i64(result), failure, i32(expected))
			C.fflush(nil)
			C._exit(1)
		}
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0, 671)
		wanted := if expected == 0 { 43 } else { 0 }
		if C.WEXITSTATUS(status) != wanted {
			C.printf(c'MOUNT EXECREL STATUS: status=%d expected=%d\n', C.WEXITSTATUS(status), i32(wanted))
			C.fflush(nil)
			check(false, 671)
		}
	}
}

fn exec_relative_script(path &char, helper &char, right bool) {
	unsafe {
		mut text := [512]char{}
		length := C.snprintf(&text[0], 512, c'#!%s\n%s\n', helper, if right { &char(c'RIGHT') } else { &char(c'WRONG') })
		output := C.open(path, C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
		check(length > 0 && length < 512 && output >= 0
			&& C.write(output, &text[0], usize(length)) == length && C.close(output) == 0, 672)
	}
}

fn exec_relative_case(kind int) {
	unsafe {
		owner := kind % 2 == 1
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 672)
		mut root := [256]char{}
		mut source := [256]char{}
		mut other := [256]char{}
		mut target := [256]char{}
		mut helper := [256]char{}
		mut extra := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/er-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &root[0]) > 0
			&& C.snprintf(&other[0], 256, c'%s/other', &root[0]) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &source[0]) > 0
			&& C.snprintf(&helper[0], 256, c'/tmp/mount-lifecycle/er-%d-helper', i32(kind)) > 0, 672)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 672)
		directory(&source[0]); directory(&other[0])
		descriptor_exec_copy(&helper[0])
		if kind == 4 { descriptor_exec_copy(&target[0]) }
		else { exec_relative_script(&target[0], &helper[0], true) }
		check(C.snprintf(&extra[0], 256, c'%s/target', &other[0]) > 0, 672)
		exec_relative_script(&extra[0], &helper[0], false)
		flags := C.O_DIRECTORY | (if kind % 2 == 1 { C.O_PATH } else { C.O_RDONLY })
		dirfd := C.open(&source[0], flags | if kind in [3, 4, 5, 7] { C.O_CLOEXEC } else { 0 })
		image := C.open(&target[0], C.O_RDONLY)
		check(dirfd >= 0 && image >= 0 && C.chdir(&other[0]) == 0, 672)
		if kind == 1 {
			check(C.snprintf(&extra[0], 256, c'%s/moved', &root[0]) > 0
				&& C.syscall(int(C.SYS_renameat), i32(C.AT_FDCWD), &source[0], i32(C.AT_FDCWD), &extra[0]) == 0, 672)
		}
		if kind == 2 {
			check(C.snprintf(&extra[0], 256, c'%s/sub', &source[0]) > 0, 672)
			directory(&extra[0])
		}
		mut before := C.stat{}
		check(C.fstat(image, &before) == 0, 673)
		for high in [u64(0), u64(0x1122334400000000)]! {
			raw := high | u64(u32(dirfd))
			for exec_flags in [int(0), int(C.AT_EMPTY_PATH), int(C.AT_SYMLINK_NOFOLLOW), int(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
				match kind {
					0, 1, 2 { exec_relative_attempt(raw, if kind == 2 { c'sub/../target' } else { c'target' }, exec_flags, 0, owner, 0) }
					3 {
						exec_relative_attempt(raw, c'target', exec_flags, C.ENOENT, owner, 0)
						check(C.syscall(int(C.SYS_fcntl), i32(dirfd), i32(C.F_SETFD), i32(0)) == 0, 673)
						exec_relative_attempt(raw, c'target', exec_flags, 0, owner, 0)
						check(C.syscall(int(C.SYS_fcntl), i32(dirfd), i32(C.F_SETFD), i32(C.FD_CLOEXEC)) == 0, 673)
						duplicate := int(C.syscall(int(C.SYS_dup), i32(dirfd)))
						check(duplicate >= 0, 673)
						exec_relative_attempt(u64(u32(duplicate)), c'target', exec_flags, 0, owner, 0)
						check(C.close(duplicate) == 0, 673)
					}
					4 { exec_relative_attempt(raw, c'target', exec_flags, 0, owner, 2) }
					5 {
						exec_relative_attempt(raw, &target[0], exec_flags, 0, owner, 1)
						exec_relative_attempt(high | u64(u32(i32(-1234))), &target[0], exec_flags, 0, owner, 1)
						check(C.fchdir(dirfd) == 0, 673)
						exec_relative_attempt(high | u64(u32(i32(C.AT_FDCWD))), c'target', exec_flags, 0, owner, 1)
						check(C.chdir(&other[0]) == 0, 673)
					}
					6 {
						exec_relative_attempt(raw, c'missing', exec_flags, C.ENOENT, owner, 0)
						exec_relative_attempt(high | u64(u32(image)), c'target', exec_flags, C.ENOTDIR, owner, 0)
						exec_relative_attempt(high | u64(u32(i32(-1234))), c'target', exec_flags, C.EBADF, owner, 0)
					}
					7 {
						mount_statfs_policy(&root[0], u64(C.MS_NOEXEC))
						exec_relative_attempt(raw, c'target', exec_flags, C.EACCES, owner, 0)
						mount_statfs_policy(&root[0], 0)
						exec_relative_attempt(raw, c'target', exec_flags | 1, C.EINVAL, owner, 0)
					}
					else { check(false, 673) }
				}
			}
		}
		if kind == 6 {
			check(C.snprintf(&extra[0], 256, c'%s/link', &source[0]) > 0 && C.symlink(c'target', &extra[0]) == 0, 673)
			exec_relative_attempt(u64(u32(dirfd)), c'link', 0, 0, owner, 0)
			exec_relative_attempt(u64(u32(dirfd)), c'link', int(C.AT_SYMLINK_NOFOLLOW), C.ELOOP, owner, 0)
		}
		if kind == 2 {
			mut chain_helper := [256]char{}
			check(C.snprintf(&chain_helper[0], 256, c'%s/chain-helper', &root[0]) > 0
				&& C.snprintf(&extra[0], 256, c'%s/chain', &source[0]) > 0, 673)
			exec_relative_script(&chain_helper[0], &helper[0], true)
			exec_relative_script(&extra[0], &chain_helper[0], true)
			exec_relative_attempt(u64(u32(dirfd)), c'chain', 0, 0, owner, 3)
		}
		mut after := C.stat{}
		check(C.fstat(image, &after) == 0 && after.st_nlink == before.st_nlink, 674)
		timestamp_identity(&after, &before)
		check(timestamp_equal(after.st_mtim, before.st_mtim) && timestamp_equal(after.st_ctim, before.st_ctim)
			&& C.close(image) == 0 && C.close(dirfd) == 0, 674)
	}
}

fn exec_relative_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 675)
			if child == 0 { exec_relative_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT EXECREL CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT EXECREL: PASS')
		C.fflush(nil)
	}
}
