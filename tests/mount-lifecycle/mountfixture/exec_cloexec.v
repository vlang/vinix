// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn C.atoi(&char) i32

fn exec_cloexec_entry(argc i32, argv &&char) {
	unsafe {
		if argc < 6 || C.strcmp(argv[argc - 5], c'--mount-cloexec-child') != 0 { return }
		C.puts(c'MOUNT EXECCLOEXEC CHILD: START')
		C.fflush(nil)
		owner := C.strcmp(argv[argc - 4], c'owner') == 0
		uid := if owner { u32(1000) } else { u32(0) }
		script := C.strcmp(argv[argc - 3], c'script') == 0
		closed := C.strcmp(argv[argc - 2], c'closed') == 0
		fd := C.atoi(argv[argc - 1])
		check(C.getuid() == uid && C.geteuid() == uid && C.getgid() == uid && C.getegid() == uid
			&& argc == if script { 7 } else { 6 }, 660)
		location := C.__errno_location()
		*location = 0
		flags := C.syscall(int(C.SYS_fcntl), fd, i32(C.F_GETFD), i32(0))
		check(if closed { flags == -1 && *C.__errno_location() == C.EBADF } else { flags == 0 }, 660)
		if script {
			mut proc_name := [128]char{}
			mut dev_name := [128]char{}
			check(!closed && C.snprintf(&proc_name[0], 128, c'/proc/self/fd/%d', fd) > 0
				&& C.snprintf(&dev_name[0], 128, c'/dev/fd/%d', fd) > 0, 660)
			check(C.strcmp(argv[1], &proc_name[0]) == 0 || C.strcmp(argv[1], &dev_name[0]) == 0, 660)
			opened := C.open(&proc_name[0], C.O_RDONLY)
			mut bytes := [2]u8{}
			check(opened >= 0 && C.read(opened, &bytes[0], 2) == 2
				&& bytes[0] == `#` && bytes[1] == `!` && C.close(opened) == 0, 660)
		}
		C._exit(41)
	}
}

fn exec_cloexec_attempt(fd int, flags int, expected int, owner bool, script bool, closed bool) {
	unsafe {
		before_flags := C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_GETFD), i32(0))
		child := C.fork()
		check(child >= 0, 661)
		if child == 0 {
			if owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 661) }
			mut number := [32]char{}
			check(C.snprintf(&number[0], 32, c'%d', i32(fd)) > 0, 661)
			arguments := [&char(c'exec-cloexec'), &char(c'--mount-cloexec-child'),
				if owner { &char(c'owner') } else { &char(c'root') },
				if script { &char(c'script') } else { &char(c'elf') },
				if closed { &char(c'closed') } else { &char(c'open') }, &number[0], &char(nil)]!
			environment := [&char(nil)]!
			location := C.__errno_location()
			*location = 0
			result := C.syscall(int(C.SYS_execveat), i32(fd), c'', &arguments[0], &environment[0], i32(flags))
			failure := *C.__errno_location()
			if expected != 0 && result == -1 && failure == expected {
				check(C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_GETFD), i32(0)) == before_flags, 661)
				C._exit(0)
			}
			C.printf(c'MOUNT EXECCLOEXEC RESULT: result=%ld errno=%d expected=%d\n', i64(result), failure, i32(expected))
			C.fflush(nil)
			C._exit(1)
		}
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0, 661)
		wanted := if expected == 0 { 41 } else { 0 }
		if C.WEXITSTATUS(status) != wanted {
			C.printf(c'MOUNT EXECCLOEXEC STATUS: status=%d expected=%d\n', C.WEXITSTATUS(status), i32(wanted))
			C.fflush(nil)
			check(false, 661)
		}
		check(C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_GETFD), i32(0)) == before_flags, 661)
	}
}

