// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type HeapAllocate = fn (u64, u64, u64) u64
type HeapDeallocate = fn (u64, u64, u64)
type HeapRetain = fn (u64) u64
type HeapRelease = fn (u64)
type HeapReleaseN = fn (u64, u32)
type HeapUnique = fn (u64) bool
type HeapSign = fn (u64, u64) u64
type HeapArcProbe = fn (u64, u64, &u64)

struct HeapApi {
	native bool
	@[required]
	allocate HeapAllocate
	@[required]
	deallocate HeapDeallocate
	@[required]
	class_deallocate HeapDeallocate
	@[required]
	uninitialized HeapDeallocate
	@[required]
	retain HeapRetain
	@[required]
	release HeapRelease
	@[required]
	release_n HeapReleaseN
	@[required]
	bridge_retain HeapRetain
	@[required]
	bridge_release HeapRelease
	@[required]
	unknown_retain HeapRetain
	@[required]
	unknown_release HeapRelease
	@[required]
	unique HeapUnique
}

struct HeapScenario {
	api HeapApi
	metadata u64
	size u64
	mask u64
	class_object bool
	reenter bool
mut:
	owner u64
	child u64
	replacement u64
	calls u64
}

fn heap_resolve(api HeapApi) {
	if !api.native {
		library := '/usr/lib/swift/libswiftCore.dylib'
		for name in ['_swift_allocObject', '_swift_deallocObject', '_swift_release', '_$sSSN']! {
			assert (runtime_symbol(library, name) or { panic(err) }) != 0
		}
	}
}

fn heap_callback(owner u64) {
	mut scenario := unsafe { &HeapScenario(read64(owner + 16)) }
	assert owner == scenario.owner && scenario.calls == 0
	assert read64(owner + 8) == 0x100000003
	assert read64(owner + scenario.size - 8) == 0x12345678
	scenario.calls++
	if !scenario.api.native {
		C.ios_objc_initialize_lock()
		assert ios_runtime.swift_heap[owner].deiniting
		C.ios_objc_initialize_unlock()
		if _ := swift_buffer_refs(owner, 1) { assert false, 'deinitializing owner cannot be resurrected' }
		if _ := swift_buffer_refs(owner, -1) { assert false, 'deinitializing owner cannot be released twice' }
	}
	if scenario.reenter {
		// Another thread must acquire the registry lock while this callback waits.
		worker := spawn heap_resolve(scenario.api)
		worker.wait()
		heap_case(scenario.api, scenario.metadata, 48, 32, scenario.class_object, false)
	}
	if scenario.child != 0 { scenario.api.release(scenario.child) }
	if scenario.class_object { scenario.api.class_deallocate(owner, scenario.size, scenario.mask) }
	else { scenario.api.deallocate(owner, scenario.size, scenario.mask) }
	if scenario.reenter {
		// The old address may now be reused. Its new registry entry must survive
		// the outer release returning, without reading the old freed header.
		scenario.replacement = scenario.api.allocate(scenario.metadata, scenario.size, scenario.mask)
	}
}

fn heap_case(api HeapApi, metadata u64, size u64, alignment u64, class_object bool, reenter bool) {
	mut scenario := unsafe { &HeapScenario(C.__builtin_alloca(sizeof(HeapScenario))) }
	unsafe { *scenario = HeapScenario{ api: api, metadata: metadata, size: size,
		mask: alignment - 1, class_object: class_object, reenter: reenter } }
	owner := api.allocate(metadata, size, alignment - 1)
	scenario.owner = owner
	assert owner != 0 && owner & (alignment - 1) == 0
	assert read64(owner) & 0x0000ffffffffffff == metadata && read64(owner + 8) == 3 && api.unique(owner)
	unsafe { *(&u64(owner + 16)) = u64(scenario); *(&u64(owner + size - 8)) = 0x12345678 }
	assert api.retain(owner) == owner && read64(owner + 8) == 0x200000003 && !api.unique(owner)
	api.release(owner)
	assert scenario.calls == 0 && read64(owner + 8) == 3 && api.unique(owner)
	assert api.bridge_retain(owner) == owner
	api.bridge_release(owner)
	// unknown-object ARC is meaningful for class instances; heap contexts use
	// native ARC directly, since Darwin's unknown route expects a class object.
	if class_object && !api.native {
		assert api.unknown_retain(owner) == owner
		api.unknown_release(owner)
	}
	api.release_n(owner, 0)
	assert api.unique(owner)
	api.retain(owner); api.retain(owner)
	api.release_n(owner, 3)
	assert scenario.calls == 1
	if scenario.replacement != 0 { api.uninitialized(scenario.replacement, size, alignment - 1) }
}

