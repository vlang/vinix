// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

fn screenshot(mut child os.Process, path string) ![]u8 {
	if os.exists(path) { os.rm(path)! }
	child.stdin_write('screendump "${path}"\n')
	deadline := time.now().add(3 * time.second)
	for time.now() < deadline {
		if os.exists(path) {
			data := os.read_bytes(path)!
			validate_screen(data) or { time.sleep(10 * time.millisecond); continue }
			return data
		}
		time.sleep(10 * time.millisecond)
	}
	return error('Screenshot failed framebuffer validation: ${path}')
}

fn exercise_usb(mut child os.Process, output string, log_path string, graphics bool) ! {
	before := os.read_file(log_path)!
	if !before.contains('USB keyboard ready') || !before.contains('USB mouse ready') {
		return error('USB boot devices were not enumerated')
	}
	// HMP feeds QEMU's HID devices; no serial input is involved in this command.
	for key in ['e', 'c', 'h', 'o', 'spc', 'u', 's', 'b', 'minus', 'a', 'x', 'backspace', 'shift-z', 'ret'] {
		child.stdin_write('sendkey ${key} 30\n')
		time.sleep(90 * time.millisecond)
	}
	deadline := time.now().add(3 * time.second)
	mut typed := false
	for time.now() < deadline {
		log := os.read_file(log_path)!
		if log.len >= before.len && log[before.len..].replace('\r', '').contains('\nusb-aZ\nvinix$ ') {
			typed = true
			break
		}
		time.sleep(10 * time.millisecond)
	}
	if !typed { return error('USB keyboard failed shell typing, shift or backspace') }
	if graphics {
		child.stdin_write('mouse_move 50 30\n')
		time.sleep(150 * time.millisecond)
		data := screenshot(mut child, output + '/usb-pointer.ppm')!
		validate_pointer(data, false)!
		child.stdin_write('mouse_button 1\n')
		time.sleep(150 * time.millisecond)
		pressed := screenshot(mut child, output + '/usb-pressed.ppm')!
		validate_pointer(pressed, true)!
		child.stdin_write('mouse_button 0\n')
		time.sleep(150 * time.millisecond)
		validate_pointer(screenshot(mut child, output + '/usb-released.ppm')!, false)!
	}
	println('PASS USB HID keyboard typing, modifiers and editing' + if graphics { ', mouse movement and buttons' } else { '' })
}
