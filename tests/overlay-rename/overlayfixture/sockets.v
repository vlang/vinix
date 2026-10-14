// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

fn C.listen(int, int) int
struct C.sockaddr {}
fn C.vinix_overlay_connect(int, voidptr, u32) int
fn C.accept(int, &C.sockaddr, &u32) int

fn socket_address(path &char, address &C.sockaddr_un) {
	unsafe {
		*address = C.sockaddr_un{}
		address.sun_family = u16(C.AF_UNIX)
		check(C.snprintf(&address.sun_path[0], 108, c'%s', path) > 0, 400)
	}
}

fn persistent_bind(path &char) int {
	unsafe {
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(path, address)
		check(fd >= 0 && C.bind(fd, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0, 401)
		return fd
	}
}

fn socket_absent(path &char, site int) {
	unsafe {
		mut st := C.stat{}
		check(C.lstat(path, &st) == -1 && *C.__errno_location() == C.ENOENT, site)
	}
}

fn persistent_socket_cycle(base &char, backing &char, hold bool) {
	unsafe {
		mut source := [108]char{}
		mut target := [108]char{}
		mut disk_source := [108]char{}
		mut disk_target := [108]char{}
		check(C.snprintf(&source[0], 108, c'%s/socket-source', base) > 0
			&& C.snprintf(&target[0], 108, c'%s/socket-target', base) > 0
			&& C.snprintf(&disk_source[0], 108, c'%s/socket-source', backing) > 0
			&& C.snprintf(&disk_target[0], 108, c'%s/socket-target', backing) > 0, 402)
		socket_default_acl(base, 0, 2)
		listener := persistent_bind(&source[0])
		replaced := persistent_bind(&target[0])
		check(C.removexattr(base, c'system.posix_acl_default') == 0, 552)
		old_path := C.open(&target[0], C.O_PATH)
		check(old_path >= 0 && C.listen(listener, 2) == 0, 403)
		check(C.rename(&source[0], &target[0]) == 0, 404)
		socket_absent(&disk_source[0], 405)
		mut st := C.stat{}
		check(C.fstat(old_path, &st) == 0 && st.st_nlink == 0, 406)
		socket_live_xattrs(&target[0], listener)
		check(C.chmod(&target[0], 0) == 0, 472)
		socket_private_opens(&target[0])
		metadata := C.open(&target[0], C.O_PATH)
		check(metadata >= 0 && C.fstat(metadata, &st) == 0 && st.st_nlink == 1, 433)
		client := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		socket_owned_description(client, 521)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(&target[0], address)
		socket_metadata_operations(metadata, address)
		path_xattr_descriptions(metadata)
		socket_private_connections(client, listener, address)
		delivered_metadata := pass_socket_metadata(metadata)
		check(C.close(delivered_metadata) == 0, 464)
		keepalive := &i32(C.alloca(sizeof(i32)))
		option_length := &u32(C.alloca(sizeof(u32)))
		*keepalive = -1
		*option_length = u32(sizeof(i32))
		check(C.getsockopt(listener, C.SOL_SOCKET, C.SO_KEEPALIVE, keepalive, option_length) == 0
			&& *keepalive == 0 && C.chmod(&target[0], 0o777) == 0, 473)
		socket_path_opens(&target[0])
		check(C.chmod(&target[0], 0o200) == 0 && client >= 0
			&& C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0
			&& C.chmod(&target[0], 0o777) == 0, 407)
		pending_metadata := C.open(&target[0], C.O_PATH)
		check(pending_metadata >= 0, 465)
		bad_socket_operation(C.accept(pending_metadata, nil, nil), 466)
		bad_socket_operation(C.accept4(pending_metadata, nil, nil, C.SOCK_CLOEXEC), 471)
		check(C.close(pending_metadata) == 0, 467)
		accepted := C.accept(listener, nil, nil)
		socket_owned_description(accepted, 524)
		socket_owned_peer(accepted)
		if hold {
			C.puts(c'OVERLAY SOCKET XATTR: PASS')
			C.puts(c'OVERLAY SOCKET PATH CLOSE: PASS')
			C.puts(c'OVERLAY SOCKET ACCESS: PASS')
			C.puts(c'OVERLAY SOCKET OPEN: PASS')
			C.puts(c'OVERLAY SOCKET PERMISSION: PASS')
			C.puts(c'OVERLAY SOCKET OWNER: PASS')
			C.fflush(nil)
		}
		path := C.open(&target[0], C.O_PATH)
		check(accepted >= 0 && path >= 0 && C.unlink(&target[0]) == 0, 408)
		socket_absent(&disk_target[0], 409)
		if hold {
			check(C.fstat(path, &st) == 0, 421)
			C.printf(c'OVERLAY SOCKET UNLINK: path=%s nlink=%u uid=%u mode=%o\n',
				&target[0], u32(st.st_nlink), st.st_uid, st.st_mode)
			C.fflush(nil)
			C.sync()
		}
		check(C.fstat(path, &st) == 0 && st.st_nlink == 0 && st.st_uid == 1000
			&& st.st_mode & C.S_IFMT == C.S_IFSOCK, 410)
		if hold { check(C.usleep(6500000) == 0, 411) }
		// Removing the name and replacing another endpoint preserve existing
		// connections and held metadata across the node retirement grace.
		mut byte := char(0)
		check(C.write(client, c'Z', 1) == 1 && C.read(accepted, &byte, 1) == 1
			&& byte == char(`Z`), 412)
		rebound := persistent_bind(&target[0])
		check(C.unlink(&target[0]) == 0 && C.close(rebound) == 0
			&& C.close(old_path) == 0 && C.close(path) == 0
			&& C.close(replaced) == 0 && C.close(listener) == 0
			&& C.close(accepted) == 0 && C.close(client) == 0, 413)
		socket_record_permissions(base)
		socket_datagram_permissions(base)
		socket_abstract_permissions()
	}
}

fn persistent_sockets() {
	unsafe {
		denied_socket_bind(c'/tmp/overlay-volume/protected/denied', C.EACCES)
		check(C.mkdir(c'/tmp/overlay-volume/direct', 0o700) == 0, 414)
		persistent_socket_cycle(c'/tmp/overlay-volume/direct', c'/tmp/overlay-volume/direct', true)
		persistent_socket_cycle(c'/tmp/overlay-state/diskmerged', c'/tmp/overlay-volume/upper', true)
		persistent_socket_links(c'/tmp/overlay-volume/direct')
		persistent_socket_links(c'/tmp/overlay-state/diskmerged')
		for phase in 40 .. 42 {
			for _ in 0 .. 32 {
				persistent_socket_cycle(c'/tmp/overlay-volume/direct', c'/tmp/overlay-volume/direct', false)
				persistent_socket_cycle(c'/tmp/overlay-state/diskmerged', c'/tmp/overlay-volume/upper', false)
			}
			check(C.usleep(25000000) == 0, 415)
			sample(phase)
		}
		C.puts(c'OVERLAY PERSISTENT SOCKETS: PASS')
		C.fflush(nil)
	}
}

fn denied_socket_bind(path &char, expected int) {
	unsafe {
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(path, address)
		check(fd >= 0 && C.bind(fd, voidptr(address), u32(sizeof(C.sockaddr_un))) == -1
			&& *C.__errno_location() == expected && C.close(fd) == 0, 428)
	}
}

fn persistent_socket_links(base &char) {
	unsafe {
		mut original := [108]char{}
		mut alias := [108]char{}
		mut directory := [108]char{}
		mut moved := [108]char{}
		check(C.snprintf(&original[0], 108, c'%s/socket-source', base) > 0
			&& C.snprintf(&alias[0], 108, c'%s/socket-target', base) > 0
			&& C.snprintf(&directory[0], 108, c'%s/socket-subdir', base) > 0
			&& C.snprintf(&moved[0], 108, c'%s/socket-subdir/moved', base) > 0, 422)
		socket := persistent_bind(&original[0])
		path := C.open(&original[0], C.O_PATH)
		check(path >= 0 && C.link(&original[0], &alias[0]) == 0
			&& C.mkdir(&directory[0], 0o700) == 0
			&& C.rename(&alias[0], &moved[0]) == 0, 423)
		mut a := C.stat{}
		mut b := C.stat{}
		check(C.fstat(path, &a) == 0 && C.lstat(&moved[0], &b) == 0
			&& a.st_ino == b.st_ino && a.st_nlink == 2 && b.st_nlink == 2, 424)
		check(C.unlink(&original[0]) == 0 && C.fstat(path, &a) == 0
			&& a.st_nlink == 1 && C.unlink(&moved[0]) == 0
			&& C.fstat(path, &a) == 0 && a.st_nlink == 0, 425)
		check(C.close(path) == 0 && C.close(socket) == 0
			&& C.rmdir(&directory[0]) == 0, 426)
		C.puts(c'OVERLAY SOCKET HARDLINK MOVE: PASS')
		C.fflush(nil)
	}
}

fn persistent_sockets_remount() {
	unsafe {
		C.sync()
		check(C.umount(c'/tmp/overlay-state/diskmerged') == 0
			&& C.umount(c'/tmp/overlay-volume') == 0, 416)
		check(C.mount(volume_device(), c'/tmp/overlay-volume', c'ext2', usize(C.MS_RDONLY), nil) == 0, 417)
		socket_acl_persistence()
		for base in [&char(c'/tmp/overlay-volume/direct'), &char(c'/tmp/overlay-volume/upper')]! {
			mut path := [108]char{}
			for name in [&char(c'socket-source'), &char(c'socket-target')]! {
				check(C.snprintf(&path[0], 108, c'%s/%s', base, name) > 0, 418)
				socket_absent(&path[0], 419)
			}
		}
		worker := C.fork()
		check(worker >= 0, 429)
		if worker == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 430)
			denied_socket_bind(c'/tmp/overlay-volume/direct/denied', C.EROFS)
			C._exit(0)
		}
		mut status := 0
		check(C.waitpid(worker, &status, 0) == worker && C.WIFEXITED(status) != 0
			&& C.WEXITSTATUS(status) == 0, 431)
		socket_absent(c'/tmp/overlay-volume/direct/denied', 432)
		C.sync()
		check(C.umount(c'/tmp/overlay-volume') == 0, 420)
		C.puts(c'OVERLAY SOCKET REMOUNT: PASS')
		C.fflush(nil)
	}
}
