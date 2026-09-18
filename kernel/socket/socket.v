module socket

import resource
import file
import memory
import errno
import usercopy
import socket.public as sock_pub
import socket.unix as sock_unix
import socket.inet as sock_inet
import proc

const cmsg_header_size = u64(16)
const cmsg_align = u64(8)
const sockaddr_storage_size = u32(128)
const socket_user_io_max = u64(64 * 1024)
const socket_iov_max = u64(1024)
const socket_msg_control_max = u64(64 * 1024)
const socket_msg_payload_max = u64(1024 * 1024)

fn copy_msghdr_from_user(msg &sock_pub.MsgHdr) ?sock_pub.MsgHdr {
	if msg == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	mut copied := sock_pub.MsgHdr{}
	if !usercopy.copy_from_user(voidptr(&copied), u64(msg), sizeof(sock_pub.MsgHdr)) {
		errno.set(errno.efault)
		return none
	}
	if copied.msg_iovlen > socket_iov_max {
		errno.set(errno.emsgsize)
		return none
	}
	if copied.msg_iovlen != 0 && copied.msg_iov == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	if copied.msg_controllen != 0 && copied.msg_control == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	return copied
}

fn copy_iovecs_from_user(msg &sock_pub.MsgHdr) ?[]sock_pub.IoVec {
	mut iovs := []sock_pub.IoVec{len: int(msg.msg_iovlen)}
	if msg.msg_iovlen == 0 {
		return iovs
	}
	bytes := msg.msg_iovlen * sizeof(sock_pub.IoVec)
	if bytes / sizeof(sock_pub.IoVec) != msg.msg_iovlen
		|| !usercopy.copy_from_user(voidptr(&iovs[0]), u64(msg.msg_iov), bytes) {
		unsafe { iovs.free() }
		errno.set(errno.efault)
		return none
	}
	return iovs
}

fn bounded_socket_io(count u64) u64 {
	return if count > socket_user_io_max { socket_user_io_max } else { count }
}

fn copy_sockaddr_from_user(user_address voidptr, length u32, destination voidptr) ? {
	if user_address == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	if length == 0 || length > sockaddr_storage_size {
		errno.set(errno.einval)
		return none
	}
	if !usercopy.copy_from_user(destination, u64(user_address), u64(length)) {
		errno.set(errno.efault)
		return none
	}
}

fn socket_name_to_user(mut sock sock_pub.Socket, handle voidptr, user_address voidptr,
	user_length &u32, peer bool) ? {
	if user_length == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	mut capacity := u32(0)
	if !usercopy.copy_from_user(voidptr(&capacity), u64(user_length), sizeof(u32)) {
		errno.set(errno.efault)
		return none
	}
	mut storage := [128]u8{}
	mut kernel_length := if capacity < sockaddr_storage_size { capacity } else { sockaddr_storage_size }
	if peer {
		sock.peername(handle, if user_address == unsafe { nil } { unsafe { nil } } else { voidptr(&storage[0]) },
			&kernel_length)?
	} else {
		sock.sockname(handle, if user_address == unsafe { nil } { unsafe { nil } } else { voidptr(&storage[0]) },
			&kernel_length)?
	}
	if user_address != unsafe { nil } && capacity != 0 {
		mut to_copy := u64(kernel_length)
		if to_copy > u64(capacity) {
			to_copy = u64(capacity)
		}
		if to_copy > u64(sockaddr_storage_size) {
			to_copy = u64(sockaddr_storage_size)
		}
		if to_copy != 0 && !usercopy.copy_to_user(u64(user_address), voidptr(&storage[0]), to_copy) {
			errno.set(errno.efault)
			return none
		}
	}
	if !usercopy.copy_to_user(u64(user_length), voidptr(&kernel_length), sizeof(u32)) {
		errno.set(errno.efault)
		return none
	}
}


struct CMsgHdr {
	cmsg_len   u64
	cmsg_level i32
	cmsg_type  i32
}

