// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import net.unix

fn exercise_pointer(mut child os.Process, mut console unix.StreamConn, log_path string) !string {
	before := os.read_file(log_path)!
	console.write_string('pointertest\n')!
	deadline := time.now().add(3 * time.second)
	mut ready := false
	for time.now() < deadline {
		log := os.read_file(log_path)!
		if log.len >= before.len && log[before.len..].contains('pointer: ready;') { ready = true; break }
		time.sleep(10 * time.millisecond)
	}
	if !ready { return error('Userspace pointer test did not start') }
	child.stdin_write('mouse_move 7 -4\n')
	time.sleep(100 * time.millisecond)
	child.stdin_write('mouse_button 1\n')
	time.sleep(100 * time.millisecond)
	child.stdin_write('mouse_button 0\n')
	time.sleep(100 * time.millisecond)
	result := shell_command(mut console, log_path, '')!
	if !result.contains('pointer: x=457 y=326 buttons=0 pressed=1 released=1') {
		return error('Userspace pointer lost position, button level or inter-read edges: ${result}')
	}
	println('PASS userspace pointer: coordinates, short reads, click edges and edge consumption')
	return result
}