fn heap_worker(api HeapApi, metadata u64) {
	for _ in 0 .. 100 { heap_case(api, metadata, 48, 16, false, false); heap_resolve(api) }
}

fn heap_alias_worker(api HeapApi, owner u64) {
	for _ in 0 .. 1000 { assert api.retain(owner) == owner; api.release(owner) }
}

fn heap_preserve(api HeapApi, owner u64, probe u64) {
	call := unsafe { HeapArcProbe(voidptr(probe + 64)) }
	mut registers := [17]u64{}
	for entry in [u64(unsafe { voidptr(api.retain) }), u64(unsafe { voidptr(api.release) }),
		u64(unsafe { voidptr(api.release) })]! {
		call(owner, entry, unsafe { &registers[0] })
		for reg in 9 .. 16 { assert registers[reg] == u64(0x5000 + reg) }
		assert registers[16] == 0x5020
	}
}

fn heap_suite(api HeapApi, probe u64) {
	page := usize(C.getpagesize())
	for kind in [u64(0), 0x400, 0x500]! {
		words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert words != u64(-1)
		metadata := words + 24
		unsafe {
			*(&u64(metadata)) = kind
			*(&u64(metadata + 32)) = 2 // Darwin type-metadata bit.
			*(&u64(metadata + 40)) = 2 // Native reference counting, address point zero.
			*(&u64(metadata + 48)) = 0x700000020
			*(&u64(metadata - 16)) = probe
		}
		$if macos {
			if api.native {
				sign := unsafe { HeapSign(voidptr(probe + 32)) }
				unsafe { *(&u64(metadata - 16)) = sign(probe, (metadata - 16) | (u64(0xbbbf) << 48)) }
			}
		}
		assert C.mprotect(unsafe { voidptr(words) }, page, C.PROT_READ) == 0
		for alignment in [u64(8), 16, 32, 64, 256, 4096]! {
			for size in [u64(32), 48, 4096]! {
				heap_case(api, metadata, size, alignment, kind == 0, alignment == 64)
				// Constructor failure: free a unique uninitialized owner without
				// dispatching its destructor or inspecting its stored properties.
				owner := api.allocate(metadata, size, alignment - 1)
				assert read64(owner + 8) == 3
				api.uninitialized(owner, size, alignment - 1)
			}
		}
		if kind == 0x400 {
			mut workers := []thread{}
			for _ in 0 .. 8 { workers << spawn heap_worker(api, metadata) }
			workers.wait()
			mut scenario := unsafe { &HeapScenario(C.__builtin_alloca(sizeof(HeapScenario))) }
			unsafe { *scenario = HeapScenario{ api: api, metadata: metadata, size: 48, mask: 15 } }
			owner := api.allocate(metadata, 48, 15); scenario.owner = owner
			unsafe { *(&u64(owner + 16)) = u64(scenario); *(&u64(owner + 40)) = 0x12345678 }
			mut aliases := []thread{}
			for _ in 0 .. 8 { aliases << spawn heap_alias_worker(api, owner) }
			aliases.wait()
			assert read64(owner + 8) == 3 && api.unique(owner) && scenario.calls == 0
			heap_preserve(api, owner, probe); assert scenario.calls == 1
			// A parent destructor releases its owned child outside the lock.
			mut child := unsafe { &HeapScenario(C.__builtin_alloca(sizeof(HeapScenario))) }
			unsafe { *child = HeapScenario{ api: api, metadata: metadata, size: 48, mask: 15 } }
			child.owner = api.allocate(metadata, 48, 15)
			scenario.child = child.owner; scenario.calls = 0
			scenario.owner = api.allocate(metadata, 48, 15)
			unsafe {
				*(&u64(child.owner + 16)) = u64(child); *(&u64(child.owner + 40)) = 0x12345678
				*(&u64(scenario.owner + 16)) = u64(scenario); *(&u64(scenario.owner + 40)) = 0x12345678
			}
			api.release(scenario.owner)
			assert scenario.calls == 1 && child.calls == 1
		}
		if !api.native {
			for invalid in [u64(0), 1, 15, 0x8000000000000000]! {
				if _ := swift_heap_layout(metadata, invalid, 7) { assert false }
			}
			if _ := swift_heap_layout(metadata, 32, 5) { assert false }
			if _ := swift_heap_layout(0, 32, 7) { assert false }
			owner := api.allocate(metadata, 32, 7)
			if _ := swift_heap_deallocate_checked(owner, 32, 7, false) { assert false }
			if _ := swift_heap_deallocate_checked(owner, 31, 7, true) { assert false }
			api.retain(owner)
			if _ := swift_heap_deallocate_checked(owner, 32, 7, true) { assert false }
			api.release(owner)
			assert read64(owner + 8) == 3 && api.unique(owner)
			api.uninitialized(owner, 32, 7)
			assert ios_runtime.swift_heap.len == 0
		}
		assert C.munmap(unsafe { voidptr(words) }, page) == 0
	}
}

