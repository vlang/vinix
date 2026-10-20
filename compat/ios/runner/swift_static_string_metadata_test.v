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

type SsmGuard = fn (u64, u64, u64, u64, u64, &u64)
type SsmOptional = fn (u64, u64) SwiftAssociatedMetadata

struct SsmApi {
	native     bool
	metadata   u64
	descriptor u64
	accessor   u64
	witness    u64
	code       u64
}

fn ssm_relative(p u64) u64 {
	return if read32(p) == 0 { u64(0) } else { u64(i64(p) + i64(i32(read32(p)))) }
}

fn ssm_slot(api SsmApi, slot int) u64 {
	return read64(api.witness + u64(slot * 8)) & 0x0000ffffffffffff
}

fn ssm_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0x910003fd, 0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5121 << 5) | 21), 0xaa0403f0,
		0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn ssm_call(api SsmApi, a u64, b u64, c u64, d u64, entry u64) [4]u64 {
	mut output := [4]u64{}
	unsafe { SsmGuard(voidptr(api.code))(a, b, c, d, entry, &output[0]) }
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output
}

fn ssm_layout(api SsmApi) {
	assert read64(api.metadata) == 0x200 && read64(api.metadata + 8) == api.descriptor
	for i, offset in [u32(0), 8, 16]! {
		assert read32(api.metadata + 16 + u64(i * 4)) == offset
	}
	assert read32(api.descriptor) == 0x51 && read32(api.descriptor + 20) == 3 && read32(api.descriptor + 24) == 2
	assert unsafe { (&char(ssm_relative(api.descriptor + 8))).vstring() } == 'StaticString'
	parent := ssm_relative(api.descriptor + 4)
	assert read32(parent) == 0 && unsafe { (&char(ssm_relative(parent + 8))).vstring() } == 'Swift'
	assert ssm_relative(api.descriptor + 12) == api.accessor
	assert read64(api.witness + 64) == 17 && read64(api.witness + 72) == 24 && read32(api.witness + 80) == 7 && read32(api.witness + 84) == 0
	for slot in 0 .. 8 {
		assert ssm_slot(api, slot) != 0
	}
	for request in [u64(0), 0xff, 0x100, 0x1ff, ~u64(0)]! {
		result := ssm_call(api, request, 0, 0, 0, api.accessor)
		assert result[0] == api.metadata && result[1] == 0
	}
	if !api.native {
		assert ssm_relative(api.descriptor + 16) == 0
	}
}

fn ssm_values(api SsmApi) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 4) == 0 }
	for offset in [u64(0), u64(page * 2)]! {
		assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	source := span + u64(page) - 17
	destination := span + u64(page * 3) - 17
	for flags in [u8(0), 1, 2, 3, 255]! {
		assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
		// Arbitrary pointer/scalar and count bits are copied without dereferencing.
		for i in 0 .. 16 {
			unsafe { *(&u8(source + u64(i))) = u8(i * 13 + 17) }
		}
		unsafe {
			*(&u8(source + 16)) = flags
			*(&u8(source - 1)) = 0x67
		}
		assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
		for slot in [0, 2, 3, 4, 5]! {
			C.memset(voidptr(destination - 1), 0x5a, 18)
			result := ssm_call(api, destination, source, api.metadata, 0, ssm_slot(api, slot))
			assert result[0] == destination
			assert C.memcmp(voidptr(source), voidptr(destination), 17) == 0 && unsafe { *(&u8(destination - 1)) } == 0x5a
			assert ssm_call(api, destination, destination, api.metadata, 0, ssm_slot(api, slot))[0] == destination
		}
	}
	ssm_call(api, span + u64(page), api.metadata, 0, 0, ssm_slot(api, 1))
	assert unsafe { *(&u8(source - 1)) } == 0x67
}

fn ssm_enums(api SsmApi) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 2) == 0 }
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_NONE) == 0
	for cases in [u32(0), 1, 255, 256, 65535, 65536, 0xfffffffe, 0xffffffff]! {
		count := if cases == 0 { u64(17) } else { u64(18) }
		value := span + u64(page) - count
		for tag in [u32(0), 1, 2, 255, 256, 65535, 65536, 0x7fffffff, 0xfffffffe, 0xffffffff]! {
			C.memset(voidptr(value - 1), 0x67, usize(count + 1))
			ssm_call(api, value, tag, cases, api.metadata, ssm_slot(api, 7))
			assert unsafe { *(&u8(value - 1)) } == 0x67
			for i in u64(0) .. 17 {
				expected := if tag == 0 {
					u8(0x67)
				} else if i < 4 {
					u8((tag - 1) >> (i * 8))
				} else {
					u8(0)
				}
				assert unsafe { *(&u8(value + i)) } == expected
			}
			if cases != 0 {
				assert unsafe { *(&u8(value + 17)) } == u8(tag != 0)
			}
			expected := if cases == 0 { u32(0) } else { tag }
			assert u32(ssm_call(api, value, cases, api.metadata, 0, ssm_slot(api, 6))[0]) == expected
		}
		if cases == 0 {
			ssm_call(api, span + u64(page), 0, 0, api.metadata, ssm_slot(api, 7))
			assert ssm_call(api, span + u64(page), 0, api.metadata, 0, ssm_slot(api, 6))[0] == 0
		}
	}
}

