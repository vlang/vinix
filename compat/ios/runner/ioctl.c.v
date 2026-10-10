// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/ioctl.h>

fn C.ioctl(i32, u64, ...voidptr) i32
fn C.ios_ioctl()

fn darwin_ioctl_result(result i32, previous i32) i32 {
	if result < 0 {
		native := unsafe { *C.ios_errno_address() }
		darwin_set_errno(darwin_native_error(native))
	} else { darwin_set_errno(previous) }
	return result
}

fn darwin_ioctl_interface_result(result i32, previous i32) i32 {
	if result < 0 && unsafe { *C.ios_errno_address() } == C.ENODEV {
		darwin_set_errno(6); return -1
	}
	return darwin_ioctl_result(result, previous)
}

fn darwin_ioctl_interface(fd i32, request u64, argument voidptr, previous i32) i32 {
	$if macos { return darwin_ioctl_result(C.ioctl(fd, request, argument), previous) }
	$if linux {
		// Darwin's ifreq is 32 bytes, the native Linux structure is 40.
		// Only query names enter the native buffer; copy back precisely the
		// selected union member, retaining the caller's name and unused bytes.
		mut buffer := [40]u8{}
		unsafe { C.memcpy(&buffer[0], argument, 16) }
		native := match request {
			0xc0206911 { u64(C.SIOCGIFFLAGS) }
			0xc0206917 { u64(C.SIOCGIFMETRIC) }
			0xc0206921 { u64(C.SIOCGIFADDR) }
			0xc0206923 { u64(C.SIOCGIFBRDADDR) }
			0xc0206925 { u64(C.SIOCGIFNETMASK) }
			0xc0206933 { u64(C.SIOCGIFMTU) }
			else { darwin_set_errno(45); return -1 }
		}
		if request == 0xc0206923 {
			if darwin_ioctl_interface_result(C.ioctl(fd, u64(C.SIOCGIFFLAGS), unsafe { &buffer[0] }), previous) < 0 { return -1 }
			if buffer[16] & 2 == 0 { darwin_set_errno(22); return -1 }
		}
		if darwin_ioctl_interface_result(C.ioctl(fd, native, unsafe { &buffer[0] }), previous) < 0 { return -1 }
		output := unsafe { voidptr(usize(argument) + 16) }
		if request == 0xc0206911 {
			flags := u32(buffer[16]) | (u32(buffer[17]) << 8)
			mut converted := flags & 0x3ff
			if flags & u32(C.IFF_MULTICAST) != 0 { converted |= 0x8000 }
			unsafe { *(&u16(output)) = u16(converted) }
		} else if request in [u64(0xc0206917), 0xc0206933] {
			unsafe { C.memcpy(output, &buffer[16], 4) }
		} else {
			buffer[16] = 16; buffer[17] = 2
			if request == 0xc0206925 {
				// Darwin's mask sockaddr length excludes trailing zero address
				// bytes (for example, 255.0.0.0 reports five bytes).
				mut length := 8
				for length > 4 && buffer[16 + length - 1] == 0 { length-- }
				buffer[16] = u8(length)
			}
			unsafe { C.memcpy(output, &buffer[16], 16) }
		}
		darwin_set_errno(previous)
		return 0
	}
	darwin_set_errno(45)
	return -1
}

@[export: 'ios_ioctl_stack']
fn darwin_ioctl(fd i32, request u64, stack u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	// Requests without a variadic argument never read the stack slot. The
	// measured Darwin input-copy path reports null data before an invalid fd.
	if request == 0x20006601 || request == 0x20006602 {
		native := if request == 0x20006601 { u64(C.FIOCLEX) } else { u64(C.FIONCLEX) }
		return darwin_ioctl_result(C.ioctl(fd, native, unsafe { nil }), previous)
	}
	if request !in [u64(0x8004667e), 0x4004667f, 0xc0206911, 0xc0206917,
		0xc0206921, 0xc0206923, 0xc0206925, 0xc0206933] {
		if darwin_file_result(C.fcntl(fd, C.F_GETFD, usize(0))) < 0 { return -1 }
		darwin_set_errno(45); return -1
	}
	argument := unsafe { voidptr(read64(stack)) }
	if argument == unsafe { nil } { darwin_set_errno(14); return -1 }
	if darwin_file_result(C.fcntl(fd, C.F_GETFD, usize(0))) < 0 { return -1 }
	if request == 0x8004667e || request == 0x4004667f {
		native := if request == 0x8004667e { u64(C.FIONBIO) } else { u64(C.FIONREAD) }
		return darwin_ioctl_result(C.ioctl(fd, native, argument), previous)
	}
	return darwin_ioctl_interface(fd, request, argument, previous)
}
