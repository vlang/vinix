// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Local progress only. Reporting, players and server-loaded achievements need
// a Game Center backend. Native forwarded properties use private shim state;
// the native 40-byte instance is an opaque reserve, not invented public ivars.
fn achievement_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GKAchievement' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKAchievement superclass chain')
}

fn achievement_install(cls u64, caller_storage bool) {
	if achievement_family(cls) && (caller_storage || cls != ios_runtime.names['GKAchievement']) {
		panic('iOS: GKAchievement requires built-in allocation')
	}
}

fn achievement_types(name string, meta bool, selector string) ?string {
	if name != 'GKAchievement' || meta { return none }
	return match selector {
		'init', 'identifier', 'lastReportedDate' { '@16@0:8' }
		'initWithIdentifier:' { '@24@0:8@16' }
		'setIdentifier:' { 'v24@0:8@16' }
		'percentComplete' { 'd16@0:8' }
		'setPercentComplete:' { 'v24@0:8d16' }
		'isCompleted', 'showsCompletionBanner' { 'B16@0:8' }
		'setShowsCompletionBanner:' { 'v20@0:8B16' }
		else { return none }
	}
}

fn achievement_unsupported(selector string) bool {
	return (selector.starts_with('set') && selector !in ['setIdentifier:', 'setPercentComplete:', 'setShowsCompletionBanner:']!)
		|| (selector.starts_with('init') && selector !in ['init', 'initWithIdentifier:']!)
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:',
		'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:',
		'removeObserver:forKeyPath:context:', 'player', 'playerID', 'isHidden',
		'loadAchievementsWithCompletionHandler:', 'resetAchievementsWithCompletionHandler:',
		'reportAchievements:withCompletionHandler:', 'reportAchievementWithCompletionHandler:']!
}

// All state access is serialized by the recursive runtime lock. An isa change
// cannot grant storage rights, and constructor callbacks cannot access a half
// initialized object or consume the caller's receiver reference unnoticed.
fn achievement_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['GKAchievement'] || header.caller_storage
		|| header.native_size != 40 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKAchievement requires live built-in storage')
	}
	if header.achievement_initializing { panic('iOS: GKAchievement initialization is active') }
	if initialized && !header.achievement_initialized { panic('iOS: GKAchievement requires initialization') }
	return header
}

fn achievement_identifier(object u64) {
	if object == 0 { return }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.destroyed || header.releasing
			|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: achievement identifier requires a built-in initialized string')
		}
	}
	if _ := cf_string_compare_text(object) { return }
	panic('iOS: achievement identifier requires a live UTF8 string')
}

fn achievement_retire(header &ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.achievement_initializing { panic('iOS: destroying an active GKAchievement') }
	// Generic field destruction releases the identifier and creation date.
}

fn achievement_initialize(object u64, identifier u64, default_identifier bool) u64 {
	C.ios_objc_initialize_lock()
	mut header := achievement_storage(object, false)
	achievement_identifier(identifier)
	old_identifier := header.fields[0]
	old_date := header.fields[1]
	input := objc_retain(identifier)
	objc_retain(object)
	header.achievement_initializing = true
	C.ios_objc_initialize_unlock()
	defer { objc_release(input); objc_release(object) }
	name := if default_identifier { owned_string('*uninitialized achievement identifier*') } else { objc_retain(input) }
	defer { objc_release(name) }
	date := if !default_identifier || name != 0 { objc_allocate(cf_date_id()) } else { u64(0) }
	defer { objc_release(date) }
	if date != 0 { ns_date_initialize(date, cf_absolute_time()) }
	C.ios_objc_initialize_lock()
	header = obj_header(object)
	// Temporarily clear the busy flag only while holding the lock to reuse the
	// live-storage validation. No application callback runs in this interval.
	if !header.achievement_initializing { panic('iOS: achievement constructor changed destination storage') }
	header.achievement_initializing = false
	achievement_storage(object, false)
	if header.fields[0] != old_identifier || header.fields[1] != old_date
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 {
		panic('iOS: achievement constructor changed destination storage or consumed receiver ownership')
	}
	if date == 0 {
		C.ios_objc_initialize_unlock()
		// Failed initializers consume one receiver reference. Our pin keeps it
		// live until all temporary references have been released.
		objc_release(object)
		return 0
	}
	header.achievement_initializing = true
	header.fields[0] = objc_retain(name)
	header.fields[1] = objc_retain(date)
	header.achievement_percent = 0
	header.achievement_banner = true
	header.achievement_initialized = true
	C.ios_objc_initialize_unlock()
	objc_release(old_identifier)
	objc_release(old_date)
	C.ios_objc_initialize_lock()
	header.achievement_initializing = false
	C.ios_objc_initialize_unlock()
	return object
}

fn achievement_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !achievement_family(cls) { return false }
	if achievement_unsupported(selector) { panic('iOS: unsupported GKAchievement method: ' + selector) }
	if achievement_types('GKAchievement', meta, selector) == none { return false }
	if selector in ['init', 'initWithIdentifier:']! {
		frame.x[0] = achievement_initialize(object, if selector == 'init' { u64(0) } else { frame.x[2] }, selector == 'init')
		return true
	}
	C.ios_objc_initialize_lock()
	mut header := achievement_storage(object, true)
	match selector {
		'identifier', 'lastReportedDate' {
			frame.x[0] = objc_autorelease(objc_retain(header.fields[if selector == 'identifier' { 0 } else { 1 }]))
		}
		'setIdentifier:' {
			value := frame.x[2]
			achievement_identifier(value)
			old := header.fields[0]
			header.fields[0] = objc_retain(value)
			frame.x[0] = 0
			C.ios_objc_initialize_unlock()
			objc_release(old)
			return true
		}
		'percentComplete' { frame_float_return(mut frame, 0, header.achievement_percent) }
		'setPercentComplete:' { header.achievement_percent = frame_double(frame, 0); frame.x[0] = 0 }
		'isCompleted' { frame.x[0] = u64(header.achievement_percent >= 100) }
		'showsCompletionBanner' { frame.x[0] = u64(header.achievement_banner) }
		'setShowsCompletionBanner:' { header.achievement_banner = u8(frame.x[2]) != 0; frame.x[0] = 0 }
		else {}
	}
	C.ios_objc_initialize_unlock()
	return true
}
