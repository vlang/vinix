// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.mincore(voidptr, usize, &u8) i32

$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self() u32
	fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
	fn C.mach_port_deallocate(u32, u32) i32
}

type DeLookup = fn (u64, u64, u64) u64
type DeAccess = fn (u64, u64, u64, u64) SwiftAssociatedMetadata
type DeNominal = fn (u64) SwiftAssociatedMetadata
type DeProbe = fn (u64, u64, u64, u64, &u64)

struct DeApi {
	native          bool
	descriptor      u64
	lookup          DeLookup @[required]
	access          DeAccess @[required]
	keys            [2]u64
	values          [3]u64
	hashes          [2]u64
	key_witnesses   [2]u64
	value_witnesses [3]u64
}

fn de_symbol(native bool, library string, name string) u64 {
	if native {
		handle := C.dlopen(&char(library.str), 2)
		assert handle != unsafe { nil }
		address := u64(C.dlsym(handle, unsafe { &char(name.str + 1) }))
		assert address != 0, name
		assert C.dlclose(handle) == 0
		return address
	}
	return runtime_symbol(library, name) or { panic(err) }
}

fn de_relative(field u64) u64 { return u64(i64(field) + i64(i32(read32(field)))) }

fn de_api(native bool, guard u64) DeApi {
	core := '/usr/lib/swift/libswiftCore.dylib'
	foundation := '/System/Library/Frameworks/Foundation.framework/Foundation'
	get := unsafe { DeLookup(voidptr(de_symbol(native, core, '_swift_getWitnessTable'))) }
	access := unsafe { DeAccess(voidptr(de_symbol(native, core, '_$sSDMa'))) }
	string_type := de_symbol(native, core, '_$sSSN')
	integer := de_symbol(native, core, '_$sSiN')
	date_access := unsafe { DeNominal(voidptr(de_symbol(native, foundation, '_$s10Foundation4DateVMa'))) }
	date := date_access(0).metadata
	date_descriptor := de_symbol(native, foundation, '_$s10Foundation4DateVSEAAMc')
	date_table := get(date_descriptor, date, 0)
	string_table := if native { de_symbol(native, core, '_$sSSSEsWP') } else { guard }
	integer_table := if native { de_symbol(native, core, '_$sSiSEsWP') } else { guard + 8 }
	string_hash := if native { de_symbol(native, core, '_$sSSSHsWP') } else { guard + 16 }
	return DeApi{ native: native, descriptor: de_symbol(native, core, '_$sSDyxq_GSEsSERzSER_rlMc'), lookup: get, access: access, keys: [
		string_type,
		integer,
	]!, values: [string_type, integer, date]!, hashes: [string_hash,
		de_symbol(native, core, '_$sSiSHsWP')]!, key_witnesses: [string_table, integer_table]!, value_witnesses: [
		string_table,
		integer_table,
		date_table,
	]! }
}

