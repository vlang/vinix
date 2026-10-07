// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

const demo_path = '/usr/share/games/n64/paddle.z64'
const control_ids = ['open', 'pause', 'reset', 'up', 'down', 'left', 'right', 'start', 'z',
	'l', 'r', 'a', 'b', 'c_up', 'c_down', 'c_left', 'c_right', 'stick_up', 'stick_down',
	'stick_left', 'stick_right']
const control_names = ['Open game', 'Pause', 'Reset', 'Up', 'Down', 'Left', 'Right', 'Start',
	'Z', 'L', 'R', 'A', 'B', 'C Up', 'C Down', 'C Left', 'C Right', 'Stick U', 'Stick D',
	'Stick L', 'Stick R']
// Keep this order in sync with the core adapter's controller mask.
const joy_ids = ['a', 'b', 'z', 'start', 'up', 'down', 'left', 'right', 'c_up', 'c_down',
	'c_left', 'c_right', 'l', 'r', 'stick_up', 'stick_down', 'stick_left', 'stick_right']

__global opening = false
__global paused_before_open = false
__global path_text = ''
__global app_width = 800
__global app_height = 680

fn control_rect(index int) (int, int, int, int) {
	if index < 3 { return 8 + index * 120, app_height - 120, 112, 30 }
	if index < 11 {
		width := (app_width - 16) / 8
		return 8 + (index - 3) * width, app_height - 82, width - 6, 30
	}
	width := (app_width - 16) / 10
	return 8 + (index - 11) * width, app_height - 44, width - 6, 30
}

fn ui_build(mut out []u8) {
	encode_element(mut out, 0, 0, 0, f64(app_width), f64(app_height), '', '', '', control_ids.len + 2)
	path := 'vinix-surface:${emulator.surface_path}'
	defer { unsafe { path.free() } }
	// Scale the original 4:3 framebuffer uniformly, with dark letterboxing.
	available_height := app_height - 150
	width := if app_width * 3 <= available_height * 4 {
		app_width
	} else {
		available_height * 4 / 3
	}
	height := width * 3 / 4
	encode_element(mut out, 3, f64((app_width - width) / 2), f64((available_height - height) / 2), f64(width), f64(height), '', '', path, 0)
	label := if opening {
		'Game path: ${path_text}_ (Enter to open, Esc to cancel)'
	} else {
		emulator.status.clone()
	}
	defer { unsafe { label.free() } }
	encode_element(mut out, 2, 8, f64(app_height - 148), f64(app_width - 16), 22, '', label, '', 0)
	for index, id in control_ids {
		x, y, button_width, button_height := control_rect(index)
		text := if id == 'pause' && emulator.paused { 'Resume' } else { control_names[index] }
		encode_element(mut out, 4, f64(x), f64(y), f64(button_width), f64(button_height), id, text, '', 0)
	}
}

fn action(id string) {
	name := if id.starts_with('n64.') { id[4..] } else { id }
	defer { if name != id { unsafe { name.free() } } }
	match name {
		'open' {
			if !opening { paused_before_open = emulator.paused }
			opening = true
			emulator.paused = true
			emulator.buttons = 0
			emulator.pulse = 0
			emulator.pulse_frames = 0
			unsafe { path_text.free() }
			path_text = ''
		}
		'pause' {
			emulator.paused = !emulator.paused
			emulator.buttons = 0
			emulator.pulse = 0
			emulator.pulse_frames = 0
		}
		'reset' {
			if emulator.loaded {
				game_save()
				if !emulator_reset() {
					emulator.paused = true
					return
				}
				emulator.frames = 0
				emulator.paused = false
				emulator.buttons = 0
				emulator.pulse = 0
				emulator.pulse_frames = 0
			}
		}
		else {
			for index, button in joy_ids {
				if name == button {
					if emulator.buttons & (u32(1) << index) == 0 {
						emulator.pulse |= u32(1) << index
						emulator.pulse_frames = 12
					}
					break
				}
			}
		}
	}
}

