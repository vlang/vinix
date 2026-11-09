// SPDX-License-Identifier: GPL-2.0-or-later
module main

// PPC bootstrap ABI: atomically restrict a computational app to its two
// inherited protocol pipe ends, standard streams, memory and clock services.
// This is irreversible and does not pretend to implement pledge/capabilities.
fn sys_app_sandbox(input u32, output u32) int {
	if current_process == 0 || input < 3 || output < 3 || input >= 64 || output >= 64
		|| input == output || !descriptors[input].used || !descriptors[output].used
		|| descriptors[input].pipe == 0 || descriptors[output].pipe == 0
		|| descriptors[input].writable || !descriptors[output].writable { return -22 }
	if framebuffer_length != 0 { return -16 }
	for fd in 3 .. 64 { if u32(fd) != input && u32(fd) != output && descriptors[fd].used { sys_close(u32(fd)) } }
	processes[current_process].sandbox = true
	return 0
}

fn sandbox_allows(number u32) bool {
	return number in [u32(1), 3, 4, 6, 20, 24, 45, 47, 49, 50, 55, 64, 91, 116,
		122, 145, 146, 158, 162, 167, 175, 192, 204, 207, 223, 232, 234, 359, 403, 436]!
}
