// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/socket.h>
#include <sys/uio.h>

struct C.iovec {
mut:
	iov_base voidptr
	iov_len usize
}

struct C.msghdr {
mut:
	msg_name voidptr
	msg_namelen u32
	msg_iov &C.iovec
	msg_iovlen usize
	msg_control voidptr
	msg_controllen usize
	msg_flags i32
}

struct DarwinMessage {
mut:
	name voidptr
	name_length u32
	vectors &C.iovec
	vector_count i32
	control voidptr
	control_length u32
	flags i32
}

fn C.recvmsg(i32, &C.msghdr, i32) isize
fn C.sendmsg(i32, &C.msghdr, i32) isize

// Control records are only four-byte aligned on Darwin, including timeval's
// 64-bit seconds. memcpy also permits an unaligned caller control buffer.
fn message_load32(address usize) u32 {
	mut value := u32(0)
	unsafe { C.memcpy(&value, voidptr(address), 4) }
	return value
}

fn message_load64(address usize) u64 {
	mut value := u64(0)
	unsafe { C.memcpy(&value, voidptr(address), 8) }
	return value
}

fn message_store32(address usize, value u32) {
	unsafe { C.memcpy(voidptr(address), &value, 4) }
}

fn message_store64(address usize, value u64) {
	unsafe { C.memcpy(voidptr(address), &value, 8) }
}

fn message_linux_layout() bool {
	$if linux { return true }
	return false
}

fn message_vectors(message &DarwinMessage) ?usize {
	if message.vector_count <= 0 || message.vector_count > 1024 { darwin_set_errno(40); return none }
	if message.vectors == unsafe { nil } { darwin_set_errno(14); return none }
	mut total := usize(0)
	unsafe {
		for i in 0 .. message.vector_count {
			vector := message.vectors[i]
			if vector.iov_len > usize(0x7fffffffffffffff) - total { darwin_set_errno(22); return none }
			if vector.iov_len != 0 && vector.iov_base == nil { darwin_set_errno(14); return none }
			total += vector.iov_len
		}
	}
	return total
}

// Build native ancillary records without acquiring any descriptor ownership.
// Only SCM_RIGHTS is a supported send control; reject others before socket I/O.
fn message_control_send(input usize, length usize, native usize, capacity usize, linux_layout bool) ?usize {
	header := if linux_layout { usize(16) } else { usize(12) }
	align := if linux_layout { usize(8) } else { usize(4) }
	mut offset := usize(0)
	mut used := usize(0)
	for offset < length {
		if length - offset < 12 { darwin_set_errno(22); return none }
		base := input + offset
		size := usize(message_load32(base))
		if size < 12 || size > length - offset || (size - 12) % 4 != 0 { darwin_set_errno(22); return none }
		if message_load32(base + 4) != 0xffff || message_load32(base + 8) != 1 { darwin_set_errno(45); return none }
		native_size := header + size - 12
		space := (native_size + align - 1) & ~(align - 1)
		if space > capacity - used { darwin_set_errno(45); return none }
		destination := native + used
		unsafe { C.memset(voidptr(destination), 0, space) }
		if linux_layout { message_store64(destination, u64(native_size)) } else { message_store32(destination, u32(native_size)) }
		message_store32(destination + header - 8, if linux_layout { u32(1) } else { u32(0xffff) })
		message_store32(destination + header - 4, 1)
		unsafe { C.memcpy(voidptr(destination + header), voidptr(base + 12), size - 12) }
		used += space
		offset += (size + 3) & ~usize(3)
	}
	return used
}

// Translate actual native records. Descriptors installed by native recvmsg
// belong to this operation until a complete int reaches the caller; close
// every descriptor that cannot be represented, including partial words.
fn message_control_receive(native usize, length usize, output usize, capacity usize, linux_layout bool) (usize, i32) {
	header := if linux_layout { usize(16) } else { usize(12) }
	align := if linux_layout { usize(8) } else { usize(4) }
	level := if linux_layout { u32(1) } else { u32(0xffff) }
	timestamp := if linux_layout { u32(29) } else { u32(2) }
	mut record := [8192]u8{}
	mut offset := usize(0)
	mut used := usize(0)
	mut flags := i32(0)
	for length - offset >= header {
		base := native + offset
		size := if linux_layout { usize(message_load64(base)) } else { usize(message_load32(base)) }
		if size < header || size > length - offset { flags |= 0x20; break }
		kind := message_load32(base + header - 4)
		payload := size - header
		mut darwin_size := usize(0)
		address := usize(unsafe { &record[0] })
		if message_load32(base + header - 8) == level && kind == 1 && payload % 4 == 0 && payload <= record.len - 12 {
			darwin_size = 12 + payload
			unsafe { C.memcpy(voidptr(address + 12), voidptr(base + header), payload) }
			for i := usize(0); i < payload; i += 4 {
				if output == 0 || used + 12 + i + 4 > capacity { C.close(i32(message_load32(base + header + i))) }
			}
		} else if message_load32(base + header - 8) == level && kind == timestamp && payload >= 16 {
			darwin_size = 28
			message_store64(address + 12, message_load64(base + header))
			message_store32(address + 20, message_load32(base + header + 8))
			message_store32(address + 24, 0)
		} else {
			flags |= 0x20
		}
		if darwin_size != 0 {
			message_store32(address, u32(darwin_size))
			message_store32(address + 4, 0xffff)
			message_store32(address + 8, if kind == 1 { u32(1) } else { u32(2) })
			space := (darwin_size + 3) & ~usize(3)
			copied := if output == 0 || used >= capacity { usize(0) } else if space < capacity - used { space } else { capacity - used }
			if copied != 0 { unsafe { C.memcpy(voidptr(output + used), &record[0], copied) } }
			if copied < space { flags |= 0x20 }
			used += copied
		}
		space := (size + align - 1) & ~(align - 1)
		if space > length - offset { break }
		offset += space
	}
	return used, flags
}

