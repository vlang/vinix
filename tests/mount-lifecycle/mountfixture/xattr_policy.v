// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn mount_xattr_write(family int, path &char, fd int, name &char, value voidptr, size usize, flags int, removing bool) int {
	unsafe {
		if removing {
			return int(match family {
				0 { C.syscall(int(C.SYS_removexattr), path, name) }
				1 { C.syscall(int(C.SYS_lremovexattr), path, name) }
				else { C.syscall(int(C.SYS_fremovexattr), i32(fd), name) }
			})
		}
		return int(match family {
			0 { C.syscall(int(C.SYS_setxattr), path, name, value, size, i32(flags)) }
			1 { C.syscall(int(C.SYS_lsetxattr), path, name, value, size, i32(flags)) }
			else { C.syscall(int(C.SYS_fsetxattr), i32(fd), name, value, size, i32(flags)) }
		})
	}
}
fn mount_xattr_result(family int, path &char, fd int, name &char, value voidptr, size usize, flags int, removing bool, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := mount_xattr_write(family, path, fd, name, value, size, flags, removing)
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT XATTR RESULT: family=%d removing=%d flags=%d result=%d errno=%d expected=%d\n', family, int(removing), flags, result, failure, expected) }
	C.fflush(unsafe { nil })
	check(false, 420)
}
fn mount_xattr_value(family int, path &char, fd int, name &char, expected voidptr, size usize, present bool) {
	unsafe {
		mut bytes := [64]u8{}
		location := C.__errno_location()
		*location = 0
		count := match family {
			0 { C.syscall(int(C.SYS_getxattr), path, name, &bytes[0], usize(64)) }
			1 { C.syscall(int(C.SYS_lgetxattr), path, name, &bytes[0], usize(64)) }
			else { C.syscall(int(C.SYS_fgetxattr), i32(fd), name, &bytes[0], usize(64)) }
		}
		if present { check(count == isize(size) && (size == 0 || C.memcmp(&bytes[0], expected, size) == 0), 421) }
		else { check(count == -1 && *location == C.ENODATA, 421) }
	}
}
fn mount_xattr_names(family int, path &char, fd int, name &char, present bool) {
	unsafe {
		mut bytes := [512]char{}
		count := match family {
			0 { C.syscall(int(C.SYS_listxattr), path, &bytes[0], usize(512)) }
			1 { C.syscall(int(C.SYS_llistxattr), path, &bytes[0], usize(512)) }
			else { C.syscall(int(C.SYS_flistxattr), i32(fd), &bytes[0], usize(512)) }
		}
		check(count >= 0 && count <= 512, 422)
		mut start := 0
		mut found := false
		for i in 0 .. int(count) {
			if bytes[i] != 0 { continue }
			if i - start == int(C.strlen(name)) && C.memcmp(&bytes[start], name, usize(i - start)) == 0 { found = true }
			start = i + 1
		}
		check(start == int(count) && found == present, 422)
	}
}
fn mount_xattr_observe(writable &char, readonly &char, wfd int, rfd int, name &char, value voidptr, size usize, present bool) {
	for family in 0 .. 3 {
		mount_xattr_value(family, writable, wfd, name, value, size, present)
		mount_xattr_value(family, readonly, rfd, name, value, size, present)
		mount_xattr_names(family, writable, wfd, name, present)
		mount_xattr_names(family, readonly, rfd, name, present)
	}
}

