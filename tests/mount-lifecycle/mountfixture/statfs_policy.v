// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

// Linux's 64-bit statfs ABI has fifteen words on both target architectures.
// RELATIME differs between mount(2) and statfs(2); STRICTATIME has no bit.
fn mount_statfs_expected(policy u64) u64 {
	return u64(0x20) | (policy & u64(1 | 2 | 4 | 8 | 1024 | 2048))
		| if policy & u64(C.MS_RELATIME) != 0 { u64(4096) } else { u64(0) }
}

fn mount_statfs_policy(path &char, policy u64) {
	mut flags := policy | u64(C.MS_REMOUNT | C.MS_BIND)
	if policy & u64(C.MS_RELATIME | C.MS_NOATIME) == 0 { flags |= u64(C.MS_STRICTATIME) }
	check(C.mount(c'none', path, unsafe { nil }, usize(flags), unsafe { nil }) == 0, 540)
}

fn mount_statfs_remount(path &char, readonly bool) {
	mount_statfs_policy(path, if readonly { u64(C.MS_RDONLY) } else { u64(0) })
}

fn mount_statfs_read(fd int, path &char, expected u64) [15]u64 {
	unsafe {
		mut value := [15]u64{init: u64(0xfeedface)}
		result := if fd >= 0 { C.syscall(int(C.SYS_fstatfs), i32(fd), &value[0]) }
			else { C.syscall(int(C.SYS_statfs), path, &value[0]) }
		if result != 0 || value[10] != expected {
			C.printf(c'MOUNT FSFLAGS RESULT: fd=%ld result=%ld errno=%d flags=%lx expected=%lx\n',
				i64(fd), i64(result), *C.__errno_location(), value[10], expected)
			C.fflush(nil)
		}
		check(result == 0 && value[10] == expected, 541)
		check(value[0] == u64(0x01021994) && value[1] > 0 && value[8] > 0 && value[9] > 0, 542)
		for index in 11 .. 15 { check(value[index] == 0, 542) }
		return value
	}
}

fn mount_statfs_same(value [15]u64, original [15]u64) {
	// Free blocks may change as the guest allocates memory. These fields
	// identify the same backend independently of its mount policy.
	unsafe {
		for index in 0 .. 10 {
			if index in [3, 4, 6] { continue }
			check(value[index] == original[index], 543)
		}
	}
}

fn mount_statfs_at(root int, file int, expected u64, original [15]u64) {
	unsafe {
		check(C.fchdir(root) == 0, 544)
		mount_statfs_same(mount_statfs_read(-1, c'.', expected), original)
		mount_statfs_same(mount_statfs_read(-1, c'marker', expected), original)
		mount_statfs_same(mount_statfs_read(root, nil, expected), original)
		mount_statfs_same(mount_statfs_read(file, nil, expected), original)
	}
}

