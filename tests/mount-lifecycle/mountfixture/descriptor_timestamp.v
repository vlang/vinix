// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn descriptor_timestamp_result(operation int, fd int, pathfd int, values &C.timespec, form int, expected int) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		where := if operation == 0 { &char(nil) } else { &char(c'') }
		selected := if operation == 2 { pathfd } else { fd }
		flags := if operation == 0 { i32(0) } else { i32(C.AT_EMPTY_PATH) }
		result := C.syscall(int(C.SYS_utimensat), i32(selected), where,
			if form == 1 { voidptr(nil) } else { voidptr(values) }, flags)
		failure := *location
		if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
		C.printf(c'MOUNT DESCTIMES RESULT: operation=%ld form=%ld result=%ld errno=%d expected=%ld\n',
			i64(operation), i64(form), i64(result), failure, i64(expected))
		C.fflush(nil)
		check(false, 570)
	}
}

fn descriptor_timestamp_matrix(fd int, pathfd int, fresh int, freshpath int, readonly bool, _ bool) {
	unsafe {
		for iteration in 0 .. 64 {
			for operation in 0 .. 3 {
				for form in 0 .. 5 {
					for location in 0 .. if fresh >= 0 { 2 } else { 1 } {
						selected := if location == 0 { fd } else { fresh }
						selected_path := if location == 0 { pathfd } else { freshpath }
						denied := if location == 0 { readonly } else { !readonly }
						mut before := C.stat{}
						check(C.fstat(fd, &before) == 0, 571)
						mut values := [C.timespec{tv_sec: 1234000000 + iteration * 10 + operation, tv_nsec: 123456789},
							C.timespec{tv_sec: 1235000000 + iteration * 10 + operation, tv_nsec: 987654321}]!
						if form == 2 { values[0].tv_nsec = i64(C.UTIME_NOW); values[1].tv_nsec = i64(C.UTIME_NOW) }
						if form == 3 { values[1].tv_nsec = i64(C.UTIME_OMIT) }
						if form == 4 { values[0].tv_nsec = i64(C.UTIME_OMIT) }
						mut earliest := C.timespec{}
						mut latest := C.timespec{}
						check(C.clock_gettime(i32(C.CLOCK_REALTIME), &earliest) == 0, 571)
						descriptor_timestamp_result(operation, selected, selected_path, &values[0], form,
							if denied { int(C.EROFS) } else { 0 })
						check(C.clock_gettime(i32(C.CLOCK_REALTIME), &latest) == 0, 571)
						if denied { timestamp_unchanged(fd, &before); continue }
						mut after := C.stat{}
						check(C.fstat(fd, &after) == 0, 572)
						timestamp_identity(&after, &before)
						if form in [1, 2] {
							earliest.tv_sec--
							check(timestamp_le(earliest, after.st_atim) && timestamp_le(after.st_atim, latest)
								&& timestamp_le(earliest, after.st_mtim) && timestamp_le(after.st_mtim, latest), 572)
						} else {
							check(timestamp_equal(after.st_atim, if form == 4 { before.st_atim } else { values[0] })
								&& timestamp_equal(after.st_mtim, if form == 3 { before.st_mtim } else { values[1] }), 572)
						}
						if fresh >= 0 {
							mut alias := C.stat{}
							check(C.fstat(fresh, &alias) == 0 && timestamp_equal(alias.st_atim, after.st_atim)
								&& timestamp_equal(alias.st_mtim, after.st_mtim), 572)
						}
					}
				}
			}
		}
	}
}

fn descriptor_timestamp_denials(fd int, pathfd int, fresh int, freshpath int, readonly bool, owner bool) {
	unsafe {
		if owner { return }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0, 573)
		child := C.fork()
		check(child >= 0, 573)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 573)
			mut values := [C.timespec{tv_sec: 1234000000, tv_nsec: 123456789}, C.timespec{tv_sec: 1235000000, tv_nsec: 987654321}]!
			for operation in 0 .. 3 {
				for form in 0 .. 3 {
					values[0].tv_nsec = if form == 2 { i64(C.UTIME_NOW) } else { i64(123456789) }
					values[1].tv_nsec = if form == 2 { i64(C.UTIME_NOW) } else { i64(987654321) }
					permission := if form == 0 { int(C.EPERM) } else { int(C.EACCES) }
					descriptor_timestamp_result(operation, fd, pathfd, &values[0], form,
						if readonly { int(C.EROFS) } else { permission })
					if fresh >= 0 { descriptor_timestamp_result(operation, fresh, freshpath, &values[0], form,
						if readonly { permission } else { int(C.EROFS) }) }
				}
			}
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(fd, &before)
	}
}

fn descriptor_timestamp_case(kind int) {
	unsafe {
		readonly := kind % 2 == 1
		is_directory := kind in [2, 3]
		unlinked := kind in [4, 5]
		owner := kind >= 6
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 564)
		mut root := [256]char{}
		mut target := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/dt-%d', i32(kind)) > 0
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
		descriptor_timestamp_matrix(fd, pathfd, fresh, freshpath, readonly, owner)
		descriptor_timestamp_denials(fd, pathfd, fresh, freshpath, readonly, owner)
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

fn descriptor_timestamp_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 568)
			if child == 0 { descriptor_timestamp_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCTIMES CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCTIMES: PASS')
		C.fflush(nil)
	}
}
