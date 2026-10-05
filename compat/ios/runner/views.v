// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn invoke_action(target u64, selector u64, sender u64) {
	imp := native_method(read64(target), ctext(selector))
	if imp != 0 {
		method := unsafe { ObjAction(voidptr(imp)) }
		method(target, unsafe { &char(selector) }, sender)
	} else {
		mut frame := RegisterFrame{}
		frame.x[0] = target
		frame.x[1] = selector
		frame.x[2] = sender
		if !framework_dispatch(target, ctext(selector), mut frame) {
			panic('iOS: target/action method is missing')
		}
	}
	ios_runtime.dirty = true
}

fn ui_current_controller() u64 {
	mut controller := obj_header(ios_runtime.window).fields[7]
	for _ in 0 .. 32 {
		presented := obj_header(controller).fields[8]
		if presented == 0 { return controller }
		controller = presented
	}
	panic('iOS: presentation hierarchy exceeds limit')
}

fn ui_load_controller(controller u64) {
	mut header := obj_header(controller)
	if header.fields[6] == 0 {
		header.fields[6] = objc_allocate(ios_runtime.names['UIView'])
		mut view := obj_header(header.fields[6])
		view.frame = ObjRect{0, 0, 390, 680}
	}
	if !header.loaded {
		header.loaded = true
		invoke_void(controller, c'viewDidLoad')
	}
	invoke_void(controller, c'viewDidLayoutSubviews')
}

fn ui_remove_child(child u64) {
	mut header := obj_header(child)
	if header.parent_view == 0 { return }
	mut parent := obj_header(header.parent_view)
	for i in 0 .. parent.child_count {
		if parent.children[i] != child { continue }
		for j := i; j < parent.child_count - 1; j++ { parent.children[j] = parent.children[j + 1] }
		parent.child_count--
		parent.children[parent.child_count] = 0
		header.parent_view = 0
		objc_release(child)
		return
	}
	panic('iOS: inconsistent UIView parent')
}

fn ui_add_child(parent u64, child u64) {
	if parent == child || ui_contains(child, parent, 0) { panic('iOS: cyclic UIView hierarchy') }
	objc_retain(child) // Keep it alive across removal from its previous parent.
	ui_remove_child(child)
	mut header := obj_header(parent)
	if header.child_count == 64 { panic('iOS: UIView child limit exceeded') }
	header.children[header.child_count] = child
	header.child_count++
	mut item := obj_header(child)
	item.parent_view = parent
}

fn ui_contains(root u64, object u64, depth int) bool {
	if root == object { return true }
	if depth > 32 { return false }
	header := obj_header(root)
	for i in 0 .. header.child_count {
		if ui_contains(header.children[i], object, depth + 1) { return true }
	}
	return false
}

fn ui_swipe(root u64, direction i64, depth int) bool {
	if depth > 32 { return false }
	header := obj_header(root)
	for gesture in header.gestures {
		g := obj_header(gesture)
		if g.number & direction == 0 { continue }
		invoke_action(g.target, g.action, gesture)
		return true
	}
	for i in 0 .. header.child_count {
		if ui_swipe(header.children[i], direction, depth + 1) { return true }
	}
	return false
}

fn ui_key(root u64, tag i64, depth int) {
	if depth > 32 { return }
	header := obj_header(root)
	if header.target != 0 && header.tag == tag {
		ui_action(root) or { panic(err) }
		return
	}
	for i in 0 .. header.child_count { ui_key(header.children[i], tag, depth + 1) }
}

fn ui_show_alert(alert u64) {
	mut header := obj_header(alert)
	header.frame = ObjRect{45, 210, 300, 180}
	header.color = 0xeeeeee
	for i in 0 .. 2 {
		label := objc_allocate(ios_runtime.names['UILabel'])
		mut item := obj_header(label)
		item.frame = ObjRect{15, f64(15 + i * 40), 270, 35}
		item.align = 1
		store_field(label, 0, header.fields[i])
		ui_add_child(alert, label)
		objc_release(label)
	}
	button := objc_allocate(ios_runtime.names['UIButton'])
	mut item := obj_header(button)
	item.frame = ObjRect{15, 120, 270, 45}
	item.target = alert
	item.action = u64(c'dismissAlert:')
	item.fields[5] = objc_allocate(ios_runtime.names['UILabel'])
	store_field(item.fields[5], 0, header.fields[3])
	ui_add_child(alert, button)
	objc_release(button)
	// Message/title slots become UILabel text. Do not serialize an alert as a label.
	store_field(alert, 0, 0)
	store_field(alert, 1, 0)
	store_field(alert, 3, 0)
	ui_add_child(ui_root_view(), alert)
}
