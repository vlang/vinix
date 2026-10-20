// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type DmAccess = fn (u64, u64, u64, u64) SwiftAssociatedMetadata
type DmInstantiate = fn (u64, u64, u64) u64
type DmNominal = fn (u64) SwiftAssociatedMetadata
type DmSend = fn (u64, u64) u64
type DmCopy = fn (u64, u64, u64) u64
type DmDestroy = fn (u64, u64)
type DmGet = fn (u64, u32, u64) u32
type DmStore = fn (u64, u32, u32, u64)
type DmKeep = fn (u64) u64
type DmDrop = fn (u64)
type DmAllocate = fn (i64, u64) SwiftArrayAllocation

struct DmApi {
	native       bool
	table        u64
	metadata     u64
	descriptor   u64
	entry        u64
	integer      u64
	string_type  u64
	any_type     u64
	void_type    u64
	date_type    u64
	string_hash  u64
	integer_hash u64
	empty        u64
	access       DmAccess   @[required]
	allocate     DmAllocate @[required]
	native_keep  DmKeep     @[required]
	native_drop  DmDrop     @[required]
}

fn dm_symbol(native bool, library string, name string) u64 {
	if native {
		handle := C.dlopen(unsafe { &char(library.str) }, 2)
		assert handle != unsafe { nil }
		address := u64(C.dlsym(handle, unsafe { &char(name.str + 1) }))
		assert address != 0
		return address
	}
	return runtime_symbol(library, name) or { panic(err) }
}

fn dm_api(native bool) DmApi {
	core := '/usr/lib/swift/libswiftCore.dylib'
	foundation := '/System/Library/Frameworks/Foundation.framework/Foundation'
	entry := dm_symbol(native, core, '_$sSDMa')
	access := unsafe { DmAccess(voidptr(entry)) }
	key := dm_symbol(native, core, '_$sSSN')
	integer := dm_symbol(native, core, '_$sSiN')
	hashable := if native { dm_symbol(true, core, '_$sSSSHsWP') } else { dm_hashable_fixture() }
	response := access(0, key, integer, hashable)
	assert response.state == 0
	date_entry := dm_symbol(native, foundation, '_$s10Foundation4DateVMa')
	date := unsafe { DmNominal(voidptr(date_entry))(0) }
	assert date.state == 0
	return DmApi{ native: native, metadata: response.metadata, table: read64(response.metadata - 8) & 0x0000ffffffffffff, descriptor: read64(response.metadata + 8), entry: entry, integer: integer, string_type: key, any_type: dm_symbol(native, core, '_$sypN') + 8, void_type: dm_symbol(native, core, '_$sytN') + 8, date_type: date.metadata, string_hash: hashable, integer_hash: dm_symbol(native, core, '_$sSiSHsWP'), empty: dm_symbol(native, core, '__swiftEmptyDictionarySingleton'), access: access, allocate: unsafe { DmAllocate(voidptr(dm_symbol(native, core, '_$ss27_allocateUninitializedArrayySayxG_BptBwlF'))) }, native_keep: unsafe { DmKeep(voidptr(dm_symbol(native, core, '_swift_retain'))) }, native_drop: unsafe { DmDrop(voidptr(dm_symbol(native, core, '_swift_release'))) } }
}

// The image supplies Key: Hashable; metadata construction only borrows its
// identity. String hashing is a separate unsupported export in this runtime.
// These caller-owned test witnesses trap if an accessor tries to invoke them.
fn dm_unexpected_hashable(_a u64, _b u64, _c u64, _d u64) u64 {
	panic('Dictionary metadata must not invoke borrowed Hashable witnesses')
}

fn dm_hashable_fixture() u64 {
	base := ios_runtime.swift_dictionary_metadata_arena + u64(C.getpagesize()) * 2 + 256
	for i in 0 .. 5 {
		unsafe { *(&u64(voidptr(base + u64(i * 8)))) = u64(voidptr(dm_unexpected_hashable)) }
	}
	return base
}

fn (api DmApi) retain(word u64) u64 {
	if api.native {
		$if macos {
			if word & 0x4000000000000000 != 0 {
				C.CFRetain(voidptr(word & swift_address_mask))
			} else {
				api.native_keep(word)
			}
		}
	} else {
		swift_bridge_retain(word)
	}
	return word
}

