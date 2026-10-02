module socket

import resource
import file
import errno
import usercopy
import socket.public as sock_pub
import socket.unix as sock_unix
import socket.inet as sock_inet
import socket.netlink as sock_netlink
import proc

const cmsg_header_size = u64(16)
const cmsg_align = u64(8)

struct CMsgHdr {
	cmsg_len   u64
	cmsg_level i32
	cmsg_type  i32
}

// The largest address any family has: struct sockaddr_storage.
const sockaddr_max = u32(128)

// The longest message any family takes, and so the most a receive needs room
// for. A send goes through a buffer one byte longer: a stream takes that much
// and says so, and a datagram too long to send is refused by its family, with
// EMSGSIZE, rather than cut short here.
const message_max = u64(sock_unix.sock_buf)

// The most ancillary data a message carries.
const control_max = u64(64 * 1024)

// UIO_MAXIOV.
const iov_max = u64(1024)

// A transfer this small uses a buffer on the stack.
const small_message = u64(512)

// The socket families are handed kernel memory, always: an address, a
// message, its ancillary data. The calls here copy each in from the process
// and each result back out through usercopy, which is what tells a pointer
// that leads nowhere, or into the kernel, from one that is the process's own.

// An address a process passed, copied into `storage`. A null one stays null:
// each family says what a missing address means.
fn address_from_user(addr voidptr, addrlen u32, storage voidptr) ?voidptr {
	if addr == unsafe { nil } {
		return unsafe { nil }
	}
	if addrlen > sockaddr_max {
		errno.set(errno.einval)
		return none
	}
	if !usercopy.copy_from_user(storage, u64(addr), addrlen) {
		errno.set(errno.efault)
		return none
	}
	return storage
}

// An address on its way out: as much as the caller's buffer holds, and the
// length the address needs.
fn address_to_user(addr voidptr, addrlen_ptr u64, storage voidptr, capacity u32, length u32) bool {
	mut to_copy := if length < capacity { length } else { capacity }
	if to_copy > sockaddr_max {
		to_copy = sockaddr_max
	}
	if to_copy > 0 && !usercopy.copy_to_user(u64(addr), storage, to_copy) {
		return false
	}
	return usercopy.copy_to_user(addrlen_ptr, voidptr(&length), sizeof(u32))
}

fn release_passed_fds(mut fds []&file.FD) {
	for mut fd in fds {
		fd.unref()
	}
	unsafe { fds.free() }
}

fn collect_passed_fds(msg &sock_pub.MsgHdr) ?[]&file.FD {
	mut result := []&file.FD{}
	// Nothing slices it, so growing can free each outgrown block.
	result.flags |= .noslices
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
		// pledge(2): passing descriptors on needs "sendfd".
		if fd_count != 0 {
			refused := proc.pledge_check(proc.pledge_sendfd)
			if refused != 0 {
				release_passed_fds(mut result)
				errno.set(refused)
				return none
			}
		}
		for i := u64(0); i < fd_count; i++ {
			fdnum := unsafe { *(&i32(voidptr(u64(header) + cmsg_header_size + i * sizeof(i32)))) }
			mut source := file.fd_from_fdnum(unsafe { nil }, int(fdnum)) or {
				release_passed_fds(mut result)
				return none
			}
			// fd_from_fdnum() acquired the Handle reference now owned by this
			// queued descriptor, so only the source descriptor is let go.
			mut passed := &file.FD{
				handle: source.handle
				flags: 0
			}
			source.release_descriptor()
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

// The address family of the socket `fdnum` names, or -1 when it names no
// socket. pledge(2) decides by it which promise a call on the socket needs.
pub fn family_of(fdnum int) int {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return -1 }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res is sock_unix.UnixSocket {
		return sock_pub.af_unix
	}
	if mut res is sock_inet.InetSocket {
		return res.family
	}
	if mut res is sock_netlink.NetlinkSocket {
		return sock_pub.af_netlink
	}
	return -1
}

fn socketpair_create(domain int, @type int, _protocol int) ?(&resource.Resource, &resource.Resource) {
	match domain {
		sock_pub.af_unix {
			mut socket0, mut socket1 := sock_unix.create_pair(@type)?
			return socket0.boxed(), socket1.boxed()
		}
		// Linux's IPv4 has no socketpair(2); a family there is none of has
		// no sockets at all.
		sock_pub.af_inet, sock_pub.af_inet6 {
			errno.set(errno.eopnotsupp)
			return none
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.eafnosupport)
			return none
		}
	}
}

