// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.appsdk
import os

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn main() {
	frame := appsdk.WindowFrame{ sequence: 1, title: 'Counter', width: 320, height: 160, background: 0xffffff,
		elements: [appsdk.WindowElement{ kind: 'button', id: 'increase', text: 'Increase', x: 12, y: 12, width: 128, height: 28, color: 0, background: 0xe0e0ff }] }
	text := frame.encode()!
	invalid := text.replace('"width":320', '"width":2049')
	event_text := appsdk.WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }.encode()!
	assert os.setenv('VINIX_WINDOW_PROTOCOL', '1', true) == 0
	saved_stdout := C.dup(1)
	sink := C.open(c'/dev/null', C.O_WRONLY)
	assert saved_stdout >= 0 && sink >= 0 && C.dup2(sink, 1) == 1
	C.close(sink)
	defer { unsafe { text.free(); invalid.free(); event_text.free(); (&array(&frame.elements)).free() } }
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			mut decoded := appsdk.decode_window_frame(text)!
			encoded := decoded.encode()!
			assert encoded == text
			unsafe { encoded.free() }
			decoded.close(); decoded.close()
			mut event := appsdk.decode_window_event(event_text)!
			encoded_event := event.encode()!
			unsafe { encoded_event.free() }
			event.close()
			appsdk.publish_window_frame(frame)!
			mut refused := false
			appsdk.decode_window_frame(invalid) or { refused = true; unsafe { err.free() } }
			assert refused
		}
	}
	kept := C.vinix_heap_end()
	assert C.dup2(saved_stdout, 1) == 1
	C.close(saved_stdout)
	assert kept == 0, 'native window SDK retained ${kept} bytes'
	println('Native window SDK: 1000 frame/event decode, encode, validation refusal and retirement cycles retain zero tracked bytes')
}
