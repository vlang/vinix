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

type JSONEncoderInitAccess = fn (u64) SwiftAssociatedMetadata
type JSONEncoderInitAllocate = fn (u64, u64, u64) u64
type JSONEncoderInitRelease = fn (u64)
type JSONEncoderInitRetain = fn (u64) u64
type JSONEncoderInitUnique = fn (u64) bool
type JSONEncoderInitProbe = fn (u64, u64, u64, &u64)
type JSONEncoderInitCopy = fn (u64, u64, u64) u64
type JSONEncoderInitDestroy = fn (u64, u64)

fn json_encoder_init_mapping(address u64, mapped bool, executable bool) {
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

struct JSONEncoderInitApi {
	native      bool
	metadata    u64
	accessor    u64
	constructor u64
	descriptor  u64
	allocate    JSONEncoderInitAllocate @[required]
	retain      JSONEncoderInitRetain   @[required]
	release     JSONEncoderInitRelease  @[required]
	unique      JSONEncoderInitUnique   @[required]
}

fn json_encoder_init_api() JSONEncoderInitApi {
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	accessor := runtime_symbol(library, '_$s10Foundation11JSONEncoderCMa') or { panic(err) }
	access := unsafe { JSONEncoderInitAccess(voidptr(accessor)) }
	response := access(0)
	return JSONEncoderInitApi{
		metadata:    response.metadata
		accessor:    accessor
		constructor: runtime_symbol(library, '_$s10Foundation11JSONEncoderCACycfc') or { panic(err) }
		descriptor:  runtime_symbol(library, '_$s10Foundation11JSONEncoderCMn') or { panic(err) }
		allocate:    swift_heap_allocate
		retain:      swift_retain
		release:     swift_release
		unique:      swift_is_unique_native
	}
}

fn json_encoder_init_instance(api JSONEncoderInitApi, probe JSONEncoderInitProbe) {
	owner := api.allocate(api.metadata, 144, 7)
	C.memset(voidptr(owner + 16), 0xa5, 128)
	mut output := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	probe(api.constructor, owner, 0x5021, unsafe { &output[1] })
	assert output[0] == 0xcafe && output[5] == 0xbeef
	assert output[1] == owner && output[3] == owner && output[4] == 0x5021
	assert read64(owner) & 0x0000ffffffffffff == api.metadata && read64(owner + 8) == 3
	for i in u64(16) .. 128 {
		if i >= 41 && i < 48 {
			assert unsafe { *(&u8(owner + i)) } == 0xa5
		} else if i == 40 {
			assert unsafe { *(&u8(owner + i)) } == 2
		} else if i == 48 {
			assert unsafe { *(&u8(owner + i)) } == 1
		} else {
			assert unsafe { *(&u8(owner + i)) } == 0
		}
	}
	dictionary := read64(owner + 128)
	assert dictionary != 0 && read64(dictionary + 8) == 0x80000004ffffffff
	for i in u64(16) .. 48 {
		assert unsafe { *(&u8(dictionary + i)) } == 0
	}
	assert read64(dictionary + 48) == 1 && read64(dictionary + 56) == 1 && read64(dictionary + 64) == ~u64(1)
	assert api.retain(dictionary) == dictionary && !api.unique(dictionary)
	api.release(dictionary)
	child := read64(owner + 136)
	assert child != 0 && read64(child + 8) == 3 && read32(child + 16) == 0
	assert api.unique(owner) && api.unique(child)
	assert api.retain(owner) == owner && !api.unique(owner)
	api.release(owner)
	witness := read64(api.metadata - 8) & 0x0000ffffffffffff
	copy_value := unsafe { JSONEncoderInitCopy(voidptr(read64(witness + 16) & 0x0000ffffffffffff)) }
	destroy_value := unsafe { JSONEncoderInitDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	mut values := [u64(0xcafe), owner, 0, 0xbeef]!
	assert copy_value(u64(unsafe { &values[2] }), u64(unsafe { &values[1] }), api.metadata) == u64(unsafe { &values[2] })
	assert values[0] == 0xcafe && values[1] == owner && values[2] == owner && values[3] == 0xbeef
	assert !api.unique(owner)
	destroy_value(u64(unsafe { &values[2] }), api.metadata)
	assert api.unique(owner) && values[2] == owner
	if !api.native {
		assert swift_object_type(owner) == api.metadata
		assert swift_json_encoder_initialize_checked(owner) or { u64(0) } == 0
		C.ios_objc_initialize_lock()
		assert (ios_runtime.swift_json_encoders[owner] or { u64(0) }) == child
		C.ios_objc_initialize_unlock()
		assert swift_unknown_retain(dictionary) == dictionary
		swift_unknown_release(dictionary)
	}
	// Retain the lock independently: releasing Self must consume exactly the
	// encoder's reference, and the lock remains live until this final release.
	assert api.retain(child) == child
	api.release(owner)
	assert read64(child + 8) == 3 && api.unique(child)
	api.release(child)
	// Another worker may immediately reuse either address. Check whole
	// registries only after all workers join, rather than querying dead keys.
}

fn json_encoder_init_worker(api JSONEncoderInitApi, probe JSONEncoderInitProbe) {
	for _ in 0 .. 64 { json_encoder_init_instance(api, probe) }
}

fn json_encoder_init_suite(api JSONEncoderInitApi, probe JSONEncoderInitProbe) {
	access := unsafe { JSONEncoderInitAccess(voidptr(api.accessor)) }
	for request in [u64(0), 1, 0xff, 0x100, 0x1ff, u64(-1)]! {
		response := access(request)
		assert response.metadata == api.metadata && response.state == 0
	}
	metadata := api.metadata
	assert read32(metadata + 40) & 2 != 0 && read32(metadata + 44) == 0
	assert read32(metadata + 48) == 144 && unsafe { *(&u16(metadata + 52)) } == 7
	assert read64(metadata + 64) & 0x0000ffffffffffff == api.descriptor
	assert read64(metadata + 80) == 16 && read64(metadata + 88) == 136
	assert read32(api.descriptor) & 31 == 16 && read32(api.descriptor) & 0x80 == 0
	assert read32(api.descriptor + 24) == 3 && read32(api.descriptor + 28) == 38
	json_encoder_init_instance(api, probe)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn json_encoder_init_worker(api, probe) }
	workers.wait()
	if !api.native {
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_json_encoders.len == 0
		assert swift_mangled_nominal(api.descriptor) or { panic(err) } == metadata
		assert read64(metadata + 272) == api.accessor + 128
	}
}

fn json_encoder_init_publish() u64 { return swift_json_encoder_arena() or { panic(err) } }

fn test_swift_json_encoder_initializer() {
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
	probe := unsafe { JSONEncoderInitProbe(voidptr(code)) }
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert foundation != unsafe { nil } && core != unsafe { nil }
		accessor := u64(C.dlsym(foundation, c'$s10Foundation11JSONEncoderCMa'))
		access := unsafe { JSONEncoderInitAccess(voidptr(accessor)) }
		response := access(0)
		api := JSONEncoderInitApi{
			native:      true
			metadata:    response.metadata
			accessor:    accessor
			constructor: u64(C.dlsym(foundation, c'$s10Foundation11JSONEncoderCACycfc'))
			descriptor:  u64(C.dlsym(foundation, c'$s10Foundation11JSONEncoderCMn'))
			allocate:    unsafe { JSONEncoderInitAllocate(C.dlsym(core, c'swift_allocObject')) }
			retain:      unsafe { JSONEncoderInitRetain(C.dlsym(core, c'swift_retain')) }
			release:     unsafe { JSONEncoderInitRelease(C.dlsym(core, c'swift_release')) }
			unique:      unsafe { JSONEncoderInitUnique(C.dlsym(core, c'swift_isUniquelyReferenced_nonNull_native')) }
		}
		json_encoder_init_suite(api, probe)
		println('IOS-JSON-ENCODER-INIT-NATIVE: base metadata, exact default option writes and preserved padding, x20/x21 and returned Self, independent owned lock teardown, 8 workers x64 constructions')
	}
	if _ := swift_json_encoder_arena() {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn json_encoder_init_publish() }
		bases := publishers.wait()
		for base in bases {
			assert base == bases[0]
		}
		api := json_encoder_init_api()
		json_encoder_init_mapping(bases[0], true, true)
		json_encoder_init_mapping(api.metadata, true, false)
		json_encoder_init_suite(api, probe)
		assert swift_json_encoder_initialize_checked(code) or { u64(0) } == 0
		shared := swift_heap_allocate(api.metadata, 144, 7)
		C.memset(voidptr(shared + 16), 0xa5, 128)
		swift_retain(shared)
		assert swift_json_encoder_initialize_checked(shared) or { u64(0) } == 0
		swift_release(shared)
		for i in u64(16) .. 144 {
			assert unsafe { *(&u8(shared + i)) } == 0xa5
		}
		swift_heap_deallocate_uninitialized(shared, 144, 7)
		short := swift_heap_allocate(api.metadata, 143, 7)
		assert swift_json_encoder_initialize_checked(short) or { u64(0) } == 0
		swift_heap_deallocate_uninitialized(short, 143, 7)
		for symbol in ['_$s10Foundation11JSONEncoderCACycfc', '_$s10Foundation11JSONEncoderCMa',
			'_$s10Foundation11JSONEncoderCMn']! {
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
		assert ios_runtime.swift_json_encoder_arena == 0 && ios_runtime.swift_json_encoders.len == 0
		json_encoder_init_mapping(bases[0], false, false)
		json_encoder_init_mapping(api.metadata, false, false)
		if _ := swift_json_encoder_symbol('_$s10Foundation11JSONEncoderCMa') {
			assert false
		}
		assert swift_json_encoder_initialize_checked(code) or { u64(0) } == 0
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-JSON-ENCODER-INIT: canonical base construction/default options, borrowed x20 and unchanged x21, exact padding, independent lock ownership and flat drained registries, concurrent publication/construction, invalid/duplicate/short/retired Self rejection, two retirements; default encoding/options/subclass/ObjC methods remain unsupported')
}
