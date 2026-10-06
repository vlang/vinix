// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

const demo_path = '/usr/share/games/ps1/tetrade.exe'
const control_ids = ['open', 'pause', 'reset', 'up', 'down', 'left', 'right', 'select', 'start',
	'l1', 'r1', 'cross', 'circle', 'square', 'triangle', 'l2', 'r2']
const control_names = ['Open game', 'Pause', 'Reset', 'Up', 'Down', 'Left', 'Right', 'Select',
	'Start', 'L1', 'R1', 'Cross', 'Circle', 'Square', 'Triangle', 'L2', 'R2']
const joy_ids = ['cross', 'square', 'select', 'start', 'up', 'down', 'left', 'right', 'circle',
	'triangle', 'l1', 'r1', 'l2', 'r2', 'l3', 'r3']

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
	width := (app_width - 16) / 6
	return 8 + (index - 11) * width, app_height - 44, width - 6, 30
}

fn ui_build(mut out []u8) {
	encode_element(mut out, 0, 0, 0, f64(app_width), f64(app_height), '', '', '', 19)
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
	name := if id.starts_with('ps1.') { id[4..] } else { id }
	defer { if name != id { unsafe { name.free() } } }
	match name {
		'open' {
			if !opening { paused_before_open = emulator.paused }
			opening = true
			emulator.paused = true
			emulator.buttons = 0
			unsafe { path_text.free() }
			path_text = ''
		}
		'pause' {
			emulator.paused = !emulator.paused
			emulator.buttons = 0
			emulator.pulse = 0
		}
		'reset' {
			if emulator.loaded {
				card_save()
				C.retro_reset()
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
				load_game(path_text) or {
					set_status(err.msg())
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
	if text in ['\x1b[A', 'up', 'w'] {
		action('up')
		return
	}
	if text in ['\x1b[B', 'down', 's'] {
		action('down')
		return
	}
	if text in ['\x1b[D', 'left', 'a'] {
		action('left')
		return
	}
	if text in ['\x1b[C', 'right', 'd'] {
		action('right')
		return
	}
	for character in text {
		match character {
			`z` { action('cross') }
			`x` { action('circle') }
			`c` { action('square') }
			`v` { action('triangle') }
			`q` { action('l1') }
			`e` { action('r1') }
			`1` { action('l2') }
			`3` { action('r2') }
			10, 13 { action('start') }
			9 { action('select') }
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
			println('usage: vinix-ps1 [--mute] [PS1 CUE/BIN/CHD/PBP/EXE/M3U file]\nLaunch from the Vinix desktop. Open game accepts a file path.\nArrows/WASD: D-pad; Z/X/C/V: Cross/Circle/Square/Triangle;\nEnter: Start; Tab: Select; Q/E: L1/R1; 1/3: L2/R2; P: Pause.\nBIOS and memory cards: ~/.local/share/vinix/ps1/{bios,saves}.')
			return
		}
		if argument == '--mute' {
			emulator.muted = true
		} else if argument.starts_with('--') {
			eprintln('PS1: unknown option: ${argument}')
			exit(2)
		} else {
			game = argument
		}
	}
	request := os.getenv('VINIX_REQUEST_FD').int()
	response := os.getenv('VINIX_RESPONSE_FD').int()
	if request < 3 || response < 3 || request == response {
		eprintln('PS1: launch from the Vinix desktop')
		exit(2)
	}
	emulator_init() or {
		emulator_close()
		eprintln('PS1: ${err}')
		exit(1)
	}
	load_game(game) or { set_status(err.msg()) }
	serve(request, response) or {
		emulator_close()
		eprintln('PS1: ${err}')
		exit(1)
	}
	emulator_close()
	C.close(request)
	C.close(response)
}
