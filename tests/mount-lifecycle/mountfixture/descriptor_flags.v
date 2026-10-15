// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn descriptor_flags_matrix(fd int, fresh int, readonly bool) {
	unsafe {
		allowed := if readonly { fresh } else { fd }
		denied := if readonly { fd } else { fresh }
		mut identity := C.stat{}
		check(C.fstat(fd, &identity) == 0 && mount_flags_get(fd) == 0, 590)
		for iteration in 0 .. 64 {
			for wanted in [0x20, 0x10, 0x30, 0]! {
				mut before := C.stat{}
				check(C.fstat(fd, &before) == 0, 590)
				if denied >= 0 {
					mount_flags_set(denied, wanted, C.EROFS)
					mount_flags_set(denied, mount_flags_get(fd), C.EROFS)
					timestamp_unchanged(fd, &before)
				}
				if allowed < 0 { check(mount_flags_get(fd) == 0, 590); continue }
				mount_flags_set(allowed, wanted, 0)
				check(mount_flags_get(fd) == wanted && (fresh < 0 || mount_flags_get(fresh) == wanted), 590)
				check(C.fstat(fd, &before) == 0, 590)
				if denied >= 0 {
					// Clearing protection and repeating the current value both
					// require the actual description's mount to be writable.
					mount_flags_set(denied, wanted ^ 0x30, C.EROFS)
					mount_flags_set(denied, wanted, C.EROFS)
					timestamp_unchanged(fd, &before)
					check(mount_flags_get(fd) == wanted && mount_flags_get(fresh) == wanted, 590)
				}
			}
		}
		check(mount_flags_get(fd) == 0 && (fresh < 0 || mount_flags_get(fresh) == 0), 591)
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0, 591)
		child := C.fork()
		check(child >= 0, 591)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 591)
			for wanted in [0x20, 0x10, 0x30, 0]! {
				// Preserve Vinix's capability-before-mount error ordering.
				mount_flags_set(fd, wanted, C.EPERM)
				if fresh >= 0 { mount_flags_set(fresh, wanted, C.EPERM) }
				check(mount_flags_get(fd) == 0 && (fresh < 0 || mount_flags_get(fresh) == 0), 591)
			}
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(fd, &before)
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0, 591)
		timestamp_identity(&after, &identity)
	}
}

fn descriptor_flags_case(kind int) {
	unsafe {
		readonly := kind % 2 == 1
		is_directory := kind in [2, 3]
		unlinked := kind in [4, 5]
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 592)
		mut root := [256]char{}
		mut target := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/df-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0, 592)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 592)
		if is_directory { directory(&target[0]) } else { marker(&target[0]) }
		original := C.open(&target[0], C.O_RDONLY)
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		check(original >= 0 && fd >= 0 && C.close(original) == 0, 592)
		check(C.syscall(int(C.SYS_fchmod), i32(fd), u32(0o600)) == 0, 592)
		if unlinked { check(C.unlink(&target[0]) == 0, 592) }
		mount_statfs_remount(&root[0], readonly)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 593)
		mount_statfs_remount(&root[0], !readonly)
		fresh := if unlinked { -1 } else { C.open(&target[0], C.O_RDONLY) }
		check(unlinked || fresh >= 0, 593)
		report := mount_statfs_read(fd, nil, mount_statfs_expected(if readonly { u64(1) } else { u64(0) }))
		copied_report := mount_statfs_read(-1, &root[0], mount_statfs_expected(if readonly { u64(0) } else { u64(1) }))
		mount_statfs_same(report, copied_report)
		if !unlinked {
			expected := if readonly { 0 } else { -1 }
			check(C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &target[0], u32(0o600)) == expected, 593)
			if expected == -1 { check(*C.__errno_location() == C.EROFS, 593) }
		}
		descriptor_flags_matrix(fd, fresh, readonly)
		mut value := C.stat{}
		check(C.fstat(fd, &value) == 0 && (!unlinked || value.st_nlink == 0), 594)
		if !is_directory {
			mut bytes := [8]u8{}
			check(C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 594)
		}
		check(C.close(fd) == 0 && (fresh < 0 || C.close(fresh) == 0), 594)
	}
}

fn descriptor_flags_cases(selected int) {
	unsafe {
		for kind in 0 .. 6 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 595)
			if child == 0 { descriptor_flags_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCFLAGS CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCFLAGS: PASS')
		C.fflush(nil)
	}
}
