// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

type TextFieldSend = fn (u64, u64, u64) u64
type TextFieldFrame = fn (u64, u64, ObjRect) u64
type TextFieldBool = fn (u64, u64) bool

struct TextFieldSuper {
	object u64
	cls u64
}

fn field_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { TextFieldSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument) }
}

fn field_init(object u64, selector &char) u64 {
	mut context := TextFieldSuper{object, read64(object)}
	return unsafe { TextFieldSend(voidptr(C.ios_objc_super))(u64(&context), u64(selector), 0) }
}

fn field_text(object u64, selector &char) u64 {
	return objc_autorelease(owned_string('subclass'))
}

fn test_text_field_configuration() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['UITextField']
		assert objc_class_parent(cls) == ios_runtime.names['UIControl']
		assert objc_class_parent(read64(cls)) == read64(ios_runtime.names['UIControl'])
		assert objc_class_size(cls) == 1064
		assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'UITextField'
			assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/GameKit.framework/GameKit', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong }
			}
		}
		baseline := ios_runtime.live
		object := unsafe { TextFieldFrame(voidptr(C.ios_objc_msgsend))(objc_allocate(cls), u64(c'initWithFrame:'), ObjRect{1, -2, 320, 44}) }
		assert obj_header(object).frame == ObjRect{1, -2, 320, 44}
		assert string_text(field_msg(object, c'text', 0)) == ''
		assert field_msg(object, c'placeholder', 0) == 0 && field_msg(object, c'delegate', 0) == 0
		for i, getter in ['textAlignment', 'borderStyle', 'keyboardType', 'keyboardAppearance', 'returnKeyType', 'autocapitalizationType', 'autocorrectionType', 'spellCheckingType']! {
			setter := ['setTextAlignment:', 'setBorderStyle:', 'setKeyboardType:', 'setKeyboardAppearance:', 'setReturnKeyType:', 'setAutocapitalizationType:', 'setAutocorrectionType:', 'setSpellCheckingType:']![i]
			assert field_msg(object, getter.str, 0) == [u64(4), 0, 0, 0, 0, 2, 0, 0]![i]
			assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(getter.str))))) == 'q16@0:8'
			assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(setter.str))))) == 'v24@0:8q16'
			field_msg(object, setter.str, u64(i64(-7 - i)))
			assert i64(field_msg(object, getter.str, 0)) == -7 - i
		}
		for i, getter in ['isSecureTextEntry', 'clearsOnBeginEditing', 'enablesReturnKeyAutomatically', 'isEditing']! {
			assert !unsafe { TextFieldBool(voidptr(C.ios_objc_msgsend))(object, u64(getter.str)) }
			assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(getter.str))))) == 'B16@0:8'
			if i == 3 { continue }
			setter := ['setSecureTextEntry:', 'setClearsOnBeginEditing:', 'setEnablesReturnKeyAutomatically:']![i]
			assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(setter.str))))) == 'v20@0:8B16'
			field_msg(object, setter.str, 1)
			assert unsafe { TextFieldBool(voidptr(C.ios_objc_msgsend))(object, u64(getter.str)) }
			field_msg(object, setter.str, 0)
			assert !unsafe { TextFieldBool(voidptr(C.ios_objc_msgsend))(object, u64(getter.str)) }
		}
		for i, getter in ['text', 'placeholder', 'delegate']! {
			setter := ['setText:', 'setPlaceholder:', 'setDelegate:']![i]
			assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(getter.str))))) == '@16@0:8'
			assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(setter.str))))) == 'v24@0:8@16'
		}
		assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(c'initWithFrame:'))))) == '@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16'
		for property in ['Text', 'Placeholder']! {
			value := field_msg(objc_allocate(ios_runtime.names['NSMutableString']), c'initWithUTF8String:', u64(c'hello 🌍'))
			setter := 'set' + property + ':'
			getter := property.to_lower()
			field_msg(object, setter.str, value)
			stored := field_msg(object, getter.str, 0)
			assert stored != value && obj_header(value).refs == 1
			suffix := owned_string('-changed')
			field_msg(value, c'appendString:', suffix)
			objc_release(suffix); objc_release(value)
			assert string_text(stored) == 'hello 🌍'
			field_msg(object, setter.str, stored) // Copy before releasing the previous value.
			assert string_text(field_msg(object, getter.str, 0)) == 'hello 🌍'
			field_msg(object, setter.str, 0)
			if property == 'Text' { assert string_text(field_msg(object, getter.str, 0)) == '' }
			else { assert field_msg(object, getter.str, 0) == 0 }
		}
		delegate := objc_new(ios_runtime.names['NSObject'])
		field_msg(object, c'setDelegate:', delegate)
		assert obj_header(delegate).refs == 1
		inner := objc_pool_push()
		assert field_msg(object, c'delegate', 0) == delegate
		objc_pool_pop(inner)
		assert obj_header(delegate).refs == 1
		objc_release(delegate)
		assert field_msg(object, c'delegate', 0) == 0
		other := objc_new(ios_runtime.names['NSObject'])
		field_msg(object, c'setDelegate:', other)
		objc_release(object)
		objc_release(other) // Destroyed fields must unregister their weak slots.
		assert ios_runtime.live == baseline
		plain := objc_new(cls)
		assert obj_header(plain).frame == ObjRect{}
		objc_release(plain)
		sub := objc_allocate_class(cls, c'VinixTextField', 0)
		assert objc_add_ivar(sub, c'_tag', 8, 3, c'q')
		assert objc_add_method(sub, u64(c'init'), u64(unsafe { voidptr(field_init) }), c'@16@0:8')
		assert objc_add_method(sub, u64(c'text'), u64(unsafe { voidptr(field_text) }), c'@16@0:8')
		objc_register_class(sub)
		assert objc_ivar_offset(objc_find_ivar(sub, c'_tag')) == 1064
		assert objc_class_size(sub) == 1072
		instance := objc_new(sub)
		assert string_text(field_msg(instance, c'text', 0)) == 'subclass'
		saved := objc_method_imp(objc_instance_method(cls, u64(c'text')))
		assert string_text(unsafe { TextFieldSend(voidptr(saved))(instance, u64(c'text'), 0) }) == ''
		owned := owned_string('base')
		field_msg(instance, c'setText:', owned)
		objc_release(owned)
		assert string_text(unsafe { TextFieldSend(voidptr(saved))(instance, u64(c'text'), 0) }) == 'base'
		for selector in ['insertText:', 'becomeFirstResponder', 'initWithCoder:', 'copy', 'classForCoder', 'setAttributedText:']! {
			assert !objc_responds(instance, selector.str)
			assert objc_instance_method(sub, u64(selector.str)) == 0
		}
		objc_release(instance)
		objc_dispose_class(sub)
		objc_pool_pop(pool)
		assert ios_runtime.live == baseline
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-UITEXTFIELD: scoped imports, native metadata/defaults, CGRect and BOOL dispatch, copied UTF-8 strings, weak delegates, subclass/saved IMP and two drained runtimes')
}

