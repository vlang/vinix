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

type KseProbe = fn (u64, u64, u64, u64, u64, u64, u64, u64)
type KseSign = fn (u64, u64) u64
type KseLiteral = fn (&u8, i64, bool) SwiftStringWords
type KseRelease = fn (u64)

fn kse_pair(load bool, vector bool, first u32, second u32, base u32, offset int) u32 {
	width := if vector { 16 } else { 8 }
	assert offset % width == 0 && offset >= 0 && offset / width < 64
	return (if vector { u32(0xad000000) } else { u32(0xa9000000) })
		| (if load { u32(0x00400000) } else { u32(0) }) | (u32(offset / width) << 15)
		| (second << 10) | (base << 5) | first
}
fn kse_store(register u32, base u32, offset u32) u32 {
	assert offset % 8 == 0
	return 0xf9000000 | ((offset / 8) << 10) | (base << 5) | register
}
fn kse_mov(register u32, value u32) u32 { return 0xd2800000 | (value << 5) | register }

fn kse_code(code u64) {
	mut ops := [u32(0xa9ba7bfd)]
	for i in 0 .. 5 { ops << kse_pair(false, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16) }
	// Ordinary C probe -> Swift String encoder with borrowed container/key/metadata.
	ops << [u32(0xaa0003f0), 0xaa0103f4, 0xaa0203e2, 0xaa0303e3, 0xaa0503f3,
		0xaa0603f5, 0xaa0703e8, 0xaa0403e7]
	for register in u32(4) .. 7 { ops << kse_mov(register, 0x5100 + register) }
	ops << kse_pair(true, false, 0, 1, 7, 224) // Borrowed two-word String argument.
	pc := code + u64(ops.len * 4);distance := u32(code + 640 - pc)
	ops << u32(0x10000017 | ((distance & 3) << 29) | ((distance >> 2) << 5))
	for i in 0 .. 4 { ops << kse_pair(true, true, u32(i * 2), u32(i * 2 + 1), 23, i * 32) }
	ops << u32(0xd63f0200)
	ops << kse_pair(false, false, 0, 1, 19, 0)
	ops << kse_pair(false, false, 20, 21, 19, 16)
	ops << kse_store(8, 19, 32)
	for i in 0 .. 4 { ops << kse_pair(false, true, u32(i * 2), u32(i * 2 + 1), 19, 48 + i * 32) }
	for i in 0 .. 5 { ops << kse_pair(true, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16) }
	ops << [u32(0xa8c67bfd), 0xd65f03c0]
	assert ops.len * 4 <= 256
	for i, op in ops { write32(code + u64(i * 4), op) }
	mut method := []u32{}
	for register in u32(0) .. 9 { method << kse_store(register, 7, register * 8) }
	method << kse_pair(false, false, 20, 21, 7, 72)
	for i in 0 .. 4 { method << kse_pair(false, true, u32(i * 2), u32(i * 2 + 1), 7, 96 + i * 32) }
	method << kse_pair(true, false, 0, 1, 7, 224)
	method << u32(0xf94078f5) // ldr x21,[x7,#240]: exact success/error channel.
	method << u32(0xd65f03c0)
	assert method.len * 4 <= 128
	for i, op in method { write32(code + 256 + u64(i * 4), op) }
	write32(code + 512, 0xdac10020);write32(code + 516, 0xd65f03c0) // pacia x0,x1
	write32(code + 528, 0xdac10820);write32(code + 532, 0xd65f03c0) // pacda x0,x1
	for i in 0 .. 16 { unsafe { *(&u64(code + 640 + u64(i * 8))) = u64(0x12340000 + i) } }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 768))
}

fn kse_case(entry u64, container u64, box u64, metadata u64, key_type u64,
	key_table u64, guard u64, probe KseProbe, words SwiftStringWords, thrown u64, incoming u64) {
	mut observed := [34]u64{}
	mut output := [26]u64{}
	observed[28] = words.first;observed[29] = words.second;observed[30] = thrown
	observed[31] = 0xCAFE;output[0] = 0xCAFE;output[25] = 0xBEEF
	probe(entry, container, guard, metadata, u64(unsafe { &observed[0] }), u64(unsafe { &output[1] }), incoming, guard)
	assert observed[0] == words.first && observed[1] == words.second
	assert observed[2] == guard && observed[3] == key_type && observed[4] == key_table
	for i in 5 .. 7 { assert observed[i] == u64(0x5100 + i) }
	assert observed[7] == u64(unsafe { &observed[0] }) && observed[8] == key_type
	assert observed[9] == box && observed[10] == incoming
	// Void has no result registers; only the callback arguments are significant.
	assert output[3] == container && output[4] == thrown && output[5] == key_type
	for i in 0 .. 16 { assert observed[12 + i] == u64(0x12340000 + i) && output[7 + i] == u64(0x12340000 + i) }
	assert observed[28] == words.first && observed[29] == words.second && observed[30] == thrown
	assert observed[31] == 0xCAFE && output[0] == 0xCAFE && output[25] == 0xBEEF
}

fn kse_worker(entry u64, container u64, box u64, metadata u64, key_type u64,
	key_table u64, guard u64, probe KseProbe, words SwiftStringWords) {
	for _ in 0 .. 64 { kse_case(entry, container, box, metadata, key_type, key_table, guard, probe, words, 0, 0) }
}

