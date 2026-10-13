// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32

type StorageAllocate = fn (i64, u64) SwiftArrayAllocation
type StorageBufferAllocate = fn (i64, u64) u64
type StorageRetain = fn (u64) u64
type StorageRelease = fn (u64)
type StorageUnique = fn (u64) bool
type StorageAccess = fn (u64, u64) SwiftAssociatedMetadata
type StorageCopy = fn (u64, u64, u64) u64
type StorageSign = fn (u64, u64) u64
type StorageCString = fn (&u8) SwiftStringWords
type StorageObjCMetadata = fn (u64) u64

struct StorageApi {
	native bool
	string_metadata u64
	int_metadata u64
	objc_metadata u64
	@[required]
	allocate StorageAllocate
	@[required]
	buffer_allocate StorageBufferAllocate
	@[required]
	retain StorageRetain
	@[required]
	release StorageRelease
	@[required]
	unique StorageUnique
	@[required]
	access StorageAccess
}

fn storage_primitive(api StorageApi, element u64, stride u64) {
	for count in [i64(0), 1, 5, 257]! {
		value := api.allocate(count, element)
		assert value.owner != 0 && value.bytes == value.owner + 32
		assert read64(value.owner + 16) == u64(count)
		assert read64(value.owner + 24) == if count == 0 { u64(1) } else { u64(count) << 1 }
		if count == 0 {
			assert read64(value.owner + 8) == 0x80000004ffffffff
			assert !api.unique(value.owner)
		} else {
			assert read64(value.owner + 8) == 3 && api.unique(value.owner)
			for i in i64(0) .. count {
				if stride == 16 {
					text := if i % 2 == 0 { 'é 🎮' } else { 'a\x00b' }
					unsafe { *(&SwiftStringWords(value.bytes + u64(i) * stride)) = swift_string_literal(text.str, i64(text.len), false) }
				} else { unsafe { *(&u64(value.bytes + u64(i) * stride)) = u64(i) } }
			}
		}
		assert api.retain(value.owner) == value.owner && !api.unique(value.owner)
		api.release(value.owner)
		assert api.unique(value.owner) == (count != 0)
		api.release(value.owner)
	}
	assert api.allocate(0, element).owner == api.allocate(0, api.int_metadata).owner
}

fn storage_string_refs(api StorageApi, object u64) u64 {
	$if macos { if api.native { return u64(C.CFGetRetainCount(unsafe { voidptr(object) })) } }
	return u64(obj_header(object).refs)
}

fn storage_strings(api StorageApi, buffer bool) {
	mut object := u64(0)
	$if macos { if api.native { object = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	if !api.native { object = owned_string('Array Element destroy owner') }
	owner := if buffer { api.buffer_allocate(3, api.string_metadata) } else { api.allocate(3, api.string_metadata).owner }
	value := SwiftArrayAllocation{ owner: owner, bytes: owner + 32 }
	if buffer { assert read64(owner + 16) == 0 && read64(owner + 24) >> 1 >= 3 }
	for i in 0 .. 3 {
		$if macos { if api.native { C.CFRetain(unsafe { voidptr(object) }) } }
		if !api.native { objc_retain(object) }
		unsafe { *(&SwiftStringWords(value.bytes + u64(i * 16))) = SwiftStringWords{ first: 0, second: object | 0x5000000000000000 } }
	}
	if buffer { unsafe { *(&u64(owner + 16)) = 3 } }
	assert storage_string_refs(api, object) == 4
	metadata := api.access(0, api.string_metadata).metadata
	copy_witness := unsafe { StorageCopy(voidptr(read64(read64(metadata - 8) + 16))) }
	destroy_witness := unsafe { SwiftElementDestroy(voidptr(read64(read64(metadata - 8) + 8))) }
	mut source := value.owner; mut alias := u64(0)
	assert copy_witness(u64(unsafe { &alias }), u64(unsafe { &source }), metadata) == u64(unsafe { &alias })
	assert alias == source && !api.unique(source) && storage_string_refs(api, object) == 4
	destroy_witness(u64(unsafe { &source }), metadata)
	assert api.unique(alias) && storage_string_refs(api, object) == 4
	destroy_witness(u64(unsafe { &alias }), metadata)
	assert storage_string_refs(api, object) == 1
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(object) }) } }
	if !api.native { objc_release(object) }
}

