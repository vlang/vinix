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

type MeAccess = fn (u64) SwiftAssociatedMetadata
type MeGuard = fn (u64, u64, u64, u64, u64, &u64)
type MeGet = fn (u64, u32, u64) u32
type MeStore = fn (u64, u32, u32, u64)
type MeOptional = fn (u64, u64) SwiftAssociatedMetadata

struct MeApi {
	native     bool
	metadata   u64
	descriptor u64
	accessor   u64
	witness    u64
}

fn me_relative(p u64) u64 { return u64(i64(p) + i64(i32(read32(p)))) }

fn me_function(api MeApi, offset u64) u64 {
	entry := read64(api.witness + offset)
	return if api.native { entry & 0x0000ffffffffffff } else { entry }
}

fn me_call(probe u64, a u64, b u64, c u64, d u64, entry u64) [4]u64 {
	mut output := [4]u64{}
	unsafe { MeGuard(voidptr(probe))(a, b, c, d, entry, &output[0]) }
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output
}

fn me_layout(api MeApi, probe u64) {
	assert read64(api.metadata) == 0x201 && read64(api.metadata + 8) == api.descriptor
	assert read64(api.witness + 64) == 0 && read64(api.witness + 72) == 1
	assert read32(api.witness + 80) == 0x00200000 && read32(api.witness + 84) == 0
	assert read32(api.descriptor) == 0x52 && read32(api.descriptor + 20) == 0 && read32(api.descriptor + 24) == 1
	assert unsafe { (&char(me_relative(api.descriptor + 8))).vstring() } == '_MergeError'
	parent := me_relative(api.descriptor + 4)
	assert read32(parent) == 0 && unsafe { (&char(me_relative(parent + 8))).vstring() } == 'Swift'
	assert me_relative(api.descriptor + 12) == api.accessor
	for offset in [u64(0), 8, 16, 24, 32, 40, 48, 56, 88, 96, 104]! {
		assert me_function(api, offset) != 0
	}
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff, ~u64(0)]! {
		response := unsafe { MeAccess(voidptr(api.accessor))(request) }
		assert response.metadata == api.metadata && response.state == 0
		output := me_call(probe, request, 0, 0, 0, api.accessor)
		assert output[0] == api.metadata && output[1] == 0
	}
	if !api.native {
		assert read32(api.descriptor + 16) == 0
	}
}

fn me_values(api MeApi, probe u64, protected u64) {
	// A zero-sized value permits absent storage and pointers at either guard.
	for destination in [u64(0), protected, protected + u64(C.getpagesize())]! {
		for source in [u64(0), protected, ~u64(0)]! {
			for offset in [u64(0), 16, 24, 32, 40]! {
				assert me_call(probe, destination, source, protected, 0, me_function(api, offset))[0] == destination
			}
		}
		me_call(probe, destination, protected, 0, 0, me_function(api, 8))
		assert me_call(probe, destination, protected, 0, 0, me_function(api, 88))[0] == 0
		me_call(probe, destination, protected, 0, 0, me_function(api, 96))
		me_call(probe, destination, 0, protected, 0, me_function(api, 104))
	}
}

fn me_enums(api MeApi, probe u64, span u64) {
	page := u64(C.getpagesize())
	get := unsafe { MeGet(voidptr(me_function(api, 48))) }
	store := unsafe { MeStore(voidptr(me_function(api, 56))) }
	for cases in [u32(0), 1, 2, 254, 255, 256, 65534, 65535, 65536, 0xfffffffe, 0xffffffff]! {
		// Independent width expectation includes Swift's UInt32 addition wrap.
		width := if cases == 0 {
			u64(0)
		} else if cases < 255 || cases == 0xffffffff {
			u64(1)
		} else if cases < 65535 {
			u64(2)
		} else {
			u64(4)
		}
		for at_end in [false, true]! {
			value := span + page + if at_end { page - width } else { u64(0) }
			for tag in [u32(0), 1, 2, 254, 255, 256, 65534, 65535, 65536, 0xfffffffe, 0xffffffff]! {
				assert C.mprotect(voidptr(span + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
				C.memset(voidptr(span + page), 0xa5, usize(page))
				store(value, tag, cases, api.metadata)
				me_call(probe, value, tag, cases, api.metadata, me_function(api, 56))
				for i in u64(0) .. 8 {
					address := if at_end { value - 4 + i } else { value + i }
					if address < span + page || address >= span + page * 2 { continue }
					expected := if address >= value && address - value < width {
						u8(tag >> u32((address - value) * 8))
					} else {
						u8(0xa5)
					}
					assert unsafe { *(&u8(address)) } == expected
				}
				assert C.mprotect(voidptr(span + page), usize(page), C.PROT_READ) == 0
				expected := if width == 0 {
					u32(0)
				} else if width == 1 {
					u32(u8(tag))
				} else if width == 2 {
					u32(u16(tag))
				} else {
					tag
				}
				assert get(value, cases, api.metadata) == expected
				assert u32(me_call(probe, value, cases, api.metadata, 0, me_function(api, 48))[0]) == expected
			}
		}
	}
}

fn me_optional(api MeApi, probe u64) {
	mut access := u64(voidptr(swift_optional_access))
	$if macos {
		if api.native {
			access = u64(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2), c'$sSqMa'))
		}
	}
	mut wrapped := api.metadata
	for depth in 0 .. 3 {
		metadata := unsafe { MeOptional(voidptr(access))(0, wrapped) }.metadata
		witness := read64(metadata - 8) & 0x0000ffffffffffff
		assert read64(metadata) == 0x202 && read64(metadata + 16) == wrapped
		assert read64(witness + 64) == u64(depth + 1) && read64(witness + 72) == u64(depth + 1)
		assert read32(witness + 80) == 0x00200000 && read32(witness + 84) == 0
		mut value := [u8(0xa5), 0x67, 0x67, 0x67, u8(0x5a)]!
		address := u64(unsafe { &value[1] })
		entry := read64(witness + 104) & 0x0000ffffffffffff
		me_call(probe, address, 1, metadata, 0, entry)
		assert value[0] == 0xa5 && value[4] == 0x5a
		for i in 0 .. 3 {
			assert value[i + 1] == if i < depth {
				u8(0)
			} else if i == depth {
				u8(1)
			} else {
				u8(0x67)
			}
		}
		assert me_call(probe, address, metadata, 0, 0, read64(witness + 88) & 0x0000ffffffffffff)[0] == 1
		wrapped = metadata
	}
}

