// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
type SortMessage = fn (u64, u64, u64, u64, u64) u64
type SortRealMessage = fn (u64, u64, f64) u64
struct SortApi { native bool send u64 cls u64 strings u64 mutable_strings u64 dates u64 dictionaries u64 }
fn (api SortApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return objc_selector(name)
}
fn (api SortApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { SortMessage(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api SortApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0, 0) }
fn (api SortApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0, 0)) }
fn (api SortApi) date(value f64) u64 { return unsafe { SortRealMessage(voidptr(api.send))(api.dates, api.selector(c'dateWithTimeIntervalSinceReferenceDate:'), value) } }
fn (api SortApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0, 0) }
fn (api SortApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api SortApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api SortApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn sort_probe_string_copy(object u64, selector &char) u64 { return owned_string(string_text(object)) }
fn sort_probe_bad_copy(object u64, selector &char) u64 { return objc_new(ios_runtime.names['NSObject']) }
fn sort_probe_nil_copy(object u64, selector &char) u64 { return 0 }
fn (api SortApi) mutable_string(value &char) u64 {
	$if macos { if api.native { return api.retain(api.message(api.mutable_strings, c'stringWithUTF8String:', u64(value), 0, 0)) } }
	object := owned_string(ctext(u64(value))); objc_set_class(object, api.mutable_strings); return object
}
fn (api SortApi) change_string(object u64, value &char) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(value), 0, 0); return } }
	text := ctext(u64(value)); mut header := obj_header(object)
	C.free(header.text); header.text = unsafe { &char(C.malloc(usize(text.len + 1))) }; assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, text.str, usize(text.len)); header.text[text.len] = 0 }; header.text_length = text.len
}
fn sort_runtime_api() SortApi {
	mutable := objc_allocate_class(ios_runtime.names['NSString'], c'VinixSortMutableString', 0)
	assert mutable != 0 && objc_add_method(mutable, u64(c'copy'), u64(unsafe { voidptr(sort_probe_string_copy) }), c'@16@0:8')
	objc_register_class(mutable)
	return SortApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSSortDescriptor'], strings: ios_runtime.names['NSString'], mutable_strings: mutable, dates: ios_runtime.names['NSDate'], dictionaries: ios_runtime.names['NSMutableDictionary']}
}
__global sort_callback_api = SortApi{}
__global sort_callback_descriptor = u64(0)
__global sort_callback_reenter = bool(false)
__global sort_callback_calls = i64(0)
__global sort_key_callback_calls = i64(0)
__global sort_reversal_source = u64(0)
__global sort_reversal_key_copies = int(0)
fn sort_reversal_string_copy(object u64, selector &char) u64 {
	result := objc_retain(object)
	sort_reversal_key_copies++
	if sort_reversal_key_copies == 2 {
		assert sort_reversal_source != 0
		source := sort_reversal_source; sort_reversal_source = 0; objc_release(source)
	}
	return result
}
fn sort_callback_reader() {
	api := sort_callback_api; pool := api.pool()
	assert api.message(sort_callback_descriptor, c'ascending', 0, 0, 0) == 1
	api.drain(pool)
}
fn sort_custom_compare(object u64, selector u64, other u64) i64 {
	C.ios_ref_change(unsafe { &sort_callback_calls }, 1)
	if sort_callback_reenter { worker := spawn sort_callback_reader(); worker.wait() }
	return i64(read64(object + 8)) * 100 + i64(read64(other + 8))
}
fn sort_custom_key_path(object u64, selector u64, key u64) u64 {
	assert sort_callback_api.text(key) == 'fixture.value'
	C.ios_ref_change(unsafe { &sort_key_callback_calls }, 1)
	if sort_callback_reenter { worker := spawn sort_callback_reader(); worker.wait() }
	return read64(object + 16)
}
fn sort_custom_class(api SortApi) u64 {
	$if macos { if api.native {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixNativeSortValue', 0); assert cls != unsafe { nil }
		assert C.class_addIvar(cls, c'rank', 8, 3, c'q') && C.class_addIvar(cls, c'value', 8, 3, c'@')
		assert C.class_addMethod(cls, C.sel_registerName(c'compare:'), unsafe { voidptr(sort_custom_compare) }, c'q24@0:8@16')
		assert C.class_addMethod(cls, C.sel_registerName(c'fixtureCompare:'), unsafe { voidptr(sort_custom_compare) }, c'q24@0:8@16')
		assert C.class_addMethod(cls, C.sel_registerName(c'valueForKeyPath:'), unsafe { voidptr(sort_custom_key_path) }, c'@24@0:8@16')
		C.objc_registerClassPair(cls); return u64(cls)
	} }
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSortValue', 0); assert cls != 0
	assert objc_add_ivar(cls, c'rank', 8, 3, c'q') && objc_add_ivar(cls, c'value', 8, 3, c'@')
	assert objc_add_method(cls, u64(c'compare:'), u64(unsafe { voidptr(sort_custom_compare) }), c'q24@0:8@16')
	assert objc_add_method(cls, u64(c'fixtureCompare:'), u64(unsafe { voidptr(sort_custom_compare) }), c'q24@0:8@16')
	assert objc_add_method(cls, u64(c'valueForKeyPath:'), u64(unsafe { voidptr(sort_custom_key_path) }), c'@24@0:8@16')
	objc_register_class(cls); return cls
}

