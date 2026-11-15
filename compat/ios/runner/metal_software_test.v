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
	if os.args.len == 3 && os.args[1] == '--software-metal-blit-reject' {
		mode := os.args[2].int(); assert mode >= 0 && mode < 10
		objc_start(); sm_test_reject_case(mode); exit(0)
	}
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
	names := ['sum', 'float_sum', 'bad_flags', 'bad_access', 'bad_slot', 'bad_builtin', 'divide', 'empty', 'indexed_sum', 'address_space_sum', 'cast_constant_store', 'cast_constant_view_store', 'max', 'float_max', 'int_float', 'float_int', 'negate', 'frozen', 'flagged_sum', 'frozen_sum', 'disjoint', 'disjoint_frozen', 'samesign', 'samesign_frozen', 'cast_trunc', 'cast_trunc_frozen', 'cast_zext', 'cast_zext_frozen', 'constant_lane', 'constant_lane_frozen', 'vector_update', 'vector_update_undef', 'vector_update_frozen', 'vector_shuffle', 'vector_shuffle_undef', 'vector_shuffle_frozen', 'vector_freeze', 'vector_freeze_undef_index', 'vector_freeze_old_undef', 'vector_freeze_old_poison', 'vector_select', 'vector_select_poison', 'vector_select_frozen_condition', 'vector_select_undef_condition', 'vector_select_old', 'vector_lane_select', 'vector_lane_select_poison', 'vector_lane_select_undef', 'vector_lane_select_frozen', 'vector_lane_select_old', 'vector_lane_select_all_poison', 'vector_compare', 'vector_compare_poison', 'vector_compare_undef', 'vector_compare_frozen', 'vector_compare_old', 'vector_compare_samesign', 'vector_compare_constant', 'vector_binary_0_0', 'vector_binary_0_1', 'vector_binary_0_2', 'vector_binary_0_3', 'vector_binary_1_0', 'vector_binary_1_1', 'vector_binary_1_2', 'vector_binary_1_3', 'vector_binary_2_0', 'vector_binary_2_1', 'vector_binary_2_2', 'vector_binary_2_3', 'vector_binary_3_0', 'vector_binary_3_1', 'vector_binary_4_0', 'vector_binary_4_1', 'vector_binary_5_0', 'vector_binary_6_0', 'vector_binary_7_0', 'vector_binary_7_1', 'vector_binary_7_2', 'vector_binary_7_3', 'vector_binary_8_0', 'vector_binary_8_1', 'vector_binary_9_0', 'vector_binary_9_1', 'vector_binary_10_0', 'vector_binary_11_0', 'vector_binary_11_1', 'vector_binary_12_0', 'vector_binary_poison', 'vector_binary_undef', 'vector_binary_frozen', 'vector_binary_sources', 'vector_binary_divide', 'vector_binary_signed_divide', 'vector_binary_signed_rem', 'vector_binary_overshift', 'vector_binary_chain', 'vector_fneg_half_raw', 'vector_fneg_half_poison', 'vector_fneg_half_undef', 'vector_fneg_half_source', 'vector_fneg_half_result', 'vector_fneg_half_old', 'vector_fneg_half_double', 'vector_fneg_half_chain', 'vector_fneg_float_raw', 'vector_fneg_float_poison', 'vector_fneg_float_undef', 'vector_fneg_float_source', 'vector_fneg_float_result', 'vector_fneg_float_old', 'vector_fneg_float_double', 'vector_fneg_float_chain', 'vector_fp_half_0_raw', 'vector_fp_half_0_poison', 'vector_fp_half_0_undef', 'vector_fp_half_0_source_left', 'vector_fp_half_0_source_right', 'vector_fp_half_0_result', 'vector_fp_half_0_old', 'vector_fp_half_0_chain', 'vector_fp_half_1_raw', 'vector_fp_half_1_poison', 'vector_fp_half_1_undef', 'vector_fp_half_1_source_left', 'vector_fp_half_1_source_right', 'vector_fp_half_1_result', 'vector_fp_half_1_old', 'vector_fp_half_1_chain', 'vector_fp_half_2_raw', 'vector_fp_half_2_poison', 'vector_fp_half_2_undef', 'vector_fp_half_2_source_left', 'vector_fp_half_2_source_right', 'vector_fp_half_2_result', 'vector_fp_half_2_old', 'vector_fp_half_2_chain', 'vector_fp_half_3_raw', 'vector_fp_half_3_poison', 'vector_fp_half_3_undef', 'vector_fp_half_3_source_left', 'vector_fp_half_3_source_right', 'vector_fp_half_3_result', 'vector_fp_half_3_old', 'vector_fp_half_3_chain', 'vector_fp_half_4_raw', 'vector_fp_half_4_poison', 'vector_fp_half_4_undef', 'vector_fp_half_4_source_left', 'vector_fp_half_4_source_right', 'vector_fp_half_4_result', 'vector_fp_half_4_old', 'vector_fp_half_4_chain', 'vector_fp_float_0_raw', 'vector_fp_float_0_poison', 'vector_fp_float_0_undef', 'vector_fp_float_0_source_left', 'vector_fp_float_0_source_right', 'vector_fp_float_0_result', 'vector_fp_float_0_old', 'vector_fp_float_0_chain', 'vector_fp_float_1_raw', 'vector_fp_float_1_poison', 'vector_fp_float_1_undef', 'vector_fp_float_1_source_left', 'vector_fp_float_1_source_right', 'vector_fp_float_1_result', 'vector_fp_float_1_old', 'vector_fp_float_1_chain', 'vector_fp_float_2_raw', 'vector_fp_float_2_poison', 'vector_fp_float_2_undef', 'vector_fp_float_2_source_left', 'vector_fp_float_2_source_right', 'vector_fp_float_2_result', 'vector_fp_float_2_old', 'vector_fp_float_2_chain', 'vector_fp_float_3_raw', 'vector_fp_float_3_poison', 'vector_fp_float_3_undef', 'vector_fp_float_3_source_left', 'vector_fp_float_3_source_right', 'vector_fp_float_3_result', 'vector_fp_float_3_old', 'vector_fp_float_3_chain', 'vector_fp_float_4_raw', 'vector_fp_float_4_poison', 'vector_fp_float_4_undef', 'vector_fp_float_4_source_left', 'vector_fp_float_4_source_right', 'vector_fp_float_4_result', 'vector_fp_float_4_old', 'vector_fp_float_4_chain', 'vector_ic_64_1_0_0_raw', 'vector_ic_64_1_0_0_poison', 'vector_ic_64_1_0_0_undef', 'vector_ic_64_1_0_0_source', 'vector_ic_64_1_0_0_result', 'vector_ic_64_1_0_0_old', 'vector_ic_64_1_0_0_chain', 'vector_ic_64_1_0_1_raw', 'vector_ic_64_1_0_1_poison', 'vector_ic_64_1_0_1_undef', 'vector_ic_64_1_0_1_source', 'vector_ic_64_1_0_1_result', 'vector_ic_64_1_0_1_old', 'vector_ic_64_1_0_1_chain', 'vector_ic_64_1_0_2_raw', 'vector_ic_64_1_0_2_poison', 'vector_ic_64_1_0_2_undef', 'vector_ic_64_1_0_2_source', 'vector_ic_64_1_0_2_result', 'vector_ic_64_1_0_2_old', 'vector_ic_64_1_0_2_chain', 'vector_ic_64_1_0_3_raw', 'vector_ic_64_1_0_3_poison', 'vector_ic_64_1_0_3_undef', 'vector_ic_64_1_0_3_source', 'vector_ic_64_1_0_3_result', 'vector_ic_64_1_0_3_old', 'vector_ic_64_1_0_3_chain', 'vector_ic_32_8_0_0_raw', 'vector_ic_32_8_0_0_poison', 'vector_ic_32_8_0_0_undef', 'vector_ic_32_8_0_0_source', 'vector_ic_32_8_0_0_result', 'vector_ic_32_8_0_0_old', 'vector_ic_32_8_0_0_chain', 'vector_ic_32_8_0_1_raw', 'vector_ic_32_8_0_1_poison', 'vector_ic_32_8_0_1_undef', 'vector_ic_32_8_0_1_source', 'vector_ic_32_8_0_1_result', 'vector_ic_32_8_0_1_old', 'vector_ic_32_8_0_1_chain', 'vector_ic_32_8_0_2_raw', 'vector_ic_32_8_0_2_poison', 'vector_ic_32_8_0_2_undef', 'vector_ic_32_8_0_2_source', 'vector_ic_32_8_0_2_result', 'vector_ic_32_8_0_2_old', 'vector_ic_32_8_0_2_chain', 'vector_ic_32_8_0_3_raw', 'vector_ic_32_8_0_3_poison', 'vector_ic_32_8_0_3_undef', 'vector_ic_32_8_0_3_source', 'vector_ic_32_8_0_3_result', 'vector_ic_32_8_0_3_old', 'vector_ic_32_8_0_3_chain', 'vector_ic_1_64_1_0_raw', 'vector_ic_1_64_1_0_poison', 'vector_ic_1_64_1_0_undef', 'vector_ic_1_64_1_0_source', 'vector_ic_1_64_1_0_result', 'vector_ic_1_64_1_0_old', 'vector_ic_1_64_1_0_chain', 'vector_ic_1_64_1_1_raw', 'vector_ic_1_64_1_1_poison', 'vector_ic_1_64_1_1_undef', 'vector_ic_1_64_1_1_source', 'vector_ic_1_64_1_1_result', 'vector_ic_1_64_1_1_old', 'vector_ic_1_64_1_1_chain', 'vector_ic_1_64_2_0_raw', 'vector_ic_1_64_2_0_poison', 'vector_ic_1_64_2_0_undef', 'vector_ic_1_64_2_0_source', 'vector_ic_1_64_2_0_result', 'vector_ic_1_64_2_0_old', 'vector_ic_1_64_2_0_chain', 'vector_ic_8_32_1_0_raw', 'vector_ic_8_32_1_0_poison', 'vector_ic_8_32_1_0_undef', 'vector_ic_8_32_1_0_source', 'vector_ic_8_32_1_0_result', 'vector_ic_8_32_1_0_old', 'vector_ic_8_32_1_0_chain', 'vector_ic_8_32_1_1_raw', 'vector_ic_8_32_1_1_poison', 'vector_ic_8_32_1_1_undef', 'vector_ic_8_32_1_1_source', 'vector_ic_8_32_1_1_result', 'vector_ic_8_32_1_1_old', 'vector_ic_8_32_1_1_chain', 'vector_ic_8_32_2_0_raw', 'vector_ic_8_32_2_0_poison', 'vector_ic_8_32_2_0_undef', 'vector_ic_8_32_2_0_source', 'vector_ic_8_32_2_0_result', 'vector_ic_8_32_2_0_old', 'vector_ic_8_32_2_0_chain', 'vector_ic_32_64_1_0_raw', 'vector_ic_32_64_1_0_poison', 'vector_ic_32_64_1_0_undef', 'vector_ic_32_64_1_0_source', 'vector_ic_32_64_1_0_result', 'vector_ic_32_64_1_0_old', 'vector_ic_32_64_1_0_chain', 'vector_ic_32_64_1_1_raw', 'vector_ic_32_64_1_1_poison', 'vector_ic_32_64_1_1_undef', 'vector_ic_32_64_1_1_source', 'vector_ic_32_64_1_1_result', 'vector_ic_32_64_1_1_old', 'vector_ic_32_64_1_1_chain', 'vector_ic_32_64_2_0_raw', 'vector_ic_32_64_2_0_poison', 'vector_ic_32_64_2_0_undef', 'vector_ic_32_64_2_0_source', 'vector_ic_32_64_2_0_result', 'vector_ic_32_64_2_0_old', 'vector_ic_32_64_2_0_chain', 'bad_vector_integer_cast', 'bad_vector_fneg', 'bad_vector_binary', 'bad_vector_compare', 'bad_wide_vector_condition', 'bad_vector_freeze', 'bad_shuffle_count', 'bad_lane_count', 'bits', 'bits_frozen', 'funnel', 'extrema', 'abs_keep', 'abs_frozen', 'saturating', 'saturating_convert', 'saturating_convert_frozen', 'saturating_shift', 'saturating_shift_frozen', 'bit_permutation', 'float_sign', 'rounding', 'square_root', 'floating_extrema', 'classification', 'fused', 'scaling', 'number_extrema', 'legacy_extrema', 'polynomial', 'optional_fused', 'default_rounding', 'overflowing', 'frozen_overflowing', 'pair_choices', 'selected_overflowing', 'inserted_overflowing', 'branching', 'byte_fill', 'byte_inline_fill', 'byte_move', 'byte_copy', 'byte_inline_copy', 'looping', 'switching', 'oversized_switch', 'backward_sum', 'bad_vector_bitcast', 'vector_bc_16_0_raw', 'vector_bc_16_0_poison', 'vector_bc_16_0_undef', 'vector_bc_16_0_source', 'vector_bc_16_0_result', 'vector_bc_16_0_old', 'vector_bc_16_0_roundtrip', 'vector_bc_16_0_chain', 'vector_bc_16_1_raw', 'vector_bc_16_1_poison', 'vector_bc_16_1_undef', 'vector_bc_16_1_source', 'vector_bc_16_1_result', 'vector_bc_16_1_old', 'vector_bc_16_1_roundtrip', 'vector_bc_16_1_chain', 'vector_bc_32_0_raw', 'vector_bc_32_0_poison', 'vector_bc_32_0_undef', 'vector_bc_32_0_source', 'vector_bc_32_0_result', 'vector_bc_32_0_old', 'vector_bc_32_0_roundtrip', 'vector_bc_32_0_chain', 'vector_bc_32_1_raw', 'vector_bc_32_1_poison', 'vector_bc_32_1_undef', 'vector_bc_32_1_source', 'vector_bc_32_1_result', 'vector_bc_32_1_old', 'vector_bc_32_1_roundtrip', 'vector_bc_32_1_chain', 'bad_vector_precision', 'vector_pc_16_raw', 'vector_pc_16_poison', 'vector_pc_16_undef', 'vector_pc_16_source', 'vector_pc_16_result', 'vector_pc_16_old', 'vector_pc_16_roundtrip', 'vector_pc_16_chain', 'vector_pc_32_raw', 'vector_pc_32_poison', 'vector_pc_32_undef', 'vector_pc_32_source', 'vector_pc_32_result', 'vector_pc_32_old', 'vector_pc_32_roundtrip', 'vector_pc_32_chain', 'bad_vector_int_float', 'vector_if_1_16_5_raw', 'vector_if_1_16_5_poison', 'vector_if_1_16_5_undef', 'vector_if_1_16_5_source', 'vector_if_1_16_5_result', 'vector_if_1_16_5_old', 'vector_if_1_16_5_bits', 'vector_if_1_16_5_chain', 'vector_if_1_16_6_raw', 'vector_if_1_16_6_poison', 'vector_if_1_16_6_undef', 'vector_if_1_16_6_source', 'vector_if_1_16_6_result', 'vector_if_1_16_6_old', 'vector_if_1_16_6_bits', 'vector_if_1_16_6_chain', 'vector_if_1_32_5_raw', 'vector_if_1_32_6_raw', 'vector_if_8_16_5_raw', 'vector_if_8_16_6_raw', 'vector_if_16_16_5_raw', 'vector_if_16_16_6_raw', 'vector_if_16_32_5_raw', 'vector_if_16_32_6_raw', 'vector_if_32_32_5_raw', 'vector_if_32_32_6_raw', 'vector_if_64_16_5_raw', 'vector_if_64_16_6_raw', 'vector_if_64_32_5_raw', 'vector_if_64_32_5_poison', 'vector_if_64_32_5_undef', 'vector_if_64_32_5_source', 'vector_if_64_32_5_result', 'vector_if_64_32_5_old', 'vector_if_64_32_5_bits', 'vector_if_64_32_5_chain', 'vector_if_64_32_6_raw', 'vector_if_64_32_6_poison', 'vector_if_64_32_6_undef', 'vector_if_64_32_6_source', 'vector_if_64_32_6_result', 'vector_if_64_32_6_old', 'vector_if_64_32_6_bits', 'vector_if_64_32_6_chain', 'bad_vector_float_int', 'vector_fi_16_1_3_raw', 'vector_fi_16_1_3_poison', 'vector_fi_16_1_3_undef', 'vector_fi_16_1_3_source', 'vector_fi_16_1_3_result', 'vector_fi_16_1_3_old', 'vector_fi_16_1_3_chain', 'vector_fi_16_1_3_integer', 'vector_fi_16_1_3_invalid', 'vector_fi_16_1_4_raw', 'vector_fi_16_1_4_poison', 'vector_fi_16_1_4_undef', 'vector_fi_16_1_4_source', 'vector_fi_16_1_4_result', 'vector_fi_16_1_4_old', 'vector_fi_16_1_4_chain', 'vector_fi_16_1_4_integer', 'vector_fi_16_1_4_invalid', 'vector_fi_16_8_3_raw', 'vector_fi_16_8_4_raw', 'vector_fi_16_16_3_raw', 'vector_fi_16_16_4_raw', 'vector_fi_16_64_3_raw', 'vector_fi_16_64_4_raw', 'vector_fi_32_1_3_raw', 'vector_fi_32_1_4_raw', 'vector_fi_32_8_3_raw', 'vector_fi_32_8_4_raw', 'vector_fi_32_32_3_raw', 'vector_fi_32_32_4_raw', 'vector_fi_32_64_3_raw', 'vector_fi_32_64_3_poison', 'vector_fi_32_64_3_undef', 'vector_fi_32_64_3_source', 'vector_fi_32_64_3_result', 'vector_fi_32_64_3_old', 'vector_fi_32_64_3_chain', 'vector_fi_32_64_3_integer', 'vector_fi_32_64_3_invalid', 'vector_fi_32_64_4_raw', 'vector_fi_32_64_4_poison', 'vector_fi_32_64_4_undef', 'vector_fi_32_64_4_source', 'vector_fi_32_64_4_result', 'vector_fi_32_64_4_old', 'vector_fi_32_64_4_chain', 'vector_fi_32_64_4_integer', 'vector_fi_32_64_4_invalid', 'bad_vector_sign', 'vector_si_16_0_raw', 'vector_si_16_0_left', 'vector_si_16_0_right', 'vector_si_16_0_undef', 'vector_si_16_0_signundef', 'vector_si_16_0_source', 'vector_si_16_0_signsource', 'vector_si_16_0_result', 'vector_si_16_0_old', 'vector_si_16_0_chain', 'vector_si_16_1_raw', 'vector_si_16_1_left', 'vector_si_16_1_right', 'vector_si_16_1_undef', 'vector_si_16_1_signundef', 'vector_si_16_1_source', 'vector_si_16_1_signsource', 'vector_si_16_1_result', 'vector_si_16_1_old', 'vector_si_16_1_chain', 'vector_si_32_0_raw', 'vector_si_32_0_left', 'vector_si_32_0_right', 'vector_si_32_0_undef', 'vector_si_32_0_signundef', 'vector_si_32_0_source', 'vector_si_32_0_signsource', 'vector_si_32_0_result', 'vector_si_32_0_old', 'vector_si_32_0_chain', 'vector_si_32_1_raw', 'vector_si_32_1_left', 'vector_si_32_1_right', 'vector_si_32_1_undef', 'vector_si_32_1_signundef', 'vector_si_32_1_source', 'vector_si_32_1_signsource', 'vector_si_32_1_result', 'vector_si_32_1_old', 'vector_si_32_1_chain', 'bad_vector_round', 'vector_rd_16_0_raw', 'vector_rd_16_0_poison', 'vector_rd_16_0_undef', 'vector_rd_16_0_source', 'vector_rd_16_0_result', 'vector_rd_16_0_old', 'vector_rd_16_0_chain', 'vector_rd_16_1_raw', 'vector_rd_16_1_poison', 'vector_rd_16_1_undef', 'vector_rd_16_1_source', 'vector_rd_16_1_result', 'vector_rd_16_1_old', 'vector_rd_16_1_chain', 'vector_rd_16_2_raw', 'vector_rd_16_2_poison', 'vector_rd_16_2_undef', 'vector_rd_16_2_source', 'vector_rd_16_2_result', 'vector_rd_16_2_old', 'vector_rd_16_2_chain', 'vector_rd_16_3_raw', 'vector_rd_16_3_poison', 'vector_rd_16_3_undef', 'vector_rd_16_3_source', 'vector_rd_16_3_result', 'vector_rd_16_3_old', 'vector_rd_16_3_chain', 'vector_rd_16_4_raw', 'vector_rd_16_4_poison', 'vector_rd_16_4_undef', 'vector_rd_16_4_source', 'vector_rd_16_4_result', 'vector_rd_16_4_old', 'vector_rd_16_4_chain', 'vector_rd_16_5_raw', 'vector_rd_16_5_poison', 'vector_rd_16_5_undef', 'vector_rd_16_5_source', 'vector_rd_16_5_result', 'vector_rd_16_5_old', 'vector_rd_16_5_chain', 'vector_rd_16_6_raw', 'vector_rd_16_6_poison', 'vector_rd_16_6_undef', 'vector_rd_16_6_source', 'vector_rd_16_6_result', 'vector_rd_16_6_old', 'vector_rd_16_6_chain', 'vector_rd_32_0_raw', 'vector_rd_32_0_poison', 'vector_rd_32_0_undef', 'vector_rd_32_0_source', 'vector_rd_32_0_result', 'vector_rd_32_0_old', 'vector_rd_32_0_chain', 'vector_rd_32_1_raw', 'vector_rd_32_1_poison', 'vector_rd_32_1_undef', 'vector_rd_32_1_source', 'vector_rd_32_1_result', 'vector_rd_32_1_old', 'vector_rd_32_1_chain', 'vector_rd_32_2_raw', 'vector_rd_32_2_poison', 'vector_rd_32_2_undef', 'vector_rd_32_2_source', 'vector_rd_32_2_result', 'vector_rd_32_2_old', 'vector_rd_32_2_chain', 'vector_rd_32_3_raw', 'vector_rd_32_3_poison', 'vector_rd_32_3_undef', 'vector_rd_32_3_source', 'vector_rd_32_3_result', 'vector_rd_32_3_old', 'vector_rd_32_3_chain', 'vector_rd_32_4_raw', 'vector_rd_32_4_poison', 'vector_rd_32_4_undef', 'vector_rd_32_4_source', 'vector_rd_32_4_result', 'vector_rd_32_4_old', 'vector_rd_32_4_chain', 'vector_rd_32_5_raw', 'vector_rd_32_5_poison', 'vector_rd_32_5_undef', 'vector_rd_32_5_source', 'vector_rd_32_5_result', 'vector_rd_32_5_old', 'vector_rd_32_5_chain', 'vector_rd_32_6_raw', 'vector_rd_32_6_poison', 'vector_rd_32_6_undef', 'vector_rd_32_6_source', 'vector_rd_32_6_result', 'vector_rd_32_6_old', 'vector_rd_32_6_chain', 'no_metadata']
	assert names[names.len - 1] == 'no_metadata'
	mut source := strings.new_builder(8192)
	defer { unsafe { source.free() } }
	source.write_string('target datalayout = "e-p:64:64"\n')
	source.write_string('declare void @llvm.memset.p1.i64(ptr addrspace(1), i8, i64, i1 immarg)\n')
	source.write_string('declare <2 x half> @llvm.fabs.v2f16(<2 x half>)\n declare <2 x half> @llvm.copysign.v2f16(<2 x half>, <2 x half>)\n declare <2 x float> @llvm.fabs.v2f32(<2 x float>)\n declare <2 x float> @llvm.copysign.v2f32(<2 x float>, <2 x float>)\n')
	source.write_string('declare void @llvm.memset.inline.p1.i64(ptr addrspace(1), i8, i64, i1 immarg)\n')
	source.write_string('declare void @llvm.memcpy.p1.p2.i64(ptr addrspace(1), ptr addrspace(2), i64, i1 immarg)\n')
	source.write_string('declare void @llvm.memcpy.inline.p1.p2.i64(ptr addrspace(1), ptr addrspace(2), i64, i1 immarg)\n')
	source.write_string('declare void @llvm.memmove.p1.p2.i64(ptr addrspace(1), ptr addrspace(2), i64, i1 immarg)\ndeclare void @llvm.memmove.p1.p1.i64(ptr addrspace(1), ptr addrspace(1), i64, i1 immarg)\n')
	source.write_string('declare i32 @llvm.ctpop.i32(i32)\ndeclare i32 @llvm.bitreverse.i32(i32)\ndeclare i32 @llvm.bswap.i32(i32)\ndeclare i32 @llvm.ctlz.i32(i32, i1 immarg)\ndeclare i32 @llvm.cttz.i32(i32, i1 immarg)\n')
	source.write_string('declare i32 @llvm.fshl.i32(i32, i32, i32)\ndeclare i32 @llvm.fshr.i32(i32, i32, i32)\n')
	for op in ['smin', 'smax', 'umin', 'umax'] { source.write_string('declare i32 @llvm.${op}.i32(i32, i32)\n') }
	source.write_string('declare i32 @llvm.abs.i32(i32, i1 immarg)\n')
	for op in ['sadd', 'uadd', 'ssub', 'usub'] { source.write_string('declare i32 @llvm.${op}.sat.i32(i32, i32)\n') }
	for op in ['sshl', 'ushl'] { source.write_string('declare i32 @llvm.${op}.sat.i32(i32, i32)\n') }
	for op in ['pext', 'pdep'] { source.write_string('declare i32 @llvm.${op}.i32(i32, i32)\n') }
	for bits in [32, 64]! { source.write_string('declare i${bits} @llvm.clmul.i${bits}(i${bits}, i${bits})\n') }
	for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] { source.write_string('declare {i32, i1} @llvm.${op}.with.overflow.i32(i32, i32)\n') }
	source.write_string('declare {i64, i1} @llvm.umul.with.overflow.i64(i64, i64)\n')
	for typ, bits in {'half': 16, 'float': 32} {
		source.write_string('declare ${typ} @llvm.fabs.f${bits}(${typ})\ndeclare ${typ} @llvm.copysign.f${bits}(${typ}, ${typ})\n')
		source.write_string('declare ${typ} @llvm.sqrt.f${bits}(${typ})\n')
		source.write_string('declare ${typ} @llvm.fma.f${bits}(${typ}, ${typ}, ${typ})\n')
		source.write_string('declare ${typ} @llvm.fmuladd.f${bits}(${typ}, ${typ}, ${typ})\n')
		source.write_string('declare ${typ} @llvm.ldexp.f${bits}.i32(${typ}, i32)\n')
		source.write_string('declare i1 @llvm.is.fpclass.f${bits}(${typ}, i32 immarg)\n')
		for op in ['minimum', 'maximum', 'minimumnum', 'maximumnum', 'minnum', 'maxnum'] { source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ}, ${typ})\n') }
		for op in ['floor', 'ceil', 'trunc', 'round', 'roundeven', 'rint', 'nearbyint'] { source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ})\n') }
	}
 for bits in [16, 32] { for op in ['floor', 'ceil', 'trunc', 'round', 'roundeven', 'rint', 'nearbyint'] { t := if bits == 16 { 'half' } else { 'float' }; source.write_string('declare <2 x ${t}> @llvm.${op}.v2f${bits}(<2 x ${t}>)\n') } }
	for bits in [16, 32] { for op in ['fptosi', 'fptoui'] { typ := if bits == 16 { 'half' } else { 'float' }; source.write_string('declare i32 @llvm.${op}.sat.i32.f${bits}(${typ})\n') } }
	for name in names {

		if name in ['vector_update', 'vector_update_undef', 'vector_update_frozen'] {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %jp = getelementptr i32, ptr addrspace(2) %a, i64 1\n %qp = getelementptr i32, ptr addrspace(2) %b, i64 1\n %j = load i32, ptr addrspace(2) %jp, align 4\n %q = load i32, ptr addrspace(2) %qp, align 4\n %fx = bitcast i32 %x to float\n %fy = bitcast i32 %y to float\n %hx0 = trunc i32 %x to i16\n %hy0 = trunc i32 %y to i16\n %hx = bitcast i16 %hx0 to half\n %hy = bitcast i16 %hy0 to half\n')
			for k, t in ['i32', 'float', 'half'] {
				x := if k == 0 { '%x' } else if k == 1 { '%fx' } else { '%hx' }
				y := if k == 0 { '%y' } else if k == 1 { '%fy' } else { '%hy' }
				initial := if name.ends_with('_undef') { 'undef' } else { 'poison' }
				source.write_string('%a${k} = insertelement <4 x ${t}> ${initial}, ${t} ${x}, i32 %j\n %b${k} = insertelement <4 x ${t}> %a${k}, ${t} ${y}, i32 %q\n %old${k} = extractelement <4 x ${t}> %a${k}, i32 %j\n %new${k} = extractelement <4 x ${t}> %b${k}, i32 %q\n')
				for l, v in ['old', 'new'] {
					if name.ends_with('_frozen') { source.write_string('%f${k}${l} = freeze ${t} %${v}${k}\n') }
					value := if name.ends_with('_frozen') { '%f${k}${l}' } else { '%${v}${k}' }
					if k == 1 { source.write_string('%w${k}${l} = bitcast float ${value} to i32\n') }
					if k == 2 { source.write_string('%h${l} = bitcast half ${value} to i16\n %w${k}${l} = zext i16 %h${l} to i32\n') }
					word := if k == 0 { value } else { '%w${k}${l}' }
					source.write_string('%d${k}${l} = getelementptr i32, ptr addrspace(1) %out, i64 ${k * 2 + l}\n store i32 ${word}, ptr addrspace(1) %d${k}${l}, align 4\n')
				}
			}
			source.write_string('ret void }\n'); continue
		}





		if name == 'bad_vector_fneg' {
			source.write_string('define void @bad_vector_fneg(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %v = fneg nnan <2 x float> zeroinitializer\n ret void }\n'); continue
		}
		if name == 'bad_vector_integer_cast' { source.write_string('define void @bad_vector_integer_cast(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %n = bitcast <2 x i64> zeroinitializer to <2 x double>\n ret void }\n'); continue }
		if name.starts_with('vector_ic_') { sm_integer_vector_cast_fixture(mut source, name); continue }
		if name == 'bad_vector_bitcast' { source.write_string('define void @bad_vector_bitcast(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %n = bitcast <4 x i8> zeroinitializer to <2 x half>\n ret void }\n'); continue }
		if name == 'bad_vector_precision' { source.write_string('define void @bad_vector_precision(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %n = fpext nnan <2 x half> zeroinitializer to <2 x float>\n ret void }\n'); continue }
		if name == 'bad_vector_int_float' { source.write_string('define void @bad_vector_int_float(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %n = uitofp nneg <2 x i32> zeroinitializer to <2 x float>\n ret void }\n'); continue }
		if name == 'bad_vector_float_int' { source.write_string('define void @bad_vector_float_int(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %n = fptoui <2 x double> zeroinitializer to <2 x i32>\n ret void }\n'); continue }
		if name.starts_with('vector_fi_') { sm_vector_float_int_fixture(mut source, name); continue }
		if name == 'bad_vector_sign' { source.write_string('define void @bad_vector_sign(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %n = call nnan <2 x float> @llvm.fabs.v2f32(<2 x float> zeroinitializer)\n ret void }\n'); continue }
		if name.starts_with('vector_rd_') { sm_vector_round_fixture(mut source, name); continue }
		if name == 'bad_vector_round' { source.write_string('define void @bad_vector_round(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %r = call nnan <2 x float> @llvm.roundeven.v2f32(<2 x float> zeroinitializer)\n ret void }\n'); continue }
		if name.starts_with('vector_si_') { sm_vector_sign_fixture(mut source, name); continue }
		if name.starts_with('vector_if_') { sm_vector_int_float_fixture(mut source, name); continue }
		if name.starts_with('vector_pc_') { sm_vector_precision_fixture(mut source, name); continue }
		if name.starts_with('vector_bc_') { sm_vector_bitcast_fixture(mut source, name); continue }
		if name.starts_with('vector_fp_') { sm_vector_float_fixture(mut source, name); continue }
		if name.starts_with('vector_fneg_') { sm_vector_fneg_fixture(mut source, name); continue }
		if name == 'bad_vector_binary' {
			source.write_string('define void @bad_vector_binary(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { store i32 17, ptr addrspace(1) %out\n %v = fadd nnan <2 x float> zeroinitializer, zeroinitializer\n ret void }\n'); continue
		}
		if name.starts_with('vector_binary') {
			binary_parts := name.split('_'); binary_op := if binary_parts.len == 4 && binary_parts[2][0].is_digit() { binary_parts[2].int() } else if name == 'vector_binary_sources' || name == 'vector_binary_divide' { 3 } else if name == 'vector_binary_signed_divide' { 4 } else if name == 'vector_binary_signed_rem' { 6 } else if name == 'vector_binary_overshift' { 7 } else { 0 }
			binary_flags := if binary_parts.len == 4 && binary_parts[2][0].is_digit() { binary_parts[3].int() } else if name == 'vector_binary_frozen' { 1 } else { 0 }
			binary_left := if name in ['vector_binary_undef', 'vector_binary_sources'] { 'undef' } else if name == 'vector_binary_poison' { 'poison' } else if name in ['vector_binary_signed_divide', 'vector_binary_signed_rem'] { '<i32 7, i32 2147483648>' } else { '<i32 7, i32 8>' }
			binary_right := if name == 'vector_binary_divide' { '<i32 1, i32 0>' } else if name in ['vector_binary_signed_divide', 'vector_binary_signed_rem'] { '<i32 1, i32 4294967295>' } else if name == 'vector_binary_overshift' { '<i32 1, i32 32>' } else { '<i32 1, i32 2>' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %rp = getelementptr i32, ptr addrspace(2) %b, i64 1\n %r = load i32, ptr addrspace(2) %rp, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x i32> ${binary_left}, i32 %x, i32 0\n %b0 = insertelement <2 x i32> ${binary_right}, i32 %y, i32 0\n')
			if name == 'vector_binary_sources' { source.write_string('%aa = freeze <2 x i32> %a0\n %bb = freeze <2 x i32> %b0\n') }
			source.write_string('%v = ${sm_vector_binary_instruction(binary_op, binary_flags)} <2 x i32> ${if name == 'vector_binary_sources' { '%aa, %bb' } else { '%a0, %b0' }}\n %f = freeze <2 x i32> %v\n %c = icmp ne <2 x i32> %f, zeroinitializer\n %s = select <2 x i1> %c, <2 x i32> %f, <2 x i32> zeroinitializer\n')
			if name == 'vector_binary_chain' { source.write_string('%u = insertelement <2 x i32> %v, i32 99, i32 1\n %h = shufflevector <2 x i32> %u, <2 x i32> %v, <2 x i32> <i32 1, i32 2>\n %n = add <2 x i32> %h, <i32 1, i32 1>\n') }
			source.write_string('%old = extractelement <2 x i32> %f, i32 %r\n %d = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %old, ptr addrspace(1) %d, align 4\n %new = extractelement <2 x i32> ${if name == 'vector_binary_chain' { '%n' } else if name == 'vector_binary_frozen' { '%s' } else { '%v' }}, i32 %r\n %e = getelementptr i32, ptr addrspace(1) %out, i64 2\n store i32 %new, ptr addrspace(1) %e, align 4\n ret void }\n'); continue
		}
		if name == 'bad_vector_compare' {
			source.write_string('define void @bad_vector_compare(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { store i32 17, ptr addrspace(1) %out\n %c = fcmp nnan oeq <2 x float> zeroinitializer, zeroinitializer\n ret void }\n'); continue
		}
		if name.starts_with('vector_compare') {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %rp = getelementptr i32, ptr addrspace(2) %b, i64 1\n %r = load i32, ptr addrspace(2) %rp, align 4\n %fx = bitcast i32 %x to float\n %fy = bitcast i32 %y to float\n %hx0 = trunc i32 %x to i16\n %hy0 = trunc i32 %y to i16\n %hx = bitcast i16 %hx0 to half\n %hy = bitcast i16 %hy0 to half\n')
			compare_base := if name.ends_with('_undef') { 'undef' } else if name.ends_with('_poison') || name.ends_with('_frozen') || name.ends_with('_old') { 'poison' } else { 'zeroinitializer' }
			for k, t in ['i32', 'float', 'half'] {
				compare_x := if k == 0 { '%x' } else if k == 1 { '%fx' } else { '%hx' }; compare_y := if k == 0 { '%y' } else if k == 1 { '%fy' } else { '%hy' }
				compare_op := if k == 0 { if name.ends_with('_samesign') { 'icmp samesign eq' } else { 'icmp eq' } } else if name.ends_with('_constant') { 'fcmp true' } else { 'fcmp oeq' }
				source.write_string('%a${k} = insertelement <2 x ${t}> ${compare_base}, ${t} ${compare_x}, i32 0\n %b${k} = insertelement <2 x ${t}> zeroinitializer, ${t} ${compare_y}, i32 0\n')
				compare_left := if name.ends_with('_constant') { if k == 0 { 'zeroinitializer' } else { 'undef' } } else { '%a${k}' }
				compare_right := if name.ends_with('_constant') { if k == 0 { 'zeroinitializer' } else { 'poison' } } else { '%b${k}' }
				compare_mask := if name.ends_with('_frozen') { '%f${k}' } else { '%c${k}' }; compare_old := if name.ends_with('_old') { '%c${k}' } else { '%f${k}' }
				source.write_string('%c${k} = ${compare_op} <2 x ${t}> ${compare_left}, ${compare_right}\n %f${k} = freeze <2 x i1> %c${k}\n %s${k} = select <2 x i1> ${compare_mask}, <2 x i32> <i32 7, i32 7>, <2 x i32> <i32 11, i32 11>\n %old${k} = extractelement <2 x i1> ${compare_old}, i32 %r\n %word${k} = zext i1 %old${k} to i32\n %d${k} = getelementptr i32, ptr addrspace(1) %out, i64 ${k * 2}\n store i32 %word${k}, ptr addrspace(1) %d${k}, align 4\n %new${k} = extractelement <2 x i32> %s${k}, i32 %r\n %e${k} = getelementptr i32, ptr addrspace(1) %out, i64 ${k * 2 + 1}\n store i32 %new${k}, ptr addrspace(1) %e${k}, align 4\n')
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'bad_wide_vector_condition' {
			source.write_string('define void @bad_wide_vector_condition(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { store i32 17, ptr addrspace(1) %out, align 4\n %s = select <17 x i1> zeroinitializer, <17 x i32> zeroinitializer, <17 x i32> poison\n ret void }\n'); continue
		}
		if name in ['vector_select', 'vector_select_poison', 'vector_select_frozen_condition', 'vector_select_undef_condition', 'vector_select_old', 'vector_lane_select', 'vector_lane_select_poison', 'vector_lane_select_undef', 'vector_lane_select_frozen', 'vector_lane_select_old', 'vector_lane_select_all_poison'] {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %cp = getelementptr i32, ptr addrspace(2) %a, i64 1\n %rp = getelementptr i32, ptr addrspace(2) %b, i64 1\n %ci = load i32, ptr addrspace(2) %cp, align 4\n %c = trunc i32 %ci to i1\n %r = load i32, ptr addrspace(2) %rp, align 4\n %fx = bitcast i32 %x to float\n %fy = bitcast i32 %y to float\n %hx0 = trunc i32 %x to i16\n %hy0 = trunc i32 %y to i16\n %hx = bitcast i16 %hx0 to half\n %hy = bitcast i16 %hy0 to half\n')
			if name.ends_with('_frozen_condition') { source.write_string('%fc = freeze i1 poison\n') }

			lane_select := name.starts_with('vector_lane_select')
			condition_type := if lane_select { '<2 x i1>' } else { 'i1' }
			if lane_select && !name.ends_with('_all_poison') {
				condition_base := if name.ends_with('_poison') { 'poison' } else if name.ends_with('_undef') || name.ends_with('_frozen') { 'undef' } else { 'zeroinitializer' }
				source.write_string('%m0 = insertelement <2 x i1> ${condition_base}, i1 %c, i32 0\n')
				if name.ends_with('_frozen') { source.write_string('%mc = freeze <2 x i1> %m0\n') }
				else if name.ends_with('_poison') || name.ends_with('_undef') { source.write_string('%mc = select i1 true, <2 x i1> %m0, <2 x i1> poison\n') }
				else { source.write_string('%high = lshr i32 %ci, 1\n %c1 = trunc i32 %high to i1\n %mc = insertelement <2 x i1> %m0, i1 %c1, i32 1\n') }
			}
			condition := if lane_select { if name.ends_with('_all_poison') { 'poison' } else { '%mc' } } else if name.ends_with('_undef_condition') { 'undef' } else if name.ends_with('_frozen_condition') { '%fc' } else if name.ends_with('_poison') { 'poison' } else { '%c' }
			for k, t in ['i32', 'float', 'half'] {
				x := if k == 0 { '%x' } else if k == 1 { '%fx' } else { '%hx' }; y := if k == 0 { '%y' } else if k == 1 { '%fy' } else { '%hy' }
				old := if name.ends_with('_old') { '%s${k}' } else { '%f${k}' }
				source.write_string('%a${k} = insertelement <2 x ${t}> undef, ${t} ${x}, i32 0\n %b${k} = insertelement <2 x ${t}> poison, ${t} ${y}, i32 1\n %s${k} = select ${condition_type} ${condition}, <2 x ${t}> %a${k}, <2 x ${t}> %b${k}\n %f${k} = freeze <2 x ${t}> %s${k}\n %z${k} = select ${condition_type} ${condition}, <2 x ${t}> %f${k}, <2 x ${t}> %s${k}\n %u${k} = insertelement <2 x ${t}> %z${k}, ${t} ${y}, i32 0\n %t${k} = shufflevector <2 x ${t}> %u${k}, <2 x ${t}> %f${k}, <2 x i32> <i32 1, i32 0>\n %old${k} = extractelement <2 x ${t}> ${old}, i32 %r\n %new${k} = extractelement <2 x ${t}> %t${k}, i32 %r\n')
				for l, v in ['old', 'new'] {
					value := '%${v}${k}'
					if k == 1 { source.write_string('%w${k}${l} = bitcast float ${value} to i32\n') }
					if k == 2 { source.write_string('%h${l} = bitcast half ${value} to i16\n %w${k}${l} = zext i16 %h${l} to i32\n') }
					word := if k == 0 { value } else { '%w${k}${l}' }
					source.write_string('%d${k}${l} = getelementptr i32, ptr addrspace(1) %out, i64 ${k * 2 + l}\n store i32 ${word}, ptr addrspace(1) %d${k}${l}, align 4\n')
				}
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'bad_vector_freeze' {
			source.write_string('define void @bad_vector_freeze(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { store i32 17, ptr addrspace(1) %out, align 4\n %f = freeze <17 x i32> poison\n ret void }\n'); continue
		}
		if name in ['vector_freeze', 'vector_freeze_undef_index', 'vector_freeze_old_undef', 'vector_freeze_old_poison'] {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %jp = getelementptr i32, ptr addrspace(2) %a, i64 1\n %rp = getelementptr i32, ptr addrspace(2) %b, i64 1\n %j = load i32, ptr addrspace(2) %jp, align 4\n %r = load i32, ptr addrspace(2) %rp, align 4\n %fx = bitcast i32 %x to float\n %fy = bitcast i32 %y to float\n %hx0 = trunc i32 %x to i16\n %hy0 = trunc i32 %y to i16\n %hx = bitcast i16 %hx0 to half\n %hy = bitcast i16 %hy0 to half\n')
			for k, t in ['i32', 'float', 'half'] {
				x := if k == 0 { '%x' } else if k == 1 { '%fx' } else { '%hx' }; y := if k == 0 { '%y' } else if k == 1 { '%fy' } else { '%hy' }
				index := if name.ends_with('_undef_index') { 'undef' } else { '%j' }
				old := if name.ends_with('_old_undef') { '%a${k}' } else if name.ends_with('_old_poison') { '%s${k}' } else { '%f${k}' }
				source.write_string('%a${k} = insertelement <4 x ${t}> undef, ${t} ${x}, i32 ${index}\n %s${k} = shufflevector <4 x ${t}> %a${k}, <4 x ${t}> poison, <4 x i32> <i32 0, i32 1, i32 poison, i32 4>\n %f${k} = freeze <4 x ${t}> %s${k}\n %g${k} = freeze <4 x ${t}> %f${k}\n %b${k} = insertelement <4 x ${t}> %g${k}, ${t} ${y}, i32 0\n %u${k} = shufflevector <4 x ${t}> %b${k}, <4 x ${t}> %f${k}, <4 x i32> <i32 0, i32 4, i32 1, i32 5>\n %old${k} = extractelement <4 x ${t}> ${old}, i32 %r\n %new${k} = extractelement <4 x ${t}> %u${k}, i32 %r\n')
				for l, v in ['old', 'new'] {
					value := '%${v}${k}'
					if k == 1 { source.write_string('%w${k}${l} = bitcast float ${value} to i32\n') }
					if k == 2 { source.write_string('%h${l} = bitcast half ${value} to i16\n %w${k}${l} = zext i16 %h${l} to i32\n') }
					word := if k == 0 { value } else { '%w${k}${l}' }
					source.write_string('%d${k}${l} = getelementptr i32, ptr addrspace(1) %out, i64 ${k * 2 + l}\n store i32 ${word}, ptr addrspace(1) %d${k}${l}, align 4\n')
				}
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'bad_shuffle_count' {
			source.write_string('define void @bad_shuffle_count(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { store i32 17, ptr addrspace(1) %out, align 4\n %v = shufflevector <2 x i32> zeroinitializer, <2 x i32> poison, <17 x i32> zeroinitializer\n ret void }\n'); continue
		}
		if name in ['vector_shuffle', 'vector_shuffle_undef', 'vector_shuffle_frozen'] {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %jp = getelementptr i32, ptr addrspace(2) %a, i64 1\n %qp = getelementptr i32, ptr addrspace(2) %b, i64 1\n %rp = getelementptr i32, ptr addrspace(2) %a, i64 2\n %j = load i32, ptr addrspace(2) %jp, align 4\n %q = load i32, ptr addrspace(2) %qp, align 4\n %r = load i32, ptr addrspace(2) %rp, align 4\n %fx = bitcast i32 %x to float\n %fy = bitcast i32 %y to float\n %hx0 = trunc i32 %x to i16\n %hy0 = trunc i32 %y to i16\n %hx = bitcast i16 %hx0 to half\n %hy = bitcast i16 %hy0 to half\n')
			for k, t in ['i32', 'float', 'half'] {
				x := if k == 0 { '%x' } else if k == 1 { '%fx' } else { '%hx' }; y := if k == 0 { '%y' } else if k == 1 { '%fy' } else { '%hy' }
				initial := if name.ends_with('_undef') { 'undef' } else { 'poison' }
				source.write_string('%a${k} = insertelement <4 x ${t}> ${initial}, ${t} ${x}, i32 %j\n %b${k} = insertelement <4 x ${t}> %a${k}, ${t} ${y}, i32 %q\n %s${k} = shufflevector <4 x ${t}> %a${k}, <4 x ${t}> %b${k}, <3 x i32> <i32 0, i32 4, i32 poison>\n %t${k} = shufflevector <3 x ${t}> %s${k}, <3 x ${t}> undef, <4 x i32> <i32 3, i32 0, i32 2, i32 1>\n %u${k} = insertelement <4 x ${t}> %t${k}, ${t} ${y}, i32 %q\n %old${k} = extractelement <3 x ${t}> %s${k}, i32 %r\n %new${k} = extractelement <4 x ${t}> %u${k}, i32 %r\n')
				for l, v in ['old', 'new'] {
					if name.ends_with('_frozen') { source.write_string('%f${k}${l} = freeze ${t} %${v}${k}\n') }
					value := if name.ends_with('_frozen') { '%f${k}${l}' } else { '%${v}${k}' }
					if k == 1 { source.write_string('%w${k}${l} = bitcast float ${value} to i32\n') }
					if k == 2 { source.write_string('%h${l} = bitcast half ${value} to i16\n %w${k}${l} = zext i16 %h${l} to i32\n') }
					word := if k == 0 { value } else { '%w${k}${l}' }
					source.write_string('%d${k}${l} = getelementptr i32, ptr addrspace(1) %out, i64 ${k * 2 + l}\n store i32 ${word}, ptr addrspace(1) %d${k}${l}, align 4\n')
				}
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'bad_lane_count' {
			source.write_string('define void @bad_lane_count(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { store i32 17, ptr addrspace(1) %out, align 4\n %v = extractelement <17 x i32> zeroinitializer, i32 0\n ret void }\n'); continue
		}
		if name in ['constant_lane', 'constant_lane_frozen'] {
			choice := if name.ends_with('_frozen') { '%i = freeze i32 %bi\n %f = freeze float %bf\n %h = freeze half %bh' } else { '%i = add i32 %bi, 0\n %f = select i1 true, float %bf, float 0.0\n %h = select i1 true, half %bh, half 0.0' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %index = load i32, ptr addrspace(2) %a, align 4\n %bi = extractelement <4 x i32> <i32 7, i32 11, i32 13, i32 17>, i32 %index\n %bf = extractelement <4 x float> <float 1.5, float -0.0, float bitcast (i32 2139095041 to float), float bitcast (i32 2143363909 to float)>, i32 %index\n %bh = extractelement <4 x half> <half 0xH3E00, half 0xH8000, half 0xH7C01, half 0xH7E55>, i32 %index\n ${choice}\n %fb = bitcast float %f to i32\n %hb = bitcast half %h to i16\n %hw = zext i16 %hb to i32\n store i32 %i, ptr addrspace(1) %out, align 4\n %d1 = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %fb, ptr addrspace(1) %d1, align 4\n %d2 = getelementptr i32, ptr addrspace(1) %out, i64 2\n store i32 %hw, ptr addrspace(1) %d2, align 4\n ret void }\n'); continue
		}
		if name in ['disjoint', 'disjoint_frozen', 'samesign', 'samesign_frozen'] {
			comparison := name.starts_with('samesign'); typ := if comparison { 'i1' } else { 'i32' }
			op := if comparison { 'icmp samesign ult' } else { 'or disjoint' }
			choice := if name.ends_with('_frozen') { '%chosen = freeze ${typ} %bad' } else { '%chosen = select i1 true, ${typ} %bad, ${typ} 0' }
			result := if comparison { '%v = zext i1 %chosen to i32' } else { '%v = add i32 %chosen, 0' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %y = load i32, ptr addrspace(2) %b, align 4\n %bad = ${op} i32 %x, %y\n ${choice}\n ${result}\n store i32 %v, ptr addrspace(1) %out, align 4\n ret void }\n'); continue
		}
		if name in ['saturating_convert', 'saturating_convert_frozen'] {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %f = load float, ptr addrspace(2) %a, align 4\n %h = load half, ptr addrspace(2) %b, align 2\n')
			for i, spec in ['fptosi.f32', 'fptoui.f32', 'fptosi.f16', 'fptoui.f16'] {
				op := if spec.starts_with('fptosi') { 'fptosi' } else { 'fptoui' }; half := spec.ends_with('f16'); typ := if half { 'half' } else { 'float' }; bits := if half { 16 } else { 32 }
				value := if name.ends_with('_frozen') { 'poison' } else if half { '%h' } else { '%f' }
				source.write_string('%v${i} = call i32 @llvm.${op}.sat.i32.f${bits}(${typ} ${value})\n')
				if name.ends_with('_frozen') { source.write_string('%f${i} = freeze i32 %v${i}\n') }
				result := if name.ends_with('_frozen') { '%f${i}' } else { '%v${i}' }
				source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 ${result}, ptr addrspace(1) %d${i}, align 4\n')
			}
			source.write_string('ret void }\n'); continue
		}
		if name in ['cast_trunc', 'cast_trunc_frozen', 'cast_zext', 'cast_zext_frozen'] {
			trunc_flags := if name.starts_with('cast_trunc') { 'nuw nsw ' } else { '' }
			zext_flags := if name.starts_with('cast_zext') { 'nneg ' } else { '' }
			result := if name.ends_with('_frozen') { '%v = freeze i32 %wide' } else { '%v = add i32 %wide, 0' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %small = trunc ${trunc_flags}i32 %x to i8\n %wide = zext ${zext_flags}i8 %small to i32\n ${result}\n store i32 %v, ptr addrspace(1) %out, align 4\n ret void }\n'); continue
		}
		if name == 'address_space_sum' {
			source.write_string('define void @address_space_sum(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %a0 = addrspacecast ptr addrspace(2) %a to ptr\n %a1 = addrspacecast ptr %a0 to ptr addrspace(1)\n %ax = addrspacecast ptr addrspace(1) %a1 to ptr\n %b1 = addrspacecast ptr addrspace(2) %b to ptr addrspace(1)\n %o2 = addrspacecast ptr addrspace(1) %out to ptr addrspace(2)\n %o0 = addrspacecast ptr addrspace(2) %o2 to ptr\n %ox = addrspacecast ptr %o0 to ptr addrspace(2)\n %oy = addrspacecast ptr addrspace(2) %ox to ptr\n %ai = getelementptr i32, ptr %ax, i64 2\n %bi = getelementptr i32, ptr addrspace(1) %b1, i64 1\n %di = getelementptr i32, ptr %oy, i64 3\n %x = load i32, ptr %ai, align 4\n %y = load i32, ptr addrspace(1) %bi, align 4\n %v = add i32 %x, %y\n store i32 %v, ptr %di, align 4\n ret void }\n'); continue
		}
		if name in ['cast_constant_store', 'cast_constant_view_store'] {
			cast := if name == 'cast_constant_store' { '%p = addrspacecast ptr addrspace(2) %a to ptr' } else { '%p = addrspacecast ptr addrspace(1) %out to ptr addrspace(2)' }; pointer := if name == 'cast_constant_store' { 'ptr' } else { 'ptr addrspace(2)' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { ${cast}\n store i8 7, ${pointer} %p, align 1\n ret void }\n'); continue
		}
		if name == 'looping' { source.write_string('define void @looping(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { entry: br label %loop\n loop: br label %loop\n }\n'); continue }
		if name == 'oversized_switch' {
			source.write_string('define void @oversized_switch(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { entry: %c = load i8, ptr addrspace(2) %a, align 1\n switch i8 %c, label %default [\n')
			for j in 0 .. 65 { source.write_string('i8 ${j}, label %c${j}\n') }
			source.write_string(']\n')
			for j in 0 .. 65 { source.write_string('c${j}: ret void\n') }
			source.write_string('default: ret void }\n'); continue
		}
		if name == 'switching' {
			source.write_string('define void @switching(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { entry: %x = load i64, ptr addrspace(2) %a, align 8\n %y = load i64, ptr addrspace(2) %b, align 8\n switch i64 %x, label %fallback [i64 0, label %zero i64 1, label %one i64 -1, label %all]\n zero: %z = call {i64, i1} @llvm.umul.with.overflow.i64(i64 %x, i64 %y)\n br label %join\n one: %o = call {i64, i1} @llvm.umul.with.overflow.i64(i64 %y, i64 %y)\n br label %join\n all: %m = call {i64, i1} @llvm.umul.with.overflow.i64(i64 %x, i64 %y)\n br label %join\n fallback: %d = insertvalue {i64, i1} zeroinitializer, i64 %y, 0\n br label %join\n join: %pair = phi {i64, i1} [%z, %zero], [%o, %one], [%m, %all], [%d, %fallback]\n %tag = phi i64 [10, %zero], [20, %one], [30, %all], [40, %fallback]\n %v = extractvalue {i64, i1} %pair, 0\n %f = extractvalue {i64, i1} %pair, 1\n %flag = zext i1 %f to i64\n store i64 %v, ptr addrspace(1) %out, align 8\n %d1 = getelementptr i64, ptr addrspace(1) %out, i64 1\n store i64 %flag, ptr addrspace(1) %d1, align 8\n %d2 = getelementptr i64, ptr addrspace(1) %out, i64 2\n store i64 %tag, ptr addrspace(1) %d2, align 8\n ret void }\n'); continue
		}
		if name in ['byte_copy', 'byte_inline_copy'] {
			copy := if name == 'byte_inline_copy' { 'llvm.memcpy.inline' } else { 'llvm.memcpy' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %src = getelementptr i8, ptr addrspace(2) %a, i64 16\n %dst = getelementptr i8, ptr addrspace(1) %out, i64 8\n store i8 17, ptr addrspace(1) %out, align 1\n call void @${copy}.p1.p2.i64(ptr addrspace(1) align 4 %dst, ptr addrspace(2) align 4 %src, i64 16, i1 false)\n ret void }\n'); continue
		}
		if name == 'byte_move' {
			source.write_string('define void @byte_move(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %src = getelementptr i8, ptr addrspace(2) %a, i64 16\n %dst = getelementptr i8, ptr addrspace(1) %out, i64 8\n call void @llvm.memmove.p1.p2.i64(ptr addrspace(1) align 4 %dst, ptr addrspace(2) align 4 %src, i64 16, i1 false)\n %next = getelementptr i8, ptr addrspace(1) %dst, i64 1\n call void @llvm.memmove.p1.p1.i64(ptr addrspace(1) align 1 %next, ptr addrspace(1) align 4 %dst, i64 9, i1 false)\n ret void }\n'); continue
		}
		if name in ['byte_fill', 'byte_inline_fill'] {
			fill := if name == 'byte_inline_fill' { 'llvm.memset.inline' } else { 'llvm.memset' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i32, ptr addrspace(2) %a, align 4\n %v = trunc i32 %x to i8\n %dst = getelementptr i8, ptr addrspace(1) %out, i64 8\n call void @${fill}.p1.i64(ptr addrspace(1) align 8 %dst, i8 %v, i64 16, i1 false)\n ret void }\n'); continue
		}
		if name == 'branching' {
			source.write_string('define void @branching(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { entry: %x = load i64, ptr addrspace(2) %a, align 8\n %y = load i64, ptr addrspace(2) %b, align 8\n %c = icmp ult i64 %x, %y\n br i1 %c, label %left, label %right\n left: %l = call {i64, i1} @llvm.umul.with.overflow.i64(i64 %x, i64 %y)\n br label %join\n right: %r = insertvalue {i64, i1} zeroinitializer, i64 %x, 0\n br label %join\n join: %joined = phi ptr addrspace(1) [%out, %left], [%out, %right]\n %pair = phi {i64, i1} [%l, %left], [%r, %right]\n %tag = phi i64 [17, %left], [29, %right]\n %chosen = select i1 %c, ptr addrspace(1) %joined, ptr addrspace(1) %out\n %frozen = freeze ptr addrspace(1) %chosen\n %casted = bitcast ptr addrspace(1) %frozen to ptr addrspace(1)\n %same = icmp eq ptr addrspace(1) %casted, %out\n %dst = select i1 %same, ptr addrspace(1) %casted, ptr addrspace(1) %out\n %v = extractvalue {i64, i1} %pair, 0\n %f = extractvalue {i64, i1} %pair, 1\n %flag = zext i1 %f to i64\n store i64 %v, ptr addrspace(1) %dst, align 8\n %d1 = getelementptr i64, ptr addrspace(1) %dst, i64 1\n store i64 %flag, ptr addrspace(1) %d1, align 8\n %d2 = getelementptr i64, ptr addrspace(1) %dst, i64 2\n store i64 %tag, ptr addrspace(1) %d2, align 8\n ret void }\n'); continue
		}
		if name == 'pair_choices' {
			source.write_string('define void @pair_choices(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %p = call {i64, i1} @llvm.umul.with.overflow.i64(i64 poison, i64 0)\n')
			source.write_string('%lazy = select i1 true, {i64, i1} zeroinitializer, {i64, i1} poison\n %badcond = select i1 poison, {i64, i1} zeroinitializer, {i64, i1} %p\n')
			source.write_string('%repair_value = insertvalue {i64, i1} %p, i64 19, 0\n %repair_flag = insertvalue {i64, i1} poison, i1 true, 1\n %repair_selected = select i1 true, {i64, i1} %repair_flag, {i64, i1} %repair_value\n %repair_both = insertvalue {i64, i1} %repair_value, i1 true, 1\n %poison_value = insertvalue {i64, i1} %repair_both, i64 poison, 0\n')
			for i, seed in ['poison', 'undef', '%p', '%lazy', '%badcond', '%repair_value', '%repair_selected', '%repair_both', '%poison_value'] {
				source.write_string('%f${i} = freeze {i64, i1} ${seed}\n %v${i * 2} = extractvalue {i64, i1} %f${i}, 0\n %flag${i} = extractvalue {i64, i1} %f${i}, 1\n %v${i * 2 + 1} = zext i1 %flag${i} to i64\n')
			}
			for i in 0 .. 18 { source.write_string('%d${i} = getelementptr i64, ptr addrspace(1) %out, i64 ${i}\n store i64 %v${i}, ptr addrspace(1) %d${i}, align 8\n') }
			source.write_string('ret void }\n'); continue
		}
		if name in ['overflowing', 'frozen_overflowing', 'selected_overflowing', 'inserted_overflowing'] {
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i64, ptr addrspace(2) %a, align 8\n %y = load i64, ptr addrspace(2) %b, align 8\n %x32 = trunc i64 %x to i32\n %y32 = trunc i64 %y to i32\n')
			if name in ['selected_overflowing', 'inserted_overflowing'] { source.write_string('%c = icmp ult i64 %x, %y\n') }
			for i, op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
				freezing := if name == 'frozen_overflowing' { '%frozen${i} = freeze {i32, i1} %p${i}\n' } else if name == 'selected_overflowing' { '%frozen${i} = select i1 %c, {i32, i1} %p${i}, {i32, i1} zeroinitializer\n' } else if name == 'inserted_overflowing' { if i % 2 == 0 { '%frozen${i} = insertvalue {i32, i1} %p${i}, i32 %y32, 0\n' } else { '%frozen${i} = insertvalue {i32, i1} %p${i}, i1 %c, 1\n' } } else { '' }; value := if name != 'overflowing' { '%frozen${i}' } else { '%p${i}' }
				source.write_string('%p${i} = call {i32, i1} @llvm.${op}.with.overflow.i32(i32 %x32, i32 %y32)\n ${freezing}%r${i} = extractvalue {i32, i1} ${value}, 0\n %f${i} = extractvalue {i32, i1} ${value}, 1\n %v${i * 2} = zext i32 %r${i} to i64\n %v${i * 2 + 1} = zext i1 %f${i} to i64\n')
			}
			freezing64 := if name == 'frozen_overflowing' { '%frozen64 = freeze {i64, i1} %p64\n' } else if name == 'selected_overflowing' { '%frozen64 = select i1 %c, {i64, i1} %p64, {i64, i1} zeroinitializer\n' } else if name == 'inserted_overflowing' { '%frozen64 = insertvalue {i64, i1} %p64, i64 %y, 0\n' } else { '' }; value64 := if name != 'overflowing' { '%frozen64' } else { '%p64' }
			source.write_string('%p64 = call {i64, i1} @llvm.umul.with.overflow.i64(i64 %x, i64 %y)\n ${freezing64}%v12 = extractvalue {i64, i1} ${value64}, 0\n %f64 = extractvalue {i64, i1} ${value64}, 1\n %v13 = zext i1 %f64 to i64\n')
			for i in 0 .. 14 { source.write_string('%d${i} = getelementptr i64, ptr addrspace(1) %out, i64 ${i}\n store i64 %v${i}, ptr addrspace(1) %d${i}, align 8\n') }
			source.write_string('ret void }\n'); continue
		}
		if name == 'polynomial' {
			source.write_string('define void @polynomial(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x64 = load i64, ptr addrspace(2) %a, align 8\n %y64 = load i64, ptr addrspace(2) %b, align 8\n %x32 = trunc i64 %x64 to i32\n %y32 = trunc i64 %y64 to i32\n')
			for i, bits in [32, 64]! {
				source.write_string('%p${bits} = call i${bits} @llvm.clmul.i${bits}(i${bits} %x${bits}, i${bits} %y${bits})\n %y1${bits} = xor i${bits} %y${bits}, 1\n %q${bits} = call i${bits} @llvm.clmul.i${bits}(i${bits} %x${bits}, i${bits} %y1${bits})\n %r${bits} = xor i${bits} %p${bits}, %q${bits}\n')
				if bits == 32 { source.write_string('%v0 = zext i32 %p32 to i64\n %v1 = zext i32 %r32 to i64\n') } else { source.write_string('%v2 = or i64 %p64, 0\n %v3 = or i64 %r64, 0\n') }
				for j in 0 .. 2 { source.write_string('%d${i * 2 + j} = getelementptr i64, ptr addrspace(1) %out, i64 ${i * 2 + j}\n store i64 %v${i * 2 + j}, ptr addrspace(1) %d${i * 2 + j}, align 8\n') }
			}
			source.write_string('ret void }\n'); continue
		}
		if name == 'scaling' {
			source.write_string('define void @scaling(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %e = load i32, ptr addrspace(2) %b, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %f = call float @llvm.ldexp.f32.i32(float %x, i32 %e)\n %h = call half @llvm.ldexp.f16.i32(half %hx, i32 %e)\n %v0 = bitcast float %f to i32\n %i = bitcast half %h to i16\n %v1 = zext i16 %i to i32\n store i32 %v0, ptr addrspace(1) %out, align 4\n %d = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %v1, ptr addrspace(1) %d, align 4\n ret void }\n'); continue
		}
		if name in ['fused', 'optional_fused'] {
			op := if name == 'optional_fused' { 'fmuladd' } else { 'fma' }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %y = load float, ptr addrspace(2) %b, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hb = getelementptr i8, ptr addrspace(2) %b, i64 4\n %ca = getelementptr i8, ptr addrspace(2) %a, i64 8\n %hca = getelementptr i8, ptr addrspace(2) %a, i64 12\n %hx = load half, ptr addrspace(2) %ha, align 2\n %hy = load half, ptr addrspace(2) %hb, align 2\n %z = load float, ptr addrspace(2) %ca, align 4\n %hz = load half, ptr addrspace(2) %hca, align 2\n %f = call float @llvm.${op}.f32(float %x, float %y, float %z)\n %h = call half @llvm.${op}.f16(half %hx, half %hy, half %hz)\n %v0 = bitcast float %f to i32\n %i = bitcast half %h to i16\n %v1 = zext i16 %i to i32\n store i32 %v0, ptr addrspace(1) %out, align 4\n %d = getelementptr i32, ptr addrspace(1) %out, i64 1\n store i32 %v1, ptr addrspace(1) %d, align 4\n ret void }\n'); continue
		}
		if name == 'classification' {
			source.write_string('define void @classification(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %nan = call i1 @llvm.is.fpclass.f32(float %x, i32 3)\n %finite = call i1 @llvm.is.fpclass.f32(float %x, i32 504)\n %snan = call i1 @llvm.is.fpclass.f16(half %hx, i32 1)\n %hnan = call i1 @llvm.is.fpclass.f16(half %hx, i32 3)\n %v0 = zext i1 %nan to i32\n %v1 = zext i1 %finite to i32\n %v2 = zext i1 %snan to i32\n %v3 = select i1 %hnan, i32 77, i32 11\n')
			for i in 0 .. 4 { source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n') }
			source.write_string('ret void }\n'); continue
		}
		if name in ['floating_extrema', 'number_extrema', 'legacy_extrema'] {
			minop := match name { 'number_extrema' { 'minimumnum' } 'legacy_extrema' { 'minnum' } else { 'minimum' } }; maxop := match name { 'number_extrema' { 'maximumnum' } 'legacy_extrema' { 'maxnum' } else { 'maximum' } }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %y = load float, ptr addrspace(2) %b, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hb = getelementptr i8, ptr addrspace(2) %b, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %hy = load half, ptr addrspace(2) %hb, align 2\n %f0 = call float @llvm.${minop}.f32(float %x, float %y)\n %f1 = call float @llvm.${maxop}.f32(float %x, float %y)\n %h0 = call half @llvm.${minop}.f16(half %hx, half %hy)\n %h1 = call half @llvm.${maxop}.f16(half %hx, half %hy)\n %v0 = bitcast float %f0 to i32\n %v1 = bitcast float %f1 to i32\n %i0 = bitcast half %h0 to i16\n %i1 = bitcast half %h1 to i16\n %v2 = zext i16 %i0 to i32\n %v3 = zext i16 %i1 to i32\n')
			for i in 0 .. 4 { source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n') }
			source.write_string('ret void }\n'); continue
		}
		if name == 'square_root' {
			source.write_string('define void @square_root(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n %ax = call float @llvm.fabs.f32(float %x)\n %ahx = call half @llvm.fabs.f16(half %hx)\n %f0 = call float @llvm.sqrt.f32(float %x)\n %f1 = call float @llvm.sqrt.f32(float %ax)\n %h0 = call half @llvm.sqrt.f16(half %hx)\n %h1 = call half @llvm.sqrt.f16(half %ahx)\n %v0 = bitcast float %f0 to i32\n %v1 = bitcast float %f1 to i32\n %i0 = bitcast half %h0 to i16\n %i1 = bitcast half %h1 to i16\n %v2 = zext i16 %i0 to i32\n %v3 = zext i16 %i1 to i32\n')
			for i in 0 .. 4 { source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n') }
			source.write_string('ret void }\n'); continue
		}
		if name in ['rounding', 'default_rounding'] {
			ops := if name == 'default_rounding' { ['rint', 'nearbyint', 'roundeven'] } else { ['floor', 'ceil', 'trunc', 'round', 'roundeven'] }
			source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load float, ptr addrspace(2) %a, align 4\n %ha = getelementptr i8, ptr addrspace(2) %a, i64 4\n %hx = load half, ptr addrspace(2) %ha, align 2\n')
			for i, op in ops {
				source.write_string('%f${i} = call float @llvm.${op}.f32(float %x)\n %h${i} = call half @llvm.${op}.f16(half %hx)\n %v${i} = bitcast float %f${i} to i32\n %i${i} = bitcast half %h${i} to i16\n %v${i + ops.len} = zext i16 %i${i} to i32\n %d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i}\n store i32 %v${i}, ptr addrspace(1) %d${i}, align 4\n %d${i + ops.len} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + ops.len}\n store i32 %v${i + ops.len}, ptr addrspace(1) %d${i + ops.len}, align 4\n')
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
		indexed := name in ['indexed_sum', 'backward_sum']
		gep := if name == 'backward_sum' { '%ab = getelementptr inbounds i32, ptr addrspace(2) %a, i64 4\n %bb = getelementptr inbounds i32, ptr addrspace(2) %b, i64 3\n %db = getelementptr inbounds i32, ptr addrspace(1) %out, i64 5\n %ai = getelementptr inbounds [4 x i32], ptr addrspace(2) %ab, i64 0, i64 -2\n %bi = getelementptr nusw {i16, [2 x i16]}, ptr addrspace(2) %bb, i64 0, i32 1, i8 -5\n %di = getelementptr {i32, [2 x i32]}, ptr addrspace(1) %db, i64 0, i32 1, i16 -3\n' } else if indexed { '%ai = getelementptr inbounds i32, ptr addrspace(2) %a, i64 2\n %bi = getelementptr inbounds i32, ptr addrspace(2) %b, i64 1\n %di = getelementptr inbounds i32, ptr addrspace(1) %out, i64 3\n' } else { '' }
		a := if indexed { '%ai' } else { '%a' }; b := if indexed { '%bi' } else { '%b' }; dst := if indexed { '%di' } else { '%out' }
		cmp := if name == 'max' { 'icmp sgt' } else { 'fcmp ogt' }
		compute := if name in ['max', 'float_max'] { '%c = ${cmp} ${typ} %x, %y\n %v = select i1 %c, ${typ} %x, ${typ} %y\n' } else if name == 'frozen_sum' { '%bad = ${op} i32 %x, %y\n %v = freeze i32 %bad\n' } else { '%v = ${op} ${typ} %x, %y\n' }
		source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) {\n ${gep}%x = load ${typ}, ptr addrspace(2) ${a}, align 4\n %y = load ${typ}, ptr addrspace(2) ${b}, align 4\n ${prior}${compute}store ${typ} %v, ptr addrspace(1) ${dst}, align 4\n ret void\n}\n')
	}
	source.write_string('!air.kernel = !{')
	for i in 0 .. names.len - 1 { if i > 0 { source.write_string(', ') }; source.write_string('!${i * 10}') }
	source.write_string('}\n')
	for i, name in names[..names.len - 1] {
		n := i * 10
		source.write_string('!${n} = !{ptr @${name}, !${n + 1}, !${n + 2}}\n!${n + 1} = !{}\n')
		if name == 'empty' { source.write_string('!${n + 2} = !{}\n'); continue }
		source.write_string('!${n + 2} = !{!${n + 5}, !${n + 3}, !${n + 4}}\n')
		semantic := if name == 'bad_builtin' { 'air.thread_position_in_grid' } else { 'air.buffer' }
		source.write_string('!${n + 3} = !{i32 0, !"${semantic}", !"air.location_index", i32 0, i32 1, !"air.address_space", i32 2, !"air.read", !"air.arg_type_align_size", i32 4, !"air.buffer_size", i32 4}\n')
		slot := if name == 'bad_slot' { 0 } else { 3 }
		source.write_string('!${n + 4} = !{i32 1, !"air.buffer", !"air.location_index", i32 ${slot}, i32 1, !"air.address_space", i32 2, !"air.read"}\n')
		access := if name == 'bad_access' { 'air.read' } else if name == 'byte_move' { 'air.read_write' } else { 'air.write' }
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
		for name in ['bad_flags', 'bad_access', 'bad_slot', 'bad_builtin', 'looping', 'oversized_switch', 'cast_constant_store', 'cast_constant_view_store', 'bad_lane_count', 'bad_shuffle_count', 'bad_vector_freeze', 'bad_wide_vector_condition', 'bad_vector_compare', 'bad_vector_binary', 'bad_vector_fneg', 'bad_vector_integer_cast', 'bad_vector_bitcast', 'bad_vector_precision', 'bad_vector_int_float', 'bad_vector_float_int', 'bad_vector_sign', 'bad_vector_round', 'no_metadata', 'missing'] {
			error_slot = 0
			assert sm_test_compute_pipeline(d, library, name, &error_slot) == 0, name
			sm_library_check_error(error_slot, if name == 'missing' { i64(1) } else { i64(3) })
			assert sm_test_compute_pipeline(d, library, name, unsafe { nil }) == 0, name
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
		for indexed_kernel in ['indexed_sum', 'backward_sum', 'address_space_sum'] {
			unsafe { *(&u32(outp + 16)) = 0xcccccccc }
			indexed_command := sm_send(queue, c'commandBuffer'); ie := sm_send(indexed_command, c'computeCommandEncoder')
			ip := sm_test_compute_pipeline(d, library, indexed_kernel, unsafe { nil }); assert ip != 0
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
			assert unsafe { *(&u32(outp + 16)) } == u32(0xcccccccc)
			sm_call(indexed_command, c'commit'); assert sm_send(indexed_command, c'status') == 4
			assert unsafe { *(&u32(outp + 16)) } == 304 && unsafe { *(&u32(outp + 12)) } == 42
		}
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
		cast_command := sm_send(queue, c'commandBuffer'); cast_encoder := sm_send(cast_command, c'computeCommandEncoder')
		for i, name in ['cast_trunc', 'cast_trunc_frozen', 'cast_zext', 'cast_zext_frozen'] {
			cast_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert cast_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(cast_encoder, c'setComputePipelineState:', cast_pipeline) }
			sm_test_compute_buffer(cast_encoder, a, u64(i * 4), 0); sm_test_compute_buffer(cast_encoder, b, 0, 3)
			sm_test_compute_buffer(cast_encoder, output, u64(4 + i * 4), 7)
			sm_test_compute_dispatch(cast_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(cast_pipeline)
		}
		sm_call(cast_encoder, c'endEncoding')
		unsafe { *(&u32(ap)) = 73; *(&u32(ap + 4)) = 128; *(&u32(ap + 8)) = 92; *(&u32(ap + 12)) = 255 }
		sm_call(cast_command, c'commit'); assert sm_send(cast_command, c'status') == 4
		assert unsafe { *(&u32(outp + 4)) } == 73 && unsafe { *(&u32(outp + 8)) } == 0 && unsafe { *(&u32(outp + 12)) } == 92 && unsafe { *(&u32(outp + 16)) } == 0
		for i, name in ['cast_trunc', 'cast_zext'] {
			cast_failed := sm_send(queue, c'commandBuffer'); cast_failed_encoder := sm_send(cast_failed, c'computeCommandEncoder')
			cast_failed_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert cast_failed_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(cast_failed_encoder, c'setComputePipelineState:', cast_failed_pipeline) }
			sm_test_compute_buffer(cast_failed_encoder, a, u64(4 + i * 8), 0); sm_test_compute_buffer(cast_failed_encoder, b, 0, 3); sm_test_compute_buffer(cast_failed_encoder, output, 4, 7)
			sm_test_compute_dispatch(cast_failed_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(cast_failed_encoder, c'endEncoding'); objc_release(cast_failed_pipeline)
			sm_call(cast_failed, c'commit'); assert sm_send(cast_failed, c'status') == 5 && sm_send(cast_failed, c'error') != 0
			assert unsafe { *(&u32(outp + 4)) } == 73
		}
		promise_command := sm_send(queue, c'commandBuffer'); promise_encoder := sm_send(promise_command, c'computeCommandEncoder')
		for i, name in ['disjoint', 'disjoint_frozen', 'samesign', 'samesign_frozen'] {
			promise_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert promise_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(promise_encoder, c'setComputePipelineState:', promise_pipeline) }
			sm_test_compute_buffer(promise_encoder, a, u64(i * 4), 0); sm_test_compute_buffer(promise_encoder, b, u64(i * 4), 3); sm_test_compute_buffer(promise_encoder, output, u64(4 + i * 4), 7)
			sm_test_compute_dispatch(promise_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); objc_release(promise_pipeline)
		}
		sm_call(promise_encoder, c'endEncoding')
		unsafe { *(&u32(ap)) = 0x50; *(&u32(bp)) = 0x0f; *(&u32(ap + 4)) = 5; *(&u32(bp + 4)) = 5; *(&u32(ap + 8)) = 12; *(&u32(bp + 8)) = 25; *(&u32(ap + 12)) = 0xfffffff0; *(&u32(bp + 12)) = 1 }
		sm_call(promise_command, c'commit'); assert sm_send(promise_command, c'status') == 4
		assert unsafe { *(&u32(outp + 4)) } == 0x5f && unsafe { *(&u32(outp + 8)) } == 0 && unsafe { *(&u32(outp + 12)) } == 1 && unsafe { *(&u32(outp + 16)) } == 0
		for i, name in ['disjoint', 'samesign'] {
			promise_failed := sm_send(queue, c'commandBuffer'); promise_failed_encoder := sm_send(promise_failed, c'computeCommandEncoder')
			promise_failed_pipeline := sm_test_compute_pipeline(d, library, name, unsafe { nil }); assert promise_failed_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(promise_failed_encoder, c'setComputePipelineState:', promise_failed_pipeline) }
			sm_test_compute_buffer(promise_failed_encoder, a, u64(4 + i * 8), 0); sm_test_compute_buffer(promise_failed_encoder, b, u64(4 + i * 8), 3); sm_test_compute_buffer(promise_failed_encoder, output, 4, 7)
			sm_test_compute_dispatch(promise_failed_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(promise_failed_encoder, c'endEncoding'); objc_release(promise_failed_pipeline)
			sm_call(promise_failed, c'commit'); assert sm_send(promise_failed, c'status') == 5 && sm_send(promise_failed, c'error') != 0
			assert unsafe { *(&u32(outp + 4)) } == 0x5f
		}
		for sample in 0 .. 6 {
			convert_name := if sample == 5 { 'saturating_convert_frozen' } else { 'saturating_convert' }
			sat_command := sm_send(queue, c'commandBuffer'); sat_encoder := sm_send(sat_command, c'computeCommandEncoder')
			sat_pipeline := sm_test_compute_pipeline(d, library, convert_name, unsafe { nil }); assert sat_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(sat_encoder, c'setComputePipelineState:', sat_pipeline) }
			sm_test_compute_buffer(sat_encoder, a, 0, 0); sm_test_compute_buffer(sat_encoder, b, 0, 3); sm_test_compute_buffer(sat_encoder, output, 16, 7)
			sm_test_compute_dispatch(sat_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(sat_encoder, c'endEncoding'); objc_release(sat_pipeline)
			unsafe { *(&u32(ap)) = [u32(0x7f800000), 0xff800000, 0x7f800001, 0xbfe00000, 0x3fe00000, 0]![sample]; *(&u16(bp)) = [u16(0xfc00), 0x7c00, 0x7c01, 0xc100, 0x4100, 0]![sample] }
			sm_call(sat_command, c'commit'); assert sm_send(sat_command, c'status') == 4
			expected := [[u32(0x7fffffff), 0xffffffff, 0x80000000, 0]!, [u32(0x80000000), 0, 0x7fffffff, 0xffffffff]!, [u32(0), 0, 0, 0]!, [u32(0xffffffff), 0, 0xfffffffe, 0]!, [u32(1), 1, 2, 2]!, [u32(0), 0, 0, 0]!]![sample]
			for i in 0 .. 4 { assert unsafe { *(&u32(outp + u64(16 + i * 4))) } == expected[i] }
		}
		for lane in 0 .. 5 {
			lane_name := if lane == 4 { 'constant_lane_frozen' } else { 'constant_lane' }
			lane_command := sm_send(queue, c'commandBuffer'); lane_encoder := sm_send(lane_command, c'computeCommandEncoder')
			lane_pipeline := sm_test_compute_pipeline(d, library, lane_name, unsafe { nil }); assert lane_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(lane_encoder, c'setComputePipelineState:', lane_pipeline) }
			sm_test_compute_buffer(lane_encoder, a, 0, 0); sm_test_compute_buffer(lane_encoder, b, 0, 3); sm_test_compute_buffer(lane_encoder, output, 16, 7)
			sm_test_compute_dispatch(lane_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(lane_encoder, c'endEncoding'); objc_release(lane_pipeline)
			unsafe { *(&u32(ap)) = u32(lane) }; sm_call(lane_command, c'commit'); assert sm_send(lane_command, c'status') == 4
			assert unsafe { *(&u32(outp + 16)) } == [u32(7), 11, 13, 17, 0]![lane]
			assert unsafe { *(&u32(outp + 20)) } == [u32(0x3fc00000), 0x80000000, 0x7f800001, 0x7fc12345, 0]![lane]
			assert unsafe { *(&u32(outp + 24)) } == [u32(0x3e00), 0x8000, 0x7c01, 0x7e55, 0]![lane]
		}
		for index in [u32(4), 0xffffffff]! {
			lane_failed := sm_send(queue, c'commandBuffer'); lane_failed_encoder := sm_send(lane_failed, c'computeCommandEncoder')
			lane_failed_pipeline := sm_test_compute_pipeline(d, library, 'constant_lane', unsafe { nil }); assert lane_failed_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(lane_failed_encoder, c'setComputePipelineState:', lane_failed_pipeline) }
			sm_test_compute_buffer(lane_failed_encoder, a, 0, 0); sm_test_compute_buffer(lane_failed_encoder, b, 0, 3); sm_test_compute_buffer(lane_failed_encoder, output, 16, 7)
			sm_test_compute_dispatch(lane_failed_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(lane_failed_encoder, c'endEncoding'); objc_release(lane_failed_pipeline)
			unsafe { *(&u32(ap)) = index }; sm_call(lane_failed, c'commit'); assert sm_send(lane_failed, c'status') == 5 && sm_send(lane_failed, c'error') != 0
			for offset in [u64(16), 20, 24]! { assert unsafe { *(&u32(outp + offset)) } == 0 }
		}

		mut vector_saved := [8]u32{}
		for i in 0 .. 8 { vector_saved[i] = unsafe { *(&u32(outp + u64(i * 4))) } }
		for sample in 0 .. 7 {
			update_name := if sample == 2 { 'vector_update_undef' } else if sample in [3, 4] { 'vector_update_frozen' } else { 'vector_update' }
			update_command := sm_send(queue, c'commandBuffer'); update_encoder := sm_send(update_command, c'computeCommandEncoder')
			update_pipeline := sm_test_compute_pipeline(d, library, update_name, unsafe { nil }); assert update_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(update_encoder, c'setComputePipelineState:', update_pipeline) }
			sm_test_compute_buffer(update_encoder, a, 0, 0); sm_test_compute_buffer(update_encoder, b, 0, 3); sm_test_compute_buffer(update_encoder, output, 4, 7)
			sm_test_compute_dispatch(update_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(update_encoder, c'endEncoding'); objc_release(update_pipeline)
			xword := [u32(0x7f800001), 0x80007c01, 0x7fc17e55, 0x80000000, 0x7fc17e55, 11, 13]![sample]
			yword := [u32(0x80000000), 0x7fc18000, 0x7f807c01, 0x7f807c01, 0x80000000, 17, 19]![sample]
			jindex := [u32(0), 1, 2, 4, 1, 4, 0]![sample]; qindex := [u32(0), 3, 2, 1, 4, 0, 4]![sample]
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = xword; *(&u32(bp)) = yword; *(&u32(ap + 4)) = jindex; *(&u32(bp + 4)) = qindex }
			sm_call(update_command, c'commit')
			if sample >= 5 {
				assert sm_send(update_command, c'status') == 5 && sm_send(update_command, c'error') != 0
				for i in 0 .. 6 { assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if sample == 6 && i == 0 { xword } else { u32(0xcccccccc) } }
			} else {
				assert sm_send(update_command, c'status') == 4
				for i in 0 .. 6 { word := if i % 2 == 0 { if jindex >= 4 { u32(0) } else { xword } } else { if qindex >= 4 { u32(0) } else { yword } }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i >= 4 { word & 0xffff } else { word } }
			}
		}

		for sample in 0 .. 9 {
			shuffle_name := if sample == 6 { 'vector_shuffle_undef' } else if sample in [2, 3, 7] { 'vector_shuffle_frozen' } else { 'vector_shuffle' }
			shuffle_command := sm_send(queue, c'commandBuffer'); shuffle_encoder := sm_send(shuffle_command, c'computeCommandEncoder')
			shuffle_pipeline := sm_test_compute_pipeline(d, library, shuffle_name, unsafe { nil }); assert shuffle_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(shuffle_encoder, c'setComputePipelineState:', shuffle_pipeline) }
			sm_test_compute_buffer(shuffle_encoder, a, 0, 0); sm_test_compute_buffer(shuffle_encoder, b, 0, 3); sm_test_compute_buffer(shuffle_encoder, output, 4, 7)
			sm_test_compute_dispatch(shuffle_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(shuffle_encoder, c'endEncoding'); objc_release(shuffle_pipeline)
			xword := [u32(0x7f800001), 0x80007c01, 0x7fc17e55, 0x80000000, 11, 13, 0x7f807c01, 0x80000000, 0x7fc17e55]![sample]
			yword := [u32(0x80000000), 0x7fc18000, 0x7f807c01, 0x7f807c01, 17, 19, 0x80000000, 0x7fc17e55, 0x80000000]![sample]
			qindex := [u32(0), 1, 0, 3, 0, 1, 0, 0, 0]![sample]; rindex := [u32(0), 1, 2, 3, 2, 0, 0, 0, 1]![sample]
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = xword; *(&u32(bp)) = yword; *(&u32(ap + 4)) = if sample == 7 { u32(4) } else { u32(0) }; *(&u32(bp + 4)) = qindex; *(&u32(ap + 8)) = rindex }
			sm_call(shuffle_command, c'commit')
			if sample in [4, 5] {
				assert sm_send(shuffle_command, c'status') == 5 && sm_send(shuffle_command, c'error') != 0
				for i in 0 .. 6 { assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == u32(0xcccccccc), 'shuffle failure sample=${sample} word=${i}' }
			} else {
				assert sm_send(shuffle_command, c'status') == 4
				for i in 0 .. 6 { word := if sample == 2 { u32(0) } else if sample == 8 { if i % 2 == 0 { yword } else { xword } } else if i % 2 == 0 { if sample in [3, 7] { u32(0) } else { xword } } else { yword }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i >= 4 { word & 0xffff } else { word } }
			}
		}

		for sample in 0 .. 10 {
			freeze_name := if sample == 7 { 'vector_freeze_undef_index' } else if sample == 8 { 'vector_freeze_old_undef' } else if sample == 9 { 'vector_freeze_old_poison' } else { 'vector_freeze' }
			freeze_command := sm_send(queue, c'commandBuffer'); freeze_encoder := sm_send(freeze_command, c'computeCommandEncoder')
			freeze_pipeline := sm_test_compute_pipeline(d, library, freeze_name, unsafe { nil }); assert freeze_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(freeze_encoder, c'setComputePipelineState:', freeze_pipeline) }
			sm_test_compute_buffer(freeze_encoder, a, 0, 0); sm_test_compute_buffer(freeze_encoder, b, 0, 3); sm_test_compute_buffer(freeze_encoder, output, 4, 7)
			sm_test_compute_dispatch(freeze_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(freeze_encoder, c'endEncoding'); objc_release(freeze_pipeline)
			xword := [u32(0x7f807c01), 0x80007e55, 0x80000000, 0x7fc17e55, 0x7f807c01, 0x80000000, 13, 17, 19, 23]![sample]
			yword := [u32(0x80000000), 0x7fc18000, 0x7f807c01, 0x80000000, 0x7fc17e55, 0x7f807c01, 29, 31, 37, 41]![sample]
			jindex := [u32(0), 1, 0, 1, 4, 0, 0, 0, 0, 0]![sample]; rindex := [u32(0), 1, 1, 2, 0, 3, 4, 0, 1, 2]![sample]
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = xword; *(&u32(bp)) = yword; *(&u32(ap + 4)) = jindex; *(&u32(bp + 4)) = rindex }
			sm_call(freeze_command, c'commit')
			if sample >= 6 {
				assert sm_send(freeze_command, c'status') == 5 && sm_send(freeze_command, c'error') != 0
				for i in 0 .. 6 { assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == u32(0xcccccccc) }
			} else {
				assert sm_send(freeze_command, c'status') == 4
				for i in 0 .. 6 { word := if i % 2 == 0 { if sample in [0, 1] { xword } else { u32(0) } } else { if sample in [0, 4] { yword } else if sample in [2, 3] { xword } else { u32(0) } }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i >= 4 { word & 0xffff } else { word } }
			}
		}

		for sample in 0 .. 13 {
			select_name := if sample in [5, 6] { 'vector_select_poison' } else if sample == 4 { 'vector_select_frozen_condition' } else if sample == 7 { 'vector_select_undef_condition' } else if sample in [8, 9] { 'vector_select_old' } else { 'vector_select' }
			select_command := sm_send(queue, c'commandBuffer'); select_encoder := sm_send(select_command, c'computeCommandEncoder')
			select_pipeline := sm_test_compute_pipeline(d, library, select_name, unsafe { nil }); assert select_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(select_encoder, c'setComputePipelineState:', select_pipeline) }
			sm_test_compute_buffer(select_encoder, a, 0, 0); sm_test_compute_buffer(select_encoder, b, 0, 3); sm_test_compute_buffer(select_encoder, output, 4, 7)
			sm_test_compute_dispatch(select_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(select_encoder, c'endEncoding'); objc_release(select_pipeline)
			xword := [u32(0x7f807c01), 0x80000000, 0x7fc18000, 0x80007e55, 0x7f807c01, 0x7fc17e55, 13, 17, 19, 23, 0x7fc17e55, 0x80000000, 29]![sample]
			yword := [u32(0x80000000), 0x7fc17e55, 0x7f807c01, 0x7fc18000, 0x7fc17e55, 0x80000000, 31, 37, 41, 43, 0x80000000, 0x7f807c01, 47]![sample]
			condition := [u32(1), 1, 0, 0, 1, 0, 0, 1, 1, 0, 2, 3, 1]![sample]; rindex := [u32(0), 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 2]![sample]
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = xword; *(&u32(bp)) = yword; *(&u32(ap + 4)) = condition; *(&u32(bp + 4)) = rindex }
			sm_call(select_command, c'commit')
			if sample in [6, 7, 8, 9, 12] {
				assert sm_send(select_command, c'status') == 5 && sm_send(select_command, c'error') != 0
				for i in 0 .. 6 { assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if sample == 6 && i == 0 { u32(0) } else { u32(0xcccccccc) } }
			} else {
				assert sm_send(select_command, c'status') == 4
				effective := if sample == 4 { u32(0) } else { condition & 1 }
				for i in 0 .. 6 { word := if i % 2 == 0 { if sample == 5 { u32(0) } else if effective == 1 && rindex == 0 { xword } else if effective == 0 && rindex == 1 { yword } else { u32(0) } } else { if effective == 1 && rindex == 0 { u32(0) } else { yword } }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i >= 4 { word & 0xffff } else { word } }
			}
		}

		for sample in 0 .. 16 {
			kernel := if sample in [4, 5] { 'vector_lane_select_poison' } else if sample == 6 { 'vector_lane_select_undef' } else if sample in [7, 8, 15] { 'vector_lane_select_frozen' } else if sample in [9, 10] { 'vector_lane_select_old' } else if sample in [13, 14] { 'vector_lane_select_all_poison' } else { 'vector_lane_select' }
			lane_command := sm_send(queue, c'commandBuffer'); lane_encoder := sm_send(lane_command, c'computeCommandEncoder')
			lane_pipeline := sm_test_compute_pipeline(d, library, kernel, unsafe { nil }); assert lane_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(lane_encoder, c'setComputePipelineState:', lane_pipeline) }
			sm_test_compute_buffer(lane_encoder, a, 0, 0); sm_test_compute_buffer(lane_encoder, b, 0, 3); sm_test_compute_buffer(lane_encoder, output, 4, 7)
			sm_test_compute_dispatch(lane_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(lane_encoder, c'endEncoding'); objc_release(lane_pipeline)
			xword := if sample % 2 == 0 { u32(0x7f807c01) } else { u32(0x80000000) }
			yword := if sample % 2 == 0 { u32(0x80000000) } else { u32(0x7fc17e55) }
			condition := [u32(1), 1, 2, 2, 1, 1, 1, 1, 0, 3, 0, 3, 0xfffffffd, 0, 0, 1]![sample]
			rindex := [u32(0), 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 2, 0, 1, 0, 1]![sample]
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = xword; *(&u32(bp)) = yword; *(&u32(ap + 4)) = condition; *(&u32(bp + 4)) = rindex }
			sm_call(lane_command, c'commit')
			if sample in [4, 6, 9, 10, 11, 14] {
				assert sm_send(lane_command, c'status') == 5 && sm_send(lane_command, c'error') != 0
				for i in 0 .. 6 { assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i == 0 && sample == 4 { xword } else if i == 0 && sample == 14 { u32(0) } else { u32(0xcccccccc) } }
			} else {
				assert sm_send(lane_command, c'status') == 4
				c0 := condition & 1 != 0; c1 := if sample in [7, 8, 15] { false } else { condition & 2 != 0 }
				for i in 0 .. 6 {
					word := if i % 2 == 0 { if sample in [5, 13] { u32(0) } else if rindex == 0 { if c0 { xword } else { u32(0) } } else { if c1 { u32(0) } else { yword } } } else { if rindex == 1 || !c1 { yword } else { u32(0) } }
					assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i >= 4 { word & 0xffff } else { word }
				}
			}
		}

		for sample in 0 .. 16 {
			compare_name := if sample in [5, 6] { 'vector_compare_poison' } else if sample == 7 { 'vector_compare_undef' } else if sample in [8, 14] { 'vector_compare_frozen' } else if sample == 9 { 'vector_compare_old' } else if sample in [10, 11, 15] { 'vector_compare_samesign' } else if sample == 12 { 'vector_compare_constant' } else { 'vector_compare' }
			compare_command := sm_send(queue, c'commandBuffer'); compare_encoder := sm_send(compare_command, c'computeCommandEncoder')
			compare_pipeline := sm_test_compute_pipeline(d, library, compare_name, unsafe { nil }); assert compare_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(compare_encoder, c'setComputePipelineState:', compare_pipeline) }
			sm_test_compute_buffer(compare_encoder, a, 0, 0); sm_test_compute_buffer(compare_encoder, b, 0, 3); sm_test_compute_buffer(compare_encoder, output, 4, 7)
			sm_test_compute_dispatch(compare_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(compare_encoder, c'endEncoding'); objc_release(compare_pipeline)
			compare_xword := [u32(0), 0x80000000, 0x3f803c00, 0x7f807c01, 0x7fc17e55, 0, 0, 0, 0, 0, 0x80000000, 0x80000000, 0, 0, 0, 0x80000000]![sample]
			compare_yword := [u32(0), 0, 0x3f803c00, 0x7f807c01, 0x80000000, 0, 0, 0, 0, 0, 0, 0x80000000, 0, 0, 1, 0]![sample]
			compare_index := [u32(0), 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 2, 0, 1]![sample]
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = compare_xword; *(&u32(bp)) = compare_yword; *(&u32(bp + 4)) = compare_index }
			sm_call(compare_command, c'commit')
			if sample in [6, 7, 9, 10, 13] {
				assert sm_send(compare_command, c'status') == 5 && sm_send(compare_command, c'error') != 0
				for i in 0 .. 6 { assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == if i == 0 && sample in [6, 10] { u32(0) } else { u32(0xcccccccc) } }
			} else {
				assert sm_send(compare_command, c'status') == 4
				for k in 0 .. 3 {
					compare_bit := if sample in [8, 14] { u32(0) } else if compare_index == 1 { u32(1) } else if k == 0 { u32(compare_xword == compare_yword) } else if sample == 1 { u32(1) } else if sample in [3, 4] { u32(0) } else { u32(compare_xword == compare_yword) }
					assert unsafe { *(&u32(outp + u64(4 + k * 8))) } == compare_bit
					assert unsafe { *(&u32(outp + u64(8 + k * 8))) } == if compare_bit != 0 { u32(7) } else { u32(11) }
				}
			}
		}
		sm_test_vector_binary_dispatches(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_fneg_dispatches(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_float_dispatches(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_integer_vector_casts(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_bitcasts(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_precision(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_int_float(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_float_int(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_sign_intrinsics(d, library, queue, a, b, output, ap, bp, outp)
		sm_test_vector_round_intrinsics(d, library, queue, a, b, output, ap, bp, outp)
		for i in 0 .. 8 { unsafe { *(&u32(outp + u64(i * 4))) = vector_saved[i] } }
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
		poly_left := sm_test_buffer(d, 56, 0); poly_right := sm_test_buffer(d, 56, 0); poly_output := sm_test_buffer(d, 224, 0)
		polyap := sm_send(poly_left, c'contents'); polybp := sm_send(poly_right, c'contents'); polyp := sm_send(poly_output, c'contents')
		unsafe { C.memset(voidptr(polyp), 0xcc, 224) }
		poly_command := sm_send(queue, c'commandBuffer'); poly_encoder := sm_send(poly_command, c'computeCommandEncoder')
		poly_pipeline := sm_test_compute_pipeline(d, library, 'polynomial', unsafe { nil }); assert poly_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(poly_encoder, c'setComputePipelineState:', poly_pipeline) }
		for i in 0 .. 7 {
			sm_test_compute_buffer(poly_encoder, poly_left, u64(i * 8), 0); sm_test_compute_buffer(poly_encoder, poly_right, u64(i * 8), 3); sm_test_compute_buffer(poly_encoder, poly_output, u64(i * 32), 7)
			sm_test_compute_dispatch(poly_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(poly_encoder, c'endEncoding'); objc_release(poly_pipeline); objc_release(poly_left); objc_release(poly_right); objc_release(poly_output)
		for i, value in [u64(3), 0xffffffffffffffff, 0x8000000000000000, 0x80000000, 0x0123456789abcdef, 0, 1]! { unsafe { *(&u64(polyap + u64(i * 8))) = value } }
		for i, value in [u64(3), 0xffffffffffffffff, 2, 2, 1, 0xffffffffffffffff, 0x8000000000000000]! { unsafe { *(&u64(polybp + u64(i * 8))) = value } }
		for i in 0 .. 224 { assert unsafe { *(&u8(polyp + u64(i))) } == 0xcc }
		sm_call(poly_command, c'commit'); assert sm_send(poly_command, c'status') == 4
		for i, expected in [u64(5), 3, 5, 3, 0x55555555, 0xffffffff, 0x5555555555555555, 0xffffffffffffffff, 0, 0, 0, 0x8000000000000000, 0, 0x80000000, 0x100000000, 0x80000000, 0x89abcdef, 0x89abcdef, 0x0123456789abcdef, 0x0123456789abcdef, 0, 0, 0, 0, 0, 1, 0x8000000000000000, 1]! { assert unsafe { *(&u64(polyp + u64(i * 8))) } == expected }
		for kernel_name in ['overflowing', 'frozen_overflowing', 'selected_overflowing', 'inserted_overflowing'] {
			ov_left := sm_test_buffer(d, 56, 0); ov_right := sm_test_buffer(d, 56, 0); ov_output := sm_test_buffer(d, 784, 0)
			ovap := sm_send(ov_left, c'contents'); ovbp := sm_send(ov_right, c'contents'); ovp := sm_send(ov_output, c'contents')
			unsafe { C.memset(voidptr(ovp), 0xcc, 784) }
			ov_command := sm_send(queue, c'commandBuffer'); ov_encoder := sm_send(ov_command, c'computeCommandEncoder')
			ov_pipeline := sm_test_compute_pipeline(d, library, kernel_name, unsafe { nil }); assert ov_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(ov_encoder, c'setComputePipelineState:', ov_pipeline) }
			for i in 0 .. 7 {
				sm_test_compute_buffer(ov_encoder, ov_left, u64(i * 8), 0); sm_test_compute_buffer(ov_encoder, ov_right, u64(i * 8), 3); sm_test_compute_buffer(ov_encoder, ov_output, u64(i * 112), 7)
				sm_test_compute_dispatch(ov_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			}
			sm_call(ov_encoder, c'endEncoding'); objc_release(ov_pipeline); objc_release(ov_left); objc_release(ov_right); objc_release(ov_output)
			for i, value in [u64(0xffffffffffffffff), 0x7fffffff, 0x80000000, 0, 0xffffffffffffffff, 0x8000000000000000, 3]! { unsafe { *(&u64(ovap + u64(i * 8))) = value } }
			for i, value in [u64(1), 1, 0xffffffff, 1, 2, 2, 7]! { unsafe { *(&u64(ovbp + u64(i * 8))) = value } }
			for i in 0 .. 784 { assert unsafe { *(&u8(ovp + u64(i))) } == 0xcc }
			sm_call(ov_command, c'commit'); assert sm_send(ov_command, c'status') == 4
			insert_values := [u64(1), 1, 0xffffffff, 1, 2, 2, 7]!
			for i, row in [
				[u64(0), 0, 0, 1, 0xfffffffe, 0, 0xfffffffe, 0, 0xffffffff, 0, 0xffffffff, 0, 0xffffffffffffffff, 0],
				[u64(0x80000000), 1, 0x80000000, 0, 0x7ffffffe, 0, 0x7ffffffe, 0, 0x7fffffff, 0, 0x7fffffff, 0, 0x7fffffff, 0],
				[u64(0x7fffffff), 1, 0x7fffffff, 1, 0x80000001, 0, 0x80000001, 1, 0x80000000, 1, 0x80000000, 1, 0x7fffffff80000000, 0],
				[u64(1), 0, 1, 0, 0xffffffff, 0, 0xffffffff, 1, 0, 0, 0, 0, 0, 0],
				[u64(1), 0, 1, 1, 0xfffffffd, 0, 0xfffffffd, 0, 0xfffffffe, 0, 0xfffffffe, 1, 0xfffffffffffffffe, 1],
				[u64(2), 0, 2, 0, 0xfffffffe, 0, 0xfffffffe, 1, 0, 0, 0, 0, 0, 1],
				[u64(10), 0, 10, 0, 0xfffffffc, 0, 0xfffffffc, 1, 21, 0, 21, 0, 21, 0],
			] { for j, original in row { expected := if kernel_name == 'selected_overflowing' && i !in [2, 3, 6] { u64(0) } else if kernel_name == 'inserted_overflowing' && (j == 12 || (j < 12 && j % 4 == 0)) { insert_values[i] } else if kernel_name == 'inserted_overflowing' && j < 12 && j % 4 == 3 { u64(i in [2, 3, 6]) } else { original }; assert unsafe { *(&u64(ovp + u64(i * 112 + j * 8))) } == expected } }
			pair_output := sm_test_buffer(d, 144, 0); pairp := sm_send(pair_output, c'contents'); unsafe { C.memset(voidptr(pairp), 0xcc, 144) }
			pair_command := sm_send(queue, c'commandBuffer'); pair_encoder := sm_send(pair_command, c'computeCommandEncoder')
			pair_pipeline := sm_test_compute_pipeline(d, library, 'pair_choices', unsafe { nil }); assert pair_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(pair_encoder, c'setComputePipelineState:', pair_pipeline) }
			sm_test_compute_buffer(pair_encoder, a, 0, 0); sm_test_compute_buffer(pair_encoder, b, 0, 3); sm_test_compute_buffer(pair_encoder, pair_output, 0, 7)
			sm_test_compute_dispatch(pair_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(pair_encoder, c'endEncoding'); objc_release(pair_pipeline); objc_release(pair_output)
			for i in 0 .. 144 { assert unsafe { *(&u8(pairp + u64(i))) } == 0xcc }; sm_call(pair_command, c'commit'); assert sm_send(pair_command, c'status') == 4
			for i, expected in [u64(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 19, 0, 0, 1, 19, 1, 0, 1]! { assert unsafe { *(&u64(pairp + u64(i * 8))) } == expected }
		}
		for branch_kernel in ['branching', 'switching'] {
			branch_a := sm_test_buffer(d, 56, 0); branch_b := sm_test_buffer(d, 56, 0); branch_out := sm_test_buffer(d, 168, 0)
			branchap := sm_send(branch_a, c'contents'); branchbp := sm_send(branch_b, c'contents'); branchp := sm_send(branch_out, c'contents')
			unsafe { C.memset(voidptr(branchp), 0xcc, 168) }
			branch_command := sm_send(queue, c'commandBuffer'); branch_encoder := sm_send(branch_command, c'computeCommandEncoder')
			branch_pipeline := sm_test_compute_pipeline(d, library, branch_kernel, unsafe { nil }); assert branch_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(branch_encoder, c'setComputePipelineState:', branch_pipeline) }
			for i in 0 .. 7 {
				sm_test_compute_buffer(branch_encoder, branch_a, u64(i * 8), 0); sm_test_compute_buffer(branch_encoder, branch_b, u64(i * 8), 3); sm_test_compute_buffer(branch_encoder, branch_out, u64(i * 24), 7)
				sm_test_compute_dispatch(branch_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			}
			sm_call(branch_encoder, c'endEncoding'); objc_release(branch_pipeline); objc_release(branch_a); objc_release(branch_b); objc_release(branch_out)
			for i, value in [u64(3), 7, 0x8000000000000000, 0, 0xffffffffffffffff, 0x80000000, 1]! { unsafe { *(&u64(branchap + u64(i * 8))) = value } }
			for i, value in [u64(7), 3, 0xffffffffffffffff, 1, 1, 0xffffffff, 0xffffffffffffffff]! { unsafe { *(&u64(branchbp + u64(i * 8))) = value } }
			for i in 0 .. 168 { assert unsafe { *(&u8(branchp + u64(i))) } == 0xcc }
			sm_call(branch_command, c'commit'); assert sm_send(branch_command, c'status') == 4
			branch_expected := if branch_kernel == 'branching' { [u64(21), 0, 17, 7, 0, 29, 0x8000000000000000, 1, 17, 0, 0, 17, 0xffffffffffffffff, 0, 29, 0x7fffffff80000000, 0, 17, 0xffffffffffffffff, 0, 17]! } else { [u64(7), 0, 40, 3, 0, 40, 0xffffffffffffffff, 0, 40, 0, 0, 10, 0xffffffffffffffff, 0, 30, 0xffffffff, 0, 40, 1, 1, 20]! }
			for i, expected in branch_expected { assert unsafe { *(&u64(branchp + u64(i * 8))) } == expected }
		}
		for fill_name in ['byte_fill', 'byte_inline_fill'] {
			fill_input := sm_test_buffer(d, 12, 0); fill_output := sm_test_buffer(d, 72, 0)
			fillap := sm_send(fill_input, c'contents'); fillp := sm_send(fill_output, c'contents')
			unsafe { C.memset(voidptr(fillp), 0xcc, 72) }
			fill_command := sm_send(queue, c'commandBuffer'); fill_encoder := sm_send(fill_command, c'computeCommandEncoder')
			fill_pipeline := sm_test_compute_pipeline(d, library, fill_name, unsafe { nil }); assert fill_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(fill_encoder, c'setComputePipelineState:', fill_pipeline) }
			for i in 0 .. 3 {
				sm_test_compute_buffer(fill_encoder, fill_input, u64(i * 4), 0); sm_test_compute_buffer(fill_encoder, fill_input, 0, 3); sm_test_compute_buffer(fill_encoder, fill_output, u64(i * 24), 7)
				sm_test_compute_dispatch(fill_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			}
			sm_call(fill_encoder, c'endEncoding'); objc_release(fill_pipeline); objc_release(fill_input); objc_release(fill_output)
			for i, value in [u32(0), 0x127f, 0xabcdefff]! { unsafe { *(&u32(fillap + u64(i * 4))) = value } }
			for i in 0 .. 72 { assert unsafe { *(&u8(fillp + u64(i))) } == 0xcc }
			sm_call(fill_command, c'commit'); assert sm_send(fill_command, c'status') == 4
			for i in 0 .. 72 { assert unsafe { *(&u8(fillp + u64(i))) } == if i % 24 < 8 { u8(0xcc) } else { [u8(0), 0x7f, 0xff]![i / 24] } }
		}
		move_storage := sm_test_buffer(d, 448, 0); movep := sm_send(move_storage, c'contents')
		move_command := sm_send(queue, c'commandBuffer'); move_encoder := sm_send(move_command, c'computeCommandEncoder')
		move_pipeline := sm_test_compute_pipeline(d, library, 'byte_move', unsafe { nil }); assert move_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(move_encoder, c'setComputePipelineState:', move_pipeline) }
		move_offsets := [[0, 0]!, [0, 4]!, [4, 0]!, [0, 8]!, [8, 0]!, [0, 12]!, [12, 0]!]!
		for i, pair in move_offsets {
			sm_test_compute_buffer(move_encoder, move_storage, u64(i * 64 + pair[0]), 0); sm_test_compute_buffer(move_encoder, move_storage, 0, 3); sm_test_compute_buffer(move_encoder, move_storage, u64(i * 64 + pair[1]), 7)
			sm_test_compute_dispatch(move_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(move_encoder, c'endEncoding'); objc_release(move_pipeline); objc_release(move_storage)
		mut move_expected := [448]u8{}
		for i in 0 .. 448 { value := u8((i * 73) ^ (i >> 3)); move_expected[i] = value; unsafe { *(&u8(movep + u64(i))) = value } }
		for i, pair in move_offsets {
			src := i * 64 + pair[0] + 16; dst := i * 64 + pair[1] + 8
			mut first := [16]u8{}; for j in 0 .. 16 { first[j] = move_expected[src + j] }; for j in 0 .. 16 { move_expected[dst + j] = first[j] }
			mut second := [9]u8{}; for j in 0 .. 9 { second[j] = move_expected[dst + j] }; for j in 0 .. 9 { move_expected[dst + 1 + j] = second[j] }
		}
		for i in 0 .. 448 { assert unsafe { *(&u8(movep + u64(i))) } == u8((i * 73) ^ (i >> 3)) }
		sm_call(move_command, c'commit'); assert sm_send(move_command, c'status') == 4
		for i, value in move_expected { assert unsafe { *(&u8(movep + u64(i))) } == value }
		for copy_name in ['byte_copy', 'byte_inline_copy'] {
			copy_storage := sm_test_buffer(d, 256, 0); copy_input := sm_test_buffer(d, 32, 0); copy_output := sm_test_buffer(d, 24, 0)
			copyp := sm_send(copy_storage, c'contents'); copyap := sm_send(copy_input, c'contents'); copyout := sm_send(copy_output, c'contents')
			copy_command := sm_send(queue, c'commandBuffer'); copy_encoder := sm_send(copy_command, c'computeCommandEncoder')
			copy_pipeline := sm_test_compute_pipeline(d, library, copy_name, unsafe { nil }); assert copy_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(copy_encoder, c'setComputePipelineState:', copy_pipeline) }
			copy_offsets := [[0, 24]!, [0, 32]!, [32, 0]!, [16, 0]!]!
			for i, pair in copy_offsets {
				sm_test_compute_buffer(copy_encoder, copy_storage, u64(i * 64 + pair[0]), 0); sm_test_compute_buffer(copy_encoder, copy_storage, 0, 3); sm_test_compute_buffer(copy_encoder, copy_storage, u64(i * 64 + pair[1]), 7)
				sm_test_compute_dispatch(copy_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			}
			sm_test_compute_buffer(copy_encoder, copy_input, 0, 0); sm_test_compute_buffer(copy_encoder, copy_input, 0, 3); sm_test_compute_buffer(copy_encoder, copy_output, 0, 7)
			sm_test_compute_dispatch(copy_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			sm_call(copy_encoder, c'endEncoding'); objc_release(copy_input); objc_release(copy_output); objc_release(copy_storage)
			mut copy_expected := [256]u8{}
			for i in 0 .. 256 { value := u8((i * 73) ^ (i >> 3)); copy_expected[i] = value; unsafe { *(&u8(copyp + u64(i))) = value } }
			for i, pair in copy_offsets {
				src := i * 64 + pair[0] + 16; dst := i * 64 + pair[1]
				copy_expected[dst] = 17; for j in 0 .. 16 { copy_expected[dst + 8 + j] = copy_expected[src + j] }
			}
			for i in 0 .. 32 { unsafe { *(&u8(copyap + u64(i))) = u8(i * 13 + 1) } }; unsafe { C.memset(voidptr(copyout), 0xcc, 24) }
			for i in 0 .. 256 { assert unsafe { *(&u8(copyp + u64(i))) } == u8((i * 73) ^ (i >> 3)) }
			for i in 0 .. 24 { assert unsafe { *(&u8(copyout + u64(i))) } == 0xcc }
			sm_call(copy_command, c'commit'); assert sm_send(copy_command, c'status') == 4
			for i, value in copy_expected { assert unsafe { *(&u8(copyp + u64(i))) } == value }
			for i in 0 .. 24 { assert unsafe { *(&u8(copyout + u64(i))) } == if i == 0 { u8(17) } else if i >= 8 { u8((i + 8) * 13 + 1) } else { u8(0xcc) } }
			for offset in [u64(0), 8]! { // Partial overlap and identical ranges both reject.
				storage := sm_test_buffer(d, 64, 0); contents := sm_send(storage, c'contents'); unsafe { C.memset(voidptr(contents), 0xcc, 64) }
				bad := sm_send(queue, c'commandBuffer'); copy_bad_encoder := sm_send(bad, c'computeCommandEncoder')
				unsafe { SMSet(voidptr(C.ios_objc_msgsend))(copy_bad_encoder, c'setComputePipelineState:', copy_pipeline) }
				sm_test_compute_buffer(copy_bad_encoder, storage, 0, 0); sm_test_compute_buffer(copy_bad_encoder, storage, 0, 3); sm_test_compute_buffer(copy_bad_encoder, storage, offset, 7)
				sm_test_compute_dispatch(copy_bad_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(copy_bad_encoder, c'endEncoding'); objc_release(storage)
				sm_call(bad, c'commit'); assert sm_send(bad, c'status') == 5 && sm_send(bad, c'error') != 0
				for i in 0 .. 64 { assert unsafe { *(&u8(contents + u64(i))) } == 0xcc }
			}
			objc_release(copy_pipeline)
		}
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
		default_input := sm_test_buffer(d, 64, 0); default_output := sm_test_buffer(d, 192, 0)
		defaultap := sm_send(default_input, c'contents'); defaultp := sm_send(default_output, c'contents')
		unsafe { C.memset(voidptr(defaultp), 0xcc, 192) }
		default_command := sm_send(queue, c'commandBuffer'); default_encoder := sm_send(default_command, c'computeCommandEncoder')
		default_pipeline := sm_test_compute_pipeline(d, library, 'default_rounding', unsafe { nil }); assert default_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(default_encoder, c'setComputePipelineState:', default_pipeline) }
		for i in 0 .. 8 {
			sm_test_compute_buffer(default_encoder, default_input, u64(i * 8), 0); sm_test_compute_buffer(default_encoder, b, 0, 3); sm_test_compute_buffer(default_encoder, default_output, u64(i * 24), 7)
			sm_test_compute_dispatch(default_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(default_encoder, c'endEncoding'); objc_release(default_pipeline); objc_release(default_input); objc_release(default_output)
		for i, value in [u32(0x40200000), 0x4100, 0xc0200000, 0xc100, 0x3f000000, 0x3800, 0xbf000000, 0xb800, 0xff800001, 0xfc01, 0xff800000, 0xfc00, 0x80000000, 0x8000, 1, 1]! { unsafe { *(&u32(defaultap + u64(i * 4))) = value } }
		for i in 0 .. 192 { assert unsafe { *(&u8(defaultp + u64(i))) } == 0xcc }
		sm_call(default_command, c'commit'); assert sm_send(default_command, c'status') == 4
		for i, row in [[u32(0x40000000), 0x4000], [u32(0xc0000000), 0xc000], [u32(0), 0], [u32(0x80000000), 0x8000], [u32(0x7fc00000), 0x7e00], [u32(0xff800000), 0xfc00], [u32(0x80000000), 0x8000], [u32(0), 0]] { for j in 0 .. 6 { assert unsafe { *(&u32(defaultp + u64(i * 24 + j * 4))) } == row[if j < 3 { 0 } else { 1 }] } }
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
		for kernel_name in ['number_extrema', 'legacy_extrema'] {
			num_left := sm_test_buffer(d, 56, 0); num_right := sm_test_buffer(d, 56, 0); num_output := sm_test_buffer(d, 112, 0)
			numap := sm_send(num_left, c'contents'); numbp := sm_send(num_right, c'contents'); nump := sm_send(num_output, c'contents')
			unsafe { C.memset(voidptr(nump), 0xcc, 112) }
			num_command := sm_send(queue, c'commandBuffer'); num_encoder := sm_send(num_command, c'computeCommandEncoder')
			num_pipeline := sm_test_compute_pipeline(d, library, kernel_name, unsafe { nil }); assert num_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(num_encoder, c'setComputePipelineState:', num_pipeline) }
			for i in 0 .. 7 {
				sm_test_compute_buffer(num_encoder, num_left, u64(i * 8), 0); sm_test_compute_buffer(num_encoder, num_right, u64(i * 8), 3); sm_test_compute_buffer(num_encoder, num_output, u64(i * 16), 7)
				sm_test_compute_dispatch(num_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			}
			sm_call(num_encoder, c'endEncoding'); objc_release(num_pipeline); objc_release(num_left); objc_release(num_right); objc_release(num_output)
			for i, value in [u32(0), 0, 0x80000000, 0x8000, 0xff812345, 0xfc01, 0x3f800000, 0x3c00, 0x7f800001, 0x7c01, 0xff800000, 0xfc00, 1, 1]! { unsafe { *(&u32(numap + u64(i * 4))) = value } }
			for i, value in [u32(0x80000000), 0x8000, 0, 0, 0x3f800000, 0x3c00, 0x7fc12345, 0x7e55, 0xffc00001, 0xfe01, 0x7f800000, 0x7c00, 0x80000001, 0x8001]! { unsafe { *(&u32(numbp + u64(i * 4))) = value } }
			for i in 0 .. 112 { assert unsafe { *(&u8(nump + u64(i))) } == 0xcc }
			sm_call(num_command, c'commit'); assert sm_send(num_command, c'status') == 4
			for i, expected in [u32(0x80000000), 0, 0x8000, 0, 0x80000000, 0, 0x8000, 0, 0x3f800000, 0x3f800000, 0x3c00, 0x3c00, 0x3f800000, 0x3f800000, 0x3c00, 0x3c00, 0x7fc00000, 0x7fc00000, 0x7e00, 0x7e00, 0xff800000, 0x7f800000, 0xfc00, 0x7c00, 0x80000001, 1, 0x8001, 1]! { assert unsafe { *(&u32(nump + u64(i * 4))) } == expected }
		}
		class_input := sm_test_buffer(d, 80, 0); class_output := sm_test_buffer(d, 160, 0)
		classap := sm_send(class_input, c'contents'); classp := sm_send(class_output, c'contents')
		unsafe { C.memset(voidptr(classp), 0xcc, 160) }
		class_command := sm_send(queue, c'commandBuffer'); class_encoder := sm_send(class_command, c'computeCommandEncoder')
		class_pipeline := sm_test_compute_pipeline(d, library, 'classification', unsafe { nil }); assert class_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(class_encoder, c'setComputePipelineState:', class_pipeline) }
		for i in 0 .. 10 {
			sm_test_compute_buffer(class_encoder, class_input, u64(i * 8), 0); sm_test_compute_buffer(class_encoder, b, 0, 3); sm_test_compute_buffer(class_encoder, class_output, u64(i * 16), 7)
			sm_test_compute_dispatch(class_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(class_encoder, c'endEncoding'); objc_release(class_pipeline); objc_release(class_input); objc_release(class_output)
		for i, value in [u32(0x7f800001), 0x7c01, 0x7fc12345, 0x7e55, 0xff800000, 0xfc00, 0xbf800000, 0xbc00, 0x80000001, 0x8001, 0x80000000, 0x8000, 0, 0, 1, 1, 0x3f800000, 0x3c00, 0x7f800000, 0x7c00]! { unsafe { *(&u32(classap + u64(i * 4))) = value } }
		for i in 0 .. 160 { assert unsafe { *(&u8(classp + u64(i))) } == 0xcc }
		sm_call(class_command, c'commit'); assert sm_send(class_command, c'status') == 4
		for i in 0 .. 10 { for j, expected in [u32(i < 2), u32(i >= 3 && i <= 8), u32(i == 0), if i < 2 { u32(77) } else { u32(11) }]! { assert unsafe { *(&u32(classp + u64(i * 16 + j * 4))) } == expected } }
		for kernel_name in ['fused', 'optional_fused'] {
			fma_left := sm_test_buffer(d, 80, 0); fma_right := sm_test_buffer(d, 40, 0); fma_output := sm_test_buffer(d, 40, 0)
			fmaap := sm_send(fma_left, c'contents'); fmabp := sm_send(fma_right, c'contents'); fmap := sm_send(fma_output, c'contents')
			unsafe { C.memset(voidptr(fmap), 0xcc, 40) }
			fma_command := sm_send(queue, c'commandBuffer'); fma_encoder := sm_send(fma_command, c'computeCommandEncoder')
			fma_pipeline := sm_test_compute_pipeline(d, library, kernel_name, unsafe { nil }); assert fma_pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(fma_encoder, c'setComputePipelineState:', fma_pipeline) }
			for i in 0 .. 5 {
				sm_test_compute_buffer(fma_encoder, fma_left, u64(i * 16), 0); sm_test_compute_buffer(fma_encoder, fma_right, u64(i * 8), 3); sm_test_compute_buffer(fma_encoder, fma_output, u64(i * 8), 7)
				sm_test_compute_dispatch(fma_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
			}
			sm_call(fma_encoder, c'endEncoding'); objc_release(fma_pipeline); objc_release(fma_left); objc_release(fma_right); objc_release(fma_output)
			for i, value in [u32(0x3f800001), 0x3c01, 0xbf800000, 0xbc00, 0x7f7fffff, 0x7bff, 0xff7fffff, 0xfbff, 1, 1, 1, 1, 0x80000000, 0x8000, 0x80000000, 0x8000, 0x7f800000, 0x7c00, 0x3f800000, 0x3c00]! { unsafe { *(&u32(fmaap + u64(i * 4))) = value } }
			for i, value in [u32(0x3f7ffffe), 0x3bfe, 0x40000000, 0x4000, 0x3f000000, 0x3800, 0x3f800000, 0x3c00, 0, 0]! { unsafe { *(&u32(fmabp + u64(i * 4))) = value } }
			for i in 0 .. 40 { assert unsafe { *(&u8(fmap + u64(i))) } == 0xcc }
			sm_call(fma_command, c'commit'); assert sm_send(fma_command, c'status') == 4
			for i, expected in [u32(0xa8800000), 0x8010, 0x7f7fffff, 0x7bff, 2, 2, 0x80000000, 0x8000, 0x7fc00000, 0x7e00]! { assert unsafe { *(&u32(fmap + u64(i * 4))) } == expected }
		}
		scale_input := sm_test_buffer(d, 56, 0); scale_exponents := sm_test_buffer(d, 28, 0); scale_output := sm_test_buffer(d, 56, 0)
		scaleap := sm_send(scale_input, c'contents'); scalebp := sm_send(scale_exponents, c'contents'); scalep := sm_send(scale_output, c'contents')
		unsafe { C.memset(voidptr(scalep), 0xcc, 56) }
		scale_command := sm_send(queue, c'commandBuffer'); scale_encoder := sm_send(scale_command, c'computeCommandEncoder')
		scale_pipeline := sm_test_compute_pipeline(d, library, 'scaling', unsafe { nil }); assert scale_pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(scale_encoder, c'setComputePipelineState:', scale_pipeline) }
		for i in 0 .. 7 {
			sm_test_compute_buffer(scale_encoder, scale_input, u64(i * 8), 0); sm_test_compute_buffer(scale_encoder, scale_exponents, u64(i * 4), 3); sm_test_compute_buffer(scale_encoder, scale_output, u64(i * 8), 7)
			sm_test_compute_dispatch(scale_encoder, c'dispatchThreads:threadsPerThreadgroup:', 1)
		}
		sm_call(scale_encoder, c'endEncoding'); objc_release(scale_pipeline); objc_release(scale_input); objc_release(scale_exponents); objc_release(scale_output)
		for i, value in [u32(0x3f800000), 0x3c00, 3, 3, 0x80000001, 0x8001, 0x7f7fffff, 0x7bff, 0x80000000, 0x8000, 0xff800000, 0xfc00, 0xff800001, 0xfc01]! { unsafe { *(&u32(scaleap + u64(i * 4))) = value } }
		for i, value in [u32(1), 0xffffffff, 0xffffffff, 1, 0x7fffffff, 0x80000000, 0]! { unsafe { *(&u32(scalebp + u64(i * 4))) = value } }
		for i in 0 .. 56 { assert unsafe { *(&u8(scalep + u64(i))) } == 0xcc }
		sm_call(scale_command, c'commit'); assert sm_send(scale_command, c'status') == 4
		for i, expected in [u32(0x40000000), 0x4000, 2, 2, 0x80000000, 0x8000, 0x7f800000, 0x7c00, 0x80000000, 0x8000, 0xff800000, 0xfc00, 0x7fc00000, 0x7e00]! { assert unsafe { *(&u32(scalep + u64(i * 4))) } == expected }
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
	println('IOS-SOFTWARE-METAL-COMPUTE: classic AIR metadata, scalar buffer pipelines, sparse/reordered bindings, empty/indexed/structured-gep/max/conversion/negation/freeze/flagged/disjoint/samesign/cast-flags/constant-vector-extract/vector-insert/vector-shuffle/vector-freeze/vector-select/vector-lane-select/vector-compare/vector-integer-binary/vector-floating-binary/vector-integer-cast/vector-bitcast/vector-precision/vector-int-float/vector-float-int/vector-sign-intrinsics/vector-round-intrinsics/bit-intrinsic/funnel/extrema/abs/saturating/saturating-convert/saturating-shift/bit-permutation/clmul/overflow-pair/pair-freeze/pair-select/pair-insert/forward-branches-PHIs/invariant-pointer-PHIs/address-space-cast/pointer-select/pointer-freeze-bitcast/pointer-compare/memset/inline-memset/memmove/memcpy/inline-memcpy/switch/float-sign/rounding/default-rounding/sqrt/floating-extrema/number-extrema/legacy-extrema/classification/fma/fmuladd/ldexp kernels, derived bounds, single-thread dispatch selectors, deferred execution, snapshots, aliasing, ordered blits, eleven encoding guards, pipeline rejection, poison-store failed completion and two drained runtimes PASS')
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
fn sm_test_reject_case(mode int) {
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
}
fn sm_test_reject(mode int, cycle int) {
	// macOS atfork hooks may allocate through ASan before fork returns in the
	// child. os.exec uses posix_spawn and starts with fresh sanitizer locks.
	result := os.exec([os.executable(), '--software-metal-blit-reject', mode.str()])
	expected := [
		'Metal commit requires ended encoders and an uncommitted buffer',
		'Metal wait requires a committed buffer',
		'Metal blit range exceeds buffer', 'Metal blit range exceeds buffer',
		'overlapping Metal blit ranges', 'Metal encoding has ended',
		'Metal encoder already ended',
		'Metal commit requires ended encoders and an uncommitted buffer',
		'Metal blit resources belong to another device',
		'Metal encoder requires an uncommitted buffer with no active encoder',
	][mode]
	base := os.getenv('VINIX_METAL_COMPUTE_CHECK_DIR'); assert base.len > 0
	os.write_file('${base}/blit-reject-${os.getpid()}-${cycle}-${mode}.log', result.output) or { panic(err) }
	assert result.exit_code == 1 && result.output.contains('iOS: ' + expected) && !result.output.contains('ERROR: AddressSanitizer') && !result.output.contains('runtime error:'), 'invalid Metal state/range: mode=${mode} exit=${result.exit_code} output=${result.output}'
	unsafe { result.output.free() }
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
	for cycle in 0 .. 2 {
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
		for mode in 0 .. 10 { sm_test_reject(mode, cycle) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn sm_test_worker() }; workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL: Objective-C buffer/queue/command/blit ABI, deferred ordered copies, bounds, retained resources, completion, 10 rejected states, eight workers and two drained runtimes PASS')
}

// Dispatch operands keep all widened intermediates within i64.
fn sm_vector_binary_expected(op u32, flags u64, bits u32, a u64, b u64) !(bool, u64) {
	modulus := i64(1) << bits; limit := modulus - 1; sign := modulus / 2
	x := i64(a & u64(limit)); y := i64(b & u64(limit))
	sx := if x >= sign { x - modulus } else { x }; sy := if y >= sign { y - modulus } else { y }
	if op in [u32(3), 4, 5, 6]! && (y == 0 || (op in [u32(4), 6]! && sx == -sign && sy == -1)) { return error('invalid division') }
	if op in [u32(7), 8, 9]! && y >= bits { return true, 0 }
	mut value := i64(0); mut signed_value := i64(0); mut poison := false
	match op {
		0 { value = x + y; signed_value = sx + sy }
		1 { value = x - y; signed_value = sx - sy }
		2 { value = x * y; signed_value = sx * sy }
		3 { value = x / y; poison = flags != 0 && value * y != x }
		4 { value = sx / sy; poison = flags != 0 && value * sy != sx }
		5 { value = x % y }
		6 { value = sx % sy }
		7 { value = x * (i64(1) << y); signed_value = sx * (i64(1) << y) }
		8 { value = x / (i64(1) << y); poison = flags != 0 && value * (i64(1) << y) != x }
		9 { value = sx >> y; poison = flags != 0 && value * (i64(1) << y) != sx }
		10 { value = x & y }
		11 { value = x | y; poison = flags != 0 && value != x + y }
		else { value = x ^ y }
	}
	if op in [u32(0), 1, 2, 7]! { poison = (flags & 1 != 0 && (value < 0 || value > limit)) || (flags & 2 != 0 && (signed_value < -sign || signed_value >= sign)) }
	return poison, u64(value) & u64(limit)
}

fn sm_vector_binary_instruction(op int, flags int) string {
	name := ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor'][op]
	return name + if flags == 0 { '' } else if op in [0, 1, 2, 7] { if flags == 1 { ' nuw' } else if flags == 2 { ' nsw' } else { ' nuw nsw' } } else if op == 11 { ' disjoint' } else { ' exact' }
}
fn sm_test_vector_binary_dispatches(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	for op in 0 .. 13 { max_flags := match op { 0, 1, 2, 7 { 3 } 3, 4, 8, 9, 11 { 1 } else { 0 } }; for flags in 0 .. max_flags + 1 { for sample in 0 .. 3 {
		name := 'vector_binary_${op}_${flags}'; command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
		pipeline := sm_test_compute_pipeline(device, library, name, unsafe { nil }); assert pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }
		sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
		sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
		x := if sample == 1 { u32(0xffffffff) } else { u32(7) }; y := u32(1)
		unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = x; *(&u32(bp)) = y; *(&u32(bp + 4)) = u32(sample) }
		poison, value := sm_vector_binary_expected(u32(op), u64(flags), 32, if sample == 1 { 8 } else { x }, if sample == 1 { 2 } else { y }) or { panic(err) }
		sm_call(command, c'commit')
		bad := sample == 2 || poison
		assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
		if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
		for i in 0 .. 6 { expected := if i == 0 { u32(17) } else if i == 1 && sample != 2 { if poison { u32(0) } else { u32(value) } } else if i == 2 && !bad { u32(value) } else { u32(0xcccccccc) }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected }
	} } }
	for sample, name in ['vector_binary_poison', 'vector_binary_poison', 'vector_binary_undef', 'vector_binary_frozen', 'vector_binary_sources', 'vector_binary_divide', 'vector_binary_signed_divide', 'vector_binary_signed_rem', 'vector_binary_overshift', 'vector_binary_chain'] {
		command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
		pipeline := sm_test_compute_pipeline(device, library, name, unsafe { nil }); assert pipeline != 0
		unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }
		sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
		sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
		index := if sample in [1, 4, 8, 9] { u32(1) } else { u32(0) }; x := if sample == 3 { u32(0xffffffff) } else { u32(7) }
		unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = x; *(&u32(bp)) = u32(1); *(&u32(bp + 4)) = index }
		sm_call(command, c'commit'); bad := sample in [1, 2, 5, 6, 7, 8]
		assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
		if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
		for i in 0 .. 6 {
			expected := if i == 0 { u32(17) } else if i == 1 && sample in [0, 1, 3, 4, 8, 9] { if sample == 0 { u32(8) } else if sample == 9 { u32(10) } else { u32(0) } } else if i == 2 && !bad { if sample == 0 { u32(8) } else if sample == 9 { u32(9) } else { u32(0) } } else { u32(0xcccccccc) }
			assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected
		}
	}
	assert completed == 61 && failed == 39
}

fn sm_vector_fneg_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); t := parts[2]; mode := parts[3]; bits := if t == 'half' { 16 } else { 32 }
	other := if mode in ['undef', 'source'] { 'undef' } else if mode in ['poison', 'result'] { 'poison' } else { 'bitcast (i${bits} ${u64(1) << u32(bits - 1)} to ${t})' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${t}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${t}> <${t} zeroinitializer, ${t} ${other}>, ${t} %x, i32 0\n')
	if mode == 'source' { source.write_string('%src = freeze <2 x ${t}> %a0\n') }
	source.write_string('%n = fneg <2 x ${t}> ${if mode == 'source' { '%src' } else { '%a0' }}\n %f = freeze <2 x ${t}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n') }
	if mode in ['double', 'chain'] { source.write_string('%doubled = fneg <2 x ${t}> %n\n') }
	if mode == 'chain' { source.write_string('%c = fcmp uno <2 x ${t}> %n, %n\n %s = select <2 x i1> %c, <2 x ${t}> %n, <2 x ${t}> %doubled\n %shuffled = shufflevector <2 x ${t}> %s, <2 x ${t}> %n, <2 x i32> <i32 1, i32 2>\n') }
	selected := match mode { 'result' { '%f' } 'old' { '%changed' } 'double' { '%doubled' } 'chain' { '%shuffled' } else { '%n' } }
	source.write_string('%old = extractelement <2 x ${t}> %f, i32 %r\n %new = extractelement <2 x ${t}> ${selected}, i32 ${if mode == 'chain' { '1' } else { '%r' }}\n')
	for i, value in ['old', 'new'] {
		source.write_string('%raw${i} = bitcast ${t} %${value} to i${bits}\n')
		if bits == 16 { source.write_string('%word${i} = zext i16 %raw${i} to i32\n') }
		source.write_string('%dst${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if bits == 16 { 'word' } else { 'raw' }}${i}, ptr addrspace(1) %dst${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_vector_fneg_dispatches(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	for format in ['half', 'float'] {
		bits := if format == 'half' { 16 } else { 32 }; sign := u32(1) << u32(bits - 1)
		words := if bits == 16 { [u32(0), 0x8000, 1, 0x8001, 0x3ff, 0x400, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7c01, 0xfc01, 0x7e55, 0xfe55, 0x3e00, 0xbe00] } else { [u32(0), 0x80000000, 1, 0x80000001, 0x7fffff, 0x800000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7f800001, 0xff800001, 0x7fc12345, 0xffc12345, 0x3fc00000, 0xbfc00000] }
		for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'double', 'chain'] { for sample in 0 .. if mode == 'raw' { 16 } else { 1 } {
			command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
			pipeline := sm_test_compute_pipeline(device, library, 'vector_fneg_${format}_${mode}', unsafe { nil }); assert pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }
			sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
			sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
			// The deferred command must see these writes made after encoding.
			x := words[sample]; index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = x; *(&u32(bp)) = index }
			sm_call(command, c'commit'); bad := mode in ['poison', 'undef']
			assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
			if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
			negated := if x < sign { x + sign } else { x - sign }
			first := if mode in ['poison', 'result'] { u32(0) } else if mode == 'source' { sign } else { negated }
			second := if mode == 'old' || mode == 'result' { u32(0) } else if mode == 'double' { x } else { first }
			for i in 0 .. 6 {
				expected := if i == 0 { u32(17) } else if i == 1 && mode != 'undef' { first } else if i == 2 && !bad { second } else { u32(0xcccccccc) }
				assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${format} ${mode} sample=${sample} word=${i}'
			}
		} }
	}
	assert completed == 42 && failed == 4
}

fn sm_float_words(bits int) []u32 {
	// 0,-0,1,-1,2,-2,3,-3,.5,-.5,inf,-inf,NaN,max,minsub,
	// 2*minsub,3*minsub,5*minsub,1.5,SNaN,negative QNaN.
	return if bits == 16 { [u32(0), 0x8000, 0x3c00, 0xbc00, 0x4000, 0xc000, 0x4200, 0xc200, 0x3800, 0xb800, 0x7c00, 0xfc00, 0x7e00, 0x7bff, 1, 2, 3, 5, 0x3e00, 0x7c01, 0xfe55] } else { [u32(0), 0x80000000, 0x3f800000, 0xbf800000, 0x40000000, 0xc0000000, 0x40400000, 0xc0400000, 0x3f000000, 0xbf000000, 0x7f800000, 0xff800000, 0x7fc00000, 0x7f7fffff, 1, 2, 3, 5, 0x3fc00000, 0x7f800001, 0xffc12345] }
}
fn sm_vector_float_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); t := parts[2]; operation := parts[3].int(); mode := parts[4..].join('_'); bits := if t == 'half' { 16 } else { 32 }
	seven := if bits == 16 { u32(0x4700) } else { u32(0x40e00000) }; words := sm_float_words(bits)
	a := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source_left'] { 'undef' } else { '<${t} zeroinitializer, ${t} bitcast (i${bits} ${seven} to ${t})>' }
	b := if mode == 'source_right' { 'undef' } else { '<${t} zeroinitializer, ${t} bitcast (i${bits} ${words[4]} to ${t})>' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${t}, ptr addrspace(2) %a, align 1\n %y = load ${t}, ptr addrspace(2) %b, align 1\n %rp = getelementptr i8, ptr addrspace(2) %b, i64 4\n %r = load i32, ptr addrspace(2) %rp, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${t}> ${a}, ${t} %x, i32 0\n %b0 = insertelement <2 x ${t}> ${b}, ${t} %y, i32 0\n')
	if mode == 'source_left' { source.write_string('%src = freeze <2 x ${t}> %a0\n') }
	if mode == 'source_right' { source.write_string('%src = freeze <2 x ${t}> %b0\n') }
	binary := ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'][operation]
	source.write_string('%n = ${binary} <2 x ${t}> ${if mode == 'source_left' { '%src' } else { '%a0' }}, ${if mode == 'source_right' { '%src' } else { '%b0' }}\n %f = freeze <2 x ${t}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n') }
	if mode == 'chain' { source.write_string('%added = fadd <2 x ${t}> %n, <${t} bitcast (i${bits} ${words[2]} to ${t}), ${t} bitcast (i${bits} ${words[2]} to ${t})>\n %neg = fneg <2 x ${t}> %added\n %c = fcmp oeq <2 x ${t}> %n, %n\n %selected = select <2 x i1> %c, <2 x ${t}> %neg, <2 x ${t}> %n\n %shuffled = shufflevector <2 x ${t}> %selected, <2 x ${t}> %n, <2 x i32> <i32 0, i32 2>\n %chained = fneg <2 x ${t}> %shuffled\n') }
	selected := if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'chain' { '%chained' } else { '%n' }
	for i, vector in ['%f', selected] {
		source.write_string('%v${i} = extractelement <2 x ${t}> ${vector}, i32 %r\n %raw${i} = bitcast ${t} %v${i} to i${bits}\n')
		if bits == 16 { source.write_string('%word${i} = zext i16 %raw${i} to i32\n') }
		source.write_string('%dst${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if bits == 16 { 'word' } else { 'raw' }}${i}, ptr addrspace(1) %dst${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_vector_float_dispatches(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	lhs := [2, 2, 3, 0, 1, 10, 11, 10, 10, 2, 3, 13, 14, 16, 19, 20]!
	rhs := [2, 4, 4, 1, 1, 2, 2, 10, 11, 0, 0, 13, 14, 15, 2, 1]!
	expected_words := [
		[4, 6, 2, 0, 1, 10, 11, 10, 12, 2, 3, 10, 15, 17, 12, 12]!,
		[0, 3, 7, 0, 0, 10, 11, 12, 10, 2, 3, 0, 0, 14, 12, 12]!,
		[2, 4, 5, 1, 0, 10, 11, 10, 11, 0, 1, 10, 0, 0, 12, 12]!,
		[2, 8, 9, 12, 12, 10, 11, 12, 12, 10, 11, 2, 2, 18, 12, 12]!,
		[0, 2, 3, 12, 12, 12, 12, 12, 12, 12, 12, 0, 0, 14, 12, 12]!,
	]!
	mut completed := 0; mut failed := 0
	for format in ['half', 'float'] {
		bits := if format == 'half' { 16 } else { 32 }; words := sm_float_words(bits)
		seven := if bits == 16 { u32(0x4700) } else { u32(0x40e00000) }
		ordinary := if bits == 16 { [u32(0x4880), 0x4500, 0x4b00, 0x4300, 0x3c00]! } else { [u32(0x41100000), 0x40a00000, 0x41600000, 0x40600000, 0x3f800000]! }
		chained := if bits == 16 { [u32(0x4900), 0x4600, 0x4b80, 0x4480, 0x4000]! } else { [u32(0x41200000), 0x40c00000, 0x41700000, 0x40900000, 0x40000000]! }
		for operation in 0 .. 5 { for mode in ['raw', 'poison', 'undef', 'source_left', 'source_right', 'result', 'old', 'chain'] { for sample in 0 .. if mode == 'raw' { 16 } else { 1 } {
			unsafe { *(&u32(ap)) = u32(0xffffffff); *(&u32(bp)) = u32(0xffffffff) }
			command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
			pipeline := sm_test_compute_pipeline(device, library, 'vector_fp_${format}_${operation}_${mode}', unsafe { nil }); assert pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }
			sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
			sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
			x := if mode == 'raw' { words[lhs[sample]] } else { seven }; y := if mode == 'raw' { words[rhs[sample]] } else { words[4] }
			index := if mode in ['poison', 'source_left', 'source_right', 'result'] { u32(1) } else { u32(0) }
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = x; *(&u32(bp)) = y; *(&u32(bp + 4)) = index }
			sm_call(command, c'commit'); bad := mode in ['poison', 'undef']
			assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
			if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
			first := if mode == 'raw' { words[expected_words[operation][sample]] } else if mode in ['poison', 'result'] { u32(0) } else if mode == 'source_left' { words[[4, 5, 0, 0, 0]![operation]] } else if mode == 'source_right' { if operation < 2 { seven } else { words[[0, 0, 0, 10, 12]![operation]] } } else { ordinary[operation] }
			second := if mode == 'old' { u32(0) } else if mode == 'chain' { chained[operation] } else { first }
			for i in 0 .. 6 {
				expected := if i == 0 { u32(17) } else if i == 1 && mode != 'undef' { first } else if i == 2 && !bad { second } else { u32(0xcccccccc) }
				assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${format} op=${operation} ${mode} sample=${sample} word=${i}'
			}
		} } }
	}
	assert completed == 210 && failed == 20
}

fn sm_integer_cast_expected(op int, flags int, source int, dest int, input u64) (bool, u64) {
	mut poison := op == 1 && flags == 1 && input >> u32(source - 1) & 1 != 0
	if op == 0 { for bit in dest .. source { value := input >> u32(bit) & 1; poison = poison || (flags & 1 != 0 && value != 0) || (flags & 2 != 0 && value != input >> u32(dest - 1) & 1) } }
	mut value := u64(0)
	for bit in 0 .. dest { v := if bit < source { input >> u32(bit) & 1 } else if op == 2 { input >> u32(source - 1) & 1 } else { u64(0) }; value |= v << u32(bit) }
	return poison, value
}
fn sm_integer_vector_cast_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); src := parts[2].int(); dst := parts[3].int(); op := parts[4].int(); flags := parts[5].int(); mode := parts[6]
	initial := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }
	instruction := ['trunc', 'zext', 'sext'][op] + if flags == 0 { '' } else if op == 1 { ' nneg' } else if flags == 1 { ' nuw' } else if flags == 2 { ' nsw' } else { ' nuw nsw' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i${src}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x i${src}> ${initial}, i${src} %x, i32 0\n')
	if mode == 'source' { source.write_string('%src = freeze <2 x i${src}> %a0\n') }
	source.write_string('%n = ${instruction} <2 x i${src}> ${if mode == 'source' { '%src' } else { '%a0' }} to <2 x i${dst}>\n %f = freeze <2 x i${dst}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x i${dst}> %f, i${dst} 1, i32 0\n') }
	if mode == 'chain' { source.write_string('%back = ${if op == 0 { 'zext' } else { 'trunc' }} <2 x i${dst}> %n to <2 x i${src}>\n %c = icmp eq <2 x i${src}> %back, zeroinitializer\n %wide = zext <2 x i1> %c to <2 x i64>\n') }
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'chain' { '%wide' } else { '%n' }] {
		bits := if i == 1 && mode == 'chain' { 64 } else { dst }
		source.write_string('%v${i} = extractelement <2 x i${bits}> ${vector}, i32 %r\n')
		if bits < 64 { source.write_string('%w${i} = zext i${bits} %v${i} to i64\n') }
		source.write_string('%d${i} = getelementptr i8, ptr addrspace(1) %out, i64 ${8 + i * 8}\n store i64 %${if bits == 64 { 'v' } else { 'w' }}${i}, ptr addrspace(1) %d${i}, align 1\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_integer_vector_casts(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	for widths in [[64, 1]!, [32, 8]!, [1, 64]!, [8, 32]!, [32, 64]!] {
		src := widths[0]; dst := widths[1]; mask := if src == 64 { ~u64(0) } else { (u64(1) << u32(src)) - 1 }
		words := [u64(0), 1, mask, u64(1) << u32(src - 1), (u64(1) << u32(src - 1)) - 1, (u64(1) << u32(src - 1)) + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]!
		for op in 0 .. 3 { if (op == 0) != (dst < src) { continue }; for flags in 0 .. if op == 0 { 4 } else if op == 1 { 2 } else { 1 } { for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'chain'] { for sample in 0 .. if mode == 'raw' { 8 } else { 1 } {
			unsafe { *(&u64(ap)) = ~u64(0); *(&u32(bp)) = u32(0xffffffff) }
			command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder'); pipeline := sm_test_compute_pipeline(device, library, 'vector_ic_${src}_${dst}_${op}_${flags}_${mode}', unsafe { nil }); assert pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
			sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
			x := if mode == 'raw' { words[sample] & mask } else { u64(0) }; index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u64(ap)) = x | ~mask; *(&u32(bp)) = index }
			poison, value := sm_integer_cast_expected(op, flags, src, dst, x); bad := mode in ['poison', 'undef'] || (mode == 'raw' && poison)
			first := if mode == 'raw' && !poison { value } else { u64(0) }; second := if mode in ['old', 'chain'] { u64(1) } else { first }
			sm_call(command, c'commit'); assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
			if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
			for i in 0 .. 24 { expected := if i < 4 { u8(u32(17) >> u32(i * 8)) } else if i >= 8 && i < 16 && mode != 'undef' { u8(first >> u32((i - 8) * 8)) } else if i >= 16 && !bad { u8(second >> u32((i - 16) * 8)) } else { u8(0xcc) }; assert unsafe { *(&u8(outp + u64(4 + i))) } == expected, '${src}->${dst} op=${op} flags=${flags} ${mode} sample=${sample} byte=${i}' }
		} } } }
	}
	assert completed == 156 && failed == 82
}

fn sm_vector_bitcast_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); bits := parts[2].int(); direction := parts[3].int(); mode := parts[4]
	fp := if bits == 16 { 'half' } else { 'float' }; src := if direction == 0 { 'i${bits}' } else { fp }; dst := if direction == 0 { fp } else { 'i${bits}' }
	initial := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${src}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${src}> ${initial}, ${src} %x, i32 0\n')
	if mode == 'source' { source.write_string('%src = freeze <2 x ${src}> %a0\n') }
	source.write_string('%n = bitcast <2 x ${src}> ${if mode == 'source' { '%src' } else { '%a0' }} to <2 x ${dst}>\n %f = freeze <2 x ${dst}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${dst}> %n, ${dst} zeroinitializer, i32 0\n') }
	if mode == 'roundtrip' { source.write_string('%back = bitcast <2 x ${dst}> %n to <2 x ${src}>\n') }
	if mode == 'chain' { if direction == 1 { source.write_string('%fp = bitcast <2 x ${dst}> %n to <2 x ${fp}>\n') }; source.write_string('%neg = fneg <2 x ${fp}> ${if direction == 0 { '%n' } else { '%fp' }}\n %words = bitcast <2 x ${fp}> %neg to <2 x i${bits}>\n %cmp = icmp eq <2 x i${bits}> %words, %words\n %chain = select <2 x i1> %cmp, <2 x i${bits}> %words, <2 x i${bits}> zeroinitializer\n') }
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'roundtrip' { '%back' } else if mode == 'chain' { '%chain' } else { '%n' }] {
		t := if i == 1 && mode == 'chain' { 'i${bits}' } else if i == 1 && mode == 'roundtrip' { src } else { dst }
		source.write_string('%v${i} = extractelement <2 x ${t}> ${vector}, i32 %r\n')
		if t == fp { source.write_string('%raw${i} = bitcast ${t} %v${i} to i${bits}\n') }
		if bits == 16 { source.write_string('%word${i} = zext i16 %${if t == fp { 'raw' } else { 'v' }}${i} to i32\n') }
		source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if bits == 16 { 'word' } else if t == fp { 'raw' } else { 'v' }}${i}, ptr addrspace(1) %d${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_vector_bitcasts(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	for bits in [16, 32] { for direction in 0 .. 2 {
		words := if bits == 16 { [u32(0), 0x8000, 1, 0x8001, 0x3ff, 0x400, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7c01, 0xfc01, 0x7e55, 0xfe55, 0x3e00, 0xbe00] } else { [u32(0), 0x80000000, 1, 0x80000001, 0x7fffff, 0x800000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7f800001, 0xff800001, 0x7fc12345, 0xffc12345, 0x3fc00000, 0xbfc00000] }
		for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'roundtrip', 'chain'] { for sample in 0 .. if mode == 'raw' { 16 } else { 1 } {
			unsafe { *(&u32(ap)) = u32(0xffffffff); *(&u32(bp)) = u32(0xffffffff) }
			command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder'); pipeline := sm_test_compute_pipeline(device, library, 'vector_bc_${bits}_${direction}_${mode}', unsafe { nil }); assert pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
			sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
			x := if mode == 'raw' { words[sample] } else { words[10] }; index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = x; *(&u32(bp)) = index }
			sm_call(command, c'commit'); bad := mode in ['poison', 'undef']; assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
			if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
			first := if mode in ['poison', 'source', 'result'] { u32(0) } else { x }; second := if mode == 'old' { u32(0) } else if mode == 'chain' { x ^ (u32(1) << u32(bits - 1)) } else { first }
			for i in 0 .. 6 { expected := if i == 0 { u32(17) } else if i == 1 && mode != 'undef' { first } else if i == 2 && !bad { second } else { u32(0xcccccccc) }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${bits} direction=${direction} ${mode} sample=${sample} word=${i}' }
		} }
	} }
	assert completed == 84 && failed == 8
}

fn sm_vector_precision_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); bits := parts[2].int(); mode := parts[3]; destbits := if bits == 16 { 32 } else { 16 }
	src := if bits == 16 { 'half' } else { 'float' }; dst := if bits == 16 { 'float' } else { 'half' }; operation := if bits == 16 { 'fpext' } else { 'fptrunc' }; opposite := if bits == 16 { 'fptrunc' } else { 'fpext' }
	initial := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${src}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${src}> ${initial}, ${src} %x, i32 0\n')
	if mode == 'source' { source.write_string('%src = freeze <2 x ${src}> %a0\n') }
	source.write_string('%n = ${operation} <2 x ${src}> ${if mode == 'source' { '%src' } else { '%a0' }} to <2 x ${dst}>\n %f = freeze <2 x ${dst}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${dst}> %n, ${dst} zeroinitializer, i32 0\n') }
	if mode == 'roundtrip' { source.write_string('%back = ${opposite} <2 x ${dst}> %n to <2 x ${src}>\n') }
	if mode == 'chain' { source.write_string('%neg = fneg <2 x ${dst}> %n\n %words = bitcast <2 x ${dst}> %neg to <2 x i${destbits}>\n %cmp = icmp eq <2 x i${destbits}> %words, %words\n %chain = select <2 x i1> %cmp, <2 x i${destbits}> %words, <2 x i${destbits}> zeroinitializer\n') }
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'roundtrip' { '%back' } else if mode == 'chain' { '%chain' } else { '%n' }] {
		width := if i == 1 && mode == 'roundtrip' { bits } else { destbits }; integer := i == 1 && mode == 'chain'; t := if integer { 'i${width}' } else if i == 1 && mode == 'roundtrip' { src } else { dst }
		source.write_string('%v${i} = extractelement <2 x ${t}> ${vector}, i32 %r\n')
		if !integer { source.write_string('%raw${i} = bitcast ${t} %v${i} to i${width}\n') }
		if width == 16 { source.write_string('%word${i} = zext i16 %${if integer { 'v' } else { 'raw' }}${i} to i32\n') }
		source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if width == 16 { 'word' } else if integer { 'v' } else { 'raw' }}${i}, ptr addrspace(1) %d${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_vector_precision(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	for bits in [16, 32] {
		destbits := if bits == 16 { 32 } else { 16 }
		words := if bits == 16 { [u32(0), 0x8000, 1, 0x8001, 0x3ff, 0x400, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7c01, 0xfc01, 0x7e55, 0xfe55, 0x3c00, 0xbc00, 0x3555, 0x3e00, 0x7bfe, 0x4000] } else { [u32(0), 0x80000000, 1, 0x80000001, 0x33000000, 0x33000001, 0x33c00000, 0x387fdfff, 0x387fe000, 0x3f801000, 0x3f801001, 0x3f803000, 0xbf803000, 0x477fe000, 0x477fefff, 0x477ff000, 0xc77ff000, 0x7f7fffff, 0x7f800000, 0xff800000, 0x7f800001, 0xffc12345, 0x3fc00000, 0x3eaaaaab] }
		results := if bits == 16 { [u32(0), 0x80000000, 0x33800000, 0xb3800000, 0x387fc000, 0x38800000, 0x477fe000, 0xc77fe000, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000, 0x7fc00000, 0x7fc00000, 0x3f800000, 0xbf800000, 0x3eaaa000, 0x3fc00000, 0x477fc000, 0x40000000] } else { [u32(0), 0x8000, 0, 0x8000, 0, 1, 2, 0x3ff, 0x400, 0x3c00, 0x3c01, 0x3c02, 0xbc02, 0x7bff, 0x7bff, 0x7c00, 0xfc00, 0x7c00, 0x7c00, 0xfc00, 0x7e00, 0x7e00, 0x3e00, 0x3555] }
		assert words.len == results.len
		for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'roundtrip', 'chain'] { for sample in 0 .. if mode == 'raw' { words.len } else { 1 } {
			unsafe { *(&u32(ap)) = u32(0xffffffff); *(&u32(bp)) = u32(0xffffffff) }
			command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder'); pipeline := sm_test_compute_pipeline(device, library, 'vector_pc_${bits}_${mode}', unsafe { nil }); assert pipeline != 0
			unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
			sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
			x := if mode == 'raw' { words[sample] } else if bits == 16 { u32(0x3e00) } else { u32(0x3fc00000) }; index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }
			unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u32(ap)) = x; *(&u32(bp)) = index }
			sm_call(command, c'commit'); bad := mode in ['poison', 'undef']; assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
			if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
			first := if mode == 'raw' { results[sample] } else if mode in ['poison', 'source', 'result'] { u32(0) } else if destbits == 16 { u32(0x3e00) } else { u32(0x3fc00000) }; second := if mode == 'old' { u32(0) } else if mode == 'roundtrip' { x } else if mode == 'chain' { first ^ (u32(1) << u32(destbits - 1)) } else { first }
			for i in 0 .. 6 { expected := if i == 0 { u32(17) } else if i == 1 && mode != 'undef' { first } else if i == 2 && !bad { second } else { u32(0xcccccccc) }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${bits} ${mode} sample=${sample} word=${i}' }
		} }
	}
	assert completed == 54 && failed == 4
}