fn mount_xattr_checks(writable &char, readonly &char, wfd int, rfd int) {
	unsafe {
		first := [u8(0), 255, 17, 0, 81]!
		next := [u8(55), 0, 254, 91, 1]!
		mut identity := C.stat{}
		check(C.fstat(wfd, &identity) == 0, 423)
		for iteration in 0 .. 200 {
			for family in 0 .. 3 {
				for trusted in [false, true]! {
					name := if trusted { &char(c'trusted.mount-policy') } else { &char(c'user.mount-policy') }
					mount_xattr_result(family, writable, wfd, name, &first[0], 5, 1, false, 0)
					mount_xattr_observe(writable, readonly, wfd, rfd, name, &first[0], 5, true)
					mut before := C.stat{}
					check(C.fstat(wfd, &before) == 0, 423)
					mount_xattr_result(family, readonly, rfd, name, &next[0], 5, 2, false, C.EROFS)
					mount_xattr_result(family, readonly, rfd, name, nil, 0, 0, true, C.EROFS)
					timestamp_unchanged(wfd, &before); timestamp_unchanged(rfd, &before)
					mount_xattr_observe(writable, readonly, wfd, rfd, name, &first[0], 5, true)
					mount_xattr_result(family, writable, wfd, name, &next[0], 5, 2, false, 0)
					mount_xattr_observe(writable, readonly, wfd, rfd, name, &next[0], 5, true)
					mount_xattr_result(family, writable, wfd, name, nil, 0, 2, false, 0)
					mount_xattr_observe(writable, readonly, wfd, rfd, name, nil, 0, true)
					mount_xattr_result(family, writable, wfd, name, nil, 0, 0, true, 0)
					mount_xattr_observe(writable, readonly, wfd, rfd, name, nil, 0, false)
					check(C.fstat(wfd, &before) == 0, 423)
					mount_xattr_result(family, readonly, rfd, name, &next[0], 5, 1, false, C.EROFS)
					mount_xattr_result(family, readonly, rfd, name, nil, 0, 0, true, C.EROFS)
					timestamp_unchanged(wfd, &before); timestamp_unchanged(rfd, &before)
				}
			}
		}
		for trusted in [false, true]! {
			name := if trusted { &char(c'trusted.mount-policy') } else { &char(c'user.mount-policy') }
			mount_xattr_result(2, writable, wfd, name, &first[0], 5, 1, false, 0)
		}
		mut before := C.stat{}
		check(C.fstat(wfd, &before) == 0, 424)
		child := C.fork()
		check(child >= 0, 424)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 424)
			for family in 0 .. 3 {
				for trusted in [false, true]! {
					name := if trusted { &char(c'trusted.mount-policy') } else { &char(c'user.mount-policy') }
					expected := if trusted { C.EPERM } else { C.EACCES }
					mount_xattr_result(family, writable, wfd, name, &next[0], 5, 2, false, expected)
					mount_xattr_result(family, writable, wfd, name, nil, 0, 0, true, expected)
					mount_xattr_result(family, readonly, rfd, name, &next[0], 5, 2, false, C.EROFS)
					mount_xattr_result(family, readonly, rfd, name, nil, 0, 0, true, C.EROFS)
					if trusted {
						mount_xattr_value(family, writable, wfd, name, nil, 0, false)
						mount_xattr_value(family, readonly, rfd, name, nil, 0, false)
						mount_xattr_names(family, writable, wfd, name, false)
						mount_xattr_names(family, readonly, rfd, name, false)
					}
				}
			}
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(wfd, &before); timestamp_unchanged(rfd, &before)
		for trusted in [false, true]! {
			name := if trusted { &char(c'trusted.mount-policy') } else { &char(c'user.mount-policy') }
			mount_xattr_observe(writable, readonly, wfd, rfd, name, &first[0], 5, true)
			mount_xattr_result(2, writable, wfd, name, nil, 0, 0, true, 0)
		}
		mut after := C.stat{}
		check(C.fstat(wfd, &after) == 0, 424)
		timestamp_identity(&after, &identity)
		mut bytes := [8]u8{}
		check(C.read(wfd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 425)
	}
}

