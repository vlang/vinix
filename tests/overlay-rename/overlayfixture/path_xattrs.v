// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

fn C.lgetxattr(&char, &char, voidptr, usize) isize
fn C.lsetxattr(&char, &char, voidptr, usize, int) int
fn C.listxattr(&char, voidptr, usize) isize
fn C.llistxattr(&char, voidptr, usize) isize
fn C.lremovexattr(&char, &char) int
fn C.fgetxattr(int, &char, voidptr, usize) isize
fn C.fsetxattr(int, &char, voidptr, usize, int) int
fn C.flistxattr(int, voidptr, usize) isize
fn C.fremovexattr(int, &char) int

fn xattr_refusal(result isize, expected int, site int) {
	unsafe {
		code := *C.__errno_location()
		if result != -1 || code != expected {
			C.printf(c'OVERLAY SOCKET XATTR: site=%d result=%ld errno=%d expected=%d\n', site, result, code, expected)
			C.fflush(nil)
		}
		check(result == -1 && code == expected, site)
	}
}

fn socket_xattr_root(path &char, index int) {
	unsafe {
		mut acl := [44]u8{}
		result := C.getxattr(path, c'system.posix_acl_access', &acl[0], 44)
		if result != 44 {
			C.printf(c'OVERLAY SOCKET XATTR: site=559 result=%ld errno=%d\n', result, *C.__errno_location())
			C.fflush(nil)
		}
		check(result == 44 && acl[0] == 2 && acl[30] == if index == 2 { u8(0) } else { u8(2) }, 559)
		check(C.getxattr(path, c'system.posix_acl_access', nil, 0) == 44, 560)
		if index == 0 {
			// Exercise explicit live updates while preserving the denied fixture.
			acl[14] = 2
			check(C.setxattr(path, c'system.posix_acl_access', &acl[0], 44, 0) == 0, 561)
			acl[14] = 0
			check(C.lsetxattr(path, c'system.posix_acl_access', &acl[0], 44, 0) == 0, 562)
		}
	}
}

fn path_xattr_descriptions(fd int) {
	unsafe {
		mut output := [64]u8{init: 0x5a}
		xattr_refusal(C.fgetxattr(fd, c'system.posix_acl_access', &output[0], 64), C.EBADF, 563)
		xattr_refusal(C.fsetxattr(fd, c'system.posix_acl_access', nil, 0, 0), C.EBADF, 564)
		xattr_refusal(C.flistxattr(fd, voidptr(&output[0]), 64), C.EBADF, 565)
		xattr_refusal(C.fremovexattr(fd, c'system.posix_acl_access'), C.EBADF, 566)
		// Descriptor validation precedes user pointer inspection as well.
		xattr_refusal(C.fgetxattr(fd, &char(1), voidptr(1), 64), C.EBADF, 567)
		xattr_refusal(C.fsetxattr(fd, &char(1), voidptr(1), 44, 0), C.EBADF, 568)
		xattr_refusal(C.flistxattr(fd, voidptr(1), 64), C.EBADF, 569)
		xattr_refusal(C.fremovexattr(fd, &char(1)), C.EBADF, 570)
		for byte in output { check(byte == 0x5a, 571) }
	}
}

fn socket_xattr_account(path &char, index int) {
	unsafe {
		mut acl := [44]u8{}
		check(C.lgetxattr(path, c'system.posix_acl_access', &acl[0], 44) == 44, 572)
		if index != 3 {
			xattr_refusal(C.setxattr(path, c'system.posix_acl_access', &acl[0], 44, 0), C.EPERM, 573)
			xattr_refusal(C.removexattr(path, c'system.posix_acl_access'), C.EPERM, 574)
		}
		metadata := C.open(path, C.O_PATH)
		check(metadata >= 0, 575)
		path_xattr_descriptions(metadata)
		check(C.close(metadata) == 0, 576)
	}
}

