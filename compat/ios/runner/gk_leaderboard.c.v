// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Local metadata measured on arm64 Mac Catalyst. The native 88-byte instance
// stays opaque; scopes, range and the retained identifier live in ObjHeader.
// Remote leaderboards, copying and coding need separate implementations.
fn leaderboard_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GKLeaderboard' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKLeaderboard superclass chain')
}

fn leaderboard_install(cls u64, caller_storage bool) {
	if leaderboard_family(cls) && (caller_storage || cls != ios_runtime.names['GKLeaderboard']) {
		panic('iOS: GKLeaderboard requires built-in allocation')
	}
}

fn leaderboard_types(name string, meta bool, selector string) ?string {
	if name != 'GKLeaderboard' { return none }
	if meta { return if selector == 'init' { '@16@0:8' } else { none } }
	return match selector {
		'init', 'title', 'groupIdentifier', 'baseLeaderboardID', 'startDate', 'nextStartDate',
		'category', 'identifier', 'scores', 'localPlayerScore' { '@16@0:8' }
		'type', 'timeScope', 'playerScope' { 'q16@0:8' }
		'maxRange' { 'Q16@0:8' }
		'duration' { 'd16@0:8' }
		'isLoading' { 'B16@0:8' }
		'setCategory:', 'setIdentifier:' { 'v24@0:8@16' }
		'setTimeScope:', 'setPlayerScope:' { 'v24@0:8q16' }
		'range' { '{_NSRange=QQ}16@0:8' }
		'setRange:' { 'v32@0:8{_NSRange=QQ}16' }
		else { return none }
	}
}

fn leaderboard_unsupported(selector string) bool {
	return (selector.starts_with('set') && selector !in ['setCategory:', 'setIdentifier:', 'setTimeScope:', 'setPlayerScope:', 'setRange:']!)
		|| (selector.starts_with('init') && selector != 'init')
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:',
		'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:',
		'loadLeaderboardsWithIDs:completionHandler:', 'loadPreviousOccurrenceWithCompletionHandler:',
		'submitScore:context:player:leaderboardIDs:completionHandler:', 'submitScore:context:player:completionHandler:',
		'loadEntriesForPlayerScope:timeScope:range:completionHandler:', 'loadEntriesForPlayers:timeScope:completionHandler:',
		'loadCategoriesWithCompletionHandler:', 'loadScoresWithCompletionHandler:',
		'loadLeaderboardsWithCompletionHandler:', 'loadImageWithCompletionHandler:']!
}

fn leaderboard_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['GKLeaderboard'] || header.caller_storage
		|| header.native_size != 88 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKLeaderboard requires live built-in storage')
	}
	if initialized && !header.leaderboard_initialized { panic('iOS: GKLeaderboard requires initialization') }
	return header
}

fn leaderboard_identifier(object u64) {
	if object == 0 { return }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.destroyed || header.releasing || header.caller_storage
			|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: leaderboard identifier requires a built-in initialized string')
		}
	}
	if _ := cf_string_compare_text(object) { return }
	panic('iOS: leaderboard identifier requires a live UTF8 string')
}

fn leaderboard_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := leaderboard_storage(object, false)
	old := header.fields[0]
	header.fields[0] = 0
	header.leaderboard_values = [u64(2), 0, 1, 25]!
	header.leaderboard_initialized = true
	C.ios_objc_initialize_unlock()
	objc_release(old)
	return object
}

fn leaderboard_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !leaderboard_family(cls) { return false }
	if leaderboard_unsupported(selector) { panic('iOS: unsupported GKLeaderboard method: ' + selector) }
	info := ios_runtime.classes[cls] or { return false }
	if leaderboard_types(info.name, meta, selector) == none { return false }
	if meta { panic('iOS: GKLeaderboard cannot initialize a class object') }
	if selector == 'init' { frame.x[0] = leaderboard_initialize(object); return true }
	C.ios_objc_initialize_lock()
	mut header := leaderboard_storage(object, true)
	match selector {
		'identifier', 'category' { frame.x[0] = objc_autorelease(objc_retain(header.fields[0])) }
		'setIdentifier:', 'setCategory:' {
			value := frame.x[2]
			leaderboard_identifier(value)
			old := header.fields[0]
			// Native retains mutable strings despite the SDK's copy annotation.
			header.fields[0] = objc_retain(value)
			frame.x[0] = 0
			C.ios_objc_initialize_unlock()
			objc_release(old)
			return true
		}
		'timeScope' { frame.x[0] = header.leaderboard_values[0] }
		'playerScope' { frame.x[0] = header.leaderboard_values[1] }
		'setTimeScope:' { header.leaderboard_values[0] = frame.x[2]; frame.x[0] = 0 }
		'setPlayerScope:' { header.leaderboard_values[1] = frame.x[2]; frame.x[0] = 0 }
		'range' { frame.x[0] = header.leaderboard_values[2]; frame.x[1] = header.leaderboard_values[3] }
		'setRange:' {
			// Native raises NSRangeException here. Until exceptions are modeled,
			// reject invalid ranges explicitly instead of accepting invalid state.
			if frame.x[2] == 0 || frame.x[3] > 100 { panic('iOS: GKLeaderboard range requires location >= 1 and length <= 100') }
			header.leaderboard_values[2] = frame.x[2]; header.leaderboard_values[3] = frame.x[3]
			frame.x[0] = 0
		}
		'duration' { frame_float_return(mut frame, 0, 0) }
		else { frame.x[0] = 0 }
	}
	C.ios_objc_initialize_unlock()
	return true
}