fn sort_construction_cases(api SortApi) {
	pool := api.pool()
	for construction in [c'alloc', c'new']! {
		object := api.message(api.cls, construction, 0, 0, 0)
		assert object != 0 && api.message(object, c'class', 0, 0, 0) == api.cls
		assert api.message(object, c'key', 0, 0, 0) == 0 && api.message(object, c'ascending', 0, 0, 0) == 0
		assert api.message(object, c'selector', 0, 0, 0) == 0 && api.message(object, c'comparator', 0, 0, 0) == 0
		assert read64(object + 8) == 0 && read64(object + 16) == 0 && read64(object + 24) == 0 && read64(object + 32) == 0
		assert api.message(object, c'init', 0, 0, 0) == object && api.message(object, c'init', 0, 0, 0) == object
		reversed := api.message(object, c'reversedSortDescriptor', 0, 0, 0)
		assert api.message(reversed, c'ascending', 0, 0, 0) == 1 && api.message(reversed, c'key', 0, 0, 0) == 0 && api.message(reversed, c'selector', 0, 0, 0) == api.selector(c'compare:')
		api.release(object)
	}
	for ascending in [u64(0), 1]! {
		for explicit_selector in [false, true]! {
			source := api.mutable_string(c'fixture.value')
			selector := if explicit_selector { api.selector(c'fixtureCompare:') } else { api.selector(c'compare:') }
			allocated := api.message(api.cls, c'alloc', 0, 0, 0)
			descriptor := if explicit_selector { api.message(allocated, c'initWithKey:ascending:selector:', source, ascending, selector) } else { api.message(allocated, c'initWithKey:ascending:', source, ascending, 0) }
			assert descriptor == allocated && api.message(descriptor, c'ascending', 0, 0, 0) == ascending
			key := api.message(descriptor, c'key', 0, 0, 0)
			assert key != source && api.text(key) == 'fixture.value' && read64(descriptor + 16) == key
			assert api.message(descriptor, c'selector', 0, 0, 0) == selector && read64(descriptor + 24) == selector
			assert api.message(descriptor, c'comparator', 0, 0, 0) == 0
			api.change_string(source, c'changed input'); api.release(source)
			assert api.text(api.message(descriptor, c'key', 0, 0, 0)) == 'fixture.value'
			assert api.message(descriptor, c'init', 0, 0, 0) == descriptor && api.message(descriptor, c'key', 0, 0, 0) == key
			for copy_selector in [c'copy', c'copyWithZone:']! {
				assert api.message(descriptor, copy_selector, 0, 0, 0) == descriptor
				if !api.native { assert obj_header(descriptor).refs == 2 }
				api.release(descriptor)
			}
			if !api.native {
				for zone in [false, true]! { assert objc_copy_value(descriptor, zone) == descriptor; api.release(descriptor) }
			}
			reversed := api.message(descriptor, c'reversedSortDescriptor', 0, 0, 0)
			reversed_again := api.message(descriptor, c'reversedSortDescriptor', 0, 0, 0)
			assert reversed != descriptor && reversed_again != descriptor && reversed_again != reversed
			assert api.message(reversed, c'ascending', 0, 0, 0) == 1 - ascending
			assert api.message(reversed, c'key', 0, 0, 0) == key && api.message(reversed, c'selector', 0, 0, 0) == selector
			assert api.message(reversed, c'comparator', 0, 0, 0) == 0
			api.release(descriptor)
			assert api.text(api.message(reversed, c'key', 0, 0, 0)) == 'fixture.value'
			factory := if explicit_selector { api.message(api.cls, c'sortDescriptorWithKey:ascending:selector:', api.string(c'fixture.value'), ascending, selector) } else { api.message(api.cls, c'sortDescriptorWithKey:ascending:', api.string(c'fixture.value'), ascending, 0) }
			assert api.message(factory, c'ascending', 0, 0, 0) == ascending && api.message(factory, c'selector', 0, 0, 0) == selector
			assert api.text(api.message(factory, c'key', 0, 0, 0)) == 'fixture.value'
		}
	}
	for key in [u64(0), api.string(c'')]! {
		descriptor := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithKey:ascending:selector:', key, 1, 0)
		assert api.message(descriptor, c'key', 0, 0, 0) == 0 && api.message(descriptor, c'selector', 0, 0, 0) == api.selector(c'compare:')
		api.release(descriptor)
	}
	convenience := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithKey:', api.string(c'fixture.value'), 0, 0)
	assert api.message(convenience, c'ascending', 0, 0, 0) == 1 && api.message(convenience, c'selector', 0, 0, 0) == api.selector(c'compare:')
	api.release(convenience); api.drain(pool)
}

