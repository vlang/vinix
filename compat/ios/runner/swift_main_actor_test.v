// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr

type MainActorAccess = fn (u64) SwiftAssociatedMetadata
type MainActorProbe = fn (u64,u64,u64,&u64)
type MainActorRetain = fn (u64) u64
type MainActorRelease = fn (u64)
type MainActorUnique = fn (u64) bool
type MainActorCopy = fn (u64,u64,u64) u64
type MainActorDestroy = fn (u64,u64)
type MainActorType = fn (u64) u64
struct MainActorApi {
	native bool
	access u64
	getter u64
	descriptor u64
	@[required]
	retain MainActorRetain
	@[required]
	release MainActorRelease
	@[required]
	unknown_retain MainActorRetain
	@[required]
	unknown_release MainActorRelease
	@[required]
	unique MainActorUnique
	@[required]
	object_type MainActorType
}
fn main_actor_relative(field u64) u64 { return u64(i64(field) + i64(i32(read32(field)))) }
fn main_actor_first() u64 { return swift_main_actor_arena() or { panic(err) } }

fn main_actor_shared(api MainActorApi,probe MainActorProbe,metadata u64) u64 {
	mut out := [u64(0xfeedface),0,0,0,0,0xfeedface]!
	probe(api.getter,metadata,0x5021,unsafe { &out[1] })
	assert out[0] == 0xfeedface && out[5] == 0xfeedface
	assert out[1] != 0 && out[3] == metadata && out[4] == 0x5021
	return out[1]
}

fn main_actor_worker(api MainActorApi,probe MainActorProbe) u64 {
	mut own := api
	if !api.native {
		own = main_actor_api()
		assert own.access == api.access && own.getter == api.getter && own.descriptor == api.descriptor
	}
	access := unsafe { MainActorAccess(voidptr(own.access)) }
	response := access(0xff)
	assert response.state == 0
	owner := main_actor_shared(own,probe,response.metadata)
	for _ in 0 .. 1000 {
		assert main_actor_shared(own,probe,response.metadata) == owner
		assert own.retain(owner) == owner && own.unknown_retain(owner) == owner
		assert !own.unique(owner) && own.object_type(owner) == response.metadata
		own.unknown_release(owner); own.release(owner)
		assert read64(owner + 8) == swift_main_actor_immortal
	}
	return owner
}

fn main_actor_api() MainActorApi {
	library := '/usr/lib/swift/libswift_Concurrency.dylib'
	return MainActorApi{
		access: runtime_symbol(library,'_$sScMMa') or { panic(err) }
		getter: runtime_symbol(library,'_$sScM6sharedScMvgZ') or { panic(err) }
		descriptor: runtime_symbol(library,'_$sScMMn') or { panic(err) }
		retain: swift_retain, release: swift_release, unknown_retain: swift_unknown_retain,
		unknown_release: swift_unknown_release, unique: swift_is_unique_native, object_type: swift_object_type
	}
}

