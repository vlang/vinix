// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type OmAccess = fn (u64, u64) SwiftAssociatedMetadata
type OmGuard = fn (u64, u64, u64, u64, u64, &u64)
type OmCString = fn (&char) SwiftStringWords
type OmRelease = fn (u64)

struct OmApi {
	native bool
	access u64
	code   u64
}

fn om_symbol(native bool, symbol string) u64 {
	$if macos {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			result := u64(C.dlsym(library, symbol[1..].str))
			assert result != 0, symbol
			return result
		}
	}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
}

fn om_call(code u64, a u64, b u64, c u64, d u64, function u64) [4]u64 {
	mut output := [4]u64{}
	unsafe { OmGuard(voidptr(code))(a, b, c, d, function, &output[0]) }
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output
}

fn om_metadata(api OmApi, wrapped u64) u64 {
	mut metadata := u64(0)
	for request in [u64(0), 0xff, 0x100, 0x1ff, ~u64(0)]! {
		response := om_call(api.code, request, wrapped, 0, 0, api.access)
		assert response[0] != 0 && response[1] == 0
		if metadata != 0 {
			assert metadata == response[0]
		}
		metadata = response[0]
	}
	assert read64(metadata) == 0x202 && read64(metadata + 16) == wrapped
	assert read64(metadata + 8) == om_symbol(api.native, '_$sSqMn')
	wrapped_witness := read64(wrapped - 8) & 0x0000ffffffffffff
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	extra := read32(wrapped_witness + 84)
	size := read64(wrapped_witness + 64) + if extra == 0 { u64(1) } else { u64(0) }
	align := u64(read32(wrapped_witness + 80) & 255) + 1
	assert read64(witness + 64) == size && read64(witness + 72) == (size + align - 1) & ~(align - 1)
	assert read32(witness + 84) == if extra == 0 { u32(0) } else { extra - u32(1) }
	assert read32(witness + 80) == read32(wrapped_witness + 80) | u32(0x200000)
	return metadata
}

fn om_entry(metadata u64, slot int) u64 {
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	return read64(witness + u64(slot * 8)) & 0x0000ffffffffffff
}

fn om_mix(hash u64, value u64) u64 { return (hash ^ value) * u64(1099511628211) }

// Compare complete byte footprints and returned tags against the installed
// native generic Optional witnesses. Guard pages catch accidental widening.
fn om_matrix(api OmApi, metadata u64) u64 {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 4) == 0 }
	for offset in [usize(0), page * 2]! {
		assert C.mprotect(voidptr(span + u64(offset)), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	size := read64(witness + 64)
	extra := read32(witness + 84)
	alignment := u64(read32(witness + 80) & 255) + 1
	stride := (size + alignment - 1) & ~(alignment - 1)
	mut hash := u64(14695981039346656037)
	for cases in [u32(0), 1, 2, 252, 253, 254, 255, 256, 65278, 65279, 65535, 65536, 0x00fffeff,
		0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff, extra]! {
		// Reserve four bytes for the tag and verify untouched trailing bytes.
		destination := span + u64(page) - ((size + 4 + alignment - 1) & ~(alignment - 1))
		for which in [u32(0), 1, 2, 253, 254, 255, 256, 65535, 65536, 0x7ffffffe, 0x80000000,
			0xfffffffe, 0xffffffff]! {
			C.memset(voidptr(destination - 1), 0x67, usize(size + 5))
			om_call(api.code, destination, which, cases, metadata, om_entry(metadata, 7))
			assert unsafe { *(&u8(destination - 1)) } == 0x67
			for i in u64(0) .. size + 4 {
				hash = om_mix(hash, u64(unsafe { *(&u8(destination + i)) }))
			}
			result := om_call(api.code, destination, cases, metadata, 0, om_entry(metadata, 6))
			hash = om_mix(hash, u64(u32(result[0])))
		}
	}
	if read32(witness + 80) & 0x10000 != 0 { return hash }
	// Valid Optional.some/nil values only; arbitrary extra inhabitants are
	// used above through the single-payload operations that define them.
	for nil_value in [false, true]! {
		source := span + u64(page) - stride
		destination := span + u64(page * 3) - stride
		assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(source), 0, usize(size))
		om_call(api.code, source, if nil_value { u64(1) } else { u64(0) }, metadata, 0, om_entry(metadata, 13))
		assert u32(om_call(api.code, source, metadata, 0, 0, om_entry(metadata, 11))[0]) == if nil_value {
			u32(1)
		} else {
			u32(0)
		}
		assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
		// POD payloads exercise all operations; String values are checked with
		// actual owners separately rather than manufacturing String bit patterns.
		if read32(witness + 80) & 0x10000 == 0 {
			for slot in [0, 2, 3, 4, 5]! {
				C.memset(voidptr(destination - 1), 0x5a, usize(size + 1))
				if slot in [3, 5]! {
					C.memset(voidptr(destination), 0, usize(size))
					om_call(api.code, destination, 1, metadata, 0, om_entry(metadata, 13))
				}
				assert om_call(api.code, destination, source, metadata, 0, om_entry(metadata, slot))[0] == destination
				assert C.memcmp(voidptr(destination), voidptr(source), usize(size)) == 0
				assert unsafe { *(&u8(destination - 1)) } == 0x5a
				om_call(api.code, destination, metadata, 0, 0, om_entry(metadata, 1))
			}
		}
		om_call(api.code, source, metadata, 0, 0, om_entry(metadata, 12)) // projection is a no-op
	}
	return hash
}