fn de_protection(address u64, length u64, executable bool) {
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

fn de_descriptor(api DeApi) {
	d := api.descriptor
	assert read32(d + 12) == 0x20200
	protocol := de_relative(d)
	assert unsafe { (&char(voidptr(de_relative(protocol + 8)))).vstring() } == 'Encodable'
	nominal := de_relative(d + 4)
	assert unsafe { (&char(voidptr(de_relative(nominal + 8)))).vstring() } == 'Dictionary'
	for i, parameter in ['x', 'q_']! {
		requirement := d + 16 + u64(i * 12)
		assert read32(requirement) == 0x80 && de_relative(requirement + 8) == protocol
		assert unsafe { (&char(voidptr(de_relative(requirement + 4)))).vstring() } == parameter
	}
	assert read32(d + 40) == 0x50002 && read32(d + 44) == 0
	pattern := de_relative(d + 8)
	assert read64(pattern) == d && read64(pattern + 8) != 0
	if !api.native {
		assert protocol == swift_date_encoding_protocol_symbol('_$sSEMp') or { panic('protocol') }
		assert nominal == ios_runtime.swift_dictionary_metadata_arena + u64(C.getpagesize()) + 160
		cache := de_relative(d + 48)
		for i in 0 .. 16 {
			assert read64(cache + u64(i * 8)) == 0
		}
		de_protection(d, 104, false)
		de_protection(pattern, 16, false)
		de_protection(read64(pattern + 8), 16, true)
	}
}

fn de_matrix(api DeApi, probe DeProbe, guard u64) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	args := base + u64(page) - 16
	mut tables := []u64{}
	for i, key in api.keys {
		for j, value in api.values {
			assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
			unsafe {
				*(&u64(voidptr(args))) = api.key_witnesses[i]
				*(&u64(voidptr(args + 8))) = api.value_witnesses[j]
			}
			assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
			metadata := api.access(0, key, value, api.hashes[i]).metadata
			table := api.lookup(api.descriptor, metadata, args)
			assert table != 0 && table !in tables && table != de_relative(api.descriptor + 8)
			tables << table
			assert read64(table - 8) == api.key_witnesses[i] && read64(table - 16) == api.value_witnesses[j]
			assert read64(table) == api.descriptor && read64(table + 8) == read64(de_relative(api.descriptor + 8) + 8)
			assert C.mprotect(voidptr(base), page, C.PROT_NONE) == 0
			// Cache hits read neither an expired argument array nor its witnesses.
			for expired in [u64(0), args, guard]! {
				for _ in 0 .. 32 {
					assert api.lookup(api.descriptor, metadata, expired) == table
					mut result := [u64(0x1234), 0, 0, 0, 0x5678]!
					probe(api.descriptor, metadata, expired, u64(unsafe { voidptr(api.lookup) }), unsafe { &result[1] })
					assert result == [u64(0x1234), table, 0x5020, 0x5021, 0x5678]!
				}
			}
			if !api.native { de_protection(table - 16, 32, false) }
		}
	}
	unsafe { tables.free() }
	assert C.munmap(voidptr(base), page * 2) == 0
	de_descriptor(api)
}

fn de_resolve() u64 {
	return de_symbol(false, '/usr/lib/swift/libswiftCore.dylib', '_$sSDyxq_GSEsSERzSER_rlMc')
}

fn de_worker(api DeApi) u64 {
	metadata := api.access(0, api.keys[0], api.values[0], api.hashes[0]).metadata
	args := [api.key_witnesses[0], api.value_witnesses[0]]!
	mut answer := u64(0)
	for _ in 0 .. 128 {
		table := api.lookup(api.descriptor, metadata, u64(unsafe { &args[0] }))
		assert answer == 0 || answer == table
		assert read64(table - 8) == args[0] && read64(table - 16) == args[1]
		answer = table
	}
	return answer
}

fn de_reject(descriptor u64, metadata u64, arguments u64) {
	if _ := swift_witness_table_checked(descriptor, metadata, arguments) {
		assert false
	}
}

fn de_invalid(api DeApi, guard u64) {
	before := ios_runtime.swift_dictionary_encoding.len
	for metadata in [u64(0), 1, guard, ~u64(0) - 7]! { de_reject(api.descriptor, metadata, guard) }
	metadata := api.access(0, guard, guard + 8, guard + 16).metadata
	for args in [u64(0), 1, ~u64(0) - 7]! { de_reject(api.descriptor, metadata, args) }
	for i in 0 .. 2 {
		for bad in [u64(0), 1, guard + 1]! {
			mut args := [guard, guard + 8]!
			args[i] = bad
			de_reject(api.descriptor, metadata, u64(unsafe { &args[0] }))
		}
	}
	assert ios_runtime.swift_dictionary_encoding.len == before
	args := [guard, guard + 8]!
	table := api.lookup(api.descriptor, metadata, u64(unsafe { &args[0] }))
	assert read64(table - 8) == guard && read64(table - 16) == guard + 8
	assert ios_runtime.swift_dictionary_encoding.len == before + 1
	// An arbitrary image's generic descriptor still requires full support.
	mut foreign := [u32(0), 0, 0, 0x20200]!
	de_reject(u64(unsafe { &foreign[0] }), guard, guard)
	ios_runtime.swift_concurrency_retired = true
	de_reject(api.descriptor, metadata, guard)
	assert swift_dictionary_encoding_symbol('_$sSDyxq_GSEsSERzSER_rlMc') == none
	ios_runtime.swift_concurrency_retired = false
}

