// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

// Fixtures, native interface ownership, and desktop arrays are constructed
// before measurement. Each receiver borrows the process-owned text literal,
// so these tests measure dispatch itself without application allocations.
struct NativePasteHeapReceiver {
mut:
	paste_calls int
	key_calls   int
	byte_count  int
	last_text   string
}

fn (mut _ NativePasteHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }

fn (mut _ NativePasteHeapReceiver) handle(_ string) ! {}

fn (mut a NativePasteHeapReceiver) paste_input(text string) {
	a.paste_calls++
	a.byte_count += text.len
	a.last_text = text
}

fn (mut a NativePasteHeapReceiver) key_input(_ string) { a.key_calls++ }

struct NativeKeyboardFallbackHeapReceiver {
mut:
	key_calls  int
	byte_count int
	last_text  string
}

fn (mut _ NativeKeyboardFallbackHeapReceiver) build(_ ui2.Rect) !ui2.Element {
	return ui2.Element{}
}

fn (mut _ NativeKeyboardFallbackHeapReceiver) handle(_ string) ! {}

fn (mut a NativeKeyboardFallbackHeapReceiver) key_input(text string) {
	a.key_calls++
	a.byte_count += text.len
	a.last_text = text
}

fn test_native_paste_dispatch_uses_pasting_receiver_without_retained_interface_allocations() {
	mut receiver := &NativePasteHeapReceiver{}
	mut desktop := Desktop{ focus: 73 }
	desktop.apps << receiver
	desktop.windows << Window{ id: 73, page: .app, app_index: 0 }
	text := '日本😀\tsecond line\n'
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		desktop.dirty = false
		desktop.send_paste_to_focused(text)
		assert desktop.dirty
	}
	live := C.vinix_heap_end()
	assert receiver.paste_calls == 100
	assert receiver.key_calls == 0
	assert receiver.byte_count == text.len * 100
	assert receiver.last_text == text
	assert live == 0, 'Native PastingApp dispatch retained ${live} bytes for 100 deliveries'
}

fn test_native_paste_keyboard_fallback_does_not_retain_interface_allocations() {
	mut receiver := &NativeKeyboardFallbackHeapReceiver{}
	mut desktop := Desktop{ focus: 91 }
	desktop.apps << receiver
	desktop.windows << Window{ id: 91, page: .app, app_index: 0 }
	text := 'Привет😀\tsecond line\n'
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		desktop.dirty = false
		desktop.send_paste_to_focused(text)
		assert desktop.dirty
	}
	live := C.vinix_heap_end()
	assert receiver.key_calls == 100
	assert receiver.byte_count == text.len * 100
	assert receiver.last_text == text
	assert live == 0, 'Native KeyboardApp paste fallback retained ${live} bytes for 100 deliveries'
}
