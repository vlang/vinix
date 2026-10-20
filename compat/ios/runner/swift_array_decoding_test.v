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

type AdAccess = fn (u64, u64) SwiftAssociatedMetadata
type AdNominal = fn (u64) SwiftAssociatedMetadata
type AdAllocate = fn (i64, u64) SwiftArrayAllocation
type AdLookup = fn (u64, u64, u64) u64
type AdKeep = fn (u64) u64
type AdDrop = fn (u64)
type AdInvoke = fn (u64, &u64, u64, &u64)
type AdSign = fn (u64, u64) u64

type AdBox = fn (u64) SwiftArrayAllocation

struct AdApi {
	native     bool
	code       u64
	descriptor u64
	access     AdAccess @[required]
	lookup     AdLookup @[required]
	drop       AdDrop   @[required]
	keep_box   AdKeep   @[required]
	drop_box   AdDrop   @[required]
	box        u64
	elements   [3]u64
	witnesses  [3]u64
}

struct AdState {
	api              AdApi
	object           u64
	error_owner      u64
	count            u64
	kind             int
	failure          int
	profile          int
	reenter          bool
	decoder_shared   bool
	container_boxed  bool
	container_shared bool
mut:
	element            u64
	decoder_metadata   u64
	decoder_table      u64
	container_metadata u64
	container_table    u64
	decoder_self       u64
	container_self     u64
	container_owner    u64
	getters            int
	ends               int
	decodes            int
	decoder_drops      int
	container_drops    int
}

