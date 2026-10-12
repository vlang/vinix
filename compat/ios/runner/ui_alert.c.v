// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Installed Catalyst UIKit supplies the public object/method measurements.
// Its private 1400/144-byte records remain reserved; public state is separate.
struct AlertState {
mut:
	refs [3]u64 // Copied title/message and retained preferred action.
	actions [32]u64
	count int
	handler u64 // Copied block, released independently of the current isa.
	style i64
	severity i64
	action bool
	enabled bool
}
type AlertHandler = fn (u64, u64)

fn alert_name(cls u64) string {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return '' }
		if info.name in ['UIAlertController', 'UIAlertAction'] { return info.name }
		current = info.parent
		if current == 0 { return '' }
	}
	panic('iOS: cyclic alert superclass chain')
}

fn alert_types(name string, meta bool, selector string) ?string {
	if name !in ['UIAlertController', 'UIAlertAction'] { return none }
	if meta {
		if name == 'UIAlertController' && selector == 'alertControllerWithTitle:message:preferredStyle:' { return '@40@0:8@16@24q32' }
		if name == 'UIAlertAction' && selector == 'actionWithTitle:style:handler:' { return '@40@0:8@16q24@?32' }
		return none
	}
	if selector in ['init', 'title'] { return '@16@0:8' }
	if name == 'UIAlertAction' {
		return match selector {
			'copy' { '@16@0:8' }
			'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
			'style' { 'q16@0:8' }
			'isEnabled' { 'B16@0:8' }
			'setEnabled:' { 'v20@0:8B16' }
			else { return none }
		}
	}
	return match selector {
		'message', 'actions', 'preferredAction', 'textFields' { '@16@0:8' }
		'preferredStyle', 'severity' { 'q16@0:8' }
		'setTitle:', 'setMessage:', 'addAction:', 'setPreferredAction:' { 'v24@0:8@16' }
		'setSeverity:' { 'v24@0:8q16' }
		'addTextFieldWithConfigurationHandler:' { 'v24@0:8@?16' }
		else { return none }
	}
}

fn alert_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return alert_types(alert_name(if meta { object } else { read64(object) }), meta, selector) != none
}

fn alert_string(value u64) u64 {
	if value == 0 { return 0 }
	if !objc_is_kind(value, ios_runtime.names['NSString']) || string_text(value).len > 65536 { panic('iOS: alert text requires a string of at most 64KiB') }
	return owned_string(string_text(value))
}

fn alert_initialize(object u64, title u64, message u64, style i64, handler u64, factory bool) {
	mut header := obj_header(object)
	if !header.alert_owned { panic('iOS: invalid alert storage') }
	if header.alert != unsafe { nil } { panic('iOS: alert reinitialization is not implemented') }
	action := objc_is_kind(object, ios_runtime.names['UIAlertAction'])
	if style < 0 || style > if action { 2 } else { 1 } { panic('iOS: alert style is outside the implemented profile') }
	if handler != 0 && !is_block(handler) { panic('iOS: alert handler must be a block') }
	header.alert = unsafe { &AlertState(C.calloc(1, sizeof(AlertState))) }
	if header.alert == unsafe { nil } { panic('iOS: cannot allocate alert state') }
	mut state := header.alert
	state.action = action
	state.style = style
	state.enabled = action && factory // Measured -new action is disabled.
	state.refs[0] = alert_string(title)
	state.refs[1] = alert_string(message)
	state.handler = block_copy(handler)
}

fn alert_dispose(mut header ObjHeader) {
	if header.alert == unsafe { nil } { return }
	state := header.alert
	for value in state.refs { objc_release(value) }
	for i in 0 .. state.count { objc_release(state.actions[i]) }
	block_release(state.handler)
	C.free(state)
	header.alert = unsafe { nil }
}

fn alert_snapshot(state &AlertState, fields bool) u64 {
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut header := obj_header(array)
	header.json_immutable = true
	if !fields { for i in 0 .. state.count { header.items << objc_retain(state.actions[i]) } }
	return objc_autorelease(array)
}

fn alert_copy_action(object u64) u64 {
	state := obj_header(object).alert
	if state == unsafe { nil } || !state.action { panic('iOS: alert action is not initialized') }
	copy := objc_allocate(ios_runtime.names['UIAlertAction'])
	alert_initialize(copy, state.refs[0], 0, state.style, state.handler, true)
	obj_header(copy).alert.enabled = state.enabled
	return copy
}