fn sm_vector_int_float_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); bits := parts[2].int(); dest := parts[3].int(); opcode := parts[4].int(); mode := parts[5]
	t := if dest == 16 { 'half' } else { 'float' }; operation := if opcode == 5 { 'uitofp' } else { 'sitofp' }
	initial := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load i${bits}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x i${bits}> ${initial}, i${bits} %x, i32 0\n')
	if mode == 'source' { source.write_string('%src = freeze <2 x i${bits}> %a0\n') }
	source.write_string('%n = ${operation} <2 x i${bits}> ${if mode == 'source' { '%src' } else { '%a0' }} to <2 x ${t}>\n %f = freeze <2 x ${t}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n') }
	if mode == 'bits' { source.write_string('%words = bitcast <2 x ${t}> %n to <2 x i${dest}>\n %back = bitcast <2 x i${dest}> %words to <2 x ${t}>\n') }
	if mode == 'chain' { source.write_string('%neg = fneg <2 x ${t}> %n\n %words = bitcast <2 x ${t}> %neg to <2 x i${dest}>\n %cmp = icmp eq <2 x i${dest}> %words, %words\n %chain = select <2 x i1> %cmp, <2 x i${dest}> %words, <2 x i${dest}> zeroinitializer\n') }
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'bits' { '%back' } else if mode == 'chain' { '%chain' } else { '%n' }] {
		integer := i == 1 && mode == 'chain'; typ := if integer { 'i${dest}' } else { t }
		source.write_string('%v${i} = extractelement <2 x ${typ}> ${vector}, i32 %r\n')
		if !integer { source.write_string('%raw${i} = bitcast ${t} %v${i} to i${dest}\n') }
		if dest == 16 { source.write_string('%word${i} = zext i16 %${if integer { 'v' } else { 'raw' }}${i} to i32\n') }
		source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if dest == 16 { 'word' } else if integer { 'v' } else { 'raw' }}${i}, ptr addrspace(1) %d${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}

