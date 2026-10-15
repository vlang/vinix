// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
import math

#include <dlfcn.h>

$if macos {
	#include <mach/mach.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type SwiftDateProbe = fn (u64, u64, u64, &u64)
type SwiftDateAccess = fn (u64) SwiftAssociatedMetadata
type SwiftDateIntervalProbe = fn (u64, u64, u64, u64, &u64)
type SwiftDateClock = fn () f64
type SwiftDateMetadataProbe = fn (u64, u64, &u64)
type SwiftDateCopy = fn (u64, u64, u64) u64
type SwiftDateDestroy = fn (u64, u64)
type SwiftDateGetTag = fn (u64, u32, u64) u32
type SwiftDateStoreTag = fn (u64, u32, u32, u64)
type SwiftDateLookup = fn (u64, u64, u64, u64, u64) u64
type DateEncodingProbe = fn (u64, u64, u64, &u64)
type DateEncodingSign = fn (u64, u64) u64
type DateEncodingTable = fn (u64, u64, u64) u64

struct DateEncodingScenario {
	metadata u64
	encoder_metadata u64
	encoder_table u64
	container_table u64
	error_value u64
mut:
	getters int
	encodes int
	destroys int
	bits u64
	container u64
	error_before u64
}

fn date_encoding_getter(self u64, output u64, metadata u64, table u64) {
	mut scenario := unsafe { &DateEncodingScenario(read64(self)) }
	assert metadata == scenario.encoder_metadata && table == scenario.encoder_table
	assert scenario.getters == scenario.encodes && scenario.encodes == scenario.destroys
	scenario.getters++
	scenario.container = output
	unsafe {
		*(&u64(output)) = u64(scenario)
		*(&u64(output + 8)) = 0x12345678
		*(&u64(output + 16)) = 0x87654321
		*(&u64(output + 24)) = scenario.metadata
		*(&u64(output + 32)) = scenario.container_table
	}
}

fn date_encoding_double(value f64, metadata u64, table u64, self u64, incoming_error u64) u64 {
	mut scenario := unsafe { &DateEncodingScenario(read64(self)) }
	assert metadata == scenario.metadata && table == scenario.container_table && scenario.container == self
	assert scenario.getters == scenario.encodes + 1 && scenario.encodes == scenario.destroys
	assert read64(self + 8) == 0x12345678 && read64(self + 16) == 0x87654321
	scenario.encodes++
	scenario.bits = unsafe { *(&u64(&value)) }
	scenario.error_before = incoming_error
	unsafe { *(&u64(self + 8)) = 0xfeedface }
	return scenario.error_value
}

fn date_encoding_drop(value u64, metadata u64) {
	mut scenario := unsafe { &DateEncodingScenario(read64(value)) }
	assert metadata == scenario.metadata && value == scenario.container
	assert scenario.getters == scenario.encodes && scenario.encodes == scenario.destroys + 1
	assert read64(value + 8) == 0xfeedface && read64(value + 16) == 0x87654321
	scenario.destroys++
}

fn date_encoding_code() u64 {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// Ordinary entry/Encoder/Date/output -> Swift borrowed x0/x20. Capture
	// preserved Self, propagated x21 and d8, and leave unused x8 null.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xfd001be8,
		0xaa0303f3, 0xaa0003f0, 0xaa0203f4, 0xaa0103e0, 0xd2800008,
		0xd2800015, 0xd28b54a9, 0x9e670128, 0xd63f0200,
		0xa9005674, 0xfd000a68, 0xfd401be8, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	// Getter adapts x20/x8 plus metadata/table to an ordinary V callback.
	for i, op in [u32(0xaa0103e3), 0xaa0003e2, 0xaa0803e1, 0xaa1403e0, 0x58000050, 0xd61f0200]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 152)) = u64(voidptr(date_encoding_getter)) }
	// The Double stays in d0. Return the callback's opaque error through x21.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e2, 0xaa1503e3, 0x580000b0, 0xd63f0200,
		0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 192 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 224)) = u64(voidptr(date_encoding_double)) }
	write32(code + 384, 0xdac10020); write32(code + 388, 0xd65f03c0) // pacia
	write32(code + 400, 0xdac10820); write32(code + 404, 0xd65f03c0) // pacda
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 408))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	return code
}

