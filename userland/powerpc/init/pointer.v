// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn pointer_test() {
	fd := C.vinix_user_syscall(5, u32(c'/dev/pointer'), 0x800, 0)
	buffer := u32(unsafe { &response[0] })
	if fd < 0 || C.vinix_user_syscall(3, u32(fd), buffer, 31) != -22
		|| C.vinix_user_syscall(3, u32(fd), 0x02000000, 36) != -14
		|| C.vinix_user_syscall(141, u32(fd), buffer, 1024) != -20
		|| C.vinix_user_syscall(54, u32(fd), 0x1234, buffer) != -25
		|| C.vinix_user_syscall(3, u32(fd), buffer, 32) != 32 { failed_check() }
	x := word(0); y := word(4); max_x := word(8); max_y := word(12)
	if max_x == 0 || max_y == 0 { close(fd); print_text(c'pointer: no mouse\n'); return }
	print_text(c'pointer: ready; move and click, then press Enter\n')
	mut key := u8(0)
	for {
		// Poll USB via stdin without consuming /dev/pointer edge state.
		if C.vinix_user_syscall(3, 0, u32(unsafe { &key }), 1) == 1 && (key == 10 || key == 13) { break }
	}
	if C.vinix_user_syscall(3, u32(fd), buffer, 31) != -22
		|| C.vinix_user_syscall(3, u32(fd), 0x02000000, 36) != -14
		|| C.vinix_user_syscall(3, u32(fd), buffer, 36) != 36 { failed_check() }
	print_text(c'pointer: x='); number(word(0)); print_text(c' y='); number(word(4))
	print_text(c' buttons='); number(word(16)); print_text(c' pressed='); number(word(20))
	print_text(c' released='); number(word(24)); print_text(c'\n')
	// Validate the packet invariants without assuming an interactive user's motion.
	if word(0) > max_x || word(4) > max_y || word(8) != max_x || word(12) != max_y
		|| word(28) != 0 || word(32) != 0 || x > max_x || y > max_y { failed_check() }
	if C.vinix_user_syscall(3, u32(fd), buffer, 32) != 32 || word(20) != 0 || word(24) != 0 { failed_check() }
	close(fd)
}
