// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Empty local participant metadata only. Matchmaking and remote participants
// require Game Center services, which are not implemented.
fn turn_participant_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GKTurnBasedParticipant' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKTurnBasedParticipant superclass chain')
}

fn turn_participant_install(cls u64, caller_storage bool) {
	if turn_participant_family(cls) && (caller_storage || cls != ios_runtime.names['GKTurnBasedParticipant']) {
		panic('iOS: GKTurnBasedParticipant requires built-in allocation')
	}
}

fn turn_participant_types(name string, meta bool, selector string) ?string {
	if name != 'GKTurnBasedParticipant' { return none }
	if meta {
		return match selector {
			'init', 'copy' { '@16@0:8' }
			'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'player', 'playerID', 'lastTurnDate', 'timeoutDate', 'copy' { '@16@0:8' }
		'status' { 'q16@0:8' }
		// The native forwarding signature is unsigned int, despite the SDK's
		// NSInteger declaration. Match its measured truncation and return ABI.
		'matchOutcome' { 'I16@0:8' }
		'setMatchOutcome:' { 'v20@0:8I16' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		else { return none }
	}
}

fn turn_participant_unsupported(selector string) bool {
	return (selector.starts_with('set') && selector != 'setMatchOutcome:')
		|| (selector.starts_with('init') && selector != 'init')
		|| selector in ['mutableCopy', 'mutableCopyWithZone:', 'encodeWithCoder:', 'supportsSecureCoding',
		'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'addObserver:forKeyPath:options:context:',
		'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:']!
}

fn turn_participant_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['GKTurnBasedParticipant'] || header.caller_storage
		|| header.native_size != 16 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKTurnBasedParticipant requires live built-in storage')
	}
	if initialized && !header.turn_participant_initialized { panic('iOS: GKTurnBasedParticipant requires initialization') }
	return header
}

fn turn_participant_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := turn_participant_storage(object, false)
	header.turn_participant_outcome = 0
	header.turn_participant_initialized = true
	return object
}

fn turn_participant_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := turn_participant_storage(object, true)
	copy := turn_participant_initialize(objc_allocate(header.cls))
	obj_header(copy).turn_participant_outcome = header.turn_participant_outcome
	return copy
}

fn turn_participant_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !turn_participant_family(cls) { return false }
	if turn_participant_unsupported(selector) { panic('iOS: unsupported GKTurnBasedParticipant method: ' + selector) }
	info := ios_runtime.classes[cls] or { return false }
	if turn_participant_types(info.name, meta, selector) == none { return false }
	if meta {
		if selector == 'init' { panic('iOS: GKTurnBasedParticipant cannot initialize a class object') }
		frame.x[0] = object
		return true
	}
	if selector == 'init' { frame.x[0] = turn_participant_initialize(object); return true }
	if selector in ['copy', 'copyWithZone:']! { frame.x[0] = turn_participant_copy(object); return true }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := turn_participant_storage(object, true)
	if selector == 'setMatchOutcome:' { header.turn_participant_outcome = u32(frame.x[2]); return true }
	frame.x[0] = if selector == 'matchOutcome' { u64(header.turn_participant_outcome) } else { u64(0) }
	return true
}