fn socket_live_xattrs(path &char, listener int) {
	unsafe {
		mut original := [44]u8{}
		check(C.getxattr(path, c'system.posix_acl_access', &original[0], 44) == 44, 577)
		mut names := [64]u8{init: 0x5a}
		length := C.listxattr(path, voidptr(&names[0]), 64)
		check(length > 0 && length < 64 && C.strcmp(&char(&names[0]), c'system.posix_acl_access') == 0
			&& C.llistxattr(path, nil, 0) == length, 578)
		xattr_refusal(C.listxattr(path, voidptr(&names[0]), 1), C.ERANGE, 579)
		mut acl := original
		acl[6] = 0
		acl[14] = 2
		acl[30] = 2
		acl[38] = 0
		check(C.setxattr(path, c'system.posix_acl_access', &acl[0], 44, 0) == 0, 580)
		mut st := C.stat{}
		check(C.lstat(path, &st) == 0 && st.st_mode & 0o777 == 0o020, 581)
		client := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(path, address)
		check(client >= 0, 582)
		refused_socket_target(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))), 583)
		// The owner ACL entry wins over a named entry for that same UID.
		acl[6] = 2
		acl[30] = 0
		check(C.lsetxattr(path, c'system.posix_acl_access', &acl[0], 44, 0) == 0
			&& C.lstat(path, &st) == 0 && st.st_mode & 0o777 == 0o200, 584)
		check(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0, 585)
		accepted := C.accept(listener, nil, nil)
		mut byte := char(0)
		check(accepted >= 0 && C.write(client, c'X', 1) == 1 && C.read(accepted, &byte, 1) == 1
			&& byte == char(`X`), 586)
		// A socket description still cannot access its pathname inode's ACL.
		xattr_refusal(C.fgetxattr(listener, c'system.posix_acl_access', &acl[0], 44), C.ENOTSUP, 587)
		xattr_refusal(C.fsetxattr(listener, c'system.posix_acl_access', &acl[0], 44, 0), C.ENOTSUP, 588)
		xattr_refusal(C.fremovexattr(listener, c'system.posix_acl_access'), C.ENOTSUP, 589)
		check(C.lremovexattr(path, c'system.posix_acl_access') == 0, 590)
		xattr_refusal(C.getxattr(path, c'system.posix_acl_access', &acl[0], 44), C.ENODATA, 591)
		check(C.write(client, c'Y', 1) == 1 && C.read(accepted, &byte, 1) == 1
			&& byte == char(`Y`) && C.close(accepted) == 0 && C.close(client) == 0, 592)
		check(C.setxattr(path, c'system.posix_acl_access', &original[0], 44, 0) == 0, 593)
		for version in [u8(0), 1, 3, 255]! {
			acl = original
			acl[0] = version
			for wire_size in [usize(4), 5, 43, 44]! {
				xattr_refusal(C.setxattr(path, c'system.posix_acl_access', &acl[0], wire_size, 0), C.ENOTSUP, 621)
				xattr_refusal(C.lsetxattr(path, c'system.posix_acl_access', &acl[0], wire_size, 0), C.ENOTSUP, 622)
			}
			xattr_refusal(C.setxattr(path, c'system.posix_acl_access', &acl[0], 3, 0), C.EINVAL, 623)
		}
		acl = original
		acl[3] = 1
		xattr_refusal(C.setxattr(path, c'system.posix_acl_access', &acl[0], 44, 0), C.ENOTSUP, 624)
		acl = original
		xattr_refusal(C.setxattr(path, c'system.posix_acl_access', &acl[0], 5, 0), C.EINVAL, 625)
		acl = original
		// Keep the supported wire version and reject invalid permission bits.
		acl[6] = 8
		xattr_refusal(C.setxattr(path, c'system.posix_acl_access', &acl[0], 44, 0), C.EINVAL, 594)
		xattr_refusal(C.setxattr(path, c'system.posix_acl_default', &original[0], 44, 0), C.EACCES, 595)
		xattr_refusal(C.setxattr(path, c'user.socket', c'Q', 1, 0), C.EPERM, 596)
		xattr_refusal(C.setxattr(path, c'trusted.socket', c'Q', 1, 0), C.EPERM, 597)
		mut capabilities := [20]u8{}
		capabilities[3] = 2
		capabilities[4] = 1
		xattr_refusal(C.setxattr(path, c'security.capability', &capabilities[0], 20, 0), C.EPERM, 598)
		mut got := [44]u8{}
		check(C.getxattr(path, c'system.posix_acl_access', &got[0], 44) == 44
			&& C.memcmp(&got[0], &original[0], 44) == 0, 599)
	}
}
