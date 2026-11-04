// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn ui_device_feedback_types(name string, meta bool, selector string) ?string {
	if name != 'UIDevice' || meta { return none }
	return match selector {
		'_feedbackSupportLevel' { 'q16@0:8' }
		'valueForKey:' { '@24@0:8@16' }
		else { none }
	}
}

fn ui_device_feedback_selector(object u64, selector string) bool {
	return object !in ios_runtime.classes && objc_is_kind(object, ios_runtime.names['UIDevice'])
		&& selector in ['_feedbackSupportLevel', 'valueForKey:']!
}

fn ui_device_feedback_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !ui_device_feedback_selector(object, selector) { return false }
	if selector == '_feedbackSupportLevel' {
		frame.x[0] = 0 // No feedback actuator, matching the feedback-generator backend.
		return true
	}
	key := frame.x[2]
	if key == 0 || !objc_is_kind(key, ios_runtime.names['NSString']) { panic('iOS: device feedback lookup requires a string key') }
	name := string_text(key)
	if name !in ['_feedbackSupportLevel', 'feedbackSupportLevel']! {
		panic('iOS: UIDevice valueForKey: unsupported key ' + name)
	}
	// Keep this private capability lookup scoped to UIDevice. General KVC,
	// ivar access and other device keys remain unsupported. Dispatch the getter
	// normally so an application subclass/replacement retains its behavior.
	value := unsafe { ObjInit(voidptr(C.ios_objc_msgsend))(object, c'_feedbackSupportLevel') }
	number := objc_allocate(ios_runtime.names['NSNumber'])
	obj_header(number).number = i64(value)
	frame.x[0] = objc_autorelease(number)
	return true
}
