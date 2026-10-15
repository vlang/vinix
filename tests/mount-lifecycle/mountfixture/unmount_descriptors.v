// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn unmount_descriptor_busy(path &char, marker_path &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(path, &before) == 0, 3300)
		for _ in 0 .. 200 {
			refused_unmount(path, 0, C.EBUSY, 3300)
			check(same(path, &before) && contents(marker_path), 3300)
		}
	}
}

fn unmount_descriptor_data(fd int) {
	unsafe {
		mut bytes := [8]u8{}
		check(C.syscall(int(C.SYS_pread64), i32(fd), &bytes[0], usize(8), i64(0)) == 8
			&& C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 3301)
	}
}

fn unmount_descriptor_tree() {
	unsafe {
		busy_mount(c'/tmp/mount-lifecycle/uf/a')
		marker(c'/tmp/mount-lifecycle/uf/a/marker')
	}
}

fn unmount_descriptor_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3302)
		busy_mount(c'/tmp/mount-lifecycle/uf')
		directory(c'/tmp/mount-lifecycle/uf/a')
		directory(c'/tmp/mount-lifecycle/uf/b')
		unmount_descriptor_tree()
		if kind == 7 {
			for direction in 0 .. 2 {
				check(C.mount(c'/tmp/mount-lifecycle/uf/a', c'/tmp/mount-lifecycle/uf/b', nil,
					usize(C.MS_BIND), nil) == 0, 3303)
				active := if direction == 0 { &char(c'/tmp/mount-lifecycle/uf/a') } else { &char(c'/tmp/mount-lifecycle/uf/b') }
				other := if direction == 0 { &char(c'/tmp/mount-lifecycle/uf/b') } else { &char(c'/tmp/mount-lifecycle/uf/a') }
				path := if direction == 0 { &char(c'/tmp/mount-lifecycle/uf/a/marker') } else { &char(c'/tmp/mount-lifecycle/uf/b/marker') }
				fd := C.open(path, C.O_RDONLY)
				check(fd >= 0 && C.umount2(other, 0) == 0, 3303)
				unmount_descriptor_busy(active, path)
				unmount_descriptor_data(fd)
				check(C.close(fd) == 0 && C.umount2(active, 0) == 0, 3303)
				if direction == 0 { unmount_descriptor_tree() }
			}
		} else {
			path := if kind in [2, 3, 8] { &char(c'/tmp/mount-lifecycle/uf/a') }
				else { &char(c'/tmp/mount-lifecycle/uf/a/marker') }
			flags := if kind in [1, 3, 8] { int(C.O_PATH) } else { int(C.O_RDONLY) }
			mut fd := C.open(path, flags | if kind in [2, 3, 8] { C.O_DIRECTORY } else { 0 })
			check(fd >= 0, 3304)
			if kind == 4 {
				copy := C.syscall(int(C.SYS_dup), i32(fd))
				check(copy >= 0 && C.close(fd) == 0, 3304)
				fd = int(copy)
			}
			if kind in [5, 6] {
				mut ready := [2]i32{}
				mut stop := [2]i32{}
				check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 3305)
				child := C.fork()
				check(child >= 0, 3305)
				if child == 0 {
					check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3305)
					if kind == 6 {
						check(C.unshare(int(C.CLONE_NEWNS)) == 0
							&& C.umount2(c'/tmp/mount-lifecycle/uf/a', 0) == 0, 3305)
					} else {
						check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 3305)
						refused_unmount(c'/tmp/mount-lifecycle/uf/a', 0, C.EPERM, 3305)
					}
					alias_signal(int(ready[1]))
					alias_wait(int(stop[0]))
					unmount_descriptor_data(fd)
					// Exit closes the child's last descriptor before zombie reaping.
					C._exit(0)
				}
				check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0
					&& C.close(fd) == 0, 3305)
				alias_wait(int(ready[0]))
				unmount_descriptor_busy(c'/tmp/mount-lifecycle/uf/a', c'/tmp/mount-lifecycle/uf/a/marker')
				alias_signal(int(stop[1]))
				mut info := [128]u8{}
				check(C.syscall(int(C.SYS_waitid), i32(C.P_PID), i32(child), &info[0],
					i32(C.WEXITED | C.WNOWAIT), nil) == 0, 3306)
				mut zombie := [128]char{}
				mut st := C.stat{}
				check(C.snprintf(&zombie[0], 128, c'/proc/%d', i32(child)) > 0
					&& C.stat(&zombie[0], &st) == 0 && C.umount2(c'/tmp/mount-lifecycle/uf/a', 0) == 0, 3306)
				wait_child(child)
			} else if kind == 8 {
				check(C.umount2(c'/tmp/mount-lifecycle/uf/a', int(C.MNT_DETACH)) == 0, 3307)
				unmount_descriptor_tree()
				check(C.umount2(c'/tmp/mount-lifecycle/uf/a', 0) == 0, 3307)
				reader := C.openat(fd, c'marker', C.O_RDONLY)
				check(reader >= 0, 3307)
				unmount_descriptor_data(reader)
				check(C.close(reader) == 0 && C.close(fd) == 0, 3307)
			} else {
				if kind == 9 {
					check(C.unlink(c'/tmp/mount-lifecycle/uf/a/marker') == 0, 3308)
					mut st := C.stat{}
					check(C.fstat(fd, &st) == 0 && st.st_nlink == 0, 3308)
					marker(c'/tmp/mount-lifecycle/uf/a/marker')
				}
				unmount_descriptor_busy(c'/tmp/mount-lifecycle/uf/a', c'/tmp/mount-lifecycle/uf/a/marker')
				if kind in [0, 4, 9] { unmount_descriptor_data(fd) }
				check(C.close(fd) == 0 && C.umount2(c'/tmp/mount-lifecycle/uf/a', 0) == 0, 3309)
			}
		}
		check(C.umount2(c'/tmp/mount-lifecycle/uf', 0) == 0, 3310)
	}
}

fn unmount_descriptor_cases(selected int) {
	unsafe { directory(c'/tmp/mount-lifecycle/uf') }
	for kind in 0 .. 10 {
		if selected >= 0 && kind != selected { continue }
		child := C.fork()
		check(child >= 0, 3311)
		if child == 0 { unmount_descriptor_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT DESCRIPTOR CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT DESCRIPTORS: PASS')
	C.fflush(unsafe { nil })
}
