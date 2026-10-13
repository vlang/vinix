// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

fn C.getxattr(&char, &char, voidptr, usize) isize
fn C.setxattr(&char, &char, voidptr, usize, int) int
fn C.removexattr(&char, &char) int

fn prepare_opaque() {
	unsafe {
		for path in [&char(c'/tmp/overlay-state/disklower/opaque-create'),
			&char(c'/tmp/overlay-state/disklower/opaque-rename')]! {
			owned_directory(path, 140)
			mut child := [512]char{}
			for name in [&char(c'a'), &char(c'b')]! {
				check(C.snprintf(&child[0], 512, c'%s/%s', path, name) > 0, 141)
				write_file(&child[0], c'AAAAAAAA', 142)
				check(C.chown(&child[0], 1000, 1000) == 0, 143)
			}
		}
	}
}

fn opaque_changes() {
	unsafe {
		for directory in [&char(c'opaque-create'), &char(c'opaque-rename')]! {
			mut path := [512]char{}
			for name in [&char(c'a'), &char(c'b')]! {
				check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/diskmerged/%s/%s', directory, name) > 0
					&& C.unlink(&path[0]) == 0, 144)
			}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/diskmerged/%s', directory) > 0
				&& C.rmdir(&path[0]) == 0, 145)
		}
		check(C.mkdir(c'/tmp/overlay-state/diskmerged/opaque-create', 0o700) == 0, 146)
		write_file(c'/tmp/overlay-state/diskmerged/opaque-create/fresh', c'BBBBBBBB', 147)
		check(C.mkdir(c'/tmp/overlay-state/diskmerged/opaque-incoming', 0o700) == 0, 148)
		write_file(c'/tmp/overlay-state/diskmerged/opaque-incoming/fresh', c'BBBBBBBB', 149)
		check(C.rename(c'/tmp/overlay-state/diskmerged/opaque-incoming',
			c'/tmp/overlay-state/diskmerged/opaque-rename') == 0, 150)
		check_opaque_view()
		C.puts(c'OVERLAY OPAQUE CHANGES: PASS')
		C.fflush(nil)
	}
}

fn check_opaque_view() {
	unsafe {
		for directory in [&char(c'opaque-create'), &char(c'opaque-rename')]! {
			mut path := [512]char{}
			for name in [&char(c'a'), &char(c'b')]! {
				check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/diskmerged/%s/%s', directory, name) > 0, 151)
				fd := C.open(&path[0], C.O_RDONLY)
				code := *C.__errno_location()
				C.printf(c'OVERLAY OPAQUE HIDDEN: path=%s fd=%d errno=%d\n', &path[0], fd, code)
				C.fflush(nil)
				check(fd == -1 && code == C.ENOENT, 152)
			}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/diskmerged/%s/fresh', directory) > 0
				&& contents(&path[0], c'BBBBBBBB'), 153)
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/diskmerged/%s', directory) > 0, 154)
			dir := C.opendir(&path[0])
			check(dir != nil, 155)
			mut fresh := 0
			mut entries := 0
			errno_value := C.__errno_location()
			for {
				*errno_value = 0
				entry := C.readdir(dir)
				if entry == nil {
					check(*C.__errno_location() == 0, 156)
					break
				}
				entries++
				check(entries <= 3, 157)
				if C.strcmp(&entry.d_name[0], c'fresh') == 0 {
					fresh++
				} else {
					check(C.strcmp(&entry.d_name[0], c'.') == 0 || C.strcmp(&entry.d_name[0], c'..') == 0, 158)
				}
			}
			check(fresh == 1 && entries == 3 && C.closedir(dir) == 0, 159)
			mut value := [64]u8{}
			check(C.getxattr(&path[0], c'trusted.overlay.opaque', &value[0], 64) == -1
				&& *C.__errno_location() == C.ENODATA, 160)
			check(C.setxattr(&path[0], c'trusted.overlay.opaque', c'n', 1, 0) == -1
				&& *C.__errno_location() == C.EPERM
				&& C.removexattr(&path[0], c'trusted.overlay.opaque') == -1
				&& *C.__errno_location() == C.EPERM, 161)
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-volume/upper/%s', directory) > 0, 162)
			check(C.getxattr(&path[0], c'trusted.overlay.opaque', &value[0], 64) == -1
				&& *C.__errno_location() == C.ENODATA
				&& C.setxattr(&path[0], c'trusted.overlay.opaque', c'n', 1, 0) == -1
				&& *C.__errno_location() == C.EPERM, 163)
		}
	}
}