fn alert_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	name := alert_name(if meta { object } else { read64(object) })
	if !meta && name == 'UIAlertController' && selector == 'vinixSelectAlert:' { alert_select(object, frame.x[2]); return true }
	if alert_types(name, meta, selector) == none { return false }
	if meta {
		value := objc_allocate(object)
		if name == 'UIAlertAction' { alert_initialize(value, frame.x[2], 0, i64(frame.x[3]), frame.x[4], true) }
		else { alert_initialize(value, frame.x[2], frame.x[3], i64(frame.x[4]), 0, true) }
		frame.x[0] = objc_autorelease(value)
		return true
	}
	if selector == 'init' { alert_initialize(object, 0, 0, if name == 'UIAlertController' { i64(1) } else { i64(0) }, 0, false); return true }
	mut state := obj_header(object).alert
	if state == unsafe { nil } { panic('iOS: alert is not initialized') }
	match selector {
		'title', 'message' { frame.x[0] = state.refs[if selector == 'title' { 0 } else { 1 }] }
		'setTitle:', 'setMessage:' {
			index := if selector == 'setTitle:' { 0 } else { 1 }
			copied := alert_string(frame.x[2]); old := state.refs[index]; state.refs[index] = copied; objc_release(old)
			alert_layout(object)
		}
		'copy', 'copyWithZone:' {
			frame.x[0] = alert_copy_action(object)
		}
		'style', 'preferredStyle' { frame.x[0] = u64(state.style) }
		'isEnabled' { frame.x[0] = u64(state.enabled) }
		'setEnabled:' { state.enabled = u8(frame.x[2]) != 0; ios_runtime.dirty = true }
		'severity' { frame.x[0] = u64(state.severity) }
		'setSeverity:' { if frame.x[2] > 1 { panic('iOS: alert severity is outside the implemented profile') }; state.severity = i64(frame.x[2]) }
		'actions', 'textFields' { frame.x[0] = alert_snapshot(state, selector == 'textFields') }
		'preferredAction' { frame.x[0] = state.refs[2] }
		'setPreferredAction:' {
			value := frame.x[2]
			mut found := value == 0
			for i in 0 .. state.count { if state.actions[i] == value { found = true; break } }
			if !found { panic('iOS: preferred alert action must belong to the controller') }
			old := state.refs[2]; state.refs[2] = objc_retain(value); objc_release(old)
		}
		'addAction:' {
			value := frame.x[2]
			if value == 0 || !objc_is_kind(value, ios_runtime.names['UIAlertAction']) || obj_header(value).alert == unsafe { nil } { panic('iOS: addAction requires an initialized alert action') }
			if state.count == 32 { panic('iOS: alert action limit exceeded') }
			if obj_header(value).alert.style == 1 { for i in 0 .. state.count { if obj_header(state.actions[i]).alert.style == 1 { panic('iOS: alert can have only one cancel action') } } }
			state.actions[state.count] = objc_retain(value); state.count++
			alert_layout(object)
		}
		'addTextFieldWithConfigurationHandler:' { panic('iOS: alert text fields are not implemented') }
		else { return false }
	}
	return true
}

fn ui_present_controller(presenter u64, controller u64, completion u64) {
	if !objc_is_kind(presenter, ios_runtime.names['UIViewController']) || controller == 0 || !objc_is_kind(controller, ios_runtime.names['UIViewController']) { panic('iOS: presentation requires view controllers') }
	if presenter == controller || obj_header(presenter).fields[8] != 0 || obj_header(controller).presenter != 0 { panic('iOS: invalid or occupied presentation') }
	mut ancestor := presenter
	for _ in 0 .. 32 { if ancestor == controller { panic('iOS: cyclic presentation') }; ancestor = obj_header(ancestor).presenter; if ancestor == 0 { break } }
	if ancestor != 0 { panic('iOS: presentation hierarchy exceeds limit') }
	block := block_copy(completion)
	defer { block_release(block) }
	store_field(presenter, 8, controller)
	mut header := obj_header(controller)
	objc_store_weak(unsafe { &header.presenter }, presenter)
	ui_load_controller(controller)
	ios_runtime.dirty = true
	block_invoke_void(block)
}

