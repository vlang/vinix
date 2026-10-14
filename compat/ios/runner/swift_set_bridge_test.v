// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
type SetBridgeSend = fn (u64,u64,u64,u64,u64) u64
type SetBridgeMetadata = fn (u64) u64
type SetBridgeAccess = fn (u64,u64,u64) SwiftAssociatedMetadata
type SetBridgeLookup = fn (u64,u64,u64) u64
type SetBridgeSign = fn (u64,u64) u64
type SetBridgeProbe = fn (u64,u64,u64,u64,u64,&u64)
type SetBridgeWitness = fn (u64,u64,u64,u64,u64)
type SetBridgeRetain = fn (u64) u64
type SetBridgeRelease = fn (u64)
type SetBridgeDestroy = fn (u64,u64)
struct SetBridgeApi {
	native bool
	code u64
	entry u64
	core voidptr
	objc voidptr
	root u64
	@[required]
	metadata SetBridgeMetadata
	@[required]
	access SetBridgeAccess
	@[required]
	iterator_access SetBridgeAccess
	@[required]
	lookup SetBridgeLookup
	@[required]
	retain SetBridgeRetain
	@[required]
	release SetBridgeRelease
	@[required]
	objc_release SetBridgeRelease
	conformances [3]u64
}
fn set_bridge_api(native bool,code u64) SetBridgeApi {
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		overlay := C.dlopen(c'/usr/lib/swift/libswiftObjectiveC.dylib',2)
		foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib',2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		assert core != unsafe { nil } && overlay != unsafe { nil } && foundation != unsafe { nil } && objc != unsafe { nil }
		return SetBridgeApi{native:true,code:code,core:core,objc:objc,root:u64(C.objc_getClass(c'NSObject')),
			entry:u64(C.dlsym(foundation,c'$sSh10FoundationE36_unconditionallyBridgeFromObjectiveCyShyxGSo5NSSetCSgFZ')),
			metadata:unsafe { SetBridgeMetadata(C.dlsym(core,c'swift_getObjCClassMetadata')) },
			access:unsafe { SetBridgeAccess(C.dlsym(core,c'$sShMa')) },iterator_access:unsafe { SetBridgeAccess(C.dlsym(core,c'$sSh8IteratorVMa')) },
			lookup:unsafe { SetBridgeLookup(C.dlsym(core,c'swift_getWitnessTable')) },retain:unsafe { SetBridgeRetain(C.dlsym(core,c'swift_bridgeObjectRetain')) },
			release:unsafe { SetBridgeRelease(C.dlsym(core,c'swift_bridgeObjectRelease')) },objc_release:unsafe { SetBridgeRelease(C.dlsym(objc,c'objc_release')) },
			conformances:[u64(C.dlsym(overlay,c'$sSo8NSObjectCSH10ObjectiveCMc')),u64(C.dlsym(core,c'$sShyxGSTsMc')),u64(C.dlsym(core,c'$sSh8IteratorVyx_GStsMc'))]!}
	} }
	return SetBridgeApi{code:code,root:ios_runtime.names['NSObject'],entry:runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_$sSh10FoundationE36_unconditionallyBridgeFromObjectiveCyShyxGSo5NSSetCSgFZ') or {panic(err)},
		metadata:swift_objc_metadata,access:swift_set_access,iterator_access:swift_set_iterator_access,lookup:swift_witness_table,
		retain:swift_bridge_retain,release:swift_bridge_release,objc_release:objc_release,
		conformances:[runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib','_$sSo8NSObjectCSH10ObjectiveCMc') or {panic(err)},runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sShyxGSTsMc') or {panic(err)},runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSh8IteratorVyx_GStsMc') or {panic(err)}]!}
}
fn set_bridge_table(api SetBridgeApi,index int,metadata u64) u64 {
	mut descriptor := api.conformances[index]
	if api.native { descriptor = unsafe { SetBridgeSign(voidptr(api.code + 256))(descriptor,0xc6eb) } }
	return api.lookup(descriptor,metadata,0) & 0x0000ffffffffffff
}
fn set_bridge_send(api SetBridgeApi,owner u64,selector &char,a u64,b u64) u64 {
	$if macos { if api.native { return unsafe { SetBridgeSend(C.dlsym(api.objc,c'objc_msgSend'))(owner,u64(C.sel_registerName(selector)),a,b,0) } } }
	return unsafe { SetBridgeSend(voidptr(C.ios_objc_builtin))(owner,u64(selector),a,b,0) }
}
fn set_bridge_refs(api SetBridgeApi,owner u64) u64 {
	return if api.native { set_bridge_send(api,owner,c'retainCount',0,0) } else { u64(obj_header(owner).refs) }
}
fn set_bridge_object(api SetBridgeApi) u64 { return set_bridge_send(api,api.root,c'new',0,0) }
fn set_bridge_source(api SetBridgeApi,items []u64,mutable bool) u64 {
	name := if mutable {c'NSMutableSet'} else {c'NSSet'}
	$if macos { if api.native {
		allocated := set_bridge_send(api,u64(C.objc_getClass(name)),c'alloc',0,0)
		return set_bridge_send(api,allocated,c'initWithObjects:count:',u64(items.data),u64(items.len))
	} }
	source := objc_new(ios_runtime.names[if mutable {'NSMutableSet'} else {'NSSet'}])
	for item in items { ns_set_insert(source,item) }
	return source
}
fn set_bridge_call(api SetBridgeApi,source u64,element u64,hashable u64,guard u64) u64 {
	mut out := [u64(0xcafe),0,0,0,0xbeef]!
	unsafe { SetBridgeProbe(voidptr(api.code))(source,element,hashable,api.entry,guard,&out[1]) }
	assert out[0] == 0xcafe && out[2] == guard && out[3] == 0x5121 && out[4] == 0xbeef
	return out[1]
}
fn set_bridge_elements(api SetBridgeApi,owner u64,element u64,hashable u64,expected []u64) {
	metadata := api.access(0,element,hashable).metadata
	table := set_bridge_table(api,1,metadata)
	iterator := api.iterator_access(0,element,hashable).metadata
	next_table := set_bridge_table(api,2,iterator)
	mut storage := [u64(0xcafe),0,0,0,0,0,0xbeef]!
	mut result := [u64(0xcafe),0,0xbeef]!
	mut receiver := owner
	api.retain(owner) // makeIterator consumes its copied Self.
	invoke := unsafe { SetBridgeWitness(voidptr(api.code + 128)) }
	invoke(metadata,table,u64(unsafe { &receiver }),u64(unsafe { &storage[1] }),read64(table + 32) & 0x0000ffffffffffff)
	mut found := []bool{len:expected.len}
	for _ in 0 .. expected.len {
		invoke(iterator,next_table,u64(unsafe { &storage[1] }),u64(unsafe { &result[1] }),read64(next_table + 16) & 0x0000ffffffffffff)
		assert result[1] != 0
		index := expected.index(result[1]); assert index >= 0
		assert !found[index]; found[index] = true; api.objc_release(result[1])
	}
	invoke(iterator,next_table,u64(unsafe { &storage[1] }),u64(unsafe { &result[1] }),read64(next_table + 16) & 0x0000ffffffffffff)
	assert result[1] == 0 && storage[0] == 0xcafe && storage[6] == 0xbeef && result[0] == 0xcafe && result[2] == 0xbeef
	destroy := unsafe { SetBridgeDestroy(voidptr(read64(read64(iterator - 8) + 8) & 0x0000ffffffffffff)) }
	destroy(u64(unsafe { &storage[1] }),iterator)
}
fn set_bridge_worker(api SetBridgeApi,source u64,element u64,hashable u64,expected []u64,guard u64) {
	for _ in 0 .. 50 {
		owner := set_bridge_call(api,source,element,hashable,guard)
		set_bridge_elements(api,owner,element,hashable,expected); api.release(owner)
	}
}
fn set_bridge_suite(api SetBridgeApi,guard u64) {
	assert api.entry != 0
	empty := set_bridge_call(api,0,guard,guard,guard); api.release(empty)
	for mutable in [false,true]! { for count in [0,1,5,70]! {
		element := api.metadata(api.root); hashable := set_bridge_table(api,0,element)
		mut items := []u64{cap:count}
		for _ in 0 .. count { items << set_bridge_object(api) }
		source := set_bridge_source(api,items,mutable)
		before := set_bridge_refs(api,source)
		owner := set_bridge_call(api,source,element,hashable,guard)
		if mutable { set_bridge_send(api,source,c'removeAllObjects',0,0) }
		set_bridge_elements(api,owner,element,hashable,items)
		api.release(owner); assert set_bridge_refs(api,source) == before
		if count == 5 && !mutable {
			mut workers := []thread{}
			for _ in 0 .. 8 { workers << spawn set_bridge_worker(api,source,element,hashable,items,guard) }
			workers.wait(); assert set_bridge_refs(api,source) == before
		}
		owner2 := set_bridge_call(api,source,element,hashable,guard)
		api.objc_release(source)
		set_bridge_elements(api,owner2,element,hashable,if mutable {[]u64{}} else {items}); api.release(owner2)
		for item in items { assert set_bridge_refs(api,item) == 1; api.objc_release(item) }
	} }
}
__global set_bridge_callback_source u64
__global set_bridge_callback_metadata u64
__global set_bridge_callback_changed bool
fn set_bridge_callback_worker(metadata u64) u64 { return swift_nsobject_table_checked(metadata,false) or {panic(err)} }
fn set_bridge_callback_hash(_owner u64,_selector u64) u64 {
	if set_bridge_callback_metadata != 0 {
		worker := spawn set_bridge_callback_worker(set_bridge_callback_metadata); assert worker.wait() != 0
	}
	if set_bridge_callback_source != 0 && !set_bridge_callback_changed {
		set_bridge_callback_changed = true
		ns_set_mutate(set_bridge_callback_source,'removeAllObjects',0)
	}
	return 0
}
fn set_bridge_callback_equal(owner u64,_selector u64,other u64) bool { return obj_header(owner).tag == obj_header(other).tag }
fn set_bridge_reentry(api SetBridgeApi,guard u64) {
	cls := objc_allocate_class(api.root,c'VinixSetBridgeCollision',0)
	assert objc_add_method(cls,u64(c'hash'),u64(voidptr(set_bridge_callback_hash)),c'Q16@0:8')
	assert objc_add_method(cls,u64(c'isEqual:'),u64(voidptr(set_bridge_callback_equal)),c'B24@0:8@16')
	objc_register_class(cls)
	mut items := []u64{}
	for i in 0 .. 8 { owner := objc_new(cls); mut header := obj_header(owner); header.tag = i; items << owner }
	source := set_bridge_source(api,items,true)
	element := api.metadata(cls); hashable := set_bridge_table(api,0,element)
	set_bridge_callback_metadata = element; set_bridge_callback_source = source; set_bridge_callback_changed = false
	owner := set_bridge_call(api,source,element,hashable,guard)
	assert set_bridge_callback_changed && ns_set_header(source).items.len == 0
	set_bridge_callback_metadata = 0; set_bridge_callback_source = 0
	set_bridge_elements(api,owner,element,hashable,items); api.release(owner); api.objc_release(source)
	for item in items { assert set_bridge_refs(api,item) == 1; api.objc_release(item) }
}
fn test_swift_set_bridge() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && guard != u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0303f0,0xaa0503f3,0xaa0403f4,0xd28a2435,0xaa0403e8,0xd63f0200,0xf9000260,0xf9000674,0xf9000a75,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
	for i,op in [u32(0xa9be7bfd),0xa90153f3,0xaa0203f4,0xaa0303e8,0xaa0403f0,0xd63f0200,0xa94153f3,0xa8c27bfd,0xd65f03c0]! { write32(code + 128 + u64(i * 4),op) }
	write32(code + 256,0xdac10820); write32(code + 260,0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code),voidptr(code + 264)); assert C.mprotect(voidptr(code),page,C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		set_bridge_suite(set_bridge_api(true,code),guard)
		println('IOS-SET-BRIDGE-NATIVE: nil ignoring protected metadata/witness/Self, owned Set results, immutable/mutable source independence, generic Sequence/Iterator dispatch, borrowed source ownership and eight concurrent readers')
	}
	if _ := swift_foundation_set_unbridge_checked(0,guard,guard) { assert false }
	for _ in 0 .. 2 {
		objc_start(); api := set_bridge_api(false,code)
		set_bridge_suite(api,guard)
		set_bridge_reentry(api,guard)
		element := api.metadata(api.root); hashable := set_bridge_table(api,0,element)
		for source in [u64(1),guard,~u64(0)]! { if _ := swift_foundation_set_unbridge_checked(source,element,hashable) { assert false } }
		source := set_bridge_source(api,[]u64{},false)
		if _ := swift_foundation_set_unbridge_checked(source,guard,guard) { assert false }
		if _ := swift_foundation_set_unbridge_checked(source,element,guard) { assert false }
		mut header := obj_header(source); header.items << guard
		if _ := swift_foundation_set_unbridge_checked(source,element,hashable) { assert false }
		header.items.delete(0)
		header.cf_raw_values = true
		if _ := swift_foundation_set_unbridge_checked(source,element,hashable) { assert false }
		header.cf_raw_values = false
		api.objc_release(source)
		if _ := swift_foundation_set_unbridge_checked(source,element,hashable) { assert false }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		objc_stop(); if _ := swift_foundation_set_unbridge_checked(0,guard,guard) { assert false }
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(guard),page) == 0
	println('IOS-SET-BRIDGE: native-compatible owned generic Set ABI, registered NSObject reference elements, retained snapshots across mutation/source release, bitmap/hash-table storage and existing Sequence, guarded foreign/dead/type/table rejection, eight workers and two drained lifetimes')
}
