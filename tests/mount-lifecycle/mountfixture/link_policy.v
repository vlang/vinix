// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn mount_link_hardlink_policy() {
	unsafe {
		// Vinix always protects foreign hard links. Configure the same
		// policy in an owned Linux reference VM when its sysctl exists.
		fd := C.open(c'/proc/sys/fs/protected_hardlinks', C.O_WRONLY)
		if fd < 0 { check(*C.__errno_location() == C.ENOENT, 479); return }
		check(C.write(fd, c'1\n', 2) == 2 && C.close(fd) == 0, 479)
		readback := C.open(c'/proc/sys/fs/protected_hardlinks', C.O_RDONLY)
		mut value := [8]u8{}
		check(readback >= 0 && C.read(readback, &value[0], 8) > 0 && value[0] == `1` && C.close(readback) == 0, 479)
	}
}

fn mount_link_result(odir int, old &char, ndir int, name &char, flags int, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := C.syscall(int(C.SYS_linkat), i32(odir), old, i32(ndir), name, i32(flags))
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT LINK RESULT: flags=%d result=%ld errno=%d expected=%d\n', i32(flags), i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 470)
}

fn mount_link_count(fd int, expected u64) {
	mut value := C.stat{}
	check(C.fstat(fd, &value) == 0 && value.st_nlink == expected, 471)
}

