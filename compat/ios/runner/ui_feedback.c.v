// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The guest has no haptic hardware. Accept the public feedback requests without
// creating devices, scheduling work, or retaining state in the opaque instance.
fn ui_feedback_name(name string) bool {
	return name in ['UIFeedbackGenerator', 'UINotificationFeedbackGenerator', 'UISelectionFeedbackGenerator', 'UIImpactFeedbackGenerator']!
}

fn ui_feedback_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if ui_feedback_name(info.name) { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic feedback generator superclass chain')
}

fn ui_feedback_types(name string, meta bool, selector string) ?string {
	if meta { return none }
	if name == 'UIFeedbackGenerator' && selector == 'prepare' { return 'v16@0:8' }
	if name == 'UINotificationFeedbackGenerator' && selector == 'notificationOccurred:' { return 'v24@0:8q16' }
	if name == 'UISelectionFeedbackGenerator' && selector == 'selectionChanged' { return 'v16@0:8' }
	if name == 'UIImpactFeedbackGenerator' {
		return match selector {
			'initWithStyle:' { '@24@0:8q16' }
			'impactOccurred' { 'v16@0:8' }
			'impactOccurredWithIntensity:' { 'v24@0:8d16' }
			else { none }
		}
	}
	return none
}

fn ui_feedback_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn ui_feedback_selector(object u64, selector string) bool {
	if object in ios_runtime.classes { return false }
	return match selector {
		'prepare' { objc_is_kind(object, ios_runtime.names['UIFeedbackGenerator']) }
		'notificationOccurred:' { objc_is_kind(object, ios_runtime.names['UINotificationFeedbackGenerator']) }
		'selectionChanged' { objc_is_kind(object, ios_runtime.names['UISelectionFeedbackGenerator']) }
		'initWithStyle:', 'impactOccurred', 'impactOccurredWithIntensity:' { objc_is_kind(object, ios_runtime.names['UIImpactFeedbackGenerator']) }
		else { false }
	}
}

fn ui_feedback_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if ui_feedback_unsupported(selector) && ui_feedback_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		panic('iOS: feedback generator copying or coding is not implemented')
	}
	if !ui_feedback_selector(object, selector) { return false }
	obj_header(object)
	frame.x[0] = if selector == 'initWithStyle:' { object } else { 0 }
	return true
}