fn socket_create(domain int, @type int, protocol int) ?&resource.Resource {
	match domain {
		sock_pub.af_unix {
			mut ret := sock_unix.create(@type)?
			return ret.boxed()
		}
		sock_pub.af_inet, sock_pub.af_inet6 {
			ret := sock_inet.create(domain, @type, protocol)?
			return ret.box
		}
		sock_pub.af_netlink {
			ret := sock_netlink.create(@type, protocol)?
			return ret.box
		}
		else {
			// Linux reports unsupported families to callers explicitly.
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.eafnosupport)
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

	mut fds := [2]i32{}
	fds[0] = i32(file.fdnum_create_from_resource(unsafe { nil }, mut socket0, flags, 0, false) or {
		return errno.err, errno.get()
	})
	fds[1] = i32(file.fdnum_create_from_resource(unsafe { nil }, mut socket1, flags, 0, false) or {
		file.fdnum_close(unsafe { nil }, int(fds[0]), true) or {}
		return errno.err, errno.get()
	})
	if !usercopy.copy_to_user(u64(voidptr(ret)), unsafe { voidptr(&fds[0]) }, sizeof(i32) * 2) {
		file.fdnum_close(unsafe { nil }, int(fds[0]), true) or {}
		file.fdnum_close(unsafe { nil }, int(fds[1]), true) or {}
		return errno.err, errno.efault
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
	} else if mut res is sock_netlink.NetlinkSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}
	defer {
		unsafe { free(sock) }
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
	} else if mut res is sock_netlink.NetlinkSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}
	// V boxes a pointer to this interface on the heap. The socket resource
	// remains owned by the descriptor; only the temporary box is ours.
	defer {
		unsafe { free(sock) }
	}

	// bind(2) and connect(2) have no meaning for a missing address.
	if _addr == unsafe { nil } {
		return errno.err, if addrlen == 0 { errno.einval } else { errno.efault }
	}
	mut storage := [128]u8{}
	address := address_from_user(_addr, addrlen, unsafe { voidptr(&storage[0]) }) or {
		return errno.err, errno.get()
	}
	sock.bind(fd.handle, address, addrlen) or { return errno.err, errno.get() }

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
	} else if mut res is sock_netlink.NetlinkSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}
	// V boxes a pointer to this interface on the heap. The socket resource
	// remains owned by the descriptor; only the temporary box is ours.
	defer {
		unsafe { free(sock) }
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

	mut header := sock_pub.MsgHdr{}
	if !usercopy.copy_from_user(voidptr(&header), u64(voidptr(msg)), sizeof(sock_pub.MsgHdr)) {
		return errno.err, errno.efault
	}
	ret, err := receive_message(fdnum, mut header, flags)
	if err != 0 {
		return ret, err
	}
	// The pointers go back as they came; the lengths and flags are the call's.
	if !usercopy.copy_to_user(u64(voidptr(msg)), voidptr(&header), sizeof(sock_pub.MsgHdr)) {
		return errno.err, errno.efault
	}
	return ret, 0
}

