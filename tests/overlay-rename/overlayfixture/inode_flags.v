// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

fn C.vinix_overlay_truncate(&char, i64) int

fn inode_flag_path(base &char, index int, path &char) {
	check(C.snprintf(path, 512, c'%s/flags-%d', base, index) > 0, 650)
}

fn inode_flags(fd int) int {
	unsafe {
		bits := &i32(C.alloca(sizeof(i32)))
		*bits = -1
		check(C.ioctl(fd, u64(0x80086601), bits) == 0, 651)
		return int(*bits)
	}
}

fn inode_flag_set(fd int, value int) int {
	unsafe {
		bits := &i32(C.alloca(sizeof(i32)))
		*bits = i32(value)
		return C.ioctl(fd, u64(0x40086602), bits)
	}
}

fn inode_flag_initial(index int) int {
	return if index == 2 { 0x20 } else if index == 3 { 0x10 } else { 0 }
}

fn inode_flag_wanted(index int) int {
	return if index in [0, 4] { 0x20 } else if index == 1 { 0x10 } else { 0 }
}

fn inode_flag_absent(path &char) {
	unsafe {
		mut st := C.stat{}
		check(C.lstat(path, &st) == -1 && *C.__errno_location() == C.ENOENT, 652)
	}
}

fn prepare_inode_flags() {
	unsafe {
		for index in 0 .. 6 {
			mut lower := [512]char{}
			inode_flag_path(c'/tmp/overlay-state/disklower', index, &lower[0])
			if index == 4 { owned_directory(&lower[0], 653) }
			else {
				write_file(&lower[0], c'COPYDATA', 653)
				check(C.chown(&lower[0], 1000, 1000) == 0, 653)
			}
			lower_fd := C.open(&lower[0], C.O_RDONLY)
			check(lower_fd >= 0 && inode_flag_set(lower_fd, inode_flag_initial(index)) == 0
				&& C.close(lower_fd) == 0, 653)
		}
		// Finish the lower tree before the first merged-directory lookup.
		for index in 0 .. 6 {
			mut lower := [512]char{}
			mut merged := [512]char{}
			mut upper := [512]char{}
			inode_flag_path(c'/tmp/overlay-state/disklower', index, &lower[0])
			inode_flag_path(c'/tmp/overlay-state/diskmerged', index, &merged[0])
			inode_flag_path(c'/tmp/overlay-volume/upper', index, &upper[0])
			lower_fd := C.open(&lower[0], C.O_RDONLY)
			merged_fd := C.open(&merged[0], C.O_RDONLY)
			initial := inode_flag_initial(index)
			check(lower_fd >= 0 && merged_fd >= 0 && inode_flags(lower_fd) == initial, 653)
			inode_flag_absent(&upper[0])
			if index == 5 {
				check(C.ioctl(merged_fd, u64(0x40086602), voidptr(1)) == -1
					&& *C.__errno_location() == C.EFAULT, 655)
				check(inode_flag_set(merged_fd, 1) == -1
					&& *C.__errno_location() == C.ENOTSUP, 655)
				check(inode_flag_set(merged_fd, 0) == 0, 655)
				inode_flag_absent(&upper[0])
			} else {
				wanted := inode_flag_wanted(index)
				check(inode_flag_set(merged_fd, wanted) == 0, 653)
				observed := inode_flags(lower_fd)
				if observed != initial {
					C.printf(c'OVERLAY FLAGS: index=%d lower=%x expected=%x\n', index, observed, initial)
					C.fflush(nil)
				}
				check(observed == initial, 654)
				upper_fd := C.open(&upper[0], C.O_RDONLY)
				check(upper_fd >= 0 && inode_flags(upper_fd) == wanted
					&& inode_flags(merged_fd) == wanted && C.close(upper_fd) == 0, 656)
				if index != 4 {
					check(contents(&lower[0], c'COPYDATA') && contents(&merged[0], c'COPYDATA'), 657)
				}
			}
			check(inode_flags(lower_fd) == initial && C.close(lower_fd) == 0
				&& C.close(merged_fd) == 0, 658)
		}
		C.puts(c'OVERLAY FLAGS COPY-UP: PASS')
		C.fflush(nil)
	}
}

