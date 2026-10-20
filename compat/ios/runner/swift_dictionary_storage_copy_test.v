// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <objc/runtime.h>
}

fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)

type DscProbe = fn (u64, u64, u64, u64, &u64)
type DscAccess = fn (u64, u64, u64, u64) SwiftAssociatedMetadata
type DscDrop = fn (u64)
type DscObjMetadata = fn (u64) u64

fn dsc_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203f4,
		0xaa0303e8, 0xaa0403f3, 0xd28a0435, 0xd63f0200, 0xf9000260, 0xf9000674, 0xf9000a75, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 128, 0xaa1403e0)
	write32(code + 132, 0x58000070)
	write32(code + 136, 0xd61f0200)
	write32(code + 140, 0xd503201f)
	unsafe { *(&u64(code + 144)) = u64(voidptr(dsc_destroy)) }
}

fn dsc_destroy(owner u64) {
	metadata := read64(owner)
	if read64(owner + 16) != 0 {
		key := read64(metadata + 176)
		value := read64(metadata + 184)
		key_stride := read64(read64(key - 8) + 72)
		value_stride := read64(read64(value - 8) + 72)
		for bucket in u64(0) .. (u64(1) << unsafe { *(&u8(owner + 32)) }) {
			if read64(owner + 64 + bucket / 64 * 8) & (u64(1) << (bucket & 63)) == 0 { continue }
			unsafe { SwiftSequenceDestroy(voidptr(read64(read64(key - 8) + 8)))(read64(owner + 48) + bucket * key_stride, key) }
			unsafe { SwiftSequenceDestroy(voidptr(read64(read64(value - 8) + 8)))(read64(owner + 56) + bucket * value_stride, value) }
		}
	}
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageC4copy8originalAByxq_Gs05__RawaB0C_tFZ') != none
	// Match the measured native deallocating destructor's fixed arguments.
	if _ := swift_heap_deallocate_checked(owner, 64, 7, false) {
		assert false
	}
	swift_heap_deallocate_class(owner, 64, 7)
}

fn dsc_class(data u64, code u64, key u64, value u64, hashable u64) u64 {
	metadata := data + 24
	descriptor := data + 272
	unsafe {
		*(&u64(metadata - 16)) = code + 128
		*(&u64(metadata)) = metadata + 256
		*(&u64(metadata + 32)) = 2
		*(&u64(metadata + 64)) = descriptor
		*(&u64(metadata + 176)) = key
		*(&u64(metadata + 184)) = value
		*(&u64(metadata + 192)) = hashable
	}
	write32(metadata + 40, 2)
	write32(metadata + 48, 64)
	write32(metadata + 52, 7)
	write32(metadata + 56, 232)
	write32(metadata + 60, 24)
	write32(descriptor, 0xd0)
	swift_protocol_relative(descriptor + 4, data + 352)
	swift_protocol_relative(descriptor + 8, data + 384)
	write32(descriptor + 28, 26)
	write32(descriptor + 32, 4)
	swift_protocol_relative(data + 360, data + 416)
	C.memcpy(voidptr(data + 384), c'_DictionaryStorage', 19)
	C.memcpy(voidptr(data + 416), c'Swift', 6)
	return metadata
}

fn dsc_unused_copy(_a u64, _b u64, _c u64) u64 { panic('raw copy invoked a value witness') }

fn dsc_unused_destroy(_a u64, _b u64) { panic('raw copy destroyed an element') }

fn dsc_unused_tag(_a u64, _b u32, _c u64) u32 { panic('raw copy inspected an enum') }

fn dsc_unused_store(_a u64, _b u32, _c u32, _d u64) { panic('raw copy initialized an enum') }