struct SortBlockState { mut: copies i64 disposals i64 calls i64 reenter bool }
struct SortBlockDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct SortBlockLiteral { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
type SortBlockCopy = fn (u64) u64
type SortBlockRelease = fn (u64)
type SortBlockInvoke = fn (u64, u64, u64) i64
fn sort_block_reentry() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }
fn sort_block_copy(destination u64, source u64) {
	state := unsafe { &SortBlockState(read64(source + 32)) }; C.ios_ref_change(unsafe { &state.copies }, 1)
	assert read64(destination + 32) == u64(state)
	if state.reenter { worker := spawn sort_block_reentry(); worker.wait() }
}
fn sort_block_dispose(block u64) {
	state := unsafe { &SortBlockState(read64(block + 32)) }; C.ios_ref_change(unsafe { &state.disposals }, 1)
	if state.reenter { worker := spawn sort_block_reentry(); worker.wait() }
}
fn sort_block_invoke(block u64, left u64, right u64) i64 {
	state := unsafe { &SortBlockState(read64(block + 32)) }; C.ios_ref_change(unsafe { &state.calls }, 1)
	if state.reenter { worker := spawn sort_callback_reader(); worker.wait() }
	return i64(read64(left + 8)) * 100 + i64(read64(right + 8))
}
fn (api SortApi) copy_block(block u64) u64 {
	$if macos { if api.native { return unsafe { SortBlockCopy(C.dlsym(voidptr(-2), c'_Block_copy'))(block) } } }
	return block_copy(block)
}
fn (api SortApi) release_block(block u64) {
	$if macos { if api.native { unsafe { SortBlockRelease(C.dlsym(voidptr(-2), c'_Block_release'))(block) }; return } }
	block_release(block)
}

