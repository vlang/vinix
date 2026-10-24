// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import math.bits

// Public value storage only. Delivery, nonempty attachments, critical sounds, badges,
// arbitrary userInfo payloads, coding and private presentation options are absent.
struct UNContent {
mut:
	initialized bool
	busy bool
	values [13]u64
	count u64
	interruption u64 = 1
	score f64
}

fn un_content_properties() [13]string {
	return ['attachments', 'badge', 'body', 'categoryIdentifier', 'launchImageName', 'sound', 'subtitle', 'threadIdentifier', 'title', 'summaryArgument', 'targetContentIdentifier', 'userInfo', 'filterCriteria']!
}

fn un_content_setters() [13]string {
	return ['setAttachments:', 'setBadge:', 'setBody:', 'setCategoryIdentifier:', 'setLaunchImageName:', 'setSound:', 'setSubtitle:', 'setThreadIdentifier:', 'setTitle:', 'setSummaryArgument:', 'setTargetContentIdentifier:', 'setUserInfo:', 'setFilterCriteria:']!
}

fn un_content_offsets() [13]u64 { return [u64(24), 32, 40, 56, 120, 152, 168, 176, 184, 208, 224, 232, 264]! }

fn un_content_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['UNNotificationContent']] or { panic('iOS: missing notification content') }
	properties := un_content_properties()
	for i, offset in un_content_offsets() {
		types := match i { 0 { '@"NSArray"' } 1 { '@"NSNumber"' } 5 { '@"UNNotificationSound"' } 11 { '@"NSDictionary"' } else { '@"NSString"' } }
		name := '_' + properties[i]
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: types.clone(), offset: i64(offset), size: 8}
	}
	for i, name in ['summaryArgumentCount', 'interruptionLevel', 'relevanceScore']! {
		key := '_' + name
		cls.ivars[key] = &ObjIvar{name: key.clone(), types: if i == 2 { 'd' } else { 'Q' }, offset: [i64(216), 248, 256]![i], size: 8}
	}
}

fn un_content_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UNNotificationContent' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic notification content superclass chain')
}

fn un_content_require_class(cls u64) {
	if un_content_family(cls) && cls !in [ios_runtime.names['UNNotificationContent'], ios_runtime.names['UNMutableNotificationContent']]! {
		panic('iOS: custom notification content construction is not implemented')
	}
}

// Caller holds the runtime lock. Access uses allocation provenance, never isa alone.
fn un_content_storage(object u64, initialized bool) &UNContent {
	header := obj_header(object)
	if header.un_content == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 296
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls !in [ios_runtime.names['UNNotificationContent'], ios_runtime.names['UNMutableNotificationContent']]! {
		panic('iOS: notification content requires live owned built-in storage')
	}
	state := header.un_content
	if initialized && (!state.initialized || state.busy) { panic('iOS: notification content is not initialized') }
	for i, offset in un_content_offsets() {
		if read64(object + offset) != state.values[i] { panic('iOS: notification content body was changed') }
	}
	if state.initialized && (read64(object + 216) != state.count || read64(object + 248) != state.interruption
		|| read64(object + 256) != bits.f64_bits(state.score)) { panic('iOS: notification content scalar body was changed') }
	return state
}

fn un_content_publish(object u64, mut state UNContent) {
	for i, offset in un_content_offsets() { unsafe { *(&u64(object + offset)) = state.values[i] } }
	unsafe {
		*(&u64(object + 216)) = state.count
		*(&u64(object + 248)) = state.interruption
		*(&f64(object + 256)) = state.score
	}
	state.initialized = true
	state.busy = false
}

fn un_content_pristine(object u64) {
	state := un_content_storage(object, false)
	if state.initialized || state.busy { panic('iOS: notification content constructor changed state') }
	for offset := u64(8); offset < 296; offset += 8 {
		if read64(object + offset) != 0 { panic('iOS: notification content constructor changed body') }
	}
}

