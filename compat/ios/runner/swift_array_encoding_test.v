// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <mach/mach.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type AeAccess = fn (u64, u64) SwiftAssociatedMetadata
type AeNominal = fn (u64) SwiftAssociatedMetadata
type AeAllocate = fn (i64, u64) SwiftArrayAllocation
type AeLookup = fn (u64, u64, u64) u64
type AeKeep = fn (u64) u64
type AeDrop = fn (u64)
type AeInvoke = fn (u64, &u64, u64, u64, &u64)
type AeSign = fn (u64, u64) u64

struct AeApi {
	native     bool
	code       u64
	descriptor u64
	access     AeAccess   @[required]
	allocate   AeAllocate @[required]
	lookup     AeLookup   @[required]
	keep       AeKeep     @[required]
	drop       AeDrop     @[required]
	elements   [3]u64
	witnesses  [3]u64
}

struct AeState {
	api             AeApi
	object          u64
	error_owner     u64
	count           u64
	kind            int
	failure         int
	reenter         bool
	container_boxed bool
	shared          bool
	heap_metadata   u64
mut:
	metadata           u64
	table              u64
	encoder_metadata   u64
	encoder_table      u64
	container_metadata u64
	container_table    u64
	encoder_self       u64
	container          u64
	container_owner    u64
	getters            int
	encodes            int
	drops              int
}

fn ae_symbol(native bool, library string, name string) u64 {
	$if macos {
		if native {
			handle := C.dlopen(library.str, 2)
			assert handle != unsafe { nil }
			address := u64(C.dlsym(handle, name[1..].str))
			assert address != 0, name
			return address
		}
	}
	return runtime_symbol(library, name) or { panic(err) }
}

fn ae_api(native bool, code u64, guard u64) AeApi {
	core := '/usr/lib/swift/libswiftCore.dylib'
	foundation := '/System/Library/Frameworks/Foundation.framework/Foundation'
	lookup := unsafe { AeLookup(voidptr(ae_symbol(native, core, '_swift_getWitnessTable'))) }
	date_access := unsafe { AeNominal(voidptr(ae_symbol(native, foundation, '_$s10Foundation4DateVMa'))) }
	date := date_access(0).metadata
	date_table := lookup(ae_symbol(native, foundation, '_$s10Foundation4DateVSEAAMc'), date, 0)
	return AeApi{
		native:     native
		code:       code
		descriptor: ae_symbol(native, core, '_$sSayxGSEsSERzlMc')
		access:     unsafe { AeAccess(voidptr(ae_symbol(native, core, '_$sSaMa'))) }
		allocate:   unsafe { AeAllocate(voidptr(ae_symbol(native, core, '_$ss27_allocateUninitializedArrayySayxG_BptBwlF'))) }
		lookup:     lookup
		keep:       unsafe { AeKeep(voidptr(ae_symbol(native, core, '_swift_bridgeObjectRetain'))) }
		drop:       unsafe { AeDrop(voidptr(ae_symbol(native, core, '_swift_bridgeObjectRelease'))) }
		elements:   [ae_symbol(native, core, '_$sSiN'), ae_symbol(native, core, '_$sSSN'), date]!
		witnesses:  [if native { ae_symbol(true, core, '_$sSiSEsWP') } else { guard },
			if native { ae_symbol(true, core, '_$sSSSEsWP') } else { guard + 8 }, date_table]!
	}
}

fn ae_object(api AeApi) u64 {
	$if macos {
		if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) }
	}
	return owned_string('borrowed Array encoding element')
}

fn ae_object_keep(api AeApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRetain(voidptr(owner))
			return
		}
	}
	objc_retain(owner)
}

fn ae_object_drop(api AeApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(owner))
			return
		}
	}
	objc_release(owner)
}

fn ae_refs(api AeApi, owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(owner)) }
	}
	return obj_header(owner).refs
}

fn ae_relative(at u64) u64 { return u64(i64(at) + i64(i32(read32(at)))) }

fn ae_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSayxGSEsSERzlMc') or { panic(err) }
}

fn ae_reenter(s &AeState) {
	if s.reenter {
		t := spawn ae_resolve()
		assert t.wait() == s.api.descriptor
	}
}

fn ae_getter(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &AeState(read64(receiver)) }
	assert metadata == s.encoder_metadata && table == s.encoder_table && receiver == s.encoder_self
	assert s.getters == 0 && s.encodes == 0 && s.drops == 0
	assert ae_refs(s.api, s.object) == 1 + if s.kind == 1 { i64(s.count) } else { i64(0) }
	s.getters++
	mut payload := output
	if s.container_boxed {
		owner := swift_heap_allocate(s.heap_metadata, 48, 7)
		s.container_owner = owner
		if s.shared { swift_retain(owner) }
		payload = owner + 16
		unsafe { *(&u64(output)) = owner }
	}
	s.container = payload
	unsafe {
		*(&u64(payload)) = u64(s)
		*(&u64(payload + 8)) = 0x12345678
		*(&u64(payload + 16)) = 0
		*(&u64(output + 24)) = s.container_metadata
		*(&u64(output + 32)) = s.container_table
	}
	ae_reenter(s)
}