fn dsc_wide(data u64, size u64, stride u64, alignment u32) u64 {
	metadata := data + 16
	witness := data + 256
	unsafe {
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = data + 128
	}
	write32(data + 128, 0x51)
	swift_protocol_relative(data + 132, data + 192)
	swift_protocol_relative(data + 136, data + 224)
	swift_protocol_relative(data + 200, data + 208)
	C.memcpy(voidptr(data + 208), c'Swift', 6)
	C.memcpy(voidptr(data + 224), c'CopyLayoutFixture', 18)
	for i, entry in [u64(unsafe { voidptr(dsc_unused_copy) }),
		u64(unsafe { voidptr(dsc_unused_destroy) }), u64(unsafe { voidptr(dsc_unused_copy) }),
		u64(unsafe { voidptr(dsc_unused_copy) }), u64(unsafe { voidptr(dsc_unused_copy) }),
		u64(unsafe { voidptr(dsc_unused_copy) }), u64(unsafe { voidptr(dsc_unused_tag) }),
		u64(unsafe { voidptr(dsc_unused_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = entry }
	}
	unsafe {
		*(&u64(witness + 64)) = size
		*(&u64(witness + 72)) = stride
	}
	write32(witness + 80, alignment - 1)
	return metadata
}

fn dsc_call(code u64, entry u64, original u64, metadata u64, guard u64) u64 {
	mut captured := [u64(0), 0, 0]!
	unsafe { DscProbe(voidptr(code))(entry, original, metadata, guard, &captured[0]) }
	assert captured[1] == metadata && captured[2] == 0x5021
	return captured[0]
}

fn dsc_shape(owner u64, metadata u64, scale u8, key_stride u64, key_align u64, value_stride u64, value_align u64) {
	buckets := u64(1) << scale
	words := (buckets + 63) / 64
	keys := (64 + words * 8 + key_align - 1) & ~(key_align - 1)
	values := (keys + buckets * key_stride + value_align - 1) & ~(value_align - 1)
	assert read64(owner) == metadata && read64(owner + 16) == 0
	assert read64(owner + 24) == if scale == 0 {
		u64(0)
	} else {
		buckets - buckets / 4 - u64(scale == 1)
	}
	assert read64(owner + 32) == u64(scale) | (u64(0x89abcdef) << 32)
	assert read64(owner + 40) == 0x123456789abcdef0
	assert read64(owner + 48) == owner + keys && read64(owner + 56) == owner + values
	assert owner & (key_align - 1) == 0 && owner & (value_align - 1) == 0
	for i in u64(0) .. words {
		assert read64(owner + 64 + i * 8) == if buckets < 64 {
			~((u64(1) << u32(buckets)) - 1)
		} else {
			u64(0)
		}
	}
}

fn dsc_profile(code u64, entry u64, original u64, metadata u64, key u64, value u64, native bool) {
	key_witness := read64(key - 8) & 0x0000ffffffffffff
	value_witness := read64(value - 8) & 0x0000ffffffffffff
	for scale in [u8(0), 1, 2, 5, 6, 7, 14]! {
		unsafe { *(&u64(original + 32)) = u64(scale) | (u64(0x89abcdef) << 32) | 0x00000000fffeff00 }
		mut before := [8]u64{}
		C.memcpy(unsafe { &before[0] }, voidptr(original), 64)
		owner := dsc_call(code, entry, original, metadata, original + 64)
		assert C.memcmp(unsafe { &before[0] }, voidptr(original), 64) == 0
		dsc_shape(owner, metadata, scale, read64(key_witness + 72), u64(read32(key_witness + 80) & 255) + 1, read64(value_witness + 72), u64(read32(value_witness + 80) & 255) + 1)
		if !native {
			storage := ios_runtime.swift_heap[owner] or { panic('unregistered copied storage') }
			assert storage.size == read64(owner + 56) - owner + (u64(1) << scale) * read64(value_witness + 72)
			assert read64(owner + 8) == 3
			swift_release(owner)
		} else {
			$if macos {
				core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
				unsafe { DscDrop(C.dlsym(core, c'swift_release'))(owner) }
			}
		}
	}
}

fn dsc_worker(entry u64, original u64, metadata u64) {
	for _ in 0 .. 32 {
		owner := swift_dictionary_storage_copy(original, metadata)
		swift_release(owner)
	}
	assert entry == runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageC4copy8originalAByxq_Gs05__RawaB0C_tFZ') or { panic(err) }
}

fn dsc_refs(object u64, native bool) i64 {
	$if macos {
		if native { return C.CFGetRetainCount(voidptr(object)) }
	}
	return obj_header(object).refs
}

fn dsc_ownership(code u64, entry u64, original u64, metadata u64, native bool) {
	mut object := u64(0)
	mut release := DscDrop(swift_release)
	$if macos {
		if native {
			object = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
			C.CFRetain(voidptr(object))
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			release = unsafe { DscDrop(C.dlsym(core, c'swift_release')) }
		}
	}
	if !native {
		object = owned_string('Dictionary raw copy retains only after caller initialization')
		objc_retain(object)
	}
	unsafe { *(&u64(original + 32)) = u64(2) | (u64(0x89abcdef) << 32) }
	source := dsc_call(code, entry, original, metadata, original + 64)
	unsafe {
		*(&u64(read64(source + 48) + 8)) = 17
		*(&u64(read64(source + 56) + 8)) = object
		*(&u64(source + 64)) |= 2
		*(&u64(source + 16)) = 1
	}
	assert dsc_refs(object, native) == 2
	copy := dsc_call(code, entry, source, metadata, original + 64)
	assert dsc_refs(object, native) == 2 && read64(copy + 16) == 0
	// The native caller copies each initialized key/value and only then owns a
	// populated snapshot. Releasing either storage must leave its peer intact.
	for offset in [u64(176), 184]! {
		type_metadata := read64(metadata + offset)
		witness := read64(type_metadata - 8) & 0x0000ffffffffffff
		initialize := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 16) & 0x0000ffffffffffff)) }
		field := if offset == 176 { u64(48) } else { u64(56) }
		initialize(read64(copy + field) + 8, read64(source + field) + 8, type_metadata)
	}
	unsafe {
		*(&u64(copy + 64)) = read64(source + 64)
		*(&u64(copy + 16)) = 1
	}
	assert dsc_refs(object, native) == 3
	release(source)
	assert dsc_refs(object, native) == 2
	assert read64(read64(copy + 48) + 8) == 17 && read64(read64(copy + 56) + 8) == object
	release(copy)
	assert dsc_refs(object, native) == 1
	$if macos {
		if native {
			C.CFRelease(voidptr(object))
			return
		}
	}
	objc_release(object)
}