fn release_passed_fds(mut fds []&file.FD) {
	for mut fd in fds {
		fd.unref()
		unsafe { free(voidptr(fd)) }
	}
	unsafe { fds.free() }
}

fn collect_passed_fds(msg &sock_pub.MsgHdr) ?[]&file.FD {
	mut result := []&file.FD{}
	mut offset := u64(0)
	for offset < msg.msg_controllen {
		remaining := msg.msg_controllen - offset
		if remaining < cmsg_header_size {
			release_passed_fds(mut result)
			errno.set(errno.einval)
			return none
		}
		header := unsafe { &CMsgHdr(voidptr(u64(msg.msg_control) + offset)) }
		if header.cmsg_len < cmsg_header_size || header.cmsg_len > remaining
			|| header.cmsg_level != sock_pub.sol_socket {
			release_passed_fds(mut result)
			errno.set(errno.einval)
			return none
		}

		// A sender may attach its own identity beside the descriptors. Vinix
		// hands the receiver the credentials captured when the connection was
		// established, which is the check Linux performs on this record for an
		// unprivileged sender, so the attached copy carries no new information.
		if header.cmsg_type == sock_pub.scm_credentials {
			if header.cmsg_len != cmsg_header_size + sizeof(sock_pub.UCred) {
				release_passed_fds(mut result)
				errno.set(errno.einval)
				return none
			}
			next_credentials := (header.cmsg_len + cmsg_align - 1) & ~(cmsg_align - 1)
			if next_credentials > remaining {
				break
			}
			offset += next_credentials
			continue
		}

		if header.cmsg_type != sock_pub.scm_rights
			|| (header.cmsg_len - cmsg_header_size) % sizeof(i32) != 0 {
			release_passed_fds(mut result)
			errno.set(errno.einval)
			return none
		}

		fd_count := (header.cmsg_len - cmsg_header_size) / sizeof(i32)
		for i := u64(0); i < fd_count; i++ {
			fdnum := unsafe { *(&i32(voidptr(u64(header) + cmsg_header_size + i * sizeof(i32)))) }
			mut source := file.fd_from_fdnum(unsafe { nil }, int(fdnum)) or {
				release_passed_fds(mut result)
				return none
			}
			// fd_from_fdnum() acquired the Handle reference now owned by this
			// queued descriptor. Do not unref the source on the success path.
			mut passed := &file.FD{
				handle: source.handle
				flags: 0
			}
			result << passed
		}

		next := (header.cmsg_len + cmsg_align - 1) & ~(cmsg_align - 1)
		if next > remaining {
			break
		}
		offset += next
	}
	return result
}

pub fn initialise() {
	sock_inet.initialise()
}

fn socketpair_create(domain int, @type int, _protocol int) ?(&resource.Resource, &resource.Resource) {
	match domain {
		sock_pub.af_unix {
			socket0, socket1 := sock_unix.create_pair(@type)?
			return &resource.Resource(socket0), &resource.Resource(socket1)
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
		sock_pub.af_inet {
			ret := sock_inet.create(@type, protocol)?
			return ret
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.einval)
			return none
		}
	}
}

