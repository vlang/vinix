// SPDX-License-Identifier: GPL-2.0-or-later
module main

type TextInputSend = fn (u64, u64, u64, u64) u64
type TextInputBool = fn (u64, u64) bool

struct TextInputSuper {
	object u64
	cls u64
}

fn text_input_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { TextInputSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn text_input_slot(object u64, name &char) &u64 {
	ivar := objc_find_ivar(read64(object), name)
	assert ivar != 0
	return unsafe { &u64(object + u64(objc_ivar_offset(ivar))) }
}

fn text_input_init(object u64, selector &char) u64 {
	mut context := TextInputSuper{object, read64(object)}
	return unsafe { TextInputSend(voidptr(C.ios_objc_super))(u64(&context), u64(selector), 0, 0) }
}

fn text_input_start(object u64, selector &char) u64 {
	return unsafe { *text_input_slot(object, c'_start') }
}

fn text_input_end(object u64, selector &char) u64 {
	return unsafe { *text_input_slot(object, c'_end') }
}

fn text_input_empty(object u64, selector &char) bool {
	start := text_input_start(object, selector)
	end := text_input_end(object, selector)
	return unsafe { *text_input_slot(start, c'_offset') == *text_input_slot(end, c'_offset') }
}

fn text_input_dealloc(object u64, selector &char) {
	objc_store_strong(text_input_slot(object, c'_start'), 0)
	objc_store_strong(text_input_slot(object, c'_end'), 0)
	mut context := TextInputSuper{object, read64(object)}
	unsafe { TextInputSend(voidptr(C.ios_objc_super))(u64(&context), u64(selector), 0, 0) }
}

fn test_text_input_subclasses() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		for name in ['UITextPosition', 'UITextRange']! {
			cls := ios_runtime.names[name]
			assert objc_class_parent(cls) == ios_runtime.names['NSObject']
			assert objc_class_parent(read64(cls)) == read64(ios_runtime.names['NSObject'])
			assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
			// Shim storage contains isa; this does not assert Apple's private layout.
			assert objc_class_size(cls) == 8
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/GameKit.framework/GameKit', '/usr/lib/libobjc.A.dylib']! {
					if _ := runtime_symbol(wrong, symbol) { assert false, wrong + ': ' + symbol }
				}
			}
			object := text_input_msg(cls, c'new', 0, 0)
			assert text_input_msg(object, c'init', 0, 0) == object
			assert text_input_msg(object, c'class', 0, 0) == cls
			for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'classForCoder', c'supportsSecureCoding', c'setStart:', c'setEnd:', c'offset']! {
				assert !objc_responds(object, selector)
				assert objc_instance_method(cls, u64(selector)) == 0
			}
			for selector in [c'isEmpty', c'start', c'end']! {
				assert objc_responds(object, selector) == (name == 'UITextRange')
				assert !objc_responds(cls, selector)
				if name == 'UITextRange' {
					method := objc_instance_method(cls, u64(selector))
					assert ctext(u64(objc_method_types(method))) == if ctext(u64(selector)) == 'isEmpty' { 'B16@0:8' } else { '@16@0:8' }
				}
			}
			objc_release(object)
		}
		position := objc_allocate_class(ios_runtime.names['UITextPosition'], c'VinixTextPosition', 0)
		assert objc_add_ivar(position, c'_offset', 8, 3, c'q')
		objc_register_class(position)
		range := objc_allocate_class(ios_runtime.names['UITextRange'], c'VinixTextRange', 0)
		assert objc_add_ivar(range, c'_start', 8, 3, c'@')
		assert objc_add_ivar(range, c'_end', 8, 3, c'@')
		assert objc_add_method(range, u64(c'init'), u64(unsafe { voidptr(text_input_init) }), c'@16@0:8')
		assert objc_add_method(range, u64(c'start'), u64(unsafe { voidptr(text_input_start) }), c'@16@0:8')
		assert objc_add_method(range, u64(c'end'), u64(unsafe { voidptr(text_input_end) }), c'@16@0:8')
		assert objc_add_method(range, u64(c'isEmpty'), u64(unsafe { voidptr(text_input_empty) }), c'B16@0:8')
		assert objc_add_method(range, u64(c'dealloc'), u64(unsafe { voidptr(text_input_dealloc) }), c'v16@0:8')
		objc_register_class(range)
		assert objc_class_size(position) == 16 && objc_class_size(range) == 24
		assert objc_ivar_offset(objc_find_ivar(range, c'_start')) == 8
		assert objc_ivar_offset(objc_find_ivar(range, c'_end')) == 16
		start := text_input_msg(position, c'new', 0, 0)
		end := text_input_msg(position, c'new', 0, 0)
		start_offset := text_input_slot(start, c'_offset')
		end_offset := text_input_slot(end, c'_offset')
		unsafe { *start_offset = 12; *end_offset = 15 }
		object := text_input_msg(range, c'new', 0, 0)
		objc_store_strong(text_input_slot(object, c'_start'), start)
		objc_store_strong(text_input_slot(object, c'_end'), end)
		objc_release(start); objc_release(end)
		assert objc_is_kind(object, ios_runtime.names['UITextRange'])
		assert text_input_msg(object, c'start', 0, 0) == start
		assert text_input_msg(object, c'end', 0, 0) == end
		assert !unsafe { TextInputBool(voidptr(C.ios_objc_msgsend))(object, u64(c'isEmpty')) }
		unsafe { *end_offset = 12 }
		assert unsafe { TextInputBool(voidptr(C.ios_objc_msgsend))(object, u64(c'isEmpty')) }
		for selector in [c'start', c'end', c'isEmpty']! { assert objc_responds(object, selector) }
		method := objc_instance_method(range, u64(c'start'))
		assert objc_method_imp(method) == u64(unsafe { voidptr(text_input_start) })
		assert unsafe { TextInputSend(voidptr(objc_method_imp(method)))(object, u64(c'start'), 0, 0) } == start
		mut weak_start := u64(0)
		objc_store_weak(&weak_start, start)
		objc_release(object)
		assert weak_start == 0
		objc_destroy_weak(&weak_start)
		position_info := ios_runtime.classes[position] or { panic('missing text position class') }
		range_info := ios_runtime.classes[range] or { panic('missing text range class') }
		assert position_info.instances == 0 && range_info.instances == 0
		objc_dispose_class(range); objc_dispose_class(position)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-TEXTINPUT: scoped imports, abstract getter metadata, native subclass ivars and BOOL/object dispatch, endpoint ownership and two drained runtimes')
}

