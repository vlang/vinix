// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn unmount_mapping_busy(path &char, marker_path &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(path, &before) == 0, 3200)
		for _ in 0 .. 200 {
			refused_unmount(path, 0, C.EBUSY, 3200)
			check(same(path, &before) && contents(marker_path), 3200)
		}
	}
}

fn unmount_mapping_open(path &char, page usize, kind int) voidptr {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		check(fd >= 0, 3201)
		sharing := if kind == 1 { int(C.MAP_SHARED) } else { int(C.MAP_PRIVATE) }
		prot := C.PROT_READ | if kind == 2 { C.PROT_WRITE } else if kind == 3 { C.PROT_EXEC } else { 0 }
		length := if kind == 4 { 3 * page } else { page }
		mapping := descriptor_map_open(fd, length, prot, sharing, 0)
		check(C.close(fd) == 0, 3201)
		descriptor_map_data(mapping)
		if kind == 2 {
			*(&u8(mapping)) = `C`
			check(*(&u8(mapping)) == `C` && contents(path), 3201)
		}
		return mapping
	}
}

fn unmount_mapping_tree() {
	unsafe {
		busy_mount(c'/tmp/mount-lifecycle/uv/a')
		marker(c'/tmp/mount-lifecycle/uv/a/marker')
		// Three pages allow mprotect/munmap to split retained ranges.
		writer := C.open(c'/tmp/mount-lifecycle/uv/a/marker', C.O_WRONLY)
		check(writer >= 0, 3202)
		mount_writer_truncate(writer, 3 * C.sysconf(C._SC_PAGESIZE), 0)
		check(C.close(writer) == 0, 3202)
	}
}

fn unmount_mapping_case(kind int) {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		check(page >= 4096 && C.unshare(int(C.CLONE_NEWNS)) == 0, 3203)
		busy_mount(c'/tmp/mount-lifecycle/uv')
		directory(c'/tmp/mount-lifecycle/uv/a')
		directory(c'/tmp/mount-lifecycle/uv/b')
		unmount_mapping_tree()
		if kind == 7 {
			for direction in 0 .. 2 {
				check(C.mount(c'/tmp/mount-lifecycle/uv/a', c'/tmp/mount-lifecycle/uv/b', nil,
					usize(C.MS_BIND), nil) == 0, 3204)
				active := if direction == 0 { &char(c'/tmp/mount-lifecycle/uv/a') } else { &char(c'/tmp/mount-lifecycle/uv/b') }
				other := if direction == 0 { &char(c'/tmp/mount-lifecycle/uv/b') } else { &char(c'/tmp/mount-lifecycle/uv/a') }
				path := if direction == 0 { &char(c'/tmp/mount-lifecycle/uv/a/marker') } else { &char(c'/tmp/mount-lifecycle/uv/b/marker') }
				mapping := unmount_mapping_open(path, page, 0)
				check(C.umount2(other, 0) == 0, 3204)
				unmount_mapping_busy(active, path)
				descriptor_map_data(mapping)
				check(C.munmap(mapping, page) == 0 && C.umount2(active, 0) == 0, 3204)
				if direction == 0 { unmount_mapping_tree() }
			}
		} else if kind == 9 {
			fd := C.open(c'/tmp/mount-lifecycle/uv/a/marker', C.O_RDONLY)
			check(fd >= 0, 3205)
			mapping := descriptor_map_open(fd, page, C.PROT_READ | C.PROT_WRITE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS, 0)
			check(C.close(fd) == 0 && *(&u8(mapping)) == 0
				&& C.umount2(c'/tmp/mount-lifecycle/uv/a', 0) == 0, 3205)
			*(&u8(mapping)) = `A`
			check(*(&u8(mapping)) == `A` && C.munmap(mapping, page) == 0, 3205)
		} else {
			mapping := unmount_mapping_open(c'/tmp/mount-lifecycle/uv/a/marker', page, kind)
			if kind in [5, 6] {
				mut ready := [2]i32{}
				mut stop := [2]i32{}
				check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 3206)
				child := C.fork()
				check(child >= 0, 3206)
				if child == 0 {
					check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3206)
					if kind == 6 {
						check(C.unshare(int(C.CLONE_NEWNS)) == 0
							&& C.umount2(c'/tmp/mount-lifecycle/uv/a', 0) == 0, 3206)
					} else {
						check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 3206)
						refused_unmount(c'/tmp/mount-lifecycle/uv/a', 0, C.EPERM, 3206)
					}
					alias_signal(int(ready[1]))
					alias_wait(int(stop[0]))
					descriptor_map_data(mapping)
					// Exit, rather than explicit munmap, releases this last view.
					C._exit(0)
				}
				check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0
					&& C.munmap(mapping, page) == 0, 3206)
				alias_wait(int(ready[0]))
				unmount_mapping_busy(c'/tmp/mount-lifecycle/uv/a', c'/tmp/mount-lifecycle/uv/a/marker')
				alias_signal(int(stop[1]))
				mut info := [128]u8{}
				check(C.syscall(int(C.SYS_waitid), i32(C.P_PID), i32(child), &info[0],
					i32(C.WEXITED | C.WNOWAIT), nil) == 0, 3207)
				mut path := [128]char{}
				mut st := C.stat{}
				check(C.snprintf(&path[0], 128, c'/proc/%d', i32(child)) > 0
					&& C.stat(&path[0], &st) == 0 && C.umount2(c'/tmp/mount-lifecycle/uv/a', 0) == 0, 3207)
				wait_child(child)
			} else if kind == 8 {
				check(C.umount2(c'/tmp/mount-lifecycle/uv/a', int(C.MNT_DETACH)) == 0, 3208)
				unmount_mapping_tree()
				check(C.umount2(c'/tmp/mount-lifecycle/uv/a', 0) == 0, 3208)
				descriptor_map_data(mapping)
				check(C.munmap(mapping, page) == 0, 3208)
			} else {
				unmount_mapping_busy(c'/tmp/mount-lifecycle/uv/a', c'/tmp/mount-lifecycle/uv/a/marker')
				if kind == 4 {
					middle := voidptr(u64(mapping) + page)
					last := voidptr(u64(mapping) + 2 * page)
					descriptor_map_protect(middle, page, C.PROT_NONE, 0)
					check(C.munmap(mapping, page) == 0 && C.munmap(middle, page) == 0, 3209)
					unmount_mapping_busy(c'/tmp/mount-lifecycle/uv/a', c'/tmp/mount-lifecycle/uv/a/marker')
					check(*(&u8(last)) == 0 && C.munmap(last, page) == 0, 3209)
				} else { check(C.munmap(mapping, page) == 0, 3209) }
				check(C.umount2(c'/tmp/mount-lifecycle/uv/a', 0) == 0, 3209)
			}
		}
		check(C.umount2(c'/tmp/mount-lifecycle/uv', 0) == 0, 3210)
	}
}

fn unmount_mapping_cases(selected int) {
	unsafe { directory(c'/tmp/mount-lifecycle/uv') }
	for kind in 0 .. 10 {
		if selected >= 0 && kind != selected { continue }
		child := C.fork()
		check(child >= 0, 3211)
		if child == 0 { unmount_mapping_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT MAPPING CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT MAPPINGS: PASS')
	C.fflush(unsafe { nil })
}