fn ad_symbol(native bool, library string, name string) u64 {
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

fn ad_api(native bool, code u64, guard u64) AdApi {
	core := '/usr/lib/swift/libswiftCore.dylib'
	foundation := '/System/Library/Frameworks/Foundation.framework/Foundation'
	lookup := unsafe { AdLookup(voidptr(ad_symbol(native, core, '_swift_getWitnessTable'))) }
	date_access := unsafe { AdNominal(voidptr(ad_symbol(native, foundation, '_$s10Foundation4DateVMa'))) }
	date := date_access(0).metadata
	date_table := lookup(ad_symbol(native, foundation, '_$s10Foundation4DateVSeAAMc'), date, 0)
	return AdApi{
		native:     native
		code:       code
		descriptor: ad_symbol(native, core, '_$sSayxGSesSeRzlMc')
		access:     unsafe { AdAccess(voidptr(ad_symbol(native, core, '_$sSaMa'))) }
		lookup:     lookup
		drop:       unsafe { AdDrop(voidptr(ad_symbol(native, core, '_swift_bridgeObjectRelease'))) }
		keep_box:   unsafe { AdKeep(voidptr(ad_symbol(native, core, '_swift_retain'))) }
		drop_box:   unsafe { AdDrop(voidptr(ad_symbol(native, core, '_swift_release'))) }
		box:        if native { ad_symbol(true, core, '_swift_allocBox') } else { u64(0) }
		elements:   [ad_symbol(native, core, '_$sSiN'), ad_symbol(native, core, '_$sSSN'), date]!
		witnesses:  [if native { ad_symbol(true, core, '_$sSiSesWP') } else { guard },
			if native { ad_symbol(true, core, '_$sSSSesWP') } else { guard + 8 }, date_table]!
	}
}

fn ad_box(s &AdState, metadata u64, heap u64) SwiftArrayAllocation {
	if s.api.native { return unsafe { AdBox(voidptr(s.api.box))(metadata) } }
	owner := swift_heap_allocate(heap, 48, 7)
	return SwiftArrayAllocation{ owner: owner, bytes: owner + 16 }
}

fn ad_getter(metadata u64, table u64, output u64, receiver u64, incoming u64) u64 {
	mut s := unsafe { &AdState(read64(receiver)) }
	assert metadata == s.decoder_metadata && table == s.decoder_table && receiver == s.decoder_self && incoming == 0
	assert s.getters == 0 && s.ends == 0 && s.decodes == 0 && s.decoder_drops == 0
	s.getters++
	ad_reenter(s)
	if s.failure == -2 {
		ad_object_keep(s.api, s.error_owner)
		return s.error_owner
	}
	mut payload := output
	if s.container_boxed {
		box := ad_box(s, s.container_metadata, read64(s.container_metadata + 8))
		s.container_owner = box.owner
		payload = box.bytes
		if s.container_shared { s.api.keep_box(box.owner) }
		unsafe { *(&u64(output)) = box.owner }
	}
	s.container_self = payload
	unsafe {
		*(&u64(payload)) = u64(s)
		*(&u64(payload + 8)) = 0
		*(&u64(payload + 16)) = 0x12345678
		*(&u64(output + 24)) = s.container_metadata
		*(&u64(output + 32)) = s.container_table
	}
	return 0
}

fn ad_end(metadata u64, table u64, receiver u64) u64 {
	mut s := unsafe { &AdState(read64(receiver)) }
	index := read64(receiver + 8)
	assert metadata == s.container_metadata && table == s.container_table && receiver == s.container_self
	assert s.getters == 1 && s.container_drops == 0 && s.decoder_drops == 0 && index <= s.count
	assert s.ends == s.decodes
	s.ends++
	ad_reenter(s)
	return u64(index == s.count)
}

fn ad_decode(type_arg u64, metadata u64, element_table u64, container u64, table u64, output u64, receiver u64, incoming u64) u64 {
	mut s := unsafe { &AdState(read64(receiver)) }
	index := read64(receiver + 8)
	assert type_arg == s.element && metadata == s.element && element_table == s.api.witnesses[s.kind]
	assert container == s.container_metadata && table == s.container_table && receiver == s.container_self && incoming == 0
	assert s.ends == s.decodes + 1 && s.container_drops == 0 && s.decoder_drops == 0 && index < s.count
	assert ad_refs(s.api, s.object) == 1 + if s.kind == 1 { i64(index) } else { i64(0) }
	s.decodes++
	ad_reenter(s)
	if s.failure == int(index) {
		ad_object_keep(s.api, s.error_owner)
		return s.error_owner
	}
	if s.kind == 1 {
		ad_object_keep(s.api, s.object)
		unsafe { *(&SwiftStringWords(output)) = SwiftStringWords{ second: s.object | 0x5000000000000000 } }
	} else {
		unsafe { *(&u64(output)) = if s.kind == 0 { ~index } else { 0x1122334455667788 + index } }
	}
	unsafe { *(&u64(receiver + 8)) = index + 1 }
	return 0
}

fn ad_destroy(value u64, metadata u64) {
	mut s := unsafe { &AdState(read64(value)) }
	assert read64(value + 16) == 0x12345678
	if metadata == s.decoder_metadata {
		assert value == s.decoder_self && s.getters == 1 && s.decoder_drops == 0
		if !s.container_shared {
			assert s.container_drops == if s.failure == -2 { 0 } else { 1 }
		}
		s.decoder_drops++
	} else {
		assert metadata == s.container_metadata && value == s.container_self && s.container_drops == 0
		if !s.container_shared {
			assert s.decoder_drops == 0
		}
		success := s.failure != -2 && (s.failure < 0 || u64(s.failure) >= s.count) && s.profile in [
			0,
			2,
		]! && (!s.container_boxed || s.count == 0) && !s.container_shared
		assert ad_refs(s.api, s.object) == 1 + if s.kind == 1 && success {
			i64(s.count)
		} else {
			i64(0)
		}
		s.container_drops++
	}
	ad_reenter(s)
}

fn ad_box_destroy(owner u64) {
	ad_destroy(owner + 16, read64(read64(owner) + 8))
	swift_heap_deallocate(owner, 48, 7)
}

fn ad_emit(code u64) {
	// C entry/arguments/output/capture -> Swift. Preserve and capture x20/x21.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203e8,
		0xaa0303f3, 0xd28a0414, 0xd2800015, 0xa9400520, 0xf9400922, 0xd63f0200, 0xa9005674, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e2, 0xaa1403e3, 0xaa1503e4, 0x580000d0, 0xd63f0200,
		0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 168)) = u64(voidptr(ad_getter)) }
	// Generic decode -> ordinary C; indirect result in x5, Self x6, error x7.
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e5, 0xaa1403e6, 0xaa1503e7, 0x580000d0, 0xd63f0200,
		0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 192 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 232)) = u64(voidptr(ad_decode)) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e2, 0x580000d0, 0xd63f0200, 0xd28acf15, 0xa8c17bfd,
		0xd65f03c0]! {
		write32(code + 256 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 288)) = u64(voidptr(ad_end)) }
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 320 + u64(i * 4), op) }
	unsafe { *(&u64(code + 336)) = u64(voidptr(ad_box_destroy)) }
	write32(code + 384, 0xdac10020)
	write32(code + 388, 0xd65f03c0)
	write32(code + 400, 0xdac10820)
	write32(code + 404, 0xd65f03c0)
}

