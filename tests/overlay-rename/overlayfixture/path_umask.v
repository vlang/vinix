// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

fn socket_creation_mode(path &char, mask u32, inherited bool, kind int) {
	unsafe {
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(path, address)
		server := C.socket(C.AF_UNIX, kind, 0)
		check(server >= 0, 600)
		previous := C.umask(mask)
		bound := C.bind(server, voidptr(address), u32(sizeof(C.sockaddr_un)))
		C.umask(previous)
		check(bound == 0, 601)
		wanted := (u32(0o777) & ~mask) & if inherited { u32(0o622) } else { u32(0o777) }
		mut st := C.stat{}
		check(C.lstat(path, &st) == 0, 602)
		if st.st_mode & 0o777 != wanted {
			C.printf(c'OVERLAY SOCKET UMASK: site=603 actual=%o expected=%o mask=%o acl=%d kind=%d\n',
				st.st_mode & 0o777, wanted, mask, int(inherited), kind)
			C.fflush(nil)
		}
		check(st.st_mode & C.S_IFMT == C.S_IFSOCK && st.st_mode & 0o777 == wanted
			&& st.st_uid == 1000 && st.st_gid == 1000, 603)
		metadata := C.open(path, C.O_PATH)
		check(metadata >= 0 && C.fstat(metadata, &st) == 0 && st.st_mode & 0o777 == wanted
			&& C.close(metadata) == 0, 604)
		mut acl := [44]u8{}
		if inherited {
			check(C.getxattr(path, c'system.posix_acl_access', &acl[0], 44) == 44
				&& acl[6] == u8(wanted >> 6) && acl[14] == 2 && acl[22] == 0
				&& acl[30] == u8((wanted >> 3) & 7) && acl[38] == u8(wanted & 7), 605)
		} else {
			xattr_refusal(C.getxattr(path, c'system.posix_acl_access', &acl[0], 44), C.ENODATA, 606)
		}
		if kind != C.SOCK_DGRAM { check(C.listen(server, 1) == 0, 607) }
		client := C.socket(C.AF_UNIX, kind, 0)
		check(client >= 0, 608)
		result := C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un)))
		if wanted & 0o200 == 0 {
			refused_socket_target(result, 609)
		} else {
			check(result == 0, 610)
			if kind == C.SOCK_DGRAM {
				check(C.write(client, c'U', 1) == 1, 620)
				receive_permission_byte(server, char(`U`), 611)
			} else {
				accepted := C.accept(server, nil, nil)
				mut byte := char(0)
				check(accepted >= 0 && C.write(client, c'U', 1) == 1 && C.read(accepted, &byte, 1) == 1
					&& byte == char(`U`) && C.close(accepted) == 0, 612)
			}
		}
		check(C.close(client) == 0 && C.unlink(path) == 0 && C.close(server) == 0, 613)
	}
}

fn socket_creation_modes(base &char) {
	unsafe {
		for inherited in [false, true]! {
			if inherited { socket_default_acl(base, 2, 2) }
			for kind in [C.SOCK_STREAM, C.SOCK_SEQPACKET, C.SOCK_DGRAM]! {
				for mask in [u32(0), u32(0o022), u32(0o077), u32(0o222), u32(0o777)]! {
					mut path := [108]char{}
					check(C.snprintf(&path[0], 108, c'%s/socket-umask', base) > 0, 614)
					socket_creation_mode(&path[0], mask, inherited, kind)
				}
			}
			if inherited { check(C.removexattr(base, c'system.posix_acl_default') == 0, 615) }
		}
		if C.strcmp(base, c'/tmp/overlay-volume/direct') == 0
			|| C.strcmp(base, c'/tmp/overlay-state/diskmerged') == 0 {
			// Leave one masked ACL inode to check after both backends remount.
			socket_default_acl(base, 2, 2)
			mut path := [108]char{}
			check(C.snprintf(&path[0], 108, c'%s/socket-umask-persist', base) > 0, 616)
			previous := C.umask(0o077)
			server := persistent_bind(&path[0])
			C.umask(previous)
			check(C.close(server) == 0 && C.removexattr(base, c'system.posix_acl_default') == 0, 617)
		}
		C.puts(c'OVERLAY SOCKET UMASK: PASS')
		C.fflush(nil)
	}
}

fn socket_creation_persistence() {
	unsafe {
		for path in [&char(c'/tmp/overlay-volume/direct/socket-umask-persist'),
			&char(c'/tmp/overlay-volume/upper/socket-umask-persist')]! {
			mut st := C.stat{}
			mut acl := [44]u8{}
			check(C.lstat(path, &st) == 0 && st.st_mode & C.S_IFMT == C.S_IFSOCK
				&& st.st_mode & 0o777 == 0o600 && st.st_uid == 1000 && st.st_gid == 1000
				&& st.st_nlink == 1, 618)
			check(C.getxattr(path, c'system.posix_acl_access', &acl[0], 44) == 44
				&& acl[6] == 6 && acl[14] == 2 && acl[30] == 0 && acl[38] == 0, 619)
		}
		C.puts(c'OVERLAY SOCKET UMASK PERSISTENCE: PASS')
	}
}