fn date_encoding_case(entry u64, code u64, metadata u64, encoder_metadata u64, encoder_table u64, container_table u64, at_end bool, boxed bool, failing bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
	encoder := span + u64(page) + if at_end { u64(page) - 40 } else { u64(0) }
	self := span + u64(page * 3) + if at_end { u64(page) - 8 } else { u64(0) }
	mut scenario := &DateEncodingScenario{ metadata: metadata, encoder_metadata: encoder_metadata, encoder_table: encoder_table, container_table: container_table,
		error_value: if failing { span } else { u64(0) } }
	// A boxed borrowed Encoder has no ownership work here. Its source bytes
	// stay readonly; no retain, copy, uniqueness or destroy callback is allowed.
	box := span + u64(page) + 128
	unsafe {
		*(&u64(box + 16)) = u64(scenario)
		*(&u64(box + 24)) = 0x12345678
		*(&u64(encoder)) = if boxed { box } else { u64(scenario) }
		*(&u64(encoder + 8)) = 0x12345678
		*(&u64(encoder + 16)) = 0x87654321
		*(&u64(encoder + 24)) = encoder_metadata
		*(&u64(encoder + 32)) = encoder_table
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	probe := unsafe { DateEncodingProbe(voidptr(code)) }
	for bits in [u64(0), 0x8000000000000000, 1, 0xc22d63c8c5000000, 0x7ff0000000000000,
		0xfff0000000000000, 0x7ff8000000000042, 0x7ff0000000000042, ~u64(0)]! {
		unsafe { *(&u64(self)) = bits }
		assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
		mut output := [u64(0xcafe), 0, 0, 0, 0xbeef]!
		probe(entry, encoder, self, unsafe { &output[1] })
		assert output == [u64(0xcafe), self, scenario.error_value, 0x5aa5, 0xbeef]!
		assert scenario.bits == bits && scenario.error_before == 0
		assert scenario.getters == scenario.encodes && scenario.encodes == scenario.destroys
		assert read64(self) == bits && read64(encoder) == if boxed { box } else { u64(scenario) }
		assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	assert scenario.destroys == 9
	unsafe { free(scenario) }
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn date_encoding_suite(entry u64, witness_entry u64, native bool) {
	code := date_encoding_code()
	page := usize(C.getpagesize())
	data := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	metadata := data + 16; witness := data + 64; encoder_table := data + 192; container_table := data + 256
	boxed_metadata := data + 352; boxed_witness := data + 384
	mut witness_pointer := witness
	mut boxed_witness_pointer := boxed_witness
	mut destroy := u64(unsafe { voidptr(date_encoding_drop) })
	mut getter := code + 128
	mut encode := code + 192
	$if macos { if native {
		sign := unsafe { DateEncodingSign(voidptr(code + 384)) }
		witness_pointer = unsafe { DateEncodingSign(voidptr(code + 400))(witness, (metadata - 8) | (u64(0x2e3f) << 48)) }
		boxed_witness_pointer = unsafe { DateEncodingSign(voidptr(code + 400))(boxed_witness, (boxed_metadata - 8) | (u64(0x2e3f) << 48)) }
		destroy = sign(destroy, (witness + 8) | (u64(0x4f8) << 48))
		getter = sign(getter, (encoder_table + 40) | (u64(0xe681) << 48))
		encode = sign(encode, (container_table + 40) | (u64(0x3d99) << 48))
	} }
	unsafe {
		*(&u64(metadata - 8)) = witness_pointer; *(&u64(metadata)) = 0x200
		*(&u64(witness + 8)) = destroy
		*(&u64(witness + 64)) = 16; *(&u64(witness + 72)) = 16
		*(&u64(encoder_table + 40)) = getter; *(&u64(container_table + 40)) = encode
		*(&u64(boxed_metadata - 8)) = boxed_witness_pointer; *(&u64(boxed_metadata)) = 0x200
		*(&u64(boxed_witness + 8)) = destroy
		*(&u64(boxed_witness + 64)) = 32; *(&u64(boxed_witness + 72)) = 32
	}
	write32(witness + 80, 0x02010007)
	write32(boxed_witness + 80, 0x02030007)
	assert C.mprotect(voidptr(data), page, C.PROT_READ) == 0
	for target in [entry, witness_entry]! {
		for boxed in [false, true]! {
			encoder_metadata := if boxed { boxed_metadata } else { metadata }
			for at_end in [false, true]! {
				for failing in [false, true]! {
					date_encoding_case(target, code, metadata, encoder_metadata, encoder_table, container_table, at_end, boxed, failing)
				}
			}
			mut workers := []thread{}
			for i in 0 .. 8 { workers << spawn date_encoding_case(target, code, metadata, encoder_metadata, encoder_table, container_table, i % 2 == 0, boxed, i % 3 == 0) }
			workers.wait()
			unsafe { workers.free() }
		}
	}
	if !native {
		mut words := [u64(0), 0, 0, boxed_metadata, encoder_table]!
		if _ := swift_date_encoding_project_checked(u64(unsafe { &words[0] }), true) { assert false }
		assert words == [u64(0), 0, 0, boxed_metadata, encoder_table]!
	}
	assert C.munmap(voidptr(data), page) == 0 && C.munmap(voidptr(code), page) == 0
}

fn swift_date_relative(address u64) u64 {
	delta := i32(read32(address))
	return if delta == 0 { u64(0) } else { u64(i64(address) + delta) }
}

fn swift_date_metadata_cases(entry u64, descriptor u64, code u64, native bool) u64 {
	response := unsafe { SwiftDateAccess(voidptr(entry))(0) }
	metadata := response.metadata
	assert response.state == 0 && read64(metadata) == 0x200
	assert read64(metadata + 8) & 0x0000ffffffffffff == descriptor && read32(metadata + 16) == 0
	witness := read64(metadata - 8) & u64(0x0000ffffffffffff)
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8
	assert read32(witness + 80) == 0x02000007 && read32(witness + 84) == 0
	assert read32(descriptor) & 0xffff == 0x51 && read32(descriptor + 20) == 1 && read32(descriptor + 24) == 2
	assert unsafe { (&char(swift_date_relative(descriptor + 8))).vstring() } == 'Date'
	parent := swift_date_relative(descriptor + 4)
	assert unsafe { (&char(swift_date_relative(parent + 8))).vstring() } == 'Foundation'
	if !native {
		assert read32(descriptor) == 0x51 && swift_date_relative(descriptor + 16) == 0
		swift_date_mapping(entry, 24, true, true)
		swift_date_mapping(metadata - 8, 176, true, false)
	}
	probe := unsafe { SwiftDateMetadataProbe(voidptr(code + 544)) }
	for accessor in [entry, swift_date_relative(descriptor + 12)]! {
		for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff, ~u64(0)]! {
			mut output := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
			probe(request, accessor, unsafe { &output[1] })
			assert output == [u64(0xcafe), metadata, 0, 0x5020, 0x5021, 0xbeef]!
		}
	}
	return metadata
}

fn swift_date_witness_cases(metadata u64, guard u64) {
	witness := read64(metadata - 8) & u64(0x0000ffffffffffff)
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	for source_end in [false, true]! {
		for destination_end in [false, true]! {
			source := span + u64(page) + if source_end { u64(page) - 8 } else { u64(1) }
			destination := span + u64(page * 3) + if destination_end { u64(page) - 8 } else { u64(1) }
			for bits in [u64(0), 1, 0x8000000000000000, 0x3ff0000000000000, 0xc22d63c8c5000000,
				0x7ff0000000000000, 0x7ff0000000000042, 0xfff8000000000081, ~u64(0)]! {
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
				C.memcpy(voidptr(source), unsafe { &bits }, 8)
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
				assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
				for slot in [u64(0), 2, 3, 4, 5]! {
					transfer := unsafe { SwiftDateCopy(voidptr(read64(witness + slot * 8) & 0x0000ffffffffffff)) }
					C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
					assert transfer(destination, source, guard) == destination
					assert transfer(destination, destination, guard) == destination
					mut copied := u64(0)
					C.memcpy(unsafe { &copied }, voidptr(destination), 8)
					assert copied == bits
					C.memcpy(unsafe { &copied }, voidptr(source), 8)
					assert copied == bits
					for offset in u64(0) .. u64(page) {
						address := span + u64(page * 3) + offset
						if address < destination || address >= destination + 8 { assert unsafe { *(&u8(address)) } == 0xa5 }
					}
				}
			}
		}
	}
	destroy := unsafe { SwiftDateDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	get_tag := unsafe { SwiftDateGetTag(voidptr(read64(witness + 48) & 0x0000ffffffffffff)) }
	store_tag := unsafe { SwiftDateStoreTag(voidptr(read64(witness + 56) & 0x0000ffffffffffff)) }
	destroy(guard, guard)
	assert get_tag(guard, 0, guard) == 0
	store_tag(guard, 0, 0, guard)
	for cases in [u32(0), 1, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
		for tag in [u32(0), 1, 17, 0x7fffffff, 0xfffffffe, 0xffffffff]! {
			for at_end in [false, true]! {
				width := if cases == 0 { u64(8) } else { u64(9) }
				value := span + u64(page * 3) + if at_end { u64(page) - width } else { u64(1) }
				C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
				store_tag(value, tag, cases, guard)
				mut bits := u64(0)
				C.memcpy(unsafe { &bits }, voidptr(value), 8)
				assert bits == if tag == 0 { u64(0xa5a5a5a5a5a5a5a5) } else { u64(tag - 1) }
				assert get_tag(value, cases, guard) == if cases == 0 { u32(0) } else { tag }
				if cases != 0 { assert unsafe { *(&u8(value + 8)) } == if tag == 0 { u8(0) } else { u8(1) } }
				for offset in u64(0) .. u64(page) {
					address := span + u64(page * 3) + offset
					if address < value || address >= value + width { assert unsafe { *(&u8(address)) } == 0xa5 }
				}
			}
		}
	}
	// A present payload leaves all eight bits untouched; nonzero tag bytes
	// use a wrapping UInt32 payload increment, independent of the case count.
	value := span + u64(page * 4) - 9
	for byte in [u8(1), 0x80, 0xff]! {
		C.memset(voidptr(value), 0xff, 8)
		unsafe { *(&u8(value + 8)) = byte }
		assert get_tag(value, 1, guard) == 0
		store_tag(value, 0, 1, guard)
		assert unsafe { *(&u8(value + 8)) } == 0
		mut bits := u64(0)
		C.memcpy(unsafe { &bits }, voidptr(value), 8)
		assert bits == ~u64(0)
	}
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn swift_date_symbolic(lookup SwiftDateLookup, descriptor u64, metadata u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1) && C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
	name := span + u64(page) - 5
	slot := span + 16
	unsafe { *(&u8(name)) = 2; *(&u64(slot)) = descriptor }
	delta := i32(i64(slot) - i64(name + 1))
	C.memcpy(voidptr(name + 1), unsafe { &delta }, 4)
	assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		assert lookup(request, name, 5, 0, 0) == metadata
	}
	assert C.munmap(voidptr(span), page * 2) == 0
}

fn swift_date_metadata_publish(framework bool) u64 {
	library := if framework { '/System/Library/Frameworks/Foundation.framework/Foundation' } else { '/usr/lib/swift/libswiftFoundation.dylib' }
	first := if framework { '_$s10Foundation4DateVMa' } else { '_$s10Foundation4DateVMn' }
	assert (runtime_symbol(library, first) or { panic(err) }) != 0
	mut metadata := u64(0)
	for _ in 0 .. 128 {
		entry := runtime_symbol(library, '_$s10Foundation4DateVMa') or { panic(err) }
		descriptor := runtime_symbol(library, '_$s10Foundation4DateVMn') or { panic(err) }
		response := unsafe { SwiftDateAccess(voidptr(entry))(0xff) }
		assert response.state == 0 && read64(response.metadata + 8) == descriptor
		metadata = response.metadata
	}
	return metadata
}

fn swift_date_mapping(address u64, length u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + length <= start + size
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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
				assert mapped && address + length <= end && fields[1] == if executable {
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

fn swift_date_cases(entry u64, probe SwiftDateProbe, guard u64, page u64, interval_reader u64) {
	for seed in [u64(0), 0x1122334455667788, ~u64(0)]! {
		mut output := [u64(0xcafe), seed, 0xbeef]!
		mut context := [u64(0xcafe), 0, 0, 0xbeef]!
		probe(entry, u64(unsafe { &output[1] }), guard, unsafe { &context[1] })
		assert output == [u64(0xcafe), 0xc22d63c8c5000000, 0xbeef]!
		assert unsafe { *(&f64(&output[1])) } == -63114076800.0
		assert context == [u64(0xcafe), guard, 0x5021, 0xbeef]!
		$if macos {
			if interval_reader != 0 {
				mut readback := [u64(0xcafe), 0, 0, 0, 0xbeef]!
				reader := unsafe { SwiftDateProbe(voidptr(u64(voidptr(probe)) + 128)) }
				reader(interval_reader, u64(unsafe { &output[1] }), guard, unsafe { &readback[1] })
				assert readback == [u64(0xcafe), 0xc22d63c8c5000000, u64(unsafe { &output[1] }),
					0x5021, 0xbeef]!
			}
		}
	}
	// The sole writable result word touches either edge of a guarded page.
	for destination in [guard + page, guard + page * 2 - 8]! {
		unsafe { *(&u64(destination)) = ~u64(0) }
		mut context := [2]u64{}
		probe(entry, destination, guard, unsafe { &context[0] })
		assert read64(destination) == 0xc22d63c8c5000000 && context == [guard, u64(0x5021)]!
	}
}

fn swift_date_worker(entry u64, probe SwiftDateProbe, guard u64) {
	for _ in 0 .. 256 {
		mut output := [u64(0xcafe), ~u64(0), 0xbeef]!
		mut context := [2]u64{}
		probe(entry, u64(unsafe { &output[1] }), guard, unsafe { &context[0] })
		assert output == [u64(0xcafe), 0xc22d63c8c5000000, 0xbeef]! && context == [
			guard,
			u64(0x5021),
		]!
	}
}

fn swift_date_publish(framework bool) u64 {
	library := if framework {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	} else {
		'/usr/lib/swift/libswiftFoundation.dylib'
	}
	mut entry := u64(0)
	for _ in 0 .. 256 {
		entry = runtime_symbol(library, '_$s10Foundation4DateV11distantPastACvgZ') or { panic(err) }
	}
	return entry
}

fn swift_date_interval_call(entry u64, code u64, other u64, self u64, guard u64) u64 {
	mut output := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	unsafe { SwiftDateIntervalProbe(voidptr(code + 320))(entry, other, self, guard, &output[1]) }
	assert output[0] == 0xcafe && output[2] == self && output[3] == 0x5021 && output[4] == 0xbeef
	return output[1]
}

fn swift_date_intervals(entry u64, native_entry u64, code u64, guard u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	values := [u64(0), 0x8000000000000000, 0x3ff0000000000000, 0xbff0000000000000, 0x3fd0000000000000,
		0xc22d63c8c5000000, 0x7fefffffffffffff, 0xffefffffffffffff, 0x7ff0000000000000,
		0xfff0000000000000, 0x7ff8000000000042, 0xfff8000000000081]!
	for end_self in [false, true]! {
		for end_other in [false, true]! {
			self := span + u64(page) + if end_self { u64(page) - 8 } else { u64(0) }
			other := span + u64(page * 3) + if end_other { u64(page) - 8 } else { u64(0) }
			for a in values {
				for b in values {
					assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
					assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
					unsafe {
						*(&u64(self)) = a
						*(&u64(other)) = b
					}
					assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
					assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
					bits := swift_date_interval_call(entry, code, other, self, guard)
					actual := unsafe { *(&f64(&bits)) }
					expected := unsafe { *(&f64(&a)) - *(&f64(&b)) }
					if math.is_nan(expected) {
						assert math.is_nan(actual)
					} else {
						assert bits == unsafe { *(&u64(&expected)) }
					}
					if native_entry != 0 {
						assert bits == swift_date_interval_call(native_entry, code, other, self, guard)
					}
					assert read64(self) == a && read64(other) == b
				}
			}
		}
	}
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn swift_date_equal_call(entry u64, code u64, left u64, right u64, guard u64) u64 {
	mut output := [u64(0xcafe), u64(-1), 0, 0, 0xbeef]!
	unsafe { SwiftDateIntervalProbe(voidptr(code + 416))(entry, left, right, guard, &output[1]) }
	assert output[0] == 0xcafe && output[2] == guard && output[3] == 0x5021 && output[4] == 0xbeef
	assert output[1] <= 1 // Bool result must also clear the upper register bits.
	return output[1]
}

fn swift_date_equal_cases(entry u64, native_entry u64, code u64, guard u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	values := [u64(0), 0x8000000000000000, 1, 0x8000000000000001, 0x3ff0000000000000,
		0xbff0000000000000, 0x3fd0000000000000, 0xc22d63c8c5000000, 0x7fefffffffffffff,
		0xffefffffffffffff, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000042,
		0xfff8000000000081, 0x7ff0000000000042, 0xfff0000000000081]!
	for end_left in [false, true]! {
		for end_right in [false, true]! {
			left := span + u64(page) + if end_left { u64(page) - 8 } else { u64(0) }
			right := span + u64(page * 3) + if end_right { u64(page) - 8 } else { u64(0) }
			for a in values {
				for b in values {
					assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
					assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
					unsafe {
						*(&u64(left)) = a
						*(&u64(right)) = b
					}
					assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
					assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
					result := swift_date_equal_call(entry, code, left, right, guard)
					expected := u64(unsafe { *(&f64(&a)) == *(&f64(&b)) })
					assert result == expected
					if native_entry != 0 {
						assert result == swift_date_equal_call(native_entry, code, left, right, guard)
					}
					alias := swift_date_equal_call(entry, code, left, left, guard)
					assert alias == u64(!math.is_nan(unsafe { *(&f64(&a)) }))
					assert read64(left) == a && read64(right) == b
				}
			}
		}
	}
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn swift_date_now_value(entry u64, clock u64, probe SwiftDateProbe, guard u64) f64 {
	before := unsafe { SwiftDateClock(voidptr(clock))() }
	mut output := [u64(0xcafe), u64(-1), 0xbeef]!
	mut context := [u64(0xcafe), 0, 0, 0xbeef]!
	probe(entry, u64(unsafe { &output[1] }), guard, unsafe { &context[1] })
	after := unsafe { SwiftDateClock(voidptr(clock))() }
	value := unsafe { *(&f64(&output[1])) }
	assert output[0] == 0xcafe && output[2] == 0xbeef
	assert context == [u64(0xcafe), guard, 0x5021, 0xbeef]!
	assert math.is_finite(value) && value >= math.min(before, after) - 0.00001 && value <= math.max(before, after) + 0.00001
	return value
}

fn swift_date_now_cases(entry u64, clock u64, probe SwiftDateProbe, guard u64, page u64) {
	for _ in 0 .. 16 { swift_date_now_value(entry, clock, probe, guard) }
	for destination in [guard + page, guard + page * 2 - 8]! {
		before := unsafe { SwiftDateClock(voidptr(clock))() }
		unsafe { *(&u64(destination)) = u64(-1) }
		mut context := [2]u64{}
		probe(entry, destination, guard, unsafe { &context[0] })
		after := unsafe { SwiftDateClock(voidptr(clock))() }
		value := unsafe { *(&f64(destination)) }
		assert math.is_finite(value) && value >= math.min(before, after) - 0.00001 && value <= math.max(before, after) + 0.00001
		assert context == [guard, u64(0x5021)]!
	}
}

fn swift_date_value_worker(equal u64, now u64, clock u64, probe SwiftDateProbe, code u64, guard u64) {
	word := u64(C.__builtin_alloca(8))
	for _ in 0 .. 64 {
		value := swift_date_now_value(now, clock, probe, guard)
		unsafe { *(&f64(word)) = value }
		assert swift_date_equal_call(equal, code, word, word, guard) == 1
	}
}

fn test_swift_date() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	assert C.mprotect(unsafe { voidptr(guard + u64(page)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	// Ordinary entry/output/protected-unused/context -> Swift x8 result.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103e8,
		0xaa0203f4, 0xaa1403e0, 0xaa1403e1, 0xaa1403e2, 0xaa1403e3, 0xaa1403e4, 0xaa1403e5, 0xaa1403e6,
		0xaa1403e7, 0xd28a0435, 0xd2efff09, 0x9e670120, 0xd63f0200, 0xa9005674, 0xa94153f3, 0xa9425bf5,
		0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	// Native timeIntervalSince borrows Self in x20 and a zero Date at code+256 in x0. Capture its Double result from d0.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103f4,
		0x10000340, 0xaa0203e8, 0xd28a0435, 0xd63f0200, 0x9e660000, 0xf9000260, 0xa900d674, 0xa94153f3,
		0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	// Ordinary entry/other/Self/protected-x8/output -> Swift method registers.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0403f3, 0xaa0203f4,
		0xaa0103e0, 0xaa0303e8, 0xd28a0435, 0xd63f0200, 0x9e660000, 0xf9000260, 0xa900d674, 0xa94153f3,
		0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 320 + u64(i * 4), op)
	}
	// Static equality borrows x0/x1, leaves protected x8 and Self alone,
	// and returns the full canonical Bool register without a float conversion.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0403f3, 0xaa0303f4,
		0xaa0303e8, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0303e4, 0xaa0303e5, 0xaa0303e6, 0xaa0303e7,
		0xd28a0435, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 416 + u64(i * 4), op)
	}
	// Metadata accessor returns a complete x0/x1 pair for any request, while
	// preserving Swift context. This also probes the descriptor's accessor.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0103f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 544 + u64(i * 4), op)
	}
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 600) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { SwiftDateProbe(voidptr(code)) }
	mut interval_reader := u64(0)
	mut native_equal := u64(0)
	mut clock := u64(unsafe { voidptr(cf_absolute_time) })
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', C.RTLD_NOW)
		overlay := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		assert foundation != unsafe { nil } && overlay != unsafe { nil }
		entry := u64(C.dlsym(foundation, c'$s10Foundation4DateV11distantPastACvgZ'))
		assert entry != 0 && entry == u64(C.dlsym(overlay, c'$s10Foundation4DateV11distantPastACvgZ'))
		interval_reader = u64(C.dlsym(foundation, c'$s10Foundation4DateV17timeIntervalSinceySdACF'))
		assert interval_reader != 0
		native_equal = u64(C.dlsym(foundation, c'$s10Foundation4DateV2eeoiySbAC_ACtFZ'))
		native_now := u64(C.dlsym(foundation, c'$s10Foundation4DateVACycfC'))
		clock = u64(C.dlsym(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2), c'CFAbsoluteTimeGetCurrent'))
		assert native_equal != 0 && native_now != 0 && clock != 0
		assert native_equal == u64(C.dlsym(overlay, c'$s10Foundation4DateV2eeoiySbAC_ACtFZ'))
		assert native_now == u64(C.dlsym(overlay, c'$s10Foundation4DateVACycfC'))
		access := C.dlsym(foundation, c'$s10Foundation4DateVMa')
		assert access != unsafe { nil }
		response := unsafe { SwiftDateAccess(access)(0) }
		metadata := response.metadata
		witness := read64(metadata - 8) & u64(0x0000ffffffffffff)
		assert read64(witness + 64) == 8 && read64(witness + 72) == 8
		descriptor := u64(C.dlsym(foundation, c'$s10Foundation4DateVMn'))
		assert descriptor != 0 && descriptor == u64(C.dlsym(overlay, c'$s10Foundation4DateVMn'))
		assert u64(access) == u64(C.dlsym(overlay, c'$s10Foundation4DateVMa'))
		assert swift_date_metadata_cases(u64(access), descriptor, code, true) == metadata
		swift_date_witness_cases(metadata, guard)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		lookup := C.dlsym(core, c'swift_getTypeByMangledNameInContextInMetadataState')
		assert lookup != unsafe { nil }
		swift_date_symbolic(unsafe { SwiftDateLookup(lookup) }, descriptor, metadata)
		encoding_conformance := u64(C.dlsym(foundation, c'$s10Foundation4DateVSEAAMc'))
		encoding_entry := u64(C.dlsym(foundation, c'$s10Foundation4DateV6encode2toys7Encoder_p_tKF'))
		assert encoding_conformance != 0 && encoding_entry != 0
		table_lookup := unsafe { DateEncodingTable(C.dlsym(core, c'swift_getWitnessTable')) }
		encoding_table := table_lookup(encoding_conformance, metadata, 0)
		assert encoding_table != 0 && read64(encoding_table) == encoding_conformance
		date_encoding_suite(encoding_entry, read64(encoding_table + 8) & 0x0000ffffffffffff, true)
		swift_date_cases(entry, probe, guard, u64(page), interval_reader)
		swift_date_intervals(interval_reader, 0, code, guard)
		swift_date_equal_cases(native_equal, 0, code, guard)
		swift_date_now_cases(native_now, clock, probe, guard, u64(page))
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn swift_date_worker(entry, probe, guard) }
		workers.wait()
		unsafe { workers.free() }
		mut value_workers := []thread{}
		for _ in 0 .. 8 {
			value_workers << spawn swift_date_value_worker(native_equal, native_now, clock, probe, code, guard)
		}
		value_workers.wait()
		unsafe { value_workers.free() }
		println('IOS-SWIFT-DATE-NATIVE: Date Encodable/public encoding, borrowed inline/boxed Encoder, owned inline container, exact Double bits, success/error cleanup and context, concurrent calls; nominal POD8 metadata/witnesses, enums, symbolic lookup, distantPast, intervals/equality and fresh Date() measured')
	}
	if _ := swift_foundation_symbol('_$s10Foundation4DateV11distantPastACvgZ') {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		mut metadata_workers := []thread u64{}
		for i in 0 .. 8 { metadata_workers << spawn swift_date_metadata_publish(i % 2 == 0) }
		metadata_results := metadata_workers.wait()
		metadata := metadata_results[0]
		for result in metadata_results { assert result == metadata }
		unsafe { metadata_workers.free(); metadata_results.free() }
		accessor := swift_foundation_symbol('_$s10Foundation4DateVMa') or { panic(err) }
		descriptor := swift_foundation_symbol('_$s10Foundation4DateVMn') or { panic(err) }
		assert swift_date_metadata_cases(accessor, descriptor, code, false) == metadata
		assert metadata != swift_integer_metadata() && metadata != swift_string_metadata()
		swift_date_witness_cases(metadata, guard)
		swift_date_symbolic(unsafe { SwiftDateLookup(voidptr(swift_mangled_state_lookup)) }, descriptor, metadata)
		encoding_conformance := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_$s10Foundation4DateVSEAAMc') or { panic(err) }
		encoding_entry := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$s10Foundation4DateV6encode2toys7Encoder_p_tKF') or { panic(err) }
		encoding_table := swift_witness_table(encoding_conformance, metadata, 0)
		assert read64(encoding_table) == encoding_conformance && read64(encoding_table + 8) == encoding_entry
		protocol := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSEMp') or { panic(err) }
		assert swift_date_relative(encoding_conformance) == protocol && read32(encoding_conformance + 12) == 0
		assert swift_date_relative(encoding_conformance + 4) == descriptor
		assert read32(protocol) == 0x30043 && read32(protocol + 16) == 1 && read32(protocol + 24) == 0x69460011
		assert unsafe { (&char(swift_date_relative(protocol + 8))).vstring() } == 'Encodable'
		assert (runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSE6encode2toys7Encoder_p_tKFTq') or { panic(err) }) == protocol + 24
		date_encoding_suite(encoding_entry, read64(encoding_table + 8), false)
		mut publishers := []thread u64{}
		for i in 0 .. 8 { publishers << spawn swift_date_publish(i % 2 == 0) }
		entries := publishers.wait()
		entry := entries[0]
		for candidate in entries {
			assert candidate == entry
		}
		arena := ios_runtime.swift_foundation_arena
		assert entry == arena + 1152
		interval_entry := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$s10Foundation4DateV17timeIntervalSinceySdACF') or { panic(err) }
		assert interval_entry == arena + 1184
		assert interval_entry == runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_$s10Foundation4DateV17timeIntervalSinceySdACF') or { panic(err) }
		equal := swift_foundation_symbol('_$s10Foundation4DateV2eeoiySbAC_ACtFZ') or { panic(err) }
		now := swift_foundation_symbol('_$s10Foundation4DateVACycfC') or { panic(err) }
		assert equal == arena + 1216 && now == arena + 1248
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation',
			'/usr/lib/swift/libswiftFoundation.dylib']! {
			assert accessor == runtime_symbol(library, '_$s10Foundation4DateVMa') or { panic(err) }
			assert descriptor == runtime_symbol(library, '_$s10Foundation4DateVMn') or { panic(err) }
			assert encoding_conformance == runtime_symbol(library, '_$s10Foundation4DateVSEAAMc') or { panic(err) }
			assert encoding_entry == runtime_symbol(library, '_$s10Foundation4DateV6encode2toys7Encoder_p_tKF') or { panic(err) }
			assert equal == runtime_symbol(library, '_$s10Foundation4DateV2eeoiySbAC_ACtFZ') or { panic(err) }
			assert now == runtime_symbol(library, '_$s10Foundation4DateVACycfC') or { panic(err) }
		}
		swift_date_mapping(entry, 24, true, true)
		swift_date_mapping(arena + u64(page), 96, true, false)
		swift_date_cases(entry, probe, guard, u64(page), interval_reader)
		swift_date_cases(entry, probe, guard, u64(page), interval_entry)
		swift_date_intervals(interval_entry, interval_reader, code, guard)
		swift_date_equal_cases(equal, native_equal, code, guard)
		swift_date_now_cases(now, clock, probe, guard, u64(page))
		mut value_workers := []thread{}
		for _ in 0 .. 8 {
			value_workers << spawn swift_date_value_worker(equal, now, clock, probe, code, guard)
		}
		value_workers.wait()
		unsafe { value_workers.free() }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn swift_date_worker(entry, probe, guard) }
		workers.wait()
		for unsupported in ['_$s10Foundation4DateVN', '_$s10Foundation4DateVSeAAMc', '_$s10Foundation4DateVSQAAMc',
			'_$s10Foundation4DateV13distantFutureACvgZ']! {
			if _ := swift_foundation_symbol(unsupported) {
				assert false
			}
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$s10Foundation4DateV11distantPastACvgZ') {
			assert false
		}
		if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_$s10Foundation4DateV11distantPastACvgZ') {
			assert false
		}
		for name in ['_$s10Foundation4DateVSEAAMc', '_$s10Foundation4DateV6encode2toys7Encoder_p_tKF', '_$s10Foundation4DateVMa', '_$s10Foundation4DateVMn', '_$s10Foundation4DateV2eeoiySbAC_ACtFZ', '_$s10Foundation4DateVACycfC']! {
			if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) {
				assert false
			}
			if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', name) {
				assert false
			}
		}
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		swift_date_mapping(arena, u64(page) * 2, false, false)
		if _ := swift_foundation_symbol('_$s10Foundation4DateV11distantPastACvgZ') {
			assert false
		}
		for name in ['_$s10Foundation4DateVSEAAMc', '_$s10Foundation4DateV6encode2toys7Encoder_p_tKF', '_$s10Foundation4DateVMa', '_$s10Foundation4DateVMn', '_$s10Foundation4DateV2eeoiySbAC_ACtFZ', '_$s10Foundation4DateVACycfC']! {
			if _ := swift_foundation_symbol(name) {
				assert false
			}
		}
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0 && C.munmap(unsafe { voidptr(guard) }, page * 3) == 0
	println('IOS-SWIFT-DATE: concrete Encodable conformance and protocol, public encoding via borrowed inline/boxed Encoder and owned inline container, native Double bits, success/error cleanup and concurrency; nominal POD8 metadata, enum tags, symbolic lookup, distantPast, intervals/equality and Date(), scoped exports and two drained/unmapped lifetimes')
}
