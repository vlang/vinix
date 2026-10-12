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
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
type SetSend = fn (u64, u64, u64, u64, u64) u64
struct SetApi {
	native bool
	send u64
	base u64
	mutable u64
	strings u64
	array u64
}
fn (api SetApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	mut sel := u64(name)
	$if macos { if api.native { sel = u64(C.sel_registerName(name)) } }
	return unsafe { SetSend(voidptr(api.send))(object, sel, a, b, c) }
}
fn (api SetApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0, 0) }
fn (api SetApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api SetApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api SetApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
fn (api SetApi) set(cls u64, values &u64, count u64) u64 { return api.message(cls, c'setWithObjects:count:', u64(values), count, 0) }
fn (api SetApi) count(set u64) u64 { return api.message(set, c'count', 0, 0, 0) }
fn set_cases(api SetApi) {
	pool := api.pool()
	one := api.string(c'one'); two := api.string(c'two'); equal := api.string(c'one')
	values := [one, equal, two]!
	for cls in [api.base, api.mutable]! {
		fresh := api.message(cls, c'new', 0, 0, 0); assert api.count(fresh) == 0 && api.message(fresh, c'anyObject', 0, 0, 0) == 0 && api.message(fresh, c'hash', 0, 0, 0) == 0; api.release(fresh)
		set := api.set(cls, unsafe { &values[0] }, 3)
		assert api.count(set) == 2 && api.message(set, c'hash', 0, 0, 0) == 2
		assert api.message(set, c'member:', equal, 0, 0) == one
		assert api.message(set, c'containsObject:', two, 0, 0) == 1 && api.message(set, c'containsObject:', 0, 0, 0) == 0 && api.message(set, c'member:', 0, 0, 0) == 0
		copy := api.message(set, c'copyWithZone:', 0, 0, 0); assert (copy == set) == (cls == api.base)
		mutable := api.message(set, c'mutableCopyWithZone:', 0, 0, 0); assert mutable != set
		api.message(mutable, c'removeObject:', two, 0, 0); assert api.count(mutable) == 1 && api.count(copy) == 2
		assert api.message(mutable, c'isSubsetOfSet:', copy, 0, 0) == 1 && api.message(mutable, c'intersectsSet:', copy, 0, 0) == 1 && api.message(copy, c'isEqualToSet:', set, 0, 0) == 1
		api.message(mutable, c'unionSet:', copy, 0, 0); assert api.count(mutable) == 2
		api.message(mutable, c'minusSet:', mutable, 0, 0); assert api.count(mutable) == 0
		api.message(mutable, c'setSet:', copy, 0, 0); api.message(mutable, c'intersectSet:', mutable, 0, 0); api.message(mutable, c'unionSet:', mutable, 0, 0); api.message(mutable, c'setSet:', mutable, 0, 0); assert api.count(mutable) == 2
		array := api.message(set, c'allObjects', 0, 0, 0); assert api.count(array) == 2
		from_array := api.message(api.base, c'setWithArray:', array, 0, 0); assert api.message(from_array, c'isEqual:', set, 0, 0) == 1
		api.message(mutable, c'removeAllObjects', 0, 0, 0); assert api.count(array) == 2 && api.count(mutable) == 0
		api.message(mutable, c'addObjectsFromArray:', array, 0, 0); assert api.count(mutable) == 2
		api.message(mutable, c'intersectSet:', 0, 0, 0); assert api.count(mutable) == 0
		api.message(mutable, c'addObject:', one, 0, 0); api.message(mutable, c'unionSet:', 0, 0, 0); api.message(mutable, c'minusSet:', 0, 0, 0); assert api.count(mutable) == 1
		api.message(mutable, c'setSet:', 0, 0, 0); assert api.count(mutable) == 0
		api.release(copy); api.release(mutable)
	}
	for factory in [c'setWithArray:', c'setWithSet:']! { assert api.count(api.message(api.base, factory, 0, 0, 0)) == 0 }
	mut value_class := u64(0)
	$if macos { if api.native { value_class = u64(C.objc_getClass(c'NSValue')) } }
	if !api.native { value_class = ios_runtime.names['NSValue'] }
	box1 := api.message(value_class, c'valueWithPointer:', 0x12345678, 0, 0); box2 := api.message(value_class, c'valueWithPointer:', 0x12345678, 0, 0)
	boxes := [box1, box2]!; assert api.count(api.set(api.base, unsafe { &boxes[0] }, 2)) == 1
	set := api.message(api.mutable, c'setWithCapacity:', 16, 0, 0)
	api.message(set, c'addObject:', one, 0, 0)
	mut state := [8]u64{}; mut buffer := [2]u64{}
	assert api.message(set, c'countByEnumeratingWithState:objects:count:', u64(unsafe { &state[0] }), u64(unsafe { &buffer[0] }), 2) == 1 && state[1] != 0 && state[2] != 0
	assert read64(state[1]) == one
	before := read64(state[2]); api.message(set, c'addObject:', equal, 0, 0); assert api.count(set) == 1 && read64(state[2]) != before
	missing_before := read64(state[2]); api.message(set, c'removeObject:', two, 0, 0); assert api.count(set) == 1 && read64(state[2]) != missing_before
	api.drain(pool)
}
fn set_runtime_api() SetApi { return SetApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), base: ios_runtime.names['NSSet'], mutable: ios_runtime.names['NSMutableSet'], strings: ios_runtime.names['NSString'], array: ios_runtime.names['NSArray']} }
fn test_set_native_behavior() {
	$if macos {
		api := SetApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), base: u64(C.objc_getClass(c'NSSet')), mutable: u64(C.objc_getClass(c'NSMutableSet')), strings: u64(C.objc_getClass(c'NSString')), array: u64(C.objc_getClass(c'NSArray'))}
		set_cases(api)
		println('IOS-SET-NATIVE: canonical equal members, count hashes, immutable/mutable copies, snapshots, algebra, nil collections and no-op enumeration mutation passed')
	}
}
fn set_test_hash(object u64, selector u64) u64 { _ = object; _ = selector; return 7 }
fn set_test_equal(object u64, selector u64, other u64) bool { _ = selector; return read64(object + 8) == read64(other + 8) }
fn set_test_custom_class(native bool) u64 {
	$if macos { if native {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixSetMemberFixture', 0); assert cls != unsafe { nil }
		assert C.class_addIvar(cls, c'value', 8, 3, c'Q')
		assert C.class_addMethod(cls, C.sel_registerName(c'hash'), unsafe { voidptr(set_test_hash) }, c'Q16@0:8')
		assert C.class_addMethod(cls, C.sel_registerName(c'isEqual:'), unsafe { voidptr(set_test_equal) }, c'B24@0:8@16')
		C.objc_registerClassPair(cls); return u64(cls)
	} }
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSetMemberFixture', 0); assert cls != 0
	assert objc_add_ivar(cls, c'value', 8, 3, c'Q')
	assert objc_add_method(cls, u64(c'hash'), u64(unsafe { voidptr(set_test_hash) }), c'Q16@0:8')
	assert objc_add_method(cls, u64(c'isEqual:'), u64(unsafe { voidptr(set_test_equal) }), c'B24@0:8@16')
	objc_register_class(cls); return cls
}
fn set_custom_cases(api SetApi, cls u64) {
	pool := api.pool()
	first := api.message(cls, c'new', 0, 0, 0); second := api.message(cls, c'new', 0, 0, 0); different := api.message(cls, c'new', 0, 0, 0)
	unsafe { *(&u64(first + 8)) = 1; *(&u64(second + 8)) = 1; *(&u64(different + 8)) = 2 }
	set := api.message(api.mutable, c'set', 0, 0, 0)
	for value in [first, second, different]! { api.message(set, c'addObject:', value, 0, 0) }
	assert api.count(set) == 2 && api.message(set, c'member:', second, 0, 0) == first
	api.release(first); api.release(second); api.release(different)
	assert api.message(set, c'containsObject:', different, 0, 0) == 1 // The set owns its surviving members.
	api.drain(pool)
}
fn test_set_custom_equality_and_ownership() {
	$if macos { api := SetApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), base: u64(C.objc_getClass(c'NSSet')), mutable: u64(C.objc_getClass(c'NSMutableSet')), strings: u64(C.objc_getClass(c'NSString'))}; set_custom_cases(api, set_test_custom_class(true)) }
	for _ in 0 .. 2 {
		objc_start(); api := set_runtime_api(); cls := set_test_custom_class(false)
		set_cases(api); set_custom_cases(api, cls); assert ios_runtime.live == 0
		assert objc_class_size(api.base) == 8 && objc_class_size(api.mutable) == 8 && objc_class_parent(api.mutable) == api.base
		assert ctext(u64(objc_method_types(objc_instance_method(api.base, u64(c'countByEnumeratingWithState:objects:count:'))))) == 'Q40@0:8^{?=Q^@^Q[5Q]}16^@24Q32'
		assert runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_OBJC_CLASS_$_NSMutableSet') or { panic(err) } == api.mutable
		for _ in 0 .. 100 {
			pool := api.pool(); set := api.message(api.mutable, c'set', 0, 0, 0); member := objc_new(cls); unsafe { *(&u64(member + 8)) = 1 }
			api.message(set, c'addObject:', member, 0, 0); objc_release(member)
			owner := objc_new(ios_runtime.names['NSObject']); objc_set_associated(owner, 9, set, 3); copied := objc_get_associated(owner, 9)
			assert copied != set && !obj_header(copied).set_mutable && object_equal(copied, set) && cf_hash(copied) == cf_hash(set)
			objc_set_class(set, ios_runtime.names['NSObject']); objc_release(owner); api.drain(pool); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 8)); assert objc_construct_instance(api.mutable, storage) == storage; api.message(storage, c'init', 0, 0, 0)
		pool := api.pool(); api.message(storage, c'addObject:', api.string(c'owned'), 0, 0); api.drain(pool)
		assert api.count(storage) == 1 && objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) }); assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-SET: shared native fixtures, custom hash collisions/equality, member ownership, layouts/types, CF equality/hash, 100 copy/isa-change releases, caller storage and two cycles passed')
}
__global set_reentry = u64(0)
fn set_mutating_hash(object u64, selector u64) u64 { _ = object; _ = selector; ns_set_mutate(set_reentry, 'removeAllObjects', 0); return 7 }
fn set_array_mutating_hash(object u64, selector u64) u64 {
	_ = object; _ = selector
	mut frame := RegisterFrame{}
	assert framework_dispatch(set_reentry, 'removeAllObjects', mut frame)
	return 7
}
fn test_set_rejections() {
	objc_start(); api := set_runtime_api(); cls := set_test_custom_class(false)
	for operation in 0 .. 13 {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); pool := api.pool(); _ = pool
			set := api.message(api.mutable, c'set', 0, 0, 0)
			match operation {
				0 { api.message(set, c'addObject:', 0, 0, 0) }
				1 { api.message(set, c'removeObject:', 0, 0, 0) }
				2 { immutable := api.message(api.base, c'set', 0, 0, 0); api.message(immutable, c'addObject:', api.string(c'one'), 0, 0) }
				3 { api.message(set, c'init', 0, 0, 0) }
				4 { api.message(api.mutable, c'setWithCapacity:', 4097, 0, 0) }
				5 { api.message(api.base, c'setWithObjects:count:', 0, 1, 0) }
				6 { api.message(set, c'unionSet:', api.string(c'wrong'), 0, 0) }
				7 { api.message(set, c'objectAtIndex:', 0, 0, 0) }
				8 { api.message(set, c'enumerateObjectsUsingBlock:', 0, 0, 0) }
				9 { set_reentry = set; assert objc_replace_method(cls, u64(c'hash'), u64(unsafe { voidptr(set_mutating_hash) }), c'Q16@0:8') != 0; value := objc_new(cls); api.message(set, c'addObject:', value, 0, 0) }
				10 { api.message(set, c'setObject:forKey:', api.string(c'value'), api.string(c'key'), 0) }
				11 { snapshot := api.message(set, c'allObjects', 0, 0, 0); api.message(snapshot, c'addObject:', api.string(c'value'), 0, 0) }
				else {
					set_reentry = api.message(ios_runtime.names['NSMutableArray'], c'array', 0, 0, 0)
					assert objc_replace_method(cls, u64(c'hash'), u64(unsafe { voidptr(set_array_mutating_hash) }), c'Q16@0:8') != 0
					value := objc_new(cls); api.message(set_reentry, c'addObject:', value, 0, 0); objc_release(value)
					api.message(api.base, c'setWithArray:', set_reentry, 0, 0)
				}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }; assert output.contains(['nil set member', 'nil set member', 'mutation of an immutable set', 'set reinitialization is not implemented', 'set capacity exceeds 4096', 'invalid set object buffer', 'set operation requires the expected collection type', 'array indexing is not supported on sets', 'unimplemented Objective-C method NSMutableSet enumerateObjectsUsingBlock:', 'reentrant set mutation is not implemented', 'dictionary operations are not supported on sets', 'mutation of an immutable JSON collection', 'set input changed during membership callback']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-SET-REJECT: nil members, immutable writes, reinitialization, bounds, buffers, incorrect collections, indexing/dictionary/block aliases, snapshots, reentrant mutation and input-array release during hashing fail explicitly')
}
