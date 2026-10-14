// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>
struct C.timespec {
	tv_sec  i64
	tv_nsec i64
}

struct C.stat {
	st_ino   u64
	st_uid   u32
	st_gid   u32
	st_mode  u32
	st_nlink u64
	st_rdev  u64
}

struct C.dirent {
	d_name [256]char
}

fn C.clock_gettime(int, &C.timespec) int
fn C.open(&char, int, ...) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.fsync(int) int
fn C.fstat(int, &C.stat) int
fn C.lstat(&char, &C.stat) int
fn C.rename(&char, &char) int
fn C.mkdir(&char, u32) int
fn C.chown(&char, u32, u32) int
fn C.chmod(&char, u32) int
fn C.mknod(&char, u32, u64) int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.getuid() u32
fn C.geteuid() u32
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C.WIFEXITED(int) int
fn C.WEXITSTATUS(int) int
fn C.__errno_location() &i32
fn C.memcmp(voidptr, voidptr, usize) int
fn C.strcmp(&char, &char) int
fn C.opendir(&char) voidptr
fn C.readdir(voidptr) &C.dirent
fn C.closedir(voidptr) int
fn C.snprintf(voidptr, usize, &char, ...) int
fn C.printf(&char, ...) int
fn C.fflush(voidptr) int
fn C.puts(&char) int
fn C.usleep(u32) int
fn C._exit(int)
fn C.pause() int
fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.unlink(&char) int
fn C.rmdir(&char) int
fn C.symlink(&char, &char) int
fn C.link(&char, &char) int
fn C.sync()

fn owned_directory(path &char, site int) {
	check(C.mkdir(path, 0o700) == 0 && C.chown(path, 1000, 1000) == 0, site)
}

fn prepare() {
	unsafe {
		owned_directory(c'/tmp/overlay-state/lower', 31)
		owned_directory(c'/tmp/overlay-state/upper', 32)
		owned_directory(c'/tmp/overlay-state/work', 33)
		owned_directory(c'/tmp/overlay-state/merged', 34)
		fd := C.open(c'/tmp/overlay-state/lower/current', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0 && C.write(fd, c'AAAAAAAA', 8) == 8 && C.close(fd) == 0
			&& C.chown(c'/tmp/overlay-state/lower/current', 1000, 1000) == 0, 35)
		check(C.mount(c'overlay', c'/tmp/overlay-state/merged', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/lower,upperdir=/tmp/overlay-state/upper,workdir=/tmp/overlay-state/work') == 0, 36)
	}
}

fn write_file(path &char, value &char, site int) {
	fd := C.open(path, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0 && C.write(fd, value, 8) == 8 && C.fsync(fd) == 0 && C.close(fd) == 0, site)
}

fn contents(path &char, value &char) bool {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return false }
		mut data := [8]char{}
		count := C.read(fd, &data[0], 8)
		closed := C.close(fd)
		return count == 8 && closed == 0 && C.memcmp(&data[0], value, 8) == 0
	}
}

// tmpfs accepts this basename, but ext2 rejects its on-disk encoding. This
// exercises a real backend error after overlay has resolved its destination.
fn long_path(path &char, base &char) {
	unsafe {
		length := C.snprintf(path, 512, c'%s/', base)
		check(length > 0 && length + 256 < 512, 50)
		for index in 0 .. 256 { path[length + index] = char(`x`) }
		path[length + 256] = 0
	}
}

fn volume_device() &char {
	return $if arm64 { c'/dev/vda' } $else { c'/dev/sd0' }
}

