// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <objc/message.h>
	#define predicate_fixture_native_format ((unsigned long long (*)(unsigned long long,unsigned long long,unsigned long long,...))objc_msgSend)
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr
fn C.predicate_fixture_native_format(u64, u64, u64, ...) u64

type PredicateFixtureSend = fn (u64, u64, u64, u64, u64) u64
struct PredicateFixtureApi { native bool send u64 }
__global predicate_fixture_api = PredicateFixtureApi{}
fn (api PredicateFixtureApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api PredicateFixtureApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api PredicateFixtureApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { PredicateFixtureSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api PredicateFixtureApi) string(value string) u64 { return api.message(api.cls('NSString'), c'stringWithUTF8String:', u64(value.str), 0, 0) }
fn (api PredicateFixtureApi) text(value u64) string {
	pointer := api.message(value, c'UTF8String', 0, 0, 0); assert pointer != 0
	return unsafe { (&char(voidptr(pointer))).vstring() }
}
fn (api PredicateFixtureApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api PredicateFixtureApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api PredicateFixtureApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api PredicateFixtureApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api PredicateFixtureApi) array(values &u64, count int, mutable bool) u64 {
	return api.message(api.cls(if mutable { 'NSMutableArray' } else { 'NSArray' }), c'arrayWithObjects:count:', u64(values), u64(count), 0)
}
fn (api PredicateFixtureApi) evaluate(predicate u64, object u64) bool { return api.message(predicate, c'evaluateWithObject:', object, 0, 0) != 0 }
fn (api PredicateFixtureApi) format(pattern string, value u64) u64 {
	text := api.string(pattern)
	$if macos { if api.native { return C.predicate_fixture_native_format(api.cls('NSPredicate'), api.selector(c'predicateWithFormat:'), text, value) } }
	// Darwin's variadic object starts at the original stack pointer. x3 is a
	// deliberate decoy, matching neither the input nor the nil test operands.
	mut argument := value; mut frame := RegisterFrame{}
	frame.x[0] = api.cls('NSPredicate'); frame.x[1] = u64(c'predicateWithFormat:'); frame.x[2] = text; frame.x[3] = api.cls('NSObject')
	frame.stack = u64(unsafe { &argument }); assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}
fn predicate_fixture_metadata(api PredicateFixtureApi) {
	cls := api.cls('NSPredicate'); assert cls != 0
	$if macos { if api.native { assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 16; assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject') } }
	if !api.native { assert objc_class_size(cls) == 16 && objc_class_parent(cls) == api.cls('NSObject') }
	names := ['predicateWithValue:', 'predicateWithBlock:', 'predicateWithFormat:',
		'predicateWithFormat:argumentArray:', 'predicateWithFormat:arguments:',
		'evaluateWithObject:', 'evaluateWithObject:substitutionVariables:', 'copyWithZone:']!
	encodings := ['@20@0:8B16', '@24@0:8@?16', '@24@0:8@16', '@32@0:8@16@24',
		'@32@0:8@16*24', 'B24@0:8@16', 'B32@0:8@16@24', '@24@0:8^{_NSZone=}16']!
	for i, name in names {
		types := encodings[i]
		meta := name.starts_with('predicateWith'); mut actual := ''
		$if macos { if api.native {
			method := if meta { C.class_getClassMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.selector(name.str)) }) } else { C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.selector(name.str)) }) }
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native { method := if meta { objc_class_method(cls, u64(name.str)) } else { objc_instance_method(cls, u64(name.str)) }; assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn predicate_fixture_shared_values(api PredicateFixtureApi) {
	pool := api.pool(); predicate_fixture_metadata(api); cls := api.cls('NSPredicate')
	assert api.message(cls, c'predicateWithFormat:', 0, 0, 0) == 0
	for truth in [false, true]! {
		predicate := api.message(cls, c'predicateWithValue:', u64(truth), 0, 0)
		assert predicate != 0 && api.evaluate(predicate, 0) == truth && api.evaluate(predicate, api.string('any')) == truth
		assert api.message(cls, c'predicateWithValue:', u64(truth), 0, 0) == predicate
		assert api.format(if truth { 'TRUEPREDICATE' } else { 'FALSEPREDICATE' }, 0) == predicate
		copy := api.message(predicate, c'copy', 0, 0, 0); assert copy == predicate; api.message(copy, c'release', 0, 0, 0)
		empty := api.array(unsafe { nil }, 0, false)
		assert api.message(cls, c'predicateWithFormat:argumentArray:', api.string(if truth { 'TRUEPREDICATE' } else { 'FALSEPREDICATE' }), empty, 0) == predicate
	}
	for value in [api.string('UIInterfaceOrientationPortrait'), api.string('UIInterfaceOrientationLandscapeLeft')]! {
		predicate := api.format('SELF == %@', value)
		assert api.evaluate(predicate, value) && !api.evaluate(predicate, api.string('other')) && !api.evaluate(predicate, 0)
		mut arguments := [value]!
		from_array := api.message(cls, c'predicateWithFormat:argumentArray:', api.string('SELF == %@'), api.array(unsafe { &arguments[0] }, 1, false), 0)
		assert api.evaluate(from_array, value) && !api.evaluate(from_array, api.string('other'))
		copy := api.message(predicate, c'copyWithZone:', 0, 0, 0); assert copy != predicate && api.evaluate(copy, value); api.message(copy, c'release', 0, 0, 0)
	}
	nil_predicate := api.format('SELF == %@', 0)
	assert api.evaluate(nil_predicate, 0) && api.evaluate(nil_predicate, api.message(api.cls('NSNull'), c'null', 0, 0, 0)) && !api.evaluate(nil_predicate, api.string(''))
	raw := api.message(cls, c'alloc', 0, 0, 0); assert raw != 0 && api.message(raw, c'init', 0, 0, 0) == raw; api.message(raw, c'release', 0, 0, 0)
	api.drain(pool)
}
fn predicate_fixture_shared_operand(api PredicateFixtureApi) {
	pool := api.pool(); mut weak := u64(0)
	value := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0, 0), c'initWithUTF8String:', u64(c'first'), 0, 0)
	api.weak(unsafe { &weak }, value)
	predicate := api.message(api.format('SELF == %@', value), c'retain', 0, 0, 0)
	assert api.evaluate(predicate, api.string('first'))
	api.message(value, c'appendString:', api.string('-changed'), 0, 0)
	assert !api.evaluate(predicate, api.string('first')) && api.evaluate(predicate, api.string('first-changed'))
	copy := api.message(predicate, c'copy', 0, 0, 0); assert copy != predicate
	api.message(value, c'release', 0, 0, 0); api.drain(pool); assert weak != 0
	fresh := api.pool(); api.message(predicate, c'release', 0, 0, 0); assert weak != 0
	assert api.evaluate(copy, api.string('first-changed')); api.message(copy, c'release', 0, 0, 0); api.drain(fresh)
	assert weak == 0; api.destroy_weak(unsafe { &weak })
}
type PredicateFixtureAction = fn (u64, u64, u64)
struct PredicateFixtureBlockState { mut: copies int disposals int calls int last_object u64 last_variables u64 accept u64 captured u64 reenter bool callback u64 result u8 }
struct PredicateFixtureBlockDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct PredicateFixtureBlock { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
fn predicate_fixture_word(address u64) u64 { return unsafe { *(&u64(voidptr(address))) } }
fn predicate_fixture_lock_worker() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }
fn predicate_fixture_block_copy(destination u64, source u64) {
	mut state := unsafe { &PredicateFixtureBlockState(voidptr(predicate_fixture_word(source + 32))) }
	state.copies++; assert predicate_fixture_word(destination + 32) == u64(state)
	predicate_fixture_api.message(state.captured, c'retain', 0, 0, 0)
	if state.reenter { worker := spawn predicate_fixture_lock_worker(); worker.wait() }
}
fn predicate_fixture_block_dispose(block u64) {
	mut state := unsafe { &PredicateFixtureBlockState(voidptr(predicate_fixture_word(block + 32))) }
	state.disposals++; predicate_fixture_api.message(state.captured, c'release', 0, 0, 0)
	if state.reenter { worker := spawn predicate_fixture_lock_worker(); worker.wait() }
}
fn predicate_fixture_block_invoke(block u64, object u64, variables u64) u8 {
	mut state := unsafe { &PredicateFixtureBlockState(voidptr(predicate_fixture_word(block + 32))) }
	state.calls++; state.last_object = object; state.last_variables = variables
	if state.reenter { worker := spawn predicate_fixture_lock_worker(); worker.wait() }
	if state.callback != 0 { unsafe { PredicateFixtureAction(voidptr(state.callback))(u64(state), object, variables) } }
	return if state.result != 0 { state.result } else { u8(object == state.accept) }
}
fn (api PredicateFixtureApi) block_isa() u64 {
	$if macos { if api.native { return u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	return block_isa(0)
}
fn predicate_fixture_shared_blocks(api PredicateFixtureApi) {
	predicate_fixture_api = api; pool := api.pool(); mut weak := u64(0)
	capture := api.message(api.cls('NSObject'), c'new', 0, 0, 0); api.weak(unsafe { &weak }, capture)
	mut state := unsafe { &PredicateFixtureBlockState(C.calloc(1, sizeof(PredicateFixtureBlockState))) }; assert state != unsafe { nil }
	state.accept = capture; state.captured = capture; state.reenter = !api.native
	descriptor := PredicateFixtureBlockDescriptor{0, sizeof(PredicateFixtureBlock), u64(unsafe { voidptr(predicate_fixture_block_copy) }), u64(unsafe { voidptr(predicate_fixture_block_dispose) })}
	literal := PredicateFixtureBlock{api.block_isa(), u32(1) << 25, 0, u64(unsafe { voidptr(predicate_fixture_block_invoke) }), u64(unsafe { &descriptor }), u64(state)}
	predicate := api.message(api.message(api.cls('NSPredicate'), c'predicateWithBlock:', u64(unsafe { &literal }), 0, 0), c'retain', 0, 0, 0)
	assert predicate != 0 && state.copies == 1 && state.disposals == 0
	assert api.evaluate(predicate, capture) && state.calls == 1 && state.last_object == capture && state.last_variables == 0
	assert !api.evaluate(predicate, 0) && state.calls == 2 && state.last_object == 0 && state.last_variables == 0
	variables := api.message(api.cls('NSDictionary'), c'dictionary', 0, 0, 0)
	assert api.message(predicate, c'evaluateWithObject:substitutionVariables:', capture, variables, 0) != 0 && state.last_variables == variables
	assert api.message(predicate, c'evaluateWithObject:substitutionVariables:', capture, 0, 0) != 0 && state.last_variables == 0
	for result in [u8(2), 255]! { state.result = result; assert api.message(predicate, c'evaluateWithObject:', capture, 0, 0) == result }; state.result = 0
	copy := api.message(predicate, c'copy', 0, 0, 0); assert copy != predicate && state.copies == 1
	api.message(capture, c'release', 0, 0, 0); api.drain(pool); assert weak == capture
	fresh := api.pool(); api.message(predicate, c'release', 0, 0, 0)
	assert state.disposals == 0 && api.evaluate(copy, capture)
	api.message(copy, c'release', 0, 0, 0); api.drain(fresh)
	assert state.disposals == 1 && weak == 0; api.destroy_weak(unsafe { &weak }); C.free(state)
}
fn predicate_fixture_shared_arrays(api PredicateFixtureApi) {
	pool := api.pool(); a := api.string('UIInterfaceOrientationPortrait'); b := api.string('other')
	mut values := [a, b, a, b, a]!
	for mutable in [false, true]! {
		source := api.array(unsafe { &values[0] }, values.len, mutable)
		for truth in [false, true]! {
			predicate := api.message(api.cls('NSPredicate'), c'predicateWithValue:', u64(truth), 0, 0)
			filtered := api.message(source, c'filteredArrayUsingPredicate:', predicate, 0, 0)
			assert api.message(filtered, c'count', 0, 0, 0) == if truth { u64(5) } else { u64(0) }
		}
		predicate := api.format('SELF == %@', a)
		filtered := api.message(source, c'filteredArrayUsingPredicate:', predicate, 0, 0)
		assert api.message(source, c'count', 0, 0, 0) == 5 && api.message(filtered, c'count', 0, 0, 0) == 3
		for i in 0 .. 3 { assert api.message(filtered, c'objectAtIndex:', u64(i), 0, 0) == a }
		if mutable { api.message(source, c'filterUsingPredicate:', predicate, 0, 0); assert api.message(source, c'count', 0, 0, 0) == 3; api.message(source, c'addObject:', b, 0, 0); assert api.message(source, c'count', 0, 0, 0) == 4 }
	}
	empty := api.array(unsafe { nil }, 0, true); predicate := api.message(api.cls('NSPredicate'), c'predicateWithValue:', 1, 0, 0)
	assert api.message(api.message(empty, c'filteredArrayUsingPredicate:', predicate, 0, 0), c'count', 0, 0, 0) == 0
	api.message(empty, c'filterUsingPredicate:', predicate, 0, 0); assert api.message(empty, c'count', 0, 0, 0) == 0
	api.drain(pool)
}
fn predicate_fixture_shared(api PredicateFixtureApi) {
	predicate_fixture_shared_values(api); predicate_fixture_shared_operand(api); predicate_fixture_shared_blocks(api); predicate_fixture_shared_arrays(api)
}

fn predicate_runtime_api() PredicateFixtureApi { return PredicateFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }

__global predicate_fixture_mode = ''
__global predicate_fixture_source = u64(0)
__global predicate_fixture_operand = u64(0)
__global predicate_fixture_variables = u64(0)
__global predicate_fixture_receiver = u64(0)
__global predicate_fixture_fired = false
__global predicate_fixture_weak = u64(0)
__global predicate_fixture_property_weak = u64(0)
__global predicate_fixture_equal_calls = 0
__global predicate_fixture_runtime_descriptor = PredicateFixtureBlockDescriptor{}

fn predicate_fixture_worker() {
	api := predicate_runtime_api(); pool := api.pool()
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if predicate_fixture_mode in ['release-eval', 'release-copy', 'release-filter']! {
		if predicate_fixture_source != 0 { objc_release(predicate_fixture_source) }
		if predicate_fixture_operand != 0 { objc_release(predicate_fixture_operand) }
		if predicate_fixture_variables != 0 { objc_release(predicate_fixture_variables) }
	}
	api.drain(pool)
}
fn predicate_fixture_action(state u64, object u64, variables u64) {
	if predicate_fixture_fired { return }
	predicate_fixture_fired = true
	api := predicate_runtime_api()
	if predicate_fixture_mode == 'destruct' { objc_destruct_instance(predicate_fixture_receiver); return }
	if predicate_fixture_mode == 'mutate' { api.message(predicate_fixture_source, c'addObject:', api.cls('NSObject'), 0, 0); return }
	worker := spawn predicate_fixture_worker(); worker.wait()
	assert predicate_fixture_weak != 0
	assert api.evaluate(api.message(api.cls('NSPredicate'), c'predicateWithValue:', 1, 0, 0), object)
}
fn predicate_fixture_equal(object u64, selector u64, other u64) u8 {
	predicate_fixture_equal_calls++
	worker := spawn predicate_fixture_lock_worker(); worker.wait()
	return u8(object == other)
}
fn predicate_fixture_constructor(object u64, selector u64) u64 {
	if predicate_fixture_mode == '' { return object }
	predicate_fixture_fired = true
	if predicate_fixture_mode == 'destruct-copy' { objc_destruct_instance(predicate_fixture_source); return object }
	worker := spawn predicate_fixture_worker(); worker.wait()
	if predicate_fixture_mode == 'fail' {
		objc_store_weak(unsafe { &predicate_fixture_weak }, object)
		property := objc_new(ios_runtime.names['NSObject']); obj_header(object).fields[1] = property
		objc_store_weak(unsafe { &predicate_fixture_property_weak }, property)
		return 0
	}
	if predicate_fixture_mode == 'constructor-storage' { obj_header(object).fields[0] = objc_new(ios_runtime.names['NSObject']) }
	return object
}
fn predicate_fixture_array_constructor(object u64, selector u64) u64 {
	if predicate_fixture_mode == 'result-storage' { array_append(mut obj_header(object), ios_runtime.names['NSObject']) }
	if predicate_fixture_mode == 'result-isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
	return if predicate_fixture_mode == 'result-fail' { u64(0) } else { object }
}
fn predicate_fixture_block(api PredicateFixtureApi, mut state PredicateFixtureBlockState) u64 {
	if predicate_fixture_runtime_descriptor.size == 0 { predicate_fixture_runtime_descriptor = PredicateFixtureBlockDescriptor{0, sizeof(PredicateFixtureBlock), u64(unsafe { voidptr(predicate_fixture_block_copy) }), u64(unsafe { voidptr(predicate_fixture_block_dispose) })} }
	literal := PredicateFixtureBlock{api.block_isa(), u32(1) << 25, 0, u64(unsafe { voidptr(predicate_fixture_block_invoke) }), u64(unsafe { &predicate_fixture_runtime_descriptor }), u64(unsafe { &state })}
	return api.message(api.cls('NSPredicate'), c'predicateWithBlock:', u64(unsafe { &literal }), 0, 0)
}
fn predicate_fixture_runtime_lifetimes(api PredicateFixtureApi) {
	pool := api.pool(); cls := api.cls('NSPredicate'); predicate_fixture_api = api
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSPredicate') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSPredicate') or { panic(err) } == read64(cls)
	for i, name in ['_predicateFlags', 'reserved']! { ivar := objc_find_ivar(cls, name.str); assert ivar != 0 && objc_ivar_offset(ivar) == u64(8 + 4 * i) }
	// va_list is a stack argument cursor, independent of x3's object value.
	value := api.string('UIInterfaceOrientationLandscapeRight'); mut argument := value
	via_list := api.message(cls, c'predicateWithFormat:arguments:', api.string('SELF == %@'), u64(unsafe { &argument }), 0)
	assert api.evaluate(via_list, value) && !api.evaluate(via_list, api.string('different'))
	custom := objc_allocate_class(api.cls('NSObject'), c'VinixPredicateEquality', 0)
	assert objc_add_method(custom, u64(c'isEqual:'), u64(unsafe { voidptr(predicate_fixture_equal) }), c'B24@0:8@16'); objc_register_class(custom)
	operand := objc_new(custom); equal := api.format('SELF == %@', operand)
	predicate_fixture_equal_calls = 0; assert api.evaluate(equal, operand) && predicate_fixture_equal_calls == 1
	objc_release(operand)
	// Evaluation pins the predicate, input and substitutions while a joined
	// worker drops their last caller references. The copied block remains live.
	mut state := PredicateFixtureBlockState{result: 255, reenter: true, callback: u64(unsafe { voidptr(predicate_fixture_action) })}
	input := objc_new(api.cls('NSObject')); variables := objc_new(api.cls('NSDictionary'))
	inner := api.pool(); predicate := objc_retain(predicate_fixture_block(api, mut state)); api.drain(inner)
	objc_store_weak(unsafe { &predicate_fixture_weak }, predicate)
	predicate_fixture_source = predicate; predicate_fixture_operand = input; predicate_fixture_variables = variables
	predicate_fixture_mode = 'release-eval'; predicate_fixture_fired = false
	assert api.message(predicate, c'evaluateWithObject:substitutionVariables:', input, variables, 0) == 255
	predicate_fixture_mode = ''; predicate_fixture_source = 0; predicate_fixture_operand = 0; predicate_fixture_variables = 0
	assert predicate_fixture_fired && predicate_fixture_weak == 0 && state.disposals == 1
	objc_destroy_weak(unsafe { &predicate_fixture_weak })
	// Filtering pins its receiver and uses owned snapshots across every callback.
	mut filter_state := PredicateFixtureBlockState{result: 2, reenter: true, callback: u64(unsafe { voidptr(predicate_fixture_action) })}
	inner_filter := api.pool(); filter := objc_retain(predicate_fixture_block(api, mut filter_state))
	mut members := [api.cls('NSObject'), api.cls('NSString'), api.cls('NSObject')]!
	source := objc_retain(api.array(unsafe { &members[0] }, 3, false)); api.drain(inner_filter)
	objc_store_weak(unsafe { &predicate_fixture_weak }, source)
	predicate_fixture_source = source; predicate_fixture_operand = filter; predicate_fixture_mode = 'release-filter'; predicate_fixture_fired = false
	filtered := api.message(source, c'filteredArrayUsingPredicate:', filter, 0, 0)
	predicate_fixture_mode = ''; predicate_fixture_source = 0; predicate_fixture_operand = 0
	assert predicate_fixture_fired && predicate_fixture_weak == 0 && filter_state.disposals == 1
	assert api.message(filtered, c'count', 0, 0, 0) == 3
	for i in 0 .. 3 { assert api.message(filtered, c'objectAtIndex:', u64(i), 0, 0) == members[i] }
	objc_destroy_weak(unsafe { &predicate_fixture_weak })
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(predicate_fixture_constructor) }), c'@16@0:8')
	// Copy owns its source and operand until a destination callback completes.
	inner_copy := api.pool(); original := objc_retain(api.format('SELF == %@', value)); api.drain(inner_copy)
	objc_store_weak(unsafe { &predicate_fixture_weak }, original)
	predicate_fixture_source = original; predicate_fixture_mode = 'release-copy'; predicate_fixture_fired = false
	copy := api.message(original, c'copy', 0, 0, 0); predicate_fixture_mode = ''; predicate_fixture_source = 0
	assert predicate_fixture_fired && predicate_fixture_weak == 0 && api.evaluate(copy, value); objc_release(copy)
	objc_destroy_weak(unsafe { &predicate_fixture_weak })
	valid := objc_retain(api.format('SELF == %@', value)); predicate_fixture_mode = 'fail'
	assert api.format('SELF == %@', value) == 0 && predicate_fixture_weak == 0 && predicate_fixture_property_weak == 0
	objc_destroy_weak(unsafe { &predicate_fixture_weak }); objc_destroy_weak(unsafe { &predicate_fixture_property_weak })
	assert api.message(valid, c'copy', 0, 0, 0) == 0 && predicate_fixture_weak == 0 && predicate_fixture_property_weak == 0
	objc_destroy_weak(unsafe { &predicate_fixture_weak }); objc_destroy_weak(unsafe { &predicate_fixture_property_weak })
	mut failed := [4]u64{}; failed[0] = 0x1122334455667788; failed[3] = 0x8877665544332211
	assert objc_construct_instance(cls, u64(unsafe { &failed[1] })) == 0 && predicate_fixture_weak == 0 && predicate_fixture_property_weak == 0
	objc_destroy_weak(unsafe { &predicate_fixture_weak }); objc_destroy_weak(unsafe { &predicate_fixture_property_weak })
	assert failed[0] == 0x1122334455667788 && failed[3] == 0x8877665544332211
	predicate_fixture_mode = ''; objc_release(valid)
	mut guarded := [4]u64{}; guarded[0] = 0x1122334455667788; guarded[3] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert api.message(caller, c'init', 0, 0, 0) == caller; objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[3] == 0x8877665544332211
	for _ in 0 .. 32 { object := objc_retain(api.format('SELF == %@', value)); objc_set_class(object, api.cls('NSObject')); objc_release(object) }
	assert objc_add_method(api.cls('NSArray'), u64(c'.cxx_construct'), u64(unsafe { voidptr(predicate_fixture_array_constructor) }), c'@16@0:8')
	result_source := api.array(unsafe { &members[0] }, 3, true)
	predicate_fixture_mode = 'result-fail'; assert api.message(result_source, c'filteredArrayUsingPredicate:', ios_runtime.predicates[0], 0, 0) == 0
	predicate_fixture_mode = ''; api.drain(pool)
}