fn sm_test_vector_int_float(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	references := sm_int_float_reference_values(); defer { unsafe { references.free() } }
	assert references.len == 128
	for pair, shape in [[1, 16], [1, 32], [8, 16], [16, 16], [16, 32], [32, 32], [64, 16], [64, 32]] {
		bits := shape[0]; dest := shape[1]; mask := if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 }; sign := u64(1) << u32(bits - 1)
		words := [u64(0), 1, mask, sign, sign - 1, sign + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]
		for op, opcode in [5, 6] { for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'bits', 'chain'] {
			if mode != 'raw' && pair !in [0, 7] { continue }
			for sample in 0 .. if mode == 'raw' { 8 } else { 1 } {
				unsafe { *(&u64(ap)) = ~u64(0); *(&u32(bp)) = u32(0xffffffff) }
				command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder'); pipeline := sm_test_compute_pipeline(device, library, 'vector_if_${bits}_${dest}_${opcode}_${mode}', unsafe { nil }); assert pipeline != 0
				unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
				sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding'); objc_release(pipeline)
				x := if mode == 'raw' { words[sample] & mask } else { u64(1) }; index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }
				unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u64(ap)) = x; *(&u32(bp)) = index }
				sm_call(command, c'commit'); bad := mode in ['poison', 'undef']; assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
				if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
				one := if dest == 16 { u32(0x3c00) } else { u32(0x3f800000) }; onebits := one | if bits == 1 && opcode == 6 { u32(1) << u32(dest - 1) } else { u32(0) }
				first := if mode == 'raw' { references[(pair * 2 + op) * 8 + sample] } else if mode in ['poison', 'source', 'result'] { u32(0) } else { onebits }; second := if mode == 'old' { u32(0) } else if mode == 'chain' { first ^ (u32(1) << u32(dest - 1)) } else { first }
				for i in 0 .. 6 { expected := if i == 0 { u32(17) } else if i == 1 && mode != 'undef' { first } else if i == 2 && !bad { second } else { u32(0xcccccccc) }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${bits} ${dest} ${opcode} ${mode} sample=${sample} word=${i}' }
			}
		} }
	}
	assert completed == 148 && failed == 8
}