fn ad_case(api AdApi, kind int, count u64, boxed bool, shared bool, at_end bool, failure int, profile int) {
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
	decoder := span + u64(page) + if at_end { u64(page) - 40 } else { u64(0) }
	result := span + u64(page * 3) + if at_end { u64(page) - 8 } else { u64(0) }
	object := ad_object(api)
	error_owner := ad_object(api)
	defer {
		ad_object_drop(api, object)
		ad_object_drop(api, error_owner)
	}
	container_boxed := profile == 2
	container_shared := container_boxed && shared
	unsupported := (container_boxed && count != 0 && failure != -2) || profile in [1, 4, 5]!
	mut element := api.elements[kind]
	if profile == 5 {
		assert !api.native && kind == 1
		element = data + 1216
		witness := data + 1280
		C.memcpy(voidptr(witness), voidptr(read64(api.elements[kind] - 8)), 88)
		unsafe {
			*(&u64(element - 8)) = witness
			*(&u64(element)) = 0x200
			*(&u64(witness + 72)) = 65536
		}
	}
	metadata := api.access(0, element).metadata
	arg := [api.witnesses[kind]]!
	table := api.lookup(api.descriptor, metadata, u64(unsafe { &arg[0] }))
	mut s := AdState{
		api:                api
		object:             object
		error_owner:        error_owner
		count:              count
		kind:               kind
		failure:            failure
		profile:            profile
		reenter:            !api.native && kind == 1 && count == 3
		decoder_shared:     boxed && shared
		container_boxed:    container_boxed
		container_shared:   container_shared
		element:            element
		decoder_metadata:   data + 16
		decoder_table:      data + 640
		container_metadata: data + 192
		container_table:    data + 704
	}
	for i in 0 .. 2 {
		meta := data + 16 + u64(i * 176)
		vwt := data + 64 + u64(i * 176)
		mut pointer := vwt
		mut destroy := u64(voidptr(ad_destroy))
		out_of_line := (i == 0 && boxed) || (i == 1 && container_boxed)
		$if macos {
			if api.native {
				pointer = unsafe { AdSign(voidptr(api.code + 400))(vwt, (meta - 8) | (u64(0x2e3f) << 48)) }
				destroy = unsafe { AdSign(voidptr(api.code + 384))(destroy, (vwt + 8) | (u64(0x4f8) << 48)) }
			}
		}
		unsafe {
			*(&u64(meta - 8)) = pointer
			*(&u64(meta)) = 0x200
			*(&u64(meta + 8)) = data + 944 + u64(i * 64)
			*(&u64(vwt + 8)) = destroy
			*(&u64(vwt + 64)) = if out_of_line { u64(32) } else { u64(24) }
			*(&u64(vwt + 72)) = if out_of_line { u64(32) } else { u64(24) }
		}
		write32(vwt + 80, if out_of_line { u32(0x30007) } else { u32(0x10007) })
		heap := data + 944 + u64(i * 64)
		unsafe {
			*(&u64(heap - 16)) = api.code + 320
			*(&u64(heap)) = 0x400
			*(&u64(heap + 8)) = meta
		}
	}
	for item in [[u64(672), api.code + 128, 0x0a33]!, [u64(728), api.code + 256, 0x43c1]!,
		[u64(880), api.code + 192, 0x629e]!]! {
		slot := data + item[0]
		mut callback := item[1]
		$if macos {
			if api.native {
				callback = unsafe { AdSign(voidptr(api.code + 384))(callback, slot | (item[2] << 48)) }
			}
		}
		unsafe { *(&u64(slot)) = if profile == 1 && item[0] == 880 { u64(0) } else { callback } }
	}
	mut decoder_owner := u64(0)
	mut payload := decoder
	if boxed {
		box := ad_box(unsafe { &s }, s.decoder_metadata, data + 944)
		decoder_owner = box.owner
		payload = box.bytes
		if shared { api.keep_box(box.owner) }
	}
	s.decoder_self = payload
	unsafe {
		*(&u64(payload)) = u64(&s)
		*(&u64(payload + 8)) = 0
		*(&u64(payload + 16)) = 0x12345678
		if boxed { *(&u64(decoder)) = decoder_owner }
		*(&u64(decoder + 24)) = s.decoder_metadata
		*(&u64(decoder + 32)) = s.decoder_table
		*(&u64(result)) = 0xfeedface
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(data), page, C.PROT_READ) == 0
	args := [decoder, metadata, table]!
	mut capture := [u64(0xaaaa), 0, 0, 0xbbbb]!
	throws := failure == -2 || (failure >= 0 && u64(failure) < count)
	target := if profile == 4 {
		u64(0)
	} else if throws || unsupported {
		span
	} else {
		result
	}
	if unsupported {
		assert !api.native
		if _ := swift_array_decoding_checked(decoder, metadata, table, target, 0) {
			assert false
		}
	} else {
		unsafe { AdInvoke(voidptr(api.code))(read64(table + 8) & 0x0000ffffffffffff, &args[0], target, &capture[1]) }
		assert capture == [u64(0xaaaa), 0x5020, if throws { error_owner } else { u64(0) }, 0xbbbb]!
	}
	expected := if failure == -2 {
		0
	} else if profile == 1 || (container_boxed && count != 0) {
		0
	} else if profile == 5 {
		9
	} else if throws {
		failure + 1
	} else {
		int(count)
	}
	assert s.getters == 1 && s.decodes == expected
	assert s.ends == if failure == -2 {
		0
	} else if unsupported {
		if profile == 4 {
			int(count) + 1
		} else if profile == 5 {
			9
		} else {
			1
		}
	} else if throws {
		failure + 1
	} else {
		int(count) + 1
	}
	assert s.container_drops == if failure == -2 || container_shared { 0 } else { 1 }
	assert s.decoder_drops == if s.decoder_shared { 0 } else { 1 }
	if !throws && !unsupported {
		owner := read64(result)
		assert owner != 0 && read64(owner + 16) == count
		stride := if kind == 1 { u64(16) } else { u64(8) }
		for i in u64(0) .. count {
			value := owner + 32 + i * stride
			if kind == 1 {
				assert read64(value) == 0 && read64(value + 8) == object | 0x5000000000000000
			} else {
				assert read64(value) == if kind == 0 { ~i } else { 0x1122334455667788 + i }
			}
		}
		assert ad_refs(api, object) == 1 + if kind == 1 { i64(count) } else { i64(0) }
		api.drop(owner)
	} else {
		assert read64(result) == 0xfeedface
	}
	assert ad_refs(api, object) == 1
	assert ad_refs(api, error_owner) == if throws && !unsupported { 2 } else { 1 }
	if throws && !unsupported { ad_object_drop(api, error_owner) }
	if container_shared && failure != -2 { api.drop_box(s.container_owner) }
	if s.decoder_shared { api.drop_box(decoder_owner) }
	assert s.decoder_drops == 1 && s.container_drops == if failure == -2 { 0 } else { 1 }
}