fn om_strings(api OmApi) {
	wrapped := om_symbol(api.native, '_$sSSN')
	metadata := om_metadata(api, wrapped)
	release := unsafe { OmRelease(voidptr(om_symbol(api.native, '_swift_bridgeObjectRelease'))) }
	for slot in [0, 2, 3, 4, 5]! {
		for old_nil in [false, true]! {
			for new_nil in [false, true]! {
				text := 'Optional payload with a real owned long String allocation'
				mut words := SwiftStringWords{}
				if api.native {
					words = unsafe { OmCString(voidptr(om_symbol(true, '_$sSS7cStringSSSPys4Int8VG_tcfC')))(text.str) }
				} else {
					words = swift_interpolation_init(i64(text.len), 0)
					swift_string_append_bytes(u64(unsafe { &words }), u64(text.str), u64(text.len))
				}
				mut source := [words.first, words.second]!
				mut destination := [u64(0), 0]!
				src := u64(unsafe { &source[0] })
				dst := u64(unsafe { &destination[0] })
				if new_nil { om_call(api.code, src, 1, metadata, 0, om_entry(metadata, 13)) }
				if slot in [3, 5]! {
					if !old_nil {
						om_call(api.code, dst, u64(unsafe { &words }), metadata, 0, om_entry(metadata, 2))
					} else {
						om_call(api.code, dst, 1, metadata, 0, om_entry(metadata, 13))
					}
				}
				assert om_call(api.code, dst, src, metadata, 0, om_entry(metadata, slot))[0] == dst
				assert u32(om_call(api.code, dst, metadata, 0, 0, om_entry(metadata, 11))[0]) == if new_nil {
					u32(1)
				} else {
					u32(0)
				}
				if !new_nil {
					assert destination == source
				}
				if !new_nil && slot in [4, 5]! {
					// Taking consumed the source owner; keep one independent reference
					// only for the cases where it wasn't owned by the source (nil).
					assert read64(words.second + 8) >> 33 == 0
				} else {
					assert read64(words.second + 8) >> 33 == if new_nil { u64(0) } else { u64(1) }
				}
				om_call(api.code, dst, metadata, 0, 0, om_entry(metadata, 1))
				if new_nil {
					release(words.second)
				} else if slot !in [4, 5]! {
					om_call(api.code, src, metadata, 0, 0, om_entry(metadata, 1))
				}
			}
		}
	}
}

fn om_publish(wrapped u64) u64 { return swift_optional_access(0, wrapped).metadata }

fn om_worker(api OmApi, wrapped u64) {
	for _ in 0 .. 32 {
		assert om_metadata(api, wrapped) == swift_optional_access(0, wrapped).metadata
	}
}

