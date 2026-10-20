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

type DdLookup = fn (u64, u64, u64) u64
type DdAccess = fn (u64, u64, u64, u64) SwiftAssociatedMetadata
type DdNominal = fn (u64) SwiftAssociatedMetadata
type DdProbe = fn (u64, u64, u64, u64, &u64)
type DdDiagnostic = fn (u64, u64)

struct DdApi {
	native          bool
	descriptor      u64
	lookup          DdLookup @[required]
	access          DdAccess @[required]
	keys            [2]u64
	values          [3]u64
	hashes          [2]u64
	key_witnesses   [2]u64
	value_witnesses [3]u64
}

fn dd_symbol(native bool, library string, name string) u64 {
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

fn dd_relative(field u64) u64 { return u64(i64(field) + i64(i32(read32(field)))) }

fn dd_api(native bool, guard u64) DdApi {
	core := '/usr/lib/swift/libswiftCore.dylib'
	foundation := '/System/Library/Frameworks/Foundation.framework/Foundation'
	get := unsafe { DdLookup(voidptr(dd_symbol(native, core, '_swift_getWitnessTable'))) }
	access := unsafe { DdAccess(voidptr(dd_symbol(native, core, '_$sSDMa'))) }
	string_type := dd_symbol(native, core, '_$sSSN')
	integer := dd_symbol(native, core, '_$sSiN')
	date_access := unsafe { DdNominal(voidptr(dd_symbol(native, foundation, '_$s10Foundation4DateVMa'))) }
	date := date_access(0).metadata
	date_descriptor := dd_symbol(native, foundation, '_$s10Foundation4DateVSeAAMc')
	date_table := get(date_descriptor, date, 0)
	string_table := if native { dd_symbol(native, core, '_$sSSSesWP') } else { guard }
	integer_table := if native { dd_symbol(native, core, '_$sSiSesWP') } else { guard + 8 }
	string_hash := if native { dd_symbol(native, core, '_$sSSSHsWP') } else { guard + 16 }
	return DdApi{
		native:          native
		descriptor:      dd_symbol(native, core, '_$sSDyxq_GSesSeRzSeR_rlMc')
		lookup:          get
		access:          access
		keys:            [
			string_type,
			integer,
		]!
		values:          [string_type, integer, date]!
		hashes:          [string_hash, dd_symbol(native, core, '_$sSiSHsWP')]!
		key_witnesses:   [string_table, integer_table]!
		value_witnesses: [
			string_table,
			integer_table,
			date_table,
		]!
	}
}

fn dd_protection(address u64, length u64, executable bool) {
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

fn dd_descriptor(api DdApi) {
	d := api.descriptor
	assert read32(d + 12) == 0x20200
	protocol := dd_relative(d)
	assert unsafe { (&char(voidptr(dd_relative(protocol + 8)))).vstring() } == 'Decodable'
	nominal := dd_relative(d + 4)
	assert unsafe { (&char(voidptr(dd_relative(nominal + 8)))).vstring() } == 'Dictionary'
	for i, parameter in ['x', 'q_']! {
		requirement := d + 16 + u64(i * 12)
		assert read32(requirement) == 0x80 && dd_relative(requirement + 8) == protocol
		assert unsafe { (&char(voidptr(dd_relative(requirement + 4)))).vstring() } == parameter
	}
	assert read32(d + 40) == 0x50002 && read32(d + 44) == 0
	pattern := dd_relative(d + 8)
	assert read64(pattern) == d && read64(pattern + 8) != 0
	if !api.native {
		assert protocol == swift_date_decoding_protocol_symbol('_$sSeMp') or { panic('protocol') }
		assert nominal == ios_runtime.swift_dictionary_metadata_arena + u64(C.getpagesize()) + 160
		cache := dd_relative(d + 48)
		for i in 0 .. 16 {
			assert read64(cache + u64(i * 8)) == 0
		}
		dd_protection(d, 104, false)
		dd_protection(pattern, 16, false)
		dd_protection(read64(pattern + 8), 16, true)
	}
}

fn dd_matrix(api DdApi, probe DdProbe, guard u64) {
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
			assert table != 0 && table !in tables && table != dd_relative(api.descriptor + 8)
			tables << table
			assert read64(table - 8) == api.key_witnesses[i] && read64(table - 16) == api.value_witnesses[j]
			assert read64(table) == api.descriptor && read64(table + 8) == read64(dd_relative(api.descriptor + 8) + 8)
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
			if !api.native { dd_protection(table - 16, 32, false) }
		}
	}
	unsafe { tables.free() }
	assert C.munmap(voidptr(base), page * 2) == 0
	dd_descriptor(api)
}

