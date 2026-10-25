// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Numeric request configuration only. Matchmaking, recipients and rules need
// a Game Center backend. The native 40-byte object is an opaque reserve;
// forwarded native properties live in private shim state, not invented ivars.
fn match_request_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GKMatchRequest' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKMatchRequest superclass chain')
}

fn match_request_install(cls u64, caller_storage bool) {
	if match_request_family(cls) && (caller_storage || cls != ios_runtime.names['GKMatchRequest']) {
		panic('iOS: GKMatchRequest requires built-in allocation')
	}
}

fn match_request_property(selector string) int {
	return match selector {
		'minPlayers', 'setMinPlayers:' { 0 }
		'maxPlayers', 'setMaxPlayers:' { 1 }
		'playerGroup', 'setPlayerGroup:' { 2 }
		'playerAttributes', 'setPlayerAttributes:' { 3 }
		'defaultNumberOfPlayers', 'setDefaultNumberOfPlayers:' { 4 }
		'restrictToAutomatch', 'setRestrictToAutomatch:' { 5 }
		else { -1 }
	}
}

fn match_request_unsupported(selector string) bool {
	return (selector.starts_with('set') && match_request_property(selector) < 0)
		|| (selector.starts_with('init') && selector != 'init')
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:',
		'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:',
		'removeObserver:forKeyPath:context:', 'recipients', 'playersToInvite', 'inviteMessage',
		'recipientResponseHandler', 'inviteeResponseHandler', 'queueName', 'properties',
		'recipientProperties', 'maxPlayersAllowedForMatchOfType:']!
}

fn match_request_types(name string, meta bool, selector string) ?string {
	if name != 'GKMatchRequest' || meta { return none }
	if selector == 'init' { return '@16@0:8' }
	index := match_request_property(selector)
	if index < 0 { return none }
	// Native NSMethodSignature exposes these forwarded ABI types. In
	// particular the three player counts use unsigned char, not NSUInteger.
	type_code := ['C', 'C', 'Q', 'I', 'C', 'B']![index]
	return if selector.starts_with('set') { (if index == 2 { 'v24@0:8' } else { 'v20@0:8' }) + type_code + '16' } else { type_code + '16@0:8' }
}

fn match_request_storage(object u64, initialized bool) {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['GKMatchRequest'] || header.caller_storage
		|| header.native_size != 40 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKMatchRequest requires live built-in storage')
	}
	if initialized && !header.match_request_initialized { panic('iOS: GKMatchRequest requires initialization') }
}

fn match_request_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	match_request_storage(object, false)
	mut header := obj_header(object)
	header.match_request_values = [u64(2), 2, 1, 0xffffffff, 0, 0]!
	header.match_request_initialized = true
	return object
}

fn match_request_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !match_request_family(cls) { return false }
	if match_request_unsupported(selector) { panic('iOS: unsupported GKMatchRequest method: ' + selector) }
	if match_request_types('GKMatchRequest', meta, selector) == none { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	match_request_storage(object, selector != 'init')
	if selector == 'init' { frame.x[0] = match_request_initialize(object); return true }
	index := match_request_property(selector)
	mut header := obj_header(object)
	if selector.starts_with('set') {
		value := frame.x[2]
		header.match_request_values[index] = if index == 2 { value } else if index == 3 { u64(u32(value)) } else { u64(u8(value)) }
		frame.x[0] = 0
	} else { frame.x[0] = header.match_request_values[index] }
	return true
}