fn opaque_persistence() {
	unsafe {
		// Retire the removed directories and their child whiteouts before
		// remounting the backing volume, without changing the lower contents.
		check(C.usleep(6500000) == 0, 164)
		C.sync()
		check(C.umount(c'/tmp/overlay-state/diskmerged') == 0
			&& C.umount(c'/tmp/overlay-volume') == 0
			&& C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', 0, nil) == 0
			&& C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0,
				c'lowerdir=/tmp/overlay-state/disklower,upperdir=/tmp/overlay-volume/upper,workdir=/tmp/overlay-volume/work') == 0, 165)
		worker := C.fork()
		check(worker >= 0, 166)
		if worker == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 167)
			check_opaque_view()
			C._exit(0)
		}
		mut status := 0
		check(C.waitpid(worker, &status, 0) == worker && C.WIFEXITED(status) != 0
			&& C.WEXITSTATUS(status) == 0, 168)
		check_upper_links()
		for directory in [&char(c'opaque-create'), &char(c'opaque-rename')]! {
			mut path := [512]char{}
			mut value := [64]u8{}
			mut st := C.stat{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-volume/upper/%s', directory) > 0
				&& C.getxattr(&path[0], c'trusted.overlay.opaque', &value[0], 64) == 1
				&& value[0] == u8(`y`) && C.lstat(&path[0], &st) == 0
				&& st.st_uid == 1000 && st.st_gid == 1000 && st.st_mode & 0o7777 == 0o700, 169)
			for name in [&char(c'a'), &char(c'b')]! {
				check(C.snprintf(&path[0], 512, c'/tmp/overlay-state/disklower/%s/%s', directory, name) > 0
					&& contents(&path[0], c'AAAAAAAA'), 170)
			}
		}
		C.puts(c'OVERLAY OPAQUE REMOUNT: PASS')
		C.fflush(nil)
	}
}

// Compare the remounted inode's link count with actual named subdirectories.
fn check_upper_links() {
	unsafe {
		mut parent := C.stat{}
		check(C.lstat(c'/tmp/overlay-volume/upper', &parent) == 0, 172)
		dir := C.opendir(c'/tmp/overlay-volume/upper')
		check(dir != nil, 173)
		mut expected := u64(2)
		mut entries := 0
		errno_value := C.__errno_location()
		for {
			*errno_value = 0
			entry := C.readdir(dir)
			if entry == nil {
				check(*errno_value == 0, 174)
				break
			}
			entries++
			check(entries < 64, 175)
			if C.strcmp(&entry.d_name[0], c'.') == 0 || C.strcmp(&entry.d_name[0], c'..') == 0 {
				continue
			}
			mut path := [512]char{}
			mut st := C.stat{}
			check(C.snprintf(&path[0], 512, c'/tmp/overlay-volume/upper/%s', &entry.d_name[0]) > 0
				&& C.lstat(&path[0], &st) == 0, 176)
			if st.st_mode & C.S_IFMT == C.S_IFDIR { expected++ }
		}
		check(C.closedir(dir) == 0, 177)
		C.printf(c'OVERLAY UPPER LINKS: persisted=%lu expected=%lu\n', u64(parent.st_nlink), expected)
		C.fflush(nil)
		check(parent.st_nlink == expected, 178)
	}
}