fn storage_nested(api StorageApi) {
	inner := api.allocate(3, api.int_metadata)
	for i in 0 .. 3 { unsafe { *(&u64(inner.bytes + u64(i * 8))) = u64(i) } }
	element := api.access(0, api.int_metadata).metadata
	outer := api.allocate(3, element)
	for i in 0 .. 3 { unsafe { *(&u64(outer.bytes + u64(i * 8))) = api.retain(inner.owner) } }
	assert !api.unique(inner.owner)
	api.release(outer.owner)
	assert api.unique(inner.owner)
	api.release(inner.owner)
	// Destroying an uninitialized allocation is legal after its count is
	// cleared, as Swift's _deallocateUninitialized does before consumption.
	uninitialized := api.allocate(5, api.string_metadata)
	unsafe { *(&u64(uninitialized.owner + 16)) = 0 }
	api.release(uninitialized.owner)
}

fn storage_owned_tail(api StorageApi) {
	text := 'owned native UTF-8 String tail inside a typed Array'
	mut source := SwiftStringWords{}
	$if macos {
		if api.native {
			lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			initialize := unsafe { StorageCString(C.dlsym(lib, c'$sSS7cStringSSSPys4Int8VG_tcfC')) }
			source = initialize(text.str)
		}
	}
	if !api.native {
		source = swift_interpolation_init(64, 0)
		swift_string_append_bytes(u64(unsafe { &source }), u64(text.str), u64(text.len))
	}
	owner := source.second & swift_address_mask
	assert source.second & (u64(1) << 63) == 0 && read64(owner + 8) == 3
	value := api.allocate(3, api.string_metadata)
	copy_witness := unsafe { StorageCopy(voidptr(read64(read64(api.string_metadata - 8) + 16))) }
	for i in 0 .. 3 { assert copy_witness(value.bytes + u64(i * 16), u64(unsafe { &source }), api.string_metadata) == value.bytes + u64(i * 16) }
	assert (read64(owner + 8) >> 33) + 1 == 4
	api.release(value.owner)
	assert read64(owner + 8) == 3
	destroy := unsafe { SwiftElementDestroy(voidptr(read64(read64(api.string_metadata - 8) + 8))) }
	destroy(u64(unsafe { &source }), api.string_metadata)
}

struct StorageScenario {
	api StorageApi
	stride u64
	metadata u64
	reenter bool
mut:
	owner u64
	bytes u64
	visited u64
}

fn storage_resolver(api StorageApi) {
	for _ in 0 .. 20 {
		value := api.allocate(0, api.int_metadata)
		assert api.retain(value.owner) == value.owner
		api.release(value.owner); api.release(value.owner)
		assert api.access(0, api.string_metadata).state == 0
	}
}

fn storage_destroy(value u64, metadata u64) {
	mut scenario := unsafe { &StorageScenario(read64(metadata + 16)) }
	assert metadata == scenario.metadata && value == scenario.bytes + scenario.visited * scenario.stride
	assert read64(value) == scenario.visited + 1
	assert read64(scenario.owner + 16) == 5 // Allocation remains alive throughout all callbacks.
	if !scenario.api.native {
		assert scenario.owner !in ios_runtime.swift_arrays
		assert read64(scenario.owner + 8) & (u64(1) << 32) != 0
	}
	scenario.visited++
	if scenario.reenter { worker := spawn storage_resolver(scenario.api); worker.wait() }
}

