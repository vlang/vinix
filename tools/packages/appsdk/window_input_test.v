// SPDX-License-Identifier: MIT
module appsdk

import os

fn input_fixture() WindowFrame {
	return WindowFrame{ format: 2, sequence: 7, title: 'Memo', width: 320, height: 160,
		elements: [WindowElement{ kind: 'input', id: 'memo', text: 'é🚀', x: 12, y: 12,
			width: 280, height: 32, color: 0, background: 0xffffff },
			WindowElement{ kind: 'button', id: 'save', text: 'Save', x: 12, y: 60, width: 120, height: 32, color: 0, background: 0xe0e0ff }] }
}

fn test_native_text_protocol_roundtrip_and_frame_admission() {
	frame := input_fixture()
	encoded := frame.encode()!
	mut decoded := decode_window_frame(encoded)!
	assert decoded == frame
	decoded.close()
	unsafe { encoded.free(); (&array(&frame.elements)).free() }
	for text in ['', 'é🚀', r'quoted " text \ $literal; $(command)', 'x'.repeat(window_input_limit)] {
		event := WindowEvent{ format: 2, kind: 'text', sequence: 7, id: 'memo', text: text }
		value := event.encode()!
		assert value.contains('"text":') && value.len < window_text_event_limit
		mut parsed := decode_window_event(value)!
		assert parsed == event
		parsed.close(); parsed.close()
		unsafe { value.free() }
	}
	owned_frame := input_fixture()
	for event in [WindowEvent{ format: 2, kind: 'text', sequence: 7, id: 'memo', text: 'replacement' },
		WindowEvent{ format: 2, kind: 'click', sequence: 7, id: 'save' },
		WindowEvent{ format: 2, kind: 'close', sequence: 7 }, WindowEvent{ format: 2, kind: 'close' }] {
		assert owned_frame.accepts(event)
	}
	for event in [WindowEvent{ format: 1, kind: 'click', sequence: 7, id: 'save' },
		WindowEvent{ format: 2, kind: 'text', sequence: 6, id: 'memo', text: 'stale' },
		WindowEvent{ format: 2, kind: 'text', sequence: 7, id: 'save', text: 'wrong kind' },
		WindowEvent{ format: 2, kind: 'click', sequence: 7, id: 'memo' },
		WindowEvent{ format: 2, kind: 'text', sequence: 7, id: 'software.confirm' },
		WindowEvent{ format: 2, kind: 'close', sequence: 6 }] {
		assert !owned_frame.accepts(event)
	}
	unsafe { (&array(&owned_frame.elements)).free() }
}

fn test_native_text_schema_and_protocol_one_compatibility() {
	legacy := WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }.encode()!
	assert legacy == '{"format":1,"kind":"click","sequence":1,"id":"increase"}'
	unsafe { legacy.free() }
	frame := input_fixture()
	for invalid in [WindowFrame{ ...frame, format: 1 }, WindowFrame{ ...frame, elements: [frame.elements[0], frame.elements[0]] },
		WindowFrame{ ...frame, elements: [frame.elements[0], WindowElement{ ...frame.elements[1], id: 'memo' }] },
		WindowFrame{ ...frame, elements: [WindowElement{ ...frame.elements[0], text: 'x'.repeat(window_input_limit + 1) }] }] {
		mut refused := false
		invalid.validate() or { refused = true; unsafe { err.free() } }
		assert refused
	}
	unsafe { (&array(&frame.elements)).free() }
	for invalid in ['{"format":1,"kind":"text","sequence":1,"id":"memo"}',
		'{"format":1,"kind":"close","sequence":0,"id":"","text":""}',
		'{"format":2,"kind":"text","sequence":1,"id":"memo"}',
		'{"format":2,"kind":"text","sequence":0,"id":"memo","text":""}',
		'{"format":2,"kind":"click","sequence":1,"id":"save","text":"wrong"}',
		'{"format":2,"kind":"text","sequence":1,"id":"memo","text":"a","te\\u0078t":"b"}',
		'{"format":2,"kind":"text","sequence":1,"id":"memo","text":"\\n"}',
		'{"format":2,"kind":"text","sequence":1,"id":"memo","text":"\\ud800"}',
		'{"format":2,"kind":"text","sequence":1,"id":"memo","text":"' + 'x'.repeat(window_input_limit + 1) + '"}',
		' '.repeat(window_event_limit) + '{"format":1,"kind":"close","sequence":0,"id":""}'] {
		mut refused := false
		decode_window_event(invalid) or { refused = true; unsafe { err.free() } }
		assert refused
	}
}

fn test_native_text_reader_negotiates_versions_and_closes_on_eof() {
	saved := C.dup(0)
	assert saved >= 0
	mut pipe := [2]i32{} // pipe(2) writes C int descriptors, independent of V int width
	assert C.pipe(&pipe[0]) == 0
	encoded := WindowEvent{ format: 2, kind: 'text', sequence: 7, id: 'memo' }.encode()!
	line := encoded + '\n'
	assert C.write(pipe[1], line.str, usize(line.len)) == line.len
	C.close(pipe[1])
	assert C.dup2(pipe[0], 0) == 0
	if pipe[0] != 0 { C.close(pipe[0]) }
	defer { C.dup2(saved, 0); C.close(saved) }
	mut event := read_window_event_for(2)!
	assert event.kind == 'text' && event.text == '' && event.sequence == 7
	event.close()
	mut eof := read_window_event_for(2)!
	assert eof.format == 2 && eof.kind == 'close' && eof.sequence == 0
	eof.close()
	unsafe { encoded.free(); line.free() }
	assert C.pipe(&pipe[0]) == 0
	legacy := WindowEvent{ kind: 'close' }.encode()!
	legacy_line := legacy + '\n'
	assert C.write(pipe[1], legacy_line.str, usize(legacy_line.len)) == legacy_line.len
	C.close(pipe[1])
	assert C.dup2(pipe[0], 0) == 0
	if pipe[0] != 0 { C.close(pipe[0]) }
	mut mismatch := false
	read_window_event_for(2) or { mismatch = true; unsafe { err.free() } }
	assert mismatch
	unsafe { legacy.free(); legacy_line.free() }
	assert os.setenv('VINIX_WINDOW_PROTOCOL', '1', true) == 0
	frame := input_fixture()
	mut refused := false
	publish_window_frame(frame) or { refused = true; unsafe { err.free() } }
	assert refused
	unsafe { (&array(&frame.elements)).free() }
}