fn (api DmApi) release(word u64) {
	if api.native {
		$if macos {
			if word & 0x4000000000000000 != 0 {
				C.CFRelease(voidptr(word & swift_address_mask))
			} else {
				api.native_drop(word)
			}
		}
	} else {
		swift_bridge_release(word)
	}
}

fn dm_send(owner u64, selector &char) u64 {
	return unsafe { DmSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(owner, u64(C.sel_registerName(selector))) }
}

fn (api DmApi) owner(native_heap bool) u64 {
	if native_heap {
		value := api.allocate(1, api.integer)
		unsafe { *(&u64(value.bytes)) = 42 }
		return value.owner
	}
	$if macos {
		if api.native {
			return dm_send(u64(C.objc_getClass(c'NSMutableDictionary')), c'new') | u64(0x4000000000000000)
		}
	}
	return objc_allocate(ios_runtime.names['NSMutableDictionary']) | u64(0x4000000000000000)
}

fn (api DmApi) refs(owner u64, native_heap bool) u64 {
	raw := owner & swift_address_mask
	if native_heap { return (read64(raw + 8) >> 33) + 1 }
	$if macos {
		if api.native { return dm_send(raw, c'retainCount') }
	}
	return u64(obj_header(raw).refs)
}

fn dm_copy(table u64, slot int) DmCopy {
	return unsafe { DmCopy(voidptr(read64(table + u64(slot * 8)) & 0x0000ffffffffffff)) }
}

fn dm_destroy(table u64) DmDestroy {
	return unsafe { DmDestroy(voidptr(read64(table + 8) & 0x0000ffffffffffff)) }
}

fn dm_ownership(api DmApi, native_heap bool) {
	owner := api.owner(native_heap)
	assert api.refs(owner, native_heap) == 1
	mut source := [u64(0x1234), owner, 0x5678]!
	mut destination := [u64(0x1234), 0, 0x5678]!
	src := u64(unsafe { &source[1] })
	dst := u64(unsafe { &destination[1] })
	for slot in [0, 2]! {
		initialize := dm_copy(api.table, slot)
		assert initialize(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner, native_heap) == 2, 'native=${api.native} native_heap=${native_heap} slot=${slot} owner=${owner.hex()} destination=${destination[1].hex()} refs=${api.refs(owner, native_heap)}'
		destroy := dm_destroy(api.table)
		destroy(dst, 0)
		assert destination[1] == owner && api.refs(owner, native_heap) == 1
	}
	assign_copy := dm_copy(api.table, 3)
	assert assign_copy(src, src, 0) == src && api.refs(owner, native_heap) == 1
	for slot in [3, 5]! {
		destination[1] = api.owner(!native_heap) // Replacement crosses ARC domains.
		if slot == 5 { api.retain(owner) }
		assign := dm_copy(api.table, slot)
		assert assign(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner, native_heap) == 2
		api.release(destination[1])
		assert api.refs(owner, native_heap) == 1
	}
	take := dm_copy(api.table, 4)
	assert take(dst, src, 0) == dst
	assert destination[1] == owner && source[1] == owner && api.refs(owner, native_heap) == 1
	// A take of aliased storage consumes the distinct source ownership.
	api.retain(owner)
	assign_take := dm_copy(api.table, 5)
	assert assign_take(dst, dst, 0) == dst && api.refs(owner, native_heap) == 1
	assert source[0] == 0x1234 && source[2] == 0x5678 && destination[0] == 0x1234 && destination[2] == 0x5678
	api.release(destination[1])
}