pub fn syscall_socketpair(_ voidptr, domain int, @type int, protocol int, ret &i32) (u64, u64) {
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

	// A socket is always open for both directions. Saying so matters: without
	// an access mode the descriptor looks read-only, and write(2) — which is
	// how an X server answers its clients — is refused with EBADF.
	mut flags := int(resource.o_rdwr)
	if @type & sock_pub.sock_cloexec != 0 {
		flags |= resource.o_cloexec
	}
	if @type & sock_pub.sock_nonblock != 0 {
		flags |= resource.o_nonblock
	}

	unsafe {
		ret[0] = i32(file.fdnum_create_from_resource(nil, mut socket0, flags, 0, false) or {
			return errno.err, errno.get()
		})

		ret[1] = i32(file.fdnum_create_from_resource(nil, mut socket1, flags, 0, false) or {
			return errno.err, errno.get()
		})
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

	mut flags := int(resource.o_rdwr)
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
	} else if mut res is sock_inet.InetSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	mut connection_socket := sock.accept(fd.handle) or { return errno.err, errno.get() }

	ret := file.fdnum_create_from_resource(unsafe { nil }, mut connection_socket,
		resource.o_rdwr, 0, false) or { return errno.err, errno.get() }

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
	} else if mut res is sock_inet.InetSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	mut address_storage := [128]u8{}
	copy_sockaddr_from_user(_addr, addrlen, voidptr(&address_storage[0])) or {
		return errno.err, errno.get()
	}
	sock.bind(fd.handle, voidptr(&address_storage[0]), addrlen) or {
		return errno.err, errno.get()
	}

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
	} else if mut res is sock_inet.InetSocket {
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
	} else if mut res is sock_inet.InetSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	// MSG_DONTWAIT is a per-call override, not a permanent descriptor flag.
	old_flags := fd.handle.flags
	if flags & 0x40 != 0 {
		fd.handle.flags |= resource.o_nonblock
	}
	defer {
		fd.handle.flags = old_flags
	}
	mut remaining_flags := flags & ~0x40000040 // MSG_CMSG_CLOEXEC | MSG_DONTWAIT
	if mut res is sock_unix.UnixSocket {
		remaining_flags = flags & ~0x40 // Unix recvmsg consumes MSG_CMSG_CLOEXEC.
	}
	ret := sock.recvmsg(fd.handle, msg, remaining_flags) or { return errno.err, errno.get() }

	return ret, 0
}

// sendto(2), including connected UDP when no destination is supplied.  The
// old aarch64 compatibility wrapper reduced every call to write(2), losing the
// destination that DNS and DHCP clients need.
fn sendto_kernel(fdnum int, buf voidptr, len u64, flags int, dest_addr voidptr,
	addrlen u32) (u64, u64) {
	if flags & ~0x4040 != 0 { // MSG_DONTWAIT | MSG_NOSIGNAL
		return errno.err, errno.eopnotsupp
	}
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	mut res := fd.handle.resource
	if mut res is sock_inet.InetSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer { fd.handle.flags = old_flags }
		ret := res.sendto(fd.handle, buf, len, dest_addr, addrlen) or {
			return errno.err, errno.get()
		}
		return u64(ret), 0
	}
	if mut res is sock_unix.UnixSocket {
		if dest_addr != unsafe { nil } {
			return errno.err, errno.eopnotsupp
		}
		ret := fd.handle.write(buf, len) or { return errno.err, errno.get() }
		return u64(ret), 0
	}
	return errno.err, errno.enotsock
}

pub fn syscall_sendto(_ voidptr, fdnum int, buf voidptr, len u64, flags int, dest_addr voidptr, addrlen u32) (u64, u64) {
	chunk := bounded_socket_io(len)
	buffer := memory.malloc(if chunk == 0 { u64(1) } else { chunk })
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer { memory.free(buffer) }
	if chunk != 0 && !usercopy.copy_from_user(buffer, u64(buf), chunk) {
		return errno.err, errno.efault
	}

	mut address_storage := [128]u8{}
	mut kernel_address := voidptr(0)
	if dest_addr != unsafe { nil } {
		copy_sockaddr_from_user(dest_addr, addrlen, voidptr(&address_storage[0])) or {
			return errno.err, errno.get()
		}
		kernel_address = voidptr(&address_storage[0])
	}
	return sendto_kernel(fdnum, buffer, chunk, flags, kernel_address, addrlen)
}