fn storage_custom(api StorageApi, probe u64, alignment u64, size u64, count i64, reenter bool) u64 {
	page := usize(C.getpagesize())
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert words != u64(-1)
	witness := words + 64; metadata := words + 8
	stride := if size == 0 { u64(1) } else { (size + alignment - 1) & ~(alignment - 1) }
	mut scenario := StorageScenario{ api: api, stride: stride, metadata: metadata, reenter: reenter }
	unsafe {
		*(&u64(words)) = witness
		*(&u64(metadata)) = if size == 0 { u64(0x301) } else { u64(0x200) }
		*(&u64(metadata + 8)) = if size == 0 { u64(0) } else { read64(api.string_metadata + 8) }
		// An empty tuple has zero elements and a null labels pointer.
		*(&u64(metadata + 16)) = if size == 0 { u64(0) } else { u64(&scenario) }
		*(&u64(witness + 8)) = u64(voidptr(storage_destroy))
		*(&u64(witness + 64)) = size
		*(&u64(witness + 72)) = stride
		*(&u32(witness + 80)) = u32(alignment - 1) | if size == 0 { u32(0) } else { u32(0x10000) }
	}
	$if macos {
		if api.native {
			sign_code := unsafe { StorageSign(voidptr(probe)) }; sign_data := unsafe { StorageSign(voidptr(probe + 16)) }
			unsafe {
				*(&u64(witness + 8)) = sign_code(read64(witness + 8), (witness + 8) | (u64(1272) << 48))
				*(&u64(words)) = sign_data(witness, words | (u64(11839) << 48))
			}
		}
	}
	tail := (u64(32) + alignment - 1) & ~(alignment - 1)
	empty := api.allocate(0, metadata)
	assert empty.bytes == empty.owner + tail && !api.unique(empty.owner)
	api.release(empty.owner)
	value := api.allocate(count, metadata)
	scenario.owner = value.owner; scenario.bytes = value.bytes
	assert value.bytes == value.owner + tail && value.bytes % alignment == 0
	assert read64(value.owner + 16) == u64(count) && read64(value.owner + 24) == u64(count) << 1
	if size != 0 { for i in i64(0) .. count { unsafe { *(&u64(value.bytes + u64(i) * stride)) = u64(i + 1) } } }
	assert api.retain(value.owner) == value.owner
	api.release(value.owner); assert scenario.visited == 0
	api.release(value.owner); assert scenario.visited == if size == 0 { u64(0) } else { u64(count) }
	// Reserve the same layout with no live elements. Empty and partially
	// initialized tails must not invoke destroy for unused capacity.
	uninitialized := api.buffer_allocate(count, metadata)
	assert read64(uninitialized + 16) == 0 && read64(uninitialized + 24) >> 1 >= u64(count)
	assert (uninitialized + tail) % alignment == 0
	api.release(uninitialized)
	scenario.visited = 0
	scenario.owner = api.buffer_allocate(count, metadata)
	scenario.bytes = scenario.owner + tail
	if size != 0 { for i in i64(0) .. count { unsafe { *(&u64(scenario.bytes + u64(i) * stride)) = u64(i + 1) } } }
	unsafe { *(&u64(scenario.owner + 16)) = u64(count) }
	api.release(scenario.owner)
	assert scenario.visited == if size == 0 { u64(0) } else { u64(count) }
	// Native generic metadata permanently caches the supplied Element key.
	// Keep its fixture mapping alive until this test process exits.
	if !api.native { assert C.munmap(unsafe { voidptr(words) }, page) == 0 }
	return words
}

fn storage_worker(api StorageApi) {
	for _ in 0 .. 100 {
		value := api.allocate(5, api.string_metadata)
		for i in 0 .. 5 { unsafe { *(&SwiftStringWords(value.bytes + u64(i * 16))) = SwiftStringWords{ second: 0xe000000000000000 } } }
		assert api.retain(value.owner) == value.owner
		api.release(value.owner); api.release(value.owner)
		assert api.access(0, api.int_metadata).state == 0
		buffer := api.buffer_allocate(5, api.string_metadata)
		assert read64(buffer + 16) == 0 && read64(buffer + 24) >> 1 >= 5
		api.release(buffer)
	}
}

fn storage_buffers(api StorageApi, element u64, stride u64) {
	for capacity in [i64(0), 1, 2, 3, 7, 8, 15, 16, 31, 32, 257]! {
		for initialized in [i64(0), capacity / 2, capacity]! {
			owner := api.buffer_allocate(capacity, element)
			assert owner != 0 && read64(owner + 16) == 0
			if capacity == 0 {
				assert owner == api.allocate(0, api.int_metadata).owner
				assert read64(owner + 8) == 0x80000004ffffffff && read64(owner + 24) == 1
				assert !api.unique(owner)
			} else {
				assert read64(owner + 8) == 3 && api.unique(owner)
				assert read64(owner + 24) & 1 == 0 && read64(owner + 24) >> 1 >= u64(capacity)
				for i in i64(0) .. initialized {
					bytes := owner + 32 + u64(i) * stride
					if stride == 16 { unsafe { *(&SwiftStringWords(bytes)) = SwiftStringWords{ second: 0xe000000000000000 } } }
					else { unsafe { *(&u64(bytes)) = u64(i) } }
				}
				unsafe { *(&u64(owner + 16)) = u64(initialized) }
			}
			assert api.retain(owner) == owner && !api.unique(owner)
			api.release(owner)
			assert api.unique(owner) == (capacity != 0)
			api.release(owner)
		}
	}
}

