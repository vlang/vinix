// SPDX-License-Identifier: MIT
module main

import os
import tools.packages.appsdk

fn memo_frame(text string, sequence u64, saved bool) appsdk.WindowFrame {
	return appsdk.WindowFrame{ format: 2, sequence: sequence, title: 'Signed native memo', width: 480, height: 200,
		background: 0xffffff, elements: [
			appsdk.WindowElement{ kind: 'label', id: '', text: 'Memo · 256 UTF-8 bytes · Enter commits the field', x: 16, y: 12, width: 448, height: 28, color: 0x111111, background: 0 },
			appsdk.WindowElement{ kind: 'input', id: 'memo', text: text, x: 16, y: 52, width: 448, height: 36, color: 0x111111, background: 0xf0f2ff },
			appsdk.WindowElement{ kind: 'button', id: 'save', text: 'Save', x: 16, y: 104, width: 120, height: 32, color: 0x111111, background: 0xdfe5ff },
			appsdk.WindowElement{ kind: 'label', id: '', text: if saved { 'Saved in your private application data.' } else { 'Press Save to keep this memo.' }, x: 16, y: 152, width: 448, height: 28, color: 0x111111, background: 0 },
		] }
}

fn save_memo(path string, text string) ! {
	staging := path + '.new'
	defer { unsafe { staging.free() } }
	os.write_file(staging, text)!
	os.rename(staging, path)!
}

fn run() ! {
	mut context := appsdk.load()!
	defer { context.close() }
	if context.kind != 'native' || 'display' !in context.permissions { return error('native display permission is required') }
	path := context.data_directory + '/memo.txt'
	defer { unsafe { path.free() } }
	mut text := if os.exists(path) { os.read_file(path)! } else { ''.clone() }
	defer { unsafe { text.free() } }
	appsdk.validate_window_input(text)!
	mut sequence := u64(1)
	mut saved := true
	for {
		frame := memo_frame(text, sequence, saved)
		appsdk.publish_window_frame(frame) or { unsafe { (&array(&frame.elements)).free() }; return err }
		mut changed := false
		for !changed {
			mut event := appsdk.read_window_event_for(2) or { unsafe { (&array(&frame.elements)).free() }; return err }
			if !frame.accepts(event) { event.close(); continue }
			if event.kind == 'close' {
				event.close()
				unsafe { (&array(&frame.elements)).free() }
				return
			}
			if event.kind == 'text' {
				unsafe { text.free() }
				text = event.text.clone(); saved = false
			} else {
				save_memo(path, text) or { event.close(); unsafe { (&array(&frame.elements)).free() }; return err }
				saved = true
			}
			event.close(); changed = true
		}
		unsafe { (&array(&frame.elements)).free() }
		if sequence == ~u64(0) { return error('window sequence exhausted') }
		sequence++
	}
}

fn main() { run() or { eprintln(err); exit(1) } }
