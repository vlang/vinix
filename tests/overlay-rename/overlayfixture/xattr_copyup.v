// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>
fn C.ioctl(int, u64, voidptr) int

fn xattr_guard_path(base &char, index int, path &char) {
	check(C.snprintf(path, 512, c'%s/xattr-guard-%d', base, index) > 0, 630)
}

fn prepare_xattr_guards() {
	unsafe {
		// procfs supplies a lower regular file without xattr storage. Only the
		// private ext2 upper must provide storage for an authorized setter.
		check(C.mkdir(c'/tmp/overlay-volume/proc-upper', 0o700) == 0
			&& C.mkdir(c'/tmp/overlay-volume/proc-work', 0o700) == 0
			&& C.mkdir(c'/tmp/overlay-state/procmerged', 0o700) == 0, 642)
		check(C.mount(c'overlay', c'/tmp/overlay-state/procmerged', c'overlay', 0,
			c'lowerdir=/proc,upperdir=/tmp/overlay-volume/proc-upper,workdir=/tmp/overlay-volume/proc-work') == 0, 643)
		mut value := [8]char{}
		check(C.getxattr(c'/proc/version', c'user.guard', &value[0], 8) == -1
			&& *C.__errno_location() == C.ENOTSUP, 644)
		check(C.setxattr(c'/tmp/overlay-state/procmerged/version', c'user.guard', c'ROOT', 4, 0) == 0, 645)
		check(C.getxattr(c'/tmp/overlay-volume/proc-upper/version', c'user.guard', &value[0], 8) == 4
			&& C.memcmp(&value[0], c'ROOT', 4) == 0, 646)
		check(C.getxattr(c'/proc/version', c'user.guard', &value[0], 8) == -1
			&& *C.__errno_location() == C.ENOTSUP && C.umount(c'/tmp/overlay-state/procmerged') == 0, 647)
		C.puts(c'OVERLAY XATTR UNSUPPORTED LOWER: PASS')
		C.fflush(nil)
		for index in 0 .. 9 {
			mut path := [512]char{}
			xattr_guard_path(c'/tmp/overlay-state/disklower', index, &path[0])
			write_file(&path[0], c'COPYDATA', 631)
			check(C.setxattr(&path[0], c'user.keep', c'OLD', 3, 0) == 0, 632)
			check(C.chown(&path[0], if index == 1 { u32(0) } else { u32(1000) }, 1000) == 0
				&& C.chmod(&path[0], if index == 1 { u32(0o666) } else if index == 2 { u32(0o400) } else { u32(0o600) }) == 0, 633)
			if index == 0 {
				fd := C.open(&path[0], C.O_RDONLY)
				flags := &i32(C.alloca(sizeof(i32)))
				*flags = 0x10
				check(fd >= 0 && C.ioctl(fd, u64(0x40086602), flags) == 0 && C.close(fd) == 0, 634)
			}
		}
	}
}

fn xattr_guard_refused(result int, expected int) {
	unsafe {
		code := *C.__errno_location()
		if result != -1 || code != expected {
			C.printf(c'OVERLAY XATTR PREFLIGHT: result=%d errno=%d expected=%d\n', result, code, expected)
			C.fflush(nil)
		}
		check(result == -1 && code == expected, 635)
	}
}

fn xattr_guard_attempt(index int) {
	unsafe {
		mut path := [512]char{}
		mut upper := [512]char{}
		xattr_guard_path(c'/tmp/overlay-state/diskmerged', index, &path[0])
		xattr_guard_path(c'/tmp/overlay-volume/upper', index, &upper[0])
		match index {
			0 { xattr_guard_refused(C.setxattr(&path[0], c'user.guard', c'Q', 1, 0), C.EPERM)
				xattr_guard_refused(C.removexattr(&path[0], c'user.keep'), C.EPERM) }
			1 {
				mut acl := [28]u8{}
				acl[0] = 2
				for i, tag in [u8(1), 4, 32]! {
					offset := 4 + i * 8
					acl[offset] = tag
					acl[offset + 2] = 6
					for byte in 0 .. 4 { acl[offset + 4 + byte] = 255 }
				}
				xattr_guard_refused(C.setxattr(&path[0], c'system.posix_acl_access', &acl[0], 28, 0), C.EPERM)
				xattr_guard_refused(C.removexattr(&path[0], c'system.posix_acl_access'), C.EPERM)
			}
			2 { xattr_guard_refused(C.setxattr(&path[0], c'user.guard', c'Q', 1, 0), C.EACCES)
				xattr_guard_refused(C.removexattr(&path[0], c'user.keep'), C.EACCES) }
			3 { xattr_guard_refused(C.setxattr(&path[0], c'trusted.guard', c'Q', 1, 0), C.EPERM)
				xattr_guard_refused(C.removexattr(&path[0], c'trusted.guard'), C.EPERM) }
			4 {
				mut caps := [20]u8{}
				caps[3] = 2
				caps[4] = 1
				xattr_guard_refused(C.setxattr(&path[0], c'security.capability', &caps[0], 20, 0), C.EPERM)
				xattr_guard_refused(C.removexattr(&path[0], c'security.capability'), C.EPERM)
			}
			5 { mut acl := [4]u8{}
				xattr_guard_refused(C.setxattr(&path[0], c'system.posix_acl_access', &acl[0], 4, 0), C.ENOTSUP) }
			6 { mut acl := [5]u8{}
				acl[0] = 2
				xattr_guard_refused(C.setxattr(&path[0], c'system.posix_acl_access', &acl[0], 5, 0), C.EINVAL) }
			7 { xattr_guard_refused(C.setxattr(&path[0], c'user.guard', voidptr(1), 1, 0), C.EFAULT) }
			8 { xattr_guard_refused(C.setxattr(&path[0], c'user.guard', c'Q', 1, 4), C.EINVAL) }
			else {}
		}
		mut st := C.stat{}
		check(C.lstat(&upper[0], &st) == -1 && *C.__errno_location() == C.ENOENT, 636)
		mut value := [8]char{}
		check(C.getxattr(&path[0], c'user.keep', &value[0], 8) == 3
			&& C.memcmp(&value[0], c'OLD', 3) == 0 && contents(&path[0], c'COPYDATA'), 637)
	}
}

fn xattr_copyup_preflight() {
	unsafe {
		for phase in 50 .. 52 {
			for _ in 0 .. 200 { for index in 0 .. 9 { xattr_guard_attempt(index) } }
			check(C.usleep(25000000) == 0, 638)
			sample(phase)
		}
		// An authorized write must still copy up, preserving lower contents.
		check(C.setxattr(c'/tmp/overlay-state/diskmerged/xattr-guard-8', c'user.guard', c'YES', 3, 0) == 0, 639)
		mut value := [8]char{}
		check(C.getxattr(c'/tmp/overlay-volume/upper/xattr-guard-8', c'user.guard', &value[0], 8) == 3
			&& C.memcmp(&value[0], c'YES', 3) == 0, 640)
		check(C.getxattr(c'/tmp/overlay-state/disklower/xattr-guard-8', c'user.guard', &value[0], 8) == -1
			&& *C.__errno_location() == C.ENODATA, 641)
		C.puts(c'OVERLAY XATTR PREFLIGHT: PASS')
		C.fflush(nil)
	}
}
