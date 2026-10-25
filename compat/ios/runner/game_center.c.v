// SPDX-License-Identifier: GPL-2.0-or-later
module main

// These descriptors expose the iOS SDK hierarchy for linking and reflection.
// Navigation stacks and the Game Center service UI are not implemented yet.
// In particular, NSObject's generic constructors must not fabricate either UI.
fn navigation_descriptor_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UINavigationController' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic navigation controller superclass chain')
}

fn navigation_descriptor_unsupported(selector string) bool {
	return selector.starts_with('init') || selector in ['alloc', 'allocWithZone:', 'new',
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn navigation_descriptor_require_ui(cls u64) {
	if navigation_descriptor_family(cls) {
		panic('iOS: navigation and Game Center controller construction requires an implemented UI')
	}
}

fn game_center_symbol(symbol string) ?u64 {
	for name in ['GKGameCenterViewController', 'GKMatchRequest']! {
		cls := ios_runtime.names[name] or { continue }
		if symbol == '_OBJC_CLASS_$_' + name { return cls }
		if symbol == '_OBJC_METACLASS_$_' + name { return read64(cls) }
	}
	return none
}
