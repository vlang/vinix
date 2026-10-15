// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn exec_fd_entry(argc i32, argv &&char) {
	unsafe {
		if argc < 4 || C.strcmp(argv[argc - 3], c'--mount-fd-child') != 0 { return }
		owner := C.strcmp(argv[argc - 2], c'owner') == 0
		uid := if owner { u32(1000) } else { u32(0) }
		check((owner || C.strcmp(argv[argc - 2], c'root') == 0)
			&& C.getuid() == uid && C.geteuid() == uid && C.getgid() == uid && C.getegid() == uid, 650)
		if C.strlen(argv[argc - 1]) > 0 {
			mut proc_name := [128]char{}
			mut dev_name := [128]char{}
			check(argc == 5 && C.snprintf(&proc_name[0], 128, c'/proc/self/fd/%s', argv[argc - 1]) > 0
				&& C.snprintf(&dev_name[0], 128, c'/dev/fd/%s', argv[argc - 1]) > 0, 650)
			// Linux and Vinix spell the synthesized script name differently.
			check(C.strcmp(argv[1], &proc_name[0]) == 0 || C.strcmp(argv[1], &dev_name[0]) == 0, 650)
			opened := C.open(&proc_name[0], C.O_RDONLY)
			mut bytes := [2]u8{}
			check(opened >= 0 && C.read(opened, &bytes[0], 2) == 2 && bytes[0] == `#` && bytes[1] == `!`
				&& C.close(opened) == 0, 650)
		} else { check(argc == 4, 650) }
		C._exit(39)
	}
}

fn exec_fd_attempt(fd u64, path &char, flags u64, expected int, owner bool, script bool) {
	unsafe {
		child := C.fork()
		check(child >= 0, 651)
		if child == 0 {
			if owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 651) }
			mut number := [32]char{}
			if script { check(C.snprintf(&number[0], 32, c'%d', i32(fd)) > 0, 651) }
			arguments := [&char(c'exec-fd'), &char(c'--mount-fd-child'),
				if owner { &char(c'owner') } else { &char(c'root') }, &number[0], &char(nil)]!
			environment := [&char(nil)]!
			location := C.__errno_location()
			*location = 0
			// Keep the entire register; libc-style i32 arguments hide this bug.
			result := C.syscall(int(C.SYS_execveat), fd, path, &arguments[0], &environment[0], flags)
			failure := *location
			if expected != 0 && result == -1 && failure == expected { C._exit(0) }
			C.printf(c'MOUNT EXECFD RESULT: fd=%lx flags=%lx result=%ld errno=%d expected=%d\n',
				fd, flags, i64(result), failure, i32(expected))
			C.fflush(nil)
			C._exit(1)
		}
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0, 651)
		actual := C.WEXITSTATUS(status)
		wanted := if expected == 0 { 39 } else { 0 }
		if actual != wanted {
			C.printf(c'MOUNT EXECFD STATUS: fd=%lx status=%d expected=%d\n', fd, i32(actual), i32(wanted))
			C.fflush(nil)
			check(false, 651)
		}
	}
}

fn exec_fd_case(kind int) {
	unsafe {
		owner := kind % 2 == 1
		script := kind in [4, 5]
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 652)
		mut root := [256]char{}
		mut target := [256]char{}
		mut helper := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/ed-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0
			&& C.snprintf(&helper[0], 256, c'/tmp/mount-lifecycle/ed-%d-helper', i32(kind)) > 0, 652)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 652)
		if script {
			descriptor_exec_copy(&helper[0])
			mut text := [512]char{}
			length := C.snprintf(&text[0], 512, c'#!%s\n', &helper[0])
			output := C.open(&target[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
			check(length > 0 && length < 512 && output >= 0
				&& C.write(output, &text[0], usize(length)) == length && C.close(output) == 0, 652)
		} else { descriptor_exec_copy(&target[0]) }
		original := C.open(&target[0], if kind % 2 == 1 { C.O_PATH } else { C.O_RDONLY })
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		dirfd := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
		check(original >= 0 && fd >= 0 && dirfd >= 0 && C.close(original) == 0, 652)
		if kind in [2, 3] { check(C.unlink(&target[0]) == 0, 652) }
		if kind == 7 { mount_statfs_policy(&root[0], u64(C.MS_NOEXEC)) }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0 && (kind !in [2, 3] || before.st_nlink == 0), 652)
		for high in [u64(0), u64(0x1122334400000000), u64(0xffffffff00000000), u64(0x8000000000000000)]! {
			if kind < 6 {
				for flags in [u64(C.AT_EMPTY_PATH), u64(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
					exec_fd_attempt(high | u64(u32(fd)), c'', flags, 0, owner, script)
				}
			} else if kind == 6 {
				exec_fd_attempt(high | u64(u32(dirfd)), c'target', 0, 0, owner, false)
				check(C.fchdir(dirfd) == 0, 653)
				exec_fd_attempt(high | u64(u32(i32(C.AT_FDCWD))), c'target', 0, 0, owner, false)
				exec_fd_attempt(high | u64(u32(i32(-1234))), &target[0], 0, 0, owner, false)
				check(C.chdir(c'/') == 0, 653)
			} else {
				for invalid in [i32(-1), i32(-1234), i32(0x7fffffff)]! {
					raw := high | u64(u32(invalid))
					exec_fd_attempt(raw, c'', u64(C.AT_EMPTY_PATH), C.EBADF, owner, false)
					exec_fd_attempt(raw, c'target', 0, C.EBADF, owner, false)
					exec_fd_attempt(raw, c'', 0, C.ENOENT, owner, false)
					exec_fd_attempt(raw, c'', u64(C.AT_EMPTY_PATH | 1), C.EINVAL, owner, false)
				}
				exec_fd_attempt(high | u64(u32(fd)), c'', u64(C.AT_EMPTY_PATH), C.EACCES, owner, false)
			}
		}
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0 && after.st_nlink == before.st_nlink, 654)
		timestamp_identity(&after, &before)
		check(timestamp_equal(after.st_mtim, before.st_mtim) && timestamp_equal(after.st_ctim, before.st_ctim), 654)
		check(C.close(fd) == 0 && C.close(dirfd) == 0, 654)
	}
}

fn exec_fd_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 655)
			if child == 0 { exec_fd_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT EXECFD CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT EXECFD: PASS')
		C.fflush(nil)
	}
}
