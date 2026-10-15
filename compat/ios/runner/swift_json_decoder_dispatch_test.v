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

type JSONDispatchProbe = fn (u64, u64, u64, u64)
type JSONDispatchSign = fn (u64, u64) u64

fn json_dispatch_pair(load bool, vector bool, first u32, second u32, base u32, offset int) u32 {
	width := if vector { 16 } else { 8 }
	assert offset % width == 0 && offset >= 0 && offset / width < 64
	op := if vector { u32(0xad000000) } else { u32(0xa9000000) }
	return op | (if load { u32(0x00400000) } else { u32(0) }) | (u32(offset / width) << 15) | (second << 10) | (base << 5) | first
}

fn json_dispatch_mov(register u32, value u32) u32 {
	assert value <= 65535
	return 0xd2800000 | (value << 5) | register
}

fn json_dispatch_store(register u32, base u32, offset u32) u32 {
	assert offset % 8 == 0
	return 0xf9000000 | ((offset / 8) << 10) | (base << 5) | register
}

fn json_dispatch_code(code u64) {
	mut ops := [u32(0xa9ba7bfd)] // Save all C callee-saved registers in a 96-byte frame.
	for i in 0 .. 5 {
		ops << json_dispatch_pair(false, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16)
	}
	ops << [u32(0xaa0003f0), 0xaa0103f4, 0xaa0203f3, 0xaa0303f6, 0xaa1603e7, 0x91032268] // entry/Self/result/observations and x8=result+200.
	for register in u32(0) .. 7 { ops << json_dispatch_mov(register, 0x5100 + register) }
	ops << json_dispatch_mov(21, 0)
	pc := code + u64(ops.len * 4)
	distance := u32(code + 640 - pc)
	ops << u32(0x10000017 | ((distance & 3) << 29) | ((distance >> 2) << 5)) // adr x23, vector constants.
	for i in 0 .. 4 {
		ops << json_dispatch_pair(true, true, u32(i * 2), u32(i * 2 + 1), 23, i * 32)
	}
	ops << u32(0xd63f0200) // blr x16; the target may return an error in x21.
	for register in u32(0) .. 4 { ops << json_dispatch_store(register, 19, 8 + register * 8) }
	ops << json_dispatch_pair(false, false, 20, 21, 19, 40)
	for i in 0 .. 4 {
		ops << json_dispatch_pair(false, true, u32(i * 2), u32(i * 2 + 1), 19, 64 + i * 32)
	}
	for i in 0 .. 5 {
		ops << json_dispatch_pair(true, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16)
	}
	ops << [u32(0xa8c67bfd), 0xd65f03c0]
	assert ops.len * 4 <= 256
	for i, op in ops { write32(code + u64(i * 4), op) }
	for failing in [false, true]! {
		entry := code + if failing { u64(384) } else { u64(256) }
		mut method := []u32{}
		for register in u32(0) .. 9 { method << json_dispatch_store(register, 7, register * 8) }
		method << json_dispatch_pair(false, false, 20, 21, 7, 72)
		for i in 0 .. 4 {
			method << json_dispatch_pair(false, true, u32(i * 2), u32(i * 2 + 1), 7, 96 + i * 32)
		}
		method << [json_dispatch_mov(9, 0x6008), json_dispatch_store(9, 8, 0)]
		for register in u32(0) .. 4 { method << json_dispatch_mov(register, 0x6200 + register) }
		method << [json_dispatch_mov(21, if failing { u32(0xab21) } else { u32(0) }), u32(0xd65f03c0)]
		assert method.len * 4 <= 128
		for i, op in method { write32(entry + u64(i * 4), op) }
	}
	write32(code + 512, 0xdac10020)
	write32(code + 516, 0xd65f03c0) // pacia x0,x1.
	write32(code + 528, 0xdac10820)
	write32(code + 532, 0xd65f03c0) // pacda x0,x1.
	for i in 0 .. 16 {
		unsafe { *(&u64(code + 640 + u64(i * 8))) = u64(0x12340000 + i) }
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 768))
}

fn json_dispatch_case(entry u64, self u64, probe JSONDispatchProbe, failing bool) {
	mut observed := [30]u64{}
	mut result := [30]u64{}
	observed[28] = 0xcafe
	observed[29] = 0xbeef
	result[0] = 0xcafe
	result[7] = 0xbeef
	result[24] = 0xcafe
	result[26] = 0xbeef
	result[29] = 0xabcd
	probe(entry, self, u64(unsafe { &result[0] }), u64(unsafe { &observed[0] }))
	for i in 0 .. 7 {
		assert observed[i] == u64(0x5100 + i)
	}
	assert observed[7] == u64(unsafe { &observed[0] }) && observed[8] == u64(unsafe { &result[25] })
	assert observed[9] == self && observed[10] == 0
	for i in 0 .. 16 {
		assert observed[12 + i] == u64(0x12340000 + i) && result[8 + i] == u64(0x12340000 + i)
	}
	for i in 0 .. 4 {
		assert result[1 + i] == u64(0x6200 + i)
	}
	assert result[5] == self && result[6] == if failing { u64(0xab21) } else { u64(0) }
	assert result[0] == 0xcafe && result[7] == 0xbeef && result[24] == 0xcafe && result[25] == 0x6008 && result[26] == 0xbeef && result[29] == 0xabcd
	assert observed[28] == 0xcafe && observed[29] == 0xbeef
}

