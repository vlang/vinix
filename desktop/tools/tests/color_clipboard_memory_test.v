// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

// This receiver copies pasted bytes. It keeps neither the clipboard's inline
// storage nor a shortcut parser's temporary string alive after dispatch.
struct ColorClipboardHeapReceiver {
mut:
	paste_calls int
	key_calls int
	events int
	last_paste_event int
	last_key_event int
	pasted [64]u8
	pasted_length int
	typed [64]u8
	typed_length int
}

fn (mut _ ColorClipboardHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }
fn (mut _ ColorClipboardHeapReceiver) handle(_ string) ! {}

fn (mut receiver ColorClipboardHeapReceiver) paste_input(text string) {
	receiver.paste_calls++
	receiver.events++
	receiver.last_paste_event = receiver.events
	receiver.pasted_length = text.len
	for index, byte in text { receiver.pasted[index] = byte }
}

fn (mut receiver ColorClipboardHeapReceiver) key_input(text string) {
	receiver.key_calls++
	receiver.events++
	receiver.last_key_event = receiver.events
	receiver.typed_length = text.len
	for index, byte in text { receiver.typed[index] = byte }
}

fn (receiver &ColorClipboardHeapReceiver) pasted_text() string {
	return unsafe { tos(&receiver.pasted[0], receiver.pasted_length) }
}

fn (receiver &ColorClipboardHeapReceiver) typed_text() string {
	return unsafe { tos(&receiver.typed[0], receiver.typed_length) }
}

fn test_color_clipboard_owned_text_replacement_and_bounds_keep_zero_bytes() {
	mut clipboard := HostClipboard{ configured: true }
	full := '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
	oversize := 'x'.repeat(clipboard_max_bytes + 1)
	defer { unsafe { oversize.free() } }
	C.vinix_heap_begin()
	for index in 0 .. 200 {
		assert clipboard.set_local_text(full) && clipboard.local_length == 64
		owned := color_meter_value_text(0xaabbcc, index % 2 == 0)
		assert clipboard.set_local_text(owned)
		unsafe { owned.free() }
		expected := if index % 2 == 0 { '#AABBCC' } else { 'rgb(170, 187, 204)' }
		assert unsafe { tos(&clipboard.local_bytes[0], clipboard.local_length) } == expected
		assert !clipboard.set_local_text('') && !clipboard.set_local_text(oversize)
		assert clipboard.local_available && clipboard.local_length == expected.len
		assert unsafe { tos(&clipboard.local_bytes[0], clipboard.local_length) } == expected
	}
	assert C.vinix_heap_end() == 0
}

fn test_color_clipboard_complete_guest_shortcuts_dispatch_native_paste_without_retained_bytes() {
	mut receiver := &ColorClipboardHeapReceiver{}
	mut desktop := Desktop{ focus: 71, clipboard: HostClipboard{ configured: true } }
	defer { unsafe { desktop.apps.free() desktop.windows.free() desktop.native_asset_icons.free() free(receiver) } }
	desktop.apps << receiver
	desktop.windows << Window{ id: 71, page: .app, app_index: 0 }
	assert desktop.clipboard.set_local_text('#AABBCC')
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		for chord in ['\x16', key_cmd_v, key_shift_insert]! {
			desktop.dirty = false
			previous := receiver.paste_calls
			remaining := desktop.take_paste_keys(chord)
			assert remaining.len == 0 && receiver.paste_calls == previous + 1
			assert receiver.pasted_text() == '#AABBCC' && receiver.key_calls == 0
			assert desktop.dirty && desktop.clipboard.pid == -1 && desktop.clipboard.fd == -1
			unsafe { remaining.free() }
		}
		previous := receiver.paste_calls
		host_override := desktop.take_paste_keys(key_ctrl_shift_v)
		assert host_override.len == 0 && receiver.paste_calls == previous
		unsafe { host_override.free() }
	}
	assert receiver.paste_calls == 600
	assert C.vinix_heap_end() == 0
}