fn ssm_nested(api SsmApi) {
	mut access := u64(0)
	$if macos {
		if api.native {
			lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			access = u64(C.dlsym(lib, c'$sSqMa'))
		}
	}
	if !api.native {
		access = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSqMa') or { panic(err) }
	}
	mut wrapped := api.metadata
	for level in 1 .. 4 {
		result := unsafe { SsmOptional(voidptr(access))(0, wrapped) }
		assert result.state == 0 && read64(result.metadata + 16) == wrapped
		witness := read64(result.metadata - 8) & 0x0000ffffffffffff
		assert read64(witness + 64) == u64(17 + level) && read64(witness + 72) == 24 && read32(witness + 84) == 0
		assert read32(witness + 80) == 0x200007
		wrapped = result.metadata
	}
}

fn ssm_integration(api SsmApi) {
	mut record := [32]u8{}
	record[0] = 2
	record[1] = 15
	unsafe { *(&u64(&record[16])) = api.descriptor }
	assert swift_mangled_lookup_checked(u64(unsafe { &record[0] }), 5, 0, 0) or { panic(err) } == api.metadata
	array_type := swift_array_access(0, api.metadata)
	assert read64(array_type.metadata + 16) == api.metadata
	buffer := swift_array_allocate(257, api.metadata)
	storage := ios_runtime.swift_arrays[buffer.owner] or { panic('missing storage') }
	assert storage.stride == 24 && storage.element == api.metadata && storage.destroy == 0
	C.memset(voidptr(buffer.bytes), 0x67, 257 * 24)
	swift_array_destroy_elements(buffer.bytes, 257, api.metadata)
	for i in 0 .. 257 * 24 {
		assert unsafe { *(&u8(buffer.bytes + u64(i))) } == 0x67
	}
	swift_bridge_release(buffer.owner)
}

fn ssm_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss12StaticStringVN') or { panic(err) }
}

fn ssm_worker(api SsmApi) {
	for _ in 0 .. 64 {
		assert ssm_publish() == api.metadata
		ssm_layout(api)
	}
}

fn ssm_reject() {
	for symbol in ['_$ss12StaticStringVN', '_$ss12StaticStringVMn', '_$ss12StaticStringVMa']! {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
	}
	if _ := swift_static_string_metadata_arena_checked() {
		assert false
	}
}

fn ssm_protection(address u64, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, &info[0], &count, &object) == 0
		assert start <= address && address < start + size && info[0] == (C.PROT_READ | if executable {
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
			bounds := fields[0].split('-')
			if bounds.len != 2 { continue }
			start := strconv.parse_uint(bounds[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(bounds[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
			}
		}
		assert found
	}
}

fn test_swift_static_string_metadata() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(voidptr(code), page) == 0 }
	ssm_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 60))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		metadata := u64(C.dlsym(lib, c'$ss12StaticStringVN'))
		assert metadata != 0
		api := SsmApi{ native: true, metadata: metadata, descriptor: u64(C.dlsym(lib, c'$ss12StaticStringVMn')), accessor: u64(C.dlsym(lib, c'$ss12StaticStringVMa')), witness: read64(metadata - 8) & 0x0000ffffffffffff, code: code }
		ssm_layout(api)
		ssm_values(api)
		ssm_enums(api)
		ssm_nested(api)
		println('NATIVE-STATIC-STRING-METADATA: 17-byte POD, stride24 alignment8, three offsets, no extra inhabitants, complete accessor, guarded copy/take/destroy, UInt32 tags, three nested Optionals and x20/x21')
	}
	ssm_reject()
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn ssm_publish() }
		identities := publishers.wait()
		for value in identities {
			assert value == identities[0]
		}
		library := '/usr/lib/swift/libswiftCore.dylib'
		metadata := ssm_publish()
		api := SsmApi{ metadata: metadata, descriptor: runtime_symbol(library, '_$ss12StaticStringVMn') or { panic(err) }, accessor: runtime_symbol(library, '_$ss12StaticStringVMa') or { panic(err) }, witness: read64(metadata - 8), code: code }
		ssm_layout(api)
		ssm_values(api)
		ssm_enums(api)
		ssm_nested(api)
		ssm_integration(api)
		ssm_protection(api.accessor, true)
		ssm_protection(api.metadata, false)
		for symbol in ['_$ss12StaticStringVN', '_$ss12StaticStringVMn', '_$ss12StaticStringVMa']! {
			assert runtime_symbol(library, symbol[1..]) == none
			for foreign in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
				assert runtime_symbol(foreign, symbol) == none
			}
		}
		for symbol in ['_$ss12StaticStringVWV', '_$ss12StaticStringVs23CustomStringConvertiblesWP',
			'_$ss12StaticStringVMf']! {
			assert runtime_symbol(library, symbol) == none
		}
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn ssm_worker(api) }
		workers.wait()
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0
		ios_runtime.swift_concurrency_retired = true
		ssm_reject()
		ios_runtime.swift_concurrency_retired = false
		arena := ios_runtime.swift_static_string_metadata_arena
		objc_stop()
		assert ios_runtime.swift_static_string_metadata_arena == 0 && ios_runtime.swift_static_string_metadata_retired
		ssm_reject()
		for offset in [u64(0), u64(page)]! {
			$if macos {
				assert C.mprotect(voidptr(arena + offset), page, C.PROT_READ) == -1
			} $else {
				mut state := u8(0)
				assert C.mincore(voidptr(arena + offset), page, &state) == -1
			}
		}
	}
	println('IOS-STATIC-STRING-METADATA: sealed canonical descriptor/metadata, exact 17-byte POD witnesses and UInt32 enum tags, symbolic lookup and typed Arrays, nested Optionals, scoped exports, eight cold publishers/readers and two drained/unmapped lifetimes')
}