fn dm_immortal(api DmApi) {
	for owner in [u64(0), api.empty]! {
		mut source := owner
		mut destination := u64(0)
		for slot in [0, 2, 3, 4, 5]! {
			operation := dm_copy(api.table, slot)
			assert operation(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
			assert destination == owner && source == owner
		}
		destroy := dm_destroy(api.table)
		destroy(u64(unsafe { &destination }), 0)
	}
}

fn dm_enums(api DmApi) {
	get := unsafe { DmGet(voidptr(read64(api.table + 48) & 0x0000ffffffffffff)) }
	store := unsafe { DmStore(voidptr(read64(api.table + 56) & 0x0000ffffffffffff)) }
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region) }, page, C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(region + u64(page * 2)) }, page, C.PROT_NONE) == 0
	for count in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
		length := if count > 0x7fffffff { 9 } else { 8 }
		for tag in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			mut bytes := [24]u8{}
			for i in 0 .. bytes.len { bytes[i] = 0xa5 }
			address := u64(unsafe { &bytes[7] })
			store(address, tag, count, 0)
			wanted := if tag == 0 {
				u64(0xa5a5a5a5a5a5a5a5)
			} else if tag <= 0x7fffffff {
				u64(tag - 1)
			} else {
				u64(tag - 0x80000000)
			}
			mut actual := u64(0)
			for i in 0 .. 8 { actual |= u64(bytes[7 + i]) << u32(i * 8) }
			assert actual == wanted && get(address, count, 0) == tag
			if length == 9 {
				assert bytes[15] == if tag > 0x7fffffff { u8(1) } else { u8(0) }
			}
			for i in 0 .. bytes.len {
				if i < 7 || i >= 7 + length {
					assert bytes[i] == 0xa5
				}
			}
			boundary := region + u64(page * 2) - u64(length)
			C.memset(unsafe { voidptr(boundary) }, 0xa5, usize(length))
			store(boundary, tag, count, 0)
			assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ) == 0
			assert get(boundary, count, 0) == tag
			assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
		}
		for bits in [u64(0), 1, 0xfff, 0x1000, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000,
			0x8000000000000000]! {
			mut value := [bits, u64(0)]!
			assert get(u64(unsafe { &value[0] }), count, 0) == if bits >> 32 == 0 {
				u32(bits) + 1
			} else {
				u32(0)
			}
		}
	}
	assert C.munmap(unsafe { voidptr(region) }, page * 3) == 0
}

struct DmReentry {
	destination u64
	expected    u64
	table       u64
mut:
	calls int
}

fn dm_reader(state &DmReentry) {
	assert read64(state.destination) == state.expected
	mut temporary := u64(0)
	initialize := dm_copy(state.table, 2)
	assert initialize(u64(unsafe { &temporary }), state.destination, 0) == u64(unsafe { &temporary })
	assert temporary == state.expected && dm_resolve() != 0
	destroy := dm_destroy(state.table)
	destroy(u64(unsafe { &temporary }), 0)
}

fn dm_reentry_dealloc(owner u64, _selector &char) {
	mut state := unsafe { &DmReentry(obj_header(owner).tag) }
	assert state.calls == 0
	worker := spawn dm_reader(state)
	worker.wait()
	state.calls++
}

fn dm_reentry(api DmApi) {
	cls := objc_allocate_class(ios_runtime.names['NSMutableDictionary'], c'VinixDmValueReentry', 0)
	assert cls != 0
	objc_register_class(cls)
	objc_replace_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(dm_reentry_dealloc) }), c'v16@0:8')
	for native_heap in [false, true]! {
		for slot in [3, 5]! {
			mut source := api.owner(native_heap)
			mut destination := objc_allocate(cls) | u64(0x4000000000000000)
			state := unsafe { &DmReentry(C.__builtin_alloca(sizeof(DmReentry))) }
			unsafe { *state = DmReentry{ destination: u64(&destination), expected: source, table: api.table } }
			mut header := obj_header(destination & swift_address_mask)
			header.tag = i64(state)
			if slot == 5 { api.retain(source) }
			assign := dm_copy(api.table, slot)
			assert assign(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
			assert state.calls == 1 && destination == source && api.refs(source, native_heap) == 2
			api.release(destination)
			api.release(source)
		}
	}
}

fn dm_worker(api DmApi, owner u64) {
	initialize := dm_copy(api.table, 0)
	destroy := dm_destroy(api.table)
	for _ in 0 .. 1000 {
		mut source := owner
		mut destination := u64(0)
		assert initialize(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
		assert destination == owner
		destroy(u64(unsafe { &destination }), 0)
	}
}

fn dm_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSDMa') or { panic(err) }
}

fn dm_read_only(address u64) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + 88 <= start + size && info[0] == C.PROT_READ
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert address + 88 <= end && fields[1] == 'r--p'
				found = true
				break
			}
		}
		assert found
	}
}

