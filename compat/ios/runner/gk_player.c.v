// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Only local, unauthenticated profile metadata is available. Scoped identity,
// guest factories, photos and online operations require additional support.
fn gk_player_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name in ['GKBasePlayer', 'GKPlayer']! { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKPlayer superclass chain')
}

fn gk_player_install(cls u64, caller_storage bool) {
	if gk_player_family(cls) && (caller_storage || cls !in [ios_runtime.names['GKBasePlayer'], ios_runtime.names['GKPlayer']]!) {
		panic('iOS: GKPlayer requires built-in allocation')
	}
}

fn gk_player_types(name string, meta bool, selector string) ?string {
	if name !in ['GKBasePlayer', 'GKPlayer']! || meta { return none }
	if selector in ['init', 'playerID', 'displayName', 'copy']! { return '@16@0:8' }
	if selector == 'copyWithZone:' { return '@24@0:8^{_NSZone=}16' }
	if name == 'GKPlayer' {
		if selector in ['alias', 'guestIdentifier']! { return '@16@0:8' }
		if selector in ['isFriend', 'isInvitable', 'scopedIDsArePersistent']! { return 'B16@0:8' }
	}
	return none
}

fn gk_player_unsupported(selector string) bool {
	return selector.starts_with('set') || (selector.starts_with('init') && selector != 'init')
		|| selector in ['mutableCopy', 'mutableCopyWithZone:', 'encodeWithCoder:', 'supportsSecureCoding',
		'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'addObserver:forKeyPath:options:context:',
		'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'gamePlayerID', 'teamPlayerID',
		'anonymousGuestPlayerWithIdentifier:', 'loadPlayersForIdentifiers:withCompletionHandler:',
		'loadPhotoForSize:withCompletionHandler:', 'loadFriendPlayersWithCompletionHandler:',
		'loadFriendsAuthorizationStatusWithCompletionHandler:', 'loadFriendsWithCompletionHandler:',
		'loadFriends:withCompletionHandler:', 'loadChallengablePlayersWithCompletionHandler:']!
}

fn gk_player_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	base := ios_runtime.names['GKBasePlayer']
	player := ios_runtime.names['GKPlayer']
	if header.allocation_cls !in [base, player]! || header.caller_storage
		|| header.native_size != (if header.allocation_cls == base { u32(8) } else { u32(32) })
		|| header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKPlayer requires live built-in storage')
	}
	if initialized && !header.gk_player_initialized { panic('iOS: GKPlayer requires initialization') }
	return header
}

fn gk_player_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := gk_player_storage(object, false)
	if !header.gk_player_initialized {
		// Transfer the string's +1 into the generic owned-field array. Object
		// destruction releases it; repeated init must not replace or leak it.
		if header.cls == ios_runtime.names['GKPlayer'] { header.fields[0] = owned_string('Unknown') }
		header.gk_player_initialized = true
	}
	return object
}

fn gk_player_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	gk_player_storage(object, true)
	return objc_retain(object)
}

fn gk_player_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !gk_player_family(cls) { return false }
	if gk_player_unsupported(selector) { panic('iOS: unsupported GKPlayer method: ' + selector) }
	info := ios_runtime.classes[cls] or { return false }
	if gk_player_types(info.name, meta, selector) == none { return false }
	if selector == 'init' { frame.x[0] = gk_player_initialize(object); return true }
	if selector in ['copy', 'copyWithZone:']! { frame.x[0] = gk_player_copy(object); return true }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := gk_player_storage(object, true)
	frame.x[0] = if selector == 'alias' { header.fields[0] } else { u64(0) }
	return true
}