__global (
	om_retiring_destination u64
	om_retiring_metadata    u64
	om_retiring_calls       u64
)

fn om_reentrant_destroy(value u64, _metadata u64) {
	assert read64(value) == 0x1234
	assert swift_optional_tag(om_retiring_destination, om_retiring_metadata) == 1
	worker := spawn om_publish(swift_integer_metadata())
	assert worker.wait() == swift_optional_access(0, swift_integer_metadata()).metadata
	om_retiring_calls++
}

fn om_reentrant() {
	mut witness := [14]u64{}
	for i in 0 .. 8 { witness[i] = u64(unsafe { voidptr(swift_integer_copy) }) }
	witness[1] = u64(unsafe { voidptr(om_reentrant_destroy) })
	witness[6] = u64(unsafe { voidptr(swift_integer_enum_get) })
	witness[7] = u64(unsafe { voidptr(swift_integer_enum_store) })
	witness[8] = 8
	witness[9] = 8
	witness[10] = 0x10007
	mut full := [u64(unsafe { &witness[0] }), 0x200, 0]!
	wrapped := u64(unsafe { &full[1] })
	metadata := swift_optional_access(0, wrapped).metadata
	mut destination := [u64(0x1234), 0]!
	mut source := [u64(0), 1]!
	om_retiring_destination = u64(unsafe { &destination[0] })
	om_retiring_metadata = metadata
	om_retiring_calls = 0
	for taking in [false, true]! {
		destination[0] = 0x1234
		destination[1] = 0
		swift_optional_assign(om_retiring_destination, u64(unsafe { &source[0] }), metadata, taking)
		assert destination == source
	}
	assert om_retiring_calls == 2
	// The synthetic caller-owned metadata stays alive until no values use it.
	// Remove this test specialization before its borrowed stack record expires.
	C.ios_objc_initialize_lock()
	ios_runtime.swift_optional_metadata.delete(wrapped)
	C.ios_objc_initialize_unlock()
	assert C.munmap(voidptr(metadata - 8), usize(C.getpagesize())) == 0
}

fn om_reject() {
	for symbol in ['_$sSqMa', '_$sSqMn']! {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
	}
	if _ := swift_optional_metadata_arena_checked() {
		assert false
	}
	if _ := swift_optional_access_checked(0, 0) {
		assert false
	}
}

fn om_integration(api OmApi) {
	metadata := om_metadata(api, swift_string_metadata())
	allocation := swift_array_allocate(2, metadata)
	unsafe { *(&u64(allocation.owner + 16)) = 0 }
	mut words := swift_interpolation_init(64, 0)
	text := 'Array elements destroy only the live Optional String payloads'
	swift_string_append_bytes(u64(unsafe { &words }), u64(text.str), u64(text.len))
	unsafe { *(&SwiftStringWords(allocation.bytes)) = words }
	swift_optional_inject(allocation.bytes, 0, metadata)
	swift_optional_inject(allocation.bytes + 16, 1, metadata)
	unsafe { *(&u64(allocation.owner + 16)) = 2 }
	assert swift_array_access(0, metadata).metadata != 0
	swift_release(allocation.owner)
	assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0
	// A malformed complete layout is rejected before publishing metadata.
	mut witness := [14]u64{}
	mut full := [u64(unsafe { &witness[0] }), 0x200, 0]!
	for i in 0 .. 8 { witness[i] = u64(unsafe { voidptr(swift_integer_copy) }) }
	witness[8] = 25
	witness[9] = 32
	witness[10] = 7
	bad := u64(unsafe { &full[1] })
	if _ := swift_optional_access_checked(0, bad) {
		assert false
	}
	witness[8] = 8
	for flags in [u32(0x20007), 0x100007, 0x400007, 0x800007]! {
		witness[10] = flags
		if _ := swift_optional_access_checked(0, bad) {
			assert false
		}
	}
	witness[8] = 8
	witness[10] = 7
	witness[7] = 0
	if _ := swift_optional_access_checked(0, bad) {
		assert false
	}
}