pub fn syscall_recvfrom(_ voidptr, fdnum int, buf voidptr, len u64, flags int, src_addr voidptr, addrlen &u32) (u64, u64) {
	if flags & ~0x40 != 0 { // MSG_DONTWAIT
		return errno.err, errno.eopnotsupp
	}
	chunk := bounded_socket_io(len)
	if chunk != 0 && !usercopy.probe_writable(u64(buf), chunk) {
		return errno.err, errno.efault
	}
	buffer := memory.malloc(if chunk == 0 { u64(1) } else { chunk })
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer { memory.free(buffer) }

	mut source_storage := [128]u8{}
	mut source_capacity := u32(0)
	mut source_length := u32(0)
	if src_addr != unsafe { nil } {
		if addrlen == unsafe { nil }
			|| !usercopy.copy_from_user(voidptr(&source_capacity), u64(addrlen), sizeof(u32)) {
			return errno.err, errno.efault
		}
		source_length = if source_capacity < sockaddr_storage_size {
			source_capacity
		} else {
			sockaddr_storage_size
		}
		if source_length != 0
			&& !usercopy.probe_writable(u64(src_addr), u64(source_length)) {
			return errno.err, errno.efault
		}
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	mut res := fd.handle.resource
	mut ret := i64(0)
	mut has_source := false
	if mut res is sock_inet.InetSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer { fd.handle.flags = old_flags }
		ret = res.recvfrom(fd.handle, buffer, chunk,
			if src_addr == unsafe { nil } { unsafe { nil } } else { voidptr(&source_storage[0]) },
			if src_addr == unsafe { nil } { unsafe { nil } } else { &source_length }) or {
			return errno.err, errno.get()
		}
		has_source = src_addr != unsafe { nil }
	} else if mut res is sock_unix.UnixSocket {
		ret = fd.handle.read(buffer, chunk) or { return errno.err, errno.get() }
	} else {
		return errno.err, errno.enotsock
	}
	if ret < 0 || u64(ret) > chunk {
		return errno.err, errno.eio
	}
	if ret != 0 && !usercopy.copy_to_user(u64(buf), buffer, u64(ret)) {
		return errno.err, errno.efault
	}
	if has_source {
		mut to_copy := u64(source_length)
		if to_copy > u64(source_capacity) {
			to_copy = u64(source_capacity)
		}
		if to_copy > u64(sockaddr_storage_size) {
			to_copy = u64(sockaddr_storage_size)
		}
		if to_copy != 0
			&& !usercopy.copy_to_user(u64(src_addr), voidptr(&source_storage[0]), to_copy) {
			return errno.err, errno.efault
		}
		if !usercopy.copy_to_user(u64(addrlen), voidptr(&source_length), sizeof(u32)) {
			return errno.err, errno.efault
		}
	}
	return u64(ret), 0
}

