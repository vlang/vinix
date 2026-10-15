// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn mount_node_device_result(dirfd int, path &char, mode u32, dev u32, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := C.syscall(int(C.SYS_mknodat), i32(dirfd), path, mode, dev)
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT NODE RESULT: mode=%o result=%ld errno=%d expected=%d\n', mode, i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 510)
}

fn mount_node_result(dirfd int, path &char, mode u32, expected int) {
	mount_node_device_result(dirfd, path, mode, 0, expected)
}

fn mount_node_pair(wdir int, rdir int, writable &char, readonly &char, round int) {
	unsafe {
		check(C.syscall(int(C.SYS_fchmodat), i32(wdir), writable, u32(0o755)) == 0, 511)
		wparent := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rparent := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		check(wparent >= 0 && rparent >= 0, 511)
		mut path := [512]char{}
		check(C.snprintf(&path[0], 512, c'%s/marker', writable) > 0, 511)
		data := C.openat(wdir, &path[0], C.O_RDONLY)
		mut original := C.stat{}
		check(data >= 0 && C.fstat(data, &original) == 0, 511)
		saved := C.umask(0o027)
		mut wname := [512]char{}
		mut rname := [512]char{}
		for iteration in 0 .. 16 {
			for form, kind in [u32(0), u32(C.S_IFREG), u32(C.S_IFIFO), u32(C.S_IFCHR), u32(C.S_IFBLK)]! {
				mode := kind | u32(0o777)
				check(C.snprintf(&wname[0], 512, c'%s/node-%d-%d-%d', writable, i32(round), i32(iteration), i32(form)) > 0
					&& C.snprintf(&rname[0], 512, c'%s/node-%d-%d-%d', readonly, i32(round), i32(iteration), i32(form)) > 0, 511)
				mut before := C.stat{}
				check(C.fstat(wparent, &before) == 0, 511)
				mount_node_result(rdir, &rname[0], mode, C.EROFS)
				mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
				timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before)
				mount_node_result(wdir, &wname[0], mode, 0)
				mut created := C.stat{}
				mut alias := C.stat{}
				actual := if kind == 0 { u32(C.S_IFREG) } else { kind }
				check(mount_symlink_stat(wdir, &wname[0], &created) == 0
					&& mount_symlink_stat(rdir, &rname[0], &alias) == 0
					&& created.st_mode == (actual | u32(0o750)) && created.st_uid == 0 && created.st_gid == 0
					&& created.st_ino != 0 && created.st_nlink == 1 && created.st_dev == before.st_dev
					&& created.st_rdev == 0, 512)
				timestamp_identity(&alias, &created)
				mount_node_result(wdir, &wname[0], mode, C.EEXIST)
				if actual == C.S_IFREG || actual == C.S_IFIFO {
					fd := C.openat(wdir, &wname[0], C.O_RDWR | C.O_NONBLOCK)
					check(fd >= 0 && C.write(fd, c'MOUNT-OK', 8) == 8, 512)
					if actual == C.S_IFREG { check(C.syscall(int(C.SYS_lseek), i32(fd), i64(0), i32(C.SEEK_SET)) == 0, 512) }
					mut bytes := [8]u8{}
					check(C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0 && C.close(fd) == 0, 512)
				}
			}
		}
		check(C.snprintf(&wname[0], 512, c'%s/denied-%d', writable, i32(round)) > 0
			&& C.snprintf(&rname[0], 512, c'%s/denied-%d', readonly, i32(round)) > 0, 513)
		// Isolate CAP_MKNOD denial from directory DAC and Linux's 0/0
		// whiteout exception: use a writable directory and a nonzero device.
		mut capname := [512]char{}
		check(C.snprintf(&capname[0], 512, c'%s/cap-%d', writable, i32(round)) > 0
			&& C.syscall(int(C.SYS_mkdirat), i32(wdir), &capname[0], u32(0o777)) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(wdir), &capname[0], u32(0o777)) == 0, 513)
		capfd := C.openat(wdir, &capname[0], C.O_PATH | C.O_DIRECTORY)
		check(capfd >= 0, 513)
		mut before := C.stat{}
		check(C.fstat(wparent, &before) == 0, 513)
		child := C.fork()
		check(child >= 0, 513)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 513)
			for kind in [u32(0), u32(C.S_IFREG), u32(C.S_IFIFO)]! {
				mount_node_result(wdir, &wname[0], kind | u32(0o600), C.EACCES)
				mount_node_result(rdir, &rname[0], kind | u32(0o600), C.EROFS)
			}
			for kind in [u32(C.S_IFCHR), u32(C.S_IFBLK)]! { mount_node_device_result(capfd, c'denied-device', kind | u32(0o600), 0x103, C.EPERM) }
			C._exit(0)
		}
		wait_child(child)
		mount_symlink_absent(capfd, capfd, c'denied-device', c'denied-device')
		mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
		timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before)
		mut bytes := [8]u8{}
		mut after := C.stat{}
		check(C.read(data, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0 && C.fstat(data, &after) == 0, 513)
		timestamp_identity(&after, &original)
		C.umask(saved)
		check(C.close(capfd) == 0 && C.close(data) == 0 && C.close(wparent) == 0 && C.close(rparent) == 0, 513)
	}
}

fn mount_node_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 514)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/nd-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 514)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 514)
			mount_node_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 514)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 514)
		marker(&path[0])
		mut source_link := [256]char{}
		mut alias_link := [256]char{}
		if kind == 3 {
			check(C.snprintf(&source_link[0], 256, c'%s/source-link', &base[0]) > 0
				&& C.snprintf(&alias_link[0], 256, c'%s/alias-link', &base[0]) > 0
				&& C.symlink(&source[0], &source_link[0]) == 0 && C.symlink(&alias[0], &alias_link[0]) == 0, 514)
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 514)
		if kind == 6 { bind_policy_remount(&source[0], true) } else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 514) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 514)
		if kind == 7 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 514)
			mount_node_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 514)
			mount_node_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_node_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1)
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_node_pair(-999, -999, &source_link[0], &alias_link[0], 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_node_pair(-999, -999, &alias_link[0], &source_link[0], 1)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 514)
			mount_node_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 6 {
			mount_node_pair(alias_fd, source_fd, c'.', c'.', 0)
		} else {
			mount_node_pair(source_fd, alias_fd, c'.', c'.', 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_node_pair(alias_fd, source_fd, c'.', c'.', 1)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 514)
	}
}

fn mount_node_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 515)
			if child == 0 { mount_node_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT NODE CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT NODES: PASS')
		C.fflush(nil)
	}
}