fn held_inode_flags() {
	unsafe {
		for name in [&char(c'flag-lower'), &char(c'flag-upper'), &char(c'flag-work'), &char(c'flag-merged')]! {
			mut path := [512]char{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/%s', name) > 0, 669)
			owned_directory(&path[0], 669)
		}
		for name in [&char(c'removed'), &char(c'existing'), &char(c'replaced')]! {
			mut path := [512]char{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/flag-lower/%s', name) > 0, 669)
			write_file(&path[0], c'COPYDATA', 669)
		}
		write_file(c'/tmp/overlay-state/flag-upper/incoming', c'NEWVALUE', 669)
		check(C.mount(c'overlay', c'/tmp/overlay-state/flag-merged', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/flag-lower,upperdir=/tmp/overlay-state/flag-upper,workdir=/tmp/overlay-state/flag-work') == 0, 669)
		removed := C.open(c'/tmp/overlay-state/flag-merged/removed', C.O_RDONLY)
		check(removed >= 0 && C.unlink(c'/tmp/overlay-state/flag-merged/removed') == 0, 669)
		result := inode_flag_set(removed, 0x20)
		code := *C.__errno_location()
		if result != -1 || code != C.ENOENT {
			C.printf(c'OVERLAY FLAGS REMOVED: result=%d errno=%d expected=%d\n', result, code, C.ENOENT)
			C.fflush(nil)
		}
		check(result == -1 && code == C.ENOENT && inode_flags(removed) == 0, 670)
		inode_flag_absent(c'/tmp/overlay-state/flag-merged/removed')
		mut marker := C.stat{}
		check(C.lstat(c'/tmp/overlay-state/flag-upper/removed', &marker) == 0
			&& marker.st_mode & C.S_IFMT == C.S_IFCHR && marker.st_rdev == 0, 671)
		check(C.close(removed) == 0, 671)
		upper := C.open(c'/tmp/overlay-state/flag-merged/existing', C.O_RDONLY)
		check(upper >= 0 && inode_flag_set(upper, 0x20) == 0 && inode_flag_set(upper, 0) == 0
			&& C.unlink(c'/tmp/overlay-state/flag-merged/existing') == 0
			&& inode_flag_set(upper, 0x10) == 0 && inode_flags(upper) == 0x10 && C.close(upper) == 0, 672)
		inode_flag_absent(c'/tmp/overlay-state/flag-merged/existing')
		replaced := C.open(c'/tmp/overlay-state/flag-merged/replaced', C.O_RDONLY)
		check(replaced >= 0 && C.rename(c'/tmp/overlay-state/flag-merged/incoming', c'/tmp/overlay-state/flag-merged/replaced') == 0, 673)
		check(inode_flag_set(replaced, 0x20) == -1 && *C.__errno_location() == C.ENOENT
			&& inode_flags(replaced) == 0 && C.close(replaced) == 0, 673)
		check(contents(c'/tmp/overlay-state/flag-merged/replaced', c'NEWVALUE'), 674)
		check(C.umount(c'/tmp/overlay-state/flag-merged') == 0
			&& C.mount(c'overlay', c'/tmp/overlay-state/flag-merged', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/flag-lower,upperdir=/tmp/overlay-state/flag-upper,workdir=/tmp/overlay-state/flag-work') == 0, 674)
		inode_flag_absent(c'/tmp/overlay-state/flag-merged/removed')
		inode_flag_absent(c'/tmp/overlay-state/flag-merged/existing')
		check(contents(c'/tmp/overlay-state/flag-merged/replaced', c'NEWVALUE'), 674)
		for name in [&char(c'removed'), &char(c'existing'), &char(c'replaced')]! {
			mut path := [512]char{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/flag-lower/%s', name) > 0, 675)
			fd := C.open(&path[0], C.O_RDONLY)
			check(fd >= 0 && inode_flags(fd) == 0 && C.close(fd) == 0 && contents(&path[0], c'COPYDATA'), 675)
		}
		check(C.umount(c'/tmp/overlay-state/flag-merged') == 0, 675)
		C.puts(c'OVERLAY FLAGS HELD ALIASES: PASS')
		C.fflush(nil)
	}
}

fn exercise_inode_flags() {
	unsafe {
		for phase in 60 .. 62 {
			for _ in 0 .. 200 {
				fd := C.open(c'/tmp/overlay-state/diskmerged/flags-5', C.O_RDONLY)
				check(fd >= 0 && inode_flag_set(fd, 0x20) == -1
					&& *C.__errno_location() == C.EPERM
					&& inode_flag_set(fd, 0) == -1 && *C.__errno_location() == C.EPERM && inode_flags(fd) == 0
					&& C.close(fd) == 0, 659)
				inode_flag_absent(c'/tmp/overlay-volume/upper/flags-5')
			}
			check(C.usleep(25000000) == 0, 660)
			sample(phase)
		}
		append_path := &char(c'/tmp/overlay-state/diskmerged/flags-0')
		check(C.open(append_path, C.O_WRONLY) == -1 && *C.__errno_location() == C.EPERM, 661)
		check(C.vinix_overlay_truncate(append_path, 0) == -1 && *C.__errno_location() == C.EPERM, 661)
		check(C.unlink(append_path) == -1 && *C.__errno_location() == C.EPERM, 661)
		fd := C.open(append_path, C.O_WRONLY | C.O_APPEND)
		check(fd >= 0 && C.write(fd, c'Q', 1) == 1 && C.fsync(fd) == 0 && C.close(fd) == 0, 662)
		fd_read := C.open(append_path, C.O_RDONLY)
		mut data := [9]char{}
		check(fd_read >= 0 && C.read(fd_read, &data[0], 9) == 9
			&& C.memcmp(&data[0], c'COPYDATAQ', 9) == 0 && C.close(fd_read) == 0, 662)
		immutable := &char(c'/tmp/overlay-state/diskmerged/flags-1')
		check(C.open(immutable, C.O_WRONLY) == -1 && *C.__errno_location() == C.EPERM, 663)
		check(C.chmod(immutable, 0o400) == -1 && *C.__errno_location() == C.EPERM, 663)
		check(C.setxattr(immutable, c'user.guard', c'Q', 1, 0) == -1 && *C.__errno_location() == C.EPERM, 663)
		check(C.unlink(immutable) == -1 && *C.__errno_location() == C.EPERM, 663)
		write_file(c'/tmp/overlay-state/diskmerged/flags-2', c'CHANGED!', 664)
		check(C.chmod(c'/tmp/overlay-state/diskmerged/flags-3', 0o400) == 0, 664)
		write_file(c'/tmp/overlay-state/diskmerged/flags-4/child', c'COPYDATA', 664)
		check(C.unlink(c'/tmp/overlay-state/diskmerged/flags-4/child') == -1
			&& *C.__errno_location() == C.EPERM, 664)
		for index in 0 .. 6 {
			mut lower := [512]char{}
			inode_flag_path(c'/tmp/overlay-state/disklower', index, &lower[0])
			lower_fd := C.open(&lower[0], C.O_RDONLY)
			check(lower_fd >= 0 && inode_flags(lower_fd) == inode_flag_initial(index)
				&& C.close(lower_fd) == 0, 665)
			if index != 4 { check(contents(&lower[0], c'COPYDATA'), 665) }
		}
		C.puts(c'OVERLAY FLAGS AUTHORIZATION: PASS')
		C.fflush(nil)
	}
}

// Called after the ordinary volume remount, including a read-only remount.
fn persisted_inode_flags(readonly bool) {
	unsafe {
		for index in 0 .. 5 {
			mut upper := [512]char{}
			inode_flag_path(c'/tmp/overlay-volume/upper', index, &upper[0])
			fd := C.open(&upper[0], C.O_RDONLY)
			check(fd >= 0, 666)
			observed := inode_flags(fd)
			if observed != inode_flag_wanted(index) {
				C.printf(c'OVERLAY FLAGS PERSISTENCE: index=%d observed=%x expected=%x\n', index, observed, inode_flag_wanted(index))
				C.fflush(nil)
			}
			check(observed == inode_flag_wanted(index), 666)
			if readonly {
				check(inode_flag_set(fd, 0) == -1 && *C.__errno_location() == C.EROFS
					&& inode_flags(fd) == inode_flag_wanted(index), 668)
			}
			check(C.close(fd) == 0, 666)
		}
		inode_flag_absent(c'/tmp/overlay-volume/upper/flags-5')
		check(contents(c'/tmp/overlay-volume/upper/flags-1', c'COPYDATA')
			&& contents(c'/tmp/overlay-volume/upper/flags-2', c'CHANGED!')
			&& contents(c'/tmp/overlay-volume/upper/flags-4/child', c'COPYDATA'), 667)
		C.puts(c'OVERLAY FLAGS PERSISTENCE: PASS')
		C.fflush(nil)
	}
}
