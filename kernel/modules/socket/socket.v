// socket.v: Socket implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module socket

import resource
import file
import errno
import socket.public as sock_pub
import socket.unix as sock_unix

pub fn initialise() {}

fn socketpair_create(domain int, @type int, protocol int) ?(&resource.Resource, &resource.Resource) {
	match domain {
		sock_pub.af_unix {
			socket0, socket1 := sock_unix.create_pair(@type) ?
			return &resource.Resource(*socket0), &resource.Resource(*socket1)
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.einval)
			return error('')
		}
	}
}

fn socket_create(domain int, @type int, protocol int) ?&resource.Resource {
	match domain {
		sock_pub.af_unix {
			ret := sock_unix.create(@type) ?
			return ret
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.einval)
			return error('')
		}
	}
}

pub fn syscall_socketpair(_ voidptr, domain int, @type int, protocol int, ret &int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: socketpair(%d, 0x%x, %d, 0x%llx)\n', domain, @type,
		protocol, voidptr(ret))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut socket0, mut socket1 := socketpair_create(domain, @type, protocol) or {
		return -1, errno.get()
	}

	mut flags := int(0)
	if @type & sock_pub.sock_cloexec != 0 {
		flags |= resource.o_cloexec
	}
	if @type & sock_pub.sock_nonblock != 0 {
		flags |= resource.o_nonblock
	}

	unsafe {
		ret[0] = file.fdnum_create_from_resource(voidptr(0), mut socket0, flags, 0, false) or {
			return -1, errno.get()
		}

		ret[1] = file.fdnum_create_from_resource(voidptr(0), mut socket1, flags, 0, false) or {
			return -1, errno.get()
		}
	}
	return 0, 0
}

pub fn syscall_socket(_ voidptr, domain int, @type int, protocol int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: socket(%d, 0x%x, %d)\n', domain, @type, protocol)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut socket := socket_create(domain, @type, protocol) or { return -1, errno.get() }

	mut flags := int(0)
	if @type & sock_pub.sock_cloexec != 0 {
		flags |= resource.o_cloexec
	}
	if @type & sock_pub.sock_nonblock != 0 {
		flags |= resource.o_nonblock
	}

	ret := file.fdnum_create_from_resource(voidptr(0), mut socket, flags, 0, false) or {
		return -1, errno.get()
	}

	return u64(ret), 0
}

pub fn syscall_accept(_ voidptr, fdnum int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: accept(%d)\n', fdnum)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
	defer {
		fd.unref()
	}

	res := fd.handle.resource

	mut socket := &sock_pub.Socket(voidptr(0))

	if res is sock_unix.UnixSocket {
		socket = res
	} else {
		return -1, errno.einval
	}

	mut connection_socket := socket.accept(fd.handle) or {
		return -1, errno.get()
	}

	ret := file.fdnum_create_from_resource(voidptr(0), mut connection_socket, 0, 0, false) or {
		return -1, errno.get()
	}

	return u64(ret), 0
}

pub fn syscall_bind(_ voidptr, fdnum int, _addr voidptr, addrlen u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: bind(%d, 0x%llx, 0x%llx)\n', fdnum, _addr, addrlen)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
	defer {
		fd.unref()
	}

	res := fd.handle.resource

	mut socket := &sock_pub.Socket(voidptr(0))

	if res is sock_unix.UnixSocket {
		socket = res
	} else {
		return -1, errno.einval
	}

	socket.bind(fd.handle, _addr, addrlen) or { return -1, errno.get() }

	return 0, 0
}

pub fn syscall_listen(_ voidptr, fdnum int, backlog int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: listen(%d, %d)\n', fdnum, backlog)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
	defer {
		fd.unref()
	}

	res := fd.handle.resource

	mut socket := &sock_pub.Socket(voidptr(0))

	if res is sock_unix.UnixSocket {
		socket = res
	} else {
		return -1, errno.einval
	}

	socket.listen(fd.handle, backlog) or { return -1, errno.get() }

	return 0, 0
}

pub fn syscall_recvmsg(_ voidptr, fdnum int, msg &sock_pub.MsgHdr, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: recvmsg(%d, 0x%llx, 0x%x)\n', fdnum, voidptr(msg), flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
	defer {
		fd.unref()
	}

	res := fd.handle.resource

	mut socket := &sock_pub.Socket(voidptr(0))

	if res is sock_unix.UnixSocket {
		socket = res
	} else {
		return -1, errno.einval
	}

	ret := socket.recvmsg(fd.handle, msg, flags) or { return -1, errno.get() }

	return ret, 0
}

pub fn syscall_connect(_ voidptr, fdnum int, _addr voidptr, addrlen u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: connect(%d, 0x%llx, 0x%llx)\n', fdnum, _addr, addrlen)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
	defer {
		fd.unref()
	}

	res := fd.handle.resource

	mut socket := &sock_pub.Socket(voidptr(0))

	if res is sock_unix.UnixSocket {
		socket = res
	} else {
		return -1, errno.einval
	}

	socket.connect(fd.handle, _addr, addrlen) or { return -1, errno.get() }

	return 0, 0
}

pub fn syscall_getpeername(_ voidptr, fdnum int, _addr voidptr, addrlen &u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: getpeername(%d, 0x%llx, 0x%llx)\n', fdnum, _addr, addrlen)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
	defer {
		fd.unref()
	}

	res := fd.handle.resource

	mut socket := &sock_pub.Socket(voidptr(0))

	if res is sock_unix.UnixSocket {
		socket = res
	} else {
		return -1, errno.einval
	}

	socket.peername(fd.handle, _addr, addrlen) or { return -1, errno.get() }

	return 0, 0
}