pub fn syscall_sendmsg(_gpr_state voidptr, fdnum int, msg &sock_pub.MsgHdr, flags int) (u64, u64) {
	mut kernel_msg := copy_msghdr_from_user(msg) or { return errno.err, errno.get() }
	mut iovs := copy_iovecs_from_user(&kernel_msg) or { return errno.err, errno.get() }
	defer { unsafe { iovs.free() } }

	mut total := u64(0)
	for iov in iovs {
		if iov.iov_len > socket_msg_payload_max - total {
			return errno.err, errno.emsgsize
		}
		total += iov.iov_len
	}

	buffer := memory.malloc(if total == 0 { u64(1) } else { total })
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer { memory.free(buffer) }
	mut copied := u64(0)
	for iov in iovs {
		if iov.iov_len == 0 {
			continue
		}
		if iov.iov_base == unsafe { nil }
			|| !usercopy.copy_from_user(voidptr(u64(buffer) + copied), u64(iov.iov_base), iov.iov_len) {
			return errno.err, errno.efault
		}
		copied += iov.iov_len
	}

	mut control := voidptr(0)
	if kernel_msg.msg_controllen != 0 {
		if kernel_msg.msg_controllen > socket_msg_control_max {
			return errno.err, errno.emsgsize
		}
		control = memory.malloc(kernel_msg.msg_controllen)
		if control == unsafe { nil } {
			return errno.err, errno.enomem
		}
		defer { memory.free(control) }
		if !usercopy.copy_from_user(control, u64(kernel_msg.msg_control), kernel_msg.msg_controllen) {
			return errno.err, errno.efault
		}
		kernel_msg.msg_control = control
	}

	mut address_storage := [128]u8{}
	mut kernel_address := voidptr(0)
	if kernel_msg.msg_name != unsafe { nil } {
		copy_sockaddr_from_user(kernel_msg.msg_name, kernel_msg.msg_namelen,
			voidptr(&address_storage[0])) or { return errno.err, errno.get() }
		kernel_address = voidptr(&address_storage[0])
		kernel_msg.msg_name = kernel_address
	}

	if kernel_msg.msg_controllen != 0 {
		if flags & ~0x4040 != 0 || kernel_address != unsafe { nil } {
			return errno.err, errno.eopnotsupp
		}
		mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
			return errno.err, errno.get()
		}
		defer { fd.unref() }
		mut res := fd.handle.resource
		if mut res is sock_unix.UnixSocket {
			mut passed_fds := collect_passed_fds(&kernel_msg) or {
				return errno.err, errno.get()
			}
			old_flags := fd.handle.flags
			if flags & 0x40 != 0 {
				fd.handle.flags |= resource.o_nonblock
			}
			ret := res.write_with_fds(fd.handle, buffer, total, passed_fds) or {
				fd.handle.flags = old_flags
				release_passed_fds(mut passed_fds)
				return errno.err, errno.get()
			}
			fd.handle.flags = old_flags
			unsafe { passed_fds.free() }
			return u64(ret), 0
		}
		return errno.err, errno.eopnotsupp
	}

	return sendto_kernel(fdnum, buffer, total, flags, kernel_address, kernel_msg.msg_namelen)
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
	} else if mut res is sock_inet.InetSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}

	mut address_storage := [128]u8{}
	copy_sockaddr_from_user(_addr, addrlen, voidptr(&address_storage[0])) or {
		return errno.err, errno.get()
	}
	sock.connect(fd.handle, voidptr(&address_storage[0]), addrlen) or {
		return errno.err, errno.get()
	}

	return 0, 0
}

pub fn syscall_getpeername(_ voidptr, fdnum int, _addr voidptr, addrlen &u32) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	socket_name_to_user(mut sock, fd.handle, _addr, addrlen, true) or {
		return errno.err, errno.get()
	}
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
	if mut res is sock_inet.InetSocket {
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

	socket_name_to_user(mut sock, fd.handle, _addr, addrlen, false) or {
		return errno.err, errno.get()
	}
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

// getsockopt(2). Most options are integer-valued; SO_PEERCRED carries Linux's
// three-field ucred record and is handled before the generic path.
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
	if level == sock_pub.sol_socket && optname == sock_pub.so_peercred {
		if capacity < sizeof(sock_pub.UCred) {
			return errno.err, errno.einval
		}
		mut res := fd.handle.resource
		if mut res is sock_unix.UnixSocket {
			credentials := res.peer_credentials() or { return errno.err, errno.get() }
			written := u32(sizeof(sock_pub.UCred))
			if !usercopy.copy_to_user(optval, voidptr(&credentials), sizeof(sock_pub.UCred))
				|| !usercopy.copy_to_user(optlen, voidptr(&written), sizeof(u32)) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		return errno.err, errno.enoprotoopt
	}
	if capacity < sizeof(i32) {
		return errno.err, errno.einval
	}

	value := sock.getsockopt(fd.handle, level, optname) or { return errno.err, errno.get() }

	written := u32(sizeof(i32))
	value32 := i32(value)
	if !usercopy.copy_to_user(optval, voidptr(&value32), sizeof(i32)) {
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
	mut value32 := i32(0)
	if optval != 0 && optlen >= u32(sizeof(i32)) {
		if !usercopy.copy_from_user(voidptr(&value32), optval, sizeof(i32)) {
			return errno.err, errno.efault
		}
	} else if optval == 0 && optlen != 0 {
		return errno.err, errno.efault
	}

	sock.setsockopt(fd.handle, level, optname, int(value32)) or { return errno.err, errno.get() }

	return 0, 0
}