fn sort_comparison_cases(api SortApi, cls u64) {
	pool := api.pool(); sort_callback_api = api
	left := api.message(cls, c'new', 0, 0, 0); right := api.message(cls, c'new', 0, 0, 0)
	wrapper_left := api.message(cls, c'new', 0, 0, 0); wrapper_right := api.message(cls, c'new', 0, 0, 0)
	unsafe { *(&u64(left + 8)) = 2; *(&u64(right + 8)) = 7; *(&u64(wrapper_left + 16)) = left; *(&u64(wrapper_right + 16)) = right }
	for ascending in [u64(0), 1]! {
		for keyed in [false, true]! {
			key := if keyed { api.string(c'fixture.value') } else { u64(0) }
			descriptor := api.message(api.cls, c'sortDescriptorWithKey:ascending:selector:', key, ascending, api.selector(c'fixtureCompare:'))
			first := if keyed { wrapper_left } else { left }; second := if keyed { wrapper_right } else { right }
			sign := if ascending == 1 { i64(1) } else { i64(-1) }
			sort_callback_descriptor = descriptor; sort_callback_reenter = ascending == 1; sort_callback_calls = 0; sort_key_callback_calls = 0
			assert i64(api.message(descriptor, c'compareObject:toObject:', first, second, 0)) == sign * 207
			assert i64(api.message(descriptor, c'compareObject:toObject:', second, first, 0)) == sign * 702
			assert sort_callback_calls == 2
			assert sort_key_callback_calls == if keyed { 4 } else { 0 }
			assert api.message(descriptor, c'compareObject:toObject:', first, first, 0) == 0 && sort_callback_calls == 2
			assert sort_key_callback_calls == if keyed { 6 } else { 0 }
			assert api.message(descriptor, c'compareObject:toObject:', 0, 0, 0) == 0
			assert i64(api.message(descriptor, c'compareObject:toObject:', 0, second, 0)) == -sign
			assert i64(api.message(descriptor, c'compareObject:toObject:', first, 0, 0)) == sign
			assert sort_callback_calls == 2
			assert sort_key_callback_calls == if keyed { 8 } else { 0 }
			sort_callback_reenter = false
			reversed := api.message(descriptor, c'reversedSortDescriptor', 0, 0, 0)
			assert i64(api.message(reversed, c'compareObject:toObject:', first, second, 0)) == -sign * 207
		}
	}
	default := api.message(api.cls, c'new', 0, 0, 0); default_reverse := api.message(default, c'reversedSortDescriptor', 0, 0, 0)
	assert i64(api.message(default_reverse, c'compareObject:toObject:', left, right, 0)) == 207; api.release(default)
	// A dictionary key path uses the same NSDate comparison selector as an
	// application-supplied valueForKeyPath: method, including missing values.
	date_left := api.date(100.25); date_right := api.date(200.75)
	inner_left := api.message(api.dictionaries, c'dictionary', 0, 0, 0); inner_right := api.message(api.dictionaries, c'dictionary', 0, 0, 0)
	outer_left := api.message(api.dictionaries, c'dictionary', 0, 0, 0); outer_right := api.message(api.dictionaries, c'dictionary', 0, 0, 0)
	api.message(inner_left, c'setObject:forKey:', date_left, api.string(c'value'), 0); api.message(inner_right, c'setObject:forKey:', date_right, api.string(c'value'), 0)
	api.message(outer_left, c'setObject:forKey:', inner_left, api.string(c'fixture'), 0); api.message(outer_right, c'setObject:forKey:', inner_right, api.string(c'fixture'), 0)
	keyed := api.message(api.cls, c'sortDescriptorWithKey:ascending:', api.string(c'fixture.value'), 1, 0)
	assert i64(api.message(keyed, c'compareObject:toObject:', outer_left, outer_right, 0)) == -1
	missing := api.message(api.dictionaries, c'dictionary', 0, 0, 0)
	assert i64(api.message(keyed, c'compareObject:toObject:', missing, outer_right, 0)) == -1
	self_key := api.message(api.cls, c'sortDescriptorWithKey:ascending:', api.string(c'self'), 1, 0)
	assert i64(api.message(self_key, c'compareObject:toObject:', date_left, date_right, 0)) == -1
	api.message(outer_left, c'setObject:forKey:', date_left, api.string(c'self'), 0); api.message(outer_right, c'setObject:forKey:', date_right, api.string(c'self'), 0)
	assert i64(api.message(self_key, c'compareObject:toObject:', outer_left, outer_right, 0)) == -1
	for object in [left, right, wrapper_left, wrapper_right]! { api.release(object) }
	sort_callback_descriptor = 0; sort_callback_api = SortApi{}; api.drain(pool)
}