// Exact native LLVM results captured by tests/ios/air-vector-int-float.v.
fn sm_int_float_reference_values() []u32 {
	return [
		u32(0x0), 0x3c00, 0x3c00, 0x3c00, 0x0, 0x0, 0x0, 0x3c00,
		0x0, 0xbc00, 0xbc00, 0xbc00, 0x0, 0x0, 0x0, 0xbc00,
		0x0, 0x3f800000, 0x3f800000, 0x3f800000, 0x0, 0x0, 0x0, 0x3f800000,
		0x0, 0xbf800000, 0xbf800000, 0xbf800000, 0x0, 0x0, 0x0, 0xbf800000,
		0x0, 0x3c00, 0x5bf8, 0x5800, 0x57f0, 0x5808, 0x5950, 0x4d40,
		0x0, 0x3c00, 0xbc00, 0xd800, 0x57f0, 0xd7f0, 0xd560, 0x4d40,
		0x0, 0x3c00, 0x7c00, 0x7800, 0x7800, 0x7800, 0x7955, 0x77c1,
		0x0, 0x3c00, 0xbc00, 0xf800, 0x7800, 0xf800, 0xf555, 0x77c1,
		0x0, 0x3f800000, 0x477fff00, 0x47000000, 0x46fffe00, 0x47000100, 0x472aaa00, 0x46f82a00,
		0x0, 0x3f800000, 0xbf800000, 0xc7000000, 0x46fffe00, 0xc6fffe00, 0xc6aaac00, 0x46f82a00,
		0x0, 0x3f800000, 0x4f800000, 0x4f000000, 0x4f000000, 0x4f000000, 0x4f2aaaab, 0x4efe94f8,
		0x0, 0x3f800000, 0xbf800000, 0xcf000000, 0x4f000000, 0xcf000000, 0xceaaaaab, 0x4efe94f8,
		0x0, 0x3c00, 0x7c00, 0x7c00, 0x7c00, 0x7c00, 0x7c00, 0x7c00,
		0x0, 0x3c00, 0xbc00, 0xfc00, 0x7c00, 0xfc00, 0xfc00, 0xfc00,
		0x0, 0x3f800000, 0x5f800000, 0x5f000000, 0x5f000000, 0x5f000000, 0x5f2aaaab, 0x5f1e377a,
		0x0, 0x3f800000, 0xbf800000, 0xdf000000, 0x5f000000, 0xdf000000, 0xdeaaaaab, 0xdec3910d
	]
}

