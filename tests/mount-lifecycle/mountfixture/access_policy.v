// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn C.setreuid(u32, u32) int

fn mount_access_result(dirfd int, path &char, mode int, flags int, legacy bool, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := if legacy { C.syscall(int(C.SYS_faccessat), i32(dirfd), path, i32(mode)) }
		else { C.syscall(int(C.SYS_faccessat2), i32(dirfd), path, i32(mode), i32(flags)) }
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT ACCESS RESULT: mode=%d flags=%x legacy=%d result=%ld errno=%d expected=%d\n', i32(mode), i32(flags), i32(if legacy { 1 } else { 0 }), i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 520)
}

fn mount_access_expected(mode int, readonly bool, noexec bool) int {
	return if noexec && mode & C.X_OK != 0 { int(C.EACCES) }
		else if readonly && mode & C.W_OK != 0 { int(C.EROFS) } else { 0 }
}

fn mount_access_matrix(wdir int, rdir int, writable &char, readonly &char, ro bool, nx bool) {
	unsafe {
		wfd := C.openat(wdir, writable, C.O_PATH)
		rfd := C.openat(rdir, readonly, C.O_PATH)
		mut before := C.stat{}
		check(wfd >= 0 && rfd >= 0 && C.fstat(wfd, &before) == 0, 521)
		for _ in 0 .. 16 {
			for mode in 0 .. 8 {
				expected := mount_access_expected(mode, ro, nx)
				mount_access_result(wdir, writable, mode, 0, true, 0)
				mount_access_result(rdir, readonly, mode, 0, true, expected)
				for flags in [int(0), int(C.AT_EACCESS), int(C.AT_SYMLINK_NOFOLLOW), int(C.AT_EACCESS | C.AT_SYMLINK_NOFOLLOW)]! {
					mount_access_result(wdir, writable, mode, flags, false, 0)
					mount_access_result(rdir, readonly, mode, flags, false, expected)
				}
				for flags in [int(C.AT_EMPTY_PATH), int(C.AT_EMPTY_PATH | C.AT_EACCESS), int(C.AT_EMPTY_PATH | C.AT_SYMLINK_NOFOLLOW)]! {
					mount_access_result(wfd, c'', mode, flags, false, 0)
					mount_access_result(rfd, c'', mode, flags, false, expected)
				}
			}
		}
		timestamp_unchanged(wfd, &before); timestamp_unchanged(rfd, &before)
		check(C.close(wfd) == 0 && C.close(rfd) == 0, 521)
	}
}

fn mount_access_pair(wdir int, rdir int, writable &char, readonly &char, round int) {
	unsafe {
		wparent := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rparent := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		check(wparent >= 0 && rparent >= 0
			&& C.syscall(int(C.SYS_fchmodat), i32(wparent), c'.', u32(0o755)) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(wparent), c'marker', u32(0o777)) == 0, 522)
		mut name := [128]char{}
		for form, kind in [u32(C.S_IFIFO), u32(C.S_IFCHR), u32(C.S_IFBLK), u32(C.S_IFREG)]! {
			check(C.snprintf(&name[0], 128, c'access-%d-%d', i32(round), i32(form)) > 0, 522)
			mount_node_result(wparent, &name[0], kind | u32(0o600), 0)
			check(C.syscall(int(C.SYS_fchmodat), i32(wparent), &name[0], u32(if form == 3 { 0o600 } else { 0o666 })) == 0, 522)
		}
		check(C.snprintf(&name[0], 128, c'access-link-%d', i32(round)) > 0
			&& C.syscall(int(C.SYS_symlinkat), c'marker', i32(wparent), &name[0]) == 0, 522)
		mut parent_before := C.stat{}
		check(C.fstat(wparent, &parent_before) == 0, 522)
		mount_access_matrix(wparent, rparent, c'marker', c'marker', true, false)
		for mode in 0 .. 8 {
			mount_access_result(wparent, c'.', mode, 0, false, 0)
			mount_access_result(rparent, c'.', mode, 0, false, mount_access_expected(mode, true, false))
			for form in 0 .. 3 {
				check(C.snprintf(&name[0], 128, c'access-%d-%d', i32(round), i32(form)) > 0, 523)
				expected := if mode & C.X_OK != 0 { int(C.EACCES) } else { 0 }
				mount_access_result(wparent, &name[0], mode, 0, false, expected)
				mount_access_result(rparent, &name[0], mode, 0, false, expected)
			}
			check(C.snprintf(&name[0], 128, c'access-link-%d', i32(round)) > 0, 523)
			mount_access_result(rparent, &name[0], mode, int(C.AT_SYMLINK_NOFOLLOW), false, mount_access_expected(mode, true, false))
		}
		cwd := C.open(c'.', C.O_PATH | C.O_DIRECTORY)
		check(cwd >= 0 && C.fchdir(wparent) == 0, 523)
		mount_access_result(int(C.AT_FDCWD), c'', int(C.W_OK), int(C.AT_EMPTY_PATH), false, 0)
		check(C.fchdir(rparent) == 0, 523)
		mount_access_result(int(C.AT_FDCWD), c'', int(C.W_OK), int(C.AT_EMPTY_PATH), false, C.EROFS)
		check(C.fchdir(cwd) == 0 && C.close(cwd) == 0, 523)
		child := C.fork()
		check(child >= 0, 524)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 524)
			mount_access_matrix(wparent, rparent, c'marker', c'marker', true, false)
			check(C.snprintf(&name[0], 128, c'access-%d-3', i32(round)) > 0, 524)
			mount_access_result(wparent, &name[0], int(C.W_OK), 0, false, C.EACCES)
			mount_access_result(rparent, &name[0], int(C.W_OK), 0, false, C.EACCES)
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(wparent, &parent_before); timestamp_unchanged(rparent, &parent_before)
		check(C.close(wparent) == 0 && C.close(rparent) == 0, 524)
	}
}

