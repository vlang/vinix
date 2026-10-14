// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn mount_symlink_stat(dirfd int, path &char, value &C.stat) int {
	return int(C.syscall(int(C.SYS_newfstatat), i32(dirfd), path, value, i32(C.AT_SYMLINK_NOFOLLOW)))
}

fn mount_symlink_result(target &char, dirfd int, path &char, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := C.syscall(int(C.SYS_symlinkat), target, i32(dirfd), path)
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT SYMLINK RESULT: result=%ld errno=%d expected=%d\n', i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 450)
}

fn mount_symlink_absent(wdir int, rdir int, writable &char, readonly &char) {
	mut value := C.stat{}
	check(mount_symlink_stat(wdir, writable, &value) == -1
		&& unsafe { *C.__errno_location() } == C.ENOENT, 451)
	check(mount_symlink_stat(rdir, readonly, &value) == -1
		&& unsafe { *C.__errno_location() } == C.ENOENT, 451)
}

fn mount_symlink_value(dirfd int, path &char, target &char, original &C.stat) {
	unsafe {
		mut bytes := [256]u8{}
		length := C.strlen(target)
		check(C.syscall(int(C.SYS_readlinkat), i32(dirfd), path, &bytes[0], usize(256)) == isize(length)
			&& C.memcmp(&bytes[0], target, length) == 0, 452)
		mut value := C.stat{}
		check(mount_symlink_stat(dirfd, path, &value) == 0, 452)
		timestamp_identity(&value, original)
	}
}

fn mount_symlink_pair(wdir int, rdir int, writable &char, readonly &char, round int) {
	unsafe {
		// Linux tmpfs defaults to a world-writable root. Make the DAC
		// denial precondition explicit on both systems before measuring it.
		check(C.syscall(int(C.SYS_fchmodat), i32(wdir), writable, u32(0o755)) == 0, 453)
		wparent := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rparent := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		check(wparent >= 0 && rparent >= 0, 453)
		mut path := [512]char{}
		check(C.snprintf(&path[0], 512, c'%s/marker', writable) > 0, 453)
		data := C.openat(wdir, &path[0], C.O_RDONLY)
		mut marker_before := C.stat{}
		check(data >= 0 && C.fstat(data, &marker_before) == 0, 453)
		mut wname := [512]char{}
		mut rname := [512]char{}
		for iteration in 0 .. 32 {
			for form in 0 .. 2 {
				target := if form == 0 { &char(c'marker') } else { &char(c'missing/../literal//target') }
				check(C.snprintf(&wname[0], 512, c'%s/link-%d-%d-%d', writable, i32(round), i32(iteration), i32(form)) > 0
					&& C.snprintf(&rname[0], 512, c'%s/link-%d-%d-%d', readonly, i32(round), i32(iteration), i32(form)) > 0, 453)
				mut before := C.stat{}
				check(C.fstat(wparent, &before) == 0, 454)
				mount_symlink_result(target, rdir, &rname[0], C.EROFS)
				mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
				timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before)
				mount_symlink_result(target, wdir, &wname[0], 0)
				mut created := C.stat{}
				check(mount_symlink_stat(wdir, &wname[0], &created) == 0
					&& created.st_mode & C.S_IFMT == C.S_IFLNK && created.st_size == i64(C.strlen(target))
					&& created.st_uid == 0 && created.st_gid == 0, 455)
				mount_symlink_value(wdir, &wname[0], target, &created)
				mount_symlink_value(rdir, &rname[0], target, &created)
			}
		}
		check(C.snprintf(&wname[0], 512, c'%s/denied-%d', writable, i32(round)) > 0
			&& C.snprintf(&rname[0], 512, c'%s/denied-%d', readonly, i32(round)) > 0, 456)
		mut before := C.stat{}
		check(C.fstat(wparent, &before) == 0, 456)
		child := C.fork()
		check(child >= 0, 456)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 456)
			mount_symlink_result(c'missing/../literal//target', wdir, &wname[0], C.EACCES)
			mount_symlink_result(c'missing/../literal//target', rdir, &rname[0], C.EROFS)
			C._exit(0)
		}
		wait_child(child)
		mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
		timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before)
		mut bytes := [8]u8{}
		mut marker_after := C.stat{}
		check(C.read(data, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.fstat(data, &marker_after) == 0, 456)
		timestamp_identity(&marker_after, &marker_before)
		check(C.close(data) == 0 && C.close(wparent) == 0 && C.close(rparent) == 0, 456)
	}
}

fn mount_symlink_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 457)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/sp-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 457)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 457)
			mount_symlink_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0)
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
			mount_symlink_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 457)
			mount_symlink_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_symlink_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1)
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_symlink_pair(-999, -999, &source_link[0], &alias_link[0], 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_symlink_pair(-999, -999, &alias_link[0], &source_link[0], 1)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 457)
			mount_symlink_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 6 {
			mount_symlink_pair(alias_fd, source_fd, c'.', c'.', 0)
		} else {
			mount_symlink_pair(source_fd, alias_fd, c'.', c'.', 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_symlink_pair(alias_fd, source_fd, c'.', c'.', 1)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 457)
	}
}

fn mount_symlink_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 458)
			if child == 0 { mount_symlink_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT SYMLINK CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT SYMLINK: PASS')
		C.fflush(nil)
	}
}
