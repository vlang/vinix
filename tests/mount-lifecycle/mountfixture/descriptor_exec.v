// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32

fn descriptor_exec_entry(argc i32, argv &&char) {
	unsafe {
		if argc < 3 || C.strcmp(argv[argc - 2], c'--mount-exec-child') != 0 { return }
		owner := C.strcmp(argv[argc - 1], c'owner') == 0
		uid := if owner { u32(1000) } else { u32(0) }
		check((owner || C.strcmp(argv[argc - 1], c'root') == 0)
			&& C.getuid() == uid && C.geteuid() == uid && C.getgid() == uid && C.getegid() == uid, 620)
		// A distinct exit status proves the requested image actually started.
		C._exit(37)
	}
}

fn descriptor_exec_copy(target &char) {
	unsafe {
		source := C.open(c'/proc/self/exe', C.O_RDONLY)
		output := C.open(target, C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
		check(source >= 0 && output >= 0, 621)
		mut bytes := [8192]u8{}
		for {
			count := C.read(source, &bytes[0], 8192)
			check(count >= 0, 621)
			if count == 0 { break }
			mut written := isize(0)
			for written < count {
				amount := C.write(output, &bytes[written], usize(count - written))
				check(amount > 0, 621)
				written += amount
			}
		}
		check(C.close(source) == 0 && C.close(output) == 0, 621)
	}
}

fn descriptor_exec_attempt(form int, fd int, path &char, noexec bool, owner bool) {
	unsafe {
		child := C.fork()
		check(child >= 0, 622)
		if child == 0 {
			arguments := [&char(c'mount-exec'), &char(c'--mount-exec-child'),
				if owner { &char(c'owner') } else { &char(c'root') }, &char(nil)]!
			environment := [&char(nil)]!
			location := C.__errno_location()
			*location = 0
			result := if form == 2 {
				C.syscall(int(C.SYS_execve), path, &arguments[0], &environment[0])
			} else {
				C.syscall(int(C.SYS_execveat), i32(fd), path, &arguments[0], &environment[0],
					i32(if form == 0 { C.AT_EMPTY_PATH } else { 0 }))
			}
			failure := *location
			if noexec && result == -1 && failure == C.EACCES { C._exit(0) }
			C.printf(c'MOUNT DESCEXEC RESULT: form=%d result=%ld errno=%d expected=%d\n',
				i32(form), i64(result), failure, i32(if noexec { C.EACCES } else { 0 }))
			C.fflush(nil)
			C._exit(1)
		}
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0, 622)
		actual := C.WEXITSTATUS(status)
		expected := if noexec { 0 } else { 37 }
		if actual != expected {
			C.printf(c'MOUNT DESCEXEC STATUS: form=%d status=%d expected=%d\n', i32(form), i32(actual), i32(expected))
			C.fflush(nil)
			check(false, 622)
		}
	}
}