fn me_integration(api MeApi) {
	mut record := [u64(0), 0, api.descriptor]!
	address := u64(unsafe { &record[0] })
	unsafe {
		*(&u8(address)) = 2
		*(&u8(address + 1)) = 15
	}
	assert swift_mangled_lookup_checked(address, 5, 0, 0) or { panic(err) } == api.metadata
	array := swift_array_access(0, api.metadata)
	assert read64(array.metadata + 16) == api.metadata
	buffer := swift_array_allocate(257, api.metadata)
	storage := ios_runtime.swift_arrays[buffer.owner] or { panic('missing zero-sized array') }
	assert storage.stride == 1 && storage.destroy == 0 && storage.element == api.metadata
	swift_array_destroy_elements(0, 257, api.metadata)
	swift_bridge_release(buffer.owner)
	assert api.metadata != swift_void_full_metadata() + 8 && api.metadata != swift_integer_metadata()
}

fn me_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss11_MergeErrorON') or { panic(err) }
}

fn me_worker(metadata u64) {
	for _ in 0 .. 64 {
		assert me_publish() == metadata
	}
}

fn me_reject() {
	for symbol in ['_$ss11_MergeErrorON', '_$ss11_MergeErrorOMn', '_$ss11_MergeErrorOMa']! {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
	}
	if _ := swift_merge_error_metadata_arena_checked() {
		assert false
	}
}

fn test_swift_merge_error_metadata() {
	page := usize(C.getpagesize())
	probe := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert probe != u64(-1) && span != u64(-1)
	defer {
		assert C.munmap(voidptr(probe), page) == 0
		assert C.munmap(voidptr(span), page * 3) == 0
	}
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0x910003fd, 0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5121 << 5) | 21), 0xaa0403f0,
		0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(probe + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(probe), voidptr(probe + 60))
	assert C.mprotect(voidptr(probe), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		metadata := u64(C.dlsym(core, c'$ss11_MergeErrorON'))
		assert metadata != 0
		api := MeApi{ native: true, metadata: metadata, descriptor: u64(C.dlsym(core, c'$ss11_MergeErrorOMn')), accessor: u64(C.dlsym(core, c'$ss11_MergeErrorOMa')), witness: read64(metadata - 8) & 0x0000ffffffffffff }
		me_layout(api, probe)
		me_values(api, probe, span)
		me_enums(api, probe, span)
		me_optional(api, probe)
		println('NATIVE-MERGE-ERROR-METADATA: complete zero-size enum metadata and eleven witnesses, protected absent values, single-payload tag widths and UInt32 wrap, nested Optional representations and preserved x20/x21')
	}
	me_reject()
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn me_publish() }
		identities := publishers.wait()
		for identity in identities {
			assert identity == identities[0]
		}
		unsafe {
			identities.free()
			publishers.free()
		}
		library := '/usr/lib/swift/libswiftCore.dylib'
		metadata := me_publish()
		api := MeApi{ metadata: metadata, descriptor: runtime_symbol(library, '_$ss11_MergeErrorOMn') or { panic(err) }, accessor: runtime_symbol(library, '_$ss11_MergeErrorOMa') or { panic(err) }, witness: read64(metadata - 8) }
		me_layout(api, probe)
		me_values(api, probe, span)
		me_enums(api, probe, span)
		me_optional(api, probe)
		me_integration(api)
		me_protection(api.accessor, 24, true)
		me_protection(api.metadata - 8, 272, false)
		for symbol in ['_$ss11_MergeErrorON', '_$ss11_MergeErrorOMn', '_$ss11_MergeErrorOMa']! {
			assert runtime_symbol(library, symbol[1..]) == none
			for foreign in ['/usr/lib/swift/libswiftFoundation.dylib', '/usr/lib/libSystem.B.dylib']! {
				assert runtime_symbol(foreign, symbol) == none
			}
		}
		for unsupported in ['_$ss11_MergeErrorOWV']! {
			assert runtime_symbol(library, unsupported) == none
		}
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn me_worker(metadata) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		ios_runtime.swift_concurrency_retired = true
		me_reject()
		ios_runtime.swift_concurrency_retired = false
		arena := ios_runtime.swift_merge_error_metadata_arena
		objc_stop()
		assert ios_runtime.swift_merge_error_metadata_arena == 0 && ios_runtime.swift_merge_error_metadata_retired
		me_reject()
		for offset in [u64(0), u64(page)]! {
			$if macos {
				assert C.mprotect(voidptr(arena + offset), page, C.PROT_READ) == -1
			} $else {
				mut state := u8(0)
				assert C.mincore(voidptr(arena + offset), page, &state) == -1
			}
		}
	}
	println('IOS-MERGE-ERROR-METADATA: canonical sealed enum/accessor, eleven zero-size witnesses, guarded tag widths and UInt32 wrap, nested Optional and typed Array, symbolic descriptor lookup, eight cold publishers/readers and two drained/unmapped lifetimes')
}

fn me_protection(address u64, length u64, executable bool) {
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
