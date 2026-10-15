// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn unmount_writer_busy(path &char, marker_path &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(path, &before) == 0, 2900)
		for _ in 0 .. 200 {
			refused_unmount(path, 0, C.EBUSY, 2901)
			check(same(path, &before) && contents(marker_path), 2902)
			// A refused shutdown must not close admission for another writer.
			fresh := C.open(marker_path, C.O_WRONLY)
			check(fresh >= 0 && C.close(fresh) == 0, 2902)
		}
	}
}

fn unmount_writer_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 2903)
		busy_mount(c'/tmp/mount-lifecycle/uw')
		directory(c'/tmp/mount-lifecycle/uw/a')
		directory(c'/tmp/mount-lifecycle/uw/b')
		busy_mount(c'/tmp/mount-lifecycle/uw/a')
		marker(c'/tmp/mount-lifecycle/uw/a/marker')
		if kind == 0 {
			for flags in [int(C.O_WRONLY), int(C.O_RDWR)]! {
				fd := C.open(c'/tmp/mount-lifecycle/uw/a/marker', flags)
				check(fd >= 0, 2904)
				unmount_writer_busy(c'/tmp/mount-lifecycle/uw/a', c'/tmp/mount-lifecycle/uw/a/marker')
				check(C.close(fd) == 0, 2904)
			}
		} else if kind == 1 {
			fd := C.open(c'/tmp/mount-lifecycle/uw/a/marker', C.O_RDWR)
			copy := C.syscall(int(C.SYS_dup), i32(fd))
			check(fd >= 0 && copy >= 0 && C.close(fd) == 0, 2905)
			unmount_writer_busy(c'/tmp/mount-lifecycle/uw/a', c'/tmp/mount-lifecycle/uw/a/marker')
			check(C.close(int(copy)) == 0, 2905)
		} else if kind == 2 || kind == 6 {
			fd := C.open(c'/tmp/mount-lifecycle/uw/a/marker', C.O_RDWR)
			mut ready := [2]i32{}
			mut stop := [2]i32{}
			check(fd >= 0 && C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 2906)
			child := C.fork()
			check(child >= 0, 2906)
			if child == 0 {
				check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 2906)
				if kind == 6 {
					// Inherited writers pin the original object, not this namespace's
					// fresh attachment with the same id.
					check(C.unshare(int(C.CLONE_NEWNS)) == 0
						&& C.umount2(c'/tmp/mount-lifecycle/uw/a', 0) == 0, 2907)
				}
				mut token := u8(1)
				check(C.write(int(ready[1]), &token, 1) == 1 && C.close(int(ready[1])) == 0
					&& C.read(int(stop[0]), &token, 1) == 1 && C.close(int(stop[0])) == 0, 2906)
				if kind == 2 {
					check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 2908)
					refused_unmount(c'/tmp/mount-lifecycle/uw/a', 0, C.EPERM, 2908)
				}
				check(C.syscall(int(C.SYS_pwrite64), i32(fd), c'MOUNT-OK', usize(8), i64(0)) == 8
					&& C.close(fd) == 0, 2908)
				C._exit(0)
			}
			mut token := u8(0)
			check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0 && C.close(fd) == 0
				&& C.read(int(ready[0]), &token, 1) == 1 && C.close(int(ready[0])) == 0, 2906)
			unmount_writer_busy(c'/tmp/mount-lifecycle/uw/a', c'/tmp/mount-lifecycle/uw/a/marker')
			check(C.write(int(stop[1]), &token, 1) == 1 && C.close(int(stop[1])) == 0, 2906)
			wait_child(child)
		} else if kind == 3 || kind == 4 {
			fd := C.open(c'/tmp/mount-lifecycle/uw/a/marker', C.O_RDWR)
			page := usize(C.sysconf(C._SC_PAGESIZE))
			check(fd >= 0 && page >= 4096, 2909)
			mount_writer_truncate(fd, i64(page), 0)
			mapping := descriptor_map_open(fd, page, C.PROT_READ | C.PROT_WRITE,
				if kind == 3 { int(C.MAP_PRIVATE) } else { int(C.MAP_SHARED) }, 0)
			check(C.close(fd) == 0, 2909)
			descriptor_map_data(mapping)
			unmount_writer_busy(c'/tmp/mount-lifecycle/uw/a', c'/tmp/mount-lifecycle/uw/a/marker')
			check(C.munmap(mapping, page) == 0, 2909)
		} else if kind == 5 {
			for direction in 0 .. 2 {
				check(C.mount(c'/tmp/mount-lifecycle/uw/a', c'/tmp/mount-lifecycle/uw/b', nil,
					usize(C.MS_BIND), nil) == 0, 2910)
				active := if direction == 0 { &char(c'/tmp/mount-lifecycle/uw/a') } else { &char(c'/tmp/mount-lifecycle/uw/b') }
				other := if direction == 0 { &char(c'/tmp/mount-lifecycle/uw/b') } else { &char(c'/tmp/mount-lifecycle/uw/a') }
				path := if direction == 0 { &char(c'/tmp/mount-lifecycle/uw/a/marker') } else { &char(c'/tmp/mount-lifecycle/uw/b/marker') }
				fd := C.open(path, C.O_RDWR)
				check(fd >= 0 && C.umount2(other, 0) == 0, 2910)
				unmount_writer_busy(active, path)
				check(C.close(fd) == 0 && C.umount2(active, 0) == 0, 2910)
				if direction == 0 {
					busy_mount(c'/tmp/mount-lifecycle/uw/a')
					marker(c'/tmp/mount-lifecycle/uw/a/marker')
				}
			}
		} else {
			held := C.open(c'/tmp/mount-lifecycle/uw/a', C.O_PATH | C.O_DIRECTORY)
			reader := C.open(c'/tmp/mount-lifecycle/uw/a/marker', C.O_RDONLY)
			check(held >= 0 && reader >= 0, 2911)
			if kind == 7 {
				writer := C.open(c'/tmp/mount-lifecycle/uw/a/marker', C.O_RDWR)
				check(writer >= 0 && C.umount2(c'/tmp/mount-lifecycle/uw/a', int(C.MNT_DETACH)) == 0, 2911)
				for _ in 0 .. 200 {
					fresh := C.openat(held, c'marker', C.O_WRONLY)
					check(fresh >= 0 && C.close(fresh) == 0, 2911)
				}
				check(C.close(writer) == 0, 2911)
			} else {
				// Native-only admission control for the existing read-only/O_PATH
				// busy-accounting gap. A stale route cannot start a writer or
				// truncate after ordinary unmount has closed admission.
				check(C.umount2(c'/tmp/mount-lifecycle/uw/a', 0) == 0, 2912)
				for _ in 0 .. 200 {
					for flags in [int(C.O_WRONLY), int(C.O_RDWR), int(C.O_WRONLY | C.O_TRUNC), int(C.O_RDONLY | C.O_TRUNC)]! {
						result := C.openat(held, c'marker', flags)
						check(result == -1 && *C.__errno_location() == C.EBUSY, 2912)
					}
					mut after := C.stat{}
					mut bytes := [8]u8{}
					check(C.fstat(reader, &after) == 0 && after.st_size == 8
						&& C.syscall(int(C.SYS_pread64), i32(reader), &bytes[0], usize(8), i64(0)) == 8
						&& C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 2912)
				}
			}
			check(C.close(held) == 0 && C.close(reader) == 0, 2911)
		}
		if kind !in [5, 7, 8] { check(C.umount2(c'/tmp/mount-lifecycle/uw/a', 0) == 0, 2913) }
		check(C.umount2(c'/tmp/mount-lifecycle/uw', 0) == 0, 2913)
	}
}

fn unmount_writer_cases(selected int, portable bool) {
	unsafe { directory(c'/tmp/mount-lifecycle/uw') }
	for kind in 0 .. if portable { 8 } else { 9 } {
		if selected >= 0 && kind != selected { continue }
		child := C.fork()
		check(child >= 0, 2914)
		if child == 0 { unmount_writer_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT WRITER CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT WRITERS: PASS')
	C.fflush(unsafe { nil })
}
