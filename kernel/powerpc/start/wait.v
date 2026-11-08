// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu
import powerpc.gem
import powerpc.ohci
import powerpc.runtime
import powerpc.serial

// Linux PPC32 pollfd: int fd; short events, revents. All fields are native BE.
struct PollDescriptor {
mut:
	fd i32
	events u16
	revents u16
}

fn descriptor_events(fd i32) u16 {
	if fd < 0 { return 0 }
	if fd == 0 { return if serial.pending() || ohci.key_pending() { u16(0x41) } else { u16(0) } }
	if fd == 1 || fd == 2 { return 0x104 }
	if fd >= 16 || !descriptors[fd].used { return 0x20 } // POLLNVAL, even without requested events
	node := descriptors[fd].file
	if node == -6 { return if ohci.pointer_pending() { u16(0x41) } else { u16(0) } }
	if node == -4 { return if ohci.sound_present() { u16(0x104) } else { u16(8) } }
	if node == -3 {
		if !gem.present() { return 8 }
		mut mask := if gem.receive_pending() { u16(0x41) } else { u16(0) }
		if descriptors[fd].writable { mask |= 0x104 }
		return mask
	}
	// Archive reads complete immediately (including EOF and directory errors).
	// fbdev only implements ioctl/mmap; its read/write fail without waiting.
	return if descriptors[fd].writable { u16(0x145) } else { u16(0x41) }
}

fn sys_poll(address u32, count u32, milliseconds i32) int {
	if count > 16 { return -22 } // same bound as the process descriptor table
	if !user_space.accessible(address, count * 8, true) { return -14 }
	mut fds := [16]PollDescriptor{}
	if !copy_from_user(unsafe { &u8(&fds[0]) }, address, count * 8) { return -14 }
	wait_start := cpu.timebase()
	wait_ticks := if milliseconds > 0 {
		runtime.divide_u64(u64(milliseconds) * startup_info.timebase_hz + 999, 1000)
	} else { u64(0) }
	for {
		ohci.poll()
		mut ready := 0
		for i := u32(0); i < count; i++ {
			fds[i].revents = descriptor_events(fds[i].fd) & (fds[i].events | 0x38)
			if fds[i].revents != 0 { ready++ }
		}
		if ready != 0 || (milliseconds >= 0 && cpu.timebase() - wait_start >= wait_ticks) {
			if !copy_to_user(address, unsafe { &u8(&fds[0]) }, count * 8) { return -14 }
			return ready
		}
	}
	return 0
}

fn sys_nanosleep(address u32) int {
	// musl converts its 64-bit time_t to this old kernel ABI for small waits.
	mut request := [2]u32{}
	if !copy_from_user(unsafe { &u8(&request[0]) }, address, 8) { return -14 }
	if i32(request[0]) < 0 || request[1] >= 1000000000 { return -22 }
	wait_ticks := u64(request[0]) * startup_info.timebase_hz
		+ runtime.divide_u64(u64(request[1]) * startup_info.timebase_hz + 999999999, 1000000000)
	wait_start := cpu.timebase()
	// One process, polled drivers: service USB while waiting. Interrupt-driven
	// idle and interruptible sleeps require the later scheduler/signal work.
	for cpu.timebase() - wait_start < wait_ticks { ohci.poll() }
	return 0
}