fn ae_encode(value u64, element u64, element_table u64, metadata u64, table u64, receiver u64, incoming u64) u64 {
	mut s := unsafe { &AeState(read64(receiver)) }
	index := u64(s.encodes)
	assert element == s.api.elements[s.kind] && element_table == s.api.witnesses[s.kind]
	assert metadata == s.container_metadata && table == s.container_table && receiver == s.container && incoming == 0
	assert s.getters == 1 && s.drops == 0 && index < s.count
	assert read64(receiver + 8) == 0x12345678 && read64(receiver + 16) == index
	if s.kind == 1 {
		words := unsafe { *(&SwiftStringWords(value)) }
		assert words.first == 0 && words.second == s.object | 0x5000000000000000
		assert ae_refs(s.api, s.object) == i64(s.count) + 2
	} else {
		assert read64(value) == (if s.kind == 0 { ~index } else { 0x1122334455667788 + index })
	}
	s.encodes++
	unsafe { *(&u64(receiver + 16)) = index + 1 }
	ae_reenter(s)
	if s.failure == int(index) {
		ae_object_keep(s.api, s.error_owner)
		return s.error_owner
	}
	return 0
}

fn ae_destroy(value u64, metadata u64) {
	mut s := unsafe { &AeState(read64(value)) }
	assert metadata == s.container_metadata && value == s.container
	assert s.getters == 1 && s.drops == 0 && read64(value + 16) == u64(s.encodes)
	assert ae_refs(s.api, s.object) == 1 + if s.kind == 1 { i64(s.count) } else { i64(0) }
	s.drops++
	ae_reenter(s)
}

fn ae_box_destroy(owner u64) {
	s := unsafe { &AeState(read64(owner + 16)) }
	ae_destroy(owner + 16, s.container_metadata)
	swift_heap_deallocate(owner, 48, 7)
}

fn ae_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203f4,
		0xaa0303f5, 0xaa0403f3, 0xa9400520, 0xa9410d22, 0xaa0303e8, 0xd63f0200, 0xa9005674, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e2, 0xaa1403e3, 0x580000b0, 0xd63f0200, 0xd28acf15,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 160)) = u64(voidptr(ae_getter)) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e5, 0xaa1503e6, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 192 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 224)) = u64(voidptr(ae_encode)) }
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 320 + u64(i * 4), op) }
	unsafe { *(&u64(code + 336)) = u64(voidptr(ae_box_destroy)) }
	write32(code + 384, 0xdac10020)
	write32(code + 388, 0xd65f03c0)
	write32(code + 400, 0xdac10820)
	write32(code + 404, 0xd65f03c0)
}

