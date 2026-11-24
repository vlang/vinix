// SPDX-License-Identifier: MIT
module appsdk

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn test_window_decoders_retire_frames_events_and_partial_records() {
	input := r'{"kind":"input","id":"memo","text":"\u00e9\ud83d\ude80","x":12,"y":12,"width":280,"height":32,"color":0,"background":16777215}'
	button := '{"kind":"button","id":"save","text":"Save","x":12,"y":56,"width":120,"height":28,"color":0,"background":0}'
	frame_json := '{"format":2,"sequence":7,"title":"Memo","width":320,"height":160,"background":0,"elements":[${input},${button}]}'
	click_json := '{"format":1,"kind":"click","sequence":7,"id":"save"}'
	text_json := '{"format":2,"kind":"text","sequence":7,"id":"memo","text":""}'
	invalid_frames := [frame_json.replace('"x":12', '"x":-1'), frame_json.replace('"width":320', '"width":0'),
		frame_json.replace('"id":"save"', '"id":"memo"'), frame_json[..frame_json.len - 2]]
	invalid_events := [text_json.replace('"text":""', r'"text":"\ud800"'),
		text_json.replace('"sequence":7', '"sequence":0'), click_json + '{}']
	defer {
		unsafe {
			frame_json.free()
			for text in invalid_frames { text.free() }
			for text in invalid_events { text.free() }
			(&array(&invalid_frames)).free()
			(&array(&invalid_events)).free()
		}
	}
	mut frame := &WindowFrame{}
	mut event := &WindowEvent{}
	defer { unsafe { free(frame); free(event) } }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 256 {
		unsafe { *frame = decode_window_frame(frame_json)! }
		assert frame.sequence == 7 && frame.title == 'Memo' && frame.elements.len == 2
		assert frame.elements[0].text == 'é🚀'
		for text in [click_json, text_json]! {
			unsafe { *event = decode_window_event(text)! }
			assert event.sequence == 7
			assert frame.accepts(event) == (text == text_json)
			assert event.id == if text == click_json { 'save' } else { 'memo' }
			event.close()
		}
		frame.close()
		for text in invalid_frames {
			mut refused := false
			decode_window_frame(text) or { refused = true; unsafe { err.free() } }
			assert refused
		}
		for text in invalid_events {
			mut refused := false
			decode_window_event(text) or { refused = true; unsafe { err.free() } }
			assert refused
		}
	}
	$if track_heap ? {
		retained := C.vinix_heap_end()
		assert retained == 0, 'native window decoding retained ${retained} bytes'
		println('Native window decoding: 256 frame, event and partial-record cycles retained zero tracked bytes')
	}
}