fn prepare_disk(opaque bool, full bool) {
	unsafe {
		owned_directory(c'/tmp/overlay-volume', 51)
		check(C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', 0, nil) == 0
			&& C.chown(c'/tmp/overlay-volume', 1000, 1000) == 0, 52)
		owned_directory(c'/tmp/overlay-volume/upper', 53)
		owned_directory(c'/tmp/overlay-volume/work', 54)
		owned_directory(c'/tmp/overlay-state/disklower', 55)
		owned_directory(c'/tmp/overlay-state/diskmerged', 56)
		write_file(c'/tmp/overlay-state/disklower/current', c'AAAAAAAA', 57)
		write_file(c'/tmp/overlay-state/disklower/move', c'AAAAAAAA', 58)
		write_file(c'/tmp/overlay-state/disklower/deleted', c'AAAAAAAA', 96)
		owned_directory(c'/tmp/overlay-state/disklower/empty', 97)
		check(C.chown(c'/tmp/overlay-state/disklower/current', 1000, 1000) == 0
			&& C.chown(c'/tmp/overlay-state/disklower/move', 1000, 1000) == 0
			&& C.chown(c'/tmp/overlay-state/disklower/deleted', 1000, 1000) == 0, 59)
		mut target := [512]char{}
		long_path(&target[0], c'/tmp/overlay-state/disklower')
		write_file(&target[0], c'AAAAAAAA', 60)
		check(C.chown(&target[0], 1000, 1000) == 0, 61)
		if opaque { prepare_opaque() }
		if full { prepare_opaque_full() }
		reject_work()
		check(C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/disklower,upperdir=/tmp/overlay-volume/upper,workdir=/tmp/overlay-volume/work') == 0, 62)
	}
}

fn reject_work() {
	unsafe {
		options := &char(c'lowerdir=/tmp/overlay-state/disklower,upperdir=/tmp/overlay-volume/upper,workdir=/tmp/overlay-volume/work')
		write_file(c'/tmp/overlay-volume/work/work', c'AAAAAAAA', 108)
		check(C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0, options) == -1
			&& *C.__errno_location() == C.EINVAL && contents(c'/tmp/overlay-volume/work/work', c'AAAAAAAA'), 109)
		check(C.unlink(c'/tmp/overlay-volume/work/work') == 0
			&& C.symlink(c'../upper', c'/tmp/overlay-volume/work/work') == 0, 110)
		check(C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0, options) == -1
			&& *C.__errno_location() == C.EINVAL, 111)
		check(C.unlink(c'/tmp/overlay-volume/work/work') == 0
			&& C.mkdir(c'/tmp/overlay-volume/work/work', 0o2777) == 0, 112)
		check(C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0, options) == -1
			&& *C.__errno_location() == C.EACCES, 113)
		check(C.chmod(c'/tmp/overlay-volume/work/work', 0o2000) == 0, 114)
		owned_directory(c'/tmp/overlay-volume/removed-work', 130)
		removed := C.open(c'/tmp/overlay-volume/removed-work', C.O_RDONLY | C.O_DIRECTORY)
		check(removed >= 0 && C.rmdir(c'/tmp/overlay-volume/removed-work') == 0, 131)
		mut removed_options := [512]char{}
		check(C.snprintf(&removed_options[0], 512,
			c'lowerdir=/tmp/overlay-state/disklower,upperdir=/tmp/overlay-volume/upper,workdir=/proc/self/fd/%d', removed) > 0, 132)
		check(C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0, &removed_options[0]) == -1
			&& *C.__errno_location() == C.ENOENT && C.close(removed) == 0, 133)
		C.puts(c'OVERLAY PRIVATE WORK: PASS')
		C.fflush(nil)
	}
}

fn backend_failure() {
	unsafe {
		write_file(c'/tmp/overlay-state/diskmerged/failure-source', c'BBBBBBBB', 63)
		mut target := [512]char{}
		long_path(&target[0], c'/tmp/overlay-state/diskmerged')
		result := C.rename(c'/tmp/overlay-state/diskmerged/failure-source', &target[0])
		code := *C.__errno_location()
		source_ok := contents(c'/tmp/overlay-state/diskmerged/failure-source', c'BBBBBBBB')
		target_ok := contents(&target[0], c'AAAAAAAA')
		C.printf(c'OVERLAY BACKEND FAILURE: result=%d errno=%d source_ok=%d target_ok=%d uid=%u\n',
			result, code, int(source_ok), int(target_ok), C.getuid())
		C.fflush(nil)
		check(result == -1 && code == C.ENAMETOOLONG && source_ok && target_ok, 64)
		// The lower-source path stages a real source whiteout. A rejected
		// backing rename must discard that staging inode and keep both names.
		lower_result := C.rename(c'/tmp/overlay-state/diskmerged/move', &target[0])
		lower_code := *C.__errno_location()
		lower_source_ok := contents(c'/tmp/overlay-state/diskmerged/move', c'AAAAAAAA')
		lower_target_ok := contents(&target[0], c'AAAAAAAA')
		C.printf(c'OVERLAY LOWER BACKEND FAILURE: result=%d errno=%d source_ok=%d target_ok=%d\n',
			lower_result, lower_code, int(lower_source_ok), int(lower_target_ok))
		C.fflush(nil)
		check(lower_result == -1 && lower_code == C.ENAMETOOLONG
			&& lower_source_ok && lower_target_ok, 120)
		long_path(&target[0], c'/tmp/overlay-state/disklower')
		check(contents(&target[0], c'AAAAAAAA'), 65)
		C.puts(c'OVERLAY BACKEND FAILURE: PASS')
	}
}

