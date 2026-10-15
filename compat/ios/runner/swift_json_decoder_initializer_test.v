// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

$if macos {
	#include <mach/mach.h>
}

fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type JSONInitAccess = fn (u64) SwiftAssociatedMetadata
type JSONInitAllocate = fn (u64, u64, u64) u64
type JSONInitRelease = fn (u64)
type JSONInitRetain = fn (u64) u64
type JSONInitUnique = fn (u64) bool
type JSONInitProbe = fn (u64, u64, u64, &u64)
type JSONInitCopy = fn (u64, u64, u64) u64
type JSONInitDestroy = fn (u64, u64)

fn json_init_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 8 <= start + size
			assert info[0] == C.PROT_READ | if executable { C.PROT_EXEC } else { 0 }
		} else {
			assert status != 0 || start > address
		}
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
				assert mapped && fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found == mapped
	}
}

struct JSONInitApi {
	native      bool
	metadata    u64
	accessor    u64
	constructor u64
	descriptor  u64
	allocate    JSONInitAllocate @[required]
	retain      JSONInitRetain @[required]
	release     JSONInitRelease @[required]
	unique      JSONInitUnique @[required]
}

fn json_init_api() JSONInitApi {
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	accessor := runtime_symbol(library, '_$s10Foundation11JSONDecoderCMa') or { panic(err) }
	access := unsafe { JSONInitAccess(voidptr(accessor)) }
	response := access(0)
	return JSONInitApi{
		metadata:    response.metadata
		accessor:    accessor
		constructor: runtime_symbol(library, '_$s10Foundation11JSONDecoderCACycfc') or { panic(err) }
		descriptor:  runtime_symbol(library, '_$s10Foundation11JSONDecoderCMn') or { panic(err) }
		allocate:    swift_heap_allocate
		retain:      swift_retain
		release:     swift_release
		unique:      swift_is_unique_native
	}
}

fn json_init_instance(api JSONInitApi, probe JSONInitProbe) {
	owner := api.allocate(api.metadata, 160, 7)
	C.memset(voidptr(owner + 16), 0xa5, 144)
	mut output := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	probe(api.constructor, owner, 0x5021, unsafe { &output[1] })
	assert output[0] == 0xcafe && output[5] == 0xbeef
	assert output[1] == owner && output[3] == owner && output[4] == 0x5021
	assert read64(owner) & 0x0000ffffffffffff == api.metadata && read64(owner + 8) == 3
	assert read64(owner + 16) == 0xd000000000000021
	key := (read64(owner + 24) & 0x00007fffffffffff) + 32
	assert C.memcmp(voidptr(key), c'_NSAssumesTopLevelDictionaryJSON5', 33) == 0
	for i in u64(32) .. 160 {
		if (i >= 49 && i < 56) || (i >= 145 && i < 152) {
			assert unsafe { *(&u8(owner + i)) } == 0xa5
		} else if i == 48 {
			assert unsafe { *(&u8(owner + i)) } == 2
		} else if i == 56 {
			assert unsafe { *(&u8(owner + i)) } == 1
		} else if i < 136 || i == 144 {
			assert unsafe { *(&u8(owner + i)) } == 0
		}
	}
	dictionary := read64(owner + 136)
	assert dictionary != 0 && read64(dictionary + 8) == 0x80000004ffffffff
	for i in u64(16) .. 48 {
		assert unsafe { *(&u8(dictionary + i)) } == 0
	}
	assert read64(dictionary + 48) == 1 && read64(dictionary + 56) == 1 && read64(dictionary + 64) == ~u64(1)
	assert api.retain(dictionary) == dictionary && !api.unique(dictionary)
	api.release(dictionary)
	child := read64(owner + 152)
	assert child != 0 && read64(child + 8) == 3 && read32(child + 16) == 0
	assert api.unique(owner) && api.unique(child)
	assert api.retain(owner) == owner && !api.unique(owner)
	api.release(owner)
	witness := read64(api.metadata - 8) & 0x0000ffffffffffff
	copy_value := unsafe { JSONInitCopy(voidptr(read64(witness + 16) & 0x0000ffffffffffff)) }
	destroy_value := unsafe { JSONInitDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	mut values := [u64(0xcafe), owner, 0, 0xbeef]!
	assert copy_value(u64(unsafe { &values[2] }), u64(unsafe { &values[1] }), api.metadata) == u64(unsafe { &values[2] })
	assert values[0] == 0xcafe && values[1] == owner && values[2] == owner && values[3] == 0xbeef
	assert !api.unique(owner)
	destroy_value(u64(unsafe { &values[2] }), api.metadata)
	assert api.unique(owner) && values[2] == owner
	if !api.native {
		assert swift_object_type(owner) == api.metadata
		assert swift_json_decoder_initialize_checked(owner) or { u64(0) } == 0
		C.ios_objc_initialize_lock()
		assert (ios_runtime.swift_json_decoders[owner] or { u64(0) }) == child
		C.ios_objc_initialize_unlock()
		assert swift_unknown_retain(dictionary) == dictionary
		swift_unknown_release(dictionary)
	}
	// Retain the lock independently: releasing Self must consume exactly the
	// decoder's reference, and the lock remains live until this final release.
	assert api.retain(child) == child
	api.release(owner)
	assert read64(child + 8) == 3 && api.unique(child)
	api.release(child)
	// Another worker may immediately reuse either address. Check whole
	// registries only after all workers join, rather than querying dead keys.
}

fn json_init_worker(api JSONInitApi, probe JSONInitProbe) {
	for _ in 0 .. 64 { json_init_instance(api, probe) }
}

fn json_init_suite(api JSONInitApi, probe JSONInitProbe) {
	access := unsafe { JSONInitAccess(voidptr(api.accessor)) }
	for request in [u64(0), 1, 0xff, 0x100, 0x1ff, u64(-1)]! {
		response := access(request)
		assert response.metadata == api.metadata && response.state == 0
	}
	metadata := api.metadata
	assert read32(metadata + 40) & 2 != 0 && read32(metadata + 44) == 0
	assert read32(metadata + 48) == 160 && unsafe { *(&u16(metadata + 52)) } == 7
	assert read64(metadata + 64) & 0x0000ffffffffffff == api.descriptor
	assert read64(metadata + 80) == 16 && read64(metadata + 88) == 32 && read64(metadata + 96) == 152
	assert read32(api.descriptor) & 31 == 16 && read32(api.descriptor) & 0x80 == 0
	assert read32(api.descriptor + 24) == 3 && read32(api.descriptor + 28) == 44
	json_init_instance(api, probe)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn json_init_worker(api, probe) }
	workers.wait()
	if !api.native {
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_json_decoders.len == 0
		assert swift_mangled_nominal(api.descriptor) or { panic(err) } == metadata
		assert read64(metadata + 320) == api.accessor + 128
	}
}

