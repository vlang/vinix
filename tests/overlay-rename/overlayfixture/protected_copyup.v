// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

fn protected_base(group int, layer int) &char {
	return unsafe {
		if group == 1 {
			if layer == 0 { &char(c'/tmp/overlay-state/prot-lower') }
			else if layer == 1 { &char(c'/tmp/overlay-state/prot-merged') }
			else { &char(c'/tmp/overlay-state/prot-upper') }
		} else if group == 2 {
			if layer == 0 { &char(c'/tmp/overlay-state/diskmerged/prot-stacked-lower') }
			else if layer == 1 { &char(c'/tmp/overlay-state/prot-stacked') }
			else { &char(c'/tmp/overlay-volume/prot-upper') }
		} else {
			if layer == 0 { &char(c'/tmp/overlay-state/disklower') }
			else if layer == 1 { &char(c'/tmp/overlay-state/diskmerged') }
			else { &char(c'/tmp/overlay-volume/upper') }
		}
	}
}

fn protected_path(base &char, group int, index int, path &char) {
	check(C.snprintf(path, 512, c'%s/protected-%d-%d', base, group, index) > 0, 690)
}

fn prepare_protected_copyup() {
	unsafe {
		for name in [&char(c'prot-lower'), &char(c'prot-upper'), &char(c'prot-work'), &char(c'prot-merged'), &char(c'prot-stacked')]! {
			mut path := [512]char{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/%s', name) > 0, 691)
			owned_directory(&path[0], 691)
		}
		owned_directory(c'/tmp/overlay-volume/prot-upper', 691)
		owned_directory(c'/tmp/overlay-volume/prot-work', 691)
		// Keep this backing subtree stable. Other suites remove names from the
		// inner root, while mounted overlay views retain their cached children.
		owned_directory(c'/tmp/overlay-state/disklower/prot-stacked-lower', 691)
		for group in 0 .. 3 {
			// Populate every lower before the first lookup in either overlay.
			base := if group == 1 { &char(c'/tmp/overlay-state/prot-lower') }
				else if group == 2 { &char(c'/tmp/overlay-state/disklower/prot-stacked-lower') }
				else { &char(c'/tmp/overlay-state/disklower') }
			for index in 0 .. 9 {
				mut path := [512]char{}
				protected_path(base, group, index, &path[0])
				if index == 7 {
					owned_directory(&path[0], 692)
					mut child := [512]char{}
					check(C.snprintf(&child[0], 512, c'%s/old', &path[0]) > 0, 692)
					write_file(&child[0], c'COPYDATA', 692)
					check(C.chown(&child[0], 1000, 1000) == 0, 692)
				} else {
					write_file(&path[0], c'COPYDATA', 692)
					check(C.chown(&path[0], 1000, 1000) == 0, 692)
				}
				check(C.setxattr(&path[0], c'user.keep', c'OLD', 3, 0) == 0, 692)
				fd := C.open(&path[0], C.O_RDONLY)
				check(fd >= 0 && inode_flag_set(fd, if index == 8 { 0 } else { 0x20 }) == 0 && C.close(fd) == 0, 693)
			}
		}
		check(C.mount(c'overlay', c'/tmp/overlay-state/prot-merged', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/prot-lower,upperdir=/tmp/overlay-state/prot-upper,workdir=/tmp/overlay-state/prot-work') == 0, 694)
	}
}

fn mount_protected_stack() {
	unsafe {
		check(C.mount(c'overlay', c'/tmp/overlay-state/prot-stacked', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/diskmerged/prot-stacked-lower,upperdir=/tmp/overlay-volume/prot-upper,workdir=/tmp/overlay-volume/prot-work') == 0, 694)
	}
}

fn protected_contents(path &char, index int) {
	unsafe {
		if index != 6 { check(contents(path, c'COPYDATA'), 703); return }
		fd := C.open(path, C.O_RDONLY)
		mut data := [9]char{}
		check(fd >= 0 && C.read(fd, &data[0], 9) == 9
			&& C.memcmp(&data[0], c'COPYDATAQ', 9) == 0 && C.close(fd) == 0, 703)
	}
}

fn protected_flags(fd int, group int, index int) {
	unsafe {
		observed := inode_flags(fd)
		expected := if index == 8 { 0 } else { 0x20 }
		if observed != expected {
			C.printf(c'OVERLAY PROTECTED COPY: group=%d index=%d flags=%x expected=%x\n', group, index, observed, expected)
			C.fflush(nil)
		}
		check(observed == expected, 695)
	}
}

fn protected_refuse_unlink(path &char, group int) {
	unsafe {
		result := C.unlink(path)
		failure := *C.__errno_location()
		if result != -1 || failure != C.EPERM {
			C.printf(c'OVERLAY PROTECTED UNLINK: group=%d path=%s result=%d errno=%d expected=%d\n', group, path, result, failure, C.EPERM)
			C.fflush(nil)
		}
		check(result == -1 && failure == C.EPERM, 697)
	}
}

fn exercise_protected_copyup() {
	unsafe {
		for group in 0 .. 3 {
			for index in 0 .. 9 {
				mut path := [512]char{}
				mut upper := [512]char{}
				mut lower := [512]char{}
				protected_path(protected_base(group, 1), group, index, &path[0])
				protected_path(protected_base(group, 2), group, index, &upper[0])
				protected_path(protected_base(group, 0), group, index, &lower[0])
				fd := C.open(&path[0], C.O_RDONLY)
				check(fd >= 0, 696)
				inode_flag_absent(&upper[0])
				match index {
					0, 8 { check(C.setxattr(&path[0], c'user.copy', c'YES', 3, 0) == 0, 696) }
					1 { check(C.removexattr(&path[0], c'user.keep') == 0, 696) }
					2 { check(C.chmod(&path[0], 0o600) == 0, 696) }
					3 { check(C.chown(&path[0], 1000, 1000) == 0, 696) }
					4 { check(C.utimensat(C.AT_FDCWD, &path[0], nil, 0) == 0, 696) }
					5 { check(C.fchmod(fd, 0o600) == 0, 696) }
					6 {
						append_fd := C.open(&path[0], C.O_WRONLY | C.O_APPEND)
						check(append_fd >= 0 && C.write(append_fd, c'Q', 1) == 1
							&& C.fsync(append_fd) == 0 && C.close(append_fd) == 0, 696)
					}
					7 {
						mut child := [512]char{}
						check(C.snprintf(&child[0], 512, c'%s/new', &path[0]) > 0, 696)
						write_file(&child[0], c'COPYDATA', 696)
						protected_refuse_unlink(&child[0], group)
						check(C.snprintf(&child[0], 512, c'%s/old', &path[0]) > 0, 697)
						protected_refuse_unlink(&child[0], group)
					}
					else {}
				}
				protected_flags(fd, group, index)
				check(C.close(fd) == 0, 698)
				upper_fd := C.open(&upper[0], C.O_RDONLY)
				lower_fd := C.open(&lower[0], C.O_RDONLY)
				check(upper_fd >= 0 && lower_fd >= 0, 698)
				protected_flags(upper_fd, group, index)
				protected_flags(lower_fd, group, index)
				check(C.close(upper_fd) == 0 && C.close(lower_fd) == 0, 698)
				if index != 7 {
					check(contents(&lower[0], c'COPYDATA'), 699)
					protected_contents(&path[0], index)
				}
				mut value := [8]char{}
				check(C.getxattr(&lower[0], c'user.keep', &value[0], 8) == 3
					&& C.memcmp(&value[0], c'OLD', 3) == 0, 699)
				if group == 2 {
					mut inner_upper := [512]char{}
					protected_path(c'/tmp/overlay-volume/upper/prot-stacked-lower', group, index, &inner_upper[0])
					inode_flag_absent(&inner_upper[0])
				}
				if index != 8 {
					check(C.unlink(&path[0]) == -1 && *C.__errno_location() == C.EPERM, 699)
					if index != 7 {
						check(C.open(&path[0], C.O_WRONLY) == -1 && *C.__errno_location() == C.EPERM, 699)
						check(C.vinix_overlay_truncate(&path[0], 0) == -1 && *C.__errno_location() == C.EPERM, 699)
					}
				}
			}
		}
		C.puts(c'OVERLAY PROTECTED COPY-UP: PASS')
		C.fflush(nil)
	}
}

fn protected_copyup_cycle() {
	unsafe {
		for group in 0 .. 3 {
			mut path := [512]char{}
			protected_path(protected_base(group, 1), group, 0, &path[0])
			check(C.setxattr(&path[0], c'user.copy', c'YES', 3, 0) == 0, 700)
			fd := C.open(&path[0], C.O_RDONLY)
			check(fd >= 0, 700)
			protected_flags(fd, group, 0)
			check(C.close(fd) == 0, 700)
		}
	}
}

fn close_protected_copyup() {
	unsafe {
		overlay_depth_limit()
		check(C.umount(c'/tmp/overlay-state/prot-stacked') == 0
			&& C.umount(c'/tmp/overlay-state/prot-merged') == 0
			&& C.usleep(25000000) == 0, 701)
	}
}

fn persisted_protected_copyup() {
	unsafe {
		for group in [0, 2]! {
			for index in 0 .. 9 {
				mut upper := [512]char{}
				protected_path(protected_base(group, 2), group, index, &upper[0])
				fd := C.open(&upper[0], C.O_RDONLY)
				check(fd >= 0, 702)
				protected_flags(fd, group, index)
				check(C.close(fd) == 0, 702)
				if index != 7 { protected_contents(&upper[0], index) }
			}
		}
		C.puts(c'OVERLAY PROTECTED PERSISTENCE: PASS')
		C.fflush(nil)
	}
}