fn ad_matrix(api AdApi) {
	for kind in 0 .. 3 {
		for count in [u64(0), 1, 3, 9]! {
			for boxed in [false, true]! {
				for shared in [false, true]! {
					for at_end in [false, true]! {
						for failure in [-2, -1, 0, 2]! {
							ad_case(api, kind, count, boxed, shared, at_end, failure, 0)
						}
					}
				}
			}
		}
	}
}

fn ad_object(api AdApi) u64 {
	$if macos {
		if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) }
	}
	return owned_string('borrowed Array decoding element')
}

fn ad_object_keep(api AdApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRetain(voidptr(owner))
			return
		}
	}
	objc_retain(owner)
}

fn ad_object_drop(api AdApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(owner))
			return
		}
	}
	objc_release(owner)
}

fn ad_refs(api AdApi, owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(owner)) }
	}
	return obj_header(owner).refs
}

fn ad_relative(at u64) u64 { return u64(i64(at) + i64(i32(read32(at)))) }

fn ad_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSayxGSesSeRzlMc') or { panic(err) }
}

fn ad_reenter(s &AdState) {
	if s.reenter {
		t := spawn ad_resolve()
		assert t.wait() == s.api.descriptor
	}
}

fn ad_protection(address u64, length u64, executable bool) {
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

fn ad_descriptor(api AdApi, guard u64) {
	d := api.descriptor
	protocol := ad_relative(d)
	nominal := ad_relative(d + 4)
	assert read32(d + 12) == 0x20100 && read32(d + 16) == 0x80 && read32(d + 28) == 0x30002 && read32(d + 32) == 0
	assert unsafe { (&char(voidptr(ad_relative(protocol + 8)))).vstring() } == 'Decodable'
	assert unsafe { (&char(voidptr(ad_relative(nominal + 8)))).vstring() } == 'Array'
	assert unsafe { (&char(voidptr(ad_relative(d + 20)))).vstring() } == 'x' && ad_relative(d + 24) == protocol
	pattern := ad_relative(d + 8)
	assert read64(pattern) == d && read64(pattern + 8) != 0
	if !api.native {
		ad_protection(d, 80, false)
		ad_protection(pattern, 16, false)
		ad_protection(read64(pattern + 8), 32, true)
		cache := ad_relative(d + 36)
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
		assert table != ad_relative(d + 8) && read64(table) == d && read64(table - 8) == pair[1]
		if !api.native { ad_protection(table - 8, 24, false) }
		assert C.mprotect(voidptr(base), page, C.PROT_NONE) == 0
		for expired in [u64(0), args, guard]! {
			for _ in 0 .. 32 {
				assert api.lookup(d, metadata, expired) == table
			}
		}
	}
}

fn ad_worker(api AdApi, i int) { ad_case(api, i % 3, 3, i % 2 == 0, false, true, i % 3 - 1, 0) }

fn test_swift_array_decoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	ad_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 408))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		api := ad_api(true, code, guard)
		ad_descriptor(api, guard)
		ad_matrix(api)
		for kind in 0 .. 3 {
			for failure in [-1, 129]! { ad_case(api, kind, 130, true, true, true, failure, 0) }
		}
		println('NATIVE-ARRAY-DECODING: 384 Int/String/Date cases, growing owned arrays, shared Decoder boxes, nested conditional conformance, original owned errors and partial Array cleanup before container/Decoder destruction')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn ad_resolve() }
		identities := publishers.wait()
		api := ad_api(false, code, guard)
		for descriptor in identities {
			assert descriptor == api.descriptor
		}
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn ad_worker(api, i) }
		workers.wait()
		unsafe {
			workers.free()
			identities.free()
			publishers.free()
		}
		ad_descriptor(api, guard)
		ad_matrix(api)
		for kind in 0 .. 3 {
			for failure in [-1, 129]! { ad_case(api, kind, 130, true, true, true, failure, 0) }
		}
		for shared in [false, true]! {
			for count in [u64(0), 3]! {
				for failure in [-2, -1]! { ad_case(api, 1, count, true, shared, true, failure, 2) }
			}
		}
		ad_case(api, 1, 3, true, false, true, -1, 1)
		ad_case(api, 1, 3, true, false, true, -1, 4)
		ad_case(api, 1, 9, true, false, true, -1, 5)
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
			assert runtime_symbol(library, '_$sSayxGSesSeRzlMc') == none
		}
		ios_runtime.swift_concurrency_retired = true
		assert swift_array_decoding_symbol('_$sSayxGSesSeRzlMc') == none
		if _ := swift_witness_table_checked(api.descriptor, opaque, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		tables := ios_runtime.swift_array_decoding.values()
		arena := ios_runtime.swift_array_decoding_arena
		objc_stop()
		assert ios_runtime.swift_array_decoding.len == 0 && ios_runtime.swift_array_decoding_arena == 0
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
	println('IOS-ARRAY-DECODING: canonical conditional witnesses and unkeyed decoding, owned element moves and bounded growth, original error transfer and partial Array cleanup, readonly guarded Decoder and unwritten failure result, shared boxes, eight cold publishers/workers, reentrant callbacks and two drained/unmapped lifetimes; nonempty boxed mutable containers remain unsupported')
}
