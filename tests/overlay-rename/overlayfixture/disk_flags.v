// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

fn disk_flags_get(fd int) int {
	unsafe {
		bits := &i32(C.alloca(sizeof(i32)))
		*bits = -1
		check(C.ioctl(fd, u64(0x80086601), bits) == 0, 680)
		return int(*bits)
	}
}

fn disk_flags_set(fd int, value int) {
	unsafe {
		bits := &i32(C.alloca(sizeof(i32)))
		*bits = i32(value)
		check(C.ioctl(fd, u64(0x40086602), bits) == 0, 681)
	}
}

fn direct_inode_flags_persistence() {
	unsafe {
		write_file(c'/tmp/overlay-volume/protected-file', c'COPYDATA', 682)
		check(C.mkdir(c'/tmp/overlay-volume/protected-dir', 0o700) == 0, 682)
		for path in [&char(c'/tmp/overlay-volume/protected-file'), &char(c'/tmp/overlay-volume/protected-dir'), &char(c'/tmp/overlay-volume')]! {
			fd := C.open(path, C.O_RDONLY)
			check(fd >= 0 && disk_flags_get(fd) == 0, 682)
			disk_flags_set(fd, 0x10 | 0x20)
			check(disk_flags_get(fd) == 0x30 && C.close(fd) == 0, 682)
		}
		// prepare_disk exercises refused work directories and retires their
		// temporary backing inodes. Drain those queues before unmounting.
		check(C.usleep(25000000) == 0, 687)
		C.sync()
		check(C.umount(c'/tmp/overlay-state/diskmerged') == 0 && C.umount(c'/tmp/overlay-volume') == 0, 683)
		check(C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', 0, nil) == 0, 683)
		for path in [&char(c'/tmp/overlay-volume/protected-file'), &char(c'/tmp/overlay-volume/protected-dir'), &char(c'/tmp/overlay-volume')]! {
			fd := C.open(path, C.O_RDONLY)
			check(fd >= 0, 684)
			observed := disk_flags_get(fd)
			if observed != 0x30 {
				C.printf(c'EXT2 FLAGS REMOUNT: path=%s observed=%x expected=30\n', path, observed)
				C.fflush(nil)
			}
			check(observed == 0x30 && C.close(fd) == 0, 684)
		}
		check(C.open(c'/tmp/overlay-volume/protected-file', C.O_WRONLY) == -1
			&& *C.__errno_location() == C.EPERM, 685)
		check(C.chmod(c'/tmp/overlay-volume/protected-dir', 0o755) == -1
			&& *C.__errno_location() == C.EPERM, 685)
		check(C.mkdir(c'/tmp/overlay-volume/new-child', 0o700) == -1
			&& *C.__errno_location() == C.EPERM, 685)
		check(contents(c'/tmp/overlay-volume/protected-file', c'COPYDATA'), 685)
		C.sync()
		check(C.umount(c'/tmp/overlay-volume') == 0, 686)
		C.puts(c'EXT2 FLAGS REMOUNT: PASS')
		C.fflush(nil)
	}
}