fn dm_suite(api DmApi) {
	assert read64(api.table + 64) == 8 && read64(api.table + 72) == 8
	assert read32(api.table + 80) == 0x10007 && read32(api.table + 84) == 0x7fffffff
	dm_immortal(api)
	dm_enums(api)
	for native_heap in [false, true]! {
		for _ in 0 .. 100 { dm_ownership(api, native_heap) }
		owner := api.owner(native_heap)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn dm_worker(api, owner) }
		workers.wait()
		assert api.refs(owner, native_heap) == 1
		api.release(owner)
	}
	if !api.native {
		dm_reentry(api)
		dm_read_only(api.table)
	}
}

fn dm_relative(field u64) u64 { return u64(i64(field) + i64(i32(read32(field)))) }

fn dm_layout(api DmApi, metadata u64, key u64, value u64, hashable u64) {
	assert read64(metadata) == 0x200 && read64(metadata + 8) == api.descriptor
	assert read64(metadata + 16) == key && read64(metadata + 24) == value && read64(metadata + 32) == hashable && read64(metadata + 40) == 0
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8 && read64(witness + 80) == 0x7fffffff00010007
	if !api.native {
		assert witness == api.table
	}
}

fn dm_descriptor(api DmApi) {
	d := api.descriptor
	assert read32(d) & 0xffff == 0xd1 && read32(d + 20) == 1 && read32(d + 24) == 5
	assert unsafe { (&char(voidptr(dm_relative(d + 8)))).vstring() } == 'Dictionary'
	parent := dm_relative(d + 4)
	assert read32(parent) & 31 == 0 && unsafe { (&char(voidptr(dm_relative(parent + 8)))).vstring() } == 'Swift'
	assert read32(d + 36) == 0x10002 && read32(d + 40) == 3 && read32(d + 44) & 0xffff == 0x8080 && read32(d + 48) == 0x80
	assert unsafe { (&char(voidptr(dm_relative(d + 52)))).vstring() } == 'x'
	protocol := dm_relative(d + 56)
	assert unsafe { (&char(voidptr(dm_relative(protocol + 8)))).vstring() } == 'Hashable'
	if !api.native {
		assert read32(d + 16) == 0
		cache := dm_relative(d + 28)
		for i in 0 .. 16 {
			assert read64(cache + u64(i * 8)) == 0
		}
		pattern := dm_relative(d + 32)
		assert read32(pattern + 4) == 0 && read32(pattern + 8) == 0x40000000 && dm_relative(pattern + 12) == api.table
		instantiate := unsafe { DmInstantiate(voidptr(dm_relative(pattern))) }
		mut args := [api.string_type, api.integer, api.string_hash]!
		assert instantiate(d, u64(unsafe { &args[0] }), pattern) == api.metadata
	}
}

fn dm_matrix(api DmApi) {
	from_descriptor := unsafe { DmAccess(voidptr(dm_relative(api.descriptor + 12))) }
	mut identities := []u64{}
	for key in [api.string_type, api.integer]! {
		hashable := if key == api.string_type { api.string_hash } else { api.integer_hash }
		for value in [api.string_type, api.integer, api.any_type, api.void_type, api.date_type,
			api.metadata]! {
			response := api.access(0, key, value, hashable)
			assert response.state == 0 && response.metadata !in identities
			identities << response.metadata
			dm_layout(api, response.metadata, key, value, hashable)
			for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
				for access in [api.access, from_descriptor]! {
					actual := access(request, key, value, hashable)
					assert actual.metadata == response.metadata && actual.state == 0
				}
			}
		}
	}
	unsafe { identities.free() }
	dm_descriptor(api)
	if !api.native {
		dm_read_only(api.metadata)
		dm_read_only(api.descriptor)
	}
}

type DmProbe = fn (&u64, u64, &u64)

fn dm_raw(api DmApi, code u64, guard u64) {
	probe := unsafe { DmProbe(voidptr(code)) }
	for entry in [api.entry, dm_relative(api.descriptor + 12)]! {
		input := [u64(0x13f), api.string_type, api.integer, api.string_hash, guard, guard, guard,
			guard, guard, guard, guard, guard, guard]!
		mut output := [6]u64{}
		probe(unsafe { &input[0] }, entry, unsafe { &output[0] })
		assert output[0] == api.metadata && output[1] == 0 && output[4] == guard && output[5] == guard
	}
}

fn dm_metadata_worker(api DmApi) u64 {
	mut answer := u64(0)
	for _ in 0 .. 64 {
		response := api.access(0, api.integer, api.date_type, api.integer_hash)
		assert response.state == 0 && (answer == 0 || answer == response.metadata)
		answer = response.metadata
	}
	return answer
}