fn storage_buffer_objects(api StorageApi) {
	mut object := u64(0)
	$if macos { if api.native { object = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	if !api.native { object = owned_string('partially initialized ObjC Array buffer') }
	owner := api.buffer_allocate(3, api.objc_metadata)
	assert read64(owner + 16) == 0 && read64(owner + 24) & 1 == 1 && read64(owner + 24) >> 1 >= 3
	for i in 0 .. 2 {
		$if macos { if api.native { C.CFRetain(unsafe { voidptr(object) }) } }
		if !api.native { objc_retain(object) }
		unsafe { *(&u64(owner + 32 + u64(i * 8))) = object }
	}
	// Poison the uninitialized slot: destruction must only visit the live prefix.
	unsafe { *(&u64(owner + 48)) = 0xdeadbeef; *(&u64(owner + 16)) = 2 }
	assert storage_string_refs(api, object) == 3
	assert api.retain(owner) == owner
	api.release(owner); assert storage_string_refs(api, object) == 3
	api.release(owner); assert storage_string_refs(api, object) == 1
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(object) }) } }
	if !api.native { objc_release(object) }
	empty := api.buffer_allocate(0, api.objc_metadata)
	assert empty == api.allocate(0, api.int_metadata).owner && read64(empty + 24) == 1
	api.release(empty)
}

fn storage_run(api StorageApi, probe u64) {
	storage_primitive(api, api.int_metadata, 8)
	storage_primitive(api, api.string_metadata, 16)
	storage_strings(api, false)
	storage_strings(api, true)
	storage_buffers(api, api.int_metadata, 8)
	storage_buffers(api, api.string_metadata, 16)
	storage_buffer_objects(api)
	storage_nested(api)
	storage_owned_tail(api)
	for alignment in [u64(1), 8, 16, 32, 64, 128, 256]! {
		storage_custom(api, probe, alignment, 8, 5, alignment == 64)
	}
	storage_custom(api, probe, 1, 0, 5, false)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn storage_worker(api) }
	workers.wait()
}

fn storage_invalid(element u64) {
	for count in [i64(-1), i64(-9223372036854775807) - 1, i64(0x7fffffffffffffff)]! {
		if _ := swift_array_layout(count, element) { assert false }
	}
	if _ := swift_array_layout(1, 0) { assert false }
	mut metadata := [u64(0), u64(0x200), 0, 0]!
	mut witness := [11]u64{}
	metadata[0] = u64(unsafe { &witness[0] }); pointer := u64(unsafe { &metadata[1] })
	for bad in 0 .. 8 {
		witness[1] = u64(unsafe { voidptr(storage_destroy) }); witness[8] = 8; witness[9] = 8; witness[10] = 0x10007
		metadata[1] = 0x200; metadata[2] = 0
		if bad == 0 { witness[9] = 0 }
		else if bad == 1 { witness[8] = 9 }
		else if bad == 2 { witness[10] = 0x10002 }
		else if bad == 3 { witness[10] = 0x410007 }
		else if bad == 4 { witness[1] = 0 }
		else if bad == 5 { metadata[1] = 0 }
		else if bad == 6 { metadata[1] = 0x303 }
		else { witness[9] = 9 }
		if _ := swift_array_layout(1, pointer) { assert false, bad.str() }
	}
	value := swift_array_allocate(1, element)
	unsafe { *(&SwiftStringWords(value.bytes)) = SwiftStringWords{ second: 0xe000000000000000 } }
	for delta in [i64(-2), i64(-9223372036854775807) - 1, i64(swift_strong_limit)]! {
		if _ := swift_buffer_refs(value.owner, delta) { assert false }
		assert read64(value.owner + 8) == 3
	}
	swift_unknown_retain(value.owner); swift_unknown_release(value.owner); swift_release(value.owner)
}