fn mount_statfs_pair(wdir int, rdir int, writable &char, readonly &char, _ int, change bool) {
	unsafe {
		check(C.syscall(int(C.SYS_fchmodat), i32(wdir), writable, u32(0o755)) == 0, 545)
		saved := C.open(c'.', C.O_PATH | C.O_DIRECTORY)
		wroot := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rroot := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		check(saved >= 0 && wroot >= 0 && rroot >= 0, 545)
		wfile := C.openat(wroot, c'marker', C.O_RDONLY)
		rfile := C.openat(rroot, c'marker', C.O_PATH)
		rread := C.openat(rroot, c'.', C.O_RDONLY | C.O_DIRECTORY)
		check(wfile >= 0 && rfile >= 0 && rread >= 0, 545)
		original := mount_statfs_read(rroot, nil, mount_statfs_expected(u64(C.MS_RDONLY)))
		if wdir == -999 {
			mount_statfs_same(mount_statfs_read(-1, writable, mount_statfs_expected(0)), original)
			mount_statfs_same(mount_statfs_read(-1, readonly, mount_statfs_expected(1)), original)
		}
		mount_statfs_at(wroot, wfile, mount_statfs_expected(0), original)
		mount_statfs_at(rroot, rfile, mount_statfs_expected(1), original)
		mount_statfs_same(mount_statfs_read(rread, nil, mount_statfs_expected(1)), original)
		if change {
			for test in 0 .. 11 {
				policy := match test {
					1 { u64(C.MS_RDONLY) }
					2 { u64(C.MS_NOSUID) }
					3 { u64(C.MS_NODEV) }
					4 { u64(C.MS_NOEXEC) }
					5 { u64(C.MS_NOATIME) }
					6 { u64(C.MS_NODIRATIME) }
					7 { u64(C.MS_RELATIME) }
					8 { u64(C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV | C.MS_NOEXEC | C.MS_NOATIME | C.MS_NODIRATIME) }
					9 { u64(C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV | C.MS_NOEXEC | C.MS_RELATIME) }
					else { u64(0) }
				}
				check(C.fchdir(rroot) == 0, 546)
				mount_statfs_policy(c'.', policy)
				for iteration in 0 .. 8 {
					mount_statfs_at(rroot, rfile, mount_statfs_expected(policy), original)
					mount_statfs_same(mount_statfs_read(rread, nil, mount_statfs_expected(policy)), original)
					mount_statfs_at(wroot, wfile, mount_statfs_expected(0), original)
				}
			}
			check(C.fchdir(rroot) == 0, 546)
			mount_statfs_remount(c'.', true)
		}
		check(C.fchdir(wroot) == 0, 547)
		mut value := [15]u64{}
		check(C.syscall(int(C.SYS_statfs), c'missing', &value[0]) == -1 && *C.__errno_location() == C.ENOENT, 547)
		check(C.syscall(int(C.SYS_statfs), c'', &value[0]) == -1 && *C.__errno_location() == C.ENOENT, 547)
		check(C.syscall(int(C.SYS_fstatfs), i32(-999), &value[0]) == -1 && *C.__errno_location() == C.EBADF, 547)
		check(C.syscall(int(C.SYS_statfs), c'.', usize(1)) == -1 && *C.__errno_location() == C.EFAULT, 547)
		check(C.syscall(int(C.SYS_fstatfs), i32(wfile), usize(1)) == -1 && *C.__errno_location() == C.EFAULT, 547)
		child := C.fork()
		check(child >= 0, 548)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 548)
			mount_statfs_at(wroot, wfile, mount_statfs_expected(0), original)
			check(C.mount(c'none', c'.', nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY | C.MS_STRICTATIME), nil) == -1
				&& *C.__errno_location() == C.EPERM, 548)
			mount_statfs_at(wroot, wfile, mount_statfs_expected(0), original)
			mount_statfs_at(rroot, rfile, mount_statfs_expected(1), original)
			C._exit(0)
		}
		wait_child(child)
		check(C.fchdir(saved) == 0 && C.close(saved) == 0 && C.close(wroot) == 0
			&& C.close(rroot) == 0 && C.close(wfile) == 0 && C.close(rfile) == 0 && C.close(rread) == 0, 549)
	}
}

fn mount_statfs_retired_worker(argument voidptr) voidptr {
	truncate_retired_worker(argument)
	peer := unsafe { &TruncatePeer(argument) }
	mount_statfs_remount(unsafe { &peer.source_path[0] }, false)
	mount_statfs_remount(unsafe { &peer.alias_path[0] }, true)
	return unsafe { nil }
}

