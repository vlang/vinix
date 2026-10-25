// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Construction and configuration only. UIKit's editing, input, drawing and
// delegate callback machinery are not implemented by this profile.
struct TextFieldState {
mut:
	initialized bool
	text u64
	placeholder u64
	delegate u64 // Registered zeroing weak slot; never owns its target.
	integers [8]i64
	flags [3]bool
}

fn text_field_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UITextField' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic UITextField superclass chain')
}

fn text_field_unsupported(selector string) bool {
	return (selector.starts_with('initWith') && selector != 'initWithFrame:')
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'encodeWithCoder:', 'classForCoder', 'supportsSecureCoding',
		'becomeFirstResponder', 'resignFirstResponder', 'canBecomeFirstResponder',
		'canResignFirstResponder', 'isFirstResponder', 'endEditing:', 'hasText',
		'insertText:', 'deleteBackward', 'inputView', 'setInputView:',
		'inputAccessoryView', 'setInputAccessoryView:', 'reloadInputViews',
		'inputDelegate', 'setInputDelegate:', 'selectedTextRange', 'setSelectedTextRange:',
		'markedTextRange', 'setMarkedText:selectedRange:', 'unmarkText',
		'attributedText', 'setAttributedText:', 'attributedPlaceholder', 'setAttributedPlaceholder:',
		'defaultTextAttributes', 'setDefaultTextAttributes:', 'typingAttributes', 'setTypingAttributes:',
		'drawTextInRect:', 'drawPlaceholderInRect:']!
}

fn text_field_types(name string, meta bool, selector string) ?string {
	if meta || name != 'UITextField' { return none }
	return match selector {
		'initWithFrame:' { '@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16' }
		'text', 'placeholder', 'delegate' { '@16@0:8' }
		'setText:', 'setPlaceholder:', 'setDelegate:' { 'v24@0:8@16' }
		'isSecureTextEntry', 'clearsOnBeginEditing', 'enablesReturnKeyAutomatically', 'isEditing' { 'B16@0:8' }
		'setSecureTextEntry:', 'setClearsOnBeginEditing:', 'setEnablesReturnKeyAutomatically:' { 'v20@0:8B16' }
		'textAlignment', 'borderStyle', 'keyboardType', 'keyboardAppearance', 'returnKeyType',
		'autocapitalizationType', 'autocorrectionType', 'spellCheckingType' { 'q16@0:8' }
		'setTextAlignment:', 'setBorderStyle:', 'setKeyboardType:', 'setKeyboardAppearance:',
		'setReturnKeyType:', 'setAutocapitalizationType:', 'setAutocorrectionType:', 'setSpellCheckingType:' { 'v24@0:8q16' }
		else { none }
	}
}

// Caller holds the recursive runtime lock. A forged isa cannot grant state.
fn text_field_storage(object u64, initialized bool) &TextFieldState {
	header := obj_header(object)
	if !header.text_field_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 1064
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.text_field == unsafe { nil } {
		panic('iOS: UITextField requires live owned text field storage')
	}
	if initialized && !header.text_field.initialized { panic('iOS: UITextField requires initialization') }
	return header.text_field
}

fn text_field_initialize(object u64, rect ObjRect) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := text_field_storage(object, false)
	if state.initialized { panic('iOS: UITextField reinitialization is not implemented') }
	for value in [rect.x, rect.y, rect.width, rect.height]! {
		if value != value || value < -8192 || value > 8192 { panic('iOS: UITextField frame is out of range') }
	}
	if rect.width < 0 || rect.height < 0 { panic('iOS: UITextField frame is out of range') }
	state.text = owned_string('')
	state.integers[0] = 4 // NSTextAlignmentNatural (native Catalyst default).
	state.integers[5] = 2 // UITextAutocapitalizationTypeSentences.
	obj_header(object).frame = rect
	state.initialized = true
	return object
}

fn text_field_copy_string(object u64) u64 {
	if object == 0 { return 0 }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: UITextField requires an initialized builtin string')
		}
	}
	text := cf_string_compare_text(object) or { panic('iOS: UITextField requires a live UTF-8 string') }
	if text.len > 65536 { panic('iOS: UITextField string exceeds profile limit') }
	return owned_string(text)
}

fn text_field_dispose(mut header ObjHeader) {
	if header.text_field == unsafe { nil } { return }
	mut state := header.text_field
	header.text_field = unsafe { nil }
	objc_destroy_weak(&state.delegate)
	objc_release(state.text)
	objc_release(state.placeholder)
	unsafe { C.free(state) }
}

fn text_field_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	cls := if object in ios_runtime.classes { object } else { read64(object) }
	if !text_field_family(cls) { return false }
	if text_field_unsupported(selector) { panic('iOS: unsupported UITextField method: ' + selector) }
	if object in ios_runtime.classes { return false }
	if selector in ['init', 'initWithFrame:']! {
		frame.x[0] = text_field_initialize(object, if selector == 'init' { ObjRect{} } else { frame_rect(frame) })
		return true
	}
	if text_field_types('UITextField', false, selector) == none { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := text_field_storage(object, true)
	match selector {
		'text' { frame.x[0] = state.text }
		'placeholder' { frame.x[0] = state.placeholder }
		'setText:', 'setPlaceholder:' {
			value := if frame.x[2] == 0 && selector == 'setText:' { owned_string('') } else { text_field_copy_string(frame.x[2]) }
			old := if selector == 'setText:' { state.text } else { state.placeholder }
			if selector == 'setText:' { state.text = value } else { state.placeholder = value }
			objc_release(old)
			frame.x[0] = 0
		}
		'delegate' { frame.x[0] = objc_autorelease(objc_load_weak(&state.delegate)) }
		'setDelegate:' { objc_store_weak(&state.delegate, frame.x[2]); frame.x[0] = 0 }
		'isEditing' { frame.x[0] = 0 }
		else {
			for i, getter in ['textAlignment', 'borderStyle', 'keyboardType', 'keyboardAppearance',
				'returnKeyType', 'autocapitalizationType', 'autocorrectionType', 'spellCheckingType']! {
				if selector == getter { frame.x[0] = u64(state.integers[i]); return true }
			}
			for i, setter in ['setTextAlignment:', 'setBorderStyle:', 'setKeyboardType:', 'setKeyboardAppearance:',
				'setReturnKeyType:', 'setAutocapitalizationType:', 'setAutocorrectionType:', 'setSpellCheckingType:']! {
				if selector == setter { state.integers[i] = i64(frame.x[2]); frame.x[0] = 0; return true }
			}
			for i, getter in ['isSecureTextEntry', 'clearsOnBeginEditing', 'enablesReturnKeyAutomatically']! {
				if selector == getter { frame.x[0] = if state.flags[i] { u64(1) } else { u64(0) }; return true }
			}
			for i, setter in ['setSecureTextEntry:', 'setClearsOnBeginEditing:', 'setEnablesReturnKeyAutomatically:']! {
				if selector == setter { state.flags[i] = u8(frame.x[2]) != 0; frame.x[0] = 0; return true }
			}
		}
	}
	return true
}
