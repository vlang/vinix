module socket

import resource
import file
import errno
import usercopy
import socket.public as sock_pub
import socket.unix as sock_unix
import proc

pub fn initialise() {}

fn socketpair_create(domain int, @type int, protocol int) ?(&resource.Resource, &resource.Resource) {
	match domain {
		sock_pub.af_unix {
			socket0, socket1 := sock_unix.create_pair(@type)?
			return &resource.Resource(*socket0), &resource.Resource(*socket1)
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.einval)
			return none
		}
	}
}

fn socket_create(domain int, @type int, protocol int) ?&resource.Resource {
	match domain {
		sock_pub.af_unix {
			ret := sock_unix.create(@type)?
			return ret
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.einval)
			return none
		}
	}
}

pub fn syscall_socketpair(_ voidptr, domain int, @type int, protocol int, ret &int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: socketpair(%d, 0x%x, %d, 0x%llx)\n', process.name.str,
		domain, @type, protocol, voidptr(ret))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut socket0, mut socket1 := socketpair_create(domain, @type, protocol) or {
		return errno.err, errno.get()
	}

	mut flags := int(0)
	if @type & sock_pub.sock_cloexec != 0 {
		flags |= resource.o_cloexec
	}
	if @type & sock_pub.sock_nonblock != 0 {
		flags |= resource.o_nonblock
	}

	unsafe {
		ret[0] = file.fdnum_create_from_resource(nil, mut socket0, flags, 0, false) or {
			return errno.err, errno.get()
		}

		ret[1] = file.fdnum_create_from_resource(nil, mut socket1, flags, 0, false) or {
			return errno.err, errno.get()
		}
	}
	return 0, 0
}

pub fn syscall_socket(_ voidptr, domain int, @type int, protocol int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: socket(%d, 0x%x, %d)\n', process.name.str, domain, @type,
		protocol)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut sock := socket_create(domain, @type, protocol) or {
		return errno.err, errno.get()
	}

	mut flags := int(0)
	if @type & sock_pub.sock_cloexec != 0 {
		flags |= resource.o_cloexec
	}
	if @type & sock_pub.sock_nonblock != 0 {
		flags |= resource.o_nonblock
	}

	ret := file.fdnum_create_from_resource(unsafe { nil }, mut sock, flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(ret), 0
}

pub fn syscall_accept(_ voidptr, fdnum int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: accept(%d)\n', process.name.str, fdnum)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource

	mut sock := &sock_pub.Socket(unsafe { nil })

	if mut res is sock_unix.UnixSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	mut connection_socket := sock.accept(fd.handle) or { return errno.err, errno.get() }

	ret := file.fdnum_create_from_resource(unsafe { nil }, mut connection_socket, 0, 0,
		false) or { return errno.err, errno.get() }

	return u64(ret), 0
}

pub fn syscall_bind(_ voidptr, fdnum int, _addr voidptr, addrlen u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: bind(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum, _addr,
		addrlen)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource

	mut sock := &sock_pub.Socket(unsafe { nil })

	if mut res is sock_unix.UnixSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	sock.bind(fd.handle, _addr, addrlen) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_listen(_ voidptr, fdnum int, backlog int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: listen(%d, %d)\n', process.name.str, fdnum, backlog)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource

	mut sock := &sock_pub.Socket(unsafe { nil })

	if mut res is sock_unix.UnixSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	sock.listen(fd.handle, backlog) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_recvmsg(_ voidptr, fdnum int, msg &sock_pub.MsgHdr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: recvmsg(%d, 0x%llx, 0x%x)\n', process.name.str, fdnum,
		voidptr(msg), flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource

	mut sock := &sock_pub.Socket(unsafe { nil })

	if mut res is sock_unix.UnixSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	ret := sock.recvmsg(fd.handle, msg, flags) or { return errno.err, errno.get() }

	return ret, 0
}

pub fn syscall_connect(_ voidptr, fdnum int, _addr voidptr, addrlen u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: connect(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum,
		_addr, addrlen)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource

	mut sock := &sock_pub.Socket(unsafe { nil })

	if mut res is sock_unix.UnixSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	sock.connect(fd.handle, _addr, addrlen) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_getpeername(_ voidptr, fdnum int, _addr voidptr, addrlen &u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: getpeername(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum,
		_addr, addrlen)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource

	mut sock := &sock_pub.Socket(unsafe { nil })

	if mut res is sock_unix.UnixSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	sock.peername(fd.handle, _addr, addrlen) or { return errno.err, errno.get() }

	return 0, 0
}

// Resolve a descriptor to the socket behind it, so that the socket syscalls
// reject an ordinary file rather than answering for it.
fn socket_from_fdnum(fdnum int) ?(&file.FD, &sock_pub.Socket) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum)?

	mut res := fd.handle.resource
	if mut res is sock_unix.UnixSocket {
		return fd, &sock_pub.Socket(res)
	}

	fd.unref()
	errno.set(errno.enotsock)
	return none
}

// getsockname(2). This used to answer for any descriptor at all, always with a
// hardcoded AF_UNIX address, whether or not the fd was a socket and whatever
// the socket was actually bound to.
pub fn syscall_getsockname(_ voidptr, fdnum int, _addr voidptr, addrlen &u32) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	if addrlen == unsafe { nil } {
		return errno.err, errno.efault
	}

	sock.sockname(fd.handle, _addr, addrlen) or { return errno.err, errno.get() }

	return 0, 0
}

// shutdown(2). This was a no-op that reported success, so a peer waiting on the
// other end of a shut-down connection never saw end of file.
pub fn syscall_shutdown(_ voidptr, fdnum int, how int) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	sock.shutdown(fd.handle, how) or { return errno.err, errno.get() }

	return 0, 0
}

// getsockopt(2). Only the integer-valued options are served; anything else is
// reported as unknown rather than answered with a fabricated zero.
pub fn syscall_getsockopt(_ voidptr, fdnum int, level int, optname int, optval u64, optlen u64) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	if optval == 0 || optlen == 0 {
		return errno.err, errno.efault
	}

	mut capacity := u32(0)
	if !usercopy.copy_from_user(voidptr(&capacity), optlen, sizeof(u32)) {
		return errno.err, errno.efault
	}
	if capacity < sizeof(int) {
		return errno.err, errno.einval
	}

	value := sock.getsockopt(fd.handle, level, optname) or { return errno.err, errno.get() }

	written := u32(sizeof(int))
	if !usercopy.copy_to_user(optval, voidptr(&value), sizeof(int)) {
		return errno.err, errno.efault
	}
	if !usercopy.copy_to_user(optlen, voidptr(&written), sizeof(u32)) {
		return errno.err, errno.efault
	}

	return 0, 0
}

// setsockopt(2).
pub fn syscall_setsockopt(_ voidptr, fdnum int, level int, optname int, optval u64, optlen u32) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	// SO_LINGER and the timeout options carry a struct; take the leading int,
	// which is all any of the options handled here look at.
	mut value := int(0)
	if optval != 0 && optlen >= u32(sizeof(int)) {
		if !usercopy.copy_from_user(voidptr(&value), optval, sizeof(int)) {
			return errno.err, errno.efault
		}
	} else if optval == 0 && optlen != 0 {
		return errno.err, errno.efault
	}

	sock.setsockopt(fd.handle, level, optname, value) or { return errno.err, errno.get() }

	return 0, 0
}
