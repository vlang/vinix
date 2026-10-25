// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Class descriptors allow image metadata to link. Continuous pan recognition
// needs a touch lifecycle; the discrete swipe dispatcher cannot implement it.
fn pan_descriptor_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		if current == 0 { return false }
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UIPanGestureRecognizer' { return true }
		current = info.parent
	}
	return false
}

fn pan_descriptor_unsupported(selector string) bool {
	return selector.starts_with('init') || selector in ['alloc', 'allocWithZone:', 'new',
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn pan_descriptor_require_recognition(cls u64) {
	if pan_descriptor_family(cls) {
		panic('iOS: pan gesture construction requires an implemented continuous touch lifecycle')
	}
}
