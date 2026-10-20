// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.objc_disposeClassPair(voidptr)
fn C.class_createInstance(voidptr, usize) voidptr
fn C.sel_registerName(&char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type OaProbe = fn (u64, u64, u64, &u64)
type OaUnary = fn (u64) u64
type OaDrop = fn (u64)
type OaCopy = fn (u64, u64, u64) u64
type OaDestroy = fn (u64, u64)
type OaCount = fn (u64, u64) u64

const oa_export = '_$ss018_bridgeAnyObjectToB0yypyXlSgF'

struct OaApi {
	native bool
	code   u64
	entry  u64
	any    u64
	base   u64
	leaf   u64
	get    OaUnary = swift_object_type
	drop   OaDrop  = swift_unknown_release
	send   u64
}

fn oa_symbol(native bool, name string) u64 {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			result := u64(C.dlsym(core, name[1..].str))
			assert result != 0, name
			return result
		}
	}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
}

fn oa_api(native bool, code u64) OaApi {
	$if macos {
		if native {
			objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
			base := u64(C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixNativeObjectAnyBase', 0))
			assert base != 0
			C.objc_registerClassPair(voidptr(base))
			leaf := u64(C.objc_allocateClassPair(voidptr(base), c'VinixNativeObjectAnyLeaf', 0))
			assert leaf != 0
			C.objc_registerClassPair(voidptr(leaf))
			return OaApi{
				native: true
				code:   code
				entry:  oa_symbol(true, oa_export)
				any:    oa_symbol(true, '_$sypN') + 8
				base:   base
				leaf:   leaf
				get:    unsafe { OaUnary(voidptr(oa_symbol(true, '_swift_getObjectType'))) }
				drop:   unsafe { OaDrop(C.dlsym(objc, c'objc_release')) }
				send:   u64(C.dlsym(objc, c'objc_msgSend'))
			}
		}
	}
	base := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixObjectAnyBase', 0)
	objc_register_class(base)
	leaf := objc_allocate_class(base, c'VinixObjectAnyLeaf', 0)
	objc_register_class(leaf)
	return OaApi{ code: code, entry: oa_symbol(false, oa_export), any: swift_any_full_metadata() + 8, base: base, leaf: leaf }
}

fn oa_object(api OaApi, cls u64) u64 {
	$if macos {
		if api.native { return u64(C.class_createInstance(voidptr(cls), 0)) }
	}
	return objc_allocate(cls)
}

fn oa_refs(api OaApi, owner u64) u64 {
	$if macos {
		if api.native {
			return unsafe { OaCount(voidptr(api.send))(owner, u64(C.sel_registerName(c'retainCount'))) }
		}
	}
	return u64(obj_header(owner).refs)
}

fn oa_invoke(api OaApi, owner u64, destination u64) {
	mut registers := [2]u64{}
	unsafe { OaProbe(voidptr(api.code))(owner, api.entry, destination, &registers[0]) }
	assert registers == [u64(0x5020), 0x5021]!
}

fn oa_witness(api OaApi, slot int) u64 {
	return read64((read64(api.any - 8) & 0x0000ffffffffffff) + u64(slot * 8)) & 0x0000ffffffffffff
}

fn oa_copy(api OaApi, slot int, destination u64, source u64) {
	assert unsafe { OaCopy(voidptr(oa_witness(api, slot)))(destination, source, api.any) } == destination
}

fn oa_destroy(api OaApi, value u64) {
	unsafe { OaDestroy(voidptr(oa_witness(api, 1)))(value, api.any) }
}

fn oa_layout(api OaApi, value u64, owner u64) u64 {
	metadata := read64(value + 24)
	assert read64(value) == owner && metadata != 0
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8
	if owner == 0 {
		assert read64(metadata) == 0x202
		assert read32(witness + 80) == 0x210007 && read32(witness + 84) == 0x7ffffffe
		wrapped := read64(metadata + 16)
		assert read64(wrapped) == 0x303 && read64(wrapped + 8) == 0
		wrapped_witness := read64(wrapped - 8) & 0x0000ffffffffffff
		assert read64(wrapped_witness + 64) == 8 && read32(wrapped_witness + 84) == 0x7fffffff
		if !api.native {
			assert swift_optional_access(0, wrapped).metadata == metadata
		}
	} else {
		assert metadata == api.get(owner) && read32(witness + 80) == 0x10007
	}
	return metadata
}

fn oa_cases(api OaApi) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 4) == 0 }
	for offset in [usize(0), page * 2]! {
		assert C.mprotect(voidptr(span + u64(offset)), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	mut nil_metadata := u64(0)
	for cls in [u64(0), api.base, api.leaf]! {
		for at_end in [false, true]! {
			owner := if cls == 0 { u64(0) } else { oa_object(api, cls) }
			source := span + if at_end { u64(page) - 32 } else { u64(8) }
			destination := span + u64(page * 2) + if at_end { u64(page) - 32 } else { u64(8) }
			C.memset(voidptr(source), 0x67, 32)
			before := if owner == 0 { u64(0) } else { oa_refs(api, owner) }
			oa_invoke(api, owner, source)
			metadata := oa_layout(api, source, owner)
			assert read64(source + 8) == 0x6767676767676767 && read64(source + 16) == 0x6767676767676767
			if owner != 0 {
				assert oa_refs(api, owner) == before + 1
			} else {
				if nil_metadata != 0 {
					assert metadata == nil_metadata
				}
				nil_metadata = metadata
			}
			assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
			for slot in [2, 3, 4, 5]! {
				C.memset(voidptr(destination), 0x5a, 32)
				if slot in [3, 5]! { oa_invoke(api, 0, destination) }
				oa_copy(api, slot, destination, source)
				assert oa_layout(api, destination, owner) == metadata
				assert read64(destination + 8) == if slot == 4 {
					u64(0x6767676767676767)
				} else {
					u64(0x5a5a5a5a5a5a5a5a)
				}
				assert read64(destination + 16) == if slot == 4 {
					u64(0x6767676767676767)
				} else {
					u64(0x5a5a5a5a5a5a5a5a)
				}
				if owner != 0 {
					assert oa_refs(api, owner) == before + if slot in [4, 5]! {
						u64(1)
					} else {
						u64(2)
					}
				}
				oa_destroy(api, destination)
				if slot in [4, 5]! {
					// Taking consumed the source. Recreate its independent Any owner
					// after restoring the protected input page to writable storage.
					assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
					oa_invoke(api, owner, source)
					assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
				}
			}
			assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
			oa_destroy(api, source)
			if owner != 0 {
				assert oa_refs(api, owner) == before
				api.drop(owner)
			}
		}
	}
}

fn oa_assignments(api OaApi) {
	for taking in [false, true]! {
		for old_nil in [false, true]! {
			for next_nil in [false, true]! {
				owner := oa_object(api, api.leaf)
				mut source := [u64(0x67), 0x67, 0x67, 0x67]!
				mut destination := [u64(0x5a), 0x5a, 0x5a, 0x5a]!
				src := u64(unsafe { &source[0] })
				dst := u64(unsafe { &destination[0] })
				oa_invoke(api, if next_nil { u64(0) } else { owner }, src)
				oa_invoke(api, if old_nil { u64(0) } else { owner }, dst)
				oa_copy(api, if taking { 5 } else { 3 }, dst, src)
				assert oa_layout(api, dst, if next_nil { u64(0) } else { owner }) == source[3]
				assert oa_refs(api, owner) == 1 + if next_nil {
					u64(0)
				} else if taking {
					u64(1)
				} else {
					u64(2)
				}
				oa_destroy(api, dst)
				if !taking { oa_destroy(api, src) }
				assert oa_refs(api, owner) == 1
				api.drop(owner)
			}
		}
	}
}

fn oa_publisher() u64 { return oa_symbol(false, oa_export) }

fn oa_worker(api OaApi, owner u64) u64 {
	mut metadata := u64(0)
	for _ in 0 .. 64 {
		mut value := [4]u64{}
		oa_invoke(api, owner, u64(unsafe { &value[0] }))
		if metadata != 0 {
			assert value[3] == metadata
		}
		metadata = value[3]
		oa_destroy(api, u64(unsafe { &value[0] }))
	}
	return metadata
}

fn oa_reject() {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', oa_export) == none
	mut output := [u64(0x67), 0x67, 0x67, 0x67]!
	if _ := swift_object_any_checked(u64(unsafe { &output[0] }), 0) {
		assert false
	}
	assert output == [u64(0x67), 0x67, 0x67, 0x67]!
}

fn oa_bad(api OaApi) {
	mut output := [u64(0x67), 0x67, 0x67, 0x67]!
	for owner in [u64(8), 0x8000000000000000, swift_array_empty()]! {
		if _ := swift_object_any_checked(u64(unsafe { &output[0] }), owner) {
			assert false
		}
		assert output == [u64(0x67), 0x67, 0x67, 0x67]!
	}
	owner := oa_object(api, api.leaf)
	for destination in [u64(0), 1, ~u64(0) - 7]! {
		if _ := swift_object_any_checked(destination, owner) {
			assert false
		}
		assert oa_refs(api, owner) == 1
	}
	api.drop(owner)
	if _ := swift_object_any_checked(u64(unsafe { &output[0] }), owner) {
		assert false
	}
	assert output == [u64(0x67), 0x67, 0x67, 0x67]!
}

fn oa_formal(owner u64, _selector &char) u64 {
	worker := spawn oa_publisher()
	assert worker.wait() != 0
	return u64(obj_header(owner).tag)
}

__global oa_heap_destroys u64

fn oa_heap_destroy(owner u64) {
	assert read64(owner + 16) == 0xcafe && read64(owner + 8) == 0x100000003
	mut output := [u64(0x67), 0x67, 0x67, 0x67]!
	if _ := swift_object_any_checked(u64(unsafe { &output[0] }), owner) {
		assert false
	}
	assert output == [u64(0x67), 0x67, 0x67, 0x67]!
	oa_heap_destroys++
	swift_heap_deallocate(owner, 32, 15)
}

fn oa_heap_and_constant(api OaApi, fixture u64) {
	metadata := fixture + 16
	unsafe { *(&u64(metadata - 8)) = swift_unknown_value_witnesses() }
	owner := swift_heap_allocate(metadata, 32, 15)
	unsafe { *(&u64(owner + 16)) = 0xcafe }
	oa_heap_destroys = 0
	mut value := [4]u64{}
	oa_invoke(api, owner, u64(unsafe { &value[0] }))
	assert value[0] == owner && value[3] == metadata && read64(owner + 8) == 0x200000003
	swift_release(owner)
	mut copy := [4]u64{}
	oa_copy(api, 2, u64(unsafe { &copy[0] }), u64(unsafe { &value[0] }))
	assert read64(owner + 8) == 0x200000003
	oa_destroy(api, u64(unsafe { &value[0] }))
	assert read64(owner + 8) == 3
	oa_destroy(api, u64(unsafe { &copy[0] }))
	assert oa_heap_destroys == 1
	mut constant := [ios_runtime.names['NSString'], u64(0), 0, 0]!
	address := u64(unsafe { &constant[0] })
	ios_runtime.constants[address] = true
	oa_invoke(api, address, u64(unsafe { &value[0] }))
	assert value[0] == address && value[3] == swift_objc_metadata(constant[0])
	oa_destroy(api, u64(unsafe { &value[0] }))
	ios_runtime.constants.delete(address)
}

fn oa_reentrant(api OaApi) {
	objc_replace_method(api.base, objc_selector(c'class'), u64(unsafe { voidptr(oa_formal) }), c'#16@0:8')
	owner := oa_object(api, api.base)
	mut header := obj_header(owner)
	header.tag = i64(ios_runtime.names['NSObject'])
	mut value := [4]u64{}
	oa_invoke(api, owner, u64(unsafe { &value[0] }))
	assert value[0] == owner && value[3] == swift_objc_metadata(ios_runtime.names['NSObject']) && header.refs == 2
	oa_destroy(api, u64(unsafe { &value[0] }))
	api.drop(owner)
}

fn test_swift_object_any() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(voidptr(code), page) == 0 }
	for i, op in [u32(0xa9bc7bfd), 0xa90157f4, 0xa9025bf3, 0xaa0303f3, 0xaa0103f0, 0xaa0203e8,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005674, 0xa9425bf3, 0xa94157f4, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200, 0xd503201f]! {
		write32(code + 64 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 80)) = u64(voidptr(oa_heap_destroy)) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 88))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		api := oa_api(true, code)
		oa_cases(api)
		oa_assignments(api)
		C.objc_disposeClassPair(voidptr(api.leaf))
		C.objc_disposeClassPair(voidptr(api.base))
		println('NATIVE-OBJECT-ANY: borrowed optional object to indirect Any, dynamic metadata/retained objects and nil Optional<AnyObject> payload, untouched padding, protected Any copy/take/assign/destroy ownership and x20/x21')
	}
	oa_reject()
	fixture := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert fixture != u64(-1)
	defer { assert C.munmap(voidptr(fixture), page) == 0 }
	metadata := fixture + 16
	unsafe {
		*(&u64(fixture)) = code + 64
		*(&u64(metadata + 32)) = 2
		*(&u64(metadata + 64)) = fixture + 128
	}
	write32(metadata + 40, 2)
	write32(metadata + 48, 32)
	write32(metadata + 52, 15)
	write32(fixture + 128, 0x10)
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn oa_publisher() }
		identities := publishers.wait()
		for identity in identities {
			assert identity == identities[0]
		}
		unsafe {
			identities.free()
			publishers.free()
		}
		api := oa_api(false, code)
		oa_cases(api)
		oa_assignments(api)
		oa_bad(api)
		oa_heap_and_constant(api, fixture)
		owner := oa_object(api, api.leaf)
		for object in [u64(0), owner]! {
			mut workers := []thread u64{}
			for _ in 0 .. 8 { workers << spawn oa_worker(api, object) }
			values := workers.wait()
			for value in values {
				assert value == values[0]
			}
			unsafe {
				values.free()
				workers.free()
			}
		}
		assert oa_refs(api, owner) == 1
		api.drop(owner)
		oa_reentrant(api)
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', oa_export[1..]) == none
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', oa_export) == none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', oa_export) == none
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_object_any_arena
		oa_protection(arena, 24, true)
		oa_protection(arena + u64(page), 40, false)
		ios_runtime.swift_concurrency_retired = true
		oa_reject()
		ios_runtime.swift_concurrency_retired = false
		objc_stop()
		assert ios_runtime.swift_object_any_arena == 0 && ios_runtime.swift_object_any_retired
		oa_reject()
		for address in [arena, arena + u64(page)]! {
			$if macos {
				assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(address), page, unsafe { &resident }) == -1
			}
		}
	}
	println('IOS-OBJECT-ANY: canonical sealed bridge/AnyObject metadata and owned Any values, nil payload identity, exact result footprint, balanced copy/take/assignment, unlocked formal-class reentry, eight cold publishers/workers and two drained/unmapped lifetimes')
}

fn oa_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + length <= start + size && info[0] == (C.PROT_READ | if executable {
			C.PROT_EXEC
		} else {
			0
		})
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
				assert address + length <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found
	}
}
