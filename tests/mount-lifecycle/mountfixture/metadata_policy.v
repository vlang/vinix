// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

// File descriptors are opened read-only: metadata writes still require a
// writable mount, independently of the descriptor's data access mode.
fn metadata_operation(operation int, dirfd int, path &char, fd int) int {
	unsafe {
		return int(match operation {
			0 { C.syscall(int(C.SYS_fchmodat), i32(dirfd), path, u32(0o640)) }
			1 { C.syscall(int(C.SYS_fchownat), i32(dirfd), path, u32(1), u32(2), i32(0)) }
			2 { C.syscall(int(C.SYS_fchmod), i32(fd), u32(0o640)) }
			3 { C.syscall(int(C.SYS_fchown), i32(fd), u32(1), u32(2)) }
			4 { C.syscall(int(C.SYS_fchownat), i32(fd), c'', u32(1), u32(2), i32(C.AT_EMPTY_PATH)) }
			else { C.syscall(int(C.SYS_fchownat), i32(dirfd), path, u32(1), u32(2), i32(C.AT_SYMLINK_NOFOLLOW)) }
		})
	}
}

fn metadata_result(operation int, dirfd int, path &char, fd int, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := metadata_operation(operation, dirfd, path, fd)
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT METADATA RESULT: operation=%d result=%d errno=%d expected=%d\n', operation, result, failure, expected) }
	C.fflush(unsafe { nil })
	check(false, 380)
}

fn metadata_stat(fd int, mode u32, uid u32, gid u32, identity &C.stat) {
	mut now := C.stat{}
	check(C.fstat(fd, &now) == 0 && now.st_dev == identity.st_dev && now.st_ino == identity.st_ino
		&& now.st_size == identity.st_size && now.st_mode & 0o7777 == mode
		&& now.st_mode & 0o170000 == identity.st_mode & 0o170000
		&& now.st_uid == uid && now.st_gid == gid, 381)
}

fn metadata_pair(wdir int, rdir int, writable &char, readonly &char, wlink &char, rlink &char, has_link bool) {
	unsafe {
		wfd := C.openat(wdir, writable, C.O_RDONLY)
		rfd := C.openat(rdir, readonly, C.O_RDONLY)
		link_fd := if has_link { C.openat(wdir, wlink, C.O_PATH | C.O_NOFOLLOW) } else { -1 }
		mut before := C.stat{}
		mut link_before := C.stat{}
		check(wfd >= 0 && rfd >= 0 && C.fstat(wfd, &before) == 0
			&& before.st_mode & 0o7777 == 0o600 && before.st_uid == 0 && before.st_gid == 0, 382)
		if has_link { check(link_fd >= 0 && C.fstat(link_fd, &link_before) == 0, 382) }
		for iteration in 0 .. 200 {
			for operation in 0 .. if has_link { 6 } else { 5 } {
				metadata_result(operation, rdir, if operation == 5 { rlink } else { readonly }, rfd, C.EROFS)
				metadata_stat(wfd, 0o600, 0, 0, &before)
				metadata_stat(rfd, 0o600, 0, 0, &before)
				if has_link { metadata_stat(link_fd, 0o777, 0, 0, &link_before) }
				metadata_result(operation, wdir, if operation == 5 { wlink } else { writable }, wfd, 0)
				if operation == 5 {
					metadata_stat(wfd, 0o600, 0, 0, &before)
					metadata_stat(link_fd, 0o777, 1, 2, &link_before)
					check(C.syscall(int(C.SYS_fchownat), i32(wdir), wlink, u32(0), u32(0), i32(C.AT_SYMLINK_NOFOLLOW)) == 0, 383)
				} else {
					changing_mode := operation in [0, 2]
					metadata_stat(wfd, if changing_mode { u32(0o640) } else { u32(0o600) },
						if changing_mode { u32(0) } else { u32(1) }, if changing_mode { u32(0) } else { u32(2) }, &before)
					check(C.syscall(int(C.SYS_fchown), i32(wfd), u32(0), u32(0)) == 0
						&& C.syscall(int(C.SYS_fchmod), i32(wfd), u32(0o600)) == 0, 383)
				}
			}
		}
		child := C.fork()
		check(child >= 0, 384)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 384)
			for operation in 0 .. if has_link { 6 } else { 5 } {
				metadata_result(operation, wdir, if operation == 5 { wlink } else { writable }, wfd, C.EPERM)
				metadata_result(operation, rdir, if operation == 5 { rlink } else { readonly }, rfd, C.EROFS)
			}
			C._exit(0)
		}
		wait_child(child)
		metadata_stat(wfd, 0o600, 0, 0, &before)
		metadata_stat(rfd, 0o600, 0, 0, &before)
		mut bytes := [8]u8{}
		check(C.read(wfd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.close(wfd) == 0 && C.close(rfd) == 0, 385)
		if has_link { check(C.close(link_fd) == 0, 385) }
	}
}

fn metadata_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 386)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/mp-%d', kind) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 386)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 386)
			metadata_pair(peer.source_fd, peer.alias_fd, c'marker', c'marker', c'', c'', false)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 386)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 386)
		marker(&path[0])
		if kind == 3 {
			check(C.snprintf(&alias[0], 256, c'%s/file-alias', &base[0]) > 0, 386)
			marker(&alias[0])
			check(C.mount(&path[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 386)
			bind_policy_remount(&alias[0], true)
			metadata_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &path[0], &alias[0], c'', c'', false)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			metadata_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &alias[0], &path[0], c'', c'', false)
			return
		}
		check(C.snprintf(&path[0], 256, c'%s/link', &source[0]) > 0 && C.symlink(c'marker', &path[0]) == 0
			&& C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 386)
		if kind == 6 { bind_policy_remount(&source[0], true) }
		else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 386) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 386)
		if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 386)
			metadata_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/marker', c'marker', c'/link', c'link', true)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			metadata_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'marker', c'/marker', c'link', c'/link', true)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 386)
			metadata_pair(source_fd, alias_fd, c'marker', c'marker', c'link', c'link', true)
		} else if kind == 6 {
			metadata_pair(alias_fd, source_fd, c'marker', c'marker', c'link', c'link', true)
		} else {
			metadata_pair(source_fd, alias_fd, c'marker', c'marker', c'link', c'link', true)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			metadata_pair(alias_fd, source_fd, c'marker', c'marker', c'link', c'link', true)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 386)
	}
}

fn metadata_cases(selected int) {
	unsafe {
		for kind in 0 .. 7 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 387)
			if child == 0 { metadata_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT METADATA CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT METADATA: PASS')
		C.fflush(nil)
	}
}
