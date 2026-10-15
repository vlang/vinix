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
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 504) })
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
		println('IOS-SWIFT-DATE-NATIVE: distantPast bits and interval consumer; equality of finite values, signed zero, subnormals, infinities, quiet/signaling NaNs and aliases; Date() bounded by the CF clock, guarded eight-byte spans, protected unused registers, canonical Bool/context and concurrent calls measured')
	}
	if _ := swift_foundation_symbol('_$s10Foundation4DateV11distantPastACvgZ') {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
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
		for unsupported in ['_$s10Foundation4DateVMa', '_$s10Foundation4DateVMn',
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
		for name in ['_$s10Foundation4DateV2eeoiySbAC_ACtFZ', '_$s10Foundation4DateVACycfC']! {
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
		for name in ['_$s10Foundation4DateV2eeoiySbAC_ACtFZ', '_$s10Foundation4DateVACycfC']! {
			if _ := swift_foundation_symbol(name) {
				assert false
			}
		}
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0 && C.munmap(unsafe { voidptr(guard) }, page * 3) == 0
	println('IOS-SWIFT-DATE: distantPast, intervals, canonical floating equality and fresh nanosecond-clock Date() values, guarded readonly inputs and x8 result boundaries, unused registers and context, native IEEE/alias behavior, concurrent calls, scoped publication and two unchanged-ownership/unmapped teardowns')
}
