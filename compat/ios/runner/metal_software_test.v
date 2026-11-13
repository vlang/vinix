// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import math
import os
import strings

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
	return sm_library_code_fixture(names, [u8(0x42), 0x43, 0xc0, 0xde, 0, 0, 0, 0], wrapped, aliased, false)
}
fn sm_library_code_fixture(names []string, raw []u8, wrapped bool, aliased bool, kernels bool) []u8 {
	mut code := []u8{}; code.flags |= .noslices
	if wrapped { for value in [u64(0x0b17c0de), 0, 20, u64(raw.len), 0xffffffff]! { sm_library_append(mut code, 4, value) } }
	code << raw
	digest := sha256.sum(code)
	defer { unsafe { code.free(); digest.free() } }
	mut data := []u8{len: 88}; data.flags |= .noslices
	sm_library_number(mut data, 0, 4, 0x424c544d); sm_library_number(mut data, 6, 2, 2)
	sm_library_append(mut data, 4, u64(names.len))
	for i, name in names {
		start := data.len; sm_library_append(mut data, 4, 0)
		mut text := name.bytes(); text << u8(0); sm_library_tag(mut data, 'NAME', text); unsafe { text.free() }
		sm_library_tag(mut data, 'TYPE', [if kernels { u8(2) } else { u8(i % 3) }])
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
fn test_software_metal_float_texture_storage() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
		for index, format in [u64(25), 65, 115, 55, 105, 125]! {
			pixel := [u64(2), 4, 8, 4, 8, 16]![index]; assert sm_test_linear_alignment(d, format) == 256
			desc := sm_test_descriptor(format, 5, 4, 0); sm_test_set(desc, c'setUsage:', 17)
			t := sm_test_texture(d, desc); assert t != 0 && sm_send(t, c'pixelFormat') == format
			view := sm_test_view(t, format); assert view != 0
			for bad in [u64(10), 30, 70, 80, if format == 25 { u64(55) } else { u64(25) }]! { assert sm_test_view(t, bad) == 0 }
			mut input := [128]u8{}; mut output := [256]u8{}
			unit := if index < 3 { 2 } else { 4 }
			for i in 0 .. int(7 * pixel) {
				word := if unit == 2 { [u64(0), 0x8000, 0x3c00, 0xbc00, 0x7c00, 0xfc00, 0x7e01, 1]![(i / unit) % 8] } else { [u64(0), 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7fc00001, 1]![(i / unit) % 8] }
				input[i] = u8(word >> u32((i % unit) * 8))
			}
			region := SoftwareMetalRegion{x: 1, y: 1, width: 3, height: 2, depth: 1}
			sm_test_read(t, region, 0, u64(unsafe { &output[0] }), 3 * pixel); for i in 0 .. int(6 * pixel) { assert output[i] == 0 }
			sm_test_transfer_slice(view, region, 0, 0, u64(unsafe { &input[0] }), 4 * pixel, 0, true); sm_test_read(t, region, 0, u64(unsafe { &output[0] }), 3 * pixel)
			for y in 0 .. 2 { for x in 0 .. int(3 * pixel) { assert output[y * int(3 * pixel) + x] == input[y * int(4 * pixel) + x] } }
			b := sm_test_buffer(d, 2048, 0); target := sm_test_buffer_texture_view(b, desc, 256, 256); assert target != 0
			source := sm_test_buffer(d, 256, 0); readback := sm_test_buffer(d, 256, 0)
			C.memcpy(unsafe { voidptr(sm_send(source, c'contents') + pixel) }, unsafe { &input[0] }, usize(7 * pixel)); C.memset(unsafe { voidptr(sm_send(readback, c'contents')) }, 0xcc, 256)
			cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder'); size := SoftwareMetalSize{width: 3, height: 2, depth: 1}; origin := SoftwareMetalOrigin{x: 1, y: 1}
			sm_test_buffer_texture(enc, source, pixel, 4 * pixel, 0, size, t, 0, 0, origin, true)
			sm_test_texture_copy(enc, t, 0, 0, origin, size, target, 0, 0, origin)
			sm_test_buffer_texture(enc, readback, pixel, 5 * pixel, 0, size, target, 0, 0, origin, false)
			input[0] ^= 0x5a; unsafe { *(&u8(sm_send(source, c'contents') + pixel)) = input[0] }
			objc_release(t); objc_release(view); objc_release(b); objc_release(source); sm_call(enc, c'endEncoding'); sm_call(cmd, c'commit')
			base := sm_send(readback, c'contents')
			for i in 0 .. 256 { expected := if i >= int(pixel) && i < int(4 * pixel) { input[i - int(pixel)] } else if i >= int(6 * pixel) && i < int(9 * pixel) { input[i - int(2 * pixel)] } else { u8(0xcc) }; assert unsafe { *(&u8(base + u64(i))) } == expected }
			objc_release(target); objc_release(readback)
		}
		objc_release(q); objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-FLOAT-TEXTURES: six half/float formats, 2/4/8/16-byte pixels, raw signed-zero/finite/infinity/NaN/subnormal bits, zero storage, CPU pitches, same-format views, incompatible views rejected, aligned buffer storage, both deferred buffer transfers and texture blits, padding guards, live writes and two drained runtimes PASS')
}
fn test_software_metal_rgba8_textures() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
		for format in [u64(70), 71]! {
			assert sm_test_linear_alignment(d, format) == 256
			desc := sm_test_descriptor(format, 2, 2, 0); sm_test_set(desc, c'setUsage:', 17)
			t := sm_test_texture(d, desc); assert t != 0 && sm_send(t, c'pixelFormat') == format
			view := sm_test_view(t, if format == 70 { u64(71) } else { u64(70) }); assert view != 0
			nested := sm_test_view_ranges(view, format, 2, SoftwareMetalRange{length: 1}, SoftwareMetalRange{length: 1}); assert nested != 0
			for bad in [u64(0), 10, 30, 80, 81, 112]! { assert sm_test_view(t, bad) == 0 }
			mut input := [u8(3), 17, 91, 255, 9, 29, 83, 127, 11, 41, 73, 63, 19, 53, 67, 31]!
			mut output := [32]u8{}; region := SoftwareMetalRegion{width: 2, height: 2, depth: 1}
			sm_test_read(t, region, 0, u64(unsafe { &output[0] }), 8); for i in 0 .. 16 { assert output[i] == 0 }
			sm_test_put(view, region, 0, u64(unsafe { &input[0] }), 8); sm_test_transfer_slice(nested, region, 0, 0, u64(unsafe { &output[0] }), 8, 0, false)
			for i in 0 .. 16 { assert output[i] == input[i] } // Distinct R/B values detect accidental swizzling.
			b := sm_test_buffer(d, 1024, 0); target := sm_test_buffer_texture_view(b, desc, 256, 256); assert target != 0
			readback := sm_test_buffer(d, 64, 0); C.memset(unsafe { voidptr(sm_send(readback, c'contents')) }, 0xcc, 64)
			cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder'); size := SoftwareMetalSize{width: 2, height: 2, depth: 1}
			sm_test_texture_copy(enc, nested, 0, 0, SoftwareMetalOrigin{}, size, target, 0, 0, SoftwareMetalOrigin{})
			sm_test_buffer_texture(enc, readback, 4, 16, 0, size, target, 0, 0, SoftwareMetalOrigin{}, false)
			// Exact format matching still applies to blits across linear/sRGB handles.
			child := C.fork(); assert child >= 0
			if child == 0 { C.close(1); C.close(2); sm_test_texture_copy(enc, t, 0, 0, SoftwareMetalOrigin{}, size, view, 0, 0, SoftwareMetalOrigin{}); C._exit(0) }
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			input[0] = 0x5d; sm_test_transfer_slice(view, region, 0, 0, u64(unsafe { &input[0] }), 8, 0, true)
			objc_release(t); objc_release(view); objc_release(nested); objc_release(b); sm_call(enc, c'endEncoding'); sm_call(cmd, c'commit')
			base := sm_send(readback, c'contents')
			for i in 0 .. 64 { expected := if i >= 4 && i < 12 { input[i - 4] } else if i >= 20 && i < 28 { input[i - 12] } else { u8(0xcc) }; assert unsafe { *(&u8(base + u64(i))) } == expected }
			objc_release(target); objc_release(readback)
			// No PixelFormatView usage: same-format view succeeds, pair conversion rejects.
			restricted := sm_test_texture(d, sm_test_descriptor(format, 1, 1, 0)); same := sm_test_view(restricted, format); assert same != 0 && sm_test_view(restricted, if format == 70 { u64(71) } else { u64(70) }) == 0; objc_release(same); objc_release(restricted)
		}
		objc_release(q); objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-RGBA8: linear/sRGB storage, zero initialization, raw channel order, short/full CPU transfers, nested compatible views, alignment/buffer storage, deferred live-byte texture/readback blits, client padding, format/usage rejection and two drained runtimes PASS')
}
type SMNoCopy = fn (u64, &char, u64, u64, u64, u64) u64
struct SMDeallocatorProbe {
	owner u64
	device u64
	pointer u64
	length u64
	expected u8
mut:
	copies int
	drops int
	calls int
}
fn sm_deallocator_copy(destination u64, source u64) { mut p := unsafe { &SMDeallocatorProbe(read64(source + 32)) }; objc_retain(p.owner); p.copies++ }
fn sm_deallocator_drop(block u64) { mut p := unsafe { &SMDeallocatorProbe(read64(block + 32)) }; assert p.calls == 1; objc_release(p.owner); p.drops++ }
fn sm_deallocator_invoke(block u64, pointer u64, length u64) {
	mut p := unsafe { &SMDeallocatorProbe(read64(block + 32)) }
	assert p.calls == 0 && p.copies == 1 && p.drops == 0 && pointer == p.pointer && length == p.length
	assert sm_send(p.device, c'maxBufferLength') == software_metal_max_buffer && obj_header(p.owner).refs > 0
	assert unsafe { *(&u8(pointer)) } == p.expected
	p.calls++; assert C.munmap(unsafe { voidptr(pointer) }, usize(length)) == 0
}
fn test_software_metal_buffer_deallocators() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue'); page := u64(C.getpagesize())
		for mode in 0 .. 4 {
			memory := C.mmap(unsafe { nil }, usize(page), 3, 0x1002, -1, 0); assert u64(memory) != ~u64(0); C.memset(memory, 0x4b, usize(page))
			mut p := SMDeallocatorProbe{owner: objc_allocate(ios_runtime.names['NSObject']), device: d, pointer: u64(memory), length: page, expected: if mode == 3 { u8(0x44) } else { u8(0x4b) }}
			descriptor := [u64(0), u64(sizeof(SMCompletionBlock)), u64(unsafe { voidptr(sm_deallocator_copy) }), u64(unsafe { voidptr(sm_deallocator_drop) })]!
			block := SMCompletionBlock{isa: block_isa(0), flags: u32(1) << 25, invoke: u64(unsafe { voidptr(sm_deallocator_invoke) }), descriptor: u64(unsafe { &descriptor[0] }), capture: u64(unsafe { &p })}
			// Invalid layout must not copy the block or take ownership of memory.
			assert sm_test_no_copy(d, u64(memory), page - 1, 0, u64(unsafe { &block })) == 0 && p.copies == 0 && p.calls == 0
			bad_block := SMCompletionBlock{...block, invoke: 0}; assert sm_test_no_copy(d, u64(memory), page, 0, u64(unsafe { &bad_block })) == 0
			pool := objc_pool_push(); b := sm_test_no_copy(d, u64(memory), page, 0, u64(unsafe { &block })); assert b != 0 && p.copies == 1; objc_release(p.owner)
			if mode == 0 { objc_release(b); assert p.calls == 1 }
			else if mode == 1 {
				t := sm_test_buffer_texture_view(b, sm_test_descriptor(80, 2, 2, 0), 0, 256); view := sm_test_view(t, 80); objc_release(b); objc_release(t); assert p.calls == 0; objc_release(view); assert p.calls == 1
			} else {
				cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder'); sm_test_fill(enc, b, SoftwareMetalRange{length: 1}, 0x44); objc_release(b); sm_call(enc, c'endEncoding')
				if mode == 3 { sm_call(cmd, c'commit') }; assert p.calls == 0
			}
			objc_pool_pop(pool); assert p.calls == 1 && p.drops == 1 && ios_runtime.block_refs.len == 0
			assert ios_runtime.live == 2
		}
		objc_release(q); objc_release(d); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-DEALLOCATOR: copied block/capture ABI, exact pointer and length, invalid inputs preserve ownership, callback unmaps pages, reentrant device query, direct/view/abandoned/committed final owners, exactly once disposal and two drained runtimes PASS')
}
fn sm_test_no_copy(d u64, bytes u64, length u64, options u64, deallocator u64) u64 { return unsafe { SMNoCopy(voidptr(C.ios_objc_msgsend))(d, c'newBufferWithBytesNoCopy:length:options:deallocator:', bytes, length, options, deallocator) } }
fn test_software_metal_no_copy_buffers() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		page := u64(C.getpagesize()); memory := C.mmap(unsafe { nil }, usize(2 * page), 3, 0x1002, -1, 0); assert u64(memory) != ~u64(0)
		base := u64(memory); C.memset(memory, 0x11, usize(2 * page))
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
		b := sm_test_no_copy(d, base, 2 * page, 0, 0); alias := sm_test_no_copy(d, base, 2 * page, 0, 0)
		assert b != 0 && alias != b && sm_send(b, c'contents') == base && sm_send(b, c'length') == 2 * page && sm_send(b, c'device') == d
		for mode in 0 .. 8 { assert sm_test_no_copy(d, if mode == 0 { u64(0) } else if mode == 1 { base + 1 } else if mode == 2 { ~u64(0) - page + 1 } else { base }, if mode == 3 { u64(0) } else if mode == 4 { page - 1 } else if mode == 5 { software_metal_max_buffer + page } else { page }, if mode == 6 { u64(1) } else { 0 }, if mode == 7 { d } else { 0 }) == 0 }
		owned := sm_test_buffer(d, 64, 0); texture := sm_test_buffer_texture_view(b, sm_test_descriptor(80, 2, 2, 0), 256, 256); assert texture != 0
		mut pixel := [u8(7), 13, 29, 53]!
		sm_test_put(texture, SoftwareMetalRegion{width: 1, height: 1, depth: 1}, 0, u64(unsafe { &pixel[0] }), 0)
		for i in 0 .. 4 { assert unsafe { *(&u8(base + 256 + u64(i))) } == pixel[i] }
		child := C.fork(); assert child >= 0
		if child == 0 { C.close(1); C.close(2); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder'); sm_test_copy(enc, b, 0, alias, 1, 8); C._exit(0) }
		mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder')
		sm_test_copy(enc, b, 0, owned, 0, 16); sm_test_fill(enc, alias, SoftwareMetalRange{location: 4, length: 4}, 0x44)
		sm_test_copy(enc, owned, 0, b, page, 16) // Disjoint pages of aliased storage.
		sm_test_copy(enc, b, 0, alias, page + 32, 16)
		sm_test_buffer_texture(enc, alias, page + 64, 8, 0, SoftwareMetalSize{width: 2, height: 2, depth: 1}, texture, 0, 0, SoftwareMetalOrigin{}, true)
		sm_test_buffer_texture(enc, alias, page + 96, 8, 0, SoftwareMetalSize{width: 2, height: 2, depth: 1}, texture, 0, 0, SoftwareMetalOrigin{}, false)
		unsafe { *(&u8(base)) = 0x22 }
		objc_release(b); objc_release(alias); objc_release(texture); objc_release(q); objc_release(d)
		sm_call(enc, c'endEncoding'); sm_call(cmd, c'commit'); assert unsafe { *(&u8(sm_send(owned, c'contents'))) } == 0x22
		assert unsafe { *(&u8(base + page)) } == 0x22 && unsafe { *(&u8(base + page + 32)) } == 0x22
		for i in 4 .. 8 { assert unsafe { *(&u8(base + u64(i))) } == 0x44 }
		for i in 0 .. 16 { assert unsafe { *(&u8(base + page + 96 + u64(i))) } == 0x11 }
		objc_release(owned); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
		// The runtime must neither free nor unmap caller pages on buffer disposal.
		unsafe { *(&u8(base)) = 0x7e }; assert unsafe { *(&u8(base)) } == 0x7e; assert C.munmap(memory, usize(2 * page)) == 0
	}
	println('IOS-SOFTWARE-METAL-NO-COPY: borrowed page-aligned memory, exact contents/length ABI, eight rejected inputs, alias overlap rejection, ordered copies/fills and buffer-texture transfers, live CPU bytes, retained owners, caller pages survive disposal and two drained runtimes PASS')
}
fn sm_texture_descriptor_profile(api SMSamplerAPI) {
	d := unsafe { SMDescriptor(api.send)(api.cls, api.sel(c'texture2DDescriptorWithPixelFormat:width:height:mipmapped:'), 80, 7, 3, 0) }; assert d != 0
	assert api.get(d, c'width') == 7 && api.get(d, c'height') == 3 && api.get(d, c'pixelFormat') == 80
	for zone in [false, true]! {
		api.set(d, c'setWidth:', 11); api.set(d, c'setHeight:', 5); api.set(d, c'setPixelFormat:', 81); api.set(d, c'setUsage:', 17); api.set(d, c'setStorageMode:', 0)
		copy := if zone { unsafe { SMTexture(api.send)(d, api.sel(c'copyWithZone:'), 0) } } else { api.get(d, c'copy') }
		assert copy != 0 && copy != d
		api.set(d, c'setWidth:', 2); api.set(d, c'setHeight:', 1); api.set(d, c'setPixelFormat:', 10); api.set(d, c'setUsage:', 1); api.set(d, c'setStorageMode:', 2)
		assert api.get(copy, c'width') == 11 && api.get(copy, c'height') == 5 && api.get(copy, c'pixelFormat') == 81 && api.get(copy, c'usage') == 17 && api.get(copy, c'storageMode') == 0
		api.set(copy, c'setWidth:', 13); assert api.get(d, c'width') == 2; api.get(copy, c'release')
	}
}
fn test_software_metal_texture_descriptor_copies() {
	$if !ios_metal_software ? { return }
	$if macos {
		metal := C.dlopen(c'/System/Library/Frameworks/Metal.framework/Metal', 2); objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); assert metal != unsafe { nil } && objc != unsafe { nil }
		get_class := C.dlsym(objc, c'objc_getClass'); send := C.dlsym(objc, c'objc_msgSend'); sel := C.dlsym(objc, c'sel_registerName')
		assert get_class != unsafe { nil } && send != unsafe { nil } && sel != unsafe { nil }
		cls := unsafe { SMSamplerName(get_class)(c'MTLTextureDescriptor') }; assert cls != 0
		api := SMSamplerAPI{send, unsafe { SMSamplerName(sel) }, cls}
		pool_cls := unsafe { SMSamplerName(get_class)(c'NSAutoreleasePool') }; pool := api.get(pool_cls, c'new'); sm_texture_descriptor_profile(api); api.get(pool, c'drain')
		assert C.dlclose(objc) == 0 && C.dlclose(metal) == 0
	}
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		sm_texture_descriptor_profile(SMSamplerAPI{unsafe { voidptr(C.ios_objc_msgsend) }, objc_selector, ios_runtime.names['MTLTextureDescriptor']})
		for format in [u64(10), 30, 80, 81]! {
			inner := objc_pool_push(); original := sm_test_descriptor(format, 3, 2, 0); copy := sm_send(original, c'copy'); objc_pool_pop(inner)
			assert sm_send(copy, c'width') == 3 && sm_send(copy, c'pixelFormat') == format
			t := sm_test_texture(d, copy); assert t != 0; sm_test_set(copy, c'setWidth:', 9); assert sm_send(t, c'width') == 3
			next := sm_send(copy, c'copy'); objc_release(copy); assert sm_send(next, c'width') == 9; objc_release(next); objc_release(t)
		}
		objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-DESCRIPTOR-COPY: native property/copy reference, five NSUInteger getters, copy and copyWithZone, bidirectional independence, four-format allocation after factory pool drain, immutable texture snapshots and two drained runtimes PASS')
}
type SMBufferTexture = fn (u64, &char, u64, u64, u64) u64
fn sm_test_linear_alignment(device u64, format u64) u64 { return unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(device, c'minimumLinearTextureAlignmentForPixelFormat:', format) } }
fn test_software_metal_linear_alignment() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); d := metal_create_system_default_device()
		for format in [u64(10), 30, 80, 81]! {
			alignment := sm_test_linear_alignment(d, format); assert alignment == 256 && alignment & (alignment - 1) == 0
			pixel := sm_pixel_size(format)
			for width in [u64(1), 63, 64, 65, 255, 256, 257, 16384]! {
				pool := objc_pool_push(); row := (width * pixel + alignment - 1) & ~(alignment - 1)
				length := alignment + row + width * pixel; b := sm_test_buffer(d, length, 0); desc := sm_test_descriptor(format, width, 2, 0)
				t := sm_test_buffer_texture_view(b, desc, alignment, row); assert t != 0 && sm_send(t, c'bufferOffset') == alignment && sm_send(t, c'bufferBytesPerRow') == row
				short := sm_test_buffer(d, length - 1, 0); assert sm_test_buffer_texture_view(short, desc, alignment, row) == 0; objc_release(short)
				assert sm_test_buffer_texture_view(b, desc, alignment - 1, row) == 0 && sm_test_buffer_texture_view(b, desc, alignment, row - 1) == 0
				mut input := [u8(11), 29, 53, 97]!; mut output := [4]u8{}
				last := SoftwareMetalRegion{x: width - 1, y: 1, width: 1, height: 1, depth: 1}
				sm_test_put(t, last, 0, u64(unsafe { &input[0] }), 0); sm_test_read(t, last, 0, u64(unsafe { &output[0] }), 0)
				for i in 0 .. int(pixel) { assert input[i] == output[i] }
				base := sm_send(b, c'contents'); for i in 0 .. int(pixel) { assert unsafe { *(&u8(base + length - pixel + u64(i))) } == input[i] }
				objc_release(t); objc_release(b); objc_pool_pop(pool)
			}
		}
		for format in [u64(0), 1, 112, 252, ~u64(0)]! {
			child := C.fork(); assert child >= 0
			if child == 0 { C.close(1); C.close(2); sm_test_linear_alignment(d, format); C._exit(0) }
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		objc_release(d); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-LINEAR-ALIGNMENT: NSUInteger query ABI, four formats, eight boundary widths each, calculated pitches, exact-fit backing spans, last-pixel CPU access, short/misaligned allocation rejection, five unsupported formats and two drained runtimes PASS')
}
fn sm_test_buffer_texture_view(buffer u64, descriptor u64, offset u64, row u64) u64 { return unsafe { SMBufferTexture(voidptr(C.ios_objc_msgsend))(buffer, c'newTextureWithDescriptor:offset:bytesPerRow:', descriptor, offset, row) } }
fn test_software_metal_buffer_backed_textures() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue')
		for format in [u64(10), 30, 80, 81]! {
			b := sm_test_buffer(d, 4096, 0); base := sm_send(b, c'contents'); C.memset(unsafe { voidptr(base) }, 0xcc, 4096)
			desc := sm_test_descriptor(format, 3, 2, 0); sm_test_set(desc, c'setUsage:', 17)
			t := sm_test_buffer_texture_view(b, desc, 256, 256); assert t != 0
			assert sm_send(t, c'buffer') == b && sm_send(t, c'bufferOffset') == 256 && sm_send(t, c'bufferBytesPerRow') == 256 && sm_send(t, c'parentTexture') == 0 && sm_send(t, c'iosurface') == 0
			view := sm_test_view(t, format); assert sm_send(view, c'buffer') == b && sm_send(view, c'bufferOffset') == 256 && sm_send(view, c'bufferBytesPerRow') == 256
			pixel := sm_pixel_size(format); mut input := [32]u8{}; mut output := [32]u8{}; for i in 0 .. 32 { input[i] = u8(i + 1) }
			region := SoftwareMetalRegion{width: 3, height: 2, depth: 1}; sm_test_put(view, region, 0, u64(unsafe { &input[0] }), 3 * pixel)
			for y in 0 .. 2 { for x in 0 .. int(3 * pixel) { assert unsafe { *(&u8(base + 256 + u64(y * 256 + x))) } == input[y * int(3 * pixel) + x] }; assert unsafe { *(&u8(base + 256 + u64(y * 256) + 3 * pixel)) } == 0xcc }
			for mode in 0 .. 12 {
				bad := sm_test_descriptor(format, 3, 2, 0)
				match mode { 6 { sm_test_set(bad, c'setWidth:', 0) } 7 { sm_test_set(bad, c'setHeight:', 16385) } 8 { sm_test_set(bad, c'setStorageMode:', 2) } 9 { sm_test_set(bad, c'setPixelFormat:', 99) } 10 { sm_test_set(bad, c'setUsage:', 32) } else {} }
				assert sm_test_buffer_texture_view(b, if mode == 11 { d } else { bad }, if mode == 0 { 1 } else if mode == 1 { ~u64(0) - 255 } else if mode == 2 { 4096 } else { 256 }, if mode == 3 { 0 } else if mode == 4 { 257 } else if mode == 5 { ~u64(0) - 255 } else { 256 }) == 0
			}
			other := sm_test_buffer_texture_view(b, desc, 512, 256)
			for mode in 0 .. 3 {
				child := C.fork(); assert child >= 0
				if child == 0 { C.close(1); C.close(2); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder'); if mode == 0 { sm_test_texture_copy(enc, t, 0, 0, SoftwareMetalOrigin{}, SoftwareMetalSize{width: 3, height: 2, depth: 1}, other, 0, 0, SoftwareMetalOrigin{}) } else { sm_test_buffer_texture(enc, b, 256, 256, 0, SoftwareMetalSize{width: 3, height: 2, depth: 1}, t, 0, 0, SoftwareMetalOrigin{}, mode == 1) }; C._exit(0) }
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			}; objc_release(other)
			separate := sm_test_buffer_texture_view(b, desc, 1024, 256); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder')
			sm_test_fill(enc, b, SoftwareMetalRange{location: 256, length: 3 * pixel}, 0x6b)
			sm_test_texture_copy(enc, t, 0, 0, SoftwareMetalOrigin{}, SoftwareMetalSize{width: 3, height: 2, depth: 1}, separate, 0, 0, SoftwareMetalOrigin{})
			objc_release(b); objc_release(t); sm_call(enc, c'endEncoding'); sm_call(cmd, c'commit')
			sm_test_read(separate, region, 0, u64(unsafe { &output[0] }), 3 * pixel); for i in 0 .. int(3 * pixel) { assert output[i] == 0x6b && output[int(3 * pixel) + i] == input[int(3 * pixel) + i] }
			sm_test_read(view, region, 0, u64(unsafe { &output[0] }), 3 * pixel); assert output[0] == 0x6b
			objc_release(view); objc_release(separate)
		}
		objc_release(q); objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-BUFFER-STORAGE: four formats, 256-byte layouts, CPU aliases/padding, nested view buffer metadata, twelve invalid allocations, three overlapping alias blits rejected, deferred fill/disjoint texture copy, retained storage and two drained runtimes PASS')
}
fn sm_test_view(texture u64, format u64) u64 { return unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(texture, c'newTextureViewWithPixelFormat:', format) } }
type SMViewRanges = fn (u64, &char, u64, u64, SoftwareMetalRange, SoftwareMetalRange) u64
fn sm_test_view_ranges(texture u64, format u64, kind u64, levels SoftwareMetalRange, slices SoftwareMetalRange) u64 { return unsafe { SMViewRanges(voidptr(C.ios_objc_msgsend))(texture, c'newTextureViewWithPixelFormat:textureType:levels:slices:', format, kind, levels, slices) } }
fn test_software_metal_texture_view_ranges() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		for format in [u64(10), 30, 80, 81]! {
			descriptor := sm_test_descriptor(format, 2, 1, 0); sm_test_set(descriptor, c'setUsage:', 17)
			root := sm_test_texture(d, descriptor); full := SoftwareMetalRange{length: 1}
			view := sm_test_view_ranges(root, format, 2, full, full); assert view != 0 && sm_send(view, c'parentTexture') == root
			view_format := if format == 80 { u64(81) } else if format == 81 { u64(80) } else { format }
			nested := sm_test_view_ranges(view, view_format, 2, full, full); assert nested != 0 && sm_send(nested, c'parentTexture') == view && sm_send(nested, c'pixelFormat') == view_format
			assert sm_send(nested, c'parentRelativeLevel') == 0 && sm_send(nested, c'parentRelativeSlice') == 0 && sm_send(nested, c'device') == d
			for kind in [u64(0), 1, 3, 4, 5, 6, 7, 8, 9, ~u64(0)]! { assert sm_test_view_ranges(root, format, kind, full, full) == 0 }
			for bad in [SoftwareMetalRange{}, SoftwareMetalRange{length: 2}, SoftwareMetalRange{location: 1, length: 1}, SoftwareMetalRange{location: ~u64(0), length: 2}, SoftwareMetalRange{length: ~u64(0)}]! {
				assert sm_test_view_ranges(root, format, 2, bad, full) == 0 && sm_test_view_ranges(root, format, 2, full, bad) == 0
			}
			assert sm_test_view_ranges(root, 99, 2, full, full) == 0
			mut input := [u8(13), 29, 37, 41, 53, 61, 73, 89]!; mut output := [8]u8{}
			pixel := sm_pixel_size(format); region := SoftwareMetalRegion{width: 2, height: 1, depth: 1}
			sm_test_put(root, region, 0, u64(unsafe { &input[0] }), 2 * pixel); objc_release(root); objc_release(view)
			sm_test_read(nested, region, 0, u64(unsafe { &output[0] }), 2 * pixel)
			for i in 0 .. int(2 * pixel) { assert output[i] == input[i] }; objc_release(nested)
		}
		objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-VIEW-RANGES: two inline NSRange ABI arguments, four formats, nested shared bytes and parent lifetimes, BGRA reinterpretation, ten unsupported types, empty/out-of-bounds/overflow ranges on both axes, bad formats and two drained runtimes PASS')
}
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
			view := sm_test_view(root, view_format); nested := sm_test_view_ranges(view, format, 2, SoftwareMetalRange{length: 1}, SoftwareMetalRange{length: 1}); assert view != 0 && nested != 0 && view != root && nested != view
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
				sm_test_transfer_slice(texture, SoftwareMetalRegion{0, 0, 0, width, height, 1}, 0, 0, u64(unsafe { &bytes[0] }), 32, 0, true)
				mut readback := [256]u8{}; sm_test_transfer_slice(alias, SoftwareMetalRegion{0, 0, 0, width, height, 1}, 0, 0, u64(unsafe { &readback[0] }), 32, 0, false)
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
type SMPutSlice = fn (u64, &char, SoftwareMetalRegion, u64, u64, u64, u64, u64)
type SMReadSlice = fn (u64, &char, u64, u64, u64, SoftwareMetalRegion, u64, u64)
fn sm_test_transfer_slice(texture u64, region SoftwareMetalRegion, level u64, slice u64, bytes u64, row u64, image u64, write bool) {
	if write { unsafe { SMPutSlice(voidptr(C.ios_objc_msgsend))(texture, c'replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:', region, level, slice, bytes, row, image) } }
	else { unsafe { SMReadSlice(voidptr(C.ios_objc_msgsend))(texture, c'getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:', bytes, row, image, region, level, slice) } }
}
fn test_software_metal_cpu_slice_transfers() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		for format in [u64(10), 30, 80, 81]! {
			root := sm_test_texture(d, sm_test_descriptor(format, 5, 4, 0)); view := sm_test_view(root, format); objc_release(root)
			pixel := sm_pixel_size(format); region := SoftwareMetalRegion{x: 1, y: 1, width: 3, height: 2, depth: 1}
			mut input := [128]u8{}; mut output := [128]u8{}; for i in 0 .. 128 { input[i] = u8(i + 1); output[i] = 0xcc }
			for write in [false, true]! {
				if write { sm_test_transfer_slice(view, region, 0, 0, u64(unsafe { &input[4] }), 4 * pixel, 0, true); sm_test_read(view, region, 0, u64(unsafe { &output[4] }), 5 * pixel) }
				else { sm_test_put(view, region, 0, u64(unsafe { &input[4] }), 4 * pixel); sm_test_transfer_slice(view, region, 0, 0, u64(unsafe { &output[4] }), 5 * pixel, 0, false) }
				for i in 0 .. 128 {
					if i >= 4 && i < int(4 + 3 * pixel) { assert output[i] == input[i] }
					else if i >= int(4 + 5 * pixel) && i < int(4 + 8 * pixel) { assert output[i] == input[i - int(pixel)] }
					else { assert output[i] == 0xcc }
				}
				for mode in 0 .. 9 {
					child := C.fork(); assert child >= 0
					if child == 0 {
						C.close(1); C.close(2)
						r := match mode { 5 { SoftwareMetalRegion{...region, x: ~u64(0)} } 6 { SoftwareMetalRegion{...region, width: 0} } 8 { SoftwareMetalRegion{...region, depth: 2} } else { region } }
						sm_test_transfer_slice(view, r, if mode == 2 { u64(1) } else { 0 }, if mode == 1 { ~u64(0) } else { 0 }, if mode == 3 { u64(0) } else { u64(unsafe { &input[0] }) }, if mode == 4 { ~u64(0) } else if mode == 7 { pixel } else { 4 * pixel }, if mode == 0 { ~u64(0) } else { 0 }, write); C._exit(0)
					}
					mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
				}
			}
			// Single-row zero pitch remains valid through both full selectors.
			one := SoftwareMetalRegion{width: 1, height: 1, depth: 1}; sm_test_transfer_slice(view, one, 0, 0, u64(unsafe { &input[0] }), 0, 0, true); sm_test_transfer_slice(view, one, 0, 0, u64(unsafe { &output[0] }), 0, 0, false)
			for i in 0 .. int(pixel) { assert output[i] == input[i] }; objc_release(view)
		}
		objc_release(d); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-CPU-SLICES: both full selector ABIs, four formats, short/full cross-checks, view lifetimes, subregions/padded client rows, zero-pitch single row, nine invalid modes in both directions and two drained runtimes PASS')
}
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
type SMComputeBuffer = fn (u64, &char, u64, u64, u64)
type SMComputeDispatch = fn (u64, &char, SoftwareMetalSize, SoftwareMetalSize)
type SMComputeOffset = fn (u64, &char, u64, u64)
type SMComputeBuffers = fn (u64, &char, u64, u64, SoftwareMetalRange)
fn sm_test_compute_buffer(encoder u64, buffer u64, offset u64, slot u64) { unsafe { SMComputeBuffer(voidptr(C.ios_objc_msgsend))(encoder, c'setBuffer:offset:atIndex:', buffer, offset, slot) } }
fn sm_test_compute_bytes(encoder u64, bytes u64, length u64, slot u64) { unsafe { SMComputeBuffer(voidptr(C.ios_objc_msgsend))(encoder, c'setBytes:length:atIndex:', bytes, length, slot) } }
fn sm_test_compute_offset(encoder u64, offset u64, slot u64) { unsafe { SMComputeOffset(voidptr(C.ios_objc_msgsend))(encoder, c'setBufferOffset:atIndex:', offset, slot) } }
fn sm_test_compute_buffers(encoder u64, buffers u64, offsets u64, range SoftwareMetalRange) { unsafe { SMComputeBuffers(voidptr(C.ios_objc_msgsend))(encoder, c'setBuffers:offsets:withRange:', buffers, offsets, range) } }
fn sm_test_compute_dispatch(encoder u64, selector &char, width u64) { unsafe { SMComputeDispatch(voidptr(C.ios_objc_msgsend))(encoder, selector, SoftwareMetalSize{width, 1, 1}, SoftwareMetalSize{1, 1, 1}) } }
fn sm_test_compute_pipeline(device u64, library u64, name string, output &u64) u64 {
	text := owned_string(name)
	function := unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(library, c'newFunctionWithName:', text) }
	objc_release(text)
	result := unsafe { SMLibrary(voidptr(C.ios_objc_msgsend))(device, c'newComputePipelineStateWithFunction:error:', function, output) }
	objc_release(function)
	return result
}
// Portable LLVM fixtures with classic AIR metadata. They exercise our explicit
// interpreter profile and are not compiler-produced/native Metal libraries.
fn sm_test_compute_library(label string) ![]u8 {
	base := os.getenv('VINIX_METAL_COMPUTE_CHECK_DIR')
	assert base.len > 0 && !os.abs_path(base).starts_with(os.getwd() + '/')
	out := base + if os.getenv('SWIFT_DETERMINISTIC_HASHING') == '1' { '/deterministic/' + label } else { '/normal/' + label }
	assert !os.exists(out); os.mkdir_all(out)!
	names := ['sum', 'float_sum', 'bad_flags', 'bad_access', 'bad_slot', 'bad_builtin', 'divide', 'empty', 'indexed_sum', 'max', 'float_max', 'int_float', 'float_int', 'negate', 'frozen', 'flagged_sum', 'frozen_sum', 'bits', 'bits_frozen', 'funnel', 'extrema', 'abs_keep', 'abs_frozen', 'saturating', 'saturating_shift', 'saturating_shift_frozen', 'bit_permutation', 'float_sign', 'rounding', 'square_root', 'floating_extrema', 'no_metadata']
	mut source := strings.new_builder(8192)
	defer { unsafe { source.free() } }
	source.write_string('target datalayout = "e-p:64:64"\n')
	source.write_string('declare i32 @llvm.ctpop.i32(i32)\ndeclare i32 @llvm.bitreverse.i32(i32)\ndeclare i32 @llvm.bswap.i32(i32)\ndeclare i32 @llvm.ctlz.i32(i32, i1 immarg)\ndeclare i32 @llvm.cttz.i32(i32, i1 immarg)\n')
	source.write_string('declare i32 @llvm.fshl.i32(i32, i32, i32)\ndeclare i32 @llvm.fshr.i32(i32, i32, i32)\n')
	for op in ['smin', 'smax', 'umin', 'umax'] { source.write_string('declare i32 @llvm.${op}.i32(i32, i32)\n') }
	source.write_string('declare i32 @llvm.abs.i32(i32, i1 immarg)\n')
	for op in ['sadd', 'uadd', 'ssub', 'usub'] { source.write_string('declare i32 @llvm.${op}.sat.i32(i32, i32)\n') }
	for op in ['sshl', 'ushl'] { source.write_string('declare i32 @llvm.${op}.sat.i32(i32, i32)\n') }
	for op in ['pext', 'pdep'] { source.write_string('declare i32 @llvm.${op}.i32(i32, i32)\n') }
	for typ, bits in {'half': 16, 'float': 32} {
		source.write_string('declare ${typ} @llvm.fabs.f${bits}(${typ})\ndeclare ${typ} @llvm.copysign.f${bits}(${typ}, ${typ})\n')
		source.write_string('declare ${typ} @llvm.sqrt.f${bits}(${typ})\n')
		for op in ['minimum', 'maximum'] { source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ}, ${typ})\n') }
		for op in ['floor', 'ceil', 'trunc', 'round', 'roundeven'] { source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ})\n') }
	}
	for name in names {
		if name == 'floating_extrema' {
			source.write_string('define void @floating_extrema(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %y = load float, ptr addrspace(2) %b, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hb = getelementptr i8, ptr addrspace(2) %b, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %hy = load half, ptr addrspace(2) %hb, align 2\n %f0 = call float @llvm.minimum.f32(float %x, float %y)\n %f1 = call float @llvm.maximum.f32(float %x, float %y)\n %h0 = call half @llvm.minimum.f16(half %hx, half %hy)\n %h1 = call half @llvm.maximum.f16(half %hx, half %hy)\n %v0 = bitcast float %f0 to i32\n %v1 = bitcast float %f1 to i32\n %i0 = bitcast half %h0 to i16\n %i1 = bitcast half %h1 to i16\n %v2 = zext i16 %i0 to i32\n %v3 = zext i16 %i1 to i32\n')
			for i in 0 .. 4 { source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n') }
			source.write_string('ret void }\n'); continue
		}
		if name == 'square_root' {
			source.write_string('define void @square_root(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %ax = call float @llvm.fabs.f32(float %x)\n %ahx = call half @llvm.fabs.f16(half %hx)\n %f0 = call float @llvm.sqrt.f32(float %x)\n %f1 = call float @llvm.sqrt.f32(float %ax)\n %h0 = call half @llvm.sqrt.f16(half %hx)\n %h1 = call half @llvm.sqrt.f16(half %ahx)\n %v0 = bitcast float %f0 to i32\n %v1 = bitcast float %f1 to i32\n %i0 = bitcast half %h0 to i16\n %i1 = bitcast half %h1 to i16\n %v2 = zext i16 %i0 to i32\n %v3 = zext i16 %i1 to i32\n')
			for i in 0 .. 4 { source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n') }
			source.write_string('ret void }\n'); continue
		}
		if name == 'rounding' {
			source.write_string('define void @rounding(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n')
			for i, op in ['floor', 'ceil', 'trunc', 'round', 'roundeven'] {
				source.write_string('%f${i} = call float @llvm.${op}.f32(float %x)\n %h${i} = call half @llvm.${op}.f16(half %hx)\n %v${i} = bitcast float %f${i} to i32\n %i${i} = bitcast half %h${i} to i16\n %v${i + 5} = zext i16 %i${i} to i32\n %d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n %d${i + 5} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 5}\n store i32 %v${i + 5}, ptr addrspace(1) %d${i + 5}, align 4\n')
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'float_sign' {
			source.write_string('define void @float_sign(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %y = load float, ptr addrspace(2) %b, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hb = getelementptr i8, ptr addrspace(2) %b, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %hy = load half, ptr addrspace(2) %hb, align 2\n %f0 = call float @llvm.fabs.f32(float %x)\n %f1 = call float @llvm.copysign.f32(float %x, float %y)\n %h0 = call half @llvm.fabs.f16(half %hx)\n %h1 = call half @llvm.copysign.f16(half %hx, half %hy)\n %v0 = bitcast float %f0 to i32\n %v1 = bitcast float %f1 to i32\n %i0 = bitcast half %h0 to i16\n %i1 = bitcast half %h1 to i16\n %v2 = zext i16 %i0 to i32\n %v3 = zext i16 %i1 to i32\n')
			for i in 0 .. 4 { source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n') }
			source.write_string('ret void }\n'); continue
		}
		if name == 'bit_permutation' {
			source.write_string('define void @bit_permutation(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %mask = load i32, ptr addrspace(2) %b, align 4\n %ex = call i32 @llvm.pext.i32(i32 %x, i32 %mask)\n %dep = call i32 @llvm.pdep.i32(i32 %x, i32 %mask)\n %expand = call i32 @llvm.pdep.i32(i32 %ex, i32 %mask)\n %pack = call i32 @llvm.pext.i32(i32 %dep, i32 %mask)\n')
			for i, value in ['ex', 'dep', 'expand', 'pack'] {
				source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %${value}, ptr addrspace(1) %d${i}, align 4\n')
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'empty' { source.write_string('define void @empty() { ret void }\n'); continue }
		if name in ['saturating_shift', 'saturating_shift_frozen'] {
			frozen := name == 'saturating_shift_frozen'
			choice := if frozen { '%sx = freeze i32 %s\n %ux = freeze i32 %u\n' } else { '' }
			signed := if frozen { '%sx' } else { '%s' }; unsigned := if frozen { '%ux' } else { '%u' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %amount = load i32, ptr addrspace(2) %b, align 4\n %s = call i32 @llvm.sshl.sat.i32(i32 %x, i32 %amount)\n %u = call i32 @llvm.ushl.sat.i32(i32 %x, i32 %amount)\n ${choice}store i32 ${signed}, ptr addrspace(1) %out, align 4\n %next = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 ${unsigned}, ptr addrspace(1) %next, align 4\n ret void }\n'); continue
		}
		if name == 'saturating' {
			source.write_string('define void @saturating(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n')
			for i, op in ['sadd', 'uadd', 'ssub', 'usub'] {
				source.write_string('%v${i} = call i32 @llvm.${op}.sat.i32(i32 %x, i32 %y)\n %d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n')
			}
			source.write_string('ret void }\n'); continue
		}
		if name in ['abs_keep', 'abs_frozen'] {
			flag := if name == 'abs_frozen' { 'true' } else { 'false' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %ax = call i32 @llvm.abs.i32(i32 %x, i1 ${flag})\n %ay = call i32 @llvm.abs.i32(i32 %y, i1 ${flag})\n %vx = freeze i32 %ax\n %vy = freeze i32 %ay\n store i32 %vx, ptr addrspace(1) %out, align 4\n %next = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %vy, ptr addrspace(1) %next, align 4\n ret void }\n'); continue
		}
		if name == 'extrema' {
			source.write_string('define void @extrema(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n')
			for i, op in ['smin', 'smax', 'umin', 'umax'] {
				source.write_string('%v${i} = call i32 @llvm.${op}.i32(i32 %x, i32 %y)\n %d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n')
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'funnel' {
			source.write_string('define void @funnel(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %sp = getelementptr i32, ptr addrspace(2) %a, i64 1\n %s = load i32, ptr addrspace(2) %sp, align 4\n %left = call i32 @llvm.fshl.i32(i32 %x, i32 %y, i32 %s)\n %right = call i32 @llvm.fshr.i32(i32 %x, i32 %y, i32 %s)\n store i32 %left, ptr addrspace(1) %out, align 4\n %next = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %right, ptr addrspace(1) %next, align 4\n ret void }\n'); continue
		}
		if name in ['bits', 'bits_frozen'] {
			flag := if name == 'bits_frozen' { 'true' } else { 'false' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %pop = call i32 @llvm.ctpop.i32(i32 %x)\n %rev = call i32 @llvm.bitreverse.i32(i32 %x)\n %swap = call i32 @llvm.bswap.i32(i32 %rev)\n %lead0 = call i32 @llvm.ctlz.i32(i32 %y, i1 ${flag})\n %trail0 = call i32 @llvm.cttz.i32(i32 %y, i1 ${flag})\n %lead = freeze i32 %lead0\n %trail = freeze i32 %trail0\n %sum = add i32 %pop, %lead\n %v = add i32 %sum, %trail\n store i32 %swap, ptr addrspace(1) %out, align 4\n %next = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %v, ptr addrspace(1) %next, align 4\n ret void }\n'); continue
		}
		if name in ['negate', 'frozen'] {
			work := if name == 'negate' { '%v = fneg float %x\n' } else { '%bad = fptosi float %x to i32\n %v = freeze i32 %bad\n' }
			typ := if name == 'negate' { 'float' } else { 'i32' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %y = load float, ptr addrspace(2) %b, align 4\n ${work}store ${typ} %v, ptr addrspace(1) %out, align 4\n ret void }\n'); continue
		}
		if name in ['int_float', 'float_int'] {
			first := if name == 'int_float' { 'i32' } else { 'float' }; last := if name == 'int_float' { 'float' } else { 'i32' }
			work := if name == 'int_float' { '%f = sitofp i32 %x to float\n %v = fadd float %f, %y\n' } else { '%f = fadd float %x, %y\n %v = fptosi float %f to i32\n' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${first}, ptr addrspace(2) %a, align 4\n %y = load float, ptr addrspace(2) %b, align 4\n ${work}store ${last} %v, ptr addrspace(1) %out, align 4\n ret void }\n'); continue
		}
		typ := if name in ['float_sum', 'float_max', 'bad_flags'] { 'float' } else { 'i32' }
		op := if name == 'float_sum' { 'fadd' } else if name == 'divide' { 'udiv' } else if name == 'bad_flags' { 'fadd nnan' } else if name in ['flagged_sum', 'frozen_sum'] { 'add nuw nsw' } else { 'add' }
		prior := if name == 'divide' { 'store i32 17, ptr addrspace(1) %out, align 4\n' } else { '' }
		indexed := name == 'indexed_sum'
		gep := if indexed { '%ai = getelementptr inbounds i32, ptr addrspace(2) %a, i64 2\n %bi = getelementptr inbounds i32, ptr addrspace(2) %b, i64 1\n %di = getelementptr inbounds i32, ptr addrspace(1) %out, i64 3\n' } else { '' }
		a := if indexed { '%ai' } else { '%a' }; b := if indexed { '%bi' } else { '%b' }; dst := if indexed { '%di' } else { '%out' }
		cmp := if name == 'max' { 'icmp sgt' } else { 'fcmp ogt' }
		compute := if name in ['max', 'float_max'] { '%c = ${cmp} ${typ} %x, %y\n %v = select i1 %c, ${typ} %x, ${typ} %y\n' } else if name == 'frozen_sum' { '%bad = ${op} i32 %x, %y\n %v = freeze i32 %bad\n' } else { '%v = ${op} ${typ} %x, %y\n' }
		source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) {\n ${gep}%x = load ${typ}, ptr addrspace(2) ${a}, align 4\n %y = load ${typ}, ptr addrspace(2) ${b}, align 4\n ${prior}${compute}store ${typ} %v, ptr addrspace(1) ${dst}, align 4\n ret void\n}\n')
	}
	source.write_string('!air.kernel = !{!0, !10, !20, !30, !40, !50, !60, !70, !80, !90, !100, !110, !120, !130, !140, !150, !160, !170, !180, !190, !200, !210, !220, !230, !240, !250, !260, !270, !280, !290, !300}\n')
	for i, name in names[..31] {
		n := i * 10
		source.write_string('!${n} = !{ptr @${name}, !${n + 1}, !${n + 2}}\n!${n + 1} = !{}\n')
		if name == 'empty' { source.write_string('!${n + 2} = !{}\n'); continue }
		source.write_string('!${n + 2} = !{!${n + 5}, !${n + 3}, !${n + 4}}\n')
		semantic := if name == 'bad_builtin' { 'air.thread_position_in_grid' } else { 'air.buffer' }
		source.write_string('!${n + 3} = !{i32 0, !"${semantic}", !"air.location_index", i32 0, i32 1, !"air.address_space", i32 2, !"air.read", !"air.arg_type_align_size", i32 4, !"air.buffer_size", i32 4}\n')
		slot := if name == 'bad_slot' { 0 } else { 3 }
		source.write_string('!${n + 4} = !{i32 1, !"air.buffer", !"air.location_index", i32 ${slot}, i32 1, !"air.address_space", i32 2, !"air.read"}\n')
		access := if name == 'bad_access' { 'air.read' } else { 'air.write' }
		source.write_string('!${n + 5} = !{i32 2, !"air.buffer", !"air.location_index", i32 7, i32 1, !"air.address_space", i32 1, !"${access}"}\n')
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process('/opt/homebrew/opt/llvm/bin/llvm-as')
	proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close()
	os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	bits := os.read_bytes(out + '/input.bc')!
	defer { unsafe { bits.free() } }
	return sm_library_code_fixture(names, bits, true, true, true)
}
fn test_software_metal_compute() {
	$if !ios_metal_software ? { return }
	bytes := sm_test_compute_library('compute')!
	defer { unsafe { bytes.free() } }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		library := sm_library_bytes(d, bytes.clone(), unsafe { nil })
		assert library != 0
		mut error_slot := u64(0x1234)
		pipeline := sm_test_compute_pipeline(d, library, 'sum', &error_slot)
		assert pipeline != 0 && error_slot == 0x1234
		assert sm_send(pipeline, c'device') == d && sm_send(pipeline, c'threadExecutionWidth') == 1 && sm_send(pipeline, c'maxTotalThreadsPerThreadgroup') == 1 && sm_send(pipeline, c'staticThreadgroupMemoryLength') == 0
		for name in ['bad_flags', 'bad_access', 'bad_slot', 'bad_builtin', 'no_metadata', 'missing'] {
			error_slot = 0
			assert sm_test_compute_pipeline(d, library, name, &error_slot) == 0
			sm_library_check_error(error_slot, if name == 'missing' { i64(1) } else { i64(3) })
			assert sm_test_compute_pipeline(d, library, name, unsafe { nil }) == 0
		}
		queue := sm_send(d, c'newCommandQueue')
		empty_pipeline := sm_test_compute_pipeline(d, library, 'empty', unsafe { nil }); assert empty_pipeline != 0
		empty_command := sm_send(queue, c'commandBuffer'); empty_encoder := sm_send(empty_command, c'computeCommandEncoder')
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(empty_encoder, c'setComputePipelineState:', empty_pipeline) }
		sm_test_compute_dispatch(empty_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		sm_call(empty_encoder, c'endEncoding'); objc_release(empty_pipeline); sm_call(empty_command, c'commit')
		assert sm_send(empty_command, c'status') == 4 && sm_send(empty_command, c'error') == 0
		a := sm_test_buffer(d, 32, 0); b := sm_test_buffer(d, 32, 0); output := sm_test_buffer(d, 32, 0); copy := sm_test_buffer(d, 32, 0)
		ap := sm_send(a, c'contents'); bp := sm_send(b, c'contents'); outp := sm_send(output, c'contents'); cp := sm_send(copy, c'contents')
		unsafe { C.memset(voidptr(outp), 0xcc, 32) }
		command_pool := objc_pool_push()
		command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
		objc_retain(command)
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }
		sm_test_compute_buffer(encoder, a, 4, 0); sm_test_compute_buffer(encoder, b, 8, 3); sm_test_compute_buffer(encoder, output, 12, 7)
		for mode in 0 .. 11 {
			child := C.fork(); assert child >= 0
			if child == 0 {
				C.close(1); C.close(2)
				match mode {
					0 { sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 2) }
					1 { sm_test_compute_buffer(encoder, 0, 0, 0); sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1) }
					2 { sm_test_compute_buffer(encoder, a, 32, 0); sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1) }
					3 { sm_test_compute_buffer(encoder, a, 1, 0); sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1) }
					4 { sm_test_compute_buffer(encoder, a, 0, 31) }
					5 { sm_call(encoder, c'endEncoding'); sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1) }
					6 { sm_send(command, c'blitCommandEncoder') }
					7 { sm_call(command, c'commit') }
					8 { other := metal_create_system_default_device(); foreign := sm_test_buffer(other, 32, 0); sm_test_compute_buffer(encoder, foreign, 0, 0) }
					9 { fresh := sm_send(queue, c'commandBuffer'); unbound := sm_send(fresh, c'computeCommandEncoder'); sm_test_compute_dispatch(unbound, c'dispatchThreads:threadsPerThreadgroup:', 1) }
					else { unsafe { SMComputeDispatch(voidptr(C.ios_objc_msgsend))(encoder, c'dispatchThreads:threadsPerThreadgroup:', SoftwareMetalSize{1, 1, 1}, SoftwareMetalSize{2, 1, 1}) } }
				}
				C._exit(0)
			}
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		// Rebinding and changing pipeline cannot alter the recorded dispatch.
		float_pipeline := sm_test_compute_pipeline(d, library, 'float_sum', unsafe { nil }); assert float_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', float_pipeline) }
		sm_test_compute_buffer(encoder, copy, 0, 7); sm_call(encoder, c'endEncoding')
		blit := sm_send(command, c'blitCommandEncoder'); sm_test_copy(blit, output, 12, copy, 16, 4); sm_call(blit, c'endEncoding')
		unsafe { *(&u32(ap + 4)) = 19; *(&u32(bp + 8)) = 23 }
		assert unsafe { *(&u32(outp + 12)) } == u32(0xcccccccc)
		objc_release(pipeline); objc_release(float_pipeline)
		objc_pool_pop(command_pool) // Recorded work owns its pipeline after encoder destruction.
		sm_call(command, c'commit'); sm_call(command, c'waitUntilCompleted')
		assert sm_send(command, c'status') == 4 && sm_send(command, c'error') == 0
		assert unsafe { *(&u32(outp + 12)) } == 42 && unsafe { *(&u32(cp + 16)) } == 42 && unsafe { *(&u32(cp)) } == 0
		for i in 0 .. 32 { if i < 12 || i >= 16 { assert unsafe { *(&u8(outp + u64(i))) } == 0xcc } }
		objc_release(command)
		indexed_command := sm_send(queue, c'commandBuffer'); ie := sm_send(indexed_command, c'computeCommandEncoder')
		ip := sm_test_compute_pipeline(d, library, 'indexed_sum', unsafe { nil }); assert ip != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(ie, c'setComputePipelineState:', ip) }
		sm_test_compute_buffer(ie, a, 4, 0); sm_test_compute_buffer(ie, b, 8, 3); sm_test_compute_buffer(ie, output, 4, 7)
		// Derived extents must reject before recording, including when a
		// binding's base offset alone fits the buffer.
		child := C.fork(); assert child >= 0
		if child == 0 {
			C.close(1); C.close(2)
			sm_test_compute_buffer(ie, output, 20, 7)
			sm_test_compute_dispatch(ie, c'dispatchThreads:threadsPerThreadgroup:', 1); C._exit(0)
		}
		mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		sm_test_compute_dispatch(ie, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(ie, c'endEncoding'); objc_release(ip)
		unsafe { *(&u32(ap + 12)) = 101; *(&u32(bp + 12)) = 203 }
		sm_call(indexed_command, c'commit'); assert sm_send(indexed_command, c'status') == 4
		assert unsafe { *(&u32(outp + 16)) } == 304 && unsafe { *(&u32(outp + 12)) } == 42
		maximum := sm_send(queue, c'commandBuffer'); me := sm_send(maximum, c'computeCommandEncoder')
		for i, name in ['max', 'float_max'] {
			mp := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert mp != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(me, c'setComputePipelineState:', mp) }
			sm_test_compute_buffer(me, a, if i == 0 { u64(0) } else { 4 }, 0)
			sm_test_compute_buffer(me, b, if i == 0 { u64(0) } else { 8 }, 3)
			sm_test_compute_buffer(me, output, u64(20 + i * 4), 7)
			sm_test_compute_dispatch(me, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(mp)
		}
		sm_call(me, c'endEncoding')
		unsafe { *(&u32(ap)) = 0xfffffffb; *(&u32(bp)) = 3; *(&u32(ap + 4)) = 0x3fc00000; *(&u32(bp + 8)) = 0x40100000 }
		sm_call(maximum, c'commit'); assert sm_send(maximum, c'status') == 4
		assert unsafe { *(&u32(outp + 20)) } == 3 && unsafe { *(&u32(outp + 24)) } == u32(0x40100000)
		converted := sm_send(queue, c'commandBuffer'); ce := sm_send(converted, c'computeCommandEncoder')
		for i, name in ['int_float', 'float_int'] {
			conversion_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert conversion_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(ce, c'setComputePipelineState:', conversion_pipeline) }
			sm_test_compute_buffer(ce, a, if i == 0 { u64(0) } else { 4 }, 0)
			sm_test_compute_buffer(ce, b, if i == 0 { u64(0) } else { 8 }, 3)
			sm_test_compute_buffer(ce, output, u64(4 + i * 4), 7)
			sm_test_compute_dispatch(ce, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(conversion_pipeline)
		}
		sm_call(ce, c'endEncoding')
		unsafe { *(&u32(bp)) = 0x3fa00000; *(&u32(ap + 4)) = 0x40b80000; *(&u32(bp + 8)) = 0xbfa00000 }
		sm_call(converted, c'commit'); assert sm_send(converted, c'status') == 4
		assert unsafe { *(&u32(outp + 4)) } == u32(0xc0700000) && unsafe { *(&u32(outp + 8)) } == 4
		unary := sm_send(queue, c'commandBuffer'); ue := sm_send(unary, c'computeCommandEncoder')
		for i, name in ['negate', 'frozen'] {
			unary_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert unary_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(ue, c'setComputePipelineState:', unary_pipeline) }
			sm_test_compute_buffer(ue, a, u64(8 + i * 4), 0); sm_test_compute_buffer(ue, b, 0, 3)
			sm_test_compute_buffer(ue, output, u64(4 + i * 4), 7)
			sm_test_compute_dispatch(ue, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(unary_pipeline)
		}
		sm_call(ue, c'endEncoding')
		unsafe { *(&u32(ap + 8)) = 0x7f812345; *(&u32(ap + 12)) = 0x7f800000 }
		sm_call(unary, c'commit'); assert sm_send(unary, c'status') == 4
		assert unsafe { *(&u32(outp + 4)) } == u32(0xff812345) && unsafe { *(&u32(outp + 8)) } == 0
		flagged := sm_send(queue, c'commandBuffer'); flags_encoder := sm_send(flagged, c'computeCommandEncoder')
		for i, name in ['flagged_sum', 'frozen_sum'] {
			flags_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert flags_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(flags_encoder, c'setComputePipelineState:', flags_pipeline) }
			sm_test_compute_buffer(flags_encoder, a, u64(4 + i * 4), 0); sm_test_compute_buffer(flags_encoder, b, u64(8 + i * 4), 3)
			sm_test_compute_buffer(flags_encoder, output, u64(4 + i * 4), 7)
			sm_test_compute_dispatch(flags_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(flags_pipeline)
		}
		sm_call(flags_encoder, c'endEncoding')
		unsafe { *(&u32(ap + 4)) = 100; *(&u32(bp + 8)) = 200; *(&u32(ap + 8)) = 0xffffffff; *(&u32(bp + 12)) = 1 }
		sm_call(flagged, c'commit'); assert sm_send(flagged, c'status') == 4
		assert unsafe { *(&u32(outp + 4)) } == 300 && unsafe { *(&u32(outp + 8)) } == 0
		flag_failure := sm_send(queue, c'commandBuffer'); fail_encoder := sm_send(flag_failure, c'computeCommandEncoder')
		fail_pipeline := sm_test_compute_pipeline(d, library, 'flagged_sum', unsafe { nil }); assert fail_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(fail_encoder, c'setComputePipelineState:', fail_pipeline) }
		sm_test_compute_buffer(fail_encoder, a, 8, 0); sm_test_compute_buffer(fail_encoder, b, 12, 3); sm_test_compute_buffer(fail_encoder, output, 4, 7)
		sm_test_compute_dispatch(fail_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(fail_encoder, c'endEncoding'); objc_release(fail_pipeline)
		sm_call(flag_failure, c'commit'); assert sm_send(flag_failure, c'status') == 5 && sm_send(flag_failure, c'error') != 0
		assert unsafe { *(&u32(outp + 4)) } == 300
		bits_command := sm_send(queue, c'commandBuffer'); bits_encoder := sm_send(bits_command, c'computeCommandEncoder')
		for i, name in ['bits', 'bits_frozen'] {
			bits_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert bits_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(bits_encoder, c'setComputePipelineState:', bits_pipeline) }
			sm_test_compute_buffer(bits_encoder, a, u64(4 + i * 4), 0); sm_test_compute_buffer(bits_encoder, b, u64(8 + i * 4), 3)
			sm_test_compute_buffer(bits_encoder, output, u64(16 + i * 8), 7)
			sm_test_compute_dispatch(bits_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(bits_pipeline)
		}
		sm_call(bits_encoder, c'endEncoding')
		unsafe { *(&u32(ap + 4)) = 0x01234567; *(&u32(ap + 8)) = 0x01234567; *(&u32(bp + 8)) = 0x100; *(&u32(bp + 12)) = 0 }
		sm_call(bits_command, c'commit'); assert sm_send(bits_command, c'status') == 4
		assert unsafe { *(&u32(outp + 16)) } == u32(0x80c4a2e6) && unsafe { *(&u32(outp + 20)) } == 43
		assert unsafe { *(&u32(outp + 24)) } == u32(0x80c4a2e6) && unsafe { *(&u32(outp + 28)) } == 12
		funnel_command := sm_send(queue, c'commandBuffer'); funnel_encoder := sm_send(funnel_command, c'computeCommandEncoder')
		funnel_pipeline := sm_test_compute_pipeline(d, library, 'funnel', unsafe { nil }); assert funnel_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(funnel_encoder, c'setComputePipelineState:', funnel_pipeline) }
		sm_test_compute_buffer(funnel_encoder, a, 0, 0); sm_test_compute_buffer(funnel_encoder, b, 0, 3); sm_test_compute_buffer(funnel_encoder, output, 16, 7)
		sm_test_compute_dispatch(funnel_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(funnel_encoder, c'endEncoding'); objc_release(funnel_pipeline)
		unsafe { *(&u32(ap)) = 0x01234567; *(&u32(ap + 4)) = 36; *(&u32(bp)) = 0x89abcdef }
		sm_call(funnel_command, c'commit'); assert sm_send(funnel_command, c'status') == 4
		assert unsafe { *(&u32(outp + 16)) } == u32(0x12345678) && unsafe { *(&u32(outp + 20)) } == u32(0x789abcde)
		extrema_command := sm_send(queue, c'commandBuffer'); extrema_encoder := sm_send(extrema_command, c'computeCommandEncoder')
		extrema_pipeline := sm_test_compute_pipeline(d, library, 'extrema', unsafe { nil }); assert extrema_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(extrema_encoder, c'setComputePipelineState:', extrema_pipeline) }
		sm_test_compute_buffer(extrema_encoder, a, 0, 0); sm_test_compute_buffer(extrema_encoder, b, 0, 3); sm_test_compute_buffer(extrema_encoder, output, 16, 7)
		sm_test_compute_dispatch(extrema_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(extrema_encoder, c'endEncoding'); objc_release(extrema_pipeline)
		unsafe { *(&u32(ap)) = 0xfffffffb; *(&u32(bp)) = 3 }
		sm_call(extrema_command, c'commit'); assert sm_send(extrema_command, c'status') == 4
		for i, expected in [u32(0xfffffffb), 3, 3, 0xfffffffb]! { assert unsafe { *(&u32(outp + u64(16 + i * 4))) } == expected }
		abs_command := sm_send(queue, c'commandBuffer'); abs_encoder := sm_send(abs_command, c'computeCommandEncoder')
		for i, name in ['abs_keep', 'abs_frozen'] {
			abs_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert abs_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(abs_encoder, c'setComputePipelineState:', abs_pipeline) }
			sm_test_compute_buffer(abs_encoder, a, 0, 0); sm_test_compute_buffer(abs_encoder, b, 0, 3); sm_test_compute_buffer(abs_encoder, output, u64(16 + i * 8), 7)
			sm_test_compute_dispatch(abs_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(abs_pipeline)
		}
		sm_call(abs_encoder, c'endEncoding')
		unsafe { *(&u32(ap)) = 0x80000000; *(&u32(bp)) = 0xfffffffb }
		sm_call(abs_command, c'commit'); assert sm_send(abs_command, c'status') == 4
		for i, expected in [u32(0x80000000), 5, 0, 5]! { assert unsafe { *(&u32(outp + u64(16 + i * 4))) } == expected }
		sat_output := sm_test_buffer(d, 64, 0); satp := sm_send(sat_output, c'contents')
		unsafe { C.memset(voidptr(satp), 0xcc, 64) }
		sat_command := sm_send(queue, c'commandBuffer'); sat_encoder := sm_send(sat_command, c'computeCommandEncoder')
		sat_pipeline := sm_test_compute_pipeline(d, library, 'saturating', unsafe { nil }); assert sat_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(sat_encoder, c'setComputePipelineState:', sat_pipeline) }
		for i in 0 .. 4 {
			sm_test_compute_buffer(sat_encoder, a, u64(i * 4), 0); sm_test_compute_buffer(sat_encoder, b, u64(i * 4), 3); sm_test_compute_buffer(sat_encoder, sat_output, u64(i * 16), 7)
			sm_test_compute_dispatch(sat_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(sat_encoder, c'endEncoding'); objc_release(sat_pipeline); objc_release(sat_output)
		for i, x in [u32(0x7fffffff), 0x80000000, 0xffffffff, 0]! { unsafe { *(&u32(ap + u64(i * 4))) = x; *(&u32(bp + u64(i * 4))) = 1 } }
		for i in 0 .. 64 { assert unsafe { *(&u8(satp + u64(i))) } == 0xcc }
		sm_call(sat_command, c'commit'); assert sm_send(sat_command, c'status') == 4
		for i, expected in [u32(0x7fffffff), 0x80000000, 0x7ffffffe, 0x7ffffffe, 0x80000001, 0x80000001, 0x80000000, 0x7fffffff, 0, 0xffffffff, 0xfffffffe, 0xfffffffe, 1, 1, 0xffffffff, 0]! { assert unsafe { *(&u32(satp + u64(i * 4))) } == expected }
		shift_output := sm_test_buffer(d, 32, 0); shiftp := sm_send(shift_output, c'contents')
		unsafe { C.memset(voidptr(shiftp), 0xcc, 32) }
		shift_command := sm_send(queue, c'commandBuffer'); shift_encoder := sm_send(shift_command, c'computeCommandEncoder')
		for i in 0 .. 4 {
			shift_pipeline := sm_test_compute_pipeline(d, library, if i == 2 { 'saturating_shift_frozen' } else { 'saturating_shift' }, unsafe { nil }); assert shift_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(shift_encoder, c'setComputePipelineState:', shift_pipeline) }
			sm_test_compute_buffer(shift_encoder, a, u64(i * 4), 0); sm_test_compute_buffer(shift_encoder, b, u64(i * 4), 3); sm_test_compute_buffer(shift_encoder, shift_output, u64(i * 8), 7)
			sm_test_compute_dispatch(shift_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(shift_pipeline)
		}
		sm_call(shift_encoder, c'endEncoding')
		for i, x in [u32(0x40000000), 0xc0000000, 0, 0x80000000]! { unsafe { *(&u32(ap + u64(i * 4))) = x; *(&u32(bp + u64(i * 4))) = [u32(1), 2, 32, 0]![i] } }
		for i in 0 .. 32 { assert unsafe { *(&u8(shiftp + u64(i))) } == 0xcc }
		sm_call(shift_command, c'commit'); assert sm_send(shift_command, c'status') == 4
		for i, expected in [u32(0x7fffffff), 0x80000000, 0x80000000, 0xffffffff, 0, 0, 0x80000000, 0x80000000]! { assert unsafe { *(&u32(shiftp + u64(i * 4))) } == expected }
		shift_failed := sm_send(queue, c'commandBuffer'); shift_fail_encoder := sm_send(shift_failed, c'computeCommandEncoder')
		shift_fail_pipeline := sm_test_compute_pipeline(d, library, 'saturating_shift', unsafe { nil }); assert shift_fail_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(shift_fail_encoder, c'setComputePipelineState:', shift_fail_pipeline) }
		sm_test_compute_buffer(shift_fail_encoder, a, 8, 0); sm_test_compute_buffer(shift_fail_encoder, b, 8, 3); sm_test_compute_buffer(shift_fail_encoder, shift_output, 16, 7)
		sm_test_compute_dispatch(shift_fail_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(shift_fail_encoder, c'endEncoding'); objc_release(shift_fail_pipeline)
		sm_call(shift_failed, c'commit'); assert sm_send(shift_failed, c'status') == 5 && sm_send(shift_failed, c'error') != 0
		for i, expected in [u32(0x7fffffff), 0x80000000, 0x80000000, 0xffffffff, 0, 0, 0x80000000, 0x80000000]! { assert unsafe { *(&u32(shiftp + u64(i * 4))) } == expected }; objc_release(shift_output)
		permutation := sm_send(queue, c'commandBuffer'); pe := sm_send(permutation, c'computeCommandEncoder')
		pp := sm_test_compute_pipeline(d, library, 'bit_permutation', unsafe { nil }); assert pp != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(pe, c'setComputePipelineState:', pp) }
		sm_test_compute_buffer(pe, a, 0, 0); sm_test_compute_buffer(pe, b, 0, 3); sm_test_compute_buffer(pe, output, 16, 7)
		sm_test_compute_dispatch(pe, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(pe, c'endEncoding'); objc_release(pp)
		unsafe { *(&u32(ap)) = 0xd6; *(&u32(bp)) = 0x55 }
		sm_call(permutation, c'commit'); assert sm_send(permutation, c'status') == 4
		for i, expected in [u32(0x0e), 0x14, 0x54, 6]! { assert unsafe { *(&u32(outp + 16 + u64(i * 4))) } == expected }
		unsafe { C.memset(voidptr(outp), 0xcc, 32) }
		sign_command := sm_send(queue, c'commandBuffer'); sign_encoder := sm_send(sign_command, c'computeCommandEncoder')
		sign_pipeline := sm_test_compute_pipeline(d, library, 'float_sign', unsafe { nil }); assert sign_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(sign_encoder, c'setComputePipelineState:', sign_pipeline) }
		for i in 0 .. 2 {
			sm_test_compute_buffer(sign_encoder, a, u64(i * 8), 0); sm_test_compute_buffer(sign_encoder, b, u64(i * 8), 3); sm_test_compute_buffer(sign_encoder, output, u64(i * 16), 7)
			sm_test_compute_dispatch(sign_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(sign_encoder, c'endEncoding'); objc_release(sign_pipeline)
		for i, value in [u32(0xff812345), 0xfe55, 0x80000000, 0xfc01]! { unsafe { *(&u32(ap + u64(i * 4))) = value } }
		for i, value in [u32(0), 0, 0x80000001, 0x8000]! { unsafe { *(&u32(bp + u64(i * 4))) = value } }
		for i in 0 .. 32 { assert unsafe { *(&u8(outp + u64(i))) } == 0xcc }
		sm_call(sign_command, c'commit'); assert sm_send(sign_command, c'status') == 4
		for i, expected in [u32(0x7f812345), 0x7f812345, 0x7e55, 0x7e55, 0, 0x80000000, 0x7c01, 0xfc01]! { assert unsafe { *(&u32(outp + u64(i * 4))) } == expected }
		round_output := sm_test_buffer(d, 160, 0); roundp := sm_send(round_output, c'contents')
		unsafe { C.memset(voidptr(roundp), 0xcc, 160) }
		round_command := sm_send(queue, c'commandBuffer'); round_encoder := sm_send(round_command, c'computeCommandEncoder')
		round_pipeline := sm_test_compute_pipeline(d, library, 'rounding', unsafe { nil }); assert round_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(round_encoder, c'setComputePipelineState:', round_pipeline) }
		for i in 0 .. 4 {
			sm_test_compute_buffer(round_encoder, a, u64(i * 8), 0); sm_test_compute_buffer(round_encoder, b, 0, 3); sm_test_compute_buffer(round_encoder, round_output, u64(i * 40), 7)
			sm_test_compute_dispatch(round_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(round_encoder, c'endEncoding'); objc_release(round_pipeline); objc_release(round_output)
		for i, value in [u32(0x40200000), 0x4100, 0xc0200000, 0xc100, 0x3f000000, 0x3800, 0xbf000000, 0xb800]! { unsafe { *(&u32(ap + u64(i * 4))) = value } }
		for i in 0 .. 160 { assert unsafe { *(&u8(roundp + u64(i))) } == 0xcc }
		sm_call(round_command, c'commit'); assert sm_send(round_command, c'status') == 4
		for i, expected in [u32(0x40000000), 0x40400000, 0x40000000, 0x40400000, 0x40000000, 0x4000, 0x4200, 0x4000, 0x4200, 0x4000, 0xc0400000, 0xc0000000, 0xc0000000, 0xc0400000, 0xc0000000, 0xc200, 0xc000, 0xc000, 0xc200, 0xc000, 0, 0x3f800000, 0, 0x3f800000, 0, 0, 0x3c00, 0, 0x3c00, 0, 0xbf800000, 0x80000000, 0x80000000, 0xbf800000, 0x80000000, 0xbc00, 0x8000, 0x8000, 0xbc00, 0x8000]! { assert unsafe { *(&u32(roundp + u64(i * 4))) } == expected }
		root_output := sm_test_buffer(d, 64, 0); rootp := sm_send(root_output, c'contents')
		unsafe { C.memset(voidptr(rootp), 0xcc, 64) }
		root_command := sm_send(queue, c'commandBuffer'); root_encoder := sm_send(root_command, c'computeCommandEncoder')
		root_pipeline := sm_test_compute_pipeline(d, library, 'square_root', unsafe { nil }); assert root_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(root_encoder, c'setComputePipelineState:', root_pipeline) }
		for i in 0 .. 4 {
			sm_test_compute_buffer(root_encoder, a, u64(i * 8), 0); sm_test_compute_buffer(root_encoder, b, 0, 3); sm_test_compute_buffer(root_encoder, root_output, u64(i * 16), 7)
			sm_test_compute_dispatch(root_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(root_encoder, c'endEncoding'); objc_release(root_pipeline); objc_release(root_output)
		for i, value in [u32(0x40000000), 0x4000, 0xc0800000, 0xc400, 0x80000000, 0x8000, 1, 1]! { unsafe { *(&u32(ap + u64(i * 4))) = value } }
		for i in 0 .. 64 { assert unsafe { *(&u8(rootp + u64(i))) } == 0xcc }
		sm_call(root_command, c'commit'); assert sm_send(root_command, c'status') == 4
		for i, expected in [u32(0x3fb504f3), 0x3fb504f3, 0x3da8, 0x3da8, 0x7fc00000, 0x40000000, 0x7e00, 0x4000, 0x80000000, 0, 0x8000, 0, 0x1a3504f3, 0x1a3504f3, 0x0c00, 0x0c00]! { assert unsafe { *(&u32(rootp + u64(i * 4))) } == expected }
		ext_left := sm_test_buffer(d, 40, 0); ext_right := sm_test_buffer(d, 40, 0); ext_output := sm_test_buffer(d, 80, 0)
		extap := sm_send(ext_left, c'contents'); extbp := sm_send(ext_right, c'contents'); extp := sm_send(ext_output, c'contents')
		unsafe { C.memset(voidptr(extp), 0xcc, 80) }
		ext_command := sm_send(queue, c'commandBuffer'); ext_encoder := sm_send(ext_command, c'computeCommandEncoder')
		ext_pipeline := sm_test_compute_pipeline(d, library, 'floating_extrema', unsafe { nil }); assert ext_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(ext_encoder, c'setComputePipelineState:', ext_pipeline) }
		for i in 0 .. 5 {
			sm_test_compute_buffer(ext_encoder, ext_left, u64(i * 8), 0); sm_test_compute_buffer(ext_encoder, ext_right, u64(i * 8), 3); sm_test_compute_buffer(ext_encoder, ext_output, u64(i * 16), 7)
			sm_test_compute_dispatch(ext_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(ext_encoder, c'endEncoding'); objc_release(ext_pipeline); objc_release(ext_left); objc_release(ext_right); objc_release(ext_output)
		for i, value in [u32(0), 0, 0x80000000, 0x8000, 0xff812345, 0xfc01, 0x3f800000, 0x3c00, 0x7f800000, 0x7c00]! { unsafe { *(&u32(extap + u64(i * 4))) = value } }
		for i, value in [u32(0x80000000), 0x8000, 0, 0, 0x3f800000, 0x3c00, 0x7fc12345, 0x7e55, 0xff800000, 0xfc00]! { unsafe { *(&u32(extbp + u64(i * 4))) = value } }
		for i in 0 .. 80 { assert unsafe { *(&u8(extp + u64(i))) } == 0xcc }
		sm_call(ext_command, c'commit'); assert sm_send(ext_command, c'status') == 4
		for i, expected in [u32(0x80000000), 0, 0x8000, 0, 0x80000000, 0, 0x8000, 0, 0x7fc00000, 0x7fc00000, 0x7e00, 0x7e00, 0x7fc00000, 0x7fc00000, 0x7e00, 0x7e00, 0xff800000, 0x7f800000, 0xfc00, 0x7c00]! { assert unsafe { *(&u32(extp + u64(i * 4))) } == expected }
		unsafe { *(&u32(bp)) = 0 } // Preserve the later division-by-zero fixture.
		// A second dispatch aliases output to an input; resources remain live
		// after caller releases its handles, through the recorded snapshot.
		alias := sm_send(queue, c'commandBuffer'); e := sm_send(alias, c'computeCommandEncoder')
		p := sm_test_compute_pipeline(d, library, 'float_sum', unsafe { nil }); assert p != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(e, c'setComputePipelineState:', p) }
		sm_test_compute_buffer(e, a, 4, 0); sm_test_compute_buffer(e, b, 8, 3); sm_test_compute_buffer(e, a, 4, 7)
		sm_test_compute_dispatch(e, c'dispatchThreadgroups:threadsPerThreadgroup:', 1); sm_call(e, c'endEncoding')
		unsafe { *(&u32(ap + 4)) = 0x3fc00000; *(&u32(bp + 8)) = 0x40100000 }
		objc_release(p); sm_call(alias, c'commit'); assert unsafe { *(&u32(ap + 4)) } == u32(0x40700000)
		// Dynamic interpreter errors report failed completion, retain earlier
		// stores, and stop subsequent commands in the same command buffer.
		failed := sm_send(queue, c'commandBuffer'); fe := sm_send(failed, c'computeCommandEncoder')
		fp := sm_test_compute_pipeline(d, library, 'divide', unsafe { nil }); assert fp != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(fe, c'setComputePipelineState:', fp) }
		sm_test_compute_buffer(fe, a, 0, 0); sm_test_compute_buffer(fe, b, 0, 3); sm_test_compute_buffer(fe, output, 0, 7)
		sm_test_compute_dispatch(fe, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(fe, c'endEncoding'); objc_release(fp)
		fb := sm_send(failed, c'blitCommandEncoder'); sm_test_copy(fb, output, 0, copy, 0, 4); sm_call(fb, c'endEncoding')
		objc_release(a); objc_release(b); objc_release(output); objc_release(copy); objc_release(library); objc_release(d); objc_release(queue)
		sm_call(failed, c'commit'); sm_call(failed, c'waitUntilCompleted'); sm_call(failed, c'waitUntilScheduled')
		assert sm_send(failed, c'status') == 5 && unsafe { *(&u32(outp)) } == 17 && unsafe { *(&u32(cp)) } == 0
		error := sm_send(failed, c'error'); assert error != 0 && string_text(sm_send(error, c'domain')) == 'MTLCommandBufferErrorDomain' && sm_send(error, c'code') == 1
		assert string_text(sm_send(error, c'localizedDescription')).len > 0
		objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		// Framework globals intentionally live until runtime shutdown. Check
		// their scoped cells after verifying all command resources have drained.
		domain_cell := runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_MTLCommandBufferErrorDomain') or { panic(err) }
		assert string_text(read64(domain_cell)) == 'MTLCommandBufferErrorDomain'
		assert runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_MTLCommandBufferErrorDomain') or { panic(err) } == domain_cell
		if _ := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_MTLCommandBufferErrorDomain') { assert false }
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-COMPUTE: classic AIR metadata, scalar buffer pipelines, sparse/reordered bindings, empty/indexed/max/conversion/negation/freeze/flagged/bit-intrinsic/funnel/extrema/abs/saturating/saturating-shift/bit-permutation/float-sign/rounding/sqrt/floating-extrema kernels, derived bounds, single-thread dispatch selectors, deferred execution, snapshots, aliasing, ordered blits, eleven encoding guards, pipeline rejection, poison-store failed completion and two drained runtimes PASS')
}
fn sm_call(object u64, selector &char) { unsafe { SMVoid(voidptr(C.ios_objc_msgsend))(object, selector) } }
struct SMBindingReentry {
	encoder u64
	first u64
	second u64
	inline bool
mut:
	calls int
}
fn sm_binding_reentry(block u64, pointer u64, length u64) {
	mut p := unsafe { &SMBindingReentry(read64(block + 32)) }
	state := obj_header(p.encoder).metal_compute
	if p.inline {
		assert state.inline_slots & (u32(1) << 24) != 0 && state.offsets[24] == 0
		assert unsafe { *(&u32(sm_send(state.buffers[24], c'contents'))) } == 77
	} else { assert state.buffers[24] == p.first && state.buffers[25] == p.second }
	// An update made by client cleanup must remain visible after the outer
	// setter returns. This runs under the runtime's recursive lock.
	sm_test_compute_buffer(p.encoder, p.first, 0, 26)
	p.calls++
	assert C.munmap(unsafe { voidptr(pointer) }, usize(length)) == 0
}
fn test_software_metal_compute_bindings() {
	$if !ios_metal_software ? { return }
	bytes := sm_test_compute_library('bindings')!
	defer { unsafe { bytes.free() } }
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push(); d := metal_create_system_default_device()
		library := sm_library_bytes(d, bytes.clone(), unsafe { nil }); assert library != 0
		pipeline := sm_test_compute_pipeline(d, library, 'sum', unsafe { nil }); assert pipeline != 0
		queue := sm_send(d, c'newCommandQueue'); output := sm_test_buffer(d, 64, 0)
		a := sm_test_buffer(d, 64, 0); b := sm_test_buffer(d, 64, 0)
		ap := sm_send(a, c'contents'); bp := sm_send(b, c'contents'); outp := sm_send(output, c'contents')
		unsafe { *(&u32(ap + 4)) = 100; *(&u32(bp + 8)) = 200; C.memset(voidptr(outp), 0xcc, 64) }
		command_pool := objc_pool_push()
		command := sm_send(queue, c'commandBuffer'); objc_retain(command)
		encoder := sm_send(command, c'computeCommandEncoder')
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }
		mut buffers := [8]u64{}; mut offsets := [8]u64{}
		buffers[0] = a; offsets[0] = 4; buffers[3] = b; offsets[3] = 8; buffers[7] = output
		sm_test_compute_buffers(encoder, u64(unsafe { &buffers[0] }), u64(unsafe { &offsets[0] }), SoftwareMetalRange{0, 8})
		// Caller arrays are copied, while explicit buffer contents stay deferred.
		buffers[0] = 0; offsets[3] = 64
		sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		mut words := [4]u32{}
		words[0] = 7; words[1] = 11; words[2] = 13
		sm_test_compute_bytes(encoder, u64(unsafe { &words[0] }), 4, 0)
		sm_test_compute_bytes(encoder, u64(unsafe { &words[1] }), 4, 3)
		sm_test_compute_offset(encoder, 4, 7)
		sm_test_compute_dispatch(encoder, c'dispatchThreadgroups:threadsPerThreadgroup:', 1)
		words[0] = 1000; words[1] = 2000 // Neither source address is retained.
		// Replacing inline bytes allocates a new snapshot and resets its offset.
		sm_test_compute_bytes(encoder, u64(unsafe { &words[2] }), 4, 0)
		sm_test_compute_offset(encoder, 8, 7)
		sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		words[2] = 3000
		// Explicit setBuffer replaces inline bytes and permits offset updates.
		sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_offset(encoder, 4, 0)
		sm_test_compute_buffer(encoder, b, 8, 3); sm_test_compute_offset(encoder, 12, 7)
		sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		// Exercise all 31 slots, empty end ranges, nil clearing and the 4 KiB edge.
		mut all_buffers := [31]u64{}; mut all_offsets := [31]u64{}
		for i in 0 .. 31 { all_buffers[i] = a }
		sm_test_compute_buffers(encoder, u64(unsafe { &all_buffers[0] }), u64(unsafe { &all_offsets[0] }), SoftwareMetalRange{0, 31})
		sm_test_compute_buffers(encoder, 0, 0, SoftwareMetalRange{31, 0})
		mut inline := [4096]u8{}
		inline[0] = 31
		sm_test_compute_bytes(encoder, u64(unsafe { &inline[0] }), 4096, 30)
		assert sm_buffer_length(obj_header(obj_header(encoder).metal_compute.buffers[30])) == 4096
		all_buffers[30] = 0; all_offsets[30] = ~u64(0)
		sm_test_compute_buffers(encoder, u64(unsafe { &all_buffers[30] }), u64(unsafe { &all_offsets[30] }), SoftwareMetalRange{30, 1})
		assert obj_header(encoder).metal_compute.buffers[30] == 0 && obj_header(encoder).metal_compute.inline_slots == 0
		// A permutation remains valid when the encoder owns the only references.
		x := sm_test_buffer(d, 8, 0); y := sm_test_buffer(d, 8, 0)
		mut swap := [x, y]!; position := [u64(0), 0]!
		sm_test_compute_buffers(encoder, u64(unsafe { &swap[0] }), u64(unsafe { &position[0] }), SoftwareMetalRange{20, 2})
		objc_release(x); objc_release(y); swap[0] = y; swap[1] = x
		sm_test_compute_buffers(encoder, u64(unsafe { &swap[0] }), u64(unsafe { &position[0] }), SoftwareMetalRange{20, 2})
		assert obj_header(encoder).metal_compute.buffers[20] == y && obj_header(encoder).metal_compute.buffers[21] == x
		// Replacing no-copy buffers may synchronously invoke client code.
		for mode in 0 .. 2 {
			mut probe := SMBindingReentry{encoder: encoder, first: a, second: b, inline: mode == 1}
			descriptor := [u64(0), u64(sizeof(SMCompletionBlock))]!
			block := SMCompletionBlock{isa: block_isa(0), invoke: u64(unsafe { voidptr(sm_binding_reentry) }), descriptor: u64(unsafe { &descriptor[0] }), capture: u64(unsafe { &probe })}
			page := u64(C.getpagesize())
			for slot in 24 .. if mode == 0 { 26 } else { 25 } {
				memory := C.mmap(unsafe { nil }, usize(page), 3, 0x1002, -1, 0); assert u64(memory) != ~u64(0)
				old := sm_test_no_copy(d, u64(memory), page, 0, u64(unsafe { &block })); assert old != 0
				sm_test_compute_buffer(encoder, old, 0, u64(slot)); objc_release(old)
			}
			if mode == 0 {
				replacements := [a, b]!
				sm_test_compute_buffers(encoder, u64(unsafe { &replacements[0] }), u64(unsafe { &position[0] }), SoftwareMetalRange{24, 2})
			} else {
				value := u32(77)
				sm_test_compute_bytes(encoder, u64(unsafe { &value }), 4, 24)
			}
			assert probe.calls == if mode == 0 { 2 } else { 1 }
			assert obj_header(encoder).metal_compute.buffers[26] == a
		}
		for mode in 0 .. 16 {
			child := C.fork(); assert child >= 0
			if child == 0 {
				C.close(1); C.close(2)
				match mode {
					0 { sm_test_compute_bytes(encoder, 0, 4, 0) }
					1 { sm_test_compute_bytes(encoder, u64(unsafe { &words[0] }), 0, 0) }
					2 { sm_test_compute_bytes(encoder, u64(unsafe { &inline[0] }), 4097, 0) }
					3 { sm_test_compute_bytes(encoder, ~u64(0), 4, 0) }
					4 { sm_test_compute_bytes(encoder, u64(unsafe { &words[0] }), 4, 31) }
					5 { sm_test_compute_offset(encoder, 0, 31) }
					6 { sm_test_compute_offset(encoder, 65, 0) }
					7 { sm_test_compute_offset(encoder, 0, 30) }
					8 { sm_test_compute_bytes(encoder, u64(unsafe { &words[0] }), 4, 30); sm_test_compute_offset(encoder, 0, 30) }
					9 { sm_test_compute_buffers(encoder, 0, 0, SoftwareMetalRange{30, 2}) }
					10 { sm_test_compute_buffers(encoder, 0, 0, SoftwareMetalRange{~u64(0), 2}) }
					11 { sm_test_compute_buffers(encoder, 0, u64(unsafe { &offsets[0] }), SoftwareMetalRange{0, 1}) }
					12 { sm_test_compute_buffers(encoder, u64(unsafe { &buffers[0] }), 0, SoftwareMetalRange{0, 1}) }
					13 { sm_test_compute_buffers(encoder, ~u64(0), u64(unsafe { &offsets[0] }), SoftwareMetalRange{0, 1}) }
					14 { all_offsets[0] = 65; sm_test_compute_buffers(encoder, u64(unsafe { &all_buffers[0] }), u64(unsafe { &all_offsets[0] }), SoftwareMetalRange{0, 2}) }
					else { other := metal_create_system_default_device(); foreign := sm_test_buffer(other, 8, 0); all_buffers[1] = foreign; sm_test_compute_buffers(encoder, u64(unsafe { &all_buffers[0] }), u64(unsafe { &all_offsets[0] }), SoftwareMetalRange{0, 2}) }
				}
				C._exit(0)
			}
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		sm_call(encoder, c'endEncoding')
		for mode in 0 .. 3 {
			child := C.fork(); assert child >= 0
			if child == 0 {
				C.close(1); C.close(2)
				match mode { 0 { sm_test_compute_bytes(encoder, u64(unsafe { &words[0] }), 4, 0) } 1 { sm_test_compute_offset(encoder, 0, 0) } else { sm_test_compute_buffers(encoder, 0, 0, SoftwareMetalRange{31, 0}) } }
				C._exit(0)
			}
			mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
		}
		objc_pool_pop(command_pool) // Destroys the encoder and its unrecorded bindings.
		unsafe { *(&u32(ap + 4)) = 123; *(&u32(bp + 8)) = 456 }
		objc_release(pipeline); objc_release(library); objc_release(a); objc_release(b); objc_release(output); objc_release(queue); objc_release(d)
		assert unsafe { *(&u32(outp)) } == u32(0xcccccccc)
		sm_call(command, c'commit'); assert sm_send(command, c'status') == 4
		for i, expected in [u32(579), 18, 24, 579]! { assert unsafe { *(&u32(outp + u64(i * 4))) } == expected }
		for i in 16 .. 64 { assert unsafe { *(&u8(outp + u64(i))) } == 0xcc }
		objc_release(command); objc_pool_pop(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; objc_stop()
	}
	println('IOS-SOFTWARE-METAL-COMPUTE-BINDINGS: inline copies and 4096-byte edge, offset updates, bulk range ABI, copied arrays, nil slots, sole-owner swaps, reentrant client deallocation, four deferred snapshots, encoder destruction, 19 rejected inputs/states and two drained runtimes PASS')
}
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
