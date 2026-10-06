// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NotificationObserver {
mut:
	center u64
	observer u64 // Stable weak slots, independent of the registration array.
	filter u64
	filtered bool
	name u64
	action u64
}

struct NotificationCall {
	observer u64
	action u64
}

fn notification_remove(center u64, observer u64, name u64, filter u64) {
	for i := ios_runtime.observers.len - 1; i >= 0; i-- {
		record := ios_runtime.observers[i]
		if record.center != center || (record.observer != 0 && record.observer != observer)
			|| (name != 0 && !object_equal(record.name, name))
			|| (filter != 0 && record.filter != filter) { continue }
		objc_destroy_weak(unsafe { &record.observer })
		objc_destroy_weak(unsafe { &record.filter })
		objc_destroy_weak(unsafe { &record.center })
		objc_release(record.name)
		ios_runtime.observers.delete(i)
		unsafe { free(record) }
	}
}

fn notification_stop() {
	for record in ios_runtime.observers {
		objc_destroy_weak(unsafe { &record.observer })
		objc_destroy_weak(unsafe { &record.filter })
		objc_destroy_weak(unsafe { &record.center })
		objc_release(record.name)
		unsafe { free(record) }
	}
	ios_runtime.observers.clear()
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
	for record in ios_runtime.observers {
		if record.center != center || record.observer == 0
			|| (record.name != 0 && !object_equal(record.name, header.fields[0]))
			|| (record.filtered && (record.filter == 0 || record.filter != header.fields[1])) { continue }
		calls << NotificationCall{objc_retain(record.observer), record.action}
	}
	objc_retain(notification)
	defer { objc_release(notification) }
	for call in calls {
		invoke_action(call.observer, call.action, notification)
		objc_release(call.observer)
	}
}

fn notification_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	cls := objc_class(object)
	info := ios_runtime.classes[cls] or { return false }
	if info.name !in ['NSNotification', 'NSNotificationCenter'] { return false }
	if object in ios_runtime.classes {
		if info.name == 'NSNotificationCenter' && selector == 'defaultCenter' {
			if ios_runtime.notification_center == 0 { ios_runtime.notification_center = objc_allocate(cls) }
			frame.x[0] = ios_runtime.notification_center
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
		'addObserver:selector:name:object:' {
			if frame.x[2] == 0 || frame.x[3] == 0 { panic('iOS: notification observer requires a target and selector') }
			mut record := &NotificationObserver{action: frame.x[3], name: objc_retain(frame.x[4]), filtered: frame.x[5] != 0}
			objc_store_weak(unsafe { &record.center }, object)
			objc_store_weak(unsafe { &record.observer }, frame.x[2])
			objc_store_weak(unsafe { &record.filter }, frame.x[5])
			ios_runtime.observers << record
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