fn storage_retired(address u64) {
	$if macos { assert C.mprotect(unsafe { voidptr(address) }, usize(C.getpagesize()), C.PROT_READ) == -1 }
	$else { mut resident := u8(0); assert C.mincore(unsafe { voidptr(address) }, usize(C.getpagesize()), &resident) == -1 }
}

fn test_swift_array_storage() {
	page := usize(C.getpagesize())
	probe := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert probe != u64(-1)
	for i, instruction in [u32(0xdac10020), 0xd65f03c0, 0xd503201f, 0xd503201f, 0xdac10820, 0xd65f03c0]! { write32(probe + u64(i * 4), instruction) }
	C.__builtin___clear_cache(unsafe { voidptr(probe) }, unsafe { voidptr(probe + 24) })
	assert C.mprotect(unsafe { voidptr(probe) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	defer { assert C.munmap(unsafe { voidptr(probe) }, page) == 0 }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		objc_metadata := unsafe { StorageObjCMetadata(C.dlsym(lib, c'swift_getObjCClassMetadata')) }
		api := StorageApi{ native: true, string_metadata: u64(C.dlsym(lib, c'$sSSN')), int_metadata: u64(C.dlsym(lib, c'$sSiN')),
			objc_metadata: objc_metadata(u64(C.objc_getClass(c'NSString'))),
			allocate: unsafe { StorageAllocate(C.dlsym(lib, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
			buffer_allocate: unsafe { StorageBufferAllocate(C.dlsym(lib, c'$sSa28_allocateBufferUninitialized15minimumCapacitys06_ArrayB0VyxGSi_tFZ')) },
			retain: unsafe { StorageRetain(C.dlsym(lib, c'swift_bridgeObjectRetain')) }, release: unsafe { StorageRelease(C.dlsym(lib, c'swift_bridgeObjectRelease')) },
			unique: unsafe { StorageUnique(C.dlsym(lib, c'swift_isUniquelyReferenced_nonNull_native')) }, access: unsafe { StorageAccess(C.dlsym(lib, c'$sSaMa')) } }
		storage_run(api, probe)
		println('IOS-SWIFT-ARRAY-BUFFER-NATIVE: 66 Int/String capacity and initialized-count cases, owned String aliases, custom alignments through 256, zero-sized elements, uninitialized destruction, reentrant callbacks and eight workers')
		println('IOS-SWIFT-ARRAY-STORAGE-NATIVE: allocator result/header ABI, canonical immortal empty storage, alignments through 256, POD/zero-sized/String/custom elements, Array witness aliases, forward destruction, reentrant callbacks and eight allocation workers')
	}
	for _ in 0 .. 2 {
		objc_start(); library := '/usr/lib/swift/libswiftCore.dylib'
		api := StorageApi{ string_metadata: swift_string_metadata(), int_metadata: runtime_symbol(library, '_$sSiN') or { panic(err) }, objc_metadata: swift_objc_metadata(ios_runtime.names['NSString']),
			allocate: unsafe { StorageAllocate(voidptr(runtime_symbol(library, '_$ss27_allocateUninitializedArrayySayxG_BptBwlF') or { panic(err) })) },
			buffer_allocate: unsafe { StorageBufferAllocate(voidptr(runtime_symbol(library, '_$sSa28_allocateBufferUninitialized15minimumCapacitys06_ArrayB0VyxGSi_tFZ') or { panic(err) })) },
			retain: swift_bridge_retain, release: swift_bridge_release, unique: swift_is_unique_native, access: swift_array_access }
		storage_run(api, probe); storage_invalid(api.string_metadata)
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0
		empty := ios_runtime.swift_empty_array - 8
		objc_stop()
		assert ios_runtime.swift_empty_array == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.swift_metadata_arena == 0 && ios_runtime.live == 0
		storage_retired(empty)
	}
	println('IOS-SWIFT-ARRAY-STORAGE: checked typed allocation and alignment, real Element destruction after registry retirement without locked callbacks, immutable canonical empty owner, POD/zero-sized/String/custom values, Array aliases, overflow/rejected layouts, concurrent workers and two drained/unmapped teardowns')
	println('IOS-SWIFT-ARRAY-BUFFER: capacity reservation publishes count zero, caller initializes live prefix, aliases preserve ownership, unused tails never destroy, checked typed layouts and two drained runtime lifetimes')
}