fn sort_comparator_cases(api SortApi, cls u64) {
	mut isa := u64(0)
	$if macos { if api.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	if !api.native { isa = block_isa(0) }
	assert isa != 0
	block_descriptor := SortBlockDescriptor{0, sizeof(SortBlockLiteral), u64(unsafe { voidptr(sort_block_copy) }), u64(unsafe { voidptr(sort_block_dispose) })}
	for factory in [false, true]! {
		for ascending in [u64(0), 1]! {
			pool := api.pool(); sort_callback_api = api
			left := api.message(cls, c'new', 0, 0, 0); right := api.message(cls, c'new', 0, 0, 0)
			unsafe { *(&u64(left + 8)) = 2; *(&u64(right + 8)) = 7 }
			reader := api.retain(api.message(api.cls, c'sortDescriptorWithKey:ascending:', 0, 1, 0)); sort_callback_descriptor = reader
			mut state := unsafe { &SortBlockState(C.calloc(1, sizeof(SortBlockState))) }; assert state != unsafe { nil }; state.reenter = true
			literal := SortBlockLiteral{isa, u32(1) << 25, 0, u64(unsafe { voidptr(sort_block_invoke) }), u64(unsafe { &block_descriptor }), u64(state)}
			original := u64(unsafe { &literal })
			descriptor := if factory { api.retain(api.message(api.cls, c'sortDescriptorWithKey:ascending:comparator:', 0, ascending, original)) } else { api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithKey:ascending:comparator:', 0, ascending, original) }
			assert state.copies == 1 && state.disposals == 0
			stored := api.message(descriptor, c'comparator', 0, 0, 0)
			assert stored != 0 && stored != original && read64(descriptor + 32) == stored
			assert api.message(descriptor, c'selector', 0, 0, 0) == 0 && read64(descriptor + 24) == 0
			assert api.message(descriptor, c'ascending', 0, 0, 0) == ascending
			getter_copy := api.copy_block(stored)
			assert getter_copy == stored && state.copies == 1
			sign := if ascending == 1 { i64(1) } else { i64(-1) }
			assert i64(api.message(descriptor, c'compareObject:toObject:', left, right, 0)) == sign * 207
			assert i64(api.message(descriptor, c'compareObject:toObject:', right, left, 0)) == sign * 702
			assert state.calls == 2
			assert api.message(descriptor, c'compareObject:toObject:', left, left, 0) == 0 && api.message(descriptor, c'compareObject:toObject:', 0, 0, 0) == 0
			assert i64(api.message(descriptor, c'compareObject:toObject:', 0, right, 0)) == -sign && i64(api.message(descriptor, c'compareObject:toObject:', left, 0, 0)) == sign
			assert state.calls == 2
			reversed := api.retain(api.message(descriptor, c'reversedSortDescriptor', 0, 0, 0))
			assert api.message(reversed, c'comparator', 0, 0, 0) == stored && api.message(reversed, c'selector', 0, 0, 0) == 0
			assert i64(api.message(reversed, c'compareObject:toObject:', left, right, 0)) == -sign * 207
			api.release(descriptor); api.drain(pool)
			assert state.disposals == 0 && unsafe { SortBlockInvoke(voidptr(read64(getter_copy + 16)))(getter_copy, left, right) } == 207
			api.release(reversed); assert state.disposals == 0
			api.release_block(getter_copy); assert state.disposals == 1
			api.release(left); api.release(right); api.release(reader); C.free(state)
			sort_callback_descriptor = 0; sort_callback_api = SortApi{}
		}
	}
}

fn sort_reversal_lifetime_case(api SortApi, cls u64) {
	pool := api.pool(); sort_callback_api = api; sort_callback_reenter = false
	key_class := objc_allocate_class(api.strings, c'VinixSortReversalString', 0)
	assert key_class != 0 && objc_add_method(key_class, u64(c'copy'), u64(unsafe { voidptr(sort_reversal_string_copy) }), c'@16@0:8')
	objc_register_class(key_class)
	key := owned_string('fixture.value'); objc_set_class(key, key_class)
	mut state := unsafe { &SortBlockState(C.calloc(1, sizeof(SortBlockState))) }; assert state != unsafe { nil }
	block_descriptor := SortBlockDescriptor{0, sizeof(SortBlockLiteral), u64(unsafe { voidptr(sort_block_copy) }), u64(unsafe { voidptr(sort_block_dispose) })}
	literal := SortBlockLiteral{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(sort_block_invoke) }), u64(unsafe { &block_descriptor }), u64(state)}
	sort_reversal_key_copies = 0
	sort_reversal_source = api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithKey:ascending:comparator:', key, 1, u64(unsafe { &literal }))
	api.release(key)
	stored := api.message(sort_reversal_source, c'comparator', 0, 0, 0)
	mut source_weak := u64(0); mut key_weak := u64(0)
	objc_store_weak(unsafe { &source_weak }, sort_reversal_source); objc_store_weak(unsafe { &key_weak }, key)
	// The second key copy drops the source's last external reference before
	// reversal has acquired its comparator block. The method must pin itself.
	reversed := api.message(sort_reversal_source, c'reversedSortDescriptor', 0, 0, 0)
	assert sort_reversal_key_copies == 2 && sort_reversal_source == 0 && source_weak == 0
	assert state.copies == 1 && state.disposals == 0 && api.message(reversed, c'comparator', 0, 0, 0) == stored
	left := api.message(cls, c'new', 0, 0, 0); right := api.message(cls, c'new', 0, 0, 0)
	unsafe { *(&u64(left + 8)) = 2; *(&u64(right + 8)) = 7; *(&u64(left + 16)) = left; *(&u64(right + 16)) = right }
	assert i64(api.message(reversed, c'compareObject:toObject:', left, right, 0)) == -207 && state.calls == 1
	api.release(left); api.release(right); api.drain(pool)
	assert key_weak == 0 && state.disposals == 1
	objc_destroy_weak(unsafe { &source_weak }); objc_destroy_weak(unsafe { &key_weak }); C.free(state)
	sort_callback_api = SortApi{}
}

