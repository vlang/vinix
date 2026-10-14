// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn truncate_call(path &char, length i64) int {
	return int(C.syscall(int(C.SYS_truncate), path, length))
}

fn truncate_result(path &char, length i64, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := truncate_call(path, length)
	failure := unsafe { *location }
	if result == -1 && failure == expected { return }
	unsafe { C.printf(c'MOUNT TRUNCATE RESULT: size=%ld result=%d errno=%d expected=%d\n', length, result, failure, expected) }
	C.fflush(unsafe { nil })
	check(false, 360)
}

fn truncate_pair(writable &char, readonly &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(writable, &before) == 0 && same(readonly, &before), 361)
		for iteration in 0 .. 200 {
			for length in [i64(0), 32, 8]! {
				truncate_result(readonly, length, C.EROFS)
				mut after := C.stat{}
				check(C.stat(writable, &after) == 0 && after.st_size == 8
					&& same(writable, &before) && same(readonly, &before) && contents(writable), 362)
				check(truncate_call(writable, length) == 0 && C.stat(writable, &after) == 0
					&& after.st_size == length, 363)
				fd := C.open(writable, C.O_WRONLY | C.O_TRUNC)
				check(fd >= 0 && C.write(fd, c'MOUNT-OK', 8) == 8 && C.close(fd) == 0
					&& contents(writable), 363)
			}
		}
		// Invalid input stays invalid even when the selected attachment is RO.
		truncate_result(readonly, -1, C.EINVAL)
		child := C.fork()
		check(child >= 0, 364)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 364)
			truncate_result(writable, 0, C.EACCES)
			truncate_result(readonly, 0, C.EROFS)
			C._exit(0)
		}
		wait_child(child)
		check(contents(writable), 364)
	}
}

struct TruncatePeer { source_path [256]char alias_path [256]char mut: source_fd int alias_fd int }

fn truncate_retired_worker(argument voidptr) voidptr {
	unsafe {
		mut peer := &TruncatePeer(argument)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 365)
		check(C.mount(c'tmpfs', &peer.source_path[0], c'tmpfs', 0, nil) == 0, 365)
		mut marker_path := [256]char{}
		check(C.snprintf(&marker_path[0], 256, c'%s/marker', &peer.source_path[0]) > 0, 365)
		marker(&marker_path[0])
		check(C.mount(&peer.source_path[0], &peer.alias_path[0], nil, usize(C.MS_BIND), nil) == 0, 365)
		bind_policy_remount(&peer.alias_path[0], true)
		peer.source_fd = C.open(&peer.source_path[0], C.O_PATH | C.O_DIRECTORY)
		peer.alias_fd = C.open(&peer.alias_path[0], C.O_PATH | C.O_DIRECTORY)
		check(peer.source_fd >= 0 && peer.alias_fd >= 0, 365)
		return nil
	}
}

fn truncate_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 366)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut source_marker := [256]char{}
		mut alias_marker := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/tr-%d', kind) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 366)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 365)
			check(C.snprintf(&source_marker[0], 256, c'/proc/self/fd/%d/marker', peer.source_fd) > 0
				&& C.snprintf(&alias_marker[0], 256, c'/proc/self/fd/%d/marker', peer.alias_fd) > 0, 365)
			truncate_pair(&source_marker[0], &alias_marker[0])
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 365)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&source_marker[0], 256, c'%s/marker', &source[0]) > 0, 366)
		marker(&source_marker[0])
		if kind == 3 {
			check(C.snprintf(&alias[0], 256, c'%s/file-alias', &base[0]) > 0, 366)
			marker(&alias[0])
			check(C.mount(&source_marker[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 366)
			bind_policy_remount(&alias[0], true)
			truncate_pair(&source_marker[0], &alias[0])
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			truncate_pair(&alias[0], &source_marker[0])
			return
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0
			&& C.snprintf(&alias_marker[0], 256, c'%s/marker', &alias[0]) > 0, 366)
		bind_policy_remount(&alias[0], true)
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 366) }
		truncate_result(&alias[0], 0, C.EISDIR)
		if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 366)
			truncate_pair(c'/marker', c'marker')
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			truncate_pair(c'marker', c'/marker')
		} else if kind == 4 {
			held := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
			check(held >= 0 && C.umount2(&alias[0], int(C.MNT_DETACH)) == 0
				&& C.snprintf(&alias_marker[0], 256, c'/proc/self/fd/%d/marker', held) > 0, 366)
			truncate_pair(&source_marker[0], &alias_marker[0])
			check(C.close(held) == 0, 366)
		} else {
			truncate_pair(&source_marker[0], &alias_marker[0])
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			truncate_pair(&alias_marker[0], &source_marker[0])
		}
	}
}

fn truncate_cases(selected int) {
	unsafe {
		for kind in 0 .. 6 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 367)
			if child == 0 { truncate_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT TRUNCATE CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT TRUNCATE: PASS')
		C.fflush(nil)
	}
}