fn disk_replace() {
	unsafe {
		// Copy up the original inode, then hold it across upper replacement.
		write_file(c'/tmp/overlay-state/diskmerged/current', c'AAAAAAAA', 66)
		held := C.open(c'/tmp/overlay-state/diskmerged/current', C.O_RDONLY)
		check(held >= 0, 67)
		write_file(c'/tmp/overlay-state/diskmerged/source', c'BBBBBBBB', 68)
		check(C.rename(c'/tmp/overlay-state/diskmerged/source', c'/tmp/overlay-state/diskmerged/current') == 0, 69)
		check(C.usleep(6500000) == 0, 70)
		mut data := [8]char{}
		mut st := C.stat{}
		check(C.read(held, &data[0], 8) == 8 && C.memcmp(&data[0], c'AAAAAAAA', 8) == 0
			&& C.fstat(held, &st) == 0 && st.st_nlink == 0 && st.st_uid == 1000
			&& st.st_mode & 0o777 == 0o600 && C.close(held) == 0, 71)
		check(contents(c'/tmp/overlay-state/diskmerged/current', c'BBBBBBBB')
			&& contents(c'/tmp/overlay-volume/upper/current', c'BBBBBBBB')
			&& contents(c'/tmp/overlay-state/disklower/current', c'AAAAAAAA'), 72)
		// A lower source must stay hidden at its old path after copy-up/rename.
		check(C.rename(c'/tmp/overlay-state/diskmerged/move', c'/tmp/overlay-state/diskmerged/moved') == 0
			&& contents(c'/tmp/overlay-state/diskmerged/moved', c'AAAAAAAA')
			&& contents(c'/tmp/overlay-state/disklower/move', c'AAAAAAAA'), 73)
		check(C.open(c'/tmp/overlay-state/diskmerged/move', C.O_RDONLY) == -1
			&& *C.__errno_location() == C.ENOENT, 74)
		// Replacing a destination hidden by an in-memory whiteout must also
		// commit a real ext2 directory entry for the new file.
		check(C.unlink(c'/tmp/overlay-state/diskmerged/current') == 0, 75)
		check(C.open(c'/tmp/overlay-state/diskmerged/current', C.O_RDONLY) == -1
			&& *C.__errno_location() == C.ENOENT, 76)
		write_file(c'/tmp/overlay-state/diskmerged/source', c'BBBBBBBB', 77)
		check(C.rename(c'/tmp/overlay-state/diskmerged/source', c'/tmp/overlay-state/diskmerged/current') == 0
			&& contents(c'/tmp/overlay-state/diskmerged/current', c'BBBBBBBB')
			&& contents(c'/tmp/overlay-state/disklower/current', c'AAAAAAAA'), 78)
		check(C.mkdir(c'/tmp/overlay-state/diskmerged/source-dir', 0o700) == 0
			&& C.mkdir(c'/tmp/overlay-state/diskmerged/target-dir', 0o700) == 0, 89)
		parent := C.open(c'/tmp/overlay-volume/upper', C.O_RDONLY | C.O_DIRECTORY)
		check(parent >= 0 && C.fstat(parent, &st) == 0, 90)
		links_before := st.st_nlink
		check(C.rename(c'/tmp/overlay-state/diskmerged/source-dir', c'/tmp/overlay-state/diskmerged/target-dir') == 0
			&& C.fstat(parent, &st) == 0 && st.st_nlink + 1 == links_before
			&& C.close(parent) == 0, 91)
		check(C.open(c'/tmp/overlay-state/diskmerged/source-dir', C.O_RDONLY | C.O_DIRECTORY) == -1
			&& *C.__errno_location() == C.ENOENT, 92)
		C.printf(c'OVERLAY DIRECTORY: parent_links_before=%lu after=%lu\n', links_before, u64(st.st_nlink))
		check(C.mkdir(c'/tmp/overlay-state/diskmerged/left', 0o700) == 0
			&& C.mkdir(c'/tmp/overlay-state/diskmerged/right', 0o700) == 0
			&& C.mkdir(c'/tmp/overlay-state/diskmerged/left/incoming', 0o700) == 0
			&& C.mkdir(c'/tmp/overlay-state/diskmerged/right/destination', 0o700) == 0, 93)
		left := C.open(c'/tmp/overlay-volume/upper/left', C.O_RDONLY | C.O_DIRECTORY)
		right := C.open(c'/tmp/overlay-volume/upper/right', C.O_RDONLY | C.O_DIRECTORY)
		mut right_stat := C.stat{}
		check(left >= 0 && right >= 0 && C.fstat(left, &st) == 0
			&& C.fstat(right, &right_stat) == 0, 94)
		left_before := st.st_nlink
		right_before := right_stat.st_nlink
		check(C.rename(c'/tmp/overlay-state/diskmerged/left/incoming',
			c'/tmp/overlay-state/diskmerged/right/destination') == 0
			&& C.fstat(left, &st) == 0 && st.st_nlink + 1 == left_before
			&& C.fstat(right, &right_stat) == 0 && right_stat.st_nlink == right_before
			&& C.close(left) == 0 && C.close(right) == 0, 95)
		C.printf(c'OVERLAY CROSS DIRECTORY: left=%lu->%lu right=%lu->%lu\n', left_before,
			u64(st.st_nlink), right_before, u64(right_stat.st_nlink))
		check(C.unlink(c'/tmp/overlay-state/diskmerged/deleted') == 0
			&& C.rmdir(c'/tmp/overlay-state/diskmerged/empty') == 0, 98)
		C.puts(c'OVERLAY DISK: PASS')
		C.fflush(nil)
	}
}

