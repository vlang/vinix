// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Local metadata only. Remote matches need Game Center services. Native copying
// returns GKTurnBasedMatchInternal, a separate representation not modeled here.
// The native 40-byte instance remains opaque; owned message state is private.
fn turn_match_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GKTurnBasedMatch' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKTurnBasedMatch superclass chain')
}

fn turn_match_install(cls u64, caller_storage bool) {
	if turn_match_family(cls) && (caller_storage || cls != ios_runtime.names['GKTurnBasedMatch']) {
		panic('iOS: GKTurnBasedMatch requires built-in allocation')
	}
}

fn turn_match_types(name string, meta bool, selector string) ?string {
	if name != 'GKTurnBasedMatch' { return none }
	if meta { return if selector == 'init' { '@16@0:8' } else { none } }
	return match selector {
		'init', 'matchID', 'creationDate', 'participants', 'currentParticipant', 'matchData',
		'message', 'exchanges', 'activeExchanges', 'completedExchanges' { '@16@0:8' }
		'status' { 'q16@0:8' }
		'matchDataMaximumSize', 'exchangeDataMaximumSize', 'exchangeMaxInitiatedExchangesPerPlayer' { 'Q16@0:8' }
		'setMessage:' { 'v24@0:8@16' }
		else { return none }
	}
}

fn turn_match_unsupported(selector string) bool {
	return (selector.starts_with('set') && selector != 'setMessage:')
		|| (selector.starts_with('init') && selector != 'init')
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:',
		'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:',
		'findMatchForRequest:withCompletionHandler:', 'loadMatchesWithCompletionHandler:',
		'loadMatchWithID:withCompletionHandler:', 'rematchWithCompletionHandler:',
		'acceptInviteWithCompletionHandler:', 'declineInviteWithCompletionHandler:',
		'removeWithCompletionHandler:', 'loadMatchDataWithCompletionHandler:',
		'endTurnWithNextParticipants:turnTimeout:matchData:completionHandler:',
		'participantQuitInTurnWithOutcome:nextParticipants:turnTimeout:matchData:completionHandler:',
		'participantQuitOutOfTurnWithOutcome:withCompletionHandler:',
		'endMatchInTurnWithMatchData:completionHandler:',
		'endMatchInTurnWithMatchData:scores:achievements:completionHandler:',
		'endMatchInTurnWithMatchData:leaderboardScores:achievements:completionHandler:',
		'saveCurrentTurnWithMatchData:completionHandler:', 'saveMergedMatchData:withResolvedExchanges:completionHandler:',
		'sendExchangeToParticipants:data:localizableMessageKey:arguments:timeout:completionHandler:',
		'sendReminderToParticipants:localizableMessageKey:arguments:completionHandler:',
		'endTurnWithNextParticipant:matchData:completionHandler:',
		'participantQuitInTurnWithOutcome:nextParticipant:matchData:completionHandler:']!
}

fn turn_match_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['GKTurnBasedMatch'] || header.caller_storage
		|| header.native_size != 40 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKTurnBasedMatch requires live built-in storage')
	}
	if initialized && !header.turn_match_initialized { panic('iOS: GKTurnBasedMatch requires initialization') }
	return header
}

fn turn_match_message(object u64) {
	if object == 0 { return }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.destroyed || header.releasing || header.caller_storage
			|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: match message requires a built-in initialized string')
		}
	}
	if _ := cf_string_compare_text(object) { return }
	panic('iOS: match message requires a live UTF8 string')
}

fn turn_match_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := turn_match_storage(object, false)
	old := header.fields[0]
	header.fields[0] = 0
	header.turn_match_initialized = true
	C.ios_objc_initialize_unlock()
	objc_release(old)
	return object
}

fn turn_match_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !turn_match_family(cls) { return false }
	if turn_match_unsupported(selector) { panic('iOS: unsupported GKTurnBasedMatch method: ' + selector) }
	info := ios_runtime.classes[cls] or { return false }
	if turn_match_types(info.name, meta, selector) == none { return false }
	if meta { panic('iOS: GKTurnBasedMatch cannot initialize a class object') }
	if selector == 'init' { frame.x[0] = turn_match_initialize(object); return true }
	C.ios_objc_initialize_lock()
	mut header := turn_match_storage(object, true)
	match selector {
		'message' { frame.x[0] = objc_autorelease(objc_retain(header.fields[0])) }
		'setMessage:' {
			value := frame.x[2]
			turn_match_message(value)
			old := header.fields[0]
			// Native retains even mutable strings; it does not take a snapshot.
			header.fields[0] = objc_retain(value)
			frame.x[0] = 0
			C.ios_objc_initialize_unlock()
			objc_release(old)
			return true
		}
		'matchDataMaximumSize' { frame.x[0] = 65536 }
		'exchangeDataMaximumSize' { frame.x[0] = 1024 }
		'exchangeMaxInitiatedExchangesPerPlayer' { frame.x[0] = 30 }
		else { frame.x[0] = 0 }
	}
	C.ios_objc_initialize_unlock()
	return true
}
