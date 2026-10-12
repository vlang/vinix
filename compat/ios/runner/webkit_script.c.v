// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Scripts and content worlds hold registration data. This profile does not
// execute JavaScript or expose WebKit's native inline C++ objects.
const webkit_script_limit = 1024
const webkit_source_limit = 1024 * 1024
const webkit_world_name_limit = 4096

fn webkit_script_types(name string, meta bool, selector string) ?string {
	if meta {
		if name == 'WKContentWorld' {
			if selector in ['pageWorld', 'defaultClientWorld'] { return '@16@0:8' }
			if selector == 'worldWithName:' { return '@24@0:8@16' }
		}
		return none
	}
	if name == 'WKUserScript' {
		return match selector {
			'initWithSource:injectionTime:forMainFrameOnly:' { '@36@0:8@16q24B32' }
			'initWithSource:injectionTime:forMainFrameOnly:inContentWorld:' { '@44@0:8@16q24B32@36' }
			'source', 'copy' { '@16@0:8' }
			'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
			'injectionTime' { 'q16@0:8' }
			'isForMainFrameOnly' { 'B16@0:8' }
			else { return none }
		}
	}
	if name == 'WKContentWorld' && selector == 'name' { return '@16@0:8' }
	if name == 'WKNSArray' {
		return match selector {
			'copy', 'firstObject' { '@16@0:8' }
			'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
			'count' { 'Q16@0:8' }
			'objectAtIndex:', 'objectAtIndexedSubscript:' { '@24@0:8Q16' }
			else { return none }
		}
	}
	return none
}

fn webkit_world(index int, name u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if name != 0 {
		if !objc_is_kind(name, ios_runtime.names['NSString']) { panic('iOS: WebKit world name must be a string') }
		text := string_text(name)
		if text.len > webkit_world_name_limit { panic('iOS: WebKit world name exceeds limit') }
		for slot in 2 .. ios_runtime.webkit_world_count {
			candidate := ios_runtime.webkit_worlds[slot]
			if string_text(obj_header(candidate).webkit.refs[0]) == text { return candidate }
		}
	}
	mut slot := index
	if name != 0 {
		if ios_runtime.webkit_world_count >= ios_runtime.webkit_worlds.len { panic('iOS: WebKit content world limit exceeded') }
		slot = ios_runtime.webkit_world_count
	} else if ios_runtime.webkit_worlds[slot] != 0 { return ios_runtime.webkit_worlds[slot] }
	result := objc_allocate(ios_runtime.names['WKContentWorld'])
	webkit_initialize(result, 'WKContentWorld')
	if name != 0 { obj_header(result).webkit.refs[0] = owned_string(string_text(name)) }
	ios_runtime.webkit_worlds[slot] = result
	if name != 0 { ios_runtime.webkit_world_count++ }
	return result
}

fn webkit_script_initialize(object u64, source u64, injection u64, main_only u64, world u64) {
	if source == 0 || !objc_is_kind(source, ios_runtime.names['NSString']) { panic('iOS: WebKit script source must be a string') }
	if string_text(source).len > webkit_source_limit { panic('iOS: WebKit script source exceeds limit') }
	if injection > 1 { panic('iOS: WebKit script injection time is outside the implemented profile') }
	if world == 0 || !objc_is_kind(world, ios_runtime.names['WKContentWorld']) || obj_header(world).webkit == unsafe { nil } {
		panic('iOS: WebKit script requires an initialized content world')
	}
	if obj_header(object).webkit != unsafe { nil } { panic('iOS: WebKit script reinitialization is not implemented') }
	webkit_initialize(object, 'WKUserScript')
	mut state := obj_header(object).webkit
	state.refs[0] = owned_string(string_text(source))
	state.refs[1] = objc_retain(world)
	state.values[0] = injection
	state.flags[0] = u8(main_only) != 0
}

fn webkit_scripts_array(controller u64) u64 {
	mut state := obj_header(controller).webkit
	if state == unsafe { nil } { panic('iOS: WebKit content controller is not initialized') }
	if state.refs[0] == 0 {
		state.refs[0] = objc_allocate(ios_runtime.names['WKNSArray'])
		obj_header(state.refs[0]).webkit_array = true
	}
	return state.refs[0]
}

fn webkit_scripts_clear(controller u64) {
	state := obj_header(controller).webkit
	if state == unsafe { nil } { panic('iOS: WebKit content controller is not initialized') }
	array := state.refs[0]
	if array == 0 { return }
	mut header := obj_header(array)
	// Removing a tail before releasing it keeps callbacks away from stale slots.
	for header.items.len > 0 { collection_remove(mut header, header.items.len - 1) }
}

fn webkit_script_dispatch(object u64, name string, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes {
		if name != 'WKContentWorld' { return false }
		match selector {
			'pageWorld' { frame.x[0] = webkit_world(0, 0) }
			'defaultClientWorld' { frame.x[0] = webkit_world(1, 0) }
			'worldWithName:' {
				if frame.x[2] == 0 { panic('iOS: WebKit world name must be a string') }
				frame.x[0] = webkit_world(0, frame.x[2])
			}
			else { return false }
		}
		return true
	}
	if name == 'WKUserScript' {
		if selector in ['initWithSource:injectionTime:forMainFrameOnly:', 'initWithSource:injectionTime:forMainFrameOnly:inContentWorld:'] {
			world := if selector.ends_with('inContentWorld:') { frame.x[5] } else { webkit_world(0, 0) }
			webkit_script_initialize(object, frame.x[2], frame.x[3], frame.x[4], world)
			frame.x[0] = object
			return true
		}
		if webkit_script_types(name, false, selector) == none { return false }
		state := obj_header(object).webkit
		if state == unsafe { nil } { panic('iOS: WebKit script is not initialized') }
		match selector {
			'source' { frame.x[0] = state.refs[0] }
			'injectionTime' { frame.x[0] = state.values[0] }
			'isForMainFrameOnly' { frame.x[0] = u64(state.flags[0]) }
			'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
			else { return false }
		}
		return true
	}
	if name == 'WKContentWorld' && selector == 'name' {
		state := obj_header(object).webkit
		if state == unsafe { nil } { panic('iOS: WebKit content world is not initialized') }
		frame.x[0] = state.refs[0]
		return true
	}
	if name == 'WKNSArray' && selector in ['copy', 'copyWithZone:', 'count', 'firstObject', 'objectAtIndex:', 'objectAtIndexedSubscript:', 'countByEnumeratingWithState:objects:count:'] {
		if !obj_header(object).webkit_array { panic('iOS: WebKit script array is not initialized') }
		if selector in ['copy', 'copyWithZone:'] { frame.x[0] = objc_retain(object); return true }
	}
	if name == 'WKUserContentController' {
		match selector {
			'userScripts' { frame.x[0] = webkit_scripts_array(object) }
			'addUserScript:' {
				script := frame.x[2]
				if script == 0 || !objc_is_kind(script, ios_runtime.names['WKUserScript']) || obj_header(script).webkit == unsafe { nil } {
					panic('iOS: WebKit registration requires an initialized user script')
				}
				mut array := obj_header(webkit_scripts_array(object))
				if array.items.len >= webkit_script_limit { panic('iOS: WebKit registered script limit exceeded') }
				array_append(mut array, script)
			}
			'removeAllUserScripts' { webkit_scripts_clear(object) }
			else { return false }
		}
		return true
	}
	return false
}