fn message_flags_out(flags i32) i32 {
	mut output := i32(0)
	for pair in [[i32(C.MSG_OOB), i32(1)]!, [i32(C.MSG_EOR), i32(8)]!,
		[i32(C.MSG_TRUNC), i32(0x10)]!, [i32(C.MSG_CTRUNC), i32(0x20)]!]! {
		if flags & pair[0] != 0 { output |= pair[1] }
	}
	return output
}

fn darwin_sendmsg(fd i32, message &DarwinMessage, flags i32) isize {
	if message == unsafe { nil } { darwin_set_errno(14); return -1 }
	message_vectors(message) or { return -1 }
	native_flags := socket_native_flags(flags)
	if native_flags < 0 { return -1 }
	previous := unsafe { *C.ios_errno_address() }
	mut address := [32]u64{}
	mut control := [8192]u8{}
	mut native := C.msghdr{ msg_iov: message.vectors, msg_iovlen: usize(message.vector_count) }
	if message.name != unsafe { nil } {
		if !socket_address_in(message.name, message.name_length, unsafe { &address[0] }) { return -1 }
		native.msg_name = unsafe { &address[0] }
		native.msg_namelen = message.name_length
	}
	if message.control != unsafe { nil } && message.control_length != 0 {
		if message.control_length > control.len { darwin_set_errno(45); return -1 }
		native.msg_controllen = message_control_send(usize(message.control), message.control_length,
			usize(unsafe { &control[0] }), usize(control.len), message_linux_layout()) or { return -1 }
		native.msg_control = unsafe { &control[0] }
	}
	result := socket_result(C.sendmsg(fd, unsafe { &native }, i32(native_flags)))
	if result >= 0 { darwin_set_errno(previous) }
	return result
}

fn darwin_recvmsg(fd i32, message &DarwinMessage, flags i32) isize {
	if message == unsafe { nil } { darwin_set_errno(14); return -1 }
	total := message_vectors(message) or { return -1 }
	native_flags := socket_native_flags(flags)
	if native_flags < 0 { return -1 }
	previous := unsafe { *C.ios_errno_address() }
	mut kind := i32(0)
	mut kind_size := u32(4)
	if C.getsockopt(fd, C.SOL_SOCKET, C.SO_TYPE, unsafe { &kind }, unsafe { &kind_size }) < 0 { return socket_result(-1) }
	mut address := [32]u64{}
	mut control := [8192]u8{}
	mut vectors := [1025]C.iovec{}
	mut extra := [1]u8{}
	mut native := C.msghdr{ msg_iov: message.vectors, msg_iovlen: usize(message.vector_count) }
	$if linux {
		// The native INET backend does not report truncation in msg_flags.
		// One extra byte detects it in the same atomic receive, without a
		// racy peek/consume pair or writing beyond the caller's vectors.
		if kind == C.SOCK_DGRAM && message.vector_count < 1024 && total < usize(0x7fffffffffffffff) {
			unsafe { C.memcpy(&vectors[0], message.vectors, usize(message.vector_count) * sizeof(C.iovec)) }
			vectors[message.vector_count] = C.iovec{ iov_base: unsafe { &extra[0] }, iov_len: 1 }
			native.msg_iov = unsafe { &vectors[0] }
			native.msg_iovlen++
		}
	}
	if message.name != unsafe { nil } && message.name_length != 0 {
		native.msg_name = unsafe { &address[0] }
		native.msg_namelen = u32(sizeof(address))
	}
	// Always collect native ancillary data: the Mac can install SCM_RIGHTS
	// descriptors even with no output storage. Private storage lets us close
	// all rights that the caller did not request or cannot represent.
	native.msg_control = unsafe { &control[0] }
	native.msg_controllen = usize(control.len)
	result := socket_result(C.recvmsg(fd, unsafe { &native }, i32(native_flags)))
	if result < 0 { return result }
	mut output_flags := flags | message_flags_out(native.msg_flags)
	if usize(result) > total { output_flags |= 0x10 }
	if native.msg_name != unsafe { nil } {
		if native.msg_namelen == 0 || (native.msg_namelen == sizeof(address) && address[0] == 0) {
			// Darwin's unnamed UNIX source has a generic sockaddr header.
			native.msg_namelen = 16
			$if linux { unsafe { *(&u16(&address[0])) = u16(C.AF_UNIX) } }
		}
		socket_address_out(unsafe { &address[0] }, native.msg_namelen, message.name, unsafe { &message.name_length })
	}
	length := if native.msg_controllen < control.len { native.msg_controllen } else { usize(control.len) }
	if message.control != unsafe { nil } && message.control_length != 0 {
		used, control_flags := message_control_receive(usize(unsafe { &control[0] }), length,
			usize(message.control), message.control_length, message_linux_layout())
		message_store32(usize(message) + 40, u32(used))
		output_flags |= control_flags
	} else {
		message_control_receive(usize(unsafe { &control[0] }), length, 0, 0, message_linux_layout())
		// Darwin does not report ancillary truncation when none was requested.
		output_flags &= ~i32(0x20)
	}
	message_store32(usize(message) + 44, u32(output_flags))
	darwin_set_errno(previous)
	return if usize(result) > total { isize(total) } else { result }
}