fn mount_link_pair(wdir int, rdir int, writable &char, readonly &char, round int) {
	unsafe {
		check(C.syscall(int(C.SYS_fchmodat), i32(wdir), writable, u32(0o755)) == 0, 472)
		mut wsource := [512]char{}
		mut rsource := [512]char{}
		mut wlink := [512]char{}
		mut rlink := [512]char{}
		mut owned := [512]char{}
		mut rowned := [512]char{}
		mut public_dir := [512]char{}
		mut public_name := [512]char{}
		mut wname := [512]char{}
		mut rname := [512]char{}
		check(C.snprintf(&wsource[0], 512, c'%s/marker', writable) > 0 && C.snprintf(&rsource[0], 512, c'%s/marker', readonly) > 0
			&& C.snprintf(&wlink[0], 512, c'%s/seed-link-%d', writable, i32(round)) > 0
			&& C.snprintf(&rlink[0], 512, c'%s/seed-link-%d', readonly, i32(round)) > 0
			&& C.snprintf(&owned[0], 512, c'%s/owned-%d', writable, i32(round)) > 0
			&& C.snprintf(&rowned[0], 512, c'%s/owned-%d', readonly, i32(round)) > 0
			&& C.snprintf(&public_dir[0], 512, c'%s/public-%d', writable, i32(round)) > 0
			&& C.snprintf(&public_name[0], 512, c'%s/blocked', &public_dir[0]) > 0, 472)
		mount_symlink_result(c'marker', wdir, &wlink[0], 0)
		owner := C.openat(wdir, &owned[0], C.O_CREAT | C.O_EXCL | C.O_WRONLY, u32(0o600))
		check(owner >= 0 && C.close(owner) == 0
			&& C.syscall(int(C.SYS_fchownat), i32(wdir), &owned[0], u32(1000), u32(1000), i32(0)) == 0
			&& C.mkdirat(i32(wdir), &public_dir[0], u32(0o777)) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(wdir), &public_dir[0], u32(0o777)) == 0, 472)
		wparent := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rparent := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		public_fd := C.openat(wdir, &public_dir[0], C.O_PATH | C.O_DIRECTORY)
		data := C.openat(wdir, &wsource[0], C.O_RDONLY)
		seed := C.openat(wdir, &wlink[0], C.O_PATH | C.O_NOFOLLOW)
		check(wparent >= 0 && rparent >= 0 && public_fd >= 0 && data >= 0 && seed >= 0, 472)
		for iteration in 0 .. 16 {
			for form in 0 .. 2 {
				old := if form == 0 { &char(&wsource[0]) } else { &char(&wlink[0]) }
				rold := if form == 0 { &char(&rsource[0]) } else { &char(&rlink[0]) }
				flags := if form == 0 { 0 } else { int(C.AT_SYMLINK_FOLLOW) }
				check(C.snprintf(&wname[0], 512, c'%s/hard-%d-%d-%d', writable, i32(round), i32(iteration), i32(form)) > 0
					&& C.snprintf(&rname[0], 512, c'%s/hard-%d-%d-%d', readonly, i32(round), i32(iteration), i32(form)) > 0, 473)
				mut before := C.stat{}
				mut original := C.stat{}
				check(C.fstat(wparent, &before) == 0 && C.fstat(data, &original) == 0, 473)
				mount_link_result(rdir, rold, rdir, &rname[0], flags, C.EROFS)
				mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
				timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before); timestamp_unchanged(data, &original)
				mount_link_count(data, original.st_nlink)
				mount_link_result(wdir, old, wdir, &wname[0], flags, 0)
				mut created := C.stat{}
				check(mount_symlink_stat(wdir, &wname[0], &created) == 0 && created.st_nlink == original.st_nlink + 1, 474)
				timestamp_identity(&created, &original)
				check(mount_symlink_stat(rdir, &rname[0], &created) == 0 && created.st_nlink == original.st_nlink + 1, 474)
				timestamp_identity(&created, &original)
				fd := C.openat(wdir, &wname[0], C.O_RDONLY)
				mut bytes := [8]u8{}
				check(fd >= 0 && C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0 && C.close(fd) == 0, 474)
				mount_link_count(seed, 1)
				mount_unlink_result(wdir, &wname[0], false, 0)
				mount_link_count(data, original.st_nlink)
				mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
			}
		}
		check(C.snprintf(&wname[0], 512, c'%s/cross-%d', writable, i32(round)) > 0
			&& C.snprintf(&rname[0], 512, c'%s/cross-%d', readonly, i32(round)) > 0, 475)
		mut parent_before := C.stat{}
		mut public_before := C.stat{}
		mut source_before := C.stat{}
		check(C.fstat(wparent, &parent_before) == 0 && C.fstat(public_fd, &public_before) == 0 && C.fstat(data, &source_before) == 0, 475)
		mount_link_result(rdir, &rsource[0], wdir, &wname[0], 0, C.EXDEV)
		mount_link_result(wdir, &wsource[0], rdir, &rname[0], 0, C.EROFS)
		child := C.fork()
		check(child >= 0, 475)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 475)
			mount_link_result(wdir, &owned[0], wdir, &wname[0], 0, C.EACCES)
			mount_link_result(rdir, &rowned[0], rdir, &rname[0], 0, C.EROFS)
			mount_link_result(wdir, &wsource[0], wdir, &public_name[0], 0, C.EPERM)
			C._exit(0)
		}
		wait_child(child)
		mount_symlink_absent(wdir, rdir, &wname[0], &rname[0])
		mut absent := C.stat{}
		check(mount_symlink_stat(wdir, &public_name[0], &absent) == -1 && *C.__errno_location() == C.ENOENT, 475)
		timestamp_unchanged(wparent, &parent_before); timestamp_unchanged(rparent, &parent_before)
		timestamp_unchanged(public_fd, &public_before); timestamp_unchanged(data, &source_before)
		mount_link_count(data, source_before.st_nlink)
		mut link_before := C.stat{}
		check(C.fstat(seed, &link_before) == 0, 475)
		mount_symlink_value(wdir, &wlink[0], c'marker', &link_before)
		check(C.close(data) == 0 && C.close(seed) == 0 && C.close(public_fd) == 0 && C.close(wparent) == 0 && C.close(rparent) == 0, 475)
	}
}