fn main_actor_suite(api MainActorApi,probe MainActorProbe) u64 {
	access := unsafe { MainActorAccess(voidptr(api.access)) }
	metadata := access(0).metadata
	for request in [u64(0),1,0xff,0x100,0x1ff,u64(-1)]! {
		response := access(request)
		assert response.metadata == metadata && response.state == 0
	}
	assert read64(metadata + 64) == api.descriptor && read32(metadata + 40) & 2 != 0
	assert read32(metadata + 44) == 0 && read32(metadata + 48) == 16
	assert unsafe { *(&u16(metadata + 52)) } == 7
	assert read32(api.descriptor) & 31 == 16 && read32(api.descriptor) & 0x80 == 0
	assert unsafe { (&char(main_actor_relative(api.descriptor + 8))).vstring() } == 'MainActor'
	owner := main_actor_shared(api,probe,metadata)
	assert read64(owner) & 0x0000ffffffffffff == metadata && read64(owner + 8) == swift_main_actor_immortal
	assert api.object_type(owner) == metadata && !api.unique(owner)
	page := u64(C.getpagesize())
	storage := u64(C.mmap(unsafe { nil },usize(page * 3),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert storage != u64(-1)
	assert C.mprotect(voidptr(storage),usize(page),C.PROT_NONE) == 0
	assert C.mprotect(voidptr(storage + page * 2),usize(page),C.PROT_NONE) == 0
	source := storage + page * 2 - 8
	destination := source - 8
	unsafe { *(&u64(source)) = owner }
	witness := read64(metadata - 8)
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8
	assert read32(witness + 80) & 0x7fffff == 0x10007 && read32(witness + 84) == 0x7fffffff
	for slot in [u64(0),2,3,4,5]! {
		unsafe { *(&u64(destination)) = owner }
		copy_value := unsafe { MainActorCopy(voidptr(read64(witness + slot * 8) & 0x0000ffffffffffff)) }
		assert copy_value(destination,source,metadata) == destination && read64(destination) == owner
		assert read64(source) == owner && read64(owner + 8) == swift_main_actor_immortal
	}
	destroy := unsafe { MainActorDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	destroy(source,metadata)
	assert read64(source) == owner && read64(owner + 8) == swift_main_actor_immortal
	// The getter's metatype is borrowed and unused once its final singleton
	// exists. No dereference of a protected metatype or mutation of x20/x21.
	assert main_actor_shared(api,probe,storage) == owner
	assert C.munmap(voidptr(storage),usize(page * 3)) == 0
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn main_actor_worker(api,probe) }
	for result in workers.wait() { assert result == owner }
	assert read64(owner + 8) == swift_main_actor_immortal
	return owner
}

fn test_swift_main_actor() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xf90013f5,0xaa0003f0,0xaa0103f4,
		0xaa0203f5,0xaa0303f3,0xd63f0200,0xa9000660,0xa9015674,0xf94013f5,
		0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code + 56))
	assert C.mprotect(voidptr(code),page,C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { MainActorProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib',2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		assert lib != unsafe { nil } && core != unsafe { nil }
		api := MainActorApi{ native: true, access: u64(C.dlsym(lib,c'$sScMMa')),
			getter: u64(C.dlsym(lib,c'$sScM6sharedScMvgZ')), descriptor: u64(C.dlsym(lib,c'$sScMMn')),
			retain: unsafe { MainActorRetain(C.dlsym(core,c'swift_retain')) },
			release: unsafe { MainActorRelease(C.dlsym(core,c'swift_release')) },
			unknown_retain: unsafe { MainActorRetain(C.dlsym(core,c'swift_unknownObjectRetain')) },
			unknown_release: unsafe { MainActorRelease(C.dlsym(core,c'swift_unknownObjectRelease')) },
			unique: unsafe { MainActorUnique(C.dlsym(core,c'swift_isUniquelyReferenced_nonNull_native')) },
			object_type: unsafe { MainActorType(C.dlsym(core,c'swift_getObjectType')) } }
		assert api.access != 0 && api.getter != 0 && api.descriptor != 0
		main_actor_suite(api,probe)
		println('IOS-MAIN-ACTOR-NATIVE: complete class accessor, immortal shared reference and unchanged ARC bits, unknown/native ARC and object type, eight workers, exact bounded copy/take/destroy witnesses, borrowed protected metatype and guarded x20/x21')
	}
	if _ := swift_main_actor_arena() { assert false }
	for _ in 0 .. 2 {
		objc_start()
		// Concurrent first publication must expose one completely sealed arena.
		mut first := []thread u64{}
		for _ in 0 .. 8 { first << spawn main_actor_first() }
		arenas := first.wait()
		for arena in arenas { assert arena == arenas[0] }
		api := main_actor_api()
		owner := main_actor_suite(api,probe)
		metadata := read64(owner)
		assert swift_mangled_nominal(api.descriptor) or { panic(err) } == metadata
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.objects.len == 0
		// Actual allocations through the private class metadata still have a
		// meaningful destructor, unlike the immortal singleton's static storage.
		allocated := swift_heap_allocate(metadata,16,7)
		assert allocated != owner && swift_object_type(allocated) == metadata
		swift_release(allocated); assert ios_runtime.swift_heap.len == 0
		assert swift_array_access(0,metadata).state == 0
		storage := swift_array_allocate(3,metadata)
		unsafe { *(&u64(storage.owner + 16)) = 3; *(&u64(storage.bytes)) = owner
			*(&u64(storage.bytes + 8)) = owner; *(&u64(storage.bytes + 16)) = owner }
		swift_release(storage.owner)
		assert read64(owner + 8) == swift_main_actor_immortal
		if _ := swift_heap_deallocate_checked(owner,16,7,false) { assert false }
		for name in ['_$sScMScAsMc','_$sScM15unownedExecutorScevg','_swift_task_enqueueMainExecutor']! {
			if _ := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib',name) { assert false }
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sScMMa') { assert false }
		assert ios_runtime.live == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_main_actor_arena
		objc_stop()
		assert ios_runtime.swift_main_actor_arena == 0 && ios_runtime.swift_main_actor_retired
		assert C.mprotect(voidptr(arena),page,C.PROT_READ) != 0
		assert C.mprotect(voidptr(arena + u64(page)),page,C.PROT_READ) != 0
		if _ := swift_main_actor_arena() { assert false }
		if _ := swift_object_type_checked(owner) { assert false }
		if _ := swift_buffer_refs(owner,0) { assert false }
	}
	assert C.munmap(voidptr(code),page) == 0
	println('IOS-MAIN-ACTOR: sealed final class metadata and canonical immortal getter, native/unknown ARC and exact value witnesses, genuine allocated-instance destruction and typed-array ownership, eight first resolvers/workers, protected metatype, nominal lookup and object type, rejected executor/conformance imports, two drained/unmapped lifetimes')
}