fn mount_xattr_links(writable &char, readonly &char, target_fd int) {
	unsafe {
		name := &char(c'trusted.mount-policy')
		for iteration in 0 .. 200 {
			mut target := C.stat{}
			check(C.fstat(target_fd, &target) == 0, 426)
			mount_xattr_result(1, writable, -1, name, c'link', 4, 1, false, 0)
			mount_xattr_value(1, writable, -1, name, c'link', 4, true)
			mount_xattr_value(1, readonly, -1, name, c'link', 4, true)
			mount_xattr_names(1, readonly, -1, name, true)
			mount_xattr_value(2, c'', target_fd, name, nil, 0, false)
			timestamp_unchanged(target_fd, &target)
			mount_xattr_result(1, readonly, -1, name, c'bad', 3, 2, false, C.EROFS)
			mount_xattr_result(1, readonly, -1, name, nil, 0, 0, true, C.EROFS)
			mount_xattr_value(1, readonly, -1, name, c'link', 4, true)
			mount_xattr_result(0, writable, -1, c'user.mount-policy', c'target', 6, 1, false, 0)
			mount_xattr_result(0, readonly, -1, c'user.mount-policy', c'bad', 3, 2, false, C.EROFS)
			mount_xattr_result(0, readonly, -1, c'user.mount-policy', nil, 0, 0, true, C.EROFS)
			mount_xattr_value(0, readonly, -1, c'user.mount-policy', c'target', 6, true)
			mount_xattr_value(2, c'', target_fd, c'user.mount-policy', c'target', 6, true)
			mount_xattr_value(1, writable, -1, c'user.mount-policy', nil, 0, false)
			mount_xattr_result(0, writable, -1, c'user.mount-policy', nil, 0, 0, true, 0)
			mount_xattr_result(1, writable, -1, name, nil, 0, 0, true, 0)
			mount_xattr_value(1, readonly, -1, name, nil, 0, false)
		}
	}
}
fn mount_xattr_pair(wdir int, rdir int, writable &char, readonly &char, wlink &char, rlink &char, has_link bool) {
	unsafe {
		wfd := C.openat(wdir, writable, C.O_RDONLY)
		rfd := C.openat(rdir, readonly, C.O_RDONLY)
		check(wfd >= 0 && rfd >= 0, 427)
		mut wpath := [512]char{}
		mut rpath := [512]char{}
		timestamp_legacy_path(wdir, writable, &wpath[0]); timestamp_legacy_path(rdir, readonly, &rpath[0])
		mount_xattr_checks(&wpath[0], &rpath[0], wfd, rfd)
		if has_link {
			timestamp_legacy_path(wdir, wlink, &wpath[0]); timestamp_legacy_path(rdir, rlink, &rpath[0])
			mount_xattr_links(&wpath[0], &rpath[0], wfd)
		}
		check(C.close(wfd) == 0 && C.close(rfd) == 0, 427)
	}
}

fn mount_xattr_inherited(source_fd int, alias_fd int) {
	unsafe {
		original := C.openat(source_fd, c'marker', C.O_RDONLY)
		bound := C.openat(alias_fd, c'marker', C.O_RDONLY)
		check(original >= 0 && bound >= 0 && C.unshare(int(C.CLONE_NEWNS)) == 0, 428)
		mut wpath := [512]char{}
		mut rpath := [512]char{}
		timestamp_legacy_path(source_fd, c'marker', &wpath[0]); timestamp_legacy_path(alias_fd, c'marker', &rpath[0])
		mount_xattr_checks(&wpath[0], &rpath[0], original, bound)
		check(C.close(original) == 0 && C.close(bound) == 0, 428)
	}
}

fn mount_xattr_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 429)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/xp-%d', kind) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 429)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 429)
			mount_xattr_pair(peer.source_fd, peer.alias_fd, c'marker', c'marker', c'', c'', false)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 429)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 429)
		marker(&path[0])
		if kind == 3 {
			check(C.snprintf(&alias[0], 256, c'%s/file-alias', &base[0]) > 0, 429)
			marker(&alias[0])
			check(C.mount(&path[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 429)
			bind_policy_remount(&alias[0], true)
			mount_xattr_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &path[0], &alias[0], c'', c'', false)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_xattr_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &alias[0], &path[0], c'', c'', false)
			return
		}
		check(C.snprintf(&path[0], 256, c'%s/link', &source[0]) > 0 && C.symlink(c'marker', &path[0]) == 0
			&& C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 429)
		if kind == 6 { bind_policy_remount(&source[0], true) }
		else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 429) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 429)
		if kind == 7 {
			mount_xattr_inherited(source_fd, alias_fd)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 429)
			mount_xattr_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/marker', c'marker', c'/link', c'link', true)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_xattr_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'marker', c'/marker', c'link', c'/link', true)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 429)
			mount_xattr_pair(source_fd, alias_fd, c'marker', c'marker', c'link', c'link', true)
		} else if kind == 6 {
			mount_xattr_pair(alias_fd, source_fd, c'marker', c'marker', c'link', c'link', true)
		} else {
			mount_xattr_pair(source_fd, alias_fd, c'marker', c'marker', c'link', c'link', true)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_xattr_pair(alias_fd, source_fd, c'marker', c'marker', c'link', c'link', true)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 429)
	}
}

fn mount_xattr_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 430)
			if child == 0 { mount_xattr_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT XATTR CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT XATTR: PASS')
		C.fflush(nil)
	}
}
