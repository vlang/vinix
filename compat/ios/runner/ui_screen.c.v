// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The existing UIKit backend exposes one portrait virtual display at one pixel
// per point. Window resizing changes the window, not this display's geometry.
fn ui_screen_native_bounds() ObjRect { return ObjRect{0, 0, 390, 680} }

fn ui_screen_types(name string, meta bool, selector string) ?string {
	if name != 'UIScreen' { return none }
	if meta { return if selector == 'mainScreen' { ?string('@16@0:8') } else { none } }
	return match selector {
		'bounds', 'nativeBounds' { '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8' }
		'scale', 'nativeScale' { 'd16@0:8' }
		else { none }
	}
}

fn ui_screen_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		if current == ios_runtime.names['UIScreen'] { return true }
		info := ios_runtime.classes[current] or { return false }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic screen superclass chain')
}

fn ui_screen_selector(object u64, selector string) bool {
	if object in ios_runtime.classes { return selector == 'mainScreen' && ui_screen_family(object) }
	return selector in ['bounds', 'nativeBounds', 'scale', 'nativeScale']!
		&& objc_is_kind(object, ios_runtime.names['UIScreen'])
}

fn ui_screen_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !ui_screen_selector(object, selector) { return false }
	match selector {
		'mainScreen' { frame.x[0] = ui_main_screen() }
		'nativeBounds' { return_rect(mut frame, ui_screen_native_bounds()) }
		'bounds' {
			logical := obj_header(object).frame
			return_rect(mut frame, ObjRect{0, 0, logical.width, logical.height})
		}
		else { frame_float_return(mut frame, 0, 1) }
	}
	return true
}