fn sort_descriptor_reader(api SortApi, descriptor u64, left u64, right u64) {
	pool := api.pool()
	for _ in 0 .. 128 {
		assert api.message(descriptor, c'ascending', 0, 0, 0) == 1 && api.message(descriptor, c'comparator', 0, 0, 0) == 0
		assert i64(api.message(descriptor, c'compareObject:toObject:', left, right, 0)) == 207
	}
	api.drain(pool)
}

fn test_sort_descriptor_native() {
	$if macos {
		api := SortApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSSortDescriptor')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString')), dates: u64(C.objc_getClass(c'NSDate')), dictionaries: u64(C.objc_getClass(c'NSMutableDictionary'))}
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls) }) == 40 && C.class_getSuperclass(unsafe { voidptr(api.cls) }) == C.objc_getClass(c'NSObject')
		cls := sort_custom_class(api)
		sort_construction_cases(api); sort_comparison_cases(api, cls); sort_comparator_cases(api, cls)
		println('IOS-SORT-DESCRIPTOR-NATIVE: typed constructors, copied mutable keys, selector/comparator properties, retained-self copies, reversed ownership, signed asymmetric comparisons, nil/identity ordering, application and dictionary key paths, stack block promotion and final disposal')
	}
}

fn test_sort_descriptor_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := sort_runtime_api(); cls := sort_custom_class(api)
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSSortDescriptor')! == api.cls && runtime_symbol(library, '_OBJC_METACLASS_$_NSSortDescriptor')! == read64(api.cls)
		assert objc_class_size(api.cls) == 40 && objc_class_parent(api.cls) == ios_runtime.names['NSObject']
		for name, types in {'init': '@16@0:8', 'initWithKey:': '@24@0:8@16', 'initWithKey:ascending:': '@28@0:8@16B24', 'initWithKey:ascending:selector:': '@36@0:8@16B24:28', 'initWithKey:ascending:comparator:': '@36@0:8@16B24@?28', 'ascending': 'B16@0:8', 'key': '@16@0:8', 'selector': ':16@0:8', 'comparator': '@?16@0:8', 'compareObject:toObject:': 'q32@0:8@16@24', 'reversedSortDescriptor': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
			method := objc_instance_method(api.cls, u64(name.str)); assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		for name, types in {'sortDescriptorWithKey:ascending:': '@28@0:8@16B24', 'sortDescriptorWithKey:ascending:selector:': '@36@0:8@16B24:28', 'sortDescriptorWithKey:ascending:comparator:': '@36@0:8@16B24@?28'} {
			method := objc_class_method(api.cls, u64(name.str)); assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		for i, name in ['_sortDescriptorFlags', '_key', '_selector', '_selectorOrBlock']! {
			ivar := objc_find_ivar(api.cls, unsafe { &char(name.str) }); assert ivar != 0 && objc_ivar_offset(ivar) == i64(8 + i * 8)
			assert ctext(u64(objc_ivar_types(ivar))) == ['Q', '@"NSString"', ':', '@']![i]
		}
		sort_construction_cases(api); sort_comparison_cases(api, cls); sort_comparator_cases(api, cls)
		sort_reversal_lifetime_case(api, cls)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		pool := api.pool(); descriptor := api.message(api.cls, c'sortDescriptorWithKey:ascending:', 0, 1, 0)
		for selector in [c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'allowEvaluation', c'reverseNullOrder', c'setReverseNullOrder:', c'description', c'isEqual:']! { assert !objc_responds(descriptor, selector) && objc_instance_method(api.cls, u64(selector)) == 0 }
		left := api.message(cls, c'new', 0, 0, 0); right := api.message(cls, c'new', 0, 0, 0)
		unsafe { *(&u64(left + 8)) = 2; *(&u64(right + 8)) = 7 }
		mut readers := []thread{}; sort_callback_reenter = false
		for _ in 0 .. 8 { readers << spawn sort_descriptor_reader(api, descriptor, left, right) }
		readers.wait(); unsafe { readers.free() }; api.release(left); api.release(right); api.drain(pool)
		assert ios_runtime.live == 0
		mut guarded := [7]u64{}; guarded[0] = 0x1122334455667788; guarded[6] = 0x8877665544332211
		caller := objc_construct_instance(api.cls, u64(unsafe { &guarded[1] })); inner := api.pool()
		source := api.mutable_string(c'caller storage'); assert api.message(caller, c'initWithKey:ascending:', source, 1, 0) == caller; api.release(source)
		mut key_weak := u64(0); objc_store_weak(unsafe { &key_weak }, api.message(caller, c'key', 0, 0, 0)); api.drain(inner)
		assert key_weak != 0 && objc_destruct_instance(caller) == caller && key_weak == 0
		for i in 1 .. 5 { assert read64(caller + u64(i * 8)) == 0 }; objc_destroy_weak(unsafe { &key_weak })
		assert guarded[0] == 0x1122334455667788 && guarded[6] == 0x8877665544332211
		for _ in 0 .. 64 {
			inner2 := api.pool(); changed := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithKey:ascending:', api.string(c'isa changed'), 1, 0)
			assert objc_set_class(changed, ios_runtime.names['NSObject']) == api.cls; api.release(changed); api.drain(inner2)
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		pooled := objc_autorelease(api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithKey:ascending:', api.string(c'shutdown key'), 1, 0))
		mut pooled_weak := u64(0); mut final_key_weak := u64(0)
		objc_store_weak(unsafe { &pooled_weak }, pooled); objc_store_weak(unsafe { &final_key_weak }, api.message(pooled, c'key', 0, 0, 0)); objc_stop()
		assert pooled_weak == 0 && final_key_weak == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-SORT-DESCRIPTOR: typed selector/block ABI, native metadata, copied keys, reversed lifetimes through source-releasing key copies, reentrant comparison and block callbacks, eight concurrent readers, guarded caller storage, 64 isa replacements and two drained runtimes')
}

fn test_sort_descriptor_rejections() {
	objc_start(); api := sort_runtime_api()
	for mode in ['mutable', 'coding', 'description', 'equality', 'null-order', 'bad-key', 'bad-copy', 'nil-copy', 'nil-comparator', 'bad-comparator', 'reinitialize', 'uninitialized', 'key-path', 'aggregate', 'malformed', 'subclass', 'caller-subclass', 'spoof']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := api.message(api.cls, c'new', 0, 0, 0)
			match mode {
				'mutable' { api.message(object, c'mutableCopy', 0, 0, 0) }
				'coding' { api.message(object, c'initWithCoder:', 0, 0, 0) }
				'description' { api.message(object, c'description', 0, 0, 0) }
				'equality' { api.message(object, c'isEqual:', object, 0, 0) }
				'null-order' { api.message(object, c'setReverseNullOrder:', 1, 0, 0) }
				'bad-key' { api.message(object, c'initWithKey:ascending:', objc_new(ios_runtime.names['NSObject']), 1, 0) }
				'bad-copy', 'nil-copy' {
					bad := objc_allocate_class(ios_runtime.names['NSString'], c'VinixSortBadCopyString', 0)
					imp := if mode == 'bad-copy' { u64(unsafe { voidptr(sort_probe_bad_copy) }) } else { u64(unsafe { voidptr(sort_probe_nil_copy) }) }
					assert objc_add_method(bad, u64(c'copy'), imp, c'@16@0:8'); objc_register_class(bad)
					api.message(object, c'initWithKey:ascending:', objc_new(bad), 1, 0)
				}
				'nil-comparator', 'bad-comparator' {
					comparator := if mode == 'bad-comparator' { objc_new(ios_runtime.names['NSObject']) } else { u64(0) }
					api.message(object, c'initWithKey:ascending:comparator:', 0, 1, comparator)
				}
				'reinitialize' { api.message(object, c'initWithKey:ascending:', 0, 1, 0); api.message(object, c'initWithKey:ascending:', 0, 0, 0) }
				'uninitialized' { api.message(object, c'compareObject:toObject:', 0, 0, 0) }
				'key-path', 'aggregate', 'malformed' {
					key := match mode { 'aggregate' { c'@count' } 'malformed' { c'.value' } else { c'unsupported' } }
					api.message(object, c'initWithKey:ascending:', api.string(key), 1, 0)
					value := if mode == 'key-path' { objc_new(ios_runtime.names['NSObject']) } else { api.message(api.dictionaries, c'dictionary', 0, 0, 0) }
					api.message(object, c'compareObject:toObject:', value, 0, 0)
				}
				'subclass', 'caller-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixUnsupportedSortSubclass', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { mut storage := [5]u64{}; objc_construct_instance(sub, u64(unsafe { &storage[0] })) }
				}
				else {
					spoof_class := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSortSpoof', 0)
					assert objc_add_ivar(spoof_class, c'bytes', 32, 3, c'[32C]'); objc_register_class(spoof_class)
					spoof := objc_new(spoof_class); objc_set_class(spoof, api.cls); api.message(spoof, c'key', 0, 0, 0)
				}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'bad-key' { 'sort descriptor key must be a string' }
			'bad-copy' { 'sort descriptor key copy must be a string' }
			'nil-copy' { 'sort descriptor key copy must not be nil' }
			'nil-comparator', 'bad-comparator' { 'sort descriptor comparator must be a block' }
			'reinitialize' { 'sort descriptor designated reinitialization is not implemented' }
			'uninitialized' { 'sort descriptor comparison requires designated initialization' }
			'key-path', 'aggregate' { 'sort descriptor key paths require dictionaries or application valueForKeyPath:' }
			'malformed' { 'sort descriptor key path is outside the supported profile' }
			'subclass', 'caller-subclass' { 'custom sort descriptor subclass construction is not implemented' }
			'spoof' { 'sort descriptor requires live owned storage' }
			else { 'sort descriptor coding, mutable copying, equality, description and reverse-null ordering are not implemented' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-SORT-DESCRIPTOR-REJECT: eighteen coding/mutability/equality/description/null-order/type/copy/comparator/reinitialization/uninitialized/KVC/subclass/spoof cases fail explicitly')
}