fn descriptor_exec_case(kind int) {
	unsafe {
		noexec := kind % 2 == 1
		unlinked := kind in [2, 3]
		owner := kind in [4, 5, 8, 9]
		script := kind in [6, 7]
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 623)
		mut root := [256]char{}
		mut target := [256]char{}
		mut helper := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/de-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0
			&& C.snprintf(&helper[0], 256, c'/tmp/mount-lifecycle/de-%d-helper', i32(kind)) > 0, 623)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 623)
		if script {
			descriptor_exec_copy(&helper[0])
			mut text := [512]char{}
			length := C.snprintf(&text[0], 512, c'#!%s\n', &helper[0])
			output := C.open(&target[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
			check(length > 0 && length < 512 && output >= 0
				&& C.write(output, &text[0], usize(length)) == length && C.close(output) == 0, 623)
		} else { descriptor_exec_copy(&target[0]) }
		original := C.open(&target[0], C.O_RDONLY)
		original_path := C.open(&target[0], C.O_PATH)
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		pathfd := int(C.syscall(int(C.SYS_dup), i32(original_path)))
		check(original >= 0 && original_path >= 0 && fd >= 0 && pathfd >= 0
			&& C.close(original) == 0 && C.close(original_path) == 0, 623)
		uid := if owner { u32(1000) } else { u32(0) }
		check(C.syscall(int(C.SYS_fchown), i32(fd), uid, uid) == 0
			&& C.syscall(int(C.SYS_fchmod), i32(fd), u32(0o755)) == 0, 623)
		if unlinked { check(C.unlink(&target[0]) == 0, 623) }
		// These directory descriptions retain the original attachment across
		// unshare, unlike a new directory opened in the copied namespace.
		mut retained := i32(-1)
		mut retained_path := i32(-1)
		if kind >= 6 {
			ordinary := C.open(&root[0], C.O_RDONLY | C.O_DIRECTORY)
			path_only := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
			retained = i32(C.syscall(int(C.SYS_dup), i32(ordinary)))
			retained_path = i32(C.syscall(int(C.SYS_dup), i32(path_only)))
			check(ordinary >= 0 && path_only >= 0 && retained >= 0 && retained_path >= 0
				&& C.close(ordinary) == 0 && C.close(path_only) == 0, 623)
			mut link := [256]char{}
			check(C.snprintf(&link[0], 256, c'%s/link', &root[0]) > 0
				&& C.symlink(c'target', &link[0]) == 0
				&& C.snprintf(&link[0], 256, c'%s/absolute', &root[0]) > 0
				&& C.symlink(&target[0], &link[0]) == 0
				&& C.snprintf(&link[0], 256, c'%s/sub', &root[0]) > 0, 623)
			directory(&link[0])
		}
		mount_statfs_policy(&root[0], if noexec { u64(C.MS_NOEXEC) } else { u64(0) })
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 624)
		mount_statfs_policy(&root[0], if noexec { u64(0) } else { u64(C.MS_NOEXEC) })
		// A directory opened in the copy follows that copy's flags.
		dirfd := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
		fresh := if unlinked { -1 } else { C.open(&target[0], C.O_RDONLY) }
		fresh_path := if unlinked { -1 } else { C.open(&target[0], C.O_PATH) }
		check(dirfd >= 0 && (unlinked || (fresh >= 0 && fresh_path >= 0)), 624)
		report := mount_statfs_read(fd, nil, mount_statfs_expected(if noexec { u64(C.MS_NOEXEC) } else { u64(0) }))
		copied_report := mount_statfs_read(-1, &root[0], mount_statfs_expected(if noexec { u64(0) } else { u64(C.MS_NOEXEC) }))
		mount_statfs_same(report, copied_report)
		if retained >= 0 {
			for directory_fd in [retained, retained_path]! {
				saved := mount_statfs_read(int(directory_fd), nil, mount_statfs_expected(if noexec { u64(C.MS_NOEXEC) } else { u64(0) }))
				mount_statfs_same(saved, report)
			}
		}
		if owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 624) }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0 && (!unlinked || before.st_nlink == 0), 624)
		for iteration in 0 .. 4 {
			descriptor_exec_attempt(0, fd, c'', noexec, owner)
			descriptor_exec_attempt(0, pathfd, c'', noexec, owner)
			if retained >= 0 {
				for directory_fd in [retained, retained_path]! {
					for relative in [&char(c'target'), &char(c'link'), &char(c'sub/../target')]! {
						descriptor_exec_attempt(3, int(directory_fd), relative, noexec, owner)
					}
					// An absolute link resets the walk to the caller's root.
					descriptor_exec_attempt(3, int(directory_fd), c'absolute', !noexec, owner)
				}
			}
			if fresh >= 0 {
				descriptor_exec_attempt(0, fresh, c'', !noexec, owner)
				descriptor_exec_attempt(0, fresh_path, c'', !noexec, owner)
				descriptor_exec_attempt(1, -1234, &target[0], !noexec, owner)
				descriptor_exec_attempt(3, dirfd, c'target', !noexec, owner)
				descriptor_exec_attempt(2, -1, &target[0], !noexec, owner)
			}
		}
		if script {
			// The script's retained route does not exempt its interpreter.
			check(C.mount(&helper[0], &helper[0], nil, usize(C.MS_BIND), nil) == 0, 625)
			mount_statfs_policy(&helper[0], u64(C.MS_NOEXEC))
			for directory_fd in [retained, retained_path]! {
				descriptor_exec_attempt(3, int(directory_fd), c'target', true, owner)
			}
		}
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0 && after.st_nlink == before.st_nlink, 625)
		timestamp_identity(&after, &before)
		check(timestamp_equal(after.st_mtim, before.st_mtim) && timestamp_equal(after.st_ctim, before.st_ctim), 625)
		mut bytes := [2]u8{}
		check(C.read(fd, &bytes[0], 2) == 2 && bytes[0] == if script { u8(`#`) } else { u8(127) }
			&& bytes[1] == if script { u8(`!`) } else { u8(`E`) }, 625)
		check(C.close(fd) == 0 && C.close(pathfd) == 0 && C.close(dirfd) == 0
			&& (retained < 0 || (C.close(retained) == 0 && C.close(retained_path) == 0))
			&& (fresh < 0 || (C.close(fresh) == 0 && C.close(fresh_path) == 0)), 625)
	}
}

fn descriptor_exec_cases(selected int) {
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 626)
			if child == 0 { descriptor_exec_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCEXEC CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCEXEC: PASS')
		C.fflush(nil)
	}
}
