// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn descriptor_metadata_result(operation int, fd int, pathfd int, mode u32, uid u32, gid u32, expected int) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		result := match operation {
			0 { C.syscall(int(C.SYS_fchmod), i32(fd), mode) }
			1 { C.syscall(int(C.SYS_fchown), i32(fd), uid, gid) }
			else { C.syscall(int(C.SYS_fchownat), i32(if operation == 2 { fd } else { pathfd }), c'', uid, gid, i32(C.AT_EMPTY_PATH)) }
		}
		failure := *C.__errno_location()
		if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
		C.printf(c'MOUNT DESCMETA RESULT: operation=%ld result=%ld errno=%d expected=%ld\n',
			i64(operation), i64(result), failure, i64(expected))
		C.fflush(nil)
		check(false, 560)
	}
}

fn descriptor_metadata_matrix(fd int, pathfd int, fresh int, freshpath int, readonly bool, owner bool) {
	unsafe {
		mut original := C.stat{}
		check(C.fstat(fd, &original) == 0, 561)
		uid := if owner { u32(1000) } else { u32(0) }
		changed_uid := if owner { u32(1000) } else { u32(1001) }
		changed_gid := if owner { u32(1001) } else { u32(1002) }
		for iteration in 0 .. 64 {
			for operation in 0 .. 4 {
				for location in 0 .. if fresh >= 0 { 2 } else { 1 } {
					selected := if location == 0 { fd } else { fresh }
					selected_path := if location == 0 { pathfd } else { freshpath }
					denied := if location == 0 { readonly } else { !readonly }
					mut before := C.stat{}
					check(C.fstat(fd, &before) == 0, 561)
					descriptor_metadata_result(operation, selected, selected_path, 0o640, changed_uid, changed_gid,
						if denied { int(C.EROFS) } else { 0 })
					if denied {
						timestamp_unchanged(fd, &before)
					} else {
						metadata_stat(fd, if operation == 0 { u32(0o640) } else { u32(0o600) },
							if operation == 0 { uid } else { changed_uid },
							if operation == 0 { uid } else { changed_gid }, &original)
						check(C.syscall(int(C.SYS_fchown), i32(selected), uid, uid) == 0
							&& C.syscall(int(C.SYS_fchmod), i32(selected), u32(0o600)) == 0, 562)
					}
					metadata_stat(fd, 0o600, uid, uid, &original)
					if fresh >= 0 { metadata_stat(fresh, 0o600, uid, uid, &original) }
				}
			}
		}
	}
}

fn descriptor_metadata_denials(fd int, pathfd int, fresh int, freshpath int, readonly bool, owner bool) {
	unsafe {
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0, 563)
		child := C.fork()
		check(child >= 0, 563)
		if child == 0 {
			if !owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 563) }
			for operation in 0 .. 4 {
				// An owner may chmod but cannot assign another UID. The
				// nonowner child is refused for every metadata operation.
				if owner && operation == 0 { continue }
				descriptor_metadata_result(operation, fd, pathfd, 0o640, 2000, 2000,
					if readonly { int(C.EROFS) } else { int(C.EPERM) })
				if fresh >= 0 {
					descriptor_metadata_result(operation, fresh, freshpath, 0o640, 2000, 2000,
						if readonly { int(C.EPERM) } else { int(C.EROFS) })
				}
			}
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(fd, &before)
	}
}

fn descriptor_metadata_case(kind int) {
	unsafe {
		readonly := kind % 2 == 1
		is_directory := kind in [2, 3]
		unlinked := kind in [4, 5]
		owner := kind >= 6
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 564)
		mut root := [256]char{}
		mut target := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/dm-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0, 564)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 564)
		if is_directory { directory(&target[0]) } else { marker(&target[0]) }
		original := C.open(&target[0], C.O_RDONLY)
		pathfd := C.open(&target[0], C.O_PATH)
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		check(original >= 0 && pathfd >= 0 && fd >= 0 && C.close(original) == 0, 564)
		uid := if owner { u32(1000) } else { u32(0) }
		check(C.syscall(int(C.SYS_fchown), i32(fd), uid, uid) == 0
			&& C.syscall(int(C.SYS_fchmod), i32(fd), u32(0o600)) == 0, 564)
		if unlinked { check(C.unlink(&target[0]) == 0, 564) }
		mount_statfs_remount(&root[0], readonly)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 565)
		mount_statfs_remount(&root[0], !readonly)
		fresh := if unlinked { -1 } else { C.open(&target[0], C.O_RDONLY) }
		freshpath := if unlinked { -1 } else { C.open(&target[0], C.O_PATH) }
		check(unlinked || (fresh >= 0 && freshpath >= 0), 565)
		report := mount_statfs_read(fd, nil, mount_statfs_expected(if readonly { u64(1) } else { u64(0) }))
		copied_report := mount_statfs_read(-1, &root[0], mount_statfs_expected(if readonly { u64(0) } else { u64(1) }))
		mount_statfs_same(report, copied_report)
		if !unlinked {
			// Ordinary pathname updates continue to use the namespace copy.
			expected := if readonly { 0 } else { -1 }
			check(C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &target[0], u32(0o600)) == expected, 565)
			if expected == -1 { check(*C.__errno_location() == C.EROFS, 565) }
		}
		if owner {
			groups := [u32(1001)]!
			check(C.setgroups(1, &groups[0]) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 566)
		}
		descriptor_metadata_matrix(fd, pathfd, fresh, freshpath, readonly, owner)
		descriptor_metadata_denials(fd, pathfd, fresh, freshpath, readonly, owner)
		mut value := C.stat{}
		check(C.fstat(fd, &value) == 0 && (!unlinked || value.st_nlink == 0), 567)
		if !is_directory {
			mut bytes := [8]u8{}
			check(C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 567)
		}
		check(C.close(fd) == 0 && C.close(pathfd) == 0, 567)
		if fresh >= 0 { check(C.close(fresh) == 0 && C.close(freshpath) == 0, 567) }
	}
}

fn descriptor_metadata_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 568)
			if child == 0 { descriptor_metadata_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCMETA CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCMETA: PASS')
		C.fflush(nil)
	}
}