fn test_text_input_abstract_failures() {
	objc_start()
	base := ios_runtime.names['UITextRange']
	sub := objc_allocate_class(base, c'IncompleteTextRange', 0)
	objc_register_class(sub)
	for selector in [c'start', c'end', c'isEmpty']! {
		for mode in ['base', 'subclass', 'saved', 'super']! {
			text_input_reject(base, sub, selector, mode, 'abstract UITextRange getter requires a subclass implementation')
		}
	}
	for name in ['UITextPosition', 'UITextRange']! {
		for selector in [c'copy', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding']! {
			text_input_reject(ios_runtime.names[name], 0, selector, 'base', 'text input copy, coding and specialized initialization require a subclass implementation')
		}
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-TEXTINPUT-REJECT: 20 abstract base/subclass getters, saved IMP, super dispatch and unsupported copy/coding cases fail explicitly')
}

fn text_input_reject(base u64, sub u64, selector &char, mode string, reason string) {
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
		object := objc_allocate(if mode in ['subclass', 'super']! { sub } else { base })
		if mode == 'saved' {
			method := objc_instance_method(base, u64(selector))
			unsafe { TextInputSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) }
		} else if mode == 'super' {
			mut context := TextInputSuper{object, sub}
			unsafe { TextInputSend(voidptr(C.ios_objc_super))(u64(&context), u64(selector), 0, 0) }
		} else { text_input_msg(object, selector, 0, 0) }
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
	assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode + ': ' + ctext(u64(selector))
	output := unsafe { tos(&bytes[0], length) }
	assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), output
}