fn json_dispatch_worker(entry u64, self u64, probe JSONDispatchProbe, failing bool) {
	for _ in 0 .. 128 { json_dispatch_case(entry, self, probe, failing) }
}

fn json_dispatch_spans(entry u64, code u64, native bool) {
	page := usize(C.getpagesize())
	probe := unsafe { JSONDispatchProbe(voidptr(code)) }
	for slot_end in [false, true]! {
		for self_end in [false, true]! {
			for failing in [false, true]! {
				self_pages := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
				table_pages := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
				assert self_pages != u64(-1) && table_pages != u64(-1)
				assert C.mprotect(voidptr(self_pages + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0 && C.mprotect(voidptr(table_pages + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
				self := self_pages + u64(page) + if self_end { u64(page) - 8 } else { u64(0) }
				slot := table_pages + u64(page) + if slot_end { u64(page) - 8 } else { u64(0) }
				metadata := slot - 320
				method := code + if failing { u64(384) } else { u64(256) }
				mut isa := metadata
				mut target := method
				$if macos {
					if native {
						data_sign := unsafe { JSONDispatchSign(voidptr(code + 528)) }
						code_sign := unsafe { JSONDispatchSign(voidptr(code + 512)) }
						isa = data_sign(metadata, self | (u64(0x6ae1) << 48))
						target = code_sign(method, slot | (u64(0xcb22) << 48))
					}
				}
				unsafe {
					*(&u64(self)) = isa
					*(&u64(slot)) = target
				}
				assert C.mprotect(voidptr(self_pages + u64(page)), page, C.PROT_READ) == 0 && C.mprotect(voidptr(table_pages + u64(page)), page, C.PROT_READ) == 0
				json_dispatch_case(entry, self, probe, failing)
				mut workers := []thread{}
				for _ in 0 .. 8 {
					workers << spawn json_dispatch_worker(entry, self, probe, failing)
				}
				workers.wait()
				assert read64(self) == isa && read64(slot) == target
				assert C.munmap(voidptr(self_pages), page * 3) == 0 && C.munmap(voidptr(table_pages), page * 3) == 0
			}
		}
	}
}

fn json_dispatch_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 12 <= start + size && info[0] == (C.PROT_READ | if executable {
				C.PROT_EXEC
			} else {
				0
			})
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
				assert mapped && address + 12 <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found == mapped
	}
}

fn json_dispatch_publish(overlay bool) u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	mut entry := u64(0)
	for _ in 0 .. 256 {
		entry = runtime_symbol(library, '_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj') or { panic(err) }
	}
	return entry
}

fn test_swift_json_decoder_dispatch() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	json_dispatch_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		handle := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		assert handle != unsafe { nil }
		entry := u64(C.dlsym(handle, c'$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj'))
		assert entry != 0
		json_dispatch_spans(entry, code, true)
		println('IOS-JSON-DISPATCH-NATIVE: class slot320 and borrowed x20 Self, x0-x8/vector arguments, indirect and scalar results, x21 success/error propagation, guarded exact header/slot spans and eight concurrent callers')
	}
	if _ := swift_foundation_symbol('_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj') {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for i in 0 .. 8 { publishers << spawn json_dispatch_publish(i % 2 == 0) }
		entries := publishers.wait()
		entry := entries[0]
		for value in entries {
			assert value == entry
		}
		arena := ios_runtime.swift_foundation_arena
		assert entry == arena + 160
		json_dispatch_mapping(entry, true, true)
		json_dispatch_mapping(arena + u64(page), true, false)
		json_dispatch_spans(entry, code, false)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		for symbol in ['_$s10Foundation11JSONDecoderCACycfc', '_$s10Foundation11JSONDecoderCMa',
			'_$s10Foundation11JSONDecoderCMn']! {
			if _ := swift_foundation_symbol(symbol) {
				assert false
			}
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj') {
			assert false
		}
		if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj') {
			assert false
		}
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		json_dispatch_mapping(entry, false, false)
		json_dispatch_mapping(arena + u64(page), false, false)
		if _ := swift_foundation_symbol('_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj') {
			assert false
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-JSON-DISPATCH: real virtual override forwarding through slot320, preserved arguments/results/error channel without ARC/allocation or unused header reads, sealed concurrent publication and two unmapped retirements; decoder construction/metadata/backend remain unsupported')
}
