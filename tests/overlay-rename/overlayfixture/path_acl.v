// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

fn C.setxattr(&char, &char, voidptr, usize, int) int
fn C.removexattr(&char, &char) int
fn C.getxattr(&char, &char, voidptr, usize) isize
fn C.utimensat(int, &char, &C.timespec, int) int

// Linux POSIX ACL xattr encoding, with one named UID and an explicit mask.
// Build the bytes in V so the probe needs neither libacl nor a shell helper.
fn socket_default_acl(path &char, named u8, other u8) {
	unsafe {
		mut acl := [44]u8{}
		acl[0] = 2
		for index, tag in [u8(1), u8(2), u8(4), u8(16), u8(32)]! {
			offset := 4 + index * 8
			acl[offset] = tag
			acl[offset + 2] = match index { 0 { u8(6) } 1 { named } 3 { u8(2) } 4 { other } else { u8(0) } }
			for byte in 0 .. 4 { acl[offset + 4 + byte] = 0xff }
		}
		acl[16] = 0xe8
		acl[17] = 3
		acl[18] = 0
		acl[19] = 0
		check(C.setxattr(path, c'system.posix_acl_default', &acl[0], 44, 0) == 0, 536)
	}
}

fn socket_acl_path(base &char, index int, path &char) {
	check(C.snprintf(path, 108, c'%s/socket-acl-%d', base, index) > 0, 537)
}

fn root_socket_acls(base &char) [6]i32 {
	unsafe {
		mut descriptors := [6]i32{}
		for index in 0 .. 6 {
			socket_default_acl(base, if index in [1, 2] { u8(2) } else { u8(0) },
				if index in [1, 2] { u8(0) } else { u8(2) })
			mut path := [108]char{}
			socket_acl_path(base, index, &path[0])
			kind := if index == 4 { C.SOCK_SEQPACKET } else if index == 5 { C.SOCK_DGRAM } else { C.SOCK_STREAM }
			descriptors[index] = i32(C.socket(C.AF_UNIX, kind, 0))
			mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
			socket_address(&path[0], address)
			check(descriptors[index] >= 0 && C.bind(descriptors[index], voidptr(address), u32(sizeof(C.sockaddr_un))) == 0, 538)
			// chmod must update the inherited ACL mask on the backing inode.
			check(C.chmod(&path[0], if index == 2 { u32(0o600) } else if index == 1 { u32(0o620) } else { u32(0o622) }) == 0, 539)
			socket_xattr_root(&path[0], index)
			if index == 0 && (C.strcmp(base, c'/tmp/overlay-volume') == 0
				|| C.strcmp(base, c'/tmp/overlay-state/diskmerged') == 0) {
				// Vinix's current ext2 owner encoding rejects IDs above 16 bits.
				// A failed staged change must leave the socket and ACL owner intact.
				mut st := C.stat{}
				check(C.chown(&path[0], 70000, u32(0xffffffff)) == -1
					&& *C.__errno_location() == C.EOVERFLOW
					&& C.lstat(&path[0], &st) == 0 && st.st_uid == 0 && st.st_gid == 0
					&& st.st_mode & 0o777 == 0o622, 553)
			}
			if index == 3 {
				check(C.chown(&path[0], 1000, 1000) == 0, 540)
				mut times := &C.timespec(C.alloca(sizeof(C.timespec) * 2))
				times[0] = C.timespec{ tv_sec: 1234567 }
				times[1] = C.timespec{ tv_sec: 2345678 }
				check(C.utimensat(C.AT_FDCWD, &path[0], times, 0) == 0, 554)
			}
			if kind != C.SOCK_DGRAM { check(C.listen(descriptors[index], 1) == 0, 541) }
		}
		check(C.removexattr(base, c'system.posix_acl_default') == 0, 542)
		return descriptors
	}
}

fn socket_acl_connections(base &char, descriptors [6]i32) {
	unsafe {
		for index in 0 .. 6 {
			mut path := [108]char{}
			socket_acl_path(base, index, &path[0])
			socket_xattr_account(&path[0], index)
			mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
			socket_address(&path[0], address)
			kind := if index == 4 { C.SOCK_SEQPACKET } else if index == 5 { C.SOCK_DGRAM } else { C.SOCK_STREAM }
			client := C.socket(C.AF_UNIX, kind, 0)
			check(client >= 0, 543)
			result := C.vinix_overlay_connect(client, address, u32(sizeof(C.sockaddr_un)))
			if index in [1, 3] {
				check(result == 0, 544)
				accepted := C.accept(descriptors[index], nil, nil)
				mut byte := char(0)
				check(accepted >= 0 && C.write(client, c'L', 1) == 1 && C.read(accepted, &byte, 1) == 1
					&& byte == char(`L`) && C.close(accepted) == 0, 545)
			} else {
				refused_socket_target(result, 546)
				if index == 5 {
					refused_socket_target(C.vinix_overlay_sendto(client, nil, 0, C.MSG_DONTWAIT,
						address, u32(sizeof(C.sockaddr_un))), 547)
					mut byte := char(0)
					check(C.recvfrom(descriptors[index], &byte, 1, C.MSG_DONTWAIT, nil, nil) == -1
						&& *C.__errno_location() == C.EAGAIN, 548)
				} else {
					flags := C.fcntl(descriptors[index], C.F_GETFL)
					check(flags >= 0 && C.fcntl(descriptors[index], C.F_SETFL, i32(flags | C.O_NONBLOCK)) == 0
						&& C.accept(descriptors[index], nil, nil) == -1 && *C.__errno_location() == C.EAGAIN, 549)
				}
			}
			check(C.close(client) == 0 && C.close(descriptors[index]) == 0, 550)
		}
		C.printf(c'OVERLAY SOCKET ACL: path=%s PASS\n', base)
		C.fflush(nil)
	}
}

fn close_socket_acls(base &char, descriptors [6]i32) {
	unsafe {
		for index in 0 .. 6 {
			mut path := [108]char{}
			socket_acl_path(base, index, &path[0])
			persistent := index == 3 && (C.strcmp(base, c'/tmp/overlay-volume') == 0
				|| C.strcmp(base, c'/tmp/overlay-state/diskmerged') == 0)
			if !persistent { check(C.unlink(&path[0]) == 0, 551) }
			check(C.close(descriptors[index]) == 0, 555)
		}
	}
}

fn socket_acl_persistence() {
	unsafe {
		for base in [&char(c'/tmp/overlay-volume'), &char(c'/tmp/overlay-volume/upper')]! {
			mut path := [108]char{}
			socket_acl_path(base, 3, &path[0])
			mut st := C.stat{}
			mut acl := [44]u8{}
			check(C.lstat(&path[0], &st) == 0 && st.st_uid == 1000 && st.st_gid == 1000
				&& st.st_nlink == 1 && st.st_mode & C.S_IFMT == C.S_IFSOCK
				&& st.st_mode & 0o777 == 0o622
				&& st.st_atim.tv_sec == 1234567 && st.st_mtim.tv_sec == 2345678, 556)
			check(C.getxattr(&path[0], c'system.posix_acl_access', &acl[0], 44) == 44
				&& acl[6] == 6 && acl[14] == 0 && acl[30] == 2 && acl[38] == 2, 557)
		}
		C.puts(c'OVERLAY SOCKET ACL PERSISTENCE: PASS')
	}
}