fn heap_api(native bool) HeapApi {
	mut entries := [13]u64{}
	for i, name in ['_swift_allocObject', '_swift_deallocObject', '_swift_deallocClassInstance',
		'_swift_deallocUninitializedObject', '_swift_retain', '_swift_release', '_swift_release_n',
		'_swift_bridgeObjectRetain', '_swift_bridgeObjectRelease', '_swift_unknownObjectRetain',
		'_swift_unknownObjectRelease', '_swift_isUniquelyReferenced_nonNull_native']! {
		if native {
			lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			entries[i] = u64(C.dlsym(lib, name[1..].str))
		} else { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0
	}
	return HeapApi{
		native: native, allocate: unsafe { HeapAllocate(voidptr(entries[0])) },
		deallocate: unsafe { HeapDeallocate(voidptr(entries[1])) },
		class_deallocate: unsafe { HeapDeallocate(voidptr(entries[2])) },
		uninitialized: unsafe { HeapDeallocate(voidptr(entries[3])) },
		retain: unsafe { HeapRetain(voidptr(entries[4])) }, release: unsafe { HeapRelease(voidptr(entries[5])) },
		release_n: unsafe { HeapReleaseN(voidptr(entries[6])) },
		bridge_retain: unsafe { HeapRetain(voidptr(entries[7])) }, bridge_release: unsafe { HeapRelease(voidptr(entries[8])) },
		unknown_retain: unsafe { HeapRetain(voidptr(entries[9])) }, unknown_release: unsafe { HeapRelease(voidptr(entries[10])) },
		unique: unsafe { HeapUnique(voidptr(entries[11])) }
	}
}

fn test_swift_heap() {
	page := usize(C.getpagesize())
	probe := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert probe != u64(-1)
	for i, word in [u32(0xaa1403e0), 0x58000070, 0xd61f0200, 0xd503201f, 0, 0, 0, 0, 0xdac10020, 0xd65f03c0]! {
		write32(probe + u64(i) * 4, word)
	}
	unsafe { *(&u64(probe + 16)) = u64(voidptr(heap_callback)) }
	base := probe + 64
	write32(base, 0xa9be7bfd)
	write32(base + 4, 0xa90153f3)
	write32(base + 8, 0xaa0203f3)
	write32(base + 12, 0xaa0103f0)
	for reg in 1 .. 16 { write32(base + u64(3 + reg) * 4, 0xd2800000 | (u32(0x5000 + reg) << 5) | u32(reg)) }
	write32(base + 76, 0xd2800000 | (u32(0x5020) << 5) | 20)
	write32(base + 80, 0xd63f0200)
	for pair in 0 .. 8 {
		reg := u32(pair * 2)
		write32(base + u64(21 + pair) * 4, 0xa9000000 | (u32(pair * 2) << 15) | ((reg + 1) << 10) | (19 << 5) | reg)
	}
	write32(base + 116, 0xf9004274)
	write32(base + 120, 0xa94153f3)
	write32(base + 124, 0xa8c27bfd)
	write32(base + 128, 0xd65f03c0)
	C.__builtin___clear_cache(unsafe { voidptr(probe) }, unsafe { voidptr(base + 132) })
	assert C.mprotect(unsafe { voidptr(probe) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		heap_suite(heap_api(true), probe)
		println('IOS-SWIFT-HEAP-NATIVE: aligned class/context owners, x20 destructors, exact ARC header, constructor failure, child destruction, reentrant resolution and concurrent ARC measured')
	}
	for _ in 0 .. 2 {
		objc_start()
		heap_suite(heap_api(false), probe)
		code := ios_runtime.swift_arc_code
		assert code != 0 && ios_runtime.swift_heap.len == 0
		assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
		objc_stop()
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arc_code == 0
		assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ) == -1
	}
	assert C.munmap(unsafe { voidptr(probe) }, page) == 0
	println('IOS-SWIFT-HEAP: native allocation/destructor ABI, 54 aligned layouts, initialized and uninitialized ownership, preserved bytes, batch/bridge/unknown ARC, eight allocation and shared-owner workers, unlocked reentrant callbacks, rejected invalid states and two drained/unmapped cycles')
}
