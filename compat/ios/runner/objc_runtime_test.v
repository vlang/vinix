// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn runtime_test_imp(object u64, selector &char) u64 { _ = selector; return object }

fn test_dynamic_classes_release_owned_metadata_and_balance_instances() {
	objc_start()
	defer { objc_stop() }
	root := ios_runtime.names['NSObject']
	classes := ios_runtime.classes.len
	imp := u64(unsafe { voidptr(runtime_test_imp) })
	selector := objc_selector(c'runtimeOwnedMethod')
	for _ in 0 .. 200 {
		cls := objc_allocate_class(root, c'OwnedDynamicClass', 16)
		assert cls != 0 && objc_get_class(c'OwnedDynamicClass') == 0
		assert objc_add_ivar(cls, c'ownedIvar', 8, 3, c'@')
		assert objc_add_method(cls, selector, imp, c'@16@0:8')
		method := objc_instance_method(cls, selector)
		assert method != 0 && objc_method_imp(method) == imp
		assert objc_replace_method(cls, selector, imp, c'v@:') == imp
		assert ctext(u64(objc_method_types(method))) == '@16@0:8'
		objc_register_class(cls)
		info := ios_runtime.classes[cls] or { panic('missing test class') }
		object := objc_allocate(cls)
		assert info.instances == 1
		assert objc_set_class(object, root) == cls
		assert info.instances == 0
		assert objc_set_class(object, cls) == root
		objc_release(object)
		assert ios_runtime.live == 0 && info.instances == 0
		objc_dispose_class(cls)
		assert objc_get_class(c'OwnedDynamicClass') == 0
		assert ios_runtime.classes.len == classes
	}
}

fn test_accessibility_sidecar_strong_strings_and_zeroing_weak_container() {
	objc_start()
	defer { objc_stop() }
	baseline := ios_runtime.weak.len
	for _ in 0 .. 200 {
		container := objc_allocate(ios_runtime.names['NSObject'])
		element := objc_allocate(ios_runtime.names['UIAccessibilityElement'])
		label := owned_string('a retained accessibility label')
		mut state := accessibility_state(element)
		assert state.element && state.traits == 0
		objc_store_weak(unsafe { &state.container }, container)
		objc_store_strong(unsafe { &state.strings[0] }, label)
		objc_release(label)
		assert ios_runtime.live == 3 && state.strings[0] == label
		objc_release(container)
		assert state.container == 0 && ios_runtime.live == 2
		objc_release(element)
		assert ios_runtime.live == 0 && ios_runtime.weak.len == baseline
	}
}