fn mount_link_identity_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 476)
		mut base := [256]char{}
		mut source := [256]char{}
		mut other := [256]char{}
		mut path := [512]char{}
		mut target := [512]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/lp-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0 && C.snprintf(&other[0], 256, c'%s/other', &base[0]) > 0, 476)
		directory(&base[0]); directory(&source[0]); directory(&other[0])
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 512, c'%s/marker', &source[0]) > 0, 476)
		marker(&path[0])
		if kind == 8 { check(C.mount(&source[0], &other[0], nil, usize(C.MS_BIND), nil) == 0, 476) }
		else {
			check(C.mount(c'tmpfs', &other[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&target[0], 512, c'%s/marker', &other[0]) > 0, 476)
			marker(&target[0])
			check(C.snprintf(&path[0], 512, c'%s/redirect', &source[0]) > 0 && C.symlink(&target[0], &path[0]) == 0, 476)
		}
		src := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		dst := C.open(&other[0], C.O_PATH | C.O_DIRECTORY)
		check(src >= 0 && dst >= 0, 476)
		if kind == 8 {
			mut before := C.stat{}
			check(C.fstat(src, &before) == 0, 477)
			mount_link_result(src, c'marker', dst, c'blocked', 0, C.EXDEV)
			mount_link_result(dst, c'marker', src, c'blocked', 0, C.EXDEV)
			mount_symlink_absent(src, dst, c'blocked', c'blocked')
			timestamp_unchanged(src, &before); timestamp_unchanged(dst, &before)
			check(C.mkdirat(i32(src), c'inside', u32(0o755)) == 0, 477)
			mount_link_result(src, c'marker', src, c'inside/local', 0, 0)
			mount_unlink_result(src, c'inside/local', false, 0)
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 477)
			fresh := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
			check(fresh >= 0, 477)
			mount_link_result(src, c'marker', fresh, c'blocked', 0, C.EXDEV)
			mount_link_result(fresh, c'marker', src, c'blocked', 0, C.EXDEV)
			mount_symlink_absent(src, fresh, c'blocked', c'blocked')
			for fd in [src, fresh]! {
				mount_link_result(fd, c'marker', fd, c'local', 0, 0)
				mount_unlink_result(fd, c'local', false, 0)
			}
			check(C.close(fresh) == 0, 477)
		} else {
			mount_link_result(src, c'redirect', dst, c'followed', int(C.AT_SYMLINK_FOLLOW), 0)
			mut original := C.stat{}
			mut linked := C.stat{}
			check(mount_symlink_stat(dst, c'marker', &original) == 0 && mount_symlink_stat(dst, c'followed', &linked) == 0
				&& linked.st_nlink == 2, 478)
			timestamp_identity(&linked, &original)
			mount_unlink_result(dst, c'followed', false, 0)
			mount_link_result(src, c'redirect', src, c'blocked', int(C.AT_SYMLINK_FOLLOW), C.EXDEV)
			mount_symlink_absent(src, dst, c'blocked', c'blocked')
			mount_symlink_result(c'missing', src, c'dangling', 0)
			mount_link_result(src, c'dangling', src, c'blocked', int(C.AT_SYMLINK_FOLLOW), C.ENOENT)
			mount_link_result(src, c'.', src, c'blocked', 0, C.EPERM)
			mount_symlink_absent(src, dst, c'blocked', c'blocked')
		}
		check(C.close(src) == 0 && C.close(dst) == 0, 478)
	}
}

fn mount_link_case(kind int) {
	unsafe {
		if kind >= 8 { mount_link_identity_case(kind); return }
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 457)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/lp-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 457)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 457)
			mount_link_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0)
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
			mount_link_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 457)
			mount_link_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_link_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1)
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_link_pair(-999, -999, &source_link[0], &alias_link[0], 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_link_pair(-999, -999, &alias_link[0], &source_link[0], 1)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 457)
			mount_link_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 6 {
			mount_link_pair(alias_fd, source_fd, c'.', c'.', 0)
		} else {
			mount_link_pair(source_fd, alias_fd, c'.', c'.', 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_link_pair(alias_fd, source_fd, c'.', c'.', 1)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 457)
	}
}

fn mount_link_cases(selected int) {
	mount_link_hardlink_policy()
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 458)
			if child == 0 { mount_link_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT LINK CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT LINK: PASS')
		C.fflush(nil)
	}
}