fn dd_resolve() u64 {
	return dd_symbol(false, '/usr/lib/swift/libswiftCore.dylib', '_$sSDyxq_GSesSeRzSeR_rlMc')
}

fn dd_isolation(api DdApi) u64 {
	core := '/usr/lib/swift/libswiftCore.dylib'
	other := dd_symbol(api.native, core, '_$sSDyxq_GSEsSERzSER_rlMc')
	metadata := api.access(0, api.keys[0], api.values[0], api.hashes[0]).metadata
	witness := if api.native {
		dd_symbol(true, core, '_$sSSSEsWP')
	} else {
		api.key_witnesses[0] + 64
	}
	args := [witness, witness]!
	encoded := api.lookup(other, metadata, u64(unsafe { &args[0] }))
	decoded := api.lookup(api.descriptor, metadata, 0)
	assert other != api.descriptor && encoded != decoded
	assert read64(encoded) == other && read64(decoded) == api.descriptor
	assert read64(encoded + 8) != read64(decoded + 8)
	assert read64(encoded - 8) == witness && read64(encoded - 16) == witness
	assert read64(decoded - 8) == api.key_witnesses[0] && read64(decoded - 16) == api.value_witnesses[0]
	assert api.lookup(other, metadata, 0) == encoded
	return encoded
}

fn dd_worker(api DdApi) u64 {
	metadata := api.access(0, api.keys[0], api.values[0], api.hashes[0]).metadata
	args := [api.key_witnesses[0], api.value_witnesses[0]]!
	mut answer := u64(0)
	for _ in 0 .. 128 {
		table := api.lookup(api.descriptor, metadata, u64(unsafe { &args[0] }))
		assert answer == 0 || answer == table
		assert read64(table - 8) == args[0] && read64(table - 16) == args[1]
		assert dd_isolation(api) != table
		answer = table
	}
	return answer
}

fn dd_reject(descriptor u64, metadata u64, arguments u64) {
	if _ := swift_witness_table_checked(descriptor, metadata, arguments) {
		assert false
	}
}

fn dd_invalid(api DdApi, guard u64) {
	before := ios_runtime.swift_dictionary_decoding.len
	for metadata in [u64(0), 1, guard, ~u64(0) - 7]! { dd_reject(api.descriptor, metadata, guard) }
	metadata := api.access(0, guard, guard + 8, guard + 16).metadata
	for args in [u64(0), 1, ~u64(0) - 7]! { dd_reject(api.descriptor, metadata, args) }
	for i in 0 .. 2 {
		for bad in [u64(0), 1, guard + 1]! {
			mut args := [guard, guard + 8]!
			args[i] = bad
			dd_reject(api.descriptor, metadata, u64(unsafe { &args[0] }))
		}
	}
	assert ios_runtime.swift_dictionary_decoding.len == before
	args := [guard, guard + 8]!
	table := api.lookup(api.descriptor, metadata, u64(unsafe { &args[0] }))
	assert read64(table - 8) == guard && read64(table - 16) == guard + 8
	assert ios_runtime.swift_dictionary_decoding.len == before + 1
	// An arbitrary image's generic descriptor still requires full support.
	mut foreign := [u32(0), 0, 0, 0x20200]!
	dd_reject(u64(unsafe { &foreign[0] }), guard, guard)
	ios_runtime.swift_concurrency_retired = true
	dd_reject(api.descriptor, metadata, guard)
	assert swift_dictionary_decoding_symbol('_$sSDyxq_GSesSeRzSeR_rlMc') == none
	ios_runtime.swift_concurrency_retired = false
}