// recvmsg(2) for a header already copied in, as recvmmsg(2) has each of its
// own. What the header points at is still the process's; its lengths and flags
// are updated in place for the caller to copy out.
pub fn receive_message(fdnum int, mut header sock_pub.MsgHdr, flags int) (u64, u64) {
	total := iovec_total(header) or { return errno.err, errno.get() }
	size := if total < message_max { total } else { message_max }
	// What a socket gives up is gone from it: find out that there is nowhere
	// to put it before taking it.
	if size != 0 {
		first := iovec_from_user(header.msg_iov, 0) or { return errno.err, errno.get() }
		if first.iov_len != 0 && !usercopy.writable(u64(first.iov_base)) {
			return errno.err, errno.efault
		}
	}
	mut small := [512]u8{}
	buffer := if size <= small_message { unsafe { voidptr(&small[0]) } } else { unsafe { malloc(size) } }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		if size > small_message {
			unsafe { free(buffer) }
		}
	}
	mut vector := sock_pub.IoVec{
		iov_base: buffer
		iov_len:  size
	}
	control_size := if header.msg_control == unsafe { nil } {
		u64(0)
	} else if header.msg_controllen < control_max {
		header.msg_controllen
	} else {
		control_max
	}
	control := if control_size != 0 { unsafe { malloc(control_size) } } else { unsafe { nil } }
	defer {
		if control != unsafe { nil } {
			unsafe { free(control) }
		}
	}
	// A family with no address to report leaves these as they are, and then
	// so is the caller's buffer left.
	mut storage := [128]u8{init: 0xff}
	offered := if header.msg_name == unsafe { nil } {
		u32(0)
	} else if header.msg_namelen < sockaddr_max {
		header.msg_namelen
	} else {
		sockaddr_max
	}
	mut kernel_message := sock_pub.MsgHdr{
		msg_name:       if header.msg_name == unsafe { nil } {
			unsafe { nil }
		} else {
			unsafe { voidptr(&storage[0]) }
		}
		msg_namelen:    offered
		msg_iov:        unsafe { &vector }
		msg_iovlen:     1
		msg_control:    control
		msg_controllen: control_size
	}
	message := unsafe { &kernel_message }
	received, err := receive_into(fdnum, message, flags)
	if err != 0 {
		return received, err
	}

	// MSG_TRUNC reports the whole message's length, which may be more than
	// there was room for.
	mut left := if received < size { received } else { size }
	mut copied := u64(0)
	for i := u64(0); i < header.msg_iovlen && left != 0; i++ {
		iov := iovec_from_user(header.msg_iov, i) or { return errno.err, errno.get() }
		amount := if iov.iov_len < left { iov.iov_len } else { left }
		if amount != 0 {
			if !usercopy.copy_to_user(u64(iov.iov_base), voidptr(u64(buffer) + copied), amount) {
				return errno.err, errno.efault
			}
			copied += amount
			left -= amount
		}
	}
	if header.msg_control != unsafe { nil } {
		used := if message.msg_controllen < control_size { message.msg_controllen } else { control_size }
		if used != 0 && !usercopy.copy_to_user(u64(header.msg_control), control, used) {
			return errno.err, errno.efault
		}
	}
	header.msg_controllen = message.msg_controllen
	if header.msg_name != unsafe { nil }
		&& (message.msg_namelen != offered || storage[0] != 0xff || storage[1] != 0xff) {
		named := if message.msg_namelen < offered { message.msg_namelen } else { offered }
		if named != 0 && !usercopy.copy_to_user(u64(header.msg_name), unsafe { voidptr(&storage[0]) }, named) {
			return errno.err, errno.efault
		}
		header.msg_namelen = message.msg_namelen
	}
	header.msg_flags = message.msg_flags
	return received, 0
}

// recvmsg(2) with the header and all it points at in kernel memory.
fn receive_into(fdnum int, message &sock_pub.MsgHdr, flags int) (u64, u64) {
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
	} else if mut res is sock_netlink.NetlinkSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}
	defer {
		unsafe { free(sock) }
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
	ret := sock.recvmsg(fd.handle, message, remaining_flags) or { return errno.err, errno.get() }

	return ret, 0
}

// sendto(2), including connected UDP when no destination is supplied.  The
// old aarch64 compatibility wrapper reduced every call to write(2), losing the
// destination that DNS and DHCP clients need.
pub fn syscall_sendto(_ voidptr, fdnum int, buf voidptr, len u64, flags int, dest_addr voidptr, addrlen u32) (u64, u64) {
	if !usercopy.user_range(u64(buf), len) {
		return errno.err, errno.efault
	}
	mut storage := [128]u8{}
	address := address_from_user(dest_addr, addrlen, unsafe { voidptr(&storage[0]) }) or {
		return errno.err, errno.get()
	}
	size := if len <= message_max { len } else { message_max + 1 }
	mut small := [512]u8{}
	buffer := if size <= small_message { unsafe { voidptr(&small[0]) } } else { unsafe { malloc(size) } }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		if size > small_message {
			unsafe { free(buffer) }
		}
	}
	// A message goes whole. What is longer than one can only be a stream's,
	// which takes it in pieces.
	mut done := u64(0)
	for {
		chunk := if len - done < size { len - done } else { size }
		if chunk != 0 && !usercopy.copy_from_user(buffer, u64(buf) + done, chunk) {
			if done != 0 {
				return done, 0
			}
			return errno.err, errno.efault
		}
		sent, err := send_from_kernel(fdnum, buffer, chunk, flags, address, addrlen)
		if err != 0 {
			if done != 0 {
				return done, 0
			}
			return sent, err
		}
		done += sent
		if sent < chunk || done >= len {
			break
		}
	}
	return done, 0
}