fn ui_dismiss_controller(controller u64, completion u64) {
	if !objc_is_kind(controller, ios_runtime.names['UIViewController']) { panic('iOS: dismissal requires a view controller') }
	block := block_copy(completion)
	defer { block_release(block) }
	header := obj_header(controller)
	presenter := if header.presenter != 0 { header.presenter } else { controller }
	presented := obj_header(presenter).fields[8]
	if presented != 0 {
		mut child := obj_header(presented)
		objc_store_weak(unsafe { &child.presenter }, 0)
		store_field(presenter, 8, 0)
	}
	ios_runtime.dirty = true
	block_invoke_void(block)
}

fn alert_button_enabled(button u64) bool {
	header := obj_header(button)
	if !header.alert_button { return true }
	if header.target == 0 { return false }
	state := obj_header(header.target).alert
	if state == unsafe { nil } || header.section < 0 || header.section >= state.count { return false }
	action := obj_header(state.actions[int(header.section)]).alert
	return action != unsafe { nil } && action.enabled
}

fn alert_select(controller u64, button u64) {
	if !alert_button_enabled(button) || obj_header(button).target != controller || !obj_header(button).alert_button { return }
	if ios_runtime.window == 0 || ui_current_controller() != controller || !ui_contains(ui_root_view(), button, 0) { panic('iOS: alert selection is outside the visible controller') }
	state := obj_header(controller).alert
	// Keep all callback inputs alive while dismissal releases presentation ownership.
	objc_retain(controller)
	action := objc_retain(state.actions[int(obj_header(button).section)])
	handler := block_copy(obj_header(action).alert.handler)
	ui_dismiss_controller(controller, 0)
	if handler != 0 { unsafe { AlertHandler(voidptr(read64(handler + 16)))(handler, action) } }
	block_release(handler)
	objc_release(action)
	objc_release(controller)
	ios_runtime.dirty = true
}

fn alert_layout(controller u64) {
	mut header := obj_header(controller)
	state := header.alert
	if state == unsafe { nil } || state.action || header.fields[6] == 0 { return }
	view := header.fields[6]
	mut root := obj_header(view)
	if ios_runtime.window != 0 { window := obj_header(ios_runtime.window).frame; root.frame = ObjRect{0, 0, window.width, window.height} }
	for root.child_count > 0 { ui_remove_child(root.children[root.child_count - 1]) }
	panel := objc_allocate(ios_runtime.names['UIView'])
	mut box := obj_header(panel)
	width := if root.frame.width > 360 { f64(320) } else { root.frame.width - 40 }
	height := if f64(110 + state.count * 42) < root.frame.height - 40 { f64(110 + state.count * 42) } else { root.frame.height - 40 }
	if width < 100 || height < 110 { panic('iOS: alert window is too small') }
	row := if state.count == 0 { f64(42) } else { (height - 110) / f64(state.count) }
	box.frame = ObjRect{(root.frame.width - width) / 2, if state.style == 0 { root.frame.height - height - 20 } else { (root.frame.height - height) / 2 }, width, height}
	color := objc_allocate(ios_runtime.names['UIColor']); obj_header(color).color = 0xeeeeee; store_field(panel, 2, color); objc_release(color)
	black := objc_allocate(ios_runtime.names['UIColor']); obj_header(black).color = 0x111111
	blue := objc_allocate(ios_runtime.names['UIColor']); obj_header(blue).color = 0x0055cc
	red := objc_allocate(ios_runtime.names['UIColor']); obj_header(red).color = 0xbb2222
	for i in 0 .. 2 {
		label := objc_allocate(ios_runtime.names['UILabel']); mut item := obj_header(label)
		item.frame = ObjRect{12, f64(12 + i * 40), width - 24, 36}; item.align = 1
		store_field(label, 0, state.refs[i]); store_field(label, 3, black); ui_add_child(panel, label); objc_release(label)
	}
	for i in 0 .. state.count {
		button := objc_allocate(ios_runtime.names['UIButton']); mut item := obj_header(button)
		item.frame = ObjRect{12, 98 + f64(i) * row, width - 24, row - 2}
		item.alert_button = true; item.section = i
		objc_store_weak(unsafe { &item.target }, controller); item.action = u64(c'vinixSelectAlert:')
		item.fields[5] = objc_allocate(ios_runtime.names['UILabel']); store_field(item.fields[5], 0, obj_header(state.actions[i]).alert.refs[0])
		store_field(item.fields[5], 3, if obj_header(state.actions[i]).alert.style == 2 { red } else { blue })
		ui_add_child(panel, button); objc_release(button)
	}
	ui_add_child(view, panel); objc_release(panel)
	objc_release(black); objc_release(blue); objc_release(red)
	ios_runtime.dirty = true
}
