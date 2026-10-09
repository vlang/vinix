// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

struct AccessibilityState {
mut:
	strings [4]u64 // Label, hint, value, identifier.
	container u64 // Zeroing weak, like UIAccessibilityElement's native property.
	element bool
	traits u64
	frame ObjRect
	container_frame ObjRect
}

fn accessibility_state(object u64) &AccessibilityState {
	mut header := obj_header(object)
	if header.accessibility == unsafe { nil } {
		mut state := unsafe { &AccessibilityState(C.calloc(1, sizeof(AccessibilityState))) }
		if state == unsafe { nil } { panic('iOS: cannot allocate accessibility state') }
		state.element = objc_is_kind(object, ios_runtime.names['UIAccessibilityElement'])
		state.container_frame = ObjRect{math.inf(1), math.inf(1), 0, 0}
		header.accessibility = state
	}
	return header.accessibility
}

fn accessibility_dispose(object u64) {
	state := obj_header(object).accessibility
	if state == unsafe { nil } { return }
	objc_destroy_weak(unsafe { &state.container })
	for text in state.strings { objc_release(text) }
	C.free(state)
}

fn accessibility_selector(object u64, selector string) bool {
	if object in ios_runtime.classes { return false }
	if selector in ['isAccessibilityElement', 'setIsAccessibilityElement:',
		'accessibilityLabel', 'setAccessibilityLabel:', 'accessibilityHint', 'setAccessibilityHint:',
		'accessibilityValue', 'setAccessibilityValue:', 'accessibilityIdentifier', 'setAccessibilityIdentifier:',
		'accessibilityTraits', 'setAccessibilityTraits:', 'accessibilityFrame', 'setAccessibilityFrame:'] { return true }
	return objc_is_kind(object, ios_runtime.names['UIAccessibilityElement']) && selector in [
		'initWithAccessibilityContainer:', 'accessibilityContainer', 'setAccessibilityContainer:',
		'accessibilityFrameInContainerSpace', 'setAccessibilityFrameInContainerSpace:']
}

fn accessibility_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !accessibility_selector(object, selector) { return false }
	mut state := accessibility_state(object)
	match selector {
		'initWithAccessibilityContainer:', 'setAccessibilityContainer:' { objc_store_weak(unsafe { &state.container }, frame.x[2]) }
		'accessibilityContainer' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &state.container })) }
		'isAccessibilityElement' { frame.x[0] = u64(state.element) }
		'setIsAccessibilityElement:' { state.element = frame.x[2] != 0 }
		'accessibilityTraits' { frame.x[0] = state.traits }
		'setAccessibilityTraits:' { state.traits = frame.x[2] }
		'accessibilityFrame' { return_rect(mut frame, state.frame) }
		'setAccessibilityFrame:' { state.frame = frame_rect(frame) }
		'accessibilityFrameInContainerSpace' { return_rect(mut frame, state.container_frame) }
		'setAccessibilityFrameInContainerSpace:' {
			panic('iOS: accessibility container coordinate conversion is not implemented')
		}
		else {
			index := if selector.contains('Label') { 0 } else if selector.contains('Hint') { 1 } else if selector.contains('Value') { 2 } else { 3 }
			if selector.starts_with('set') { objc_store_strong(unsafe { &state.strings[index] }, frame.x[2]) }
			else { frame.x[0] = state.strings[index] }
		}
	}
	return true
}

fn accessibility_voice_over() bool { return ios_runtime.voice_over_running }

fn accessibility_post(notification u32, argument u64) {
	_ = notification
	_ = argument
	// Notifications have no receiver while VoiceOver is off. Vinix does not
	// attach a screen-reader service; do not claim to deliver announcements.
	if accessibility_voice_over() { panic('iOS: VoiceOver notification delivery is not implemented') }
}

fn accessibility_zoom_conflict() { ios_runtime.zoom_gesture_conflict = true }

fn accessibility_symbol(symbol string) ?u64 {
	return match symbol {
		'_UIAccessibilityIsVoiceOverRunning' { u64(unsafe { voidptr(accessibility_voice_over) }) }
		'_UIAccessibilityPostNotification' { u64(unsafe { voidptr(accessibility_post) }) }
		'_UIAccessibilityRegisterGestureConflictWithZoom' { u64(unsafe { voidptr(accessibility_zoom_conflict) }) }
		else { return none }
	}
}
