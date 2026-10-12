// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn lookup_fixture(name string, flags u8, value u8) macho.Image {
	// A single absolute export. Absolute zero tests presence independently of
	// address, without mapping memory or calling the synthetic symbol.
	mut bytes := [u8(0), 1]
	bytes << name.bytes()
	bytes << [u8(0), u8(name.len + 4), 2, flags, value, 0]
	return macho.Image{data: bytes, export_info: macho.FileRange{size: u64(bytes.len)}}
}

fn lookup_add(image macho.Image) int {
	index := module_runtime.modules.len
	module_runtime.modules << &LoadedModule{image: image, path: ''.clone()}
	module_runtime.lookup_order << ModuleProvider{index: index}
	return index
}

fn test_global_lookup_coalesces_weak_definitions_and_keeps_scopes() {
	for _ in 0 .. 2 {
		main_image := lookup_fixture('_shared', 6, 11)
		modules_start(main_image, macho.Layout{}, 0, '/main', true)
		second := lookup_add(lookup_fixture('_shared', 6, 22))
		assert module_symbol(second, '<weak lookup>', '_shared')! == 11
		assert module_symbol(second, '<flat lookup>', '_shared')! == 11
		assert module_symbol(second, '<self>', '_shared')! == 22
		assert module_symbol(second, '<main executable>', '_shared')! == 11
		strong := lookup_add(lookup_fixture('_shared', 2, 33))
		lookup_add(lookup_fixture('_shared', 2, 44))
		// Initializer order differs from provider order and must not decide binds.
		module_runtime.order = [strong, second, 0]
		for owner in 0 .. module_runtime.modules.len {
			assert module_symbol(owner, '<weak lookup>', '_shared')! == 33
			assert module_symbol(owner, '<flat lookup>', '_shared')! == 11
		}
		module_runtime.modules[second].dependencies['/bundle/weak'] = 0
		assert module_symbol(second, '/bundle/weak', '_shared')! == 11
		if _ := module_symbol(second, '<weak lookup>', '_missing') { assert false }
		if _ := module_symbol(second, '<main executable>', '_missing') { assert false }
		modules_stop()
		module_image_free(main_image)
		assert module_runtime == unsafe { nil }
	}
	println('IOS-MODULE-LOOKUP: weak coalescence, strong precedence, scope and teardown passed')
}

fn test_zero_exports_and_malformed_definitions_are_not_missing() {
	main_image := lookup_fixture('_zero', 6, 9)
	modules_start(main_image, macho.Layout{}, 0, '/main', true)
	defer { modules_stop(); module_image_free(main_image) }
	lookup_add(lookup_fixture('_zero', 2, 0))
	assert module_symbol(0, '<weak lookup>', '_zero')! == 0
	assert module_symbol(1, '<self>', '_zero')! == 0
	lookup_add(lookup_fixture('_bad', 8, 1)) // re-export requires explicit support
	if _ := module_symbol(0, '<weak lookup>', '_bad') { assert false } else {
		assert err.msg().contains('re-export/resolver')
	}
}

fn test_loaded_builtin_providers_and_cpp_export_strengths() {
	main_image := lookup_fixture('_shared', 6, 11)
	modules_start(main_image, macho.Layout{}, 0, '/main', true)
	defer { modules_stop(); module_image_free(main_image) }
	module_lookup_builtin_add('/usr/lib/libSystem.B.dylib')
	module_lookup_builtin_add('/usr/lib/libSystem.B.dylib')
	assert module_runtime.lookup_order.len == 2
	assert module_symbol(0, '<flat lookup>', '_malloc')! == runtime_symbol('/usr/lib/libSystem.B.dylib', '_malloc')!
	assert cxx_weak_symbol('__ZTISt12length_error')
	assert cxx_weak_symbol('__Znwm') && cxx_weak_symbol('__ZdlPv')
	assert !cxx_weak_symbol('__ZTISt13runtime_error') && !cxx_weak_symbol('_missing')
	$if ios_cxx ? {
		module_lookup_builtin_add('/usr/lib/libc++.1.dylib')
		for symbol in ['__ZTISt12length_error', '__Znwm', '__ZdlPv']! {
			address := module_symbol(0, '<weak lookup>', symbol)!
			assert address != 0 && address == cxx_symbol(symbol)!
			lookup_add(lookup_fixture(symbol, 6, 55))
			assert module_symbol(0, '<weak lookup>', symbol)! == address
			lookup_add(lookup_fixture(symbol, 2, 66))
			assert module_symbol(0, '<weak lookup>', symbol)! == 66
		}
		println('IOS-MODULE-LOOKUP-CXX: real RTTI, new and delete exports passed')
	}
}

fn test_native_linked_chained_client_uses_process_canonical_definition() {
	root := os.getenv('VINIX_IOS_LOOKUP_NATIVE')
	if root == '' { return }
	for order in [['weak-a', 'weak-b'], ['weak-b', 'weak-a'], ['weak-a', 'strong'], ['strong', 'weak-a']] {
		main_image := macho.parse(os.read_bytes(root + '/' + order[0] + '.dylib')!)!
		modules_start(main_image, main_image.layout(4096)!, 0x900000000, '/main', true)
		for index, name in order[1..] {
			image := macho.parse(os.read_bytes(root + '/' + name + '.dylib')!)!
			module_runtime.modules << &LoadedModule{image: image, layout: image.layout(4096)!,
				base: 0xa00000000 + u64(index) * 0x100000, path: ''.clone()}
			module_runtime.lookup_order << ModuleProvider{index: module_runtime.modules.len - 1}
		}
		client := macho.parse(os.read_bytes(root + '/client.dylib')!)!
		layout := client.layout(4096)!
		owner := module_runtime.modules.len
		module_runtime.modules << &LoadedModule{image: client, layout: layout, base: 0xc00000000, path: ''.clone()}
		module_runtime.lookup_order << ModuleProvider{index: owner}
		module_runtime.binding = owner
		chosen := if 'strong' in order { order.index('strong') } else { 0 }
		target := module_runtime.modules[chosen]
		expected := target.image.exported_address('_vinix_lookup_data', target.layout, target.base)!
		assert expected != 0
		assert module_symbol(owner, '<weak lookup>', '_vinix_lookup_data')! == expected
		original := client.data.clone()
		fixups := client.plan_fixups(layout, 0xc00000000, module_bind_symbol)!
		slot := client.exported_address('_vinix_lookup_slot', layout, 0xc00000000)! - 0xc00000000
		assert fixups.any(it.offset == slot && it.value == expected)
		assert original == client.data
		unsafe { original.free(); fixups.free() }
		modules_stop()
		module_image_free(main_image)
	}
	println('IOS-MODULE-LOOKUP-CHAINED: four native-linked client orders bind to the canonical definition')
}
