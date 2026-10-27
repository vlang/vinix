// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NotificationObserver {
mut:
	center u64 // Identity only; center destruction removes its registrations.
	observer u64 // Stable selector weak slot or an owned block token.
	filter u64
	filtered bool
	name u64
	action u64
	block bool // Owns an opaque token; selector registrations remain weak.
}

struct NotificationCall {
	observer u64
	action u64
	block u64
}

fn notification_dispose(record &NotificationObserver) {
	if !record.block { objc_destroy_weak(unsafe { &record.observer }) }
	objc_destroy_weak(unsafe { &record.filter })
	objc_release(record.name)
	if record.block {
		mut token := obj_header(record.observer)
		capture := token.notification_block
		token.notification_block = 0
		block_release(capture)
		objc_release(record.observer)
	}
	unsafe { free(record) }
}

fn notification_remove_matching(center u64, observer u64, name u64, filter u64, all bool) {
	mut removed := []&NotificationObserver{}
	removed.flags |= .noslices
	C.ios_objc_initialize_lock()
	for i := ios_runtime.observers.len - 1; i >= 0; i-- {
		record := ios_runtime.observers[i]
		// Foundation's opaque tokens identify the registration independently of
		// the receiving center and the optional removal filters.
		if record.block && !all {
			if record.observer != observer { continue }
			removed << record
			ios_runtime.observers.delete(i)
			continue
		}
		if record.center != center || (!all && record.observer != 0 && record.observer != observer)
			|| (name != 0 && !object_equal(record.name, name))
			|| (filter != 0 && record.filter != filter) { continue }
		removed << record
		ios_runtime.observers.delete(i)
	}
	C.ios_objc_initialize_unlock()
	// Capture destructors can register, post or remove observers themselves.
	for record in removed { notification_dispose(record) }
	unsafe { removed.free() }
}

fn notification_remove(center u64, observer u64, name u64, filter u64) {
	notification_remove_matching(center, observer, name, filter, false)
}

fn notification_retire(object u64, mut header ObjHeader) {
	if objc_is_kind(object, ios_runtime.names['NSNotificationCenter']) {
		notification_remove_matching(object, 0, 0, 0, true)
	}
	block := header.notification_block
	header.notification_block = 0
	if block != 0 { block_release(block) }
}

fn notification_stop() {
	C.ios_objc_initialize_lock()
	records := ios_runtime.observers.clone()
	ios_runtime.observers.clear()
	C.ios_objc_initialize_unlock()
	for record in records { notification_dispose(record) }
	unsafe { records.free() }
}

type NotificationBlockInvoke = fn (u64, u64)

fn notification_types(name string, meta bool, selector string) ?string {
	if name == 'NSNotificationCenter' && !meta && selector == 'addObserverForName:object:queue:usingBlock:' {
		return '@48@0:8@16@24@32@?40'
	}
	return none
}

fn notification_post(center u64, notification u64) {
	if notification == 0 || !objc_is_kind(notification, ios_runtime.names['NSNotification']) {
		panic('iOS: invalid notification')
	}
	header := obj_header(notification)
	mut calls := []NotificationCall{}
	calls.flags |= .noslices
	defer { unsafe { calls.free() } }
	// Retain the recipients before dispatch: callbacks may unregister observers.
	C.ios_objc_initialize_lock()
	for record in ios_runtime.observers {
		if record.center != center || record.observer == 0
			|| (record.name != 0 && !object_equal(record.name, header.fields[0]))
			|| (record.filtered && (record.filter == 0 || record.filter != header.fields[1])) { continue }
		recipient := if record.block { objc_retain(record.observer) } else { objc_load_weak(unsafe { &record.observer }) }
		if recipient == 0 { continue }
		capture := if record.block { block_retain(obj_header(recipient).notification_block) } else { u64(0) }
		calls << NotificationCall{recipient, record.action, capture}
	}
	C.ios_objc_initialize_unlock()
	objc_retain(notification)
	defer { objc_release(notification) }
	for call in calls {
		if call.block != 0 { unsafe { NotificationBlockInvoke(voidptr(read64(call.block + 16)))(call.block, notification) } }
		else { invoke_action(call.observer, call.action, notification) }
		if call.block != 0 { block_release(call.block) }
		objc_release(call.observer)
	}
}

fn notification_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	cls := objc_class(object)
	info := ios_runtime.classes[cls] or { return false }
	if info.name !in ['NSNotification', 'NSNotificationCenter'] { return false }
	if object in ios_runtime.classes {
		if info.name == 'NSNotificationCenter' && selector == 'defaultCenter' {
			C.ios_objc_initialize_lock()
			if ios_runtime.notification_center == 0 { ios_runtime.notification_center = objc_allocate(cls) }
			frame.x[0] = ios_runtime.notification_center
			C.ios_objc_initialize_unlock()
			return true
		}
		if info.name == 'NSNotification' && selector == 'notificationWithName:object:userInfo:' {
			if frame.x[2] == 0 { panic('iOS: notification requires a name') }
			note := objc_allocate(cls)
			for i in 0 .. 3 { store_field(note, i, frame.x[i + 2]) }
			frame.x[0] = objc_autorelease(note)
			return true
		}
		return false
	}
	if info.name == 'NSNotification' {
		index := match selector { 'name' { 0 } 'object' { 1 } 'userInfo' { 2 } else { return false } }
		frame.x[0] = obj_header(object).fields[index]
		return true
	}
	match selector {
		'addObserverForName:object:queue:usingBlock:' {
			if frame.x[4] != 0 { panic('iOS: notification observer operation queues are not implemented') }
			if frame.x[5] == 0 || !is_block(frame.x[5]) { panic('iOS: notification observer requires a block') }
			// Compiler capture helpers can reenter; copy outside the table lock.
			block := block_copy(frame.x[5])
			token := objc_allocate(ios_runtime.names['VinixNotificationObserver'])
			obj_header(token).notification_block = block
			mut record := &NotificationObserver{observer: token, block: true, name: objc_retain(frame.x[2]), filtered: frame.x[3] != 0}
			C.ios_objc_initialize_lock()
			record.center = object
			objc_store_weak(unsafe { &record.filter }, frame.x[3])
			ios_runtime.observers << record
			C.ios_objc_initialize_unlock()
			frame.x[0] = token // The center owns the token until removal.
		}
		'addObserver:selector:name:object:' {
			if frame.x[2] == 0 || frame.x[3] == 0 { panic('iOS: notification observer requires a target and selector') }
			mut record := &NotificationObserver{action: frame.x[3], name: objc_retain(frame.x[4]), filtered: frame.x[5] != 0}
			C.ios_objc_initialize_lock()
			record.center = object
			objc_store_weak(unsafe { &record.observer }, frame.x[2])
			objc_store_weak(unsafe { &record.filter }, frame.x[5])
			ios_runtime.observers << record
			C.ios_objc_initialize_unlock()
		}
		'removeObserver:' { notification_remove(object, frame.x[2], 0, 0) }
		'removeObserver:name:object:' { notification_remove(object, frame.x[2], frame.x[3], frame.x[4]) }
		'postNotification:' { notification_post(object, frame.x[2]) }
		'postNotificationName:object:', 'postNotificationName:object:userInfo:' {
			if frame.x[2] == 0 { panic('iOS: notification requires a name') }
			note := objc_allocate(ios_runtime.names['NSNotification'])
			store_field(note, 0, frame.x[2])
			store_field(note, 1, frame.x[3])
			if selector.ends_with('userInfo:') { store_field(note, 2, frame.x[4]) }
			notification_post(object, note)
			objc_release(note)
		}
		else { return false }
	}
	return true
}