fn dd_decoding_diagnostic(api DdApi, guard u64, code u64) {
	entry := read64(dd_relative(api.descriptor + 8) + 8)
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(fds[0])
		assert C.dup2(fds[1], 2) == 2
		C.close(fds[1])
		// Forward a protected result buffer in x8. The unsupported initializer
		// must diagnose without writing output or inspecting the Decoder.
		unsafe { DdDiagnostic(voidptr(code + 64))(guard, entry) }
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
	assert output.contains('iOS: Swift Dictionary decoding is not implemented') && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
}

fn test_swift_dictionary_decoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 64, 0xaa0003e8) // mov x8, x0
	write32(code + 68, 0xd61f0020) // br x1
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 72))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { DdProbe(voidptr(code)) }
	$if macos {
		api := dd_api(true, guard)
		dd_matrix(api, probe, guard)
		dd_isolation(api)
		println('NATIVE-DICTIONARY-DECODING: six canonical String/Int keys and String/Int/Date values, conditional requirement descriptors, two private words in reverse order, expired argument cache hits, distinct Encodable/Decodable tables and x20/x21 preservation')
	}
	if _ := swift_dictionary_decoding_table_checked(guard, guard) {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		dd_reject(0, guard, guard)
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn dd_resolve() }
		identities := publishers.wait()
		api := dd_api(false, guard)
		for descriptor in identities {
			assert descriptor == api.descriptor
		}
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn dd_worker(api) }
		tables := workers.wait()
		for table in tables {
			assert table == tables[0]
		}
		assert ios_runtime.swift_dictionary_decoding.len == 1 && ios_runtime.swift_dictionary_encoding.len == 1
		dd_matrix(api, probe, guard)
		dd_invalid(api, guard)
		dd_decoding_diagnostic(api, guard, code)
		for symbol in ['_$sSDyxq_GSesSeRzSeR_rlMcSuffix', '_$sSDyxq_GSesSeRzSeR_rlWP',
			'_$sSDyxq_GSEsSERzSER_rlMc']! {
			assert swift_dictionary_decoding_symbol(symbol) == none
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSDyxq_GSesSeRzSeR_rlMc') == none
		}
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		allocations := ios_runtime.swift_dictionary_decoding.values()
		encoded := dd_isolation(api)
		encoding_descriptor := ios_runtime.swift_dictionary_encoding_descriptor
		metadata := api.access(0, api.keys[0], api.values[0], api.hashes[0]).metadata
		objc_stop()
		assert ios_runtime.swift_dictionary_decoding.len == 0 && ios_runtime.swift_dictionary_encoding.len == 0 && ios_runtime.swift_dictionary_metadata_arena == 0 && ios_runtime.swift_dictionary_metadata_retired
		dd_reject(api.descriptor, metadata, guard) // Never dereference an unmapped descriptor.
		dd_reject(encoding_descriptor, metadata, guard)
		assert swift_dictionary_decoding_symbol('_$sSDyxq_GSesSeRzSeR_rlMc') == none
		for table in allocations {
			$if macos {
				assert C.mprotect(voidptr(table - 16), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(table - 16), page, &resident) == -1
			}
		}
		$if macos {
			assert C.mprotect(voidptr(encoded - 16), page, C.PROT_READ) == -1
		} $else {
			mut resident := u8(0)
			assert C.mincore(voidptr(encoded - 16), page, &resident) == -1
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
	println('IOS-DICTIONARY-DECODING: canonical conditional witness specialization, native descriptor/private layout, protected borrowed witnesses and exact argument boundary, expired input cache hits, C ABI x20/x21, sealed publication, eight cold publishers/mixed workers, independent Encodable/Decodable caches, invalid/foreign/retired rejection, explicit decoding diagnostic with protected x8 output and two drained/unmapped lifetimes; serialization remains unsupported')
}
