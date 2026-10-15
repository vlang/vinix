// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn mount_unlink_result(dirfd int, path &char, directory bool, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := C.syscall(int(C.SYS_unlinkat), i32(dirfd), path, i32(if directory { C.AT_REMOVEDIR } else { 0 }))
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT UNLINK RESULT: directory=%d result=%ld errno=%d expected=%d\n', i32(if directory { 1 } else { 0 }), i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 460)
}

fn mount_unlink_pair(wdir int, rdir int, writable &char, readonly &char, round int) {
	unsafe {
		check(C.syscall(int(C.SYS_fchmodat), i32(wdir), writable, u32(0o755)) == 0, 461)
		wparent := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rparent := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		check(wparent >= 0 && rparent >= 0, 461)
		mut wname := [512]char{}
		mut rname := [512]char{}
		for iteration in 0 .. 16 {
			for form in 0 .. 3 {
				check(C.snprintf(&wname[0], 512, c'%s/remove-%d-%d-%d', writable, i32(round), i32(iteration), i32(form)) > 0
					&& C.snprintf(&rname[0], 512, c'%s/remove-%d-%d-%d', readonly, i32(round), i32(iteration), i32(form)) > 0, 461)
				if form == 0 {
					fd := C.openat(wdir, &wname[0], C.O_CREAT | C.O_EXCL | C.O_WRONLY, u32(0o600))
					check(fd >= 0 && C.write(fd, c'MOUNT-OK', 8) == 8 && C.close(fd) == 0, 462)
				} else if form == 1 {
					mount_symlink_result(c'marker', wdir, &wname[0], 0)
				} else { check(C.mkdirat(i32(wdir), &wname[0], u32(0o700)) == 0, 462) }
				mut original := C.stat{}
				mut before := C.stat{}
				check(mount_symlink_stat(wdir, &wname[0], &original) == 0 && C.fstat(wparent, &before) == 0, 462)
				held := C.openat(wdir, &wname[0], if form == 0 { C.O_RDONLY } else { C.O_PATH | C.O_NOFOLLOW })
				check(held >= 0, 462)
				mount_unlink_result(rdir, &rname[0], form == 2, C.EROFS)
				// Complete one authorized removal before testing denials.
				if iteration == 1 {
					child := C.fork()
					check(child >= 0, 463)
					if child == 0 {
						check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 463)
						mount_unlink_result(wdir, &wname[0], form == 2, C.EACCES)
						mount_unlink_result(rdir, &rname[0], form == 2, C.EROFS)
						C._exit(0)
					}
					wait_child(child)
				}
				timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before)
				mut preserved := C.stat{}
				check(mount_symlink_stat(rdir, &rname[0], &preserved) == 0, 464)
				timestamp_identity(&preserved, &original)
				if form == 1 { mount_symlink_value(rdir, &rname[0], c'marker', &original) }
				mount_unlink_result(wdir, &wname[0], form == 2, 0)
				mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
				mut orphan := C.stat{}
				check(C.fstat(held, &orphan) == 0 && orphan.st_dev == original.st_dev && orphan.st_ino == original.st_ino
					&& orphan.st_mode == original.st_mode && orphan.st_uid == original.st_uid && orphan.st_gid == original.st_gid, 465)
				if form == 0 {
					mut bytes := [8]u8{}
					check(C.read(held, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 465)
				}
				check(C.close(held) == 0, 465)
			}
		}
		check(C.snprintf(&wname[0], 512, c'%s/marker', writable) > 0, 466)
		fd := C.openat(wdir, &wname[0], C.O_RDONLY)
		mut bytes := [8]u8{}
		check(fd >= 0 && C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 466)
		check(C.close(fd) == 0 && C.close(wparent) == 0 && C.close(rparent) == 0, 466)
	}
}

fn mount_unlink_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 457)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/up-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 457)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 457)
			mount_unlink_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 457)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 457)
		marker(&path[0])
		mut source_link := [256]char{}
		mut alias_link := [256]char{}
		if kind == 3 {
			check(C.snprintf(&source_link[0], 256, c'%s/source-link', &base[0]) > 0
				&& C.snprintf(&alias_link[0], 256, c'%s/alias-link', &base[0]) > 0
				&& C.symlink(&source[0], &source_link[0]) == 0 && C.symlink(&alias[0], &alias_link[0]) == 0, 457)
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 457)
		if kind == 6 { bind_policy_remount(&source[0], true) } else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 457) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 457)
		if kind == 7 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 457)
			mount_unlink_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 457)
			mount_unlink_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_unlink_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1)
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_unlink_pair(-999, -999, &source_link[0], &alias_link[0], 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_unlink_pair(-999, -999, &alias_link[0], &source_link[0], 1)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 457)
			mount_unlink_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 6 {
			mount_unlink_pair(alias_fd, source_fd, c'.', c'.', 0)
		} else {
			mount_unlink_pair(source_fd, alias_fd, c'.', c'.', 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_unlink_pair(alias_fd, source_fd, c'.', c'.', 1)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 457)
	}
}

fn mount_unlink_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 458)
			if child == 0 { mount_unlink_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT UNLINK CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT UNLINK: PASS')
		C.fflush(nil)
	}
}