fn dm_guarded(api DmApi, guard u64) {
	before := ios_runtime.swift_dictionary_metadata.len
	for slot in 0 .. 3 {
		for bad in [u64(0), 1, guard + 1]! {
			mut args := [api.string_type, api.integer, api.string_hash]!
			args[slot] = bad
			if _ := swift_dictionary_metadata_checked(0, args[0], args[1], args[2]) {
				assert false
			}
			assert ios_runtime.swift_dictionary_metadata.len == before
		}
	}
	first := swift_dictionary_metadata_checked(0, guard, guard + 8, guard + 16) or { panic(err) }
	second := swift_dictionary_metadata_checked(0, guard, guard + 8, guard + 24) or { panic(err) }
	assert first.state == 0 && second.state == 0 && first.metadata != second.metadata
	dm_layout(api, first.metadata, guard, guard + 8, guard + 16)
	mut arguments := [guard, guard + 8, guard + 16]!
	pattern := dm_relative(api.descriptor + 32)
	instantiate := unsafe { DmInstantiate(voidptr(dm_relative(pattern))) }
	assert instantiate(api.descriptor, u64(unsafe { &arguments[0] }), pattern) == first.metadata
}

fn test_swift_dictionary_metadata() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f1, 0xaa0103f0, 0xaa0203f3,
		0xd10043ff, 0xa9400620, 0xa9410e22, 0xa9421624, 0xa9431e26, 0xa9442a29, 0xa9002be9, 0xf9402a28,
		0xf9402e34, 0xf9403235, 0xd63f0200, 0xa9000660, 0xa9010e62, 0xa9025674, 0x910043ff, 0xa9425bf5,
		0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
	guard := code + u64(page)
	$if macos {
		native := dm_api(true)
		dm_matrix(native)
		dm_suite(native)
		dm_raw(native, code, guard)
		println('NATIVE-DICTIONARY-METADATA: twelve canonical Key/Value combinations, three generic arguments, descriptor Hashable requirement, six request states, x0/x1 ARM64 response, one-word native/Cocoa ownership and guarded enums')
	}
	for _ in 0 .. 2 {
		objc_start()
		if _ := swift_dictionary_metadata_checked(0, 0, guard, guard) {
			assert false
		}
		assert ios_runtime.swift_dictionary_metadata_arena == 0 && ios_runtime.swift_dictionary_metadata.len == 0
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn dm_resolve() }
		entries := publishers.wait()
		api := dm_api(false)
		for entry in entries {
			assert entry == api.entry
		}
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn dm_metadata_worker(api) }
		types := workers.wait()
		for metadata in types {
			assert metadata == types[0]
		}
		dm_matrix(api)
		dm_suite(api)
		dm_raw(api, code, guard)
		dm_guarded(api, guard)
		for name in ['_$sSDMn', '$sSDMa', '_$sSDMaExtra']! {
			assert swift_core_symbol(name) == none
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSDMa') == none
		}
		assert ios_runtime.live == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_dictionary_metadata_arena
		bases := ios_runtime.swift_dictionary_metadata.keys()
		objc_stop()
		assert ios_runtime.swift_dictionary_metadata_retired && ios_runtime.swift_dictionary_metadata_arena == 0 && ios_runtime.swift_dictionary_metadata.len == 0
		if _ := swift_dictionary_metadata_checked(0, guard, guard, guard) {
			assert false
		}
		for base in bases {
			$if macos {
				assert C.mprotect(voidptr(base), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(base), page, &resident) == -1
			}
		}
		for offset in 0 .. 3 {
			$if macos {
				assert C.mprotect(voidptr(arena + u64(offset) * u64(page)), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(arena + u64(offset) * u64(page)), page, &resident) == -1
			}
		}
		unsafe {
			bases.free()
			workers.free()
			publishers.free()
			types.free()
			entries.free()
		}
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-DICTIONARY-METADATA: canonical exact Key/Value/Hashable specializations, complete x0/x1 responses, native generic descriptor/pattern, sealed publication, guarded opaque inputs and invalid/retired rejection, native/Cocoa ownership and reentry, eight publishers/workers, and two drained/unmapped lifetimes')
}