fn mount_access_remount(path &char, ro bool, nx bool) {
	flags := usize(C.MS_REMOUNT | C.MS_BIND) | if ro { usize(C.MS_RDONLY) } else { usize(0) }
		| if nx { usize(C.MS_NOEXEC) } else { usize(0) }
	check(C.mount(c'none', path, unsafe { nil }, flags, unsafe { nil }) == 0, 525)
}

fn mount_access_extra(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 526)
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [512]char{}
		check(C.snprintf(&source[0], 256, c'/tmp/mount-lifecycle/ac-%d-source', i32(kind)) > 0
			&& C.snprintf(&alias[0], 256, c'/tmp/mount-lifecycle/ac-%d-alias', i32(kind)) > 0, 526)
		directory(&source[0]); directory(&alias[0])
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&path[0], 512, c'%s/marker', &source[0]) > 0, 526)
		marker(&path[0])
		check(C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &path[0], u32(0o777)) == 0
			&& C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 526)
		wdir := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		rdir := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(wdir >= 0 && rdir >= 0, 526)
		if kind == 8 {
			check(C.syscall(int(C.SYS_symlinkat), c'marker', i32(wdir), c'exec-link') == 0, 526)
			mount_access_remount(&alias[0], false, true)
			mount_access_matrix(wdir, rdir, c'marker', c'marker', false, true)
			mount_access_result(rdir, c'.', int(C.X_OK), 0, false, 0)
			mount_access_result(rdir, c'exec-link', int(C.X_OK), 0, false, C.EACCES)
			mount_access_result(rdir, c'exec-link', int(C.X_OK), int(C.AT_SYMLINK_NOFOLLOW), false, 0)
			mount_access_remount(&alias[0], true, true)
			mount_access_matrix(wdir, rdir, c'marker', c'marker', true, true)
			mount_access_remount(&alias[0], false, false); mount_access_remount(&source[0], false, true)
			mount_access_matrix(rdir, wdir, c'marker', c'marker', false, true)
		} else {
			check(C.syscall(int(C.SYS_fchmodat), i32(wdir), c'.', u32(0o700)) == 0, 527)
			mount_access_remount(&alias[0], true, false)
			wfd := C.openat(wdir, c'marker', C.O_PATH)
			rfd := C.openat(rdir, c'marker', C.O_PATH)
			check(wfd >= 0 && rfd >= 0, 527)
			child := C.fork()
			check(child >= 0, 527)
			if child == 0 {
				check(C.setgroups(0, nil) == 0 && C.setreuid(1000, 0) == 0, 527)
				for mode in 0 .. 8 {
					mount_access_result(wdir, c'marker', mode, 0, false, C.EACCES)
					mount_access_result(rdir, c'marker', mode, 0, false, C.EACCES)
					mount_access_result(wdir, c'marker', mode, int(C.AT_EACCESS), false, 0)
					mount_access_result(rdir, c'marker', mode, int(C.AT_EACCESS), false, mount_access_expected(mode, true, false))
					mount_access_result(wfd, c'', mode, int(C.AT_EMPTY_PATH), false, 0)
					mount_access_result(rfd, c'', mode, int(C.AT_EMPTY_PATH), false, mount_access_expected(mode, true, false))
				}
				C._exit(0)
			}
			wait_child(child)
			check(C.close(wfd) == 0 && C.close(rfd) == 0, 527)
		}
		check(C.close(wdir) == 0 && C.close(rdir) == 0, 527)
	}
}

fn mount_access_case(kind int) {
	if kind >= 8 { mount_access_extra(kind); return }
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 528)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/ac-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 528)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 528)
			mount_access_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 528)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 528)
		marker(&path[0])
		mut source_link := [256]char{}
		mut alias_link := [256]char{}
		if kind == 3 {
			check(C.snprintf(&source_link[0], 256, c'%s/source-link', &base[0]) > 0
				&& C.snprintf(&alias_link[0], 256, c'%s/alias-link', &base[0]) > 0
				&& C.symlink(&source[0], &source_link[0]) == 0 && C.symlink(&alias[0], &alias_link[0]) == 0, 528)
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 528)
		if kind == 6 { bind_policy_remount(&source[0], true) } else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 528) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 528)
		if kind == 7 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 528)
			mount_access_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 528)
			mount_access_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_access_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1)
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_access_pair(-999, -999, &source_link[0], &alias_link[0], 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_access_pair(-999, -999, &alias_link[0], &source_link[0], 1)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 528)
			mount_access_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 6 {
			mount_access_pair(alias_fd, source_fd, c'.', c'.', 0)
		} else {
			mount_access_pair(source_fd, alias_fd, c'.', c'.', 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_access_pair(alias_fd, source_fd, c'.', c'.', 1)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 528)
	}
}

fn mount_access_cases(selected int) {
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 529)
			if child == 0 { mount_access_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT ACCESS CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT ACCESS: PASS')
		C.fflush(nil)
	}
}