// sendto(2) with the message and the address in kernel memory.
fn send_from_kernel(fdnum int, buf voidptr, len u64, flags int, dest_addr voidptr, addrlen u32) (u64, u64) {
	if flags & ~0x4040 != 0 { // MSG_DONTWAIT | MSG_NOSIGNAL
		return errno.err, errno.eopnotsupp
	}
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res is sock_inet.InetSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer {
			fd.handle.flags = old_flags
		}
		ret := res.sendto(fd.handle, buf, len, dest_addr, addrlen) or {
			return errno.err, errno.get()
		}
		return u64(ret), 0
	}
	if mut res is sock_unix.UnixSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer {
			fd.handle.flags = old_flags
		}
		if dest_addr != unsafe { nil } {
			// Only a datagram has somewhere to go by address alone.
			if !res.is_datagram() {
				return errno.err, errno.eopnotsupp
			}
			ret := res.send_datagram_to(voidptr(fd.handle), buf, len, dest_addr, addrlen) or {
				return errno.err, errno.get()
			}
			return u64(ret), 0
		}
		ret := fd.handle.write(buf, len) or { return errno.err, errno.get() }
		return u64(ret), 0
	}
	if mut res is sock_netlink.NetlinkSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer {
			fd.handle.flags = old_flags
		}
		ret := fd.handle.write(buf, len) or { return errno.err, errno.get() }
		return u64(ret), 0
	}
	return errno.err, errno.enotsock
}

pub fn syscall_recvfrom(_ voidptr, fdnum int, buf voidptr, len u64, flags int, src_addr voidptr, addrlen &u32) (u64, u64) {
	// What a socket gives up is gone from it: find out that there is nowhere
	// to put it before taking it.
	if !usercopy.user_range(u64(buf), len) || (len != 0 && !usercopy.writable(u64(buf))) {
		return errno.err, errno.efault
	}
	wants_address := src_addr != unsafe { nil } && addrlen != unsafe { nil }
	mut capacity := u32(0)
	if wants_address
		&& !usercopy.copy_from_user(voidptr(&capacity), u64(voidptr(addrlen)), sizeof(u32)) {
		return errno.err, errno.efault
	}
	// A family that has no address to report leaves these as they are, and
	// then so is the caller's buffer left.
	mut storage := [128]u8{init: 0xff}
	offered := if capacity < sockaddr_max { capacity } else { sockaddr_max }
	mut length := offered
	size := if len < message_max { len } else { message_max }
	mut small := [512]u8{}
	buffer := if size <= small_message { unsafe { voidptr(&small[0]) } } else { unsafe { malloc(size) } }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		if size > small_message {
			unsafe { free(buffer) }
		}
	}
	mut address_out := unsafe { nil }
	mut length_out := &u32(unsafe { nil })
	if wants_address {
		address_out = unsafe { voidptr(&storage[0]) }
		length_out = unsafe { &length }
	}
	received, err := receive_to_kernel(fdnum, buffer, size, flags, address_out, length_out)
	if err != 0 {
		return received, err
	}
	// MSG_TRUNC reports the whole datagram's length, which may be more than
	// there was room for.
	copied := if received < size { received } else { size }
	if copied != 0 && !usercopy.copy_to_user(u64(buf), buffer, copied) {
		return errno.err, errno.efault
	}
	if wants_address && (length != offered || storage[0] != 0xff || storage[1] != 0xff)
		&& !address_to_user(src_addr, u64(voidptr(addrlen)), unsafe { voidptr(&storage[0]) },
		capacity, length) {
		return errno.err, errno.efault
	}
	return received, 0
}

