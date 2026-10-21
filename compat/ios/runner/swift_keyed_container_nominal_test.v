// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
$if macos {
	#include <mach/mach.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32
type KcnAccess = fn (u64, u64, u64) SwiftAssociatedMetadata
type KcnFactory = fn (u64, u64, u64) u64

fn kcn_relative(p u64) u64 { return u64(i64(p) + i64(i32(read32(p)))) }
fn kcn_protocol(p u64) u64 {
	value := kcn_relative(p)
	return if value & 1 == 0 { value } else { read64(value - 1) }
}
fn kcn_graph(d u64) {
	assert read32(d) & 0xffff == 0xd1
	assert unsafe { (&char(kcn_relative(d + 8))).vstring() } == 'KeyedDecodingContainer'
	module_descriptor := kcn_relative(d + 4)
	assert read32(module_descriptor) == 0 && unsafe { (&char(kcn_relative(module_descriptor + 8))).vstring() } == 'Swift'
	assert read32(d + 20) == 1 && read32(d + 24) == 4
	assert read32(d + 36) == 0x10001 && read32(d + 40) == 2
	assert read32(d + 44) == 0x80 && read32(d + 48) == 0x80
	assert unsafe { (&char(kcn_relative(d + 52))).vstring() } == 'x'
	assert kcn_relative(d + 12) & 3 == 0 && kcn_relative(d + 28) & 7 == 0
	pattern := kcn_relative(d + 32)
	// Native patterns may also carry extra data and trailing specialization flags.
	assert read32(pattern) != 0 && read32(pattern + 8) >> 21 == 0x200
	protocol := kcn_protocol(d + 56)
	assert read32(protocol) == 0x30043 && read32(protocol + 12) == 2 && read32(protocol + 16) == 6
	assert unsafe { (&char(kcn_relative(protocol + 8))).vstring() } == 'CodingKey'
	for i, name in ['CustomDebugStringConvertible', 'CustomStringConvertible']! {
		r := protocol + 24 + u64(i * 12)
		assert read32(r) == 0x80
		parent := kcn_protocol(r + 8)
		assert read32(parent) == 0x30043 && read32(parent + 12) == 0 && read32(parent + 16) == 1
		assert read32(parent + 24) & 0xffff == 0x13
		assert unsafe { (&char(kcn_relative(parent + 8))).vstring() } == name
	}
	for i, flags in [u32(0), 0, 0xdcb00013, 0x32b70002, 0xbeb70013, 0xf36c0002]! { assert read32(protocol + 48 + u64(i * 8)) == flags }
}
fn kcn_response(d u64, entry KcnAccess, key u64, witness u64) u64 {
	from_descriptor := unsafe { KcnAccess(voidptr(kcn_relative(d + 12))) }
	metadata := entry(0, key, witness).metadata
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		for access in [entry, from_descriptor]! {
			r := access(request, key, witness)
			assert r.metadata == metadata && r.state == 0 && read64(r.metadata + 8) == d
		}
	}
	assert read64(metadata + 16) == key && read64(metadata + 24) == witness
	return metadata
}
fn kcn_mapping(address u64, protection int) {
	$if macos {
		mut start := address;mut size := u64(0);mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object := u32(0);task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if protection == 0 { assert status != 0 || start > address }
		else { assert status == 0 && start <= address && address + 60 <= start + size && info[0] == protection }
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields();if fields.len < 2 { continue };range := fields[0].split('-');if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) };end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end { assert protection != 0 && fields[1] == if protection == C.PROT_READ { 'r--p' } else { 'r-xp' };found = true;break }
		}
		assert found == (protection != 0)
	}
}
fn kcn_publish() u64 {
	mut descriptor := u64(0)
	for _ in 0 .. 128 { descriptor = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22KeyedDecodingContainerVMn') or { panic(err) } }
	return descriptor
}
fn test_swift_keyed_container_nominal() {
	page := usize(C.getpagesize());guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert guard != u64(-1)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
		d := u64(C.dlsym(core, c'$ss22KeyedDecodingContainerVMn'));assert d != 0;kcn_graph(d)
		assert kcn_protocol(kcn_protocol(d + 56) + 44) == u64(C.dlsym(core, c'$ss23CustomStringConvertibleMp'))
		kcn_response(d, unsafe { KcnAccess(C.dlsym(core, c'$ss22KeyedDecodingContainerVMa')) }, u64(C.dlsym(core, c'$sSiN')), guard + 8)
		println('NATIVE-KEYED-CONTAINER-NOMINAL: Swift nominal identity, one K/two key arguments, CodingKey inheritance and six requirements, instantiation pattern and direct/descriptor complete responses')
	}
	assert swift_keyed_container_metadata_symbol('_$ss22KeyedDecodingContainerVMn') == none
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{};for _ in 0 .. 8 { workers << spawn kcn_publish() }
		values := workers.wait();d := values[0];for v in values { assert v == d };unsafe { workers.free();values.free() }
		kcn_graph(d);kcn_mapping(d, C.PROT_READ)
		coding_key := kcn_protocol(d + 56)
		string_protocol := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss23CustomStringConvertibleMp') or { panic(err) }
		assert kcn_protocol(coding_key + 44) == string_protocol
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22KeyedDecodingContainerVMa') or { panic(err) }
		assert kcn_relative(d + 12) == entry;kcn_mapping(entry, C.PROT_READ | C.PROT_EXEC)
		metadata := kcn_response(d, unsafe { KcnAccess(voidptr(entry)) }, guard, guard + 8);kcn_mapping(metadata, C.PROT_READ)
		// The factory reads exactly two borrowed words, even at a page boundary.
		for tail in [false, true]! {
			region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert region != u64(-1)
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
			args := region + u64(page) + if tail { u64(page) - 16 } else { u64(0) }
			unsafe { *(&u64(args)) = guard;*(&u64(args + 8)) = guard + 8 }
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0
			pattern := kcn_relative(d + 32);factory := unsafe { KcnFactory(voidptr(kcn_relative(pattern))) }
			assert factory(d, args, pattern) == metadata
			assert C.munmap(voidptr(region), page * 3) == 0
		}
		// Generic descriptors cannot be invoked through the nongeneric ABI.
		if _ := swift_mangled_nominal_request(d, 0) { assert false }
		for symbol in ['_$ss22KeyedDecodingContainerVN', '_$ss22KeyedEncodingContainerVN', '_$ss9CodingKeyMp']! { assert swift_keyed_container_metadata_symbol(symbol) == none }
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$ss22KeyedDecodingContainerVMn') == none
		ios_runtime.swift_concurrency_retired = true;assert swift_keyed_container_metadata_symbol('_$ss22KeyedDecodingContainerVMn') == none
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_keyed_container_metadata.len == 1 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		objc_stop();kcn_mapping(d, 0);kcn_mapping(entry, 0);kcn_mapping(metadata, 0)
		assert ios_runtime.swift_keyed_container_arena == 0 && swift_keyed_container_metadata_symbol('_$ss22KeyedDecodingContainerVMn') == none
	}
	assert C.munmap(voidptr(guard), page) == 0
	println('IOS-KEYED-CONTAINER-NOMINAL: canonical RO descriptor/metadata and RX accessor, native CodingKey declaration graph, guarded factory arguments and generic-ABI rejection; eight cold publishers and two drained/unmapped lifetimes')
}