fn keyboard(text string) {
	if opening {
		for character in text {
			if character == 27 {
				opening = false
				emulator.paused = paused_before_open
				break
			}
			if character == 10 || character == 13 {
				if !load_game(path_text) {
					emulator.paused = paused_before_open
				}
				opening = false
				break
			}
			if character == 8 || character == 127 {
				if path_text.len > 0 {
					new_text := path_text[..path_text.len - 1]
					unsafe { path_text.free() }
					path_text = new_text
				}
			} else if character >= 32 && path_text.len < 4095 {
				character_text := character.ascii_str()
				new_text := path_text + character_text
				unsafe { character_text.free() }
				unsafe { path_text.free() }
				path_text = new_text
			}
		}
		return
	}
	if text in ['\x1b[A', 'up'] {
		action('up')
		return
	}
	if text in ['\x1b[B', 'down'] {
		action('down')
		return
	}
	if text in ['\x1b[D', 'left'] {
		action('left')
		return
	}
	if text in ['\x1b[C', 'right'] {
		action('right')
		return
	}
	mut index := 0
	for index < text.len {
		character := text[index]
		index++
		if character == 27 && index + 1 < text.len && text[index] == `[` {
			match text[index + 1] {
				`A` { action('up') }
				`B` { action('down') }
				`C` { action('right') }
				`D` { action('left') }
				else {}
			}
			index += 2
			continue
		}
		match character {
			`z` { action('a') }
			`x` { action('b') }
			`c` { action('z') }
			`q` { action('l') }
			`e` { action('r') }
			`i` { action('c_up') }
			`k` { action('c_down') }
			`j` { action('c_left') }
			`l` { action('c_right') }
			`w` { action('stick_up') }
			`s` { action('stick_down') }
			`a` { action('stick_left') }
			`d` { action('stick_right') }
			10, 13 { action('start') }
			`p`, 27 { action('pause') }
			else {}
		}
	}
}

fn pointer(payload []u8) {
	if payload.len != 28 { return }
	phase := wire_number(payload, 0)
	if phase == 2 {
		emulator.buttons = 0
		return
	}
	if phase != 1 { return }
	x := int(i32(wire_number(payload, 12)))
	y := int(i32(wire_number(payload, 16)))
	for index, id in control_ids {
		left, top, width, height := control_rect(index)
		if x >= left && x < left + width && y >= top && y < top + height {
			// The desktop also sends toolbar clicks through command 2. Only
			// joypad buttons use raw pointer down/up for continuous holds.
			if index >= 3 {
				for button, name in joy_ids {
					if name == id {
						emulator.buttons |= u32(1) << button
						break
					}
				}
			}
			break
		}
	}
}

fn serve(request int, response int) ! {
	mut state := []u8{len: 116}
	state[36] = 1
	state[48] = 1
	mut out := []u8{cap: 16384}
	unsafe { out.flags |= .noslices }
	mut header := []u8{len: 136}
	defer { unsafe {
		state.free()
		out.free()
		header.free()
	}
	 }
	if !ui_reply(response, state, out) { return error('desktop handshake failed') }
	for wire_io(request, header.data, header.len, false) {
		if wire_number(header, 0) != 0x56415050 || header[4] != 10 {
			return error('unsupported desktop protocol')
		}
		length := int(wire_number(header, 132))
		if length < 0 || length > 65536 { return error('invalid desktop payload') }
		mut payload := []u8{len: length}
		if length > 0 && !wire_io(request, payload.data, length, false) {
			unsafe { payload.free() }
			return error('short desktop payload')
		}
		C.memcpy(state.data, unsafe { &header[16] }, 116)
		out.clear()
		command := header[5]
		match command {
			1 {
				width := int(wire_number(header, 8))
				height := int(wire_number(header, 12))
				if width < 400 || width > 8192 || height < 300 || height > 8192 {
					unsafe { payload.free() }
					return error('invalid window size')
				}
				app_width = width
				app_height = height
				ui_build(mut out)
			}
			2 { action(unsafe { tos(payload.data, payload.len) }) }
			3, 7 { keyboard(unsafe { tos(payload.data, payload.len) }) }
			4 {
				emulator_tick()
				out << u8(1)
			}
			5 { pointer(payload) }
			6 {}
			8 { out << u8(1) }
			else {
				unsafe { payload.free() }
				return error('unsupported desktop command')
			}
		}
		unsafe { payload.free() }
		if !ui_reply(response, state, out) || command == 6 { break }
	}
}

fn main() {
	mut game := demo_path
	for argument in os.args[1..] {
		if argument in ['--help', '-h'] {
			println('usage: vinix-n64 [--mute] [N64 Z64/V64/N64 cartridge]\nLaunch from the Vinix desktop. Open game accepts a file path.\nArrows: D-pad; WASD: analog stick; Z/X: A/B; C: Z trigger;\nEnter: Start; Q/E: L/R; I/K/J/L: C buttons; P or Esc: Pause.\nSaves: ~/.local/share/vinix/n64/saves. Cartridge games need no external BIOS.')
			return
		}
		if argument == '--mute' {
			emulator.muted = true
		} else if argument.starts_with('--') {
			eprintln('N64: unknown option: ${argument}')
			exit(2)
		} else {
			game = argument
		}
	}
	request := os.getenv('VINIX_REQUEST_FD').int()
	response := os.getenv('VINIX_RESPONSE_FD').int()
	if request < 3 || response < 3 || request == response {
		eprintln('N64: launch from the Vinix desktop')
		exit(2)
	}
	emulator_init() or {
		emulator_close()
		eprintln('N64: ${err}')
		exit(1)
	}
	load_game(game)
	serve(request, response) or {
		emulator_close()
		eprintln('N64: ${err}')
		exit(1)
	}
	emulator_close()
	C.close(request)
	C.close(response)
}
