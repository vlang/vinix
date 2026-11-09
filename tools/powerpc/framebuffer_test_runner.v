// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import net.unix

fn exercise_framebuffer(mut child os.Process, mut console unix.StreamConn, output string, log_path string) !string {
	before := os.read_file(log_path)!
	console.write_string('fbtest\n')!
	deadline := time.now().add(20 * time.second)
	mut ready := false
	for time.now() < deadline {
		log := os.read_file(log_path)!
		if log.len < before.len || log[before.len..].contains('FAIL') || log[before.len..].contains('PANIC') { return error('Framebuffer guest failure') }
		if log[before.len..].contains('framebuffer: mapped pattern; press Enter to return') { ready = true; break }
		time.sleep(10 * time.millisecond)
	}
	if !ready { return error('Userspace framebuffer mapping timed out') }
	image := screen_dump(mut child, output + '/userspace-framebuffer.ppm')!
	screen := screen_header(image)!
	// Check every pixel independently, including page boundaries and the edges.
	for y in 0 .. screen.height {
		for x in 0 .. screen.width {
			r := u32(x * 255 / (screen.width - 1))
			g := u32(y * 255 / (screen.height - 1))
			b := u32((x ^ y) & 255)
			expected := screen_color(r << 16 | g << 8 | b)
			at := screen.offset + (y * screen.width + x) * 3
			actual := u32(image[at]) << 16 | u32(image[at + 1]) << 8 | image[at + 2]
			if actual != expected { return error('Userspace framebuffer mismatch at ${x},${y}') }
		}
	}
	result := shell_command(mut console, log_path, '')!
	if !result.contains('framebuffer: released; mapping checks passed') { return error('Framebuffer was not released') }
	screenshot(mut child, output + '/framebuffer-console-restored.ppm')!
	println('PASS protected userspace framebuffer: full image, mapping bounds, reuse and console restoration')
	return 'fbtest: checked entire userspace image\n' + result
}