fn test_text_field_rejections() {
	objc_start()
	cls := ios_runtime.names['UITextField']
	for mode in ['uninitialized', 'reinit', 'caller', 'isa-in', 'isa-out', 'forged-isa', 'copy', 'copy-zone', 'bad-string', 'raw-string', 'mutable-uninit', 'oversize', 'negative-frame', 'nan-frame', 'insertText:', 'becomeFirstResponder', 'initWithCoder:', 'encodeWithCoder:', 'setAttributedText:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := if mode in ['uninitialized', 'negative-frame', 'nan-frame']! { objc_allocate(cls) } else { objc_new(cls) }
			match mode {
				'uninitialized' { field_msg(object, c'text', 0) }
				'reinit' { field_msg(object, c'init', 0) }
				'caller' { mut storage := [140]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'forged-isa' { fake := objc_allocate(ios_runtime.names['NSObject']); unsafe { *(&u64(fake)) = cls }; field_msg(fake, c'text', 0) }
				'copy', 'copy-zone' { objc_copy_value(object, mode == 'copy-zone') }
				'bad-string' { field_msg(object, c'setText:', objc_new(ios_runtime.names['NSObject'])) }
				'raw-string' { field_msg(object, c'setText:', u64(c'not an NSString')) }
				'mutable-uninit' { field_msg(object, c'setPlaceholder:', objc_allocate(ios_runtime.names['NSMutableString'])) }
				'oversize' { field_msg(object, c'setText:', owned_string('x'.repeat(65537))) }
				'negative-frame', 'nan-frame' {
					rect := if mode == 'negative-frame' { ObjRect{0, 0, -1, 0} } else { ObjRect{bits.f64_from_bits(0x7ff8000000000001), 0, 1, 1} }
					unsafe { TextFieldFrame(voidptr(C.ios_objc_msgsend))(object, u64(c'initWithFrame:'), rect) }
				}
				else { field_msg(object, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains('iOS: ') && output.contains('UITextField') && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-UITEXTFIELD-REJECT: 19 storage, initialization, string, frame, copy/coding and editing cases fail explicitly')
}