fn kse_spans(entry u64, code u64, native bool, literal KseLiteral, release KseRelease) {
	page := usize(C.getpagesize());probe := unsafe { KseProbe(voidptr(code)) }
	for placement in 0 .. 16 {
		mut regions := [4]u64{}
		mut spans := [4]u64{}
		for i in 0 .. 4 {
			regions[i] = u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
			assert regions[i] != u64(-1)
			assert C.mprotect(voidptr(regions[i] + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
			length := if i == 2 { u64(16) } else { u64(8) }
			spans[i] = regions[i] + u64(page) + if placement & (1 << i) != 0 { u64(page) - length } else { u64(0) }
		}
		container := spans[0];box := spans[1];metadata := spans[2] - 16;slot := spans[3]
		guard := regions[0];key_type := guard + 16;key_table := guard + 32
		mut isa := slot - 112;mut target := code + 256
		$if macos {
			if native {
				isa = unsafe { KseSign(voidptr(code + 528)) }(isa, box | (u64(0x6ae1) << 48))
				target = unsafe { KseSign(voidptr(code + 512)) }(target, slot | (u64(0x55f3) << 48))
			}
		}
		unsafe {
			*(&u64(container)) = box;*(&u64(box)) = isa;*(&u64(slot)) = target
			*(&u64(metadata + 16)) = key_type;*(&u64(metadata + 24)) = key_table
		}
		for region in regions { assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0 }
		for text in ['', 'hello', 'long borrowed String argument exceeds inline storage 🎮']! {
			words := literal(text.str, text.len, text.is_ascii())
			for incoming in [u64(0), 0xAB21]! {
				for thrown in [u64(0), 0xDE21]! {
					kse_case(entry, container, box, metadata, key_type, key_table, guard, probe, words, thrown, incoming)
				}
			}
			mut workers := []thread{}
			for _ in 0 .. 8 { workers << spawn kse_worker(entry, container, box, metadata, key_type, key_table, guard, probe, words) }
			workers.wait();unsafe { workers.free() }
			release(words.second)
		}
		opaque := SwiftStringWords{first:guard + 64, second:guard + 128}
		kse_case(entry, container, box, metadata, key_type, key_table, guard, probe, opaque, 0, 0)
		assert read64(container) == box && read64(box) == isa && read64(slot) == target
		assert read64(metadata + 16) == key_type && read64(metadata + 24) == key_table
		for region in regions { assert C.munmap(voidptr(region), page * 3) == 0 }
	}
}

fn kse_mapping(address u64, mapped bool) {
	$if macos {
		mut start := address;mut size := u64(0);mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped { assert status == 0 && start <= address && address + 48 <= start + size && info[0] == C.PROT_READ | C.PROT_EXEC }
		else { assert status != 0 || start > address }
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields();if fields.len < 2 { continue };range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) };end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end { assert mapped && address + 48 <= end && fields[1] == 'r-xp';found = true;break }
		}
		assert found == mapped
	}
}

fn kse_publish() u64 {
	mut entry := u64(0)
	for _ in 0 .. 128 { entry = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22KeyedEncodingContainerV6encode_6forKeyySS_xtKF') or { panic(err) } }
	return entry
}

fn test_swift_keyed_string_encoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1);kse_code(code);assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		handle := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert handle != unsafe { nil }
		entry := u64(C.dlsym(handle, c'$ss22KeyedEncodingContainerV6encode_6forKeyySS_xtKF'))
		literal_address := C.dlsym(handle, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')
		release_address := C.dlsym(handle, c'swift_bridgeObjectRelease')
		assert entry != 0 && literal_address != unsafe { nil } && release_address != unsafe { nil }
		literal := unsafe { KseLiteral(literal_address) }
		release := unsafe { KseRelease(release_address) }
		kse_spans(entry, code, true, literal, release)
		println('NATIVE-KEYED-STRING-ENCODING: slot112; borrowed String x0/x1, key x2 and metadata; x3/x4/x8 generic arguments, box x20 and restored caller context; exact x21 success/error; protected header/slot/type spans and eight readers')
	}
	if _ := swift_keyed_string_encoding_symbol('_$ss22KeyedEncodingContainerV6encode_6forKeyySS_xtKF') { assert false }
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn kse_publish() }
		entries := publishers.wait();entry := entries[0]
		for value in entries { assert value == entry }
		unsafe { publishers.free();entries.free() }
		assert entry == ios_runtime.swift_hash_code + 1600;kse_mapping(entry, true)
		kse_spans(entry, code, false, swift_string_literal, swift_bridge_release)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0
		ios_runtime.swift_concurrency_retired = true;assert swift_keyed_string_encoding_symbol('_$ss22KeyedEncodingContainerV6encode_6forKeyySS_xtKF') == none
		ios_runtime.swift_concurrency_retired = false
		for symbol in ['_$ss22KeyedEncodingContainerV6encode_6forKeyySi_xtKF', '_$ss22KeyedEncodingContainerVMa']! {
			if _ := swift_keyed_string_encoding_symbol(symbol) { assert false }
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$ss22KeyedEncodingContainerV6encode_6forKeyySS_xtKF') { assert false }
		objc_stop();assert ios_runtime.swift_hash_code == 0;kse_mapping(entry, false)
		if _ := swift_keyed_string_encoding_symbol('_$ss22KeyedEncodingContainerV6encode_6forKeyySS_xtKF') { assert false }
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-KEYED-STRING-ENCODING: real box slot112 dispatch, borrowed spans without ARC or key/String storage reads, scalar/vector forwarding and original error channel; inline/long/opaque Strings, eight publishers/readers and two drained/unmapped lifetimes; JSON backend remains unsupported')
}