fn exec_cloexec_case(kind int) {
	unsafe {
		owner := kind % 2 == 1
		script := kind !in [4, 5]
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 662)
		mut root := [256]char{}
		mut target := [256]char{}
		mut helper := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/ec-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0
			&& C.snprintf(&helper[0], 256, c'/tmp/mount-lifecycle/ec-%d-helper', i32(kind)) > 0, 662)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 662)
		if script {
			descriptor_exec_copy(&helper[0])
			mut text := [512]char{}
			length := C.snprintf(&text[0], 512, c'#!%s\n', &helper[0])
			output := C.open(&target[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
			check(length > 0 && length < 512 && output >= 0
				&& C.write(output, &text[0], usize(length)) == length && C.close(output) == 0, 662)
		} else { descriptor_exec_copy(&target[0]) }
		original := C.open(&target[0], (if kind % 2 == 1 { C.O_PATH } else { C.O_RDONLY }) | C.O_CLOEXEC)
		check(original >= 0, 662)
		fd := if kind in [0, 1, 4, 5, 7] { original } else if kind == 3 {
			int(C.syscall(int(C.SYS_fcntl), i32(original), i32(C.F_DUPFD_CLOEXEC), i32(0)))
		} else { int(C.syscall(int(C.SYS_dup), i32(original))) }
		check(fd >= 0 && C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_GETFD), i32(0))
			== if kind in [2, 6] { 0 } else { C.FD_CLOEXEC }, 662)
		check((fd == original || C.close(original) == 0)
			&& C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_SETFD), i32(C.FD_CLOEXEC)) == 0, 662)
		if kind in [2, 3, 5] { check(C.unlink(&target[0]) == 0, 662) }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0, 662)
		for flags in [int(C.AT_EMPTY_PATH), int(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
			if kind == 7 {
				mount_statfs_policy(&root[0], u64(C.MS_NOEXEC))
				exec_cloexec_attempt(fd, flags, C.EACCES, owner, true, false)
				mount_statfs_policy(&root[0], 0)
				exec_cloexec_attempt(fd, flags | 1, C.EINVAL, owner, true, false)
			}
			exec_cloexec_attempt(fd, flags, if script { C.ENOENT } else { 0 }, owner, script, true)
			if kind == 6 {
				duplicate := int(C.syscall(int(C.SYS_dup), i32(fd)))
				check(duplicate >= 0, 663)
				exec_cloexec_attempt(duplicate, flags, 0, owner, true, false)
				check(C.close(duplicate) == 0, 663)
			}
			check(C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_SETFD), i32(0)) == 0, 663)
			exec_cloexec_attempt(fd, flags, 0, owner, script, false)
			check(C.syscall(int(C.SYS_fcntl), i32(fd), i32(C.F_SETFD), i32(C.FD_CLOEXEC)) == 0, 663)
		}
		if kind == 7 {
			mut bad_path := [256]char{}
			check(C.snprintf(&bad_path[0], 256, c'%s/bad', &root[0]) > 0, 664)
			output := C.open(&bad_path[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
			check(output >= 0 && C.write(output, c'#!\n', 3) == 3 && C.close(output) == 0, 664)
			bad := C.open(&bad_path[0], C.O_RDONLY | C.O_CLOEXEC)
			check(bad >= 0, 664)
			exec_cloexec_attempt(bad, int(C.AT_EMPTY_PATH), C.ENOEXEC, owner, true, false)
			check(C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &bad_path[0], u32(0o600)) == 0, 664)
			exec_cloexec_attempt(bad, int(C.AT_EMPTY_PATH), C.EACCES, owner, true, false)
			exec_cloexec_attempt(-1234, int(C.AT_EMPTY_PATH), C.EBADF, owner, true, false)
			check(C.close(bad) == 0, 664)
		}
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0 && after.st_nlink == before.st_nlink, 664)
		timestamp_identity(&after, &before)
		check(timestamp_equal(after.st_mtim, before.st_mtim) && timestamp_equal(after.st_ctim, before.st_ctim)
			&& C.close(fd) == 0, 664)
	}
}

fn exec_cloexec_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 665)
			if child == 0 { exec_cloexec_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT EXECCLOEXEC CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT EXECCLOEXEC: PASS')
		C.fflush(nil)
	}
}
