// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Resolve image class metadata without claiming timed press input.
fn long_press_descriptor_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		if current == 0 { return false }
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UILongPressGestureRecognizer' { return true }
		current = info.parent
	}
	return false
}

fn long_press_descriptor_unsupported(selector string) bool {
	return selector.starts_with('init') || selector in ['alloc', 'allocWithZone:', 'new',
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn long_press_descriptor_require_recognition(cls u64) {
	if long_press_descriptor_family(cls) {
		panic('iOS: long press gesture construction requires an implemented timed press lifecycle')
	}
}
