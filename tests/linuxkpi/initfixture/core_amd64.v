// SPDX-License-Identifier: GPL-2.0-or-later
// Linux ABI PID 1 for the disposable native LinuxKPI guest.
module initfixture

struct Delay {
	seconds     isize
	nanoseconds isize
}

@[inline]
fn syscall3(nr isize, a isize, b isize, c isize) isize {
	mut result := isize(0)
	asm volatile amd64 {
		syscall
		; =a (result)
		; a (nr)
		  D (a)
		  S (b)
		  d (c)
		; rcx
		  r11
		  memory
	}
	return result
}

@[export: 'vinix_linuxkpi_guest_start'; noreturn]
pub fn start() {
	unsafe {
		// Original real CPL3 workload: eight intervals allow the APIC timer
		// to interrupt userspace, followed by ordinary getpid syscalls.
		for round := u32(0); round < 8; round++ {
			mut volatile spin := usize(0)
			for spin < 2000000 {
				asm volatile amd64 {
					; ; ; memory
				}
				spin++
			}
			syscall3(39, 0, 0, 0)
		}
		device := &char(c'/dev/com1')
		success := &char(c'LINUXKPI GUEST: PASS\n')
		fd := syscall3(2, isize(device), 1, 0)
		if fd >= 0 {
			syscall3(1, fd, isize(success), 21)
		}
		mut delay := Delay{1, 0}
		for {
			syscall3(35, isize(&delay), 0, 0)
		}
	}
}