// recvfrom(2) with the buffer and the address in kernel memory.
fn receive_to_kernel(fdnum int, buf voidptr, len u64, flags int, src_addr voidptr, addrlen &u32) (u64, u64) {
	// MSG_PEEK, MSG_TRUNC, MSG_DONTWAIT, MSG_WAITALL and MSG_CMSG_CLOEXEC. A
	// length-prefix protocol on a SOCK_SEQPACKET socket reads a record's size
	// with recvfrom(0, MSG_PEEK|MSG_TRUNC); the unix seqpacket path honours it.
	allowed := 0x2 | 0x20 | 0x40 | 0x100 | 0x40000000
	if flags & ~allowed != 0 {
		return errno.err, errno.eopnotsupp
	}
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res is sock_inet.InetSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer {
			fd.handle.flags = old_flags
		}
		ret := res.recvfrom(fd.handle, buf, len, src_addr, addrlen) or {
			return errno.err, errno.get()
		}
		return u64(ret), 0
	}
	if mut res is sock_unix.UnixSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer {
			fd.handle.flags = old_flags
		}
		if res.keeps_boundaries() {
			ret := res.recv_seqpacket(voidptr(fd.handle), buf, len, flags, src_addr, addrlen) or {
				return errno.err, errno.get()
			}
			return u64(ret), 0
		}
		ret := fd.handle.read(buf, len) or { return errno.err, errno.get() }
		return u64(ret), 0
	}
	if mut res is sock_netlink.NetlinkSocket {
		old_flags := fd.handle.flags
		if flags & 0x40 != 0 {
			fd.handle.flags |= resource.o_nonblock
		}
		defer {
			fd.handle.flags = old_flags
		}
		ret := fd.handle.read(buf, len) or { return errno.err, errno.get() }
		if src_addr != unsafe { nil } && addrlen != unsafe { nil } {
			sock_netlink.write_kernel_source(src_addr, addrlen)
		}
		return u64(ret), 0
	}
	return errno.err, errno.enotsock
}

// One of a message's iovecs, copied in.
fn iovec_from_user(vector voidptr, index u64) ?sock_pub.IoVec {
	mut iov := sock_pub.IoVec{}
	if !usercopy.copy_from_user(voidptr(&iov), u64(vector) + index * sizeof(sock_pub.IoVec),
		sizeof(sock_pub.IoVec)) {
		errno.set(errno.efault)
		return none
	}
	return iov
}

// What a message's iovecs hold together.
fn iovec_total(header &sock_pub.MsgHdr) ?u64 {
	if header.msg_iovlen > iov_max {
		errno.set(errno.emsgsize)
		return none
	}
	mut total := u64(0)
	for i := u64(0); i < header.msg_iovlen; i++ {
		iov := iovec_from_user(header.msg_iov, i)?
		if iov.iov_len > u64(0x7fffffff) || total + iov.iov_len > u64(0x7fffffff) {
			errno.set(errno.emsgsize)
			return none
		}
		total += iov.iov_len
	}
	return total
}

pub fn syscall_sendmsg(_ voidptr, fdnum int, msg &sock_pub.MsgHdr, flags int) (u64, u64) {
	mut header := sock_pub.MsgHdr{}
	if !usercopy.copy_from_user(voidptr(&header), u64(voidptr(msg)), sizeof(sock_pub.MsgHdr)) {
		return errno.err, errno.efault
	}
	return send_message(fdnum, unsafe { &header }, flags)
}

// sendmsg(2) for a header already copied in, as sendmmsg(2) has each of its
// own. What the header points at is still the process's.
pub fn send_message(fdnum int, header &sock_pub.MsgHdr, flags int) (u64, u64) {
	if header.msg_control == unsafe { nil } && header.msg_controllen != 0 {
		return errno.err, errno.efault
	}
	if header.msg_controllen > control_max {
		return errno.err, errno.enobufs
	}
	mut total := iovec_total(header) or { return errno.err, errno.get() }
	if total > message_max {
		total = message_max + 1
	}
	mut small := [512]u8{}
	buffer := if total <= small_message { unsafe { voidptr(&small[0]) } } else { unsafe { malloc(total) } }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		if total > small_message {
			unsafe { free(buffer) }
		}
	}
	// The iovecs are read again, and may have changed: never past `total`.
	mut copied := u64(0)
	for i := u64(0); i < header.msg_iovlen && copied < total; i++ {
		iov := iovec_from_user(header.msg_iov, i) or { return errno.err, errno.get() }
		amount := if iov.iov_len < total - copied { iov.iov_len } else { total - copied }
		if amount != 0 {
			if !usercopy.copy_from_user(voidptr(u64(buffer) + copied), u64(iov.iov_base), amount) {
				return errno.err, errno.efault
			}
			copied += amount
		}
	}
	total = copied

	mut storage := [128]u8{}
	name := address_from_user(header.msg_name, header.msg_namelen, unsafe { voidptr(&storage[0]) }) or {
		return errno.err, errno.get()
	}

	if header.msg_controllen != 0 {
		if flags & ~0x4040 != 0 || header.msg_name != unsafe { nil } {
			return errno.err, errno.eopnotsupp
		}
		sent, err := send_with_control(fdnum, buffer, total, header, flags)
		return sent, err
	}
	// Not returned as it stands: V moves a local to the heap, never to be
	// freed, when a pointer into it appears in what a function returns.
	sent, err := send_from_kernel(fdnum, buffer, total, flags, name, header.msg_namelen)
	return sent, err
}