fn test_color_clipboard_fragmented_shortcuts_and_typing_order_release_temporary_strings() {
	mut receiver := &ColorClipboardHeapReceiver{}
	mut desktop := Desktop{ focus: 81, clipboard: HostClipboard{ configured: true } }
	defer { unsafe { desktop.apps.free() desktop.windows.free() desktop.native_asset_icons.free() free(receiver) } }
	desktop.apps << receiver
	desktop.windows << Window{ id: 81, page: .app, app_index: 0 }
	assert desktop.clipboard.set_local_text('rgb(18, 120, 239)')
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		// A lone Escape is intentionally released immediately. Chords can be
		// held once their introducer has arrived, from ESC [ onward.
		escape := desktop.take_paste_keys('\x1b')
		assert escape == '\x1b' && desktop.clipboard.pending.len == 0
		unsafe { escape.free() }
		for chord in [key_cmd_v, key_shift_insert, key_ctrl_shift_v]! {
			for split in 2 .. chord.len {
				prefix := chord[..split]
				suffix := chord[split..]
				previous := receiver.paste_calls
				first := desktop.take_paste_keys(prefix)
				assert first.len == 0 && receiver.paste_calls == previous
				assert desktop.clipboard.pending.len == split
				unsafe { prefix.free() first.free() }
				second := desktop.take_paste_keys(suffix)
				assert second.len == 0 && desktop.clipboard.pending.len == 0
				assert receiver.paste_calls == previous + if chord == key_ctrl_shift_v { 0 } else { 1 }
				unsafe { suffix.free() second.free() }
			}
		}
		remaining := desktop.take_paste_keys('before\x16after')
		assert remaining == 'after' && receiver.typed_text() == 'before'
		assert receiver.last_paste_event == receiver.last_key_event + 1
		assert receiver.pasted_text() == 'rgb(18, 120, 239)'
		unsafe { remaining.free() }
		prefix := desktop.take_paste_keys('\x1b[')
		assert prefix.len == 0
		unsafe { prefix.free() }
		arrow := desktop.take_paste_keys('D')
		assert arrow == '\x1b[D' && desktop.clipboard.pending.len == 0
		unsafe { arrow.free() }
	}
	assert C.vinix_heap_end() == 0
}

fn test_color_clipboard_repeated_warmed_start_search_paste_and_frames_keep_zero_bytes() {
	mut desktop := Desktop{
		canvas: Canvas{ width: 640, height: 480 }
		start_menu_open: true
		clipboard: HostClipboard{ configured: true }
		start_menu_query: []u8{cap: start_menu_max_query}
	}
	defer { desktop.close_start_menu() unsafe { desktop.native_asset_icons.free() } }
	unsafe { desktop.start_menu_query.flags |= .noslices }
	for text in ['#AABBCC', 'rgb(170, 187, 204)']! {
		desktop.start_menu_query.clear()
		assert desktop.clipboard.set_local_text(text)
		remaining := desktop.take_paste_keys('\x16')
		unsafe { remaining.free() }
		begin_frame_elements()
		tree := desktop.start_menu_element()
		free_tree(tree)
	}
	C.vinix_heap_begin()
	for index in 0 .. 200 {
		text := if index % 2 == 0 { '#AABBCC' } else { 'rgb(170, 187, 204)' }
		desktop.start_menu_query.clear()
		desktop.start_menu_page = 3
		desktop.start_menu_searching = false
		desktop.dirty = false
		assert desktop.clipboard.set_local_text(text)
		remaining := desktop.take_paste_keys(if index % 2 == 0 { key_cmd_v } else { key_shift_insert })
		assert remaining.len == 0 && desktop.start_menu_query_text() == text
		assert desktop.start_menu_page == 0 && desktop.start_menu_searching && desktop.dirty
		unsafe { remaining.free() }
		begin_frame_elements()
		tree := desktop.start_menu_element()
		free_tree(tree)
	}
	assert C.vinix_heap_end() == 0
}