fn un_content_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	un_content_pristine(object)
	mut state := un_content_storage(object, false)
	state.busy = true
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer { objc_release(object) }
	// Application constructors run without the runtime lock and may reenter it.
	mut values := [13]u64{}
	values[0] = objc_allocate(ios_runtime.names['NSArray'])
	values[11] = objc_allocate(ios_runtime.names['NSDictionary'])
	for i in [3, 4, 7, 9]! { values[i] = owned_string('') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	state = un_content_storage(object, false)
	if state.initialized || !state.busy { panic('iOS: notification content initialization was reentered') }
	for i in [0, 3, 4, 7, 9, 11]! {
		if values[i] == 0 {
			for value in values { objc_release(value) }
			state.busy = false
			objc_release(object)
			return 0
		}
		un_content_validate_value(i, values[i])
	}
	for offset := u64(8); offset < 296; offset += 8 {
		if read64(object + offset) != 0 { panic('iOS: notification content initialization changed body') }
	}
	state.values = values
	un_content_publish(object, mut state)
	return object
}

fn un_content_validate_value(index int, value u64) {
	if value == 0 { return }
	if index == 1 { panic('iOS: notification badge values are not implemented') }
	if index == 5 { un_sound_storage(value, true); return }
	if index in [0, 11]! {
		header := obj_header(value)
		names := if index == 0 { ['NSArray', 'NSMutableArray']! } else { ['NSDictionary', 'NSMutableDictionary']! }
		if header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
			|| header.cls != header.allocation_cls || read64(value) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names[names[0]], ios_runtime.names[names[1]]]!
			|| header.items.len != 0 || header.keys.len != 0 || header.cf_raw_values || header.cf_raw_keys {
			panic('iOS: notification content only supports empty built-in collections')
		}
	} else { un_request_text(value) }
}

fn un_content_set(object u64, index int, value u64) {
	C.ios_objc_initialize_lock()
	un_content_storage(object, true)
	if obj_header(object).allocation_cls != ios_runtime.names['UNMutableNotificationContent'] { panic('iOS: notification content is immutable') }
	un_content_validate_value(index, value)
	// Native launchImageName/subtitle retain their inputs; their getters copy.
	if index == 5 || (index in [4, 6]! && (value != 0 || index == 6)) {
		mut state := un_content_storage(object, true)
		old := state.values[index]
		state.values[index] = objc_retain(value)
		un_content_publish(object, mut state)
		objc_release(old)
		C.ios_objc_initialize_unlock()
		return
	}
	// Snapshot bytes before any application constructor. No borrowed input survives.
	text := if value != 0 && index !in [0, 11]! { un_request_text(value).clone() } else { ''.clone() }
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() }; objc_release(object) }
	normalize := index in [3, 4, 7]!
	copy := if index == 0 { objc_allocate(ios_runtime.names['NSArray']) }
		else if index == 11 && value != 0 { objc_allocate(ios_runtime.names['NSDictionary']) }
		else if value != 0 || normalize { owned_string(text) } else { u64(0) }
	if copy == 0 && (value != 0 || normalize || index == 0) { panic('iOS: notification content value allocation failed') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := un_content_storage(object, true)
	un_content_validate_value(index, copy)
	old := state.values[index]
	state.values[index] = copy
	un_content_publish(object, mut state)
	objc_release(old)
}

