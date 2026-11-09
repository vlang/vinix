// SPDX-License-Identifier: GPL-2.0-or-later
module main

__global pcm [192000]u8

fn tone() {
	fd := C.vinix_user_syscall(5, u32(c'/dev/audio'), 1, 0)
	if fd < 0 { print_text(c'audio: no supported USB output\n'); return }
	defer { close(fd) }
	if C.vinix_user_syscall(4, u32(fd), 0x02000000, 192) != -14
		|| C.vinix_user_syscall(4, u32(fd), u32(unsafe { &pcm[0] }), 191) != -22
		|| C.vinix_user_syscall(4, u32(fd), u32(unsafe { &pcm[0] }), 192192) != -22 { failed_check() }
	// Distinct channel frequencies expose channel swaps and sample byte order.
	for sample := u32(0); sample < 48000; sample++ {
		left := u16(i16(if sample % 48 < 24 { 4096 } else { -4096 }))
		right := u16(i16(if sample % 96 < 48 { 2048 } else { -2048 }))
		pcm[sample * 4] = u8(left); pcm[sample * 4 + 1] = u8(left >> 8)
		pcm[sample * 4 + 2] = u8(right); pcm[sample * 4 + 3] = u8(right >> 8)
	}
	result := C.vinix_user_syscall(4, u32(fd), u32(unsafe { &pcm[0] }), 192000)
	if result == 192000 { print_text(c'audio: played 48000 stereo frames\n') }
	else { print_text(c'audio: playback failed\n') }
}
