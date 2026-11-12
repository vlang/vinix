// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import math
import os

#include <sys/wait.h>
fn C.waitpid(int, &int, int) int
fn C.__atomic_fetch_add(&u64, u64, int) u64
fn C.__atomic_load_n(&u64, int) u64
fn C.__atomic_store_n(&u64, u64, int)
type SMGet = fn (u64, &char) u64
type SMCreate = fn () u64
type SMBuffer = fn (u64, &char, u64, u64) u64
type SMBytes = fn (u64, &char, u64, u64, u64) u64
type SMCopy = fn (u64, &char, u64, u64, u64, u64, u64)
type SMVoid = fn (u64, &char)
type SMDescriptor = fn (u64, &char, u64, u64, u64, u8) u64
type SMTexture = fn (u64, &char, u64) u64
type SMSet = fn (u64, &char, u64)
type SMLibrary = fn (u64, &char, u64, &u64) u64
type SMSamplerFloatGet = fn (u64, &char) f32
type SMSamplerFloatSet = fn (u64, &char, f32)
type SMSamplerBoolGet = fn (u64, &char) u8
type SMSamplerBoolSet = fn (u64, &char, u8)
type SMSamplerName = fn (&char) u64
struct SMSamplerAPI { send voidptr selector SMSamplerName cls u64 }
fn (api SMSamplerAPI) sel(name &char) &char { return unsafe { &char(api.selector(name)) } }
fn (api SMSamplerAPI) get(object u64, name &char) u64 { return unsafe { SMGet(api.send)(object, api.sel(name)) } }
fn (api SMSamplerAPI) set(object u64, name &char, value u64) { unsafe { SMSet(api.send)(object, api.sel(name), value) } }
fn (api SMSamplerAPI) float_get(object u64, name &char) f32 { return unsafe { SMSamplerFloatGet(api.send)(object, api.sel(name)) } }
fn (api SMSamplerAPI) float_set(object u64, name &char, value f32) { unsafe { SMSamplerFloatSet(api.send)(object, api.sel(name), value) } }
fn (api SMSamplerAPI) bool_get(object u64, name &char) u8 { return unsafe { SMSamplerBoolGet(api.send)(object, api.sel(name)) } }
fn (api SMSamplerAPI) bool_set(object u64, name &char, value u8) { unsafe { SMSamplerBoolSet(api.send)(object, api.sel(name), value) } }
fn sm_sampler_profile(api SMSamplerAPI) {
	descriptor := api.get(api.cls, c'new'); assert descriptor != 0
	for i, name in [c'minFilter', c'magFilter', c'mipFilter', c'maxAnisotropy', c'sAddressMode', c'tAddressMode', c'rAddressMode', c'borderColor', c'compareFunction']! { assert api.get(descriptor, name) == if i == 3 { u64(1) } else { u64(0) } }
	assert api.bool_get(descriptor, c'normalizedCoordinates') == 1 && api.bool_get(descriptor, c'lodAverage') == 0 && api.bool_get(descriptor, c'supportArgumentBuffers') == 0
	assert api.float_get(descriptor, c'lodMinClamp') == 0 && api.float_get(descriptor, c'lodMaxClamp') == f32(3.4028234663852886e38) && api.get(descriptor, c'label') == 0
	for i, setter in [c'setMinFilter:', c'setMagFilter:', c'setMipFilter:', c'setMaxAnisotropy:', c'setSAddressMode:', c'setTAddressMode:', c'setRAddressMode:', c'setBorderColor:', c'setCompareFunction:']! { api.set(descriptor, setter, [u64(1), 1, 2, 16, 2, 3, 4, 2, 7]![i]) }
	api.float_set(descriptor, c'setLodMinClamp:', 0.25); api.float_set(descriptor, c'setLodMaxClamp:', 7.75)
	api.bool_set(descriptor, c'setNormalizedCoordinates:', 0); api.bool_set(descriptor, c'setLodAverage:', 1); api.bool_set(descriptor, c'setSupportArgumentBuffers:', 1)
	copy := api.get(descriptor, c'copy'); assert copy != 0 && copy != descriptor
	api.set(descriptor, c'setMinFilter:', 0); api.float_set(descriptor, c'setLodMinClamp:', 2); api.bool_set(descriptor, c'setLodAverage:', 0)
	api.get(descriptor, c'release')
	for i, getter in [c'minFilter', c'magFilter', c'mipFilter', c'maxAnisotropy', c'sAddressMode', c'tAddressMode', c'rAddressMode', c'borderColor', c'compareFunction']! { assert api.get(copy, getter) == [u64(1), 1, 2, 16, 2, 3, 4, 2, 7]![i] }
	assert api.float_get(copy, c'lodMinClamp') == 0.25 && api.float_get(copy, c'lodMaxClamp') == 7.75
	assert api.bool_get(copy, c'normalizedCoordinates') == 0 && api.bool_get(copy, c'lodAverage') == 1 && api.bool_get(copy, c'supportArgumentBuffers') == 1
	api.get(copy, c'release')
}
fn sm_sampler_worker(api SMSamplerAPI, device u64, descriptor u64) {
	for _ in 0 .. 64 {
		state := unsafe { SMTexture(api.send)(device, api.sel(c'newSamplerStateWithDescriptor:'), descriptor) }
		assert state != 0 && api.get(state, c'device') == device
		api.get(state, c'release')
	}
}
fn test_software_metal_samplers() {
	$if !ios_metal_software ? { return }
	$if macos {
		metal := C.dlopen(c'/System/Library/Frameworks/Metal.framework/Metal', 2); objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert metal != unsafe { nil } && objc != unsafe { nil }
		get_class := C.dlsym(objc, c'objc_getClass'); send := C.dlsym(objc, c'objc_msgSend'); selector := C.dlsym(objc, c'sel_registerName')
		assert get_class != unsafe { nil } && send != unsafe { nil } && selector != unsafe { nil }
		cls := unsafe { SMSamplerName(get_class)(c'MTLSamplerDescriptor') }; assert cls != 0
		sm_sampler_profile(SMSamplerAPI{send, unsafe { SMSamplerName(selector) }, cls})
		assert C.dlclose(objc) == 0 && C.dlclose(metal) == 0
	}
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		cls := runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_OBJC_CLASS_$_MTLSamplerDescriptor') or { panic(err) }
		assert cls == ios_runtime.names['MTLSamplerDescriptor'] && (runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_OBJC_METACLASS_$_MTLSamplerDescriptor') or { panic(err) }) == read64(cls)
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit']! { for symbol in ['_OBJC_CLASS_$_MTLSamplerDescriptor', '_OBJC_METACLASS_$_MTLSamplerDescriptor']! { if _ := runtime_symbol(library, symbol) { assert false } } }
		api := SMSamplerAPI{unsafe { voidptr(C.ios_objc_msgsend) }, objc_selector, cls}
		sm_sampler_profile(api)
		// Creation is a +1 snapshot. Labels copy mutable strings before sharing.
		descriptor := api.get(api.get(cls, c'alloc'), c'init')
		label := api.get(ios_runtime.names['NSMutableString'], c'new'); text := owned_string('sampler π'); api.set(label, c'setString:', text); objc_release(text)
		api.set(descriptor, c'setLabel:', label)
		assert api.get(descriptor, c'label') != label
		changed := owned_string('changed'); api.set(label, c'setString:', changed); objc_release(changed)
		assert string_text(api.get(descriptor, c'label')) == 'sampler π'; objc_release(label)
		state := unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), descriptor) }; assert state != 0
		api.set(descriptor, c'setLabel:', 0); api.set(descriptor, c'setMinFilter:', 1)
		assert string_text(api.get(state, c'label')) == 'sampler π' && sm_sampler_data(obj_header(state)).min_filter == 0
		zone_copy := unsafe { SMTexture(api.send)(descriptor, api.sel(c'copyWithZone:'), 0) }; assert zone_copy != descriptor && api.get(zone_copy, c'minFilter') == 1; objc_release(zone_copy)
		for axis in [c'setSAddressMode:', c'setTAddressMode:', c'setRAddressMode:']! { for value in u64(0) .. 6 { api.set(descriptor, axis, value); result := unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), descriptor) }; assert result != 0; objc_release(result) }; api.set(descriptor, axis, 0) }
		for compare in u64(0) .. 8 { api.set(descriptor, c'setCompareFunction:', compare); result := unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), descriptor) }; assert result != 0; objc_release(result) }
		for value in u64(1) .. 17 { api.set(descriptor, c'setMaxAnisotropy:', value); result := unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), descriptor) }; assert result != 0; objc_release(result) }; api.set(descriptor, c'setMaxAnisotropy:', 1)
		api.bool_set(descriptor, c'setNormalizedCoordinates:', 0); result := unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), descriptor) }; assert result != 0; objc_release(result)
		// Each rejection gets a fresh default descriptor, isolating the bad field.
		for mode in 0 .. 22 {
			bad := api.get(cls, c'new')
			match mode {
				0 { api.set(bad, c'setMinFilter:', 2) } 1 { api.set(bad, c'setMagFilter:', ~u64(0)) } 2 { api.set(bad, c'setMipFilter:', 3) }
				3 { api.set(bad, c'setMaxAnisotropy:', 0) } 4 { api.set(bad, c'setMaxAnisotropy:', 17) }
				5 { api.set(bad, c'setSAddressMode:', 6) } 6 { api.set(bad, c'setTAddressMode:', 6) } 7 { api.set(bad, c'setRAddressMode:', 6) }
				8 { api.set(bad, c'setBorderColor:', 3) } 9 { api.set(bad, c'setCompareFunction:', 8) }
				10 { api.bool_set(bad, c'setSupportArgumentBuffers:', 1) }
				11 { api.float_set(bad, c'setLodMinClamp:', -0.25) } 12 { api.float_set(bad, c'setLodMinClamp:', 2); api.float_set(bad, c'setLodMaxClamp:', 1) }
				13 { api.float_set(bad, c'setLodMinClamp:', math.f32_from_bits(0x7fc00000)) } 14 { api.float_set(bad, c'setLodMaxClamp:', math.f32_from_bits(0x7fc00000)) }
				15 { api.float_set(bad, c'setLodMinClamp:', math.f32_from_bits(0x7f800000)) } 16 { api.float_set(bad, c'setLodMaxClamp:', math.f32_from_bits(0x7f800000)) }
				else { api.bool_set(bad, c'setNormalizedCoordinates:', 0); match mode { 17 { api.set(bad, c'setSAddressMode:', 2) } 18 { api.set(bad, c'setTAddressMode:', 2) } 19 { api.set(bad, c'setRAddressMode:', 2) } 20 { api.set(bad, c'setMipFilter:', 1) } else { api.set(bad, c'setMaxAnisotropy:', 2) } } }
			}
			assert unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), bad) } == 0; objc_release(bad)
		}
		raw := api.get(cls, c'alloc')
		for bad in [u64(0), d, raw]! { assert unsafe { SMTexture(api.send)(d, api.sel(c'newSamplerStateWithDescriptor:'), bad) } == 0 }; objc_release(raw)
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn sm_sampler_worker(api, d, descriptor) }; for worker in workers { worker.wait() }; unsafe { workers.free() }
		objc_release(descriptor); objc_release(d)
		assert api.get(state, c'device') == d && string_text(api.get(state, c'label')) == 'sampler π'
		objc_release(state); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-SAMPLERS: native descriptor reference, integer/bool/float ABI, copies and immutable snapshots, copied Unicode labels, address/compare/anisotropy ranges, 25 rejected inputs, eight workers, retained device and two drained runtimes PASS')
}
fn sm_test_default_library(d u64, bundle u64, output &u64) u64 { return unsafe { SMLibrary(voidptr(C.ios_objc_msgsend))(d, c'newDefaultLibraryWithBundle:error:', bundle, output) } }
fn test_software_metal_default_libraries() {
	$if !ios_metal_software ? { return }
	for iteration in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device(); bundle := ns_main_bundle()
		assert dispatch_runtime == unsafe { nil }
		mut failure := u64(0)
		assert sm_send(d, c'newDefaultLibrary') == 0 && sm_test_default_library(d, bundle, &failure) == 0; sm_library_check_error(failure, 1)
		root := os.join_path(os.temp_dir(), 'metal-default-π-' + C.getpid().str() + '-' + iteration.str()); os.mkdir(root)!
		ios_runtime.bundle = root
		assert sm_send(d, c'newDefaultLibrary') == 0
		assert sm_test_default_library(d, bundle, &failure) == 0; sm_library_check_error(failure, 6)
		path := os.join_path(root, 'default.metallib')
		bytes := sm_library_fixture(['v_main', 'f_main', 'k_π'], true, true); os.write_file_array(path, bytes)!; unsafe { bytes.free() }
		for explicit in [false, true]! {
			failure = 0xfeed
			library := if explicit { sm_test_default_library(d, bundle, &failure) } else { sm_send(d, c'newDefaultLibrary') }
			assert library != 0 && failure == 0xfeed && sm_send(library, c'device') == d
			names := sm_send(library, c'functionNames'); assert sm_send(names, c'count') == 3
			function := unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', obj_header(names).items[2]) }
			objc_release(library); assert string_text(sm_send(function, c'name')) == 'k_π' && sm_send(function, c'functionType') == 3; objc_release(function)
		}
		foreign := objc_allocate(ios_runtime.names['NSBundle'])
		for invalid in [u64(0), d, foreign]! { assert sm_test_default_library(d, invalid, &failure) == 0; sm_library_check_error(failure, 1) }
		objc_release(foreign)
		os.write_file(path, 'bad')!
		assert sm_send(d, c'newDefaultLibrary') == 0 && sm_test_default_library(d, bundle, &failure) == 0; sm_library_check_error(failure, 3)
		ios_runtime.bundle = 'x'.repeat(1024)
		assert sm_test_default_library(d, bundle, &failure) == 0; sm_library_check_error(failure, 1)
		unsafe { ios_runtime.bundle.free() }; ios_runtime.bundle = root
		objc_release(d); objc_pool_pop(pool)
		assert ios_runtime.live == 1 && ios_runtime.objects.len == 1 // Runtime-owned main bundle only.
		objc_stop(); unsafe { path.free(); root.free() }
	}
	println('IOS-SOFTWARE-METAL-DEFAULT-LIBRARY: main-bundle lookup, implicit/explicit selectors, Unicode resource path, owned function lifetimes, unset/missing/corrupt/oversized paths, foreign/nil bundles, optional error slot and two drained runtimes without dispatch PASS')
}
fn C.mkfifo(&char, u32) int
fn sm_test_library_file(d u64, name u64, output &u64) u64 { return unsafe { SMLibrary(voidptr(C.ios_objc_msgsend))(d, c'newLibraryWithFile:error:', name, output) } }
fn test_software_metal_library_files() {
	$if !ios_metal_software ? { return }
	for iteration in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		assert dispatch_runtime == unsafe { nil }
		directory := os.join_path(os.temp_dir(), 'metal-library-files-' + C.getpid().str() + '-' + iteration.str())
		os.mkdir(directory)!
		for wrapped in [false, true]! { for aliased in [false, true]! {
			path := os.join_path(directory, 'shaders π ' + wrapped.str() + aliased.str() + '.metallib')
			bytes := sm_library_fixture(['v_main', 'f_main', 'k_π'], wrapped, aliased); os.write_file_array(path, bytes)!; unsafe { bytes.free() }
			name := owned_string(path); mut failure := u64(0xfeed)
			library := sm_test_library_file(d, name, &failure); assert library != 0 && failure == 0xfeed
			names := sm_send(library, c'functionNames'); assert sm_send(names, c'count') == 3
			function := unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', obj_header(names).items[2]) }
			assert function != 0 && sm_send(function, c'functionType') == 3
			// Storage is independent of the file and the path object.
			os.write_file(path, 'replaced')!; objc_release(name); objc_release(library)
			assert string_text(sm_send(function, c'name')) == 'k_π' && sm_send(function, c'device') == d
			objc_release(function)
		} }
		empty_path := os.join_path(directory, 'empty.metallib'); empty := sm_library_fixture([], false, false); os.write_file_array(empty_path, empty)!; unsafe { empty.free() }
		name := owned_string(empty_path); library := sm_test_library_file(d, name, unsafe { nil }); assert library != 0; objc_release(library); objc_release(name)
		large_path := os.join_path(directory, 'large.metallib'); fd := C.open(large_path.str, C.O_CREAT | C.O_WRONLY, 0o600); assert fd >= 0 && C.ftruncate(fd, 268435457) == 0; C.close(fd)
		fifo_path := os.join_path(directory, 'pipe.metallib'); assert C.mkfifo(fifo_path.str, 0o600) == 0
		for mode in 0 .. 8 {
			text := match mode { 0 { os.join_path(directory, 'missing') } 1 { directory } 2 { large_path } 3 { fifo_path } 4 { empty_path + '\x00suffix' } 5 { 'x'.repeat(1024) } 6 { '' } else { empty_path } }
			path := owned_string(text); mut failure := u64(0)
			if mode == 7 { os.write_file(empty_path, 'bad')! }
			assert sm_test_library_file(d, path, &failure) == 0
			sm_library_check_error(failure, if mode == 0 { i64(6) } else if mode == 7 { i64(3) } else { i64(1) })
			assert sm_test_library_file(d, path, unsafe { nil }) == 0
			objc_release(path)
		}
		for path in [u64(0), d]! { mut failure := u64(0); assert sm_test_library_file(d, path, &failure) == 0; sm_library_check_error(failure, 1) }
		// Remove the sparse oversized fixture; it has no payload evidence to retain.
		os.rm(large_path)!; os.rm(fifo_path)!
		objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-LIBRARY-FILES: raw/wrapped/shared containers, Unicode paths, independent file/function lifetimes, empty library, ten invalid inputs including sparse oversized files and nonblocking FIFOs, optional NSError and two drained runtimes without dispatch PASS')
}
fn sm_test_library(device u64, data u64, output &u64) u64 { return unsafe { SMLibrary(voidptr(C.ios_objc_msgsend))(device, c'newLibraryWithData:error:', data, output) } }
fn sm_library_number(mut data []u8, offset int, count int, value u64) { for i in 0 .. count { data[offset + i] = u8(value >> u32(i * 8)) } }
fn sm_library_append(mut data []u8, count int, value u64) { start := data.len; for _ in 0 .. count { data << u8(0) }; sm_library_number(mut data, start, count, value) }
fn sm_library_tag(mut data []u8, name string, payload []u8) { data << name.bytes(); sm_library_append(mut data, 2, u64(payload.len)); data << payload }
// Synthetic container/index fixtures, deliberately not executable LLVM IR.
fn sm_library_fixture(names []string, wrapped bool, aliased bool) []u8 {
	mut code := []u8{}; code.flags |= .noslices
	if wrapped { for value in [u64(0x0b17c0de), 0, 20, 8, 0xffffffff]! { sm_library_append(mut code, 4, value) } }
	code << [u8(0x42), 0x43, 0xc0, 0xde, 0, 0, 0, 0]
	digest := sha256.sum(code)
	defer { unsafe { code.free(); digest.free() } }
	mut data := []u8{len: 88}; data.flags |= .noslices
	sm_library_number(mut data, 0, 4, 0x424c544d); sm_library_number(mut data, 6, 2, 2)
	sm_library_append(mut data, 4, u64(names.len))
	for i, name in names {
		start := data.len; sm_library_append(mut data, 4, 0)
		mut text := name.bytes(); text << u8(0); sm_library_tag(mut data, 'NAME', text); unsafe { text.free() }
		sm_library_tag(mut data, 'TYPE', [u8(i % 3)])
		sm_library_tag(mut data, 'HASH', digest)
		mut offsets := []u8{len: 24}
		sm_library_number(mut offsets, 0, 8, u64(i * 8)); sm_library_number(mut offsets, 8, 8, u64(i * 8)); sm_library_number(mut offsets, 16, 8, if aliased { u64(0) } else { u64(i * code.len) })
		sm_library_tag(mut data, 'OFFT', offsets); unsafe { offsets.free() }
		sm_library_tag(mut data, 'VERS', [u8(2), 0, 7, 0, 3, 0, 0, 0])
		mut size := []u8{len: 8}; sm_library_number(mut size, 0, 8, u64(code.len)); sm_library_tag(mut data, 'MDSZ', size); unsafe { size.free() }
		data << 'ENDT'.bytes(); sm_library_number(mut data, start, 4, u64(data.len - start))
	}
	sm_library_number(mut data, 24, 8, 88); sm_library_number(mut data, 32, 8, u64(data.len - 92))
	for field in [40, 56]! {
		sm_library_number(mut data, field, 8, u64(data.len)); sm_library_number(mut data, field + 8, 8, u64(names.len * 8))
		for _ in names { sm_library_append(mut data, 4, 8); data << 'ENDT'.bytes() }
	}
	sm_library_number(mut data, 72, 8, u64(data.len)); bits := data.len
	for _ in 0 .. if aliased && names.len > 0 { 1 } else { names.len } { data << code }
	sm_library_number(mut data, 80, 8, u64(data.len - bits)); sm_library_number(mut data, 16, 8, u64(data.len))
	return data
}
fn sm_library_reader(library u64) {
	pool := objc_pool_push()
	for _ in 0 .. 64 { names := sm_send(library, c'functionNames'); assert sm_send(names, c'count') == 3 }
	objc_pool_pop(pool)
}
fn sm_library_check_error(object u64, code i64) {
	assert objc_is_kind(object, ios_runtime.names['NSError'])
	assert string_text(sm_send(object, c'domain')) == 'MTLLibraryErrorDomain' && i64(sm_send(object, c'code')) == code
	assert string_text(sm_send(object, c'localizedDescription')).len > 0
}
fn test_software_metal_compiled_library_metadata() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		for wrapped in [false, true]! { for aliased in [false, true]! {
			pool := objc_pool_push(); d := metal_create_system_default_device()
			bytes := sm_library_fixture(['v_main', 'f_main', 'k_π'], wrapped, aliased)
			// Exercise both a dispatch leaf and concatenated data split inside the header.
			first := darwin_dispatch_data_create(u64(bytes.data), if aliased { 37 } else { u64(bytes.len) }, 0, 0)
			second := if aliased { darwin_dispatch_data_create(u64(bytes.data) + 37, u64(bytes.len - 37), 0, 0) } else { u64(dispatch_runtime.empty_data) }
			data := darwin_dispatch_data_create_concat(first, second)
			darwin_dispatch_release(first); darwin_dispatch_release(second)
			mut failure := u64(0xfeed); library := sm_test_library(d, data, &failure)
			assert library != 0 && failure == 0xfeed && sm_send(library, c'device') == d
			assert obj_header(library).data.data != bytes.data
			darwin_dispatch_release(data); unsafe { bytes.free() }; assert dispatch_runtime.data.len == 1
			names := sm_send(library, c'functionNames'); assert sm_send(names, c'count') == 3
			mut functions := [3]u64{}
			for i, expected in ['v_main', 'f_main', 'k_π']! {
				name := obj_header(names).items[i]; assert string_text(name) == expected
				functions[i] = unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', name) }
				assert functions[i] != 0 && sm_send(functions[i], c'functionType') == u64(i + 1) && sm_send(functions[i], c'device') == d
			}
			missing := owned_string('missing'); assert unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', missing) } == 0; objc_release(missing)
			assert unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', 0) } == 0
			assert unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', d) } == 0
			mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn sm_library_reader(library) }; workers.wait(); unsafe { workers.free() }
			objc_release(library); objc_release(d)
			for i, function in functions { assert string_text(sm_send(function, c'name')) == ['v_main', 'f_main', 'k_π'][i]; assert sm_send(function, c'device') != 0; objc_release(function) }
			objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		} }
		pool := objc_pool_push(); d := metal_create_system_default_device()
		empty := sm_library_fixture([], false, false); data := darwin_dispatch_data_create(u64(empty.data), u64(empty.len), 0, 0)
		library := sm_test_library(d, data, unsafe { nil }); assert library != 0 && sm_send(sm_send(library, c'functionNames'), c'count') == 0
		objc_release(library); darwin_dispatch_release(data); unsafe { empty.free() }
		for invalid in [u64(0), d, u64(dispatch_runtime.empty_data)]! { mut failure := u64(0); assert sm_test_library(d, invalid, &failure) == 0; sm_library_check_error(failure, if invalid == u64(dispatch_runtime.empty_data) { i64(3) } else { i64(1) }) }
		base := sm_library_fixture(['sample'], true, false)
		for length in 0 .. base.len {
			temporary := objc_pool_push(); truncated := darwin_dispatch_data_create(u64(base.data), u64(length), 0, 0); mut failure := u64(0)
			assert sm_test_library(d, truncated, &failure) == 0; sm_library_check_error(failure, 3)
			assert sm_test_library(d, truncated, unsafe { nil }) == 0
			darwin_dispatch_release(truncated); objc_pool_pop(temporary)
		}
		for mode in 0 .. 4 {
			mut bad := base.clone()
			match mode { 0 { bad[0] = 0 } 1 { bad[bad.len - 1] ^= 1 } 2 { sm_library_number(mut bad, 72, 8, ~u64(0)) } else { // TYPE follows NAME's six-byte header and terminated sample name.
				bad[96 + 6 + 7 + 6] = 6
			} }
			broken := darwin_dispatch_data_create(u64(bad.data), u64(bad.len), 0, 0); mut failure := u64(0)
			assert sm_test_library(d, broken, &failure) == 0; sm_library_check_error(failure, if mode == 3 { i64(1) } else { i64(3) })
			darwin_dispatch_release(broken); unsafe { bad.free() }
		}
		unsafe { base.free() }
		// A shared rope represents 512 MiB using only 30 tiny nodes. Reject before flattening.
		byte := u8(1); mut rope := darwin_dispatch_data_create(u64(unsafe { &byte }), 1, 0, 0)
		for _ in 0 .. 29 { next := darwin_dispatch_data_create_concat(rope, rope); darwin_dispatch_release(rope); rope = next }
		mut failure := u64(0); assert sm_test_library(d, rope, &failure) == 0; sm_library_check_error(failure, 1); darwin_dispatch_release(rope)
		objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && dispatch_runtime.data.len == 1
		domain_cell := runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_MTLLibraryErrorDomain') or { panic(err) }
		assert string_text(read64(domain_cell)) == 'MTLLibraryErrorDomain'
		assert runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_MTLLibraryErrorDomain') or { panic(err) } == domain_cell
		objc_stop(); system_data_stop()
	}
	println('IOS-SOFTWARE-METAL-LIBRARY: raw/wrapped and independent/shared module containers, leaf/rope dispatch ABI, owned bytes, names/types/UTF-8, function lifetimes, empty/missing functions, truncations/hash/range/type errors, optional NSError, bounded 512 MiB rope rejection, eight workers and two drained runtimes PASS')
}
type SMSurface = fn (u64, &char, u64, u64, u64) u64
fn sm_test_view(texture u64, format u64) u64 { return unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(texture, c'newTextureViewWithPixelFormat:', format) } }
fn test_software_metal_texture_views() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format in [u64(10), 30, 80, 81]! { for imported in [false, true]! {
			pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
			desc := sm_test_descriptor(format, 3, 2, 0); sm_test_set(desc, c'setUsage:', 17)
			mut image := u64(0); mut surface := u64(0); plane := if format == 30 { u64(1) } else { u64(0) }
			if imported {
				attrs := objc_allocate(ios_runtime.names['NSDictionary']); empty := objc_allocate(ios_runtime.names['NSDictionary']); key := owned_string('IOSurfaceProperties')
				dictionary_insert_copy(attrs, empty, key); objc_release(empty); objc_release(key)
				assert cv_pixel_create(0, 7, 3, if format < 80 { u32(0x34323076) } else { u32(0x42475241) }, attrs, &image) == 0; objc_release(attrs)
				surface = cv_pixel_surface(image); C.memset(unsafe { voidptr(cv_surface_plane_base(surface, plane)) }, 0xcc, usize(cv_surface_plane_row(surface, plane) * cv_surface_plane_height(surface, plane)))
			}
			root := if imported { sm_test_surface(d, desc, surface, plane) } else { sm_test_texture(d, desc) }; assert root != 0 && sm_send(root, c'parentTexture') == 0
			for bad in [u64(0), 99, if format == 10 { u64(30) } else { u64(10) }]! { assert sm_test_view(root, bad) == 0 }
			view_format := if format == 80 { u64(81) } else if format == 81 { u64(80) } else { format }
			view := sm_test_view(root, view_format); nested := sm_test_view(view, format); assert view != 0 && nested != 0 && view != root && nested != view
			assert sm_send(view, c'parentTexture') == root && sm_send(nested, c'parentTexture') == view && sm_send(view, c'pixelFormat') == view_format && sm_send(nested, c'device') == d
			assert sm_send(view, c'width') == 3 && sm_send(view, c'height') == 2 && sm_send(view, c'usage') == 17 && sm_send(view, c'parentRelativeLevel') == 0 && sm_send(view, c'parentRelativeSlice') == 0
			assert sm_send(nested, c'iosurface') == surface && sm_send(nested, c'iosurfacePlane') == if imported { plane } else { u64(0) }
			pixel := sm_pixel_size(format); mut input := [128]u8{}; mut output := [128]u8{}
			for i in 0 .. int(6 * pixel) { input[i] = u8(i + 1) }
			region := SoftwareMetalRegion{width: 3, height: 2, depth: 1}
			sm_test_put(view, region, 0, u64(unsafe { &input[0] }), 3 * pixel); sm_test_read(root, region, 0, u64(unsafe { &output[0] }), 3 * pixel)
			for i in 0 .. int(6 * pixel) { assert output[i] == input[i] }
			cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder')
			child := C.fork(); assert child >= 0
			if child == 0 { C.close(1); C.close(2); sm_test_texture_copy(enc, root, 0, 0, SoftwareMetalOrigin{}, SoftwareMetalSize{width: 1, height: 1, depth: 1}, nested, 0, 0, SoftwareMetalOrigin{}); C._exit(0) }
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			sm_test_texture_copy(enc, root, 0, 0, SoftwareMetalOrigin{}, SoftwareMetalSize{width: 1, height: 1, depth: 1}, nested, 0, 0, SoftwareMetalOrigin{x: 2, y: 1})
			objc_release(root); objc_release(view); objc_release(image); objc_release(d); objc_release(q)
			sm_call(enc, c'endEncoding'); sm_call(cmd, c'commit'); sm_test_read(nested, region, 0, u64(unsafe { &output[0] }), 3 * pixel)
			for i in 0 .. int(pixel) { assert output[int(5 * pixel) + i] == input[i] }
			if imported { assert unsafe { *(&u8(cv_surface_plane_base(surface, plane) + 3 * pixel)) } == 0xcc }
			objc_release(nested); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		} }
		// Conservative cross-format profile requires PixelFormatView usage.
		pool := objc_pool_push(); d := metal_create_system_default_device(); t := sm_test_texture(d, sm_test_descriptor(80, 1, 1, 0)); assert sm_test_view(t, 81) == 0
		same := sm_test_view(t, 80); assert same != 0; objc_release(same); objc_release(t); objc_release(d); objc_pool_pop(pool); objc_stop()
	}
	println('IOS-SOFTWARE-METAL-VIEWS: four formats, owned/IOSurface storage, nested aliases, CPU coherence, BGRA reinterpretation, retained parent/device/plane, padded rows, deferred disjoint blits, overlap and format rejection, two drained runtimes PASS')
}
fn sm_test_surface(d u64, descriptor u64, surface u64, plane u64) u64 { return unsafe { SMSurface(voidptr(C.ios_objc_msgsend))(d, c'newTextureWithDescriptor:iosurface:plane:', descriptor, surface, plane) } }
fn test_software_metal_iosurface_imports() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format_index, format in [u32(0x42475241), 0x42475241, 0x34323076, 0x34323066]! {
			for plane in 0 .. if format == 0x42475241 { 1 } else { 2 } {
				pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
				attrs := objc_allocate(ios_runtime.names['NSDictionary']); empty := objc_allocate(ios_runtime.names['NSDictionary'])
				key := cf_string_create(0, c'IOSurfaceProperties', 0x08000100)
				dictionary_insert_copy(attrs, empty, key); objc_release(empty); objc_release(key)
				mut image := u64(0); assert cv_pixel_create(0, 7, 3, format, attrs, &image) == 0; objc_release(attrs)
				surface := cv_pixel_surface(image); width := cv_surface_plane_width(surface, u64(plane)); height := cv_surface_plane_height(surface, u64(plane))
				metal := if format == 0x42475241 { u64(80 + format_index) } else if plane == 0 { u64(10) } else { u64(30) }
				pixel := sm_pixel_size(metal); row := cv_surface_plane_row(surface, u64(plane)); base := cv_surface_plane_base(surface, u64(plane))
				assert row > width * pixel
				C.memset(unsafe { voidptr(base) }, 0xcc, usize(row * height))
				mut cache := u64(0); assert cv_metal_cache_create(0, 0, d, 0, &cache) == 0
				mut view := u64(0); assert cv_metal_create_view(0, cache, image, 0, metal, width, height, u64(plane), &view) == 0
				texture := objc_retain(cv_metal_get_texture(view)); descriptor := sm_test_descriptor(metal, width, height, 0)
				alias := sm_test_surface(d, descriptor, surface, u64(plane)); assert alias != 0
				assert sm_send(texture, c'iosurface') == surface && sm_send(texture, c'iosurfacePlane') == u64(plane) && sm_send(texture, c'usage') == 23
				for mode in 0 .. 11 {
					bad := sm_test_descriptor(metal, width, height, 0)
					match mode { 0 { sm_test_set(bad, c'setWidth:', 0) } 1 { sm_test_set(bad, c'setWidth:', width + 1) } 2 { sm_test_set(bad, c'setHeight:', height + 1) } 3 { sm_test_set(bad, c'setPixelFormat:', if metal == 10 { 30 } else { 10 }) } 4 { sm_test_set(bad, c'setStorageMode:', 2) } 5 { sm_test_set(bad, c'setUsage:', 32) } else {} }
					assert sm_test_surface(d, if mode == 9 { 0 } else if mode == 10 { image } else { bad }, if mode == 7 { image } else if mode == 8 { 0 } else { surface }, if mode == 6 { 2 } else { u64(plane) }) == 0
				}
				// Separate imports of one plane must reject overlapping rectangles.
				child := C.fork(); assert child >= 0
				if child == 0 { C.close(1); C.close(2); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder'); sm_test_texture_copy(enc, texture, 0, 0, SoftwareMetalOrigin{}, SoftwareMetalSize{1, 1, 1}, alias, 0, 0, SoftwareMetalOrigin{}); C._exit(0) }
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
				// CPU writes through either import are visible through the other.
				mut bytes := [256]u8{}; for i in 0 .. bytes.len { bytes[i] = u8(i % 251) }
				sm_test_put(texture, SoftwareMetalRegion{0, 0, 0, width, height, 1}, 0, u64(unsafe { &bytes[0] }), 32)
				mut readback := [256]u8{}; sm_test_read(alias, SoftwareMetalRegion{0, 0, 0, width, height, 1}, 0, u64(unsafe { &readback[0] }), 32)
				for y in u64(0) .. height { for x in u64(0) .. width * pixel { assert readback[int(y * 32 + x)] == bytes[int(y * 32 + x)] } }
				// Import a narrower descriptor, preserving the underlying plane pitch.
				sm_test_set(descriptor, c'setWidth:', width - 1)
				narrow := sm_test_surface(d, descriptor, surface, u64(plane)); assert narrow != 0
				owned := sm_test_texture(d, descriptor); assert sm_send(owned, c'iosurface') == 0
				input := sm_test_buffer(d, 128, 0); output := sm_test_buffer(d, 128, 0)
				C.memset(unsafe { voidptr(sm_send(input, c'contents')) }, 0x6b, 128)
				C.memset(unsafe { voidptr(sm_send(output, c'contents')) }, 0xee, 128)
				command := sm_send(q, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder'); size := SoftwareMetalSize{width - 1, height, 1}
				sm_test_buffer_texture(encoder, input, 0, 32, 0, size, narrow, 0, 0, SoftwareMetalOrigin{}, true)
				sm_test_texture_copy(encoder, narrow, 0, 0, SoftwareMetalOrigin{}, size, owned, 0, 0, SoftwareMetalOrigin{})
				sm_test_texture_copy(encoder, owned, 0, 0, SoftwareMetalOrigin{}, size, alias, 0, 0, SoftwareMetalOrigin{})
				sm_test_buffer_texture(encoder, output, 0, 32, 0, size, texture, 0, 0, SoftwareMetalOrigin{}, false)
				assert unsafe { *(&u8(base)) } == 0 // Still the earlier CPU pattern.
				cv_metal_flush(cache, 0); objc_release(view); objc_release(cache); objc_release(image)
				objc_release(texture); objc_release(alias); objc_release(narrow); objc_release(owned); objc_release(input)
				sm_call(encoder, c'endEncoding'); sm_call(command, c'commit')
				for y in u64(0) .. height { for x in u64(0) .. row {
					expected := if x < (width - 1) * pixel { u8(0x6b) } else if x < width * pixel { bytes[int(y * 32 + x)] } else { u8(0xcc) }
					assert unsafe { *(&u8(base + y * row + x)) } == expected
				} }
				for i in u64(0) .. 128 { assert unsafe { *(&u8(sm_send(output, c'contents') + i)) } == if i / 32 < height && i % 32 < (width - 1) * pixel { u8(0x6b) } else { u8(0xee) } }
				// Disjoint rectangles through distinct aliases remain valid.
				next := sm_send(q, c'commandBuffer'); blit := sm_send(next, c'blitCommandEncoder')
				sm_test_texture_copy(blit, texture, 0, 0, SoftwareMetalOrigin{}, SoftwareMetalSize{1, 1, 1}, alias, 0, 0, SoftwareMetalOrigin{width - 1, 0, 0})
				sm_call(blit, c'endEncoding'); sm_call(next, c'commit')
				for x in u64(0) .. pixel { assert unsafe { *(&u8(base + (width - 1) * pixel + x)) } == 0x6b }
				objc_release(output); objc_release(q); objc_release(d); objc_pool_pop(pool)
				assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
			}
		}
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-IOSURFACE: four Metal formats, BGRA/420v/420f planes, CoreVideo cache imports, shared CPU bytes, padded and narrowed strides, deferred buffer/texture blits, owners released before commit, eleven invalid imports, alias overlap/disjoint checks and two drained runtimes PASS')
}
type SMFill = fn (u64, &char, u64, SoftwareMetalRange, u8)
fn sm_test_fill(encoder u64, buffer u64, range SoftwareMetalRange, value u8) { unsafe { SMFill(voidptr(C.ios_objc_msgsend))(encoder, c'fillBuffer:range:value:', buffer, range, value) } }
fn test_software_metal_deferred_buffer_fills() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
		for value in 0 .. 256 {
			pool := objc_pool_push()
			a := sm_test_buffer(d, 64, 0); b := sm_test_buffer(d, 64, 0); c := sm_test_buffer(d, 64, 0)
			C.memset(unsafe { voidptr(sm_send(a, c'contents')) }, 0x11, 64); C.memset(unsafe { voidptr(sm_send(b, c'contents')) }, 0xfe, 64)
			range := match value % 5 { 0 { SoftwareMetalRange{length: 64} } 1 { SoftwareMetalRange{location: 64} } 2 { SoftwareMetalRange{location: 3, length: 17} } 3 { SoftwareMetalRange{location: 63, length: 1} } else { SoftwareMetalRange{location: 1, length: 62} } }
			command := sm_send(q, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
			sm_test_fill(encoder, a, range, u8(value)); sm_test_copy(encoder, a, 0, b, 0, 64)
			sm_test_fill(encoder, c, SoftwareMetalRange{length: 64}, u8(value))
			sm_test_fill(encoder, a, SoftwareMetalRange{length: 4}, 0x22); sm_test_copy(encoder, a, 0, c, 0, 4)
			for i in 0 .. 64 { assert unsafe { *(&u8(sm_send(a, c'contents') + u64(i))) } == 0x11 && unsafe { *(&u8(sm_send(b, c'contents') + u64(i))) } == 0xfe }
			objc_release(a); sm_call(encoder, c'endEncoding'); sm_call(command, c'commit'); sm_call(command, c'waitUntilCompleted')
			for i in u64(0) .. 64 {
				expected := if i >= range.location && i - range.location < range.length { u8(value) } else { u8(0x11) }
				assert unsafe { *(&u8(sm_send(b, c'contents') + i)) } == expected
				assert unsafe { *(&u8(sm_send(c, c'contents') + i)) } == if i < 4 { u8(0x22) } else { u8(value) }
			}
			objc_release(b); objc_release(c); objc_pool_pop(pool)
			assert ios_runtime.live == 2
		}
		// An abandoned command releases its retained fill destination.
		pool := objc_pool_push(); unused := sm_send(q, c'commandBuffer'); enc := sm_send(unused, c'blitCommandEncoder'); buffer := sm_test_buffer(d, 8, 0)
		sm_test_fill(enc, buffer, SoftwareMetalRange{length: 8}, 0xff); objc_release(buffer); objc_pool_pop(pool)
		assert ios_runtime.live == 2
		for mode in 0 .. 8 {
			child := C.fork(); assert child >= 0
			if child == 0 {
				C.close(1); C.close(2)
				command := sm_send(q, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
				buf := if mode == 6 { objc_allocate(ios_runtime.names['NSObject']) } else { sm_test_buffer(if mode == 3 { metal_create_system_default_device() } else { d }, 64, 0) }
				if mode in [4, 5]! { sm_call(encoder, c'endEncoding') }; if mode == 5 { sm_call(command, c'commit') }
				range := match mode { 0 { SoftwareMetalRange{location: ~u64(0), length: 1} } 1 { SoftwareMetalRange{location: 64, length: 1} } 2 { SoftwareMetalRange{location: 1, length: ~u64(0)} } 7 { SoftwareMetalRange{location: 65} } else { SoftwareMetalRange{length: 4} } }
				sm_test_fill(encoder, buf, range, 0xff); C._exit(0)
			}
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		objc_release(q); objc_release(d)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-FILL: 256 byte values, inline range ABI, deferred ordered fill/copy/fill/copy, edges/empty ranges, retained destinations, abandonment, eight rejection modes and two drained runtimes PASS')
}
type SMPut = fn (u64, &char, SoftwareMetalRegion, u64, u64, u64)
type SMRead = fn (u64, &char, u64, u64, SoftwareMetalRegion, u64)
type SMTextureCopy = fn (u64, &char, u64, u64, u64, SoftwareMetalOrigin, SoftwareMetalSize, u64, u64, u64, SoftwareMetalOrigin)
type SMUpload = fn (u64, &char, u64, u64, u64, u64, SoftwareMetalSize, u64, u64, u64, SoftwareMetalOrigin)
type SMDownload = fn (u64, &char, u64, u64, u64, SoftwareMetalOrigin, SoftwareMetalSize, u64, u64, u64, u64)
struct SMCompletionBlock { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
struct SMCompletionProbe {
	owner u64
mut:
	copies u64
	drops u64
	calls u64
	entered u64
	gate u64
	wait_entered u64
	wait_done u64
}
fn sm_completion_copy(destination u64, source u64) {
	probe := unsafe { &SMCompletionProbe(read64(source + 32)) }
	objc_retain(probe.owner)
	C.__atomic_fetch_add(unsafe { &probe.copies }, 1, 5)
}
fn sm_completion_drop(block u64) {
	probe := unsafe { &SMCompletionProbe(read64(block + 32)) }
	objc_release(probe.owner)
	C.__atomic_fetch_add(unsafe { &probe.drops }, 1, 5)
}
fn sm_completion_query(command u64) { assert sm_send(command, c'status') == 4 }
fn sm_completion_invoke(block u64, command u64) {
	probe := unsafe { &SMCompletionProbe(read64(block + 32)) }
	assert sm_send(command, c'status') == 4 && obj_header(probe.owner).refs > 0
	assert unsafe { *(&u64(sm_send(probe.owner, c'contents'))) } == u64(0x123456789abcdef0)
	worker := spawn sm_completion_query(command); worker.wait() // Requires unlocked callbacks.
	C.__atomic_fetch_add(unsafe { &probe.calls }, 1, 5)
	C.__atomic_store_n(unsafe { &probe.entered }, 1, 5)
	for C.__atomic_load_n(unsafe { &probe.gate }, 5) != 0 { C.usleep(100) }
}
fn sm_completion_commit(command u64) { pool := objc_pool_push(); sm_call(command, c'commit'); objc_pool_pop(pool) }
fn sm_completion_wait(command u64, probe &SMCompletionProbe) {
	C.__atomic_store_n(unsafe { &probe.wait_entered }, 1, 5)
	sm_call(command, c'waitUntilCompleted')
	C.__atomic_store_n(unsafe { &probe.wait_done }, 1, 5)
}
fn sm_completion_until(value &u64) {
	for _ in 0 .. 20000 { if C.__atomic_load_n(value, 5) != 0 { return }; C.usleep(100) }
	assert false, 'completion callback timed out'
}
fn sm_scheduled_query(command u64) { assert sm_send(command, c'status') == 3 }
fn sm_scheduled_invoke(block u64, command u64) {
	probe := unsafe { &SMCompletionProbe(read64(block + 32)) }
	assert sm_send(command, c'status') == 3 && unsafe { *(&u64(sm_send(probe.owner, c'contents'))) } == 0
	worker := spawn sm_scheduled_query(command); worker.wait()
	C.__atomic_fetch_add(unsafe { &probe.calls }, 1, 5)
	C.__atomic_store_n(unsafe { &probe.entered }, 1, 5)
	for C.__atomic_load_n(unsafe { &probe.gate }, 5) != 0 { C.usleep(100) }
}
fn sm_scheduled_wait(command u64, probe &SMCompletionProbe) {
	C.__atomic_store_n(unsafe { &probe.wait_entered }, 1, 5)
	sm_call(command, c'waitUntilScheduled')
	C.__atomic_store_n(unsafe { &probe.wait_done }, 1, 5)
}
fn test_software_metal_scheduled_handlers() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue'); cmd := sm_send(q, c'commandBuffer')
		target := sm_test_buffer(d, 8, 0); source := sm_test_buffer(d, 8, 0)
		unsafe { *(&u64(sm_send(source, c'contents'))) = 0x123456789abcdef0 }
		encoder := sm_send(cmd, c'blitCommandEncoder'); sm_test_copy(encoder, source, 0, target, 0, 8); sm_call(encoder, c'endEncoding'); objc_release(source)
		mut scheduled := SMCompletionProbe{owner: target, gate: 1}; mut completed := SMCompletionProbe{owner: target, gate: 1}
		descriptor := [u64(0), u64(sizeof(SMCompletionBlock)), u64(unsafe { voidptr(sm_completion_copy) }), u64(unsafe { voidptr(sm_completion_drop) })]!
		block := SMCompletionBlock{isa: block_isa(0), flags: u32(1) << 25, invoke: u64(unsafe { voidptr(sm_scheduled_invoke) }), descriptor: u64(unsafe { &descriptor[0] }), capture: u64(unsafe { &scheduled })}
		for _ in 0 .. 3 { sm_test_set(cmd, c'addScheduledHandler:', u64(unsafe { &block })) }
		completion := SMCompletionBlock{...block, invoke: u64(unsafe { voidptr(sm_completion_invoke) }), capture: u64(unsafe { &completed })}
		sm_test_set(cmd, c'addCompletedHandler:', u64(unsafe { &completion })); objc_release(target)
		commit := spawn sm_completion_commit(cmd); sm_completion_until(unsafe { &scheduled.entered })
		waiter := spawn sm_scheduled_wait(cmd, unsafe { &scheduled }); sm_completion_until(unsafe { &scheduled.wait_entered }); C.usleep(2000)
		assert C.__atomic_load_n(unsafe { &scheduled.wait_done }, 5) == 0
		C.__atomic_store_n(unsafe { &scheduled.gate }, 0, 5); sm_completion_until(unsafe { &completed.entered }); sm_completion_until(unsafe { &scheduled.wait_done }); waiter.wait()
		assert sm_send(cmd, c'status') == 4 && scheduled.calls == 3 && scheduled.copies == 3 && scheduled.drops == 3
		C.__atomic_store_n(unsafe { &completed.gate }, 0, 5); commit.wait(); sm_call(cmd, c'waitUntilScheduled'); sm_call(cmd, c'waitUntilCompleted')
		assert completed.calls == 1 && completed.drops == 1
		inner := objc_pool_push(); unused := sm_send(q, c'commandBuffer')
		mut abandoned := SMCompletionProbe{owner: objc_allocate(ios_runtime.names['NSObject'])}
		abandon := SMCompletionBlock{...block, capture: u64(unsafe { &abandoned })}
		sm_test_set(unused, c'addScheduledHandler:', u64(unsafe { &abandon })); objc_release(abandoned.owner)
		for mode in 0 .. 3 {
			child := C.fork(); assert child >= 0
			if child == 0 { C.close(1); C.close(2); if mode == 0 { sm_call(unused, c'waitUntilScheduled') } else { sm_test_set(cmd, c'addScheduledHandler:', if mode == 1 { u64(0) } else { u64(unsafe { &block }) }) }; C._exit(0) }
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		objc_pool_pop(inner); assert abandoned.calls == 0 && abandoned.copies == 1 && abandoned.drops == 1
		objc_release(q); objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-SCHEDULED: copied captures, three callbacks at status 3 before copies, unlocked worker queries, concurrent scheduled wait, completion separation, abandonment, three invalid states and two drained runtimes PASS')
}
fn test_software_metal_completed_handlers_and_wait() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push()
		d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue'); cmd := sm_send(q, c'commandBuffer')
		owner := sm_test_buffer(d, 8, 0); source := sm_test_buffer(d, 8, 0)
		unsafe { *(&u64(sm_send(source, c'contents'))) = 0x123456789abcdef0 }
		encoder := sm_send(cmd, c'blitCommandEncoder'); sm_test_copy(encoder, source, 0, owner, 0, 8); sm_call(encoder, c'endEncoding'); objc_release(source)
		mut probe := SMCompletionProbe{owner: owner, gate: 1}
		descriptor := [u64(0), u64(sizeof(SMCompletionBlock)), u64(unsafe { voidptr(sm_completion_copy) }), u64(unsafe { voidptr(sm_completion_drop) })]!
		block := SMCompletionBlock{isa: block_isa(0), flags: u32(1) << 25, invoke: u64(unsafe { voidptr(sm_completion_invoke) }), descriptor: u64(unsafe { &descriptor[0] }), capture: u64(unsafe { &probe })}
		for _ in 0 .. 3 { sm_test_set(cmd, c'addCompletedHandler:', u64(unsafe { &block })) }
		assert probe.copies == 3 && probe.drops == 0 && ios_runtime.block_refs.len == 3
		objc_release(owner)
		commit := spawn sm_completion_commit(cmd)
		sm_completion_until(unsafe { &probe.entered })
		waiter := spawn sm_completion_wait(cmd, unsafe { &probe })
		sm_completion_until(unsafe { &probe.wait_entered }); C.usleep(2000)
		assert C.__atomic_load_n(unsafe { &probe.wait_done }, 5) == 0
		C.__atomic_store_n(unsafe { &probe.gate }, 0, 5)
		commit.wait(); waiter.wait()
		assert probe.calls == 3 && probe.drops == 3 && ios_runtime.block_refs.len == 0 && probe.wait_done == 1
		// Uncommitted command disposal releases captures without invoking them.
		mut abandoned := SMCompletionProbe{owner: objc_allocate(ios_runtime.names['NSObject'])}
		abandoned_block := SMCompletionBlock{...block, capture: u64(unsafe { &abandoned })}
		inner := objc_pool_push(); unused := sm_send(q, c'commandBuffer')
		sm_test_set(unused, c'addCompletedHandler:', u64(unsafe { &abandoned_block })); objc_release(abandoned.owner); objc_pool_pop(inner)
		assert abandoned.copies == 1 && abandoned.drops == 1 && abandoned.calls == 0
		mut late := SMCompletionProbe{owner: objc_allocate(ios_runtime.names['NSObject'])}
		late_block := SMCompletionBlock{...block, capture: u64(unsafe { &late })}
		for mode in 0 .. 2 {
			child := C.fork(); assert child >= 0
			if child == 0 { C.close(1); C.close(2); sm_test_set(cmd, c'addCompletedHandler:', if mode == 0 { u64(0) } else { u64(unsafe { &late_block }) }); C._exit(0) }
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		objc_release(late.owner); objc_release(q); objc_release(d); objc_pool_pop(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-COMPLETION: copied block ABI/capture lifetimes, three callbacks, unlocked worker queries, concurrent wait, abandoned buffers, invalid/late handlers and two drained runtimes PASS')
}
fn sm_test_buffer_texture(encoder u64, buffer u64, offset u64, row u64, image u64, size SoftwareMetalSize, texture u64, slice u64, level u64, origin SoftwareMetalOrigin, upload bool) {
	if upload { unsafe { SMUpload(voidptr(C.ios_objc_msgsend))(encoder, c'copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:', buffer, offset, row, image, size, texture, slice, level, origin) } }
	else { unsafe { SMDownload(voidptr(C.ios_objc_msgsend))(encoder, c'copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:', texture, slice, level, origin, size, buffer, offset, row, image) } }
}
fn test_software_metal_buffer_texture_roundtrip() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format in [u64(10), 30, 80, 81]! {
			pool := objc_pool_push(); d := metal_create_system_default_device(); pixel := sm_pixel_size(format)
			a := sm_test_texture(d, sm_test_descriptor(format, 7, 5, 0)); b := sm_test_texture(d, sm_test_descriptor(format, 7, 5, 0))
			input := sm_test_buffer(d, 128, 0); output := sm_test_buffer(d, 128, 0); final := sm_test_buffer(d, 128, 0)
			for i in 0 .. 128 { unsafe { *(&u8(sm_send(input, c'contents') + u64(i))) = u8(i * 11 + 5); *(&u8(sm_send(output, c'contents') + u64(i))) = 0xcc } }
			q := sm_send(d, c'newCommandQueue'); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder')
			size := SoftwareMetalSize{width: 3, height: 2, depth: 1}; origin := SoftwareMetalOrigin{x: 1, y: 1}
			sm_test_buffer_texture(enc, input, 4 * pixel, 5 * pixel, 0, size, a, 0, 0, origin, true)
			sm_test_texture_copy(enc, a, 0, 0, origin, size, b, 0, 0, origin)
			sm_test_buffer_texture(enc, output, 8 * pixel, 6 * pixel, 0, size, b, 0, 0, origin, false)
			sm_test_copy(enc, output, 0, final, 0, 128)
			for i in 0 .. 128 { assert unsafe { *(&u8(sm_send(output, c'contents') + u64(i))) } == 0xcc }
			unsafe { *(&u8(sm_send(input, c'contents') + 4 * pixel)) = 0xff }
			objc_release(input); objc_release(output); objc_release(a); objc_release(q); objc_release(d)
			sm_call(enc, c'endEncoding'); sm_call(cmd, c'commit'); sm_call(cmd, c'waitUntilCompleted')
			for i in 0 .. 128 {
				position := u64(i); first := 8 * pixel; second := 14 * pixel
				inside := (position >= first && position < first + 3 * pixel) || (position >= second && position < second + 3 * pixel)
				index := if position >= second { 9 * pixel + position - second } else { 4 * pixel + position - first }
				expected := if inside { if index == 4 * pixel { u8(0xff) } else { u8(index * 11 + 5) } } else { u8(0xcc) }
				assert unsafe { *(&u8(sm_send(final, c'contents') + position)) } == expected
			}
			for upload in [true, false]! { for mode in 0 .. 10 {
				child := C.fork(); assert child >= 0
				if child == 0 {
					C.close(1); C.close(2)
					dev := metal_create_system_default_device(); queue := sm_send(dev, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
					tex := sm_test_texture(dev, sm_test_descriptor(format, 7, 5, 0)); buf := sm_test_buffer(if mode == 8 { metal_create_system_default_device() } else { dev }, 128, 0)
					if mode == 9 { sm_call(encoder, c'endEncoding') }
					sm_test_buffer_texture(encoder, buf, if mode == 0 { ~u64(0) } else if mode == 1 { u64(124) } else { u64(0) }, if mode == 2 { u64(1) } else if mode == 3 { ~u64(0) } else { 5 * pixel }, if mode == 4 { u64(1) } else { 0 }, size, tex, if mode == 5 { u64(1) } else { 0 }, if mode == 6 { u64(1) } else { 0 }, if mode == 7 { SoftwareMetalOrigin{x: 7} } else { origin }, upload)
					C._exit(0)
				}
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			} }
			objc_release(b); objc_release(final); objc_pool_pop(pool)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-BUFFER-TEXTURE: four formats, both long-selector ABIs, deferred mixed-command round trips, padded rows/offsets, retained resources, ten rejection modes per direction and two drained runtimes PASS')
}
fn sm_test_texture_copy(encoder u64, source u64, slice u64, level u64, origin SoftwareMetalOrigin, size SoftwareMetalSize, destination u64, target_slice u64, target_level u64, target SoftwareMetalOrigin) {
	unsafe { SMTextureCopy(voidptr(C.ios_objc_msgsend))(encoder, c'copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:', source, slice, level, origin, size, destination, target_slice, target_level, target) }
}
fn test_software_metal_deferred_texture_blits() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format in [u64(10), 30, 80, 81]! {
			pool := objc_pool_push(); device := metal_create_system_default_device(); pixel := sm_pixel_size(format)
			a := sm_test_texture(device, sm_test_descriptor(format, 7, 5, 0)); b := sm_test_texture(device, sm_test_descriptor(format, 9, 6, 0)); c := sm_test_texture(device, sm_test_descriptor(format, 5, 4, 0))
			mut input := [160]u8{}; mut output := [256]u8{}
			for i in 0 .. 160 { input[i] = u8(i * 13 + 7) }
			sm_test_put(a, SoftwareMetalRegion{width: 7, height: 5, depth: 1}, 0, u64(&input[0]), 7 * pixel)
			queue := sm_send(device, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
			origin := SoftwareMetalOrigin{x: 1, y: 1}; target := SoftwareMetalOrigin{x: 3, y: 2}; size := SoftwareMetalSize{width: 3, height: 2, depth: 1}
			sm_test_texture_copy(encoder, a, 0, 0, origin, size, b, 0, 0, target)
			sm_test_texture_copy(encoder, b, 0, 0, target, size, c, 0, 0, origin)
			sm_test_read(b, SoftwareMetalRegion{width: 9, height: 6, depth: 1}, 0, u64(&output[0]), 9 * pixel)
			for i in 0 .. int(54 * pixel) { assert output[i] == 0 }
			// Recording retains resources, but reads their bytes when committed.
			input[0] = 0xff
			sm_test_put(a, SoftwareMetalRegion{x: 1, y: 1, width: 1, height: 1, depth: 1}, 0, u64(&input[0]), 0)
			sm_call(encoder, c'endEncoding'); second := sm_send(command, c'blitCommandEncoder')
			sm_test_texture_copy(second, c, 0, 0, origin, SoftwareMetalSize{width: 3, height: 1, depth: 1}, c, 0, 0, SoftwareMetalOrigin{y: 3})
			sm_call(second, c'endEncoding'); objc_release(a); objc_release(queue); objc_release(device)
			sm_call(command, c'commit'); sm_call(command, c'waitUntilCompleted')
			sm_test_read(b, SoftwareMetalRegion{width: 9, height: 6, depth: 1}, 0, u64(&output[0]), 9 * pixel)
			for y in 0 .. 6 { for x in 0 .. 9 { for byte in 0 .. int(pixel) {
				expected := if y == 2 && x == 3 { input[byte] } else if y >= 2 && y < 4 && x >= 3 && x < 6 { input[((y - 1) * 7 + x - 2) * int(pixel) + byte] } else { u8(0) }
				assert output[(y * 9 + x) * int(pixel) + byte] == expected
			} } }
			sm_test_read(c, SoftwareMetalRegion{width: 5, height: 4, depth: 1}, 0, u64(&output[0]), 5 * pixel)
			for y in 0 .. 4 { for x in 0 .. 5 { for byte in 0 .. int(pixel) {
				copied := (y >= 1 && y < 3 && x >= 1 && x < 4) || (y == 3 && x < 3)
				sx := if y == 3 { x + 1 } else { x }; sy := if y == 3 { 1 } else { y }
				expected := if copied { if sx == 1 && sy == 1 { input[byte] } else { input[(sy * 7 + sx) * int(pixel) + byte] } } else { u8(0) }
				assert output[(y * 5 + x) * int(pixel) + byte] == expected
			} } }
			for mode in 0 .. 10 {
				child := C.fork(); assert child >= 0
				if child == 0 {
					C.close(1); C.close(2)
					d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue'); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder')
					src := sm_test_texture(d, sm_test_descriptor(format, 7, 5, 0))
					dst := if mode == 8 { src } else { sm_test_texture(if mode == 7 { metal_create_system_default_device() } else { d }, sm_test_descriptor(if mode == 6 { if format == 10 { u64(30) } else { u64(10) } } else { format }, 7, 5, 0)) }
					if mode == 9 { sm_call(enc, c'endEncoding') }
					sm_test_texture_copy(enc, src, if mode == 0 { u64(1) } else { 0 }, if mode == 1 { u64(1) } else { 0 }, if mode == 2 { SoftwareMetalOrigin{x: ~u64(0)} } else { origin }, if mode == 3 { SoftwareMetalSize{...size, width: 0} } else { size }, dst, if mode == 4 { u64(1) } else { 0 }, if mode == 5 { u64(1) } else { 0 }, origin)
					C._exit(0)
				}
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			}
			objc_release(b); objc_release(c); objc_pool_pop(pool)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-TEXTURE-BLITS: four formats, aggregate/stack argument ABI, deferred dependent copies, different strides, same-texture disjoint copies, retained resources, ten rejection modes and two drained runtimes PASS')
}
fn sm_test_descriptor(format u64, width u64, height u64, mipmapped u8) u64 { return unsafe { SMDescriptor(voidptr(C.ios_objc_msgsend))(ios_runtime.names['MTLTextureDescriptor'], c'texture2DDescriptorWithPixelFormat:width:height:mipmapped:', format, width, height, mipmapped) } }
fn sm_test_texture(device u64, descriptor u64) u64 { return unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(device, c'newTextureWithDescriptor:', descriptor) } }
fn sm_test_set(object u64, selector &char, value u64) { unsafe { SMSet(voidptr(C.ios_objc_msgsend))(object, selector, value) } }
fn sm_test_put(texture u64, region SoftwareMetalRegion, level u64, bytes u64, row u64) { unsafe { SMPut(voidptr(C.ios_objc_msgsend))(texture, c'replaceRegion:mipmapLevel:withBytes:bytesPerRow:', region, level, bytes, row) } }
fn sm_test_read(texture u64, region SoftwareMetalRegion, level u64, bytes u64, row u64) { unsafe { SMRead(voidptr(C.ios_objc_msgsend))(texture, c'getBytes:bytesPerRow:fromRegion:mipmapLevel:', bytes, row, region, level) } }

fn test_software_metal_texture_storage_region_abi_and_lifetimes() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format in [u64(10), 30, 80, 81]! {
			pool := objc_pool_push(); device := metal_create_system_default_device()
			assert sm_test_descriptor(format, 7, 5, 1) == 0
			descriptor := sm_test_descriptor(format, 7, 5, 0)
			assert descriptor != 0 && sm_send(descriptor, c'width') == 7
			texture := sm_test_texture(device, descriptor)
			assert texture != 0 && sm_send(texture, c'width') == 7 && sm_send(texture, c'height') == 5 && sm_send(texture, c'pixelFormat') == format && sm_send(texture, c'device') == device
			assert sm_send(texture, c'mipmapLevelCount') == 1 && sm_send(texture, c'textureType') == 2 && sm_send(texture, c'storageMode') == 0
			for selector in [c'setWidth:', c'setStorageMode:', c'setPixelFormat:', c'setUsage:']! {
				key := ctext(u64(selector))
				original := sm_send(descriptor, if key == 'setWidth:' { c'width' } else if key == 'setStorageMode:' { c'storageMode' } else if key == 'setPixelFormat:' { c'pixelFormat' } else { c'usage' })
				sm_test_set(descriptor, selector, if key == 'setWidth:' { u64(0) } else { ~u64(0) })
				assert sm_test_texture(device, descriptor) == 0
				sm_test_set(descriptor, selector, original)
			}
			sm_test_set(descriptor, c'setWidth:', 16385); assert sm_test_texture(device, descriptor) == 0
			sm_test_set(descriptor, c'setWidth:', 16384); sm_test_set(descriptor, c'setHeight:', 16384); assert sm_test_texture(device, descriptor) == 0
			assert sm_send(texture, c'width') == 7 && sm_send(texture, c'height') == 5
			objc_release(device); objc_pool_pop(pool) // Texture owns its snapshot and device.
			pixel := sm_pixel_size(format); row := 7 * pixel + 4
			mut input := [64]u8{}; mut output := [256]u8{}
			for i in 0 .. 64 { input[i] = u8(i * 7 + 3) }
			for i in 0 .. 256 { output[i] = 0xcc }
			full := SoftwareMetalRegion{width: 7, height: 5, depth: 1}
			sm_test_read(texture, full, 0, u64(&output[4]), row)
			for y in 0 .. 5 { for x in 0 .. int(row) { assert output[4 + y * int(row) + x] == if x < int(7 * pixel) { u8(0) } else { u8(0xcc) } } }
			region := SoftwareMetalRegion{x: 2, y: 1, width: 3, height: 2, depth: 1}
			sm_test_put(texture, region, 0, u64(&input[0]), 3 * pixel + 4)
			sm_test_read(texture, full, 0, u64(&output[4]), row)
			for y in 0 .. 5 { for x in 0 .. int(row) {
				expected := if x >= int(7 * pixel) { u8(0xcc) } else if y >= 1 && y < 3 && x >= int(2 * pixel) && x < int(5 * pixel) { input[(y - 1) * int(3 * pixel + 4) + x - int(2 * pixel)] } else { u8(0) }
				assert output[4 + y * int(row) + x] == expected
			} }
			for i in 0 .. 4 { assert output[i] == 0xcc && output[4 + int(row) * 5 + i] == 0xcc }
			one := SoftwareMetalRegion{width: 1, height: 1, depth: 1}
			sm_test_put(texture, one, 0, u64(&input[0]), 0)
			sm_test_read(texture, one, 0, u64(&output[240]), 0)
			for i in 0 .. int(pixel) { assert output[240 + i] == input[i] }
			for mode in 0 .. 9 {
				child := C.fork(); assert child >= 0
				if child == 0 {
					C.close(1); C.close(2)
					bad := match mode { 0 { SoftwareMetalRegion{...region, x: 7} } 1 { SoftwareMetalRegion{...region, y: ~u64(0)} } 2 { SoftwareMetalRegion{...region, depth: 2} } else { region } }
					sm_test_put(texture, bad, if mode == 3 { u64(1) } else { 0 }, if mode == 4 { u64(0) } else if mode == 6 { ~u64(0) } else { u64(unsafe { &input[0] }) }, if mode == 5 { ~u64(0) } else if mode == 7 { u64(1) } else if mode == 8 { if pixel == 1 { u64(0) } else { 3 * pixel + 1 } } else { 3 * pixel + 4 })
					C._exit(0)
				}
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			}
			objc_release(texture)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-TEXTURES: four formats, 48-byte region ABI, padded subregion uploads/readback, guards, descriptor snapshots, device lifetimes and two drained runtimes PASS')
}
fn sm_send(object u64, selector &char) u64 { return unsafe { SMGet(voidptr(C.ios_objc_msgsend))(object, selector) } }
fn sm_call(object u64, selector &char) { unsafe { SMVoid(voidptr(C.ios_objc_msgsend))(object, selector) } }
fn sm_test_buffer(device u64, length u64, options u64) u64 { return unsafe { SMBuffer(voidptr(C.ios_objc_msgsend))(device, c'newBufferWithLength:options:', length, options) } }
fn sm_test_copy(encoder u64, src u64, a u64, dst u64, b u64, size u64) { unsafe { SMCopy(voidptr(C.ios_objc_msgsend))(encoder, c'copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:', src, a, dst, b, size) } }
fn sm_test_reject(mode int) {
	child := C.fork(); assert child >= 0
	if child == 0 {
		C.close(1); C.close(2)
		device := metal_create_system_default_device(); queue := sm_send(device, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
		a := sm_test_buffer(device, 64, 0); b := sm_test_buffer(device, 64, 0)
		match mode {
			0 { sm_call(command, c'commit') }
			1 { sm_call(command, c'waitUntilCompleted') }
			2 { sm_test_copy(encoder, a, 63, b, 0, 2) }
			3 { sm_test_copy(encoder, a, ~u64(0), b, 0, 1) }
			4 { sm_test_copy(encoder, a, 0, a, 4, 8) }
			5 { sm_call(encoder, c'endEncoding'); sm_test_copy(encoder, a, 0, b, 0, 1) }
			6 { sm_call(encoder, c'endEncoding'); sm_call(encoder, c'endEncoding') }
			7 { sm_call(encoder, c'endEncoding'); sm_call(command, c'commit'); sm_call(command, c'commit') }
			8 { other := metal_create_system_default_device(); x := sm_test_buffer(other, 64, 0); sm_test_copy(encoder, a, 0, x, 0, 1) }
			else { sm_send(command, c'blitCommandEncoder') }
		}
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child && status == 256, 'invalid Metal state/range did not reject cleanly'
}
fn sm_test_worker() {
	pool := objc_pool_push()
	device := metal_create_system_default_device(); queue := sm_send(device, c'newCommandQueue')
	a := sm_test_buffer(device, 16, 0); b := sm_test_buffer(device, 16, 0)
	unsafe { *(&u64(sm_send(a, c'contents'))) = 0x123456789abcdef0 }
	command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
	sm_test_copy(encoder, a, 0, b, 8, 8); sm_call(encoder, c'endEncoding'); sm_call(command, c'commit')
	assert unsafe { *(&u64(sm_send(b, c'contents') + 8)) } == u64(0x123456789abcdef0)
	objc_release(a); objc_release(b); objc_release(queue); objc_release(device); objc_pool_pop(pool)
}
fn test_software_metal_deferred_blit_abi_lifetimes_and_threads() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		address := runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_MTLCreateSystemDefaultDevice') or { panic(err) }
		device := unsafe { SMCreate(voidptr(address))() }
		assert device != 0 && sm_send(device, c'maxBufferLength') == software_metal_max_buffer
		assert objc_responds(device, c'newLibraryWithData:error:') && !objc_responds(device, c'newRenderPipelineStateWithDescriptor:error:')
		assert sm_test_buffer(device, 0, 0) == 0 && sm_test_buffer(device, software_metal_max_buffer + 1, 0) == 0 && sm_test_buffer(device, 16, 16) == 0
		mut bytes := [64]u8{}
		for i in 0 .. 64 { bytes[i] = u8(i ^ 0xa5) }
		a := unsafe { SMBytes(voidptr(C.ios_objc_msgsend))(device, c'newBufferWithBytes:length:options:', u64(&bytes[0]), 64, 0) }
		b := sm_test_buffer(device, 64, 0); c := sm_test_buffer(device, 64, 0)
		queue := sm_send(device, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer')
		assert sm_send(a, c'length') == 64 && sm_send(a, c'device') == device && sm_send(queue, c'device') == device && sm_send(command, c'device') == device && sm_send(command, c'commandQueue') == queue
		assert sm_send(command, c'status') == 0
		encoder := sm_send(command, c'blitCommandEncoder')
		sm_test_copy(encoder, a, 8, b, 16, 32)
		sm_test_copy(encoder, b, 16, c, 0, 32) // Must observe preceding deferred command.
		sm_test_copy(encoder, c, 64, b, 64, 0)
		assert unsafe { *(&u8(sm_send(b, c'contents') + 16)) } == 0
		// Encoding retains resources; the device/queue outlive caller references.
		objc_release(a); objc_release(queue); objc_release(device)
		sm_call(encoder, c'endEncoding')
		second := sm_send(command, c'blitCommandEncoder'); sm_test_copy(second, c, 0, b, 0, 16); sm_call(second, c'endEncoding')
		sm_call(command, c'commit'); sm_call(command, c'waitUntilCompleted')
		assert sm_send(command, c'status') == 4 && sm_send(command, c'error') == 0
		for i in 0 .. 64 {
			actual := unsafe { *(&u8(sm_send(b, c'contents') + u64(i))) }
			expected := if i < 16 { bytes[i + 8] } else if i < 48 { bytes[i - 8] } else { u8(0) }
			assert actual == expected
		}
		for i in 0 .. 32 { assert unsafe { *(&u8(sm_send(c, c'contents') + u64(i))) } == bytes[i + 8] }
		objc_release(b); objc_release(c); objc_pool_pop(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		for mode in 0 .. 10 { sm_test_reject(mode) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn sm_test_worker() }; workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL: Objective-C buffer/queue/command/blit ABI, deferred ordered copies, bounds, retained resources, completion, 10 rejected states, eight workers and two drained runtimes PASS')
}
