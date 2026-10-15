// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn unmount_publication_sleeping(child int) {
	unsafe {
		mut path := [128]char{}
		check(C.snprintf(&path[0], 128, c'/proc/%d/stat', i32(child)) > 0, 3401)
		for _ in 0 .. 10000 {
			fd := C.open(&path[0], C.O_RDONLY)
			mut text := [1024]u8{}
			check(fd >= 0, 3401)
			count := C.read(fd, &text[0], 1023)
			check(count > 0 && C.close(fd) == 0, 3401)
			// The single-threaded child signalled readiness before open. Its
			// only subsequent wait is the FIFO rendezvous, before publication.
			for i := int(count) - 4; i >= 0; i-- {
				if text[i] == `)` && text[i + 1] == ` ` && text[i + 2] == `S`
					&& text[i + 3] == ` ` { return }
			}
			C.sched_yield()
		}
		check(false, 3401)
	}
}

fn unmount_publication_copied_directory(kind int) {
	unsafe {
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		outside := C.open(c'/', C.O_PATH | C.O_DIRECTORY)
		check(outside >= 0 && C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 3410)
		child := C.fork()
		check(child >= 0, 3410)
		if child == 0 {
			check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3410)
			if kind == 8 { check(C.chdir(c'/tmp/mount-lifecycle/uo/a') == 0, 3410) }
			else { check(C.chroot(c'/tmp/mount-lifecycle/uo/a') == 0 && C.chdir(c'/') == 0, 3410) }
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3410)
			alias_signal(int(ready[1]))
			alias_wait(int(stop[0]))
			fd := C.open(if kind == 8 { c'marker' } else { c'/marker' }, C.O_RDONLY)
			check(fd >= 0, 3411)
			unmount_descriptor_data(fd)
			if kind == 9 {
				// Root itself still pins the copied mount. Exiting releases both
				// it and this descriptor without using a foreign escape route.
				check(C.close(fd) == 0 && C.close(outside) == 0, 3411)
				C._exit(0)
			}
			check(C.fchdir(outside) == 0, 3411)
			check(C.close(outside) == 0, 3411)
			unmount_descriptor_busy(c'/tmp/mount-lifecycle/uo/a', c'/tmp/mount-lifecycle/uo/a/marker')
			check(C.close(fd) == 0 && C.umount2(c'/tmp/mount-lifecycle/uo/a', 0) == 0, 3411)
			C._exit(0)
		}
		check(C.close(outside) == 0 && C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0, 3410)
		alias_wait(int(ready[0]))
		check(C.umount2(c'/tmp/mount-lifecycle/uo/a', 0) == 0, 3410)
		alias_signal(int(stop[1]))
		wait_child(child)
	}
}

