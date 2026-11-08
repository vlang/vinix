// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.runtime
import powerpc.video

const framebuffer_virtual = u32(0x58000000)
__global framebuffer_length u32

// Linux fbdev layouts use 32-bit unsigned long on this ABI. In particular,
// fb_fix_screeninfo is 68 bytes here, rather than the LP64 structure size.
fn framebuffer_ioctl(request u32, address u32) int {
	screen := video.info()
	if screen.base == 0 { return -19 }
	runtime.fill(unsafe { &io_buffer[0] }, 0, 160)
	mut size := u32(0)
	if request == 0x4600 {
		size = 160
		buffer_word(0, screen.width); buffer_word(4, screen.height)
		buffer_word(8, screen.width); buffer_word(12, screen.height)
		buffer_word(24, screen.bits)
		channel := if screen.bits == 16 { u32(5) } else { u32(8) }
		buffer_word(32, channel * 2); buffer_word(36, channel)
		buffer_word(44, channel); buffer_word(48, channel)
		buffer_word(60, channel)
		buffer_word(88, 0xffffffff); buffer_word(92, 0xffffffff)
	} else if request == 0x4602 {
		size = 68
		buffer_text(0, c'Vinix OF')
		buffer_word(16, screen.base)
		buffer_word(20, screen.pitch * screen.height)
		buffer_word(32, 2) // packed truecolor, no mode switching or panning
		buffer_word(44, screen.pitch)
	} else { return -25 }
	if !copy_to_user(address, unsafe { &io_buffer[0] }, size) { return -14 }
	return 0
}

// Initially mmap2 supports one complete shared fbdev mapping. It cannot map
// arbitrary physical addresses, device registers, executable or private pages.
fn framebuffer_map(address u32, length u32, protection u32, flags u32, fd u32, offset u32) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	if descriptors[fd].file != -5 { return -19 }
	screen := video.info()
	if screen.base == 0 { return -19 }
	if address != 0 || length != screen.pitch * screen.height || length == 0
		|| screen.base & 4095 != 0 || length > 16 * 1024 * 1024
		|| (protection != 1 && protection != 3) || flags != 1 || offset != 0 { return -22 }
	if protection & 2 != 0 && !descriptors[fd].writable { return -13 }
	if framebuffer_length != 0 { return -16 }
	rounded := (length + 4095) & ~u32(4095)
	mut mapped := u32(0)
	for mapped < rounded {
		if !user_space.map_device(framebuffer_virtual + mapped, screen.base + mapped, protection & 2 != 0) {
			for at := u32(0); at < mapped; at += 4096 { user_space.unmap(framebuffer_virtual + at) }
			return -12
		}
		mapped += 4096
	}
	framebuffer_length = length
	video.claim()
	return int(framebuffer_virtual)
}

fn framebuffer_unmap(address u32, length u32) int {
	if framebuffer_length == 0 || address != framebuffer_virtual
		|| (length != framebuffer_length && length != ((framebuffer_length + 4095) & ~u32(4095))) { return -22 }
	for at := u32(0); at < framebuffer_length; at += 4096 {
		if !user_space.unmap(framebuffer_virtual + at) { halt(c'framebuffer mapping ownership') }
	}
	framebuffer_length = 0
	video.release()
	return 0
}