fn ae_case(api AeApi, kind int, count u64, boxed bool, at_end bool, failure int, profile int) {
	missing := profile == 1
	container_boxed := profile >= 2
	shared := profile == 3
	unsupported := missing || (container_boxed && count != 0)
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 5) == 0 }
	data := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	defer { assert C.munmap(voidptr(data), page) == 0 }
	for offset in [u64(page), u64(page * 3)]! {
		assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	encoder := span + u64(page) + if at_end { u64(page) - 40 } else { u64(0) }
	source := span + u64(page * 3) + if at_end { u64(page) - 8 } else { u64(0) }
	object := ae_object(api)
	error_owner := ae_object(api)
	defer {
		ae_object_drop(api, object)
		ae_object_drop(api, error_owner)
	}
	element := api.elements[kind]
	metadata := api.access(0, element).metadata
	arg := [api.witnesses[kind]]!
	table := api.lookup(api.descriptor, metadata, u64(unsafe { &arg[0] }))
	allocation := api.allocate(i64(count), element)
	defer { api.drop(allocation.owner) }
	stride := if kind == 1 { u64(16) } else { u64(8) }
	for i in u64(0) .. count {
		if kind == 1 {
			ae_object_keep(api, object)
			unsafe { *(&SwiftStringWords(allocation.bytes + i * stride)) = SwiftStringWords{ second: object | 0x5000000000000000 } }
		} else {
			unsafe {
				*(&u64(allocation.bytes + i * stride)) = if kind == 0 {
					~i
				} else {
					0x1122334455667788 + i
				}
			}
		}
	}
	mut s := AeState{
		api:                api
		object:             object
		error_owner:        error_owner
		count:              count
		kind:               kind
		failure:            failure
		reenter:            !api.native && kind == 1 && count == 3
		container_boxed:    container_boxed
		shared:             shared
		heap_metadata:      data + 944
		metadata:           metadata
		table:              table
		encoder_metadata:   data + 16
		encoder_table:      data + 640
		container_metadata: data + 192
		container_table:    data + 704
	}
	for i in 0 .. 2 {
		meta := data + 16 + u64(i * 176)
		vwt := data + 64 + u64(i * 176)
		mut pointer := vwt
		mut destroy := u64(voidptr(ae_destroy))
		$if macos {
			if api.native {
				sign := unsafe { AeSign(voidptr(api.code + 384)) }
				pointer = unsafe { AeSign(voidptr(api.code + 400))(vwt, (meta - 8) | (u64(0x2e3f) << 48)) }
				destroy = sign(destroy, (vwt + 8) | (u64(0x4f8) << 48))
			}
		}
		unsafe {
			*(&u64(meta - 8)) = pointer
			*(&u64(meta)) = 0x200
			*(&u64(vwt + 8)) = destroy
			*(&u64(vwt + 64)) = if (i == 0 && boxed) || (i == 1 && container_boxed) {
				u64(32)
			} else {
				u64(24)
			}
			*(&u64(vwt + 72)) = if (i == 0 && boxed) || (i == 1 && container_boxed) {
				u64(32)
			} else {
				u64(24)
			}
		}
		write32(vwt + 80, if (i == 0 && boxed) || (i == 1 && container_boxed) {
			u32(0x30007)
		} else {
			u32(0x10007)
		})
	}
	for item in [[u64(672), api.code + 128, 0x5b2a]!, [u64(864), api.code + 192, 0x4338]!]! {
		slot := data + item[0]
		mut callback := item[1]
		$if macos {
			if api.native {
				callback = unsafe { AeSign(voidptr(api.code + 384))(callback, slot | (item[2] << 48)) }
			}
		}
		unsafe { *(&u64(slot)) = if missing && item[0] == 864 { u64(0) } else { callback } }
	}
	unsafe {
		*(&u64(data + 928)) = api.code + 320
		*(&u64(data + 944)) = 0x400
	}
	mut payload := encoder
	if boxed {
		payload = data + 2064
		unsafe { *(&u64(encoder)) = data + 2048 }
	}
	s.encoder_self = payload
	unsafe {
		*(&u64(payload)) = u64(&s)
		*(&u64(payload + 8)) = 0x87654321
		*(&u64(encoder + 24)) = s.encoder_metadata
		*(&u64(encoder + 32)) = s.encoder_table
		*(&u64(source)) = allocation.owner
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(data), page, C.PROT_READ) == 0
	args := [encoder, metadata, table, span]!
	mut capture := [u64(0xaaaa), 0, 0, 0xbbbb]!
	if unsupported {
		assert !api.native && count != 0
		if _ := swift_array_encoding_checked(encoder, metadata, table, source, 0) {
			assert false
		}
	} else {
		unsafe { AeInvoke(voidptr(api.code))(read64(table + 8) & 0x0000ffffffffffff, &args[0], source, 0, &capture[1]) }
		assert capture == [u64(0xaaaa), source,
			if failure >= 0 && u64(failure) < count { error_owner } else { u64(0) }, 0xbbbb]!
	}
	assert s.getters == 1 && s.drops == if shared { 0 } else { 1 }
	if shared { swift_release(s.container_owner) }
	assert s.drops == 1
	expected := if unsupported {
		0
	} else if failure >= 0 && u64(failure) < count {
		failure + 1
	} else {
		int(count)
	}
	assert s.encodes == expected
	assert ae_refs(api, object) == 1 + if kind == 1 { i64(count) } else { i64(0) }
	assert ae_refs(api, error_owner) == if failure >= 0 && u64(failure) < count && !unsupported {
		2
	} else {
		1
	}
	if failure >= 0 && u64(failure) < count && !unsupported { ae_object_drop(api, error_owner) }
	assert read64(source) == allocation.owner && read64(encoder) == if boxed {
		data + 2048
	} else {
		u64(unsafe { &s })
	}
}

fn ae_matrix(api AeApi) {
	for kind in 0 .. 3 {
		for count in [u64(0), 1, 3, 9]! {
			for boxed in [false, true]! {
				for at_end in [false, true]! {
					for failure in [-1, 0, 2]! {
						ae_case(api, kind, count, boxed, at_end, failure, 0)
					}
				}
			}
		}
	}
}

fn ae_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + length <= start + size
		assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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