// A message with ancillary data: descriptors to pass, credentials. `buffer`
// is the kernel's; the control data is still where the process has it.
fn send_with_control(fdnum int, buffer voidptr, total u64, header &sock_pub.MsgHdr, flags int) (u64, u64) {
	control := unsafe { malloc(header.msg_controllen) }
	if control == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		unsafe { free(control) }
	}
	if !usercopy.copy_from_user(control, u64(header.msg_control), header.msg_controllen) {
		return errno.err, errno.efault
	}
	message := sock_pub.MsgHdr{
		msg_control:    control
		msg_controllen: header.msg_controllen
	}
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res is sock_unix.UnixSocket {
		mut passed_fds := collect_passed_fds(unsafe { &message }) or {
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
	} else if mut res is sock_netlink.NetlinkSocket {
		sock = res
	} else {
		return errno.err, errno.einval
	}
	// V boxes a pointer to this interface on the heap. The socket resource
	// remains owned by the descriptor; only the temporary box is ours.
	defer {
		unsafe { free(sock) }
	}

	if _addr == unsafe { nil } {
		return errno.err, if addrlen == 0 { errno.einval } else { errno.efault }
	}
	mut storage := [128]u8{}
	address := address_from_user(_addr, addrlen, unsafe { voidptr(&storage[0]) }) or {
		return errno.err, errno.get()
	}
	sock.connect(fd.handle, address, addrlen) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_getpeername(_ voidptr, fdnum int, _addr voidptr, addrlen &u32) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut capacity := u32(0)
	if !usercopy.copy_from_user(voidptr(&capacity), u64(voidptr(addrlen)), sizeof(u32)) {
		return errno.err, errno.efault
	}
	mut storage := [128]u8{}
	mut length := if capacity < sockaddr_max { capacity } else { sockaddr_max }
	// The family always has somewhere to write. A null address with room
	// claimed for it is found out on the way back to the caller.
	sock.peername(fd.handle, unsafe { voidptr(&storage[0]) }, unsafe { &length }) or {
		return errno.err, errno.get()
	}
	if !address_to_user(_addr, u64(voidptr(addrlen)), unsafe { voidptr(&storage[0]) }, capacity,
		length) {
		return errno.err, errno.efault
	}

	return 0, 0
}