fn mount_statfs_extra(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 550)
		path := if kind == 8 { &char(c'/tmp/mount-lifecycle/sf-extra-8') }
			else { &char(c'/tmp/mount-lifecycle/sf-extra-9') }
		mut marker_path := [256]char{}
		check(C.snprintf(&marker_path[0], 256, c'%s/marker', path) > 0, 550)
		directory(path)
		check(C.mount(c'tmpfs', path, c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0, 550)
		marker(&marker_path[0])
		before := if kind == 9 { u64(C.MS_RDONLY | C.MS_NOSUID | C.MS_NOEXEC) } else { u64(0) }
		after := if kind == 8 { u64(C.MS_RDONLY | C.MS_NODEV | C.MS_RELATIME) } else { u64(0) }
		mount_statfs_policy(path, before)
		dirfd := C.open(path, C.O_PATH | C.O_DIRECTORY)
		filefd := C.open(&marker_path[0], C.O_RDONLY)
		check(dirfd >= 0 && filefd >= 0, 550)
		original := mount_statfs_read(dirfd, nil, mount_statfs_expected(before))
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 550)
		mount_statfs_policy(path, after)
		fresh := C.open(&marker_path[0], C.O_PATH)
		check(fresh >= 0, 550)
		for iteration in 0 .. 128 {
			mount_statfs_same(mount_statfs_read(-1, path, mount_statfs_expected(after)), original)
			mount_statfs_same(mount_statfs_read(fresh, nil, mount_statfs_expected(after)), original)
			mount_statfs_same(mount_statfs_read(dirfd, nil, mount_statfs_expected(before)), original)
			mount_statfs_same(mount_statfs_read(filefd, nil, mount_statfs_expected(before)), original)
		}
		check(C.close(fresh) == 0 && C.close(dirfd) == 0 && C.close(filefd) == 0, 550)
	}
}

fn mount_statfs_case(kind int) {
	if kind >= 8 { mount_statfs_extra(kind); return }
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 551)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/sf-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 551)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, mount_statfs_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 551)
			mount_statfs_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0, kind in [0, 1, 2, 3, 6])
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 551)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0 && C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 551)
		marker(&path[0])
		mut source_link := [256]char{}
		mut alias_link := [256]char{}
		if kind == 3 {
			check(C.snprintf(&source_link[0], 256, c'%s/source-link', &base[0]) > 0
				&& C.snprintf(&alias_link[0], 256, c'%s/alias-link', &base[0]) > 0
				&& C.symlink(&source[0], &source_link[0]) == 0 && C.symlink(&alias[0], &alias_link[0]) == 0, 551)
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 551)
		if kind == 6 { mount_statfs_remount(&source[0], true) } else { mount_statfs_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 551) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 551)
		if kind == 7 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 551)
			mount_statfs_pair(source_fd, alias_fd, c'.', c'.', 0, kind in [0, 1, 2, 3, 6])
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 551)
			mount_statfs_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0, kind in [0, 1, 2, 3, 6])
			mount_statfs_remount(c'.', false); mount_statfs_remount(c'/', true)
			mount_statfs_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1, kind in [0, 1, 2, 3, 6])
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_statfs_pair(-999, -999, &source_link[0], &alias_link[0], 0, kind in [0, 1, 2, 3, 6])
			mount_statfs_remount(&alias[0], false); mount_statfs_remount(&source[0], true)
			mount_statfs_pair(-999, -999, &alias_link[0], &source_link[0], 1, kind in [0, 1, 2, 3, 6])
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 551)
			mount_statfs_pair(source_fd, alias_fd, c'.', c'.', 0, kind in [0, 1, 2, 3, 6])
		} else if kind == 6 {
			mount_statfs_pair(alias_fd, source_fd, c'.', c'.', 0, kind in [0, 1, 2, 3, 6])
		} else {
			mount_statfs_pair(source_fd, alias_fd, c'.', c'.', 0, kind in [0, 1, 2, 3, 6])
			mount_statfs_remount(&alias[0], false); mount_statfs_remount(&source[0], true)
			mount_statfs_pair(alias_fd, source_fd, c'.', c'.', 1, kind in [0, 1, 2, 3, 6])
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 551)
	}
}

fn mount_statfs_cases(selected int) {
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 552)
			if child == 0 { mount_statfs_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT FSFLAGS CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT FSFLAGS: PASS')
		C.fflush(nil)
	}
}
