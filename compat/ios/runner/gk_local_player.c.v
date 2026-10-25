// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Unauthenticated defaults measured on arm64 Mac Catalyst. GKPlayer owns
// the alias and validates the opaque native storage. No account is signed in.
fn local_player_types(name string, meta bool, selector string) ?string {
	if name != 'GKLocalPlayer' { return none }
	if meta { return if selector in ['localPlayer', 'local']! { '@16@0:8' } else { none } }
	if selector == 'authenticateHandler' { return '@?16@0:8' }
	if selector in ['isAuthenticated', 'isUnderage', 'isMultiplayerGamingRestricted', 'isPersonalizedCommunicationRestricted']! { return 'B16@0:8' }
	return none
}

fn local_player_unsupported(selector string) bool {
	return selector == 'friends' || selector == 'isPresentingFriendRequestViewController'
		|| selector.starts_with('load') || selector.starts_with('save')
		|| selector.starts_with('delete') || selector.starts_with('fetch')
		|| selector.starts_with('generate') || (selector.starts_with('authenticate') && selector != 'authenticateHandler')
		|| selector.starts_with('register') || selector.starts_with('unregister')
		|| selector.starts_with('present') || selector.starts_with('resolve')
}

fn local_player_default() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.gk_local_player == 0 {
		ios_runtime.gk_local_player = gk_player_initialize(objc_allocate(ios_runtime.names['GKLocalPlayer']))
	}
	return ios_runtime.gk_local_player
}

fn local_player_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	info := ios_runtime.classes[cls] or { return false }
	if info.name != 'GKLocalPlayer' { return false }
	if local_player_unsupported(selector) { panic('iOS: unsupported GKLocalPlayer method: ' + selector) }
	if local_player_types(info.name, meta, selector) == none { return false }
	if meta { frame.x[0] = local_player_default(); return true }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	gk_player_storage(object, true)
	frame.x[0] = if selector in ['isMultiplayerGamingRestricted', 'isPersonalizedCommunicationRestricted']! { u64(1) } else { u64(0) }
	return true
}