fn persistence(stress bool) {
	unsafe {
		C.sync()
		check(C.umount(c'/tmp/overlay-state/diskmerged') == 0 && C.umount(c'/tmp/overlay-volume') == 0, 79)
		check(C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', 0, nil) == 0, 80)
		check(contents(c'/tmp/overlay-volume/upper/current', c'BBBBBBBB')
			&& contents(c'/tmp/overlay-volume/upper/moved', c'AAAAAAAA'), 81)
		fd := C.open(c'/tmp/overlay-volume/upper/current', C.O_RDONLY)
		mut st := C.stat{}
		check(fd >= 0 && C.fstat(fd, &st) == 0 && st.st_uid == 1000
			&& st.st_mode & 0o777 == 0o600 && C.close(fd) == 0, 82)
		check(C.open(c'/tmp/overlay-volume/upper/source', C.O_RDONLY) == -1
			&& *C.__errno_location() == C.ENOENT, 83)
		C.puts(c'OVERLAY PERSISTENCE: PASS')
		C.fflush(nil)
		check(C.mount(c'overlay', c'/tmp/overlay-state/diskmerged', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/disklower,upperdir=/tmp/overlay-volume/upper,workdir=/tmp/overlay-volume/work') == 0, 99)
		for marker in [&char(c'/tmp/overlay-volume/upper/move'),
			&char(c'/tmp/overlay-volume/upper/deleted'), &char(c'/tmp/overlay-volume/upper/empty')]! {
			check(C.lstat(marker, &st) == 0 && st.st_mode & C.S_IFMT == C.S_IFCHR
				&& st.st_rdev == 0 && st.st_nlink == 1 && st.st_uid == 1000 && st.st_gid == 1000, 115)
		}
		if stress {
			owned_directory(c'/tmp/overlay-state/othermerged', 125)
			check(C.mount(c'overlay', c'/tmp/overlay-state/othermerged', c'overlay', 0,
				c'lowerdir=/tmp/overlay-state/disklower,upperdir=/tmp/overlay-volume/upper,workdir=/tmp/overlay-volume/work') == 0, 126)
		}
		worker := C.fork()
		check(worker >= 0, 100)
		if worker == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 101)
			for path in [&char(c'/tmp/overlay-state/diskmerged/move'),
				&char(c'/tmp/overlay-state/diskmerged/deleted'),
				&char(c'/tmp/overlay-state/diskmerged/empty')]! {
				fd_hidden := C.open(path, C.O_RDONLY)
				code := *C.__errno_location()
				C.printf(c'OVERLAY WHITEOUT REMOUNT: path=%s fd=%d errno=%d\n', path, fd_hidden, code)
				C.fflush(nil)
				check(fd_hidden == -1 && code == C.ENOENT, 102)
			}
			write_file(c'/tmp/overlay-state/diskmerged/deleted', c'BBBBBBBB', 103)
			check(C.symlink(c'current', c'/tmp/overlay-state/diskmerged/move') == 0
				&& contents(c'/tmp/overlay-state/diskmerged/move', c'BBBBBBBB')
				&& C.mkdir(c'/tmp/overlay-state/diskmerged/empty', 0o700) == 0, 104)
			check(C.lstat(c'/tmp/overlay-state/diskmerged/empty', &st) == 0
				&& st.st_mode & 0o7777 == 0o700 && st.st_gid == 1000, 116)
			check(C.unlink(c'/tmp/overlay-state/diskmerged/deleted') == 0
				&& C.link(c'/tmp/overlay-state/diskmerged/current', c'/tmp/overlay-state/diskmerged/deleted') == 0
				&& contents(c'/tmp/overlay-state/diskmerged/deleted', c'BBBBBBBB'), 105)
			if stress {
				check(contents(c'/tmp/overlay-state/othermerged/deleted', c'BBBBBBBB'), 127)
				check(C.rmdir(c'/tmp/overlay-volume/work/work') == 0
					&& C.rmdir(c'/tmp/overlay-volume/work') == 0 && C.usleep(6500000) == 0, 117)
				check(C.unlink(c'/tmp/overlay-state/diskmerged/deleted') == -1
					&& *C.__errno_location() == C.ENOENT
					&& contents(c'/tmp/overlay-state/diskmerged/deleted', c'BBBBBBBB'), 118)
				check(C.unlink(c'/tmp/overlay-state/othermerged/deleted') == -1
					&& *C.__errno_location() == C.ENOENT
					&& contents(c'/tmp/overlay-state/othermerged/deleted', c'BBBBBBBB'), 128)
				C.puts(c'OVERLAY REMOVED WORK: PASS')
				C.fflush(nil)
			}
			C._exit(0)
		}
		mut worker_status := 0
		check(C.waitpid(worker, &worker_status, 0) == worker && C.WIFEXITED(worker_status) != 0
			&& C.WEXITSTATUS(worker_status) == 0, 106)
		check(C.usleep(6500000) == 0, 107)
		C.sync()
		if stress { check(C.umount(c'/tmp/overlay-state/othermerged') == 0, 129) }
		check(C.umount(c'/tmp/overlay-state/diskmerged') == 0
			&& C.umount(c'/tmp/overlay-volume') == 0, 84)
		check(C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', 0, nil) == 0
			&& contents(c'/tmp/overlay-volume/upper/deleted', c'BBBBBBBB')
			&& contents(c'/tmp/overlay-volume/upper/move', c'BBBBBBBB'), 121)
		mut linked := C.stat{}
		check(C.lstat(c'/tmp/overlay-volume/upper/current', &st) == 0
			&& C.lstat(c'/tmp/overlay-volume/upper/deleted', &linked) == 0
			&& st.st_ino == linked.st_ino && st.st_nlink == 2 && linked.st_nlink == 2, 122)
		check(C.lstat(c'/tmp/overlay-volume/upper/move', &st) == 0
			&& st.st_mode & C.S_IFMT == C.S_IFLNK && st.st_uid == 1000 && st.st_gid == 1000, 123)
		check(C.lstat(c'/tmp/overlay-volume/upper/empty', &st) == 0
			&& st.st_mode & C.S_IFMT == C.S_IFDIR && st.st_mode & 0o7777 == 0o700
			&& st.st_uid == 1000 && st.st_gid == 1000 && C.umount(c'/tmp/overlay-volume') == 0, 124)
		C.puts(c'OVERLAY RECREATION PERSISTENCE: PASS')
		C.puts(c'OVERLAY WHITEOUT: PASS')
		C.fflush(nil)
	}
}

fn sample(phase int) {
	unsafe {
		mut text := [16384]char{}
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		check(fd >= 0, 37)
		count := C.read(fd, &text[0], text.len - 1)
		check(count > 0 && C.close(fd) == 0, 38)
		C.printf(c'OVERLAY SLAB: phase=%d\n%s', phase, &text[0])
		C.fflush(nil)
	}
}

fn check(ok bool, site int) {
	if !ok {
		unsafe { C.printf(c'FAIL: overlay replacement site=%d errno=%d\n', site, *C.__errno_location()) }
		C.fflush(unsafe { nil })
		C._exit(1)
	}
}

fn clock() u64 {
	mut now := C.timespec{}
	check(C.clock_gettime(C.CLOCK_MONOTONIC, unsafe { &now }) == 0, 1)
	return u64(now.tv_sec) * 1000000000 + u64(now.tv_nsec)
}

fn publish(value &char) {
	fd := C.open(c'/tmp/overlay-state/merged/new', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	if fd < 0 {
		unsafe {
			errno_value := C.__errno_location()
			code := *errno_value
			mut text := [4096]char{}
			budget := C.open(c'/proc/kernel-resources', C.O_RDONLY)
			if budget >= 0 {
				C.read(budget, &text[0], text.len - 1)
				C.close(budget)
			}
			C.printf(c'OVERLAY OPEN FAILURE: errno=%d\n%s', code, &text[0])
			*errno_value = code
		}
	}
	check(fd >= 0, 2)
	check(C.write(fd, value, 8) == 8, 40)
	check(C.fsync(fd) == 0 && C.close(fd) == 0, 41)
	check(C.rename(c'/tmp/overlay-state/merged/new', c'/tmp/overlay-state/merged/current') == 0, 3)
}

fn listing() bool {
	unsafe {
		dir := C.opendir(c'/tmp/overlay-state/merged')
		check(dir != nil, 19)
		errno_value := C.__errno_location()
		mut current := 0
		mut entries := 0
		for {
			*errno_value = 0
			entry := C.readdir(dir)
			if entry == nil {
				check(*C.__errno_location() == 0, 20)
				break
			}
			entries++
			check(entries < 32, 21)
			if C.strcmp(&entry.d_name[0], c'current') == 0 { current++ }
		}
		check(C.closedir(dir) == 0, 22)
		return current == 1
	}
}

fn exercise(crowded bool) {
	unsafe {
		if crowded {
			// Dot entries, current and nine fillers leave the initial directory
			// map at its growth threshold when the writer creates its source.
			for index in 0 .. 9 {
				mut name := [128]char{}
				check(C.snprintf(&name[0], 128, c'/tmp/overlay-state/merged/filler-%d', index) > 0, 17)
				fd := C.open(&name[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
				check(fd >= 0 && C.close(fd) == 0, 18)
			}
		}
		publish(c'AAAAAAAA')
		held := C.open(c'/tmp/overlay-state/merged/current', C.O_RDONLY)
		check(held >= 0, 7)
		writer := C.fork()
		check(writer > -1, 8)
		if writer == 0 {
			check(C.close(held) == 0, 9)
			C.usleep(10000)
			for iteration in 0 .. 1000 {
				publish(if iteration % 2 == 0 { c'BBBBBBBB' } else { c'AAAAAAAA' })
			}
			C._exit(0)
		}
		deadline := clock() + 30000000000
		mut reads := 0
		mut missing := 0
		mut open_errors := 0
		mut read_errors := 0
		mut listing_errors := 0
		mut first_open_error := 0
		mut status := 0
		for {
			check(clock() < deadline && reads < 2000000, 10)
			fd := C.open(c'/tmp/overlay-state/merged/current', C.O_RDONLY)
			if fd < 0 {
				code := *C.__errno_location()
				if first_open_error == 0 { first_open_error = code }
				if code == C.ENOENT { missing++ } else { open_errors++ }
			} else {
				mut data := [8]char{}
				count := C.read(fd, &data[0], 8)
				if count != 8 || (C.memcmp(&data[0], c'AAAAAAAA', 8) != 0 && C.memcmp(&data[0], c'BBBBBBBB', 8) != 0) {
					read_errors++
				}
				check(C.close(fd) == 0, 11)
			}
			reads++
			if reads % 32 == 0 {
				if !listing() { listing_errors++ }
				done := C.waitpid(writer, &status, C.WNOHANG)
				check(done >= 0, 12)
				if done == writer { break }
			}
		}
		check(C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0, 13)
		// The replaced inode must also survive the kernel's five-second
		// retirement grace period while this descriptor still owns it.
		check(C.usleep(6500000) == 0, 16)
		mut old := [8]char{}
		mut st := C.stat{}
		check(C.read(held, &old[0], 8) == 8 && C.memcmp(&old[0], c'AAAAAAAA', 8) == 0
			&& C.fstat(held, &st) == 0 && st.st_nlink == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o600
			&& C.close(held) == 0, 14)
		C.printf(c'OVERLAY REPLACE: crowded=%d uid=1000 replacements=1000 reads=%d missing=%d open_errors=%d read_errors=%d listing_errors=%d first_open_errno=%d\n',
			int(crowded), reads, missing, open_errors, read_errors, listing_errors, first_open_error)
		C.fflush(nil)
		sample(if crowded { 2 } else { 1 })
		check(missing == 0 && open_errors == 0 && read_errors == 0 && listing_errors == 0, 15)
	}
}

@[export: 'main']
pub fn run() int {
	unsafe {
		mut selected := [16]char{}
		fd := C.open(c'/overlay-case', C.O_RDONLY)
		if fd >= 0 {
			check(C.read(fd, &selected[0], selected.len - 1) > 0 && C.close(fd) == 0, 85)
		} else {
			selected[0] = char(`a`)
			selected[1] = char(`t`)
			selected[2] = char(`o`)
			selected[3] = char(`m`)
			selected[4] = char(`i`)
			selected[5] = char(`c`)
		}
		all := C.strcmp(&selected[0], c'all') == 0
		concurrent := all || C.strcmp(&selected[0], c'atomic') == 0
		retention := all || C.strcmp(&selected[0], c'retention') == 0
		failure := all || C.strcmp(&selected[0], c'failure') == 0
		disk := all || C.strcmp(&selected[0], c'disk') == 0
		opaque := all || C.strcmp(&selected[0], c'opaque') == 0
		full := C.strcmp(&selected[0], c'opaque-full') == 0
		sockets := C.strcmp(&selected[0], c'sockets') == 0
		access := C.strcmp(&selected[0], c'socket-access') == 0
		check(concurrent || retention || failure || disk || opaque || full || sockets || access, 86)
		owned_directory(c'/tmp/overlay-state', 30)
		if concurrent || retention { prepare() }
		if retention { prepare_retained_layers() }
		if failure || disk || opaque || full || sockets { prepare_disk(opaque, full) }
		if sockets { check(C.mkdir(c'/tmp/overlay-volume/protected', 0o700) == 0, 427) }
		if access { owned_directory(c'/tmp/overlay-state/reference', 474) }
		root_listener := if sockets || access { root_socket_listener() } else { -1 }
		worker := C.fork()
		check(worker >= 0, 87)
		if worker == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 5)
			check(C.getuid() == 1000 && C.geteuid() == 1000, 6)
			check(C.mount(c'tmpfs', c'/tmp/overlay-state', c'tmpfs', 0, nil) == -1
				&& *C.__errno_location() == C.EPERM, 39)
			// The portable reference uses a real device number. Linux permits
			// unprivileged 0/0 whiteouts; Vinix's separate refusal remains tested.
			denied_device := if access { u64(0x103) } else { u64(0) }
			check(C.mknod(c'/tmp/overlay-state/denied-device', u32(C.S_IFCHR | 0o600), denied_device) == -1
				&& *C.__errno_location() == C.EPERM, 119)
			if root_listener >= 0 { inherited_socket_owner(root_listener) }
			if concurrent {
				sample(0)
				exercise(false)
				exercise(true)
				C.puts(c'OVERLAY REPLACE: PASS')
			}
			if failure { backend_failure() }
			if retention { overlay_retention() }
			if disk { disk_replace() }
			if opaque { opaque_changes() }
			if full { opaque_full_prepare_worker() }
			if sockets { persistent_sockets() }
			if access {
				persistent_socket_cycle(c'/tmp/overlay-state/reference', c'/tmp/overlay-state/reference', false)
				C.puts(c'OVERLAY SOCKET REFERENCE: PASS')
			}
			C.fflush(nil)
			C._exit(0)
		}
		mut status := 0
		check(C.waitpid(worker, &status, 0) == worker && C.WIFEXITED(status) != 0
			&& C.WEXITSTATUS(status) == 0, 88)
		if root_listener >= 0 {
			check(C.unlink(c'/tmp/overlay-state/root-listener') == 0 && C.close(root_listener) == 0, 535)
		}
		if opaque { opaque_persistence() }
		if full { opaque_full() }
		if sockets { persistent_sockets_remount() }
		if disk {
			persistence(all)
		} else if opaque {
			C.sync()
			check(C.umount(c'/tmp/overlay-state/diskmerged') == 0 && C.umount(c'/tmp/overlay-volume') == 0, 171)
		}
		C.puts(c'OVERLAY GUEST: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