fn json_init_publish() u64 { return swift_json_decoder_arena() or { panic(err) } }

fn test_swift_json_decoder_initializer() {
	$if !arm64 {
		return
	}
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// C -> Swift initializing constructor, with canaries for borrowed Self
	// and the error register. Capture x0/x1 and x20/x21, then restore C's ABI.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xf90013f5, 0xaa0003f0, 0xaa0103f4, 0xaa0203f5,
		0xaa0303f3, 0xd63f0200, 0xa9000660, 0xa9015674, 0xf94013f5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 56))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { JSONInitProbe(voidptr(code)) }
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert foundation != unsafe { nil } && core != unsafe { nil }
		accessor := u64(C.dlsym(foundation, c'$s10Foundation11JSONDecoderCMa'))
		access := unsafe { JSONInitAccess(voidptr(accessor)) }
		response := access(0)
		api := JSONInitApi{
			native:      true
			metadata:    response.metadata
			accessor:    accessor
			constructor: u64(C.dlsym(foundation, c'$s10Foundation11JSONDecoderCACycfc'))
			descriptor:  u64(C.dlsym(foundation, c'$s10Foundation11JSONDecoderCMn'))
			allocate:    unsafe { JSONInitAllocate(C.dlsym(core, c'swift_allocObject')) }
			retain:      unsafe { JSONInitRetain(C.dlsym(core, c'swift_retain')) }
			release:     unsafe { JSONInitRelease(C.dlsym(core, c'swift_release')) }
			unique:      unsafe { JSONInitUnique(C.dlsym(core, c'swift_isUniquelyReferenced_nonNull_native')) }
		}
		json_init_suite(api, probe)
		println('IOS-JSON-INIT-NATIVE: base metadata, exact default option writes and preserved padding, x20/x21 and returned Self, independent owned lock teardown, 8 workers x64 constructions')
	}
	if _ := swift_json_decoder_arena() {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn json_init_publish() }
		bases := publishers.wait()
		for base in bases {
			assert base == bases[0]
		}
		api := json_init_api()
		json_init_mapping(bases[0], true, true)
		json_init_mapping(api.metadata, true, false)
		json_init_suite(api, probe)
		assert swift_json_decoder_initialize_checked(code) or { u64(0) } == 0
		short := swift_heap_allocate(api.metadata, 159, 7)
		assert swift_json_decoder_initialize_checked(short) or { u64(0) } == 0
		swift_heap_deallocate_uninitialized(short, 159, 7)
		for symbol in ['_$s10Foundation11JSONDecoderCACycfc', '_$s10Foundation11JSONDecoderCMa',
			'_$s10Foundation11JSONDecoderCMn']! {
			assert framework_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', symbol) or { u64(0) } ==
				runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', symbol) or { u64(0) }
			if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) {
				assert false
			}
			if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol) {
				assert false
			}
		}
		objc_stop()
		assert ios_runtime.swift_json_decoder_arena == 0 && ios_runtime.swift_json_decoders.len == 0
		json_init_mapping(bases[0], false, false)
		json_init_mapping(api.metadata, false, false)
		if _ := swift_json_decoder_symbol('_$s10Foundation11JSONDecoderCMa') {
			assert false
		}
		assert swift_json_decoder_initialize_checked(code) or { u64(0) } == 0
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-JSON-INIT: canonical base construction/default options, borrowed x20 and unchanged x21, exact padding, independent lock ownership and flat drained registries, concurrent publication/construction, invalid/duplicate/short/retired Self rejection, two retirements; default decoding/options/subclass/ObjC methods remain unsupported')
}
