// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module serial

import powerpc.video

__global control u32
__global data_port u32

fn read(address u32) u8 {
	mut value := u32(0)
	asm volatile ppc raw {
		"lbz %[value],0(%[address])\n\teieio"
		; [value] "=r" (value)
		; [address] "b" (address)
		; memory
	}
	return u8(value)
}

fn write(address u32, value u8) {
	asm volatile ppc raw {
		"stb %[value],0(%[address])\n\teieio"
		; ; [address] "b" (address)
		[value] "r" (value)
		; memory
	}
}

fn reg(index u8, value u8) {
	write(control, index)
	write(control, value)
}

pub fn init(ctrl u32, data u32) {
	control = ctrl
	data_port = data
	// Polled 38400 8N1, with all SCC interrupt sources disabled.
	reg(9, 0xc0)
	reg(4, 0x44)
	reg(3, 0xc1)
	reg(5, 0xea)
	reg(1, 0)
	reg(9, 0)
	reg(11, 0x50)
	reg(12, 1)
	reg(13, 0)
	reg(14, 3)
	reg(15, 0)
}

pub fn put(byte u8) {
	video.put(byte)
	if control == 0 { return }
	for read(control) & 4 == 0 {
	}
	write(data_port, byte)
}

pub fn get() int {
	if !pending() { return -1 }
	return int(read(data_port))
}

pub fn pending() bool {
	return control != 0 && read(control) & 1 != 0
}

pub fn text(message &char) {
	unsafe {
		for i := 0; message[i] != 0; i++ {
			if u8(message[i]) == `\n` { put(`\r`) }
			put(u8(message[i]))
		}
	}
}

pub fn hex(value u32) {
	text(c'0x')
	digits := unsafe { &char(c'0123456789abcdef') }
	for shift := 28; shift >= 0; shift -= 4 {
		put(unsafe { u8(digits[(value >> u32(shift)) & 15]) })
	}
}
