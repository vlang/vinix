// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn descriptor_xattr_result(fd int, name &char, value voidptr, size usize, flags int, removing bool, expected int) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		result := mount_xattr_write(2, c'', fd, name, value, size, flags, removing)
		failure := *location
		if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
		C.printf(c'MOUNT DESCXATTR RESULT: removing=%ld flags=%ld result=%ld errno=%d expected=%ld\n',
			i64(int(removing)), i64(flags), i64(result), failure, i64(expected))
		C.fflush(nil)
		check(false, 580)
	}
}

fn descriptor_xattr_seed(fd int) {
	unsafe {
		first := [u8(0), 255, 17, 0, 81]!
		descriptor_xattr_result(fd, c'user.descriptor-mount', &first[0], 5, 1, false, 0)
		descriptor_xattr_result(fd, c'trusted.descriptor-mount', &first[0], 5, 1, false, 0)
	}
}

fn descriptor_xattr_observe(fd int, fresh int, name &char, value voidptr, size usize, present bool) {
	unsafe {
		mount_xattr_value(2, c'', fd, name, value, size, present)
		mount_xattr_names(2, c'', fd, name, present)
		if fresh >= 0 {
			mount_xattr_value(2, c'', fresh, name, value, size, present)
			mount_xattr_names(2, c'', fresh, name, present)
		}
	}
}

fn descriptor_xattr_matrix(fd int, _ int, fresh int, _ int, readonly bool, owner bool) {
	unsafe {
		first := [u8(0), 255, 17, 0, 81]!
		next := [u8(55), 0, 254, 91, 1]!
		allowed := if readonly { fresh } else { fd }
		denied := if readonly { fd } else { fresh }
		mut identity := C.stat{}
		check(C.fstat(fd, &identity) == 0, 581)
		for iteration in 0 .. 64 {
			for namespace in 0 .. if owner { 1 } else { 2 } {
				name := if namespace == 0 { &char(c'user.descriptor-mount') } else { &char(c'trusted.descriptor-mount') }
				descriptor_xattr_observe(fd, fresh, name, &first[0], 5, true)
				mut before := C.stat{}
				check(C.fstat(fd, &before) == 0, 581)
				if denied >= 0 {
					descriptor_xattr_result(denied, name, &next[0], 5, 2, false, C.EROFS)
					descriptor_xattr_result(denied, name, nil, 0, 0, true, C.EROFS)
					timestamp_unchanged(fd, &before)
				}
				if allowed < 0 { continue }
				descriptor_xattr_result(allowed, name, &next[0], 5, 2, false, 0)
				descriptor_xattr_observe(fd, fresh, name, &next[0], 5, true)
				descriptor_xattr_result(allowed, name, nil, 0, 2, false, 0)
				descriptor_xattr_observe(fd, fresh, name, nil, 0, true)
				descriptor_xattr_result(allowed, name, nil, 0, 0, true, 0)
				descriptor_xattr_observe(fd, fresh, name, nil, 0, false)
				check(C.fstat(fd, &before) == 0, 582)
				descriptor_xattr_result(allowed, name, &next[0], 5, 2, false, C.ENODATA)
				if denied >= 0 {
					descriptor_xattr_result(denied, name, &next[0], 5, 1, false, C.EROFS)
					descriptor_xattr_result(denied, name, nil, 0, 0, true, C.EROFS)
				}
				timestamp_unchanged(fd, &before)
				descriptor_xattr_result(allowed, name, &first[0], 5, 1, false, 0)
				check(C.fstat(fd, &before) == 0, 582)
				descriptor_xattr_result(allowed, name, &next[0], 5, 1, false, C.EEXIST)
				timestamp_unchanged(fd, &before)
				descriptor_xattr_observe(fd, fresh, name, &first[0], 5, true)
			}
		}
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0, 583)
		timestamp_identity(&after, &identity)
	}
}

fn descriptor_xattr_denials(fd int, _ int, fresh int, _ int, readonly bool, owner bool) {
	unsafe {
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0, 584)
		child := C.fork()
		check(child >= 0, 584)
		if child == 0 {
			if !owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 584) }
			for namespace in 0 .. 2 {
				if owner && namespace == 0 { continue }
				name := if namespace == 0 { &char(c'user.descriptor-mount') } else { &char(c'trusted.descriptor-mount') }
				permission := if namespace == 0 { int(C.EACCES) } else { int(C.EPERM) }
				descriptor_xattr_result(fd, name, c'bad', 3, 2, false, if readonly { int(C.EROFS) } else { permission })
				descriptor_xattr_result(fd, name, nil, 0, 0, true, if readonly { int(C.EROFS) } else { permission })
				if fresh >= 0 {
					descriptor_xattr_result(fresh, name, c'bad', 3, 2, false, if readonly { permission } else { int(C.EROFS) })
					descriptor_xattr_result(fresh, name, nil, 0, 0, true, if readonly { permission } else { int(C.EROFS) })
				}
				if namespace == 1 {
					mount_xattr_value(2, c'', fd, name, nil, 0, false)
					mount_xattr_names(2, c'', fd, name, false)
				}
			}
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(fd, &before)
	}
}

fn descriptor_xattr_case(kind int) {
	unsafe {
		readonly := kind % 2 == 1
		is_directory := kind in [2, 3]
		unlinked := kind in [4, 5]
		owner := kind >= 6
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 564)
		mut root := [256]char{}
		mut target := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/dx-%d', i32(kind)) > 0
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
		descriptor_xattr_seed(fd)
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
			first := [u8(0), 255, 17, 0, 81]!
			mount_xattr_result(0, &target[0], -1, c'user.descriptor-mount', &first[0], 5, 2, false,
				if readonly { 0 } else { int(C.EROFS) })
			// Ordinary pathname updates continue to use the namespace copy.
			expected := if readonly { 0 } else { -1 }
			check(C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &target[0], u32(0o600)) == expected, 565)
			if expected == -1 { check(*C.__errno_location() == C.EROFS, 565) }
		}
		if owner {
			groups := [u32(1001)]!
			check(C.setgroups(1, &groups[0]) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 566)
		}
		descriptor_xattr_matrix(fd, pathfd, fresh, freshpath, readonly, owner)
		descriptor_xattr_denials(fd, pathfd, fresh, freshpath, readonly, owner)
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

fn descriptor_xattr_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 568)
			if child == 0 { descriptor_xattr_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCXATTR CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCXATTR: PASS')
		C.fflush(nil)
	}
}
