// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The desktop wire protocol has text pulses, not physical key transitions.
// Discovery must therefore report no connected keyboard. Native -init creates
// a real GCKeyboardInput even when discovery returns nil; do not fake it.
fn game_keyboard_name(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GCKeyboard' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic keyboard superclass chain')
}

fn game_keyboard_types(name string, meta bool, selector string) ?string {
	if name == 'GCKeyboard' && meta && selector == 'coalescedKeyboard' { return '@16@0:8' }
	return none
}

fn game_keyboard_selector(object u64, selector string) bool {
	return selector == 'coalescedKeyboard' && object in ios_runtime.classes && game_keyboard_name(object)
}

fn game_keyboard_require_discovery(cls u64) {
	if game_keyboard_name(cls) { panic('iOS: GCKeyboard construction requires an implemented physical input profile') }
}

fn game_keyboard_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !game_keyboard_name(if meta { object } else { read64(object) }) { return false }
	if meta && selector == 'coalescedKeyboard' {
		frame.x[0] = 0
		return true
	}
	match selector {
		'init', 'new', 'copy', 'copyWithZone:', 'keyboardInput', 'physicalInputProfile', 'handlerQueue', 'setHandlerQueue:' {
			panic('iOS: GCKeyboard construction requires an implemented physical input profile')
		}
		else {}
	}
	return false
}
