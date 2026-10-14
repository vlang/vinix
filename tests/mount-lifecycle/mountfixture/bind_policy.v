// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn bind_policy_mkdir(dirfd int, path &char) int {
	return int(C.syscall(int(C.SYS_mkdirat), i32(dirfd), path, u32(0o755)))
}

fn bind_policy_open(dirfd int, path &char, writable bool) {
	unsafe {
		for flags in [int(C.O_WRONLY), int(C.O_RDWR), int(C.O_RDONLY | C.O_TRUNC)]! {
			fd := C.openat(dirfd, path, flags)
			if writable {
				check(fd >= 0 && C.close(fd) == 0, 341)
				// Restore data after truncation before another route reads it.
				if flags & C.O_TRUNC != 0 {
					restore := C.openat(dirfd, path, C.O_WRONLY)
					check(restore >= 0 && C.write(restore, c'MOUNT-OK', 8) == 8 && C.close(restore) == 0, 341)
				}
			} else { check(fd == -1 && *C.__errno_location() == C.EROFS, 342) }
		}
		fd := C.openat(dirfd, path, C.O_RDONLY)
		mut bytes := [8]u8{}
		check(fd >= 0 && C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.close(fd) == 0, 343)
	}
}

fn bind_policy_directories(writable int, readonly int, second bool) {
	unsafe {
		created := C.openat(writable, if second { &char(c'allowed-second') } else { &char(c'allowed-first') },
			C.O_CREAT | C.O_EXCL | C.O_WRONLY, u32(0o600))
		check(created >= 0 && C.write(created, c'MOUNT-OK', 8) == 8 && C.close(created) == 0, 344)
		check(bind_policy_mkdir(writable, if second { &char(c'dir-second') } else { &char(c'dir-first') }) == 0, 344)
		for iteration in 0 .. 200 {
			bind_policy_open(writable, c'marker', true)
			bind_policy_open(readonly, c'marker', false)
			check(C.openat(readonly, c'forbidden', C.O_CREAT | C.O_WRONLY, u32(0o600)) == -1
				&& *C.__errno_location() == C.EROFS, 345)
			check(bind_policy_mkdir(readonly, c'forbidden-dir') == -1 && *C.__errno_location() == C.EROFS, 345)
			check(C.openat(writable, c'forbidden', C.O_RDONLY) == -1 && *C.__errno_location() == C.ENOENT
				&& C.openat(writable, c'forbidden-dir', C.O_RDONLY) == -1 && *C.__errno_location() == C.ENOENT, 345)
		}
	}
}

fn bind_policy_remount(path &char, readonly bool) {
	unsafe {
		check(C.mount(c'none', path, nil, usize(C.MS_REMOUNT | C.MS_BIND)
			| if readonly { usize(C.MS_RDONLY) } else { usize(0) }, nil) == 0, 346)
	}
}

struct BindPolicyPeer { source_path [256]char alias_path [256]char }

fn bind_policy_worker(argument voidptr) voidptr {
	unsafe {
		peer := &BindPolicyPeer(argument)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 347)
		source_fd := C.open(&peer.source_path[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&peer.alias_path[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 347)
		bind_policy_remount(&peer.alias_path[0], false)
		bind_policy_remount(&peer.source_path[0], true)
		bind_policy_directories(alias_fd, source_fd, true)
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 347)
		return nil
	}
}

fn bind_policy_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 348)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut marker_path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/bp-%d', kind) > 0, 348)
		directory(&base[0])
		check(C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 348)
		directory(&source[0]); directory(&alias[0])
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&marker_path[0], 256, c'%s/marker', &source[0]) > 0, 348)
		marker(&marker_path[0])
		if kind == 3 {
			check(C.snprintf(&alias[0], 256, c'%s/file-alias', &base[0]) > 0, 348)
			marker(&alias[0])
			check(C.mount(&marker_path[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 348)
			bind_policy_remount(&alias[0], true)
			for iteration in 0 .. 200 {
				bind_policy_open(int(C.AT_FDCWD), &marker_path[0], true)
				bind_policy_open(int(C.AT_FDCWD), &alias[0], false)
			}
			bind_policy_remount(&alias[0], false)
			bind_policy_remount(&source[0], true)
			for iteration in 0 .. 200 {
				bind_policy_open(int(C.AT_FDCWD), &alias[0], true)
				bind_policy_open(int(C.AT_FDCWD), &marker_path[0], false)
			}
			return
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 348)
		bind_policy_remount(&alias[0], true)
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 348) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 348)
		if kind == 4 {
			peer := &BindPolicyPeer(C.alloca(sizeof(BindPolicyPeer)))
			*peer = BindPolicyPeer{source_path: source, alias_path: alias}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, bind_policy_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 347)
			// The worker's private namespace changed; the shared one retains policy.
			bind_policy_directories(source_fd, alias_fd, false)
		} else {
			if kind == 2 {
				check(C.chroot(&source[0]) == 0 && C.fchdir(alias_fd) == 0, 348)
				for iteration in 0 .. 200 {
					bind_policy_open(int(C.AT_FDCWD), c'/marker', true)
					bind_policy_open(int(C.AT_FDCWD), c'marker', false)
				}
			}
			bind_policy_directories(source_fd, alias_fd, false)
			if kind == 2 {
				bind_policy_remount(c'.', false)
				bind_policy_remount(c'/', true)
			} else {
				mut source_route := [256]char{}
				mut alias_route := [256]char{}
				check(C.snprintf(&source_route[0], 256, c'/proc/self/fd/%d', source_fd) > 0
					&& C.snprintf(&alias_route[0], 256, c'/proc/self/fd/%d', alias_fd) > 0, 348)
				bind_policy_remount(&alias_route[0], false)
				bind_policy_remount(&source_route[0], true)
			}
			bind_policy_directories(alias_fd, source_fd, true)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 348)
	}
}

fn bind_policy_cases(selected int) {
	unsafe {
		for kind in 0 .. 5 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 349)
			if child == 0 { bind_policy_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT BIND POLICY CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT BIND POLICY: PASS')
		C.fflush(nil)
	}
}