fn unmount_publication_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3402)
		busy_mount(c'/tmp/mount-lifecycle/uo')
		directory(c'/tmp/mount-lifecycle/uo/a')
		directory(c'/tmp/mount-lifecycle/uo/b')
		busy_mount(c'/tmp/mount-lifecycle/uo/a')
		marker(c'/tmp/mount-lifecycle/uo/a/marker')
		if kind >= 8 {
			unmount_publication_copied_directory(kind)
			check(C.umount2(c'/tmp/mount-lifecycle/uo', 0) == 0, 3412)
			return
		}
		check(C.syscall(int(C.SYS_mknodat), i32(C.AT_FDCWD), c'/tmp/mount-lifecycle/uo/a/fifo',
			u32(C.S_IFIFO | 0o600), u64(0)) == 0
			&& C.mount(c'/tmp/mount-lifecycle/uo/a', c'/tmp/mount-lifecycle/uo/b', nil,
				usize(C.MS_BIND), nil) == 0, 3402)
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 3402)
		child := C.fork()
		check(child >= 0, 3402)
		if child == 0 {
			check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3402)
			if kind == 6 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3403) }
			unmount_exec_signal(int(ready[1]))
			fd := C.open(c'/tmp/mount-lifecycle/uo/a/fifo', if kind in [1, 3] { C.O_WRONLY } else { C.O_RDONLY })
			if kind < 2 {
				if fd != -1 || *C.__errno_location() != C.EBUSY {
					C.printf(c'MOUNT PUBLICATION RESULT: result=%d errno=%d expected=16\n', i32(fd), *C.__errno_location())
					check(false, 3400)
				}
			} else {
				check(fd >= 0, 3403)
				if kind == 6 { refused_unmount(c'/tmp/mount-lifecycle/uo/a', 0, C.EBUSY, 3403) }
			}
			unmount_exec_signal(int(ready[1]))
			unmount_exec_wait(int(stop[0]))
			if kind >= 2 { check(C.close(fd) == 0, 3403) }
			if kind == 6 { check(C.umount2(c'/tmp/mount-lifecycle/uo/a', 0) == 0, 3403) }
			C._exit(0)
		}
		check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0, 3402)
		unmount_exec_wait(int(ready[0]))
		unmount_publication_sleeping(child)
		if kind in [0, 1, 6] {
			// Native 0/1 qualify late-publication refusal. Linux instead keeps
			// the mount busy for the blocked open, so these are native-only.
			check(C.umount2(c'/tmp/mount-lifecycle/uo/a', 0) == 0, 3404)
		} else if kind in [2, 3] {
			check(C.umount2(c'/tmp/mount-lifecycle/uo/a', int(C.MNT_DETACH)) == 0, 3404)
			busy_mount(c'/tmp/mount-lifecycle/uo/a')
			check(C.umount2(c'/tmp/mount-lifecycle/uo/a', 0) == 0, 3404)
		} else if kind == 4 {
			held := C.open(c'/tmp/mount-lifecycle/uo/a/marker', C.O_RDONLY)
			check(held >= 0, 3405)
			unmount_descriptor_busy(c'/tmp/mount-lifecycle/uo/a', c'/tmp/mount-lifecycle/uo/a/marker')
			check(C.close(held) == 0, 3405)
		} else if kind == 5 {
			check(C.umount2(c'/tmp/mount-lifecycle/uo/b', 0) == 0, 3405)
		} else {
			denied := C.fork()
			check(denied >= 0, 3406)
			if denied == 0 {
				check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 3406)
				refused_unmount(c'/tmp/mount-lifecycle/uo/a', 0, C.EPERM, 3406)
				C._exit(0)
			}
			wait_child(denied)
		}
		// The sibling bind keeps the FIFO reachable without retaining the
		// removed attachment. Opening its other end now releases the wait.
		path := if kind == 5 { &char(c'/tmp/mount-lifecycle/uo/a/fifo') }
			else { &char(c'/tmp/mount-lifecycle/uo/b/fifo') }
		peer := C.open(path, C.O_NONBLOCK | if kind in [1, 3] { C.O_RDONLY } else { C.O_WRONLY })
		check(peer >= 0, 3407)
		unmount_exec_wait(int(ready[0]))
		check(C.close(peer) == 0, 3407)
		if kind in [4, 5, 7] {
			// The completed publication must be visible to ordinary unmount.
			unmount_descriptor_busy(c'/tmp/mount-lifecycle/uo/a', c'/tmp/mount-lifecycle/uo/a/marker')
		}
		unmount_exec_signal(int(stop[1]))
		wait_child(child)
		check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3407)
		if kind in [4, 5, 7] { check(C.umount2(c'/tmp/mount-lifecycle/uo/a', 0) == 0, 3408) }
		if kind != 5 { check(C.umount2(c'/tmp/mount-lifecycle/uo/b', 0) == 0, 3408) }
		check(C.umount2(c'/tmp/mount-lifecycle/uo', 0) == 0, 3408)
	}
}

fn unmount_publication_cases(selected int, portable bool) {
	unsafe { directory(c'/tmp/mount-lifecycle/uo') }
	for kind in 0 .. 10 {
		if (portable && kind < 2) || (selected >= 0 && kind != selected) { continue }
		child := C.fork()
		check(child >= 0, 3409)
		if child == 0 { unmount_publication_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT PUBLICATION CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT PUBLICATION: PASS')
	C.fflush(unsafe { nil })
}