fn sm_vector_float_int_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); bits := parts[2].int(); dest := parts[3].int(); opcode := parts[4].int(); mode := parts[5]
	t := if bits == 16 { 'half' } else { 'float' }; op := if opcode == 3 { 'fptoui' } else { 'fptosi' }
	initial := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${t}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${t}> ${initial}, ${t} %x, i32 0\n')
	if mode in ['source', 'invalid'] { source.write_string('%src = freeze <2 x ${t}> %a0\n') }
	source.write_string('%n = ${op} <2 x ${t}> ${if mode in ['source', 'invalid'] { '%src' } else { '%a0' }} to <2 x i${dest}>\n %f = freeze <2 x i${dest}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x i${dest}> %n, i${dest} 0, i32 0\n') }
	if mode == 'chain' { source.write_string('%complement = xor <2 x i${dest}> %n, <i${dest} -1, i${dest} -1>\n %cmp = icmp eq <2 x i${dest}> %complement, %complement\n %chain = select <2 x i1> %cmp, <2 x i${dest}> %complement, <2 x i${dest}> zeroinitializer\n') }
	if mode == 'integer' {
		if dest < 64 { source.write_string('%extended = zext <2 x i${dest}> %n to <2 x i64>\n %back = trunc <2 x i64> %extended to <2 x i${dest}>\n') } else { source.write_string('%narrow = trunc <2 x i64> %n to <2 x i32>\n %back = zext <2 x i32> %narrow to <2 x i64>\n') }
	}
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'chain' { '%chain' } else if mode == 'integer' { '%back' } else { '%n' }] {
		source.write_string('%v${i} = extractelement <2 x i${dest}> ${vector}, i32 %r\n')
		if dest < 64 { source.write_string('%wide${i} = zext i${dest} %v${i} to i64\n') }
		source.write_string('%d${i} = getelementptr i8, ptr addrspace(1) %out, i64 ${8 + i * 8}\n store i64 %${if dest < 64 { 'wide' } else { 'v' }}${i}, ptr addrspace(1) %d${i}, align 1\n')
	}
	source.write_string('ret void }\n')
}
fn sm_float_int_inputs(source int) []u64 {
	if source == 16 { return [u64(0), 0x8000, 0x3800, 0xb800, 0x3c00, 0xbc00, 0x3e00, 0xbe00, 0x5bfc, 0x5c00, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e55, 0x7c01] }
	return [u64(0), 0x80000000, 0x3f000000, 0xbf000000, 0x3f800000, 0xbf800000, 0x3fc00000, 0xbfc00000, 0x5f7fffff, 0x5f800000, 0x5effffff, 0xdf000000, 0x7f800000, 0xff800000, 0x7fc12345, 0x7f800001]
}
fn sm_test_vector_float_int(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	values := sm_float_int_reference_values(); tags := sm_float_int_poison_masks(); defer { unsafe { values.free(); tags.free() } }
	assert values.len == 256 && tags.len == 16
	for pair, shape in [[16, 1], [16, 8], [16, 16], [16, 64], [32, 1], [32, 8], [32, 32], [32, 64]] {
		bits := shape[0]; dest := shape[1]; mask := if dest == 64 { ~u64(0) } else { (u64(1) << u32(dest)) - 1 }; inputs := sm_float_int_inputs(bits)
		for op, opcode in [3, 4] { for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'chain', 'integer', 'invalid'] {
			if mode != 'raw' && pair !in [0, 7] { continue }
			pipeline := sm_test_compute_pipeline(device, library, 'vector_fi_${bits}_${dest}_${opcode}_${mode}', unsafe { nil }); assert pipeline != 0
			for sample in 0 .. if mode == 'raw' { 16 } else { 1 } {
				unsafe { *(&u64(ap)) = ~u64(0); *(&u32(bp)) = u32(0xffffffff) }
				command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
				unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
				sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding')
				x := if mode == 'raw' { inputs[sample] } else if mode == 'invalid' { if bits == 16 { u64(0x7e55) } else { u64(0x7fc12345) } } else { (if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }) | if dest == 1 && opcode == 4 { u64(1) << u32(bits - 1) } else { u64(0) } }; index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }
				unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u64(ap)) = x; *(&u32(bp)) = index }
				bad := mode in ['poison', 'undef', 'invalid'] || (mode == 'raw' && tags[pair * 2 + op] & (u16(1) << u32(sample)) != 0)
				sm_call(command, c'commit'); assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
				if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
				first := if mode == 'raw' { values[(pair * 2 + op) * 16 + sample] } else if mode in ['poison', 'source', 'result', 'invalid'] { u64(0) } else { u64(1) }; second := if mode == 'old' { u64(0) } else if mode == 'chain' { first ^ mask } else { first }
				for i in 0 .. 24 { expected := if i < 4 { u8(u32(17) >> u32(i * 8)) } else if i >= 8 && i < 16 && mode != 'undef' { u8(first >> u32((i - 8) * 8)) } else if i >= 16 && !bad { u8(second >> u32((i - 16) * 8)) } else { u8(0xcc) }; assert unsafe { *(&u8(outp + u64(4 + i))) } == expected, '${bits} ${dest} ${opcode} ${mode} sample=${sample} byte=${i}' }
			}
			objc_release(pipeline)
		} }
		unsafe { inputs.free() }
	}
	assert completed == 145 && failed == 143
}