fn de_encoding_diagnostic(api DeApi, guard u64) {
	entry := read64(de_relative(api.descriptor + 8) + 8)
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(fds[0])
		assert C.dup2(fds[1], 2) == 2
		C.close(fds[1])
		unsafe { DeLookup(voidptr(entry))(guard, guard, guard) }
		C._exit(0)
	}
	C.close(fds[1])
	mut bytes := [16384]u8{}
	mut length := 0
	for {
		assert length < bytes.len
		count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0
		length += int(count)
	}
	C.close(fds[0])
	mut status := i32(0)
	assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
	output := unsafe { tos(&bytes[0], length) }
	assert output.contains('iOS: Swift Dictionary encoding is not implemented') && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
}

fn test_swift_dictionary_encoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 56))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { DeProbe(voidptr(code)) }
	$if macos {
		de_matrix(de_api(true, guard), probe, guard)
		println('NATIVE-DICTIONARY-ENCODING: six canonical String/Int keys and String/Int/Date values, conditional requirement descriptors, two private words in reverse order, expired argument cache hits and x20/x21 preservation')
	}
	for _ in 0 .. 2 {
		objc_start()
		de_reject(0, guard, guard)
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn de_resolve() }
		identities := publishers.wait()
		api := de_api(false, guard)
		for descriptor in identities {
			assert descriptor == api.descriptor
		}
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn de_worker(api) }
		tables := workers.wait()
		for table in tables {
			assert table == tables[0]
		}
		assert ios_runtime.swift_dictionary_encoding.len == 1
		de_matrix(api, probe, guard)
		de_invalid(api, guard)
		de_encoding_diagnostic(api, guard)
		for symbol in ['_$sSDyxq_GSEsSERzSER_rlMcSuffix', '_$sSDyxq_GSEsSERzSER_rlWP',
			'_$sSDyxq_GSesSeRzSeR_rlMc']! {
			assert swift_dictionary_encoding_symbol(symbol) == none
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSDyxq_GSEsSERzSER_rlMc') == none
		}
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		allocations := ios_runtime.swift_dictionary_encoding.values()
		metadata := api.access(0, api.keys[0], api.values[0], api.hashes[0]).metadata
		objc_stop()
		assert ios_runtime.swift_dictionary_encoding.len == 0 && ios_runtime.swift_dictionary_metadata_arena == 0 && ios_runtime.swift_dictionary_metadata_retired
		de_reject(api.descriptor, metadata, guard) // Never dereference an unmapped descriptor.
		assert swift_dictionary_encoding_symbol('_$sSDyxq_GSEsSERzSER_rlMc') == none
		for table in allocations {
			$if macos {
				assert C.mprotect(voidptr(table - 16), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(table - 16), page, &resident) == -1
			}
		}
		unsafe {
			allocations.free()
			tables.free()
			workers.free()
			identities.free()
			publishers.free()
		}
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-DICTIONARY-ENCODING: canonical conditional witness specialization, native descriptor/private layout, protected borrowed witnesses and exact argument boundary, expired input cache hits, C ABI x20/x21, sealed publication, eight cold publishers/workers, invalid/foreign/retired rejection, explicit encoding diagnostic and two drained/unmapped lifetimes; serialization remains unsupported')
}