fn predicate_fixture_image_array() u64 {
	page := u64(4096); pointer := C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANON, -1, 0)
	assert pointer != voidptr(-1); base := u64(pointer)
	unsafe { *(&u64(pointer)) = ios_runtime.names['NSConstantArray']; *(&u64(voidptr(base + 8))) = 3; *(&u64(voidptr(base + 16))) = base + 64
		*(&u64(voidptr(base + 64))) = ios_runtime.names['NSObject']; *(&u64(voidptr(base + 72))) = ios_runtime.names['NSString']; *(&u64(voidptr(base + 80))) = ios_runtime.names['NSObject'] }
	m := ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_arrayobj', address: 0x1000, size: 24}]}]}, layout: macho.Layout{base: 0x1000, size: page}, base: base}
	defer { unsafe { m.image.segments[0].sections.free(); m.image.segments.free() } }
	assert C.mprotect(pointer, usize(page), C.PROT_READ) == 0; m.constant_arrays() or { panic(err) }; return base
}
fn predicate_fixture_only_caches() {
	assert ios_runtime.weak.len == 0 && ios_runtime.objects.len == 3 && ios_runtime.live == 3
	for object, header in ios_runtime.objects { assert header.refs == 1 && (object in ios_runtime.predicates || object == ios_runtime.null_object) }
}
fn test_predicate_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := predicate_runtime_api(); predicate_fixture_shared(api); predicate_fixture_runtime_lifetimes(api); predicate_fixture_only_caches()
		pool := api.pool(); image := predicate_fixture_image_array(); mut before := [88]u8{}; C.memcpy(unsafe { &before[0] }, voidptr(image), before.len)
		result := api.message(image, c'filteredArrayUsingPredicate:', ios_runtime.predicates[0], 0, 0)
		assert api.message(result, c'count', 0, 0, 0) == 3 && api.message(result, c'objectAtIndex:', 1, 0, 0) == api.cls('NSString')
		assert C.memcmp(unsafe { &before[0] }, voidptr(image), before.len) == 0; api.drain(pool)
		// The image sidecar remains registered until runtime teardown.
		assert ios_runtime.objects.len == 4; objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert C.munmap(voidptr(image), 4096) == 0
	}
	println('IOS-PREDICATE: va_list and Darwin stack ABI, exact metadata, noncanonical block bool, custom equality, joined-worker evaluation/filter/copy pins, constructor rollback, guarded storage,32 isa cleanup paths, read-only image arrays and two drained runtimes')
}
fn test_predicate_rejections() {
	objc_start(); api := predicate_runtime_api(); predicate_fixture_api = api
	for selector in [c'predicateFormat', c'predicateWithSubstitutionVariables:', c'mutableCopy', c'encodeWithCoder:', c'initWithCoder:', c'allowEvaluation', c'description', c'isEqual:', c'hash']! { assert !objc_responds(api.cls('NSPredicate'), selector) }
	modes := ['pattern', 'arguments-missing', 'arguments-extra', 'argument-array-object', 'varargs-null', 'varargs-alignment', 'va-list-null', 'va-list-alignment', 'block-nil', 'block-object', 'abstract-evaluate', 'abstract-copy', 'coding', 'format-query', 'substitute', 'mutable-copy', 'hash', 'equal', 'description', 'allow', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'copy-provenance', 'nil-predicate', 'object-predicate', 'abstract-filter', 'immutable-inplace', 'image-inplace', 'raw-array', 'subclass-array', 'array-spoof', 'array-isa', 'array-limit', 'mutation-filter', 'mutation-inplace', 'destruct-eval', 'destruct-copy', 'result-storage', 'result-isa', 'constructor-storage', 'variables-object']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); cls := api.cls('NSPredicate'); value := api.string('value'); predicate := api.format('SELF == %@', value)
			mut members := [api.cls('NSObject'), api.cls('NSString')]!; source := api.array(unsafe { &members[0] }, 2, true)
			match mode {
				'pattern' { api.format('SELF != %@', value) }
				'arguments-missing', 'arguments-extra', 'argument-array-object' {
					arguments := if mode == 'argument-array-object' { value } else { api.array(unsafe { &members[0] }, if mode == 'arguments-missing' { 0 } else { 2 }, false) }
					api.message(cls, c'predicateWithFormat:argumentArray:', api.string('SELF == %@'), arguments, 0)
				}
				'varargs-null', 'varargs-alignment', 'va-list-null', 'va-list-alignment' {
					mut frame := RegisterFrame{}; frame.x[0] = cls; frame.x[1] = u64(if mode.starts_with('va-list') { c'predicateWithFormat:arguments:' } else { c'predicateWithFormat:' }); frame.x[2] = api.string('SELF == %@')
					frame.x[3] = if mode.ends_with('alignment') { u64(1) } else { u64(0) }; frame.stack = frame.x[3]; objc_dispatch(mut frame, 0)
				}
				'block-nil', 'block-object' { api.message(cls, c'predicateWithBlock:', if mode == 'block-nil' { u64(0) } else { value }, 0, 0) }
				'abstract-evaluate', 'abstract-copy' { raw := objc_new(cls); api.message(raw, if mode == 'abstract-copy' { c'copy' } else { c'evaluateWithObject:' }, value, 0, 0) }
				'coding', 'format-query', 'substitute', 'mutable-copy', 'hash', 'equal', 'description', 'allow' {
					selector := match mode { 'coding' { c'encodeWithCoder:' } 'format-query' { c'predicateFormat' } 'substitute' { c'predicateWithSubstitutionVariables:' } 'mutable-copy' { c'mutableCopy' } 'hash' { c'hash' } 'equal' { c'isEqual:' } 'description' { c'description' } else { c'allowEvaluation' } }
					api.message(predicate, selector, value, 0, 0)
				}
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'VinixUnsupportedPredicate', 0); objc_register_class(custom)
					if mode == 'subclass' { objc_allocate(custom) } else { mut bytes := [2]u64{}; objc_construct_instance(custom, u64(unsafe { &bytes[0] })) }
				}
				'spoof' { object := objc_new(api.cls('NSObject')); objc_set_class(object, cls); api.evaluate(object, value) }
				'isa-change' { objc_set_class(predicate, api.cls('NSObject')); api.message(predicate, c'copy', 0, 0, 0) }
				'copy-provenance' { objc_set_class(predicate, api.cls('NSURLRequest')); objc_copy_value(predicate, false) }
				'nil-predicate', 'object-predicate', 'abstract-filter' {
					object := if mode == 'nil-predicate' { u64(0) } else { objc_new(if mode == 'abstract-filter' { cls } else { api.cls('NSObject') }) }
					api.message(source, c'filteredArrayUsingPredicate:', object, 0, 0)
				}
				'immutable-inplace' { api.message(api.array(unsafe { &members[0] }, 2, false), c'filterUsingPredicate:', predicate, 0, 0) }
				'image-inplace' { api.message(predicate_fixture_image_array(), c'filterUsingPredicate:', predicate, 0, 0) }
				'raw-array', 'subclass-array', 'array-spoof', 'array-isa', 'array-limit' {
					mut object := source
					if mode == 'raw-array' { obj_header(source).cf_raw_values = true }
					if mode == 'subclass-array' { custom := objc_allocate_class(api.cls('NSMutableArray'), c'VinixUnsupportedPredicateArray', 0); objc_register_class(custom); objc_set_class(source, custom) }
					if mode == 'array-spoof' { object = objc_new(api.cls('NSObject')); objc_set_class(object, api.cls('NSMutableArray')) }
					if mode == 'array-isa' { objc_set_class(source, api.cls('NSArray')) }
					if mode == 'array-limit' { for _ in 0 .. 65537 { obj_header(source).items << api.cls('NSObject') } }
					api.message(object, c'filteredArrayUsingPredicate:', predicate, 0, 0)
				}
				'mutation-filter', 'mutation-inplace', 'destruct-eval' {
					mut state := PredicateFixtureBlockState{result: 1, callback: u64(unsafe { voidptr(predicate_fixture_action) })}
					block_predicate := predicate_fixture_block(api, mut state); predicate_fixture_fired = false; predicate_fixture_source = source; predicate_fixture_receiver = block_predicate
					predicate_fixture_mode = if mode == 'destruct-eval' { 'destruct' } else { 'mutate' }
					if mode == 'destruct-eval' { api.evaluate(block_predicate, value) } else { api.message(source, if mode == 'mutation-inplace' { c'filterUsingPredicate:' } else { c'filteredArrayUsingPredicate:' }, block_predicate, 0, 0) }
				}
				'destruct-copy', 'constructor-storage' {
					assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(predicate_fixture_constructor) }), c'@16@0:8')
					predicate_fixture_source = predicate; predicate_fixture_mode = if mode == 'destruct-copy' { 'destruct-copy' } else { 'constructor-storage' }
					api.message(predicate, c'copy', 0, 0, 0)
				}
				'result-storage', 'result-isa' {
					assert objc_add_method(api.cls('NSArray'), u64(c'.cxx_construct'), u64(unsafe { voidptr(predicate_fixture_array_constructor) }), c'@16@0:8')
					predicate_fixture_mode = mode; api.message(source, c'filteredArrayUsingPredicate:', predicate, 0, 0)
				}
				'variables-object' { api.message(predicate, c'evaluateWithObject:substitutionVariables:', value, value, 0) }
				else {}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0
	println('IOS-PREDICATE-REJECT:43 unsupported formats/options, invalid varargs/blocks, abstract/custom/provenance storage, array types/size, callback mutation, constructor changes and active destruction fail explicitly')
}
fn test_predicate_native() {
	$if macos { api := PredicateFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}; assert api.send != 0; predicate_fixture_shared(api); println('IOS-PREDICATE-NATIVE: metadata, constant/equality/block constructors, Darwin stack varargs, retained mutable operand, copied blocks and ordered array filters') }
}
