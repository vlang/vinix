// SPDX-License-Identifier: MIT
module main

import os
import tools.packages.appsdk

fn publish(count int, sequence u64) ! {
	number := count.str()
	label := 'Count: ' + number
	frame := appsdk.WindowFrame{ sequence: sequence, title: 'Signed native counter', width: 320, height: 160,
		background: 0xffffff, elements: [
			appsdk.WindowElement{ kind: 'label', id: '', text: label, x: 16, y: 16, width: 288, height: 28, color: 0x111111, background: 0 },
			appsdk.WindowElement{ kind: 'button', id: 'increase', text: 'Increase', x: 16, y: 60, width: 128, height: 32, color: 0x111111, background: 0xdfe5ff },
		] }
	defer { unsafe { number.free(); label.free(); (&array(&frame.elements)).free() } }
	appsdk.publish_window_frame(frame)!
}

fn run() ! {
	mut context := appsdk.load()!
	defer { context.close() }
	if context.kind != 'native' || 'display' !in context.permissions { return error('native display permission is required') }
	path := context.data_directory + '/counter.txt'
	defer { unsafe { path.free() } }
	mut count := 0
	if os.exists(path) {
		text := os.read_file(path)!
		defer { unsafe { text.free() } }
		if text.len == 0 || text.len > 6 || !text.bytes().all(it >= `0` && it <= `9`) { return error('saved counter data is invalid') }
		count = text.int()
	}
	mut sequence := u64(1)
	publish(count, sequence)!
	for {
		mut event := appsdk.read_window_event()!
		if event.kind == 'close' { event.close(); break }
		if event.sequence == sequence && event.id == 'increase' && count < 999999 {
			count++; sequence++
			event.close()
			publish(count, sequence)!
		} else { event.close() }
	}
	number := count.str()
	defer { unsafe { number.free() } }
	os.write_file(path, number)!
}

fn main() { run() or { eprintln(err); exit(1) } }