fn un_content_copy(object u64, mutable bool) u64 {
	C.ios_objc_initialize_lock()
	state := un_content_storage(object, true)
	if !mutable && obj_header(object).allocation_cls == ios_runtime.names['UNNotificationContent'] {
		result := objc_retain(object); C.ios_objc_initialize_unlock(); return result
	}
	mut snapshot := *state
	mut texts := [2]string{}
	for j, i in [4, 6]! {
		if snapshot.values[i] != 0 { texts[j] = un_request_text(snapshot.values[i]).clone() }
	}
	for i, value in snapshot.values { un_content_validate_value(i, value); objc_retain(value) }
	C.ios_objc_initialize_unlock()
	defer { for text in texts { unsafe { text.free() } } }
	// Copies freeze even the two retained properties before constructors reenter.
	for j, i in [4, 6]! {
		if snapshot.values[i] == 0 { continue }
		objc_release(snapshot.values[i])
		snapshot.values[i] = owned_string(texts[j])
		if snapshot.values[i] == 0 {
			for value in snapshot.values { objc_release(value) }
			return 0
		}
	}
	copy := objc_allocate(ios_runtime.names[if mutable { 'UNMutableNotificationContent' } else { 'UNNotificationContent' }])
	if copy == 0 { for value in snapshot.values { objc_release(value) }; return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	un_content_pristine(copy)
	for i, value in snapshot.values { un_content_validate_value(i, value) }
	mut destination := un_content_storage(copy, false)
	unsafe { *destination = snapshot }
	un_content_publish(copy, mut destination)
	return copy
}

fn un_content_get(object u64, index int) u64 {
	C.ios_objc_initialize_lock()
	state := un_content_storage(object, true)
	value := state.values[index]
	un_content_validate_value(index, value)
	if index !in [4, 6]! || value == 0 {
		C.ios_objc_initialize_unlock()
		return value
	}
	text := un_request_text(value).clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	copy := owned_string(text)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	un_content_validate_value(index, copy)
	return objc_autorelease(copy)
}

fn un_content_dispose(object u64, mut header ObjHeader) {
	if header.un_content == unsafe { nil } { return }
	for value in header.un_content.values { objc_release(value) }
	unsafe { C.memset(voidptr(object + 8), 0, 288); C.free(header.un_content) }
	header.un_content = unsafe { nil }
}

fn un_content_types(name string, meta bool, selector string) ?string {
	if meta || name !in ['UNNotificationContent', 'UNMutableNotificationContent']! { return none }
	if selector in ['init', 'copy', 'mutableCopy']! || selector in un_content_properties() { return '@16@0:8' }
	if selector in ['copyWithZone:', 'mutableCopyWithZone:']! { return '@24@0:8^{_NSZone=}16' }
	if selector in ['summaryArgumentCount', 'interruptionLevel']! { return 'Q16@0:8' }
	if selector == 'relevanceScore' { return 'd16@0:8' }
	if name == 'UNMutableNotificationContent' {
		if selector == 'setRelevanceScore:' { return 'v24@0:8d16' }
		if selector in ['setSummaryArgumentCount:', 'setInterruptionLevel:']! { return 'v24@0:8Q16' }
		if selector in un_content_setters() { return 'v24@0:8@16' }
	}
	return none
}

fn un_content_unsupported(selector string) bool {
	return selector in ['supportsSecureCoding', 'initWithCoder:', 'encodeWithCoder:', 'classForCoder',
		'isEqual:', 'hash', 'description', 'debugDescription', 'contentByUpdatingWithProvider:error:',
		'enterSecurityScope', 'leaveSecurityScope', 'removeSecurityScope', 'addSecurityScope:',
		'setMarkedMutableCopyMessage:', 'markedMutableCopyMessage']!
}

fn un_content_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	mut cls := if meta { object } else { read64(object) }
	mut owned := un_content_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { if header.un_content != unsafe { nil } { owned = true; cls = header.allocation_cls } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if un_content_unsupported(selector) { panic('iOS: notification content option is not implemented') }
	info := ios_runtime.classes[cls] or { panic('iOS: missing notification content class') }
	if un_content_types(info.name, meta, selector) == none { return false }
	match selector {
		'init' { frame.x[0] = un_content_initialize(object) }
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:' {
			if selector.ends_with('WithZone:') && frame.x[2] != 0 { panic('iOS: notification content copy zones are not implemented') }
			frame.x[0] = un_content_copy(object, selector.starts_with('mutable'))
		}
		else {
			properties := un_content_properties()
			for i, setter in un_content_setters() {
				if selector == setter { un_content_set(object, i, frame.x[2]); return true }
			}
			for i, property in properties {
				if selector == property { frame.x[0] = un_content_get(object, i); return true }
			}
			C.ios_objc_initialize_lock()
			mut state := un_content_storage(object, true)
			if selector.starts_with('set') && cls != ios_runtime.names['UNMutableNotificationContent'] { panic('iOS: notification content is immutable') }
			match selector {
				'summaryArgumentCount' { frame.x[0] = state.count }
				'interruptionLevel' { frame.x[0] = state.interruption }
				'relevanceScore' { frame_float_return(mut frame, 0, state.score) }
				'setSummaryArgumentCount:' { state.count = frame.x[2]; un_content_publish(object, mut state) }
				'setInterruptionLevel:' { state.interruption = frame.x[2]; un_content_publish(object, mut state) }
				'setRelevanceScore:' {
					value := frame_double(frame, 0)
					if math.is_nan(value) { panic('iOS: notification relevance requires a number') }
					state.score = math.max(0.0, math.min(1.0, value)); un_content_publish(object, mut state)
				}
				else { panic('iOS: unknown notification content property') }
			}
			C.ios_objc_initialize_unlock()
		}
	}
	return true
}