// Defined native saturation/range oracle in tests/ios/air-vector-float-int.v.
// Poison entries use zero for the explicit first freeze store.
fn sm_float_int_reference_values() []u64 {
	return [
		u64(0x0), 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0xff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0xff, 0x1, 0xff,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0xff, 0x100, 0xffe0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0xffff, 0x1, 0xffff,
		0xff, 0x100, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0xff, 0x100, 0xffe0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff,
		0xff, 0x100, 0xffe0, 0xffffffffffff0020, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0xff, 0x1, 0xff,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0xffffffff, 0x1, 0xffffffff,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
		0xffffff0000000000, 0x0, 0x7fffff8000000000, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff,
		0x0, 0x0, 0x7fffff8000000000, 0x8000000000000000, 0x0, 0x0, 0x0, 0x0,
	]
}
fn sm_float_int_poison_masks() []u16 {
	return [u16(0xffa0), 0xff50, 0xfea0, 0xff00, 0xf8a0, 0xfc00, 0xf8a0, 0xf000, 0xffa0, 0xff50, 0xffa0, 0xff00, 0xffa0, 0xff00, 0xfaa0, 0xf300]
}

fn sm_vector_sign_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); bits := parts[2].int(); operation := parts[3].int(); mode := parts[4]; t := if bits == 16 { 'half' } else { 'float' }; op := if operation == 0 { 'fabs' } else { 'copysign' }
	left := if mode in ['left', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }; right := if mode == 'right' { 'poison' } else if mode in ['signundef', 'signsource'] { 'undef' } else { 'zeroinitializer' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${t}, ptr addrspace(2) %a, align 1\n %y = load ${t}, ptr addrspace(2) %b, align 1\n %rp = getelementptr i8, ptr addrspace(2) %b, i64 8\n %r = load i32, ptr addrspace(2) %rp, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${t}> ${left}, ${t} %x, i32 0\n %b0 = insertelement <2 x ${t}> ${right}, ${t} %y, i32 0\n')
	if mode == 'source' { source.write_string('%left = freeze <2 x ${t}> %a0\n') }
	if mode == 'signsource' { source.write_string('%right = freeze <2 x ${t}> %b0\n') }
	source.write_string('%n = call <2 x ${t}> @llvm.${op}.v2f${bits}(<2 x ${t}> ${if mode == 'source' { '%left' } else { '%a0' }}${if operation == 1 { ', <2 x ' + t + '> ' + if mode == 'signsource' { '%right' } else { '%b0' } } else { '' }})\n %f = freeze <2 x ${t}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n') }
	if mode == 'chain' { source.write_string('%neg = fneg <2 x ${t}> %n\n %words = bitcast <2 x ${t}> %neg to <2 x i${bits}>\n %cmp = icmp eq <2 x i${bits}> %words, %words\n %chain = select <2 x i1> %cmp, <2 x i${bits}> %words, <2 x i${bits}> zeroinitializer\n') }
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'chain' { '%chain' } else { '%n' }] {
		integer := i == 1 && mode == 'chain'; result_t := if integer { 'i${bits}' } else { t }
		source.write_string('%v${i} = extractelement <2 x ${result_t}> ${vector}, i32 %r\n')
		if !integer { source.write_string('%raw${i} = bitcast ${t} %v${i} to i${bits}\n') }
		if bits == 16 { source.write_string('%word${i} = zext i16 %${if integer { 'v' } else { 'raw' }}${i} to i32\n') }
		source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if bits == 16 { 'word' } else if integer { 'v' } else { 'raw' }}${i}, ptr addrspace(1) %d${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_vector_sign_intrinsics(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	for bits in [16, 32] {
		words := sm_float_int_inputs(bits); sign := u64(1) << u32(bits - 1)
		for operation in [0, 1] { for mode in ['raw', 'left', 'right', 'undef', 'signundef', 'source', 'signsource', 'result', 'old', 'chain'] {
			pipeline := sm_test_compute_pipeline(device, library, 'vector_si_${bits}_${operation}_${mode}', unsafe { nil }); assert pipeline != 0
			for sample in 0 .. if mode == 'raw' { 32 } else { 1 } {
				unsafe { *(&u64(ap)) = ~u64(0); *(&u64(bp)) = ~u64(0); *(&u32(bp + 8)) = u32(0xffffffff) }
				command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
				unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
				sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding')
				x := if mode == 'raw' { words[sample % 16] } else if bits == 16 { u64(0xfc01) } else { u64(0xff812345) }; y := if mode == 'raw' { words[(sample * 7 + 5) % 16] ^ if sample >= 16 { sign } else { u64(0) } } else { sign }; index := if mode in ['left', 'right', 'source', 'result'] { u32(1) } else { u32(0) }
				unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u64(ap)) = x; *(&u64(bp)) = y; *(&u32(bp + 8)) = index }
				bad := mode in ['left', 'undef'] || (operation == 1 && mode in ['right', 'signundef']); strict := mode == 'undef' || (operation == 1 && mode == 'signundef')
				sm_call(command, c'commit'); assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
				if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
				first := if mode in ['left', 'right', 'source', 'result'] { u64(0) } else { (x & (sign - 1)) | if operation == 1 { y & sign } else { u64(0) } }; second := if mode == 'old' { u64(0) } else if mode == 'chain' { first ^ sign } else { first }
				for i in 0 .. 6 { expected := if i == 0 { u32(17) } else if i == 1 && !strict { u32(first) } else if i == 2 && !bad { u32(second) } else { u32(0xcccccccc) }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${bits} ${operation} ${mode} sample=${sample} word=${i}' }
			}
			objc_release(pipeline)
		} }
		unsafe { words.free() }
	}
	assert completed == 152 && failed == 12
}

