// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.mmio

fn C.vinix_user_syscall6(number u32, a u32, b u32, c u32, d u32, e u32, f u32) i32

asm ppc raw {
	".pushsection .text.vinix_user_syscall6,\"ax\"\n.balign 4\n"
	".globl vinix_user_syscall6\nvinix_user_syscall6:\n"
	"mr 0,3\nmr 3,4\nmr 4,5\nmr 5,6\nmr 6,7\nmr 7,8\nmr 8,9\nsc\nbns 1f\nneg 3,3\n1: blr\n.popsection\n"
}

fn map_screen(fd i32, size u32, protection u32) i32 {
	return C.vinix_user_syscall6(192, 0, size, protection, 1, u32(fd), 0)
}

fn framebuffer_test() {
	fd := C.vinix_user_syscall(5, u32(c'/dev/fb0'), 2, 0)
	if fd < 0 { print_text(c'framebuffer: unavailable\n'); return }
	buffer := u32(unsafe { &response[0] })
	response[160] = 0xa5
	if C.vinix_user_syscall(54, u32(fd), 0x4600, buffer) != 0 || response[160] != 0xa5 { failed_check() }
	w := word(0); h := word(4); bits := word(24)
	red := word(32); green := word(44); channel := word(36)
	if w < 320 || w > 1920 || h < 240 || h > 1200 || (bits != 16 && bits != 32)
		|| word(8) != w || word(12) != h || word(56) != 0 || word(60) != channel
		|| word(48) != channel || green != channel || red != 2 * channel { failed_check() }
	response[68] = 0x5a
	if C.vinix_user_syscall(54, u32(fd), 0x4602, buffer) != 0 || response[68] != 0x5a { failed_check() }
	size := word(20); pitch := word(44)
	if size != pitch * h || pitch < w * (bits / 8) || word(32) != 2 { failed_check() }
	if C.vinix_user_syscall(54, u32(fd), 0x4600, 0x02000000) != -14
		|| C.vinix_user_syscall(54, u32(fd), 0x4602, 0x5fffffff) != -14
		|| C.vinix_user_syscall(54, u32(fd), 0x4601, buffer) != -25
		|| C.vinix_user_syscall(141, u32(fd), buffer, 1024) != -20
		|| map_screen(fd, size + 4096, 3) != -22 || map_screen(fd, size, 7) != -22
		|| map_screen(16, size, 3) != -9
		|| C.vinix_user_syscall6(192, 0, size, 3, 1, u32(fd), 1) != -22
		|| C.vinix_user_syscall6(192, 0, size, 3, 2, u32(fd), 0) != -22 { failed_check() }
	ro := open(c'/dev/fb0')
	if ro < 0 || map_screen(ro, size, 3) != -13 { failed_check() }
	readonly := map_screen(ro, size, 1)
	if readonly <= 0 || C.vinix_user_syscall(3, 0, u32(readonly), 1) != -14
		|| C.vinix_user_syscall(91, u32(readonly), size, 0) != 0 { failed_check() }
	close(ro)
	for _ in 0 .. 16 {
		mapped := map_screen(fd, size, 3)
		if mapped <= 0 || map_screen(fd, size, 3) != -16 { failed_check() }
		if C.vinix_user_syscall(91, u32(mapped) + 4096, size, 0) != -22
			|| C.vinix_user_syscall(91, u32(mapped), size - 4096, 0) != -22 { failed_check() }
		for page := u32(0); page < 4; page++ {
			address := u32(mapped) + page * 4096
			mmio.write_be32(address, 0x12345678 ^ page)
			if mmio.read_be32(address) != 0x12345678 ^ page { failed_check() }
		}
		if C.vinix_user_syscall(91, u32(mapped), size, 0) != 0
			|| C.vinix_user_syscall(4, 1, u32(mapped), 1) != -14 { failed_check() }
	}
	base := map_screen(fd, size, 3)
	if base <= 0 { failed_check() }
	close(fd) // mappings remain valid after descriptor close
	for y := u32(0); y < h; y++ {
		for x := u32(0); x < w; x++ {
			r := x * 255 / (w - 1); g := y * 255 / (h - 1); b := (x ^ y) & 255
			pixel := (r >> (8 - channel)) << red | (g >> (8 - channel)) << green | (b >> (8 - channel))
			address := u32(base) + y * pitch + x * (bits / 8)
			if bits == 16 { mmio.write_be16(address, pixel) } else { mmio.write_be32(address, pixel) }
		}
	}
	print_text(c'framebuffer: mapped pattern; press Enter to return\n')
	mut key := u8(0)
	for {
		if C.vinix_user_syscall(3, 0, u32(unsafe { &key }), 1) == 1 && (key == 10 || key == 13) { break }
	}
	if C.vinix_user_syscall(91, u32(base), size, 0) != 0 { failed_check() }
	print_text(c'framebuffer: released; mapping checks passed\n')
}
