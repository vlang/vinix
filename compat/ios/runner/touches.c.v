// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

type ObjTouch = fn (u64, &char, u64, u64)

// A desktop left pointer is one stable UITouch for its complete gesture.
// Deliver native responder callbacks before the existing swipe fallback.
fn ui_native_pointer(phase u32, button u32, x int, y int) bool {
	if phase > 2 || (phase != 0 && button != 1) { return false }
	selector := match phase {
		1 { c'touchesBegan:withEvent:' }
		2 { c'touchesEnded:withEvent:' }
		else { c'touchesMoved:withEvent:' }
	}
	mut responder := ui_root_view()
	mut imp := native_method(read64(responder), ctext(u64(selector)))
	if imp == 0 {
		responder = ui_current_controller()
		imp = native_method(read64(responder), ctext(u64(selector)))
	}
	if imp == 0 || (phase != 1 && ios_runtime.native_touch == 0) { return false }
	if phase == 1 {
		if ios_runtime.native_touch != 0 { return false }
		ios_runtime.native_touch = objc_allocate(ios_runtime.names['UITouch'])
		store_field(ios_runtime.native_touch, 0, ui_root_view())
	}
	touch := ios_runtime.native_touch
	mut header := obj_header(touch)
	header.frame.x = f64(x)
	header.frame.y = f64(y)
	header.number = match phase { 1 { i64(0) } 2 { i64(3) } else { i64(1) } }
	header.real_number = f64(time.sys_mono_now()) / 1e9
	set := objc_allocate(ios_runtime.names['NSSet'])
	array_append(mut obj_header(set), touch)
	event := objc_allocate(ios_runtime.names['UIEvent'])
	store_field(event, 0, set)
	unsafe { ObjTouch(voidptr(imp))(responder, selector, set, event) }
	objc_release(event)
	objc_release(set)
	if phase == 2 {
		ios_runtime.native_touch = 0
		objc_release(touch)
	}
	return true
}

fn touch_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes { return false }
	if objc_is_kind(object, ios_runtime.names['UIEvent']) {
		if selector != 'allTouches' { return false }
		frame.x[0] = obj_header(object).fields[0]
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['UITouch']) { return false }
	header := obj_header(object)
	match selector {
		'view' { frame.x[0] = header.fields[0] }
		'phase' { frame.x[0] = u64(header.number) }
		'tapCount' { frame.x[0] = 1 }
		'timestamp' { frame_float_return(mut frame, 0, header.real_number) }
		'locationInView:' {
			mut x := header.frame.x
			mut y := header.frame.y
			mut view := frame.x[2]
			for _ in 0 .. 128 {
				if view == 0 || objc_is_kind(view, ios_runtime.names['UIWindow']) { break }
				parent := obj_header(view)
				x -= parent.frame.x
				y -= parent.frame.y
				view = parent.parent_view
			}
			frame_float_return(mut frame, 0, x)
			frame_float_return(mut frame, 1, y)
		}
		else { return false }
	}
	return true
}
