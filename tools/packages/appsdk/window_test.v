// SPDX-License-Identifier: MIT
module appsdk

import json2

fn window_fixture() WindowFrame {
	return WindowFrame{ sequence: 1, title: 'Counter', width: 320, height: 200, background: 0xffffff,
		elements: [WindowElement{ kind: 'label', id: '', text: 'Count: 0', x: 12, y: 12, width: 280, height: 24, color: 0x111111, background: 0 },
			WindowElement{ kind: 'button', id: 'increase', text: 'Increase', x: 12, y: 50, width: 120, height: 28, color: 0x111111, background: 0xe0e0ff }] }
}

fn test_native_window_roundtrip_and_owned_retirement() {
	frame := window_fixture()
	text := frame.encode()!
	defer { unsafe { text.free() } }
	for _ in 0 .. 100 {
		mut decoded := decode_window_frame(text)!
		assert decoded == frame
		decoded.close()
		assert decoded.sequence == 0 && decoded.elements.len == 0
	}
	for event in [WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }, WindowEvent{ kind: 'close' }] {
		encoded := event.encode()!
		mut decoded := decode_window_event(encoded)!
		assert decoded == event
		decoded.close()
		unsafe { encoded.free() }
	}
}

fn test_native_window_rejects_unsafe_dimensions_controls_paths_and_versions() {
	frame := window_fixture()
	for invalid in [WindowFrame{ ...frame, format: 3 }, WindowFrame{ ...frame, sequence: 0 },
		WindowFrame{ ...frame, width: 0 }, WindowFrame{ ...frame, height: 2049 },
		WindowFrame{ ...frame, title: 'bad\ncaption' }, WindowFrame{ ...frame, background: 0xffffffff },
		WindowFrame{ ...frame, elements: [WindowElement{ ...frame.elements[0], kind: 'image', text: '/etc/shadow' }] },
		WindowFrame{ ...frame, elements: [WindowElement{ ...frame.elements[1], id: '../software.confirm' }] },
		WindowFrame{ ...frame, elements: [frame.elements[1], frame.elements[1]] },
		WindowFrame{ ...frame, elements: [WindowElement{ ...frame.elements[0], id: 'action' }] },
		WindowFrame{ ...frame, elements: [WindowElement{ ...frame.elements[0], x: 2147483647 }] },
		WindowFrame{ ...frame, elements: []WindowElement{len: 129, init: frame.elements[0]} }] {
		mut refused := false
		decode_window_frame(json2.encode(invalid)) or { refused = true }
		assert refused
	}
	for text in ['{}', '{"format":1}', 'x'.repeat(window_frame_limit + 1)] {
		mut refused := false
		decode_window_frame(text) or { refused = true }
		assert refused
	}
	for invalid in [WindowEvent{ kind: 'exec', sequence: 1, id: 'increase' },
		WindowEvent{ kind: 'click', sequence: 0, id: 'increase' }, WindowEvent{ kind: 'close', id: 'command' },
		WindowEvent{ format: 3, kind: 'close' }] {
		mut refused := false
		decode_window_event(json2.encode(invalid)) or { refused = true }
		assert refused
	}
}

fn test_native_window_json_schema_escapes_and_malformed_partial_retirement() {
	text := window_fixture().encode()!
	defer { unsafe { text.free() } }
	escaped := text.replace('"title":"Counter"', r'"title":"\u00e9\ud83d\ude80"')
	mut decoded := decode_window_frame(escaped)!
	assert decoded.title == 'é🚀'
	decoded.close()
	unsafe { escaped.free() }
	for invalid in [text.replace('"sequence":1', '"sequence":1,"sequenc\\u0065":1'),
		text.replace('"sequence":1', '"sequence":18446744073709551616'),
		text.replace('"sequence":1', '"sequence":-1'), text.replace('"sequence":1', '"sequence":1.0'),
		text.replace('"sequence":1', '"sequence":"1"'), text.replace('"title":"Counter"', r'"title":"\ud800"'),
		text.replace('"title":"Counter"', r'"title":"\udc00"'), text.replace('"title":"Counter"', r'"title":"\u00xz"'),
		text.replace('"title":"Counter"', r'"title":"\q"'), text.replace('"title":"Counter"', '"title":null'),
		text.replace('"width":320', '"width":true'), text.replace('"width":320', '"width":320,"extra":[]'),
		text + '{}', text[..text.len - 1] + ',}', text[..text.len - 5], '{"extra":' + '['.repeat(16) + '0' + ']'.repeat(16) + '}'] {
		mut refused := false
		decode_window_frame(invalid) or { refused = true; unsafe { err.free() } }
		assert refused
		unsafe { invalid.free() }
	}
}