fn test_swift_optional_metadata() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(voidptr(code), page) == 0 }
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0x910003fd, 0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5121 << 5) | 21), 0xaa0403f0,
		0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 60))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	mut native_hashes := []u64{}
	$if macos {
		api := OmApi{ native: true, access: om_symbol(true, '_$sSqMa'), code: code }
		for symbol in ['_$sSiN', '_$sSbN', '_$ss5UInt8VN', '_$sSSN']! {
			mut metadata := om_symbol(true, symbol)
			for _ in 0 .. 3 {
				metadata = om_metadata(api, metadata)
				native_hashes << om_matrix(api, metadata)
			}
		}
		om_strings(api)
		println('NATIVE-OPTIONAL-METADATA: generic complete responses, exact Optional layouts/flags and remaining extra inhabitants, nested enum byte footprints and UInt32 transitions, protected copy/take spans, owned String payloads and preserved x20/x21')
	}
	om_reject()
	for _ in 0 .. 2 {
		objc_start()
		wrapped := swift_integer_metadata()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn om_publish(wrapped) }
		identities := publishers.wait()
		for identity in identities {
			assert identity == identities[0]
		}
		unsafe {
			identities.free()
			publishers.free()
		}
		api := OmApi{ access: om_symbol(false, '_$sSqMa'), code: code }
		mut index := 0
		for symbol in ['_$sSiN', '_$sSbN', '_$ss5UInt8VN', '_$sSSN']! {
			mut metadata := om_symbol(false, symbol)
			for _ in 0 .. 3 {
				metadata = om_metadata(api, metadata)
				hash := om_matrix(api, metadata)
				$if macos {
					assert hash == native_hashes[index], symbol + ' depth ' + index.str() + ' native=' + native_hashes[index].hex() + ' profile=' + hash.hex()
				}
				index++
				om_protection(metadata - 8, 176, false)
			}
		}
		om_strings(api)
		om_integration(api)
		om_reentrant()
		mut nested := om_symbol(false, '_$sSbN')
		for depth in 1 .. 257 {
			nested = om_metadata(api, nested)
			witness := read64(nested - 8)
			assert read64(witness + 64) == if depth <= 254 { u64(1) } else { u64(depth - 253) }
			assert read32(witness + 84) == if depth < 254 { u32(254 - depth) } else { u32(0) }
		}
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn om_worker(api, wrapped) }
		workers.wait()
		unsafe { workers.free() }
		arena := ios_runtime.swift_optional_arena
		data := arena + u64(page)
		descriptor := om_symbol(false, '_$sSqMn')
		assert read32(descriptor) == 0xd2 && read32(descriptor + 20) == 1 && read32(descriptor + 24) == 1
		assert unsafe { (&char(u64(i64(descriptor + 8) + i64(i32(read32(descriptor + 8)))))).vstring() } == 'Optional'
		mut arguments := [wrapped]!
		assert swift_optional_instantiate(descriptor, u64(unsafe { &arguments[0] }), data + 272) == swift_optional_access(0, wrapped).metadata
		om_protection(arena, 48, true)
		om_protection(data, 300, false)
		for symbol in ['_$sSqMa', '_$sSqMn']! {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol[1..]) == none
			assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', symbol) == none
		}
		for symbol in ['_$sSqN', '_$sxSgSesSeRzlMc', '_$sxSgSEsSERzlMc']! {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
		}
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		retired := swift_optional_access(0, wrapped).metadata - 8
		ios_runtime.swift_concurrency_retired = true
		om_reject()
		ios_runtime.swift_concurrency_retired = false
		objc_stop()
		assert ios_runtime.swift_optional_arena == 0 && ios_runtime.swift_optional_retired
		om_reject()
		for address in [arena, data, arena + u64(page * 2), retired]! {
			$if macos {
				assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(address), page, unsafe { &resident }) == -1
			}
		}
	}
	unsafe { native_hashes.free() }
	println('IOS-OPTIONAL-METADATA: canonical sealed Optional specializations and enum witnesses, nested spare inhabitants/tag bytes, typed Array destruction and owned String payloads, eight cold publishers/workers and two drained/unmapped lifetimes')
}

fn om_protection(address u64, length u64, executable bool) {
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
