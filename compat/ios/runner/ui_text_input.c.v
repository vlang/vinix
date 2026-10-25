// SPDX-License-Identifier: GPL-2.0-or-later
module main

// UITextInput.h defines these as abstract NSObject subclasses. Positions and
// endpoints belong to the application's subclasses, not a fabricated offset
// or an empty range in the UIKit shim.
fn text_input_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name in ['UITextPosition', 'UITextRange']! { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic text input superclass chain')
}

fn text_input_unsupported(selector string) bool {
	return (selector.starts_with('initWith')) || selector in ['copy', 'copyWithZone:',
		'mutableCopy', 'mutableCopyWithZone:', 'encodeWithCoder:', 'classForCoder',
		'supportsSecureCoding']!
}

fn text_input_types(name string, meta bool, selector string) ?string {
	if meta || name != 'UITextRange' { return none }
	return match selector {
		'isEmpty' { 'B16@0:8' }
		'start', 'end' { '@16@0:8' }
		else { none }
	}
}

fn text_input_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	cls := if object in ios_runtime.classes { object } else { read64(object) }
	if !text_input_family(cls) { return false }
	if text_input_unsupported(selector) {
		panic('iOS: text input copy, coding and specialized initialization require a subclass implementation')
	}
	// Native subclass methods have already been selected by objc_dispatch.
	if object !in ios_runtime.classes && selector in ['isEmpty', 'start', 'end']!
		&& objc_is_kind(object, ios_runtime.names['UITextRange']) {
		panic('iOS: abstract UITextRange getter requires a subclass implementation: ' + selector)
	}
	return false
}