fn test_swift_dictionary_storage_copy() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	guard := code + u64(page) * 3
	original := guard - 64
	dsc_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 152))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	wide := dsc_wide(code + u64(page) * 2, 17, 64, 64)
	wide_key := dsc_wide(code + u64(page) * 2 + 512, 17, 256, 256)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		access := unsafe { DscAccess(C.dlsym(core, c'$ss18_DictionaryStorageCMa')) }
		entry := u64(C.dlsym(core, c'$ss18_DictionaryStorageC4copy8originalAByxq_Gs05__RawaB0C_tFZ'))
		int_type := u64(C.dlsym(core, c'$sSiN'))
		string_type := u64(C.dlsym(core, c'$sSSN'))
		for pair in [[string_type, int_type]!, [string_type, string_type]!,
			[string_type, u64(C.dlsym(core, c'$ss12StaticStringVN'))]!,
			[u64(C.dlsym(core, c'$sSbN')), u64(C.dlsym(core, c'$sytN')) + 8]!, [int_type, wide]!,
			[wide_key, wide]!, [string_type, u64(C.dlsym(core, c'$sypN')) + 8]!]! {
			metadata := access(0, pair[0], pair[1], u64(C.dlsym(core, c'$sSSSHsWP'))).metadata
			C.memset(voidptr(original), 0xa5, 64)
			unsafe { *(&u64(original + 40)) = 0x123456789abcdef0 }
			dsc_profile(code, entry, original, metadata, pair[0], pair[1], true)
		}
		object_type := unsafe { DscObjMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }(u64(C.objc_getClass(c'NSString')))
		owned_type := access(0, int_type, object_type, u64(C.dlsym(core, c'$sSiSHsWP'))).metadata
		dsc_ownership(code, entry, original, owned_type, true)
		println('NATIVE-DICTIONARY-STORAGE-COPY: borrowed original x0/metatype x20, owned x0 and preserved x20/x21, seven target layouts, zero-size and 256-byte alignment, exact scale/age/seed and empty occupancy, protected source tail, caller-owned snapshot lifecycle')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/usr/lib/swift/libswiftCore.dylib'
		symbol := '_$ss18_DictionaryStorageC4copy8originalAByxq_Gs05__RawaB0C_tFZ'
		entry := runtime_symbol(library, symbol) or { panic(err) }
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', symbol) == none
		int_type := swift_integer_metadata()
		string_type := swift_string_metadata()
		source_type := dsc_class(code + u64(page) * 2 + 1536, code, guard, guard, guard)
		C.memset(voidptr(original), 0xa5, 64)
		unsafe {
			*(&u64(original)) = source_type
			*(&u64(original + 8)) = 3
			*(&u64(original + 40)) = 0x123456789abcdef0
		}
		C.ios_objc_initialize_lock()
		ios_runtime.swift_heap[original] = SwiftHeapStorage{ metadata: source_type, size: 64, mask: 7 }
		C.ios_objc_initialize_unlock()
		for i, pair in [[string_type, int_type]!, [string_type, string_type]!, [string_type,
			(swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(page) + 16]!,
			[(swift_bool_metadata_arena_checked() or { panic(err) }) + u64(page) + 16,
				swift_void_full_metadata() + 8]!, [int_type, wide]!, [wide_key, wide]!,
			[string_type, swift_any_full_metadata() + 8]!]! {
			metadata := dsc_class(code + u64(page) + u64(i * 512), code, pair[0], pair[1], guard)
			dsc_profile(code, entry, original, metadata, pair[0], pair[1], false)
			if i == 0 {
				mut workers := []thread{}
				for _ in 0 .. 8 { workers << spawn dsc_worker(entry, original, metadata) }
				workers.wait()
			}
		}
		owned_type := dsc_class(code + u64(page) * 2 + 1024, code, int_type, swift_objc_metadata(ios_runtime.names['NSString']), guard)
		dsc_ownership(code, entry, original, owned_type, false)
		for bad in [u64(0), 1, guard, swift_array_empty()]! {
			if _ := swift_dictionary_storage_copy_checked(bad, guard) {
				assert false
			}
		}
		metadata := code + u64(page) + 24
		before := ios_runtime.swift_heap.len
		for scale in [u8(15), 63, 255]! {
			unsafe { *(&u8(original + 32)) = scale }
			if _ := swift_dictionary_storage_copy_checked(original, guard) {
				assert false
			}
		}
		unsafe { *(&u8(original + 32)) = 0 }
		for bad in [u64(0), 1, ~u64(0), int_type]! {
			if _ := swift_dictionary_storage_copy_checked(original, bad) {
				assert false
			}
		}
		// Oversized/overflowing target tails must fail before registering an owner.
		unsafe { *(&u8(original + 32)) = 14 }
		wide_witness := read64(wide - 8)
		for stride in [u64(2048), ~u64(63), 17]! {
			unsafe { *(&u64(wide_witness + 72)) = stride }
			if _ := swift_dictionary_storage_copy_checked(original, code + u64(page) + 4 * 512 + 24) {
				assert false
			}
		}
		unsafe {
			*(&u64(wide_witness + 72)) = 64
			*(&u8(original + 32)) = 0
		}
		mut state := ios_runtime.swift_heap[original] or { panic('missing borrowed source') }
		state.deiniting = true
		ios_runtime.swift_heap[original] = state
		if _ := swift_dictionary_storage_copy_checked(original, guard) {
			assert false
		}
		state.deiniting = false
		ios_runtime.swift_heap[original] = state
		assert ios_runtime.swift_heap.len == before
		empty := swift_foundation_arena() + u64(page) + 3328
		owner := dsc_call(code, entry, empty, metadata, guard)
		assert owner != empty && read64(owner + 24) == 0
		object := swift_foundation_dictionary_bridge(owner, string_type, int_type, guard)
		assert obj_header(object).keys.len == 0
		objc_release(object)
		swift_release(owner)
		ios_runtime.swift_concurrency_retired = true
		assert runtime_symbol(library, symbol) == none
		if _ := swift_dictionary_storage_copy_checked(original, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		C.ios_objc_initialize_lock()
		ios_runtime.swift_heap.delete(original)
		C.ios_objc_initialize_unlock()
		arena := ios_runtime.swift_dictionary_metadata_arena
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.empty_dictionary != 0
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert runtime_symbol(library, symbol) == none && ios_runtime.swift_dictionary_metadata_arena == 0
		assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
	}
	assert C.munmap(voidptr(code), page * 4) == 0
	println('IOS-DICTIONARY-STORAGE-COPY: native empty allocation contract, independent aligned tails, opaque source entries and unused witnesses, caller-owned snapshot lifecycle and reentrant destruction, guarded invalid/lifetime rejection, eight concurrent workers and two drained/unmapped lifetimes')
}