fn ae_descriptor(api AeApi, guard u64) {
	d := api.descriptor
	protocol := ae_relative(d)
	nominal := ae_relative(d + 4)
	assert read32(d + 12) == 0x20100 && read32(d + 16) == 0x80 && read32(d + 28) == 0x30002 && read32(d + 32) == 0
	assert unsafe { (&char(voidptr(ae_relative(protocol + 8)))).vstring() } == 'Encodable'
	assert unsafe { (&char(voidptr(ae_relative(nominal + 8)))).vstring() } == 'Array'
	assert unsafe { (&char(voidptr(ae_relative(d + 20)))).vstring() } == 'x' && ae_relative(d + 24) == protocol
	pattern := ae_relative(d + 8)
	assert read64(pattern) == d && read64(pattern + 8) != 0
	if !api.native {
		ae_protection(d, 80, false)
		ae_protection(pattern, 16, false)
		ae_protection(read64(pattern + 8), 32, true)
		cache := ae_relative(d + 36)
		for i in 0 .. 16 {
			assert read64(cache + u64(i * 8)) == 0
		}
	}
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	defer { assert C.munmap(voidptr(base), page * 2) == 0 }
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	args := base + u64(page) - 8
	nested := api.access(0, api.elements[1]).metadata
	nestedarg := [api.witnesses[1]]!
	nestedtable := api.lookup(d, nested, u64(unsafe { &nestedarg[0] }))
	for pair in [[api.elements[0], api.witnesses[0]]!, [api.elements[1], api.witnesses[1]]!,
		[api.elements[2], api.witnesses[2]]!, [nested, nestedtable]!]! {
		metadata := api.access(0, pair[0]).metadata
		assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { *(&u64(args)) = pair[1] }
		assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
		table := api.lookup(d, metadata, args)
		assert table != ae_relative(d + 8) && read64(table) == d && read64(table - 8) == pair[1]
		if !api.native { ae_protection(table - 8, 24, false) }
		assert C.mprotect(voidptr(base), page, C.PROT_NONE) == 0
		for expired in [u64(0), args, guard]! {
			for _ in 0 .. 32 {
				assert api.lookup(d, metadata, expired) == table
			}
		}
	}
}

fn ae_worker(api AeApi, i int) { ae_case(api, i % 3, 3, i % 2 == 0, true, i % 3 - 1, 0) }

fn test_swift_array_encoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	ae_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 408))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		api := ae_api(true, code, guard)
		ae_descriptor(api, guard)
		ae_matrix(api)
		println('NATIVE-ARRAY-ENCODING: 144 Int/String/Date cases, nested conditional conformance, one private word, expired argument cache hits, element copy/destroy before container cleanup and original owned errors')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn ae_resolve() }
		identities := publishers.wait()
		api := ae_api(false, code, guard)
		for descriptor in identities {
			assert descriptor == api.descriptor
		}
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn ae_worker(api, i) }
		workers.wait()
		unsafe {
			workers.free()
			identities.free()
			publishers.free()
		}
		ae_descriptor(api, guard)
		ae_matrix(api)
		ae_case(api, 1, 3, true, true, -1, 1)
		for profile in [2, 3]! {
			for count in [u64(0), 3]! { ae_case(api, 1, count, true, true, -1, profile) }
		}
		for metadata in [u64(0), 1, guard, ~u64(7)]! {
			if _ := swift_witness_table_checked(api.descriptor, metadata, guard) {
				assert false
			}
		}
		opaque := api.access(0, guard).metadata
		for args in [u64(0), 1, ~u64(7)]! {
			if _ := swift_witness_table_checked(api.descriptor, opaque, args) {
				assert false
			}
		}
		for invalid in [u64(0), 1]! {
			args := [invalid]!
			if _ := swift_witness_table_checked(api.descriptor, opaque, u64(unsafe { &args[0] })) {
				assert false
			}
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSayxGSEsSERzlMc') == none
		}
		ios_runtime.swift_concurrency_retired = true
		assert swift_array_encoding_symbol('_$sSayxGSEsSERzlMc') == none
		if _ := swift_witness_table_checked(api.descriptor, opaque, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		tables := ios_runtime.swift_array_encoding.values()
		arena := ios_runtime.swift_array_encoding_arena
		objc_stop()
		assert ios_runtime.swift_array_encoding.len == 0 && ios_runtime.swift_array_encoding_arena == 0
		if _ := swift_witness_table_checked(api.descriptor, opaque, guard) {
			assert false
		}
		for address in tables.map(it - 8) {
			$if macos {
				assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(address), page, unsafe { &resident }) == -1
			}
		}
		$if macos {
			assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
		} $else {
			mut resident := u8(0)
			assert C.mincore(voidptr(arena), page, unsafe { &resident }) == -1
		}
		unsafe { tables.free() }
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-ARRAY-ENCODING: canonical conditional witnesses and unkeyed protocol encoding, exact non-POD element copy/destroy, original error transfer and owned container cleanup, readonly guarded Array/Encoder, eight cold publishers/workers, reentrant callbacks and two drained/unmapped lifetimes; boxed mutable containers and bridged ObjC array storage remain unsupported')
}