// Resolve a descriptor to the socket behind it, so that the socket syscalls
// reject an ordinary file rather than answering for it. The socket is handed
// back as an interface value, which needs no box on the heap.
fn socket_from_fdnum(fdnum int) ?(&file.FD, sock_pub.Socket) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum)?

	mut res := fd.handle.resource
	if mut res is sock_unix.UnixSocket {
		return fd, sock_pub.Socket(res)
	}
	if mut res is sock_inet.InetSocket {
		return fd, sock_pub.Socket(res)
	}
	if mut res is sock_netlink.NetlinkSocket {
		return fd, sock_pub.Socket(res)
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

	mut capacity := u32(0)
	if !usercopy.copy_from_user(voidptr(&capacity), u64(voidptr(addrlen)), sizeof(u32)) {
		return errno.err, errno.efault
	}
	mut storage := [128]u8{}
	mut length := if capacity < sockaddr_max { capacity } else { sockaddr_max }
	// The family always has somewhere to write. A null address with room
	// claimed for it is found out on the way back to the caller.
	sock.sockname(fd.handle, unsafe { voidptr(&storage[0]) }, unsafe { &length }) or {
		return errno.err, errno.get()
	}
	if !address_to_user(_addr, u64(voidptr(addrlen)), unsafe { voidptr(&storage[0]) }, capacity,
		length) {
		return errno.err, errno.efault
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
	if level == sock_pub.sol_socket && (optname == sock_pub.so_rcvtimeo
		|| optname == sock_pub.so_sndtimeo || optname == sock_pub.so_linger) {
		mut res := fd.handle.resource
		send := optname == sock_pub.so_sndtimeo
		if mut res is sock_inet.InetSocket {
			on, seconds := res.linger()
			return struct_option(optname, on, seconds, res.timeout(send), optval, optlen, capacity)
		}
		if mut res is sock_unix.UnixSocket {
			on, seconds := res.linger()
			return struct_option(optname, on, seconds, res.timeout(send), optval, optlen, capacity)
		}
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

// SO_RCVTIMEO and SO_SNDTIMEO, a struct timeval, and SO_LINGER, a struct
// linger: the socket options whose values are not an int.
fn struct_option(optname int, on int, seconds int, ns u64, optval u64, optlen u64, capacity u32) (u64, u64) {
	mut words := [2]i64{}
	mut size := u32(16)
	if optname == sock_pub.so_linger {
		unsafe {
			*&i32(&words[0]) = i32(on)
			*&i32(u64(&words[0]) + 4) = i32(seconds)
		}
		size = 8
	} else {
		words[0] = i64(ns / 1000000000)
		words[1] = i64((ns % 1000000000) / 1000)
	}
	if capacity < size {
		return errno.err, errno.einval
	}
	if !usercopy.copy_to_user(optval, voidptr(&words[0]), size)
		|| !usercopy.copy_to_user(optlen, voidptr(&size), sizeof(u32)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// The value setsockopt(2) was given for SO_LINGER, as on and seconds, or for
// SO_RCVTIMEO or SO_SNDTIMEO, in nanoseconds; errno set for one that is not
// one. A negative time is no timeout, as on Linux.
fn read_struct_option(optname int, optval u64, optlen u32) ?(int, int, u64) {
	if optval == 0 {
		errno.set(errno.efault)
		return none
	}
	if optname == sock_pub.so_linger {
		if optlen < 8 {
			errno.set(errno.einval)
			return none
		}
		mut linger := [2]i32{}
		if !usercopy.copy_from_user(voidptr(&linger[0]), optval, 8) {
			errno.set(errno.efault)
			return none
		}
		return int(linger[0]), int(linger[1]), u64(0)
	}
	if optlen < 16 {
		errno.set(errno.einval)
		return none
	}
	mut timeval := [2]i64{}
	if !usercopy.copy_from_user(voidptr(&timeval[0]), optval, 16) {
		errno.set(errno.efault)
		return none
	}
	if timeval[1] < 0 || timeval[1] >= 1000000 {
		errno.set(errno.edom)
		return none
	}
	mut ns := u64(0)
	if timeval[0] > 0 || (timeval[0] == 0 && timeval[1] > 0) {
		seconds := if timeval[0] > 1000000000 { i64(1000000000) } else { timeval[0] }
		ns = u64(seconds) * 1000000000 + u64(timeval[1]) * 1000
	}
	return 0, 0, ns
}

// setsockopt(2).
pub fn syscall_setsockopt(_ voidptr, fdnum int, level int, optname int, optval u64, optlen u32) (u64, u64) {
	mut fd, mut sock := socket_from_fdnum(fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	// The timeouts and SO_LINGER of an inet or unix socket, read as the
	// structs they are. Varnish sets them on its listening socket and stopped
	// when they failed with ENOPROTOOPT.
	if level == sock_pub.sol_socket && (optname == sock_pub.so_rcvtimeo
		|| optname == sock_pub.so_sndtimeo || optname == sock_pub.so_linger) {
		mut res := fd.handle.resource
		send := optname == sock_pub.so_sndtimeo
		if mut res is sock_inet.InetSocket {
			on, seconds, ns := read_struct_option(optname, optval, optlen) or {
				return errno.err, errno.get()
			}
			if optname == sock_pub.so_linger {
				res.set_linger(on, seconds) or { return errno.err, errno.get() }
			} else {
				res.set_timeout(send, ns)
			}
			return 0, 0
		}
		if mut res is sock_unix.UnixSocket {
			on, seconds, ns := read_struct_option(optname, optval, optlen) or {
				return errno.err, errno.get()
			}
			if optname == sock_pub.so_linger {
				res.set_linger(on, seconds)
			} else {
				res.set_timeout(send, ns)
			}
			return 0, 0
		}
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