fn sm_vector_round_fixture(mut source strings.Builder, name string) {
	parts := name.split('_'); bits := parts[2].int(); operation := parts[3].int(); mode := parts[4]; t := if bits == 16 { 'half' } else { 'float' }; op := ['floor', 'ceil', 'trunc', 'round', 'roundeven', 'rint', 'nearbyint'][operation]
	initial := if mode in ['poison', 'result'] { 'poison' } else if mode in ['undef', 'source'] { 'undef' } else { 'zeroinitializer' }
	source.write_string('define void @${name}(ptr addrspace(2) %a, ptr addrspace(2) %b, ptr addrspace(1) %out) { %x = load ${t}, ptr addrspace(2) %a, align 1\n %r = load i32, ptr addrspace(2) %b, align 4\n store i32 17, ptr addrspace(1) %out, align 4\n %a0 = insertelement <2 x ${t}> ${initial}, ${t} %x, i32 0\n')
	if mode == 'source' { source.write_string('%source = freeze <2 x ${t}> %a0\n') }
	source.write_string('%n = call <2 x ${t}> @llvm.${op}.v2f${bits}(<2 x ${t}> ${if mode == 'source' { '%source' } else { '%a0' }})\n %f = freeze <2 x ${t}> %n\n')
	if mode == 'old' { source.write_string('%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n') }
	if mode == 'chain' { source.write_string('%neg = fneg <2 x ${t}> %n\n %again = call <2 x ${t}> @llvm.floor.v2f${bits}(<2 x ${t}> %neg)\n %words = bitcast <2 x ${t}> %again to <2 x i${bits}>\n %cmp = icmp eq <2 x i${bits}> %words, %words\n %chain = select <2 x i1> %cmp, <2 x i${bits}> %words, <2 x i${bits}> zeroinitializer\n') }
	for i, vector in ['%f', if mode == 'result' { '%f' } else if mode == 'old' { '%changed' } else if mode == 'chain' { '%chain' } else { '%n' }] {
		integer := i == 1 && mode == 'chain'; rt := if integer { 'i${bits}' } else { t }
		source.write_string('%v${i} = extractelement <2 x ${rt}> ${vector}, i32 %r\n')
		if !integer { source.write_string('%raw${i} = bitcast ${t} %v${i} to i${bits}\n') }
		if bits == 16 { source.write_string('%word${i} = zext i16 %${if integer { 'v' } else { 'raw' }}${i} to i32\n') }
		source.write_string('%d${i} = getelementptr i32, ptr addrspace(1) %out, i64 ${i + 1}\n store i32 %${if bits == 16 { 'word' } else if integer { 'v' } else { 'raw' }}${i}, ptr addrspace(1) %d${i}, align 4\n')
	}
	source.write_string('ret void }\n')
}
fn sm_test_vector_round_intrinsics(device u64, library u64, queue u64, a u64, b u64, output u64, ap u64, bp u64, outp u64) {
	mut completed := 0; mut failed := 0
	values := sm_round_reference_values(); defer { unsafe { values.free() } }; assert values.len == 336
	for element, bits in [16, 32] {
		words := sm_round_inputs(bits); sign := u64(1) << u32(bits - 1)
		for operation in 0 .. 7 { for mode in ['raw', 'poison', 'undef', 'source', 'result', 'old', 'chain'] {
			pipeline := sm_test_compute_pipeline(device, library, 'vector_rd_${bits}_${operation}_${mode}', unsafe { nil }); assert pipeline != 0
			for sample in 0 .. if mode == 'raw' { 24 } else { 1 } {
				unsafe { *(&u64(ap)) = ~u64(0); *(&u32(bp)) = u32(0xffffffff) }
				command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'computeCommandEncoder')
				unsafe { SMSet(voidptr(C.ios_objc_msgsend))(encoder, c'setComputePipelineState:', pipeline) }; sm_test_compute_buffer(encoder, a, 0, 0); sm_test_compute_buffer(encoder, b, 0, 3); sm_test_compute_buffer(encoder, output, 4, 7)
				sm_test_compute_dispatch(encoder, c'dispatchThreads:threadsPerThreadgroup:', 1); sm_call(encoder, c'endEncoding')
				index := if mode in ['poison', 'source', 'result'] { u32(1) } else { u32(0) }; x := if mode == 'raw' { words[sample] } else { words[7] }
				unsafe { C.memset(voidptr(outp + 4), 0xcc, 24); *(&u64(ap)) = x; *(&u32(bp)) = index }
				bad := mode in ['poison', 'undef']; strict := mode == 'undef'
				sm_call(command, c'commit'); assert sm_send(command, c'status') == if bad { u64(5) } else { u64(4) }
				if bad { assert sm_send(command, c'error') != 0; failed++ } else { completed++ }
				first := if index == 1 { u64(0) } else { values[(element * 7 + operation) * 24 + if mode == 'raw' { sample } else { 7 }] }; second := if mode == 'old' { u64(0) } else if mode == 'chain' { first ^ sign } else { first }
				for i in 0 .. 6 { expected := if i == 0 { u32(17) } else if i == 1 && !strict { u32(first) } else if i == 2 && !bad { u32(second) } else { u32(0xcccccccc) }; assert unsafe { *(&u32(outp + u64(4 + i * 4))) } == expected, '${bits} ${operation} ${mode} sample=${sample} word=${i}' }
			}
			objc_release(pipeline)
		} }
		unsafe { words.free() }
	}
	assert completed == 392 && failed == 28
}
fn sm_round_inputs(bits int) []u64 {
 if bits == 16 { return [u64(0), 0x8000, 1, 0x8001, 0x3800, 0xb800, 0x3e00, 0xbe00, 0x4100, 0xc100, 0x4300, 0xc300, 0x37ff, 0x3801, 0xb801, 0x3bff, 0x3ff, 0x400, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e55, 0xfc01] }
 return [u64(0), 0x80000000, 1, 0x80000001, 0x3f000000, 0xbf000000, 0x3fc00000, 0xbfc00000, 0x40200000, 0xc0200000, 0x40600000, 0xc0600000, 0x3effffff, 0x3f000001, 0xbf000001, 0x3f7fffff, 0x7fffff, 0x800000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc12345, 0xff812345]
}
// Independent host-double reference values for the 24 rounding inputs.
fn sm_round_reference_values() []u64 { return [
u64(0x0), 0x8000, 0x0, 0xbc00, 0x0, 0xbc00, 0x3c00, 0xc000, 0x4000, 0xc200, 0x4200, 0xc400, 0x0, 0x0, 0xbc00, 0x0, 0x0, 0x0, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x8000, 0x3c00, 0x8000, 0x3c00, 0x8000, 0x4000, 0xbc00, 0x4200, 0xc000, 0x4400, 0xc200, 0x3c00, 0x3c00, 0x8000, 0x3c00, 0x3c00, 0x3c00, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x8000, 0x0, 0x8000, 0x0, 0x8000, 0x3c00, 0xbc00, 0x4000, 0xc000, 0x4200, 0xc200, 0x0, 0x0, 0x8000, 0x0, 0x0, 0x0, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x8000, 0x0, 0x8000, 0x3c00, 0xbc00, 0x4000, 0xc000, 0x4200, 0xc200, 0x4400, 0xc400, 0x0, 0x3c00, 0xbc00, 0x3c00, 0x0, 0x0, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x8000, 0x0, 0x8000, 0x0, 0x8000, 0x4000, 0xc000, 0x4000, 0xc000, 0x4400, 0xc400, 0x0, 0x3c00, 0xbc00, 0x3c00, 0x0, 0x0, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x8000, 0x0, 0x8000, 0x0, 0x8000, 0x4000, 0xc000, 0x4000, 0xc000, 0x4400, 0xc400, 0x0, 0x3c00, 0xbc00, 0x3c00, 0x0, 0x0, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x8000, 0x0, 0x8000, 0x0, 0x8000, 0x4000, 0xc000, 0x4000, 0xc000, 0x4400, 0xc400, 0x0, 0x3c00, 0xbc00, 0x3c00, 0x0, 0x0, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0x7e00,
0x0, 0x80000000, 0x0, 0xbf800000, 0x0, 0xbf800000, 0x3f800000, 0xc0000000, 0x40000000, 0xc0400000, 0x40400000, 0xc0800000, 0x0, 0x0, 0xbf800000, 0x0, 0x0, 0x0, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
0x0, 0x80000000, 0x3f800000, 0x80000000, 0x3f800000, 0x80000000, 0x40000000, 0xbf800000, 0x40400000, 0xc0000000, 0x40800000, 0xc0400000, 0x3f800000, 0x3f800000, 0x80000000, 0x3f800000, 0x3f800000, 0x3f800000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
0x0, 0x80000000, 0x0, 0x80000000, 0x0, 0x80000000, 0x3f800000, 0xbf800000, 0x40000000, 0xc0000000, 0x40400000, 0xc0400000, 0x0, 0x0, 0x80000000, 0x0, 0x0, 0x0, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
0x0, 0x80000000, 0x0, 0x80000000, 0x3f800000, 0xbf800000, 0x40000000, 0xc0000000, 0x40400000, 0xc0400000, 0x40800000, 0xc0800000, 0x0, 0x3f800000, 0xbf800000, 0x3f800000, 0x0, 0x0, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
0x0, 0x80000000, 0x0, 0x80000000, 0x0, 0x80000000, 0x40000000, 0xc0000000, 0x40000000, 0xc0000000, 0x40800000, 0xc0800000, 0x0, 0x3f800000, 0xbf800000, 0x3f800000, 0x0, 0x0, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
0x0, 0x80000000, 0x0, 0x80000000, 0x0, 0x80000000, 0x40000000, 0xc0000000, 0x40000000, 0xc0000000, 0x40800000, 0xc0800000, 0x0, 0x3f800000, 0xbf800000, 0x3f800000, 0x0, 0x0, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
0x0, 0x80000000, 0x0, 0x80000000, 0x0, 0x80000000, 0x40000000, 0xc0000000, 0x40000000, 0xc0000000, 0x40800000, 0xc0800000, 0x0, 0x3f800000, 0xbf800000, 0x3f800000, 0x0, 0x0, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc00000,
] }
