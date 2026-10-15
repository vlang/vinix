// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn descriptor_access_result(fd int, path &char, mode int, flags int, expected int) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		result := C.syscall(int(C.SYS_faccessat2), i32(fd), path, i32(mode), i32(flags))
		failure := *location
		if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
		C.printf(c'MOUNT DESCACCESS RESULT: mode=%d flags=%x result=%ld errno=%d expected=%d\n',
			i32(mode), i32(flags), i64(result), failure, i32(expected))
		C.fflush(nil)
		check(false, 610)
	}
}

fn descriptor_access_expected(mode int, policy u64, dir bool) int {
	return mount_access_expected(mode, policy & u64(C.MS_RDONLY) != 0,
		!dir && policy & u64(C.MS_NOEXEC) != 0)
}

fn descriptor_access_matrix(data int, pathfd int, fresh_data int, fresh_path int,
	target &char, policy u64, copied u64, dir bool) {
	unsafe {
		for iteration in 0 .. 16 {
			for mode in 0 .. 8 {
				for flags in [int(0), int(C.AT_EACCESS), int(C.AT_SYMLINK_NOFOLLOW), int(C.AT_EACCESS | C.AT_SYMLINK_NOFOLLOW)]! {
					expected := descriptor_access_expected(mode, policy, dir)
					descriptor_access_result(data, c'', mode, flags | C.AT_EMPTY_PATH, expected)
					descriptor_access_result(pathfd, c'', mode, flags | C.AT_EMPTY_PATH, expected)
					if fresh_data >= 0 {
						fresh_expected := descriptor_access_expected(mode, copied, dir)
						descriptor_access_result(fresh_data, c'', mode, flags | C.AT_EMPTY_PATH, fresh_expected)
						descriptor_access_result(fresh_path, c'', mode, flags | C.AT_EMPTY_PATH, fresh_expected)
						descriptor_access_result(C.AT_FDCWD, target, mode, flags, fresh_expected)
					}
				}
			}
		}
	}
}

fn descriptor_access_case(kind int) {
	unsafe {
		unlinked := kind in [4, 5]
		dir := kind >= 6
		mask := if kind < 2 { u64(C.MS_RDONLY) } else if kind < 4 { u64(C.MS_NOEXEC) }
			else { u64(C.MS_RDONLY | C.MS_NOEXEC) }
		policy := if kind % 2 == 1 { mask } else { u64(0) }
		copied := if kind % 2 == 1 { u64(0) } else { mask }
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 611)
		mut root := [256]char{}
		mut target := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/da-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0, 611)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 611)
		if dir { directory(&target[0]) } else { marker(&target[0]) }
		data_flags := C.O_RDONLY | if dir { C.O_DIRECTORY } else { 0 }
		path_flags := C.O_PATH | if dir { C.O_DIRECTORY } else { 0 }
		original := C.open(&target[0], data_flags)
		original_path := C.open(&target[0], path_flags)
		data := int(C.syscall(int(C.SYS_dup), i32(original)))
		pathfd := int(C.syscall(int(C.SYS_dup), i32(original_path)))
		check(original >= 0 && original_path >= 0 && data >= 0 && pathfd >= 0
			&& C.close(original) == 0 && C.close(original_path) == 0, 611)
		check(C.syscall(int(C.SYS_fchown), i32(data), u32(1000), u32(1000)) == 0
			&& C.syscall(int(C.SYS_fchmod), i32(data), u32(0o777)) == 0, 611)
		if unlinked { check(C.unlink(&target[0]) == 0, 611) }
		mount_statfs_policy(&root[0], policy)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 612)
		mount_statfs_policy(&root[0], copied)
		fresh_data := if unlinked { -1 } else { C.open(&target[0], data_flags) }
		fresh_path := if unlinked { -1 } else { C.open(&target[0], path_flags) }
		check(unlinked || (fresh_data >= 0 && fresh_path >= 0), 612)
		report := mount_statfs_read(data, nil, mount_statfs_expected(policy))
		copied_report := mount_statfs_read(-1, &root[0], mount_statfs_expected(copied))
		mount_statfs_same(report, copied_report)
		mut before := C.stat{}
		check(C.fstat(data, &before) == 0 && (!unlinked || before.st_nlink == 0), 612)
		descriptor_access_matrix(data, pathfd, fresh_data, fresh_path, &target[0], policy, copied, dir)
		child := C.fork()
		check(child >= 0, 613)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 613)
			descriptor_access_matrix(data, pathfd, fresh_data, fresh_path, &target[0], policy, copied, dir)
			timestamp_unchanged(data, &before); timestamp_unchanged(pathfd, &before)
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(data, &before); timestamp_unchanged(pathfd, &before)
		if fresh_data >= 0 { timestamp_unchanged(fresh_data, &before); timestamp_unchanged(fresh_path, &before) }
		if !dir {
			mut bytes := [8]u8{}
			check(C.read(data, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 614)
		}
		check(C.close(data) == 0 && C.close(pathfd) == 0
			&& (fresh_data < 0 || (C.close(fresh_data) == 0 && C.close(fresh_path) == 0)), 614)
	}
}

fn descriptor_access_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 615)
			if child == 0 { descriptor_access_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCACCESS CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCACCESS: PASS')
		C.fflush(nil)
	}
}
