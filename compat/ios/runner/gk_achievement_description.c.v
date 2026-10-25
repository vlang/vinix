// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Locally constructed descriptions have empty metadata on native GameKit.
// The 24-byte instance is opaque; server loading and image factories still
// require a Game Center backend and are deliberately unavailable.
fn achievement_description_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GKAchievementDescription' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GKAchievementDescription superclass chain')
}

fn achievement_description_install(cls u64, caller_storage bool) {
	if achievement_description_family(cls) && (caller_storage || cls != ios_runtime.names['GKAchievementDescription']) {
		panic('iOS: GKAchievementDescription requires built-in allocation')
	}
}

fn achievement_description_types(name string, meta bool, selector string) ?string {
	if name != 'GKAchievementDescription' || meta { return none }
	return match selector {
		'init', 'identifier', 'groupIdentifier', 'title', 'achievedDescription',
		'unachievedDescription', 'image', 'rarityPercent', 'activityIdentifier',
		'activityProperties' { '@16@0:8' }
		// The forwarded native getter uses unsigned short, despite NSInteger in
		// the SDK declaration. Preserve the measured Objective-C signature.
		'maximumPoints' { 'S16@0:8' }
		'isHidden', 'isReplayable' { 'B16@0:8' }
		'releaseState' { 'Q16@0:8' }
		else { return none }
	}
}

fn achievement_description_unsupported(selector string) bool {
	return selector.starts_with('set') || (selector.starts_with('init') && selector != 'init')
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:',
		'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:',
		'removeObserver:forKeyPath:context:', 'loadAchievementDescriptionsWithCompletionHandler:',
		'loadImageWithCompletionHandler:', 'incompleteAchievementImage', 'placeholderCompletedAchievementImage']!
}

// Validate allocation identity as well as isa: changing raw memory cannot turn
// an NSObject or caller-owned buffer into a description.
fn achievement_description_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['GKAchievementDescription'] || header.caller_storage
		|| header.native_size != 24 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: GKAchievementDescription requires live built-in storage')
	}
	if initialized && !header.achievement_description_initialized {
		panic('iOS: GKAchievementDescription requires initialization')
	}
	return header
}

fn achievement_description_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := achievement_description_storage(object, false)
	header.achievement_description_initialized = true
	return object
}

fn achievement_description_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !achievement_description_family(cls) { return false }
	if achievement_description_unsupported(selector) {
		panic('iOS: unsupported GKAchievementDescription method: ' + selector)
	}
	if achievement_description_types('GKAchievementDescription', meta, selector) == none { return false }
	if selector == 'init' {
		frame.x[0] = achievement_description_initialize(object)
		return true
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	achievement_description_storage(object, true)
	frame.x[0] = 0
	return true
}
