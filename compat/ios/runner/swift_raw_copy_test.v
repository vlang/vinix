// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type RawCopyPointer = fn (u64, i64, u64)
type RawCopyBuffer = fn (u64, u64, u64, u64)
type RawCopyCount = fn (u64, u64) i64
type RawCopyBase = fn (u64, u64) u64
struct RawCopyApi {
	native bool
	pointer RawCopyPointer
	buffer RawCopyBuffer
	counts [4]RawCopyCount
	bases [2]RawCopyBase
}
fn raw_copy_api(native bool, core voidptr) RawCopyApi {
	mut counts := [4]RawCopyCount{}; mut bases := [2]RawCopyBase{}
	for i, symbol in [c'$sSw5countSivg', c'$sSW5countSivg', c'$sSw8endIndexSivg', c'$sSW8endIndexSivg', c'$sSw11baseAddressSvSgvg', c'$sSW11baseAddressSVSgvg']! {
		mut address := u64(0)
		$if macos { if native { address = u64(C.dlsym(core, symbol)) } }
		if !native { address = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_' + unsafe { symbol.vstring() }) or { panic(err) } }
		assert address != 0
		if i < 4 { counts[i] = unsafe { RawCopyCount(voidptr(address)) }; if !native { assert address == u64(unsafe { voidptr(swift_raw_buffer_count) }) } }
		else { bases[i - 4] = unsafe { RawCopyBase(voidptr(address)) }; if !native { assert address == u64(unsafe { voidptr(swift_raw_buffer_base) }) } }
	}
	$if macos { if native {
		return RawCopyApi{native: true, counts: counts, bases: bases, pointer: unsafe { RawCopyPointer(C.dlsym(core, c'$sSv10copyMemory4from9byteCountySV_SitF')) },
			buffer: unsafe { RawCopyBuffer(C.dlsym(core, c'$sSw10copyMemory4fromySW_tF')) }}
	} }
	pointer := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSv10copyMemory4from9byteCountySV_SitF') or { panic(err) }
	buffer := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSw10copyMemory4fromySW_tF') or { panic(err) }
	assert pointer == u64(unsafe { voidptr(swift_raw_pointer_copy) }) && buffer == u64(unsafe { voidptr(swift_raw_buffer_copy) })
	return RawCopyApi{counts: counts, bases: bases, pointer: unsafe { RawCopyPointer(voidptr(pointer)) }, buffer: unsafe { RawCopyBuffer(voidptr(buffer)) }}
}
fn raw_copy_getters(api RawCopyApi, guard u64, page u64) {
	for values in [[u64(0), 0, 0]!, [guard, guard, u64(0)]!, [guard, guard + 1, u64(1)]!,
		[guard + 3, guard + 260, u64(257)]!, [guard, guard + page, page]!,
		[u64(1), 0x8000000000000000, 0x7fffffffffffffff]!, [u64(-1), u64(-1), 0]!]! {
		for i in 0 .. 4 { assert api.counts[i](values[0], values[1]) == i64(values[2]) }
		for i in 0 .. 2 { assert api.bases[i](values[0], values[1]) == values[0] }
	}
}
fn raw_copy_call(api RawCopyApi, buffer bool, source u64, count i64, destination u64, capacity i64) {
	if buffer { api.buffer(source, source + u64(count), destination, destination + u64(capacity)) }
	else { api.pointer(source, count, destination) }
}
fn raw_copy_pattern(offset u64) u8 { return u8((offset * 73 + offset / 7 + 19) & 255) }
fn raw_copy_case(api RawCopyApi, buffer bool, memory u64, bytes u64, source u64, destination u64, count i64) {
	assert source + u64(count) <= bytes && destination + u64(count) + 23 <= bytes
	for i in u64(0) .. bytes { unsafe { *(&u8(memory + i)) = raw_copy_pattern(i) } }
	raw_copy_call(api, buffer, memory + source, count, memory + destination, count + 23)
	assert api.counts[0](memory + source, memory + source + u64(count)) == count
	assert api.counts[1](memory + destination, memory + destination + u64(count + 23)) == count + 23
	assert api.counts[2](memory + source, memory + source + u64(count)) == count
	assert api.counts[3](memory + destination, memory + destination + u64(count + 23)) == count + 23
	assert api.bases[0](memory + source, memory + source + u64(count)) == memory + source
	assert api.bases[1](memory + destination, memory + destination + u64(count + 23)) == memory + destination
	// The oracle reads the original pattern, independent of copy direction.
	// Checking the whole allocation includes both neighbours and spare capacity.
	for i in u64(0) .. bytes {
		expected := raw_copy_pattern(if i >= destination && i < destination + u64(count) { source + i - destination } else { i })
		assert unsafe { *(&u8(memory + i)) } == expected
	}
}
fn raw_copy_matrix(api RawCopyApi) {
	bytes := u64(16384); memory := u64(C.malloc(usize(bytes))); assert memory != 0
	for buffer in [false, true]! {
		for count in [i64(0), 1, 7, 8, 15, 16, 31, 64, 257, 4097]! {
			for offsets in [[u64(256), 8192]!, [u64(8192), 256]!, [u64(256), 257]!, [u64(257), 256]!, [u64(256), 263]!, [u64(263), 256]!, [u64(256), 256]!]! {
				raw_copy_case(api, buffer, memory, bytes, offsets[0], offsets[1], count)
			}
		}
	}
	C.free(voidptr(memory))
}
fn raw_copy_guards(api RawCopyApi, source_mapping u64, destination_mapping u64, page u64) {
	source := source_mapping + page; destination := destination_mapping + page
	assert C.mprotect(voidptr(source), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	for i in u64(0) .. page { unsafe { *(&u8(source + i)) = raw_copy_pattern(i) } }
	assert C.mprotect(voidptr(source), usize(page), C.PROT_READ) == 0
	assert C.mprotect(voidptr(destination), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	for buffer in [false, true]! {
		for count in [i64(0), 1, 7, 31, 64, 257, i64(page)]! {
			for upper in [false, true]! {
				offset := if upper { page - u64(count) } else { u64(0) }
				C.memset(voidptr(destination), 0xa5, usize(page))
				raw_copy_call(api, buffer, source + offset, count, destination + offset, count)
				for i in u64(0) .. page {
					expected := if i >= offset && i < offset + u64(count) { raw_copy_pattern(i) } else { u8(0xa5) }
					assert unsafe { *(&u8(destination + i)) } == expected && unsafe { *(&u8(source + i)) } == raw_copy_pattern(i)
				}
			}
		}
		api.pointer(source_mapping, 0, destination_mapping)
		api.buffer(source_mapping, source_mapping, destination_mapping, destination_mapping + 23)
		api.buffer(0, 0, destination_mapping, destination_mapping)
		api.buffer(source_mapping, source_mapping, 0, 0); api.buffer(0, 0, 0, 0)
	}
}
fn raw_copy_ownership(api RawCopyApi) {
	mut object := u64(0)
	$if macos { if api.native { object = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	if !api.native { object = owned_string('Raw bytes do not own their encoded addresses') }
	mut words := [object, u64(0), u64(0)]!
	source := u64(unsafe { &words[0] }); destination := u64(unsafe { &words[1] })
	api.pointer(source, 8, destination); api.buffer(source, source + 8, destination + 8, destination + 16)
	assert words[1] == object && words[2] == object
	// These are opaque address bytes, not initialized Swift reference values.
	$if macos { if api.native { assert C.CFGetRetainCount(voidptr(object)) == 1; C.CFRelease(voidptr(object)); return } }
	assert obj_header(object).refs == 1; objc_release(object)
}
fn raw_copy_rejected(guard u64) {
	for values in [[guard, u64(-1), guard]!, [u64(0), 1, guard]!, [guard, u64(1), 0]!, [u64(-8), 16, guard]!, [guard, u64(16), u64(-8)]!]! {
		if _ := swift_raw_pointer_copy_checked(values[0], i64(values[1]), values[2]) { assert false }
	}
	for values in [[u64(0), 1, guard, guard]!, [guard, guard, u64(0), 1]!, [guard, guard - 1, guard, guard]!,
		[guard, guard, guard, guard - 1]!, [u64(1), 0x8000000000000001, guard, guard]!, [guard, guard, u64(1), 0x8000000000000001]!,
		[guard, guard + 8, guard, guard + 7]!, [guard, guard + 1, u64(0), 0]!]! {
		if _ := swift_raw_buffer_copy_checked(values[0], values[1], values[2], values[3]) { assert false }
	}
	mut bytes := [16]u8{}; for i in 0 .. 16 { bytes[i] = 0x5a }
	base := u64(unsafe { &bytes[0] })
	if _ := swift_raw_buffer_copy_checked(base, base + 8, base + 8, base + 12) { assert false }
	for value in bytes { assert value == 0x5a }
}
fn raw_copy_worker(api RawCopyApi) {
	memory := u64(C.malloc(512)); assert memory != 0
	for i in 0 .. 100 { raw_copy_case(api, i & 1 == 0, memory, 512, if i & 2 == 0 { u64(64) } else { u64(71) }, if i & 2 == 0 { u64(71) } else { u64(64) }, 257) }
	C.free(voidptr(memory))
}
fn test_swift_raw_copy() {
	page := u64(C.getpagesize())
	source := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	destination := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert source != u64(-1) && destination != u64(-1)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert core != unsafe { nil }
		api := raw_copy_api(true, core); raw_copy_getters(api, source, page); raw_copy_matrix(api); raw_copy_guards(api, source, destination, page); raw_copy_ownership(api)
		assert C.dlclose(core) == 0
		println('IOS-RAW-COPY-NATIVE: source/count/Self and start/end ABI, 28 count/endIndex and 14 base getters including maximum signed count, 140 whole-allocation comparisons, forward/backward/self/disjoint overlap, 28 page-edge ranges, read-only source, protected empty/nil buffers and opaque-address ownership')
	}
	for _ in 0 .. 2 {
		objc_start(); api := raw_copy_api(false, unsafe { nil }); raw_copy_getters(api, source, page); raw_copy_matrix(api); raw_copy_guards(api, source, destination, page); raw_copy_ownership(api); raw_copy_rejected(source)
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn raw_copy_worker(api) }; workers.wait()
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
	}
	assert C.munmap(voidptr(source), usize(page * 3)) == 0 && C.munmap(voidptr(destination), usize(page * 3)) == 0
	println('IOS-RAW-COPY: native count/endIndex/base getter ABI, exact byte/overlap agreement, preserved neighbours/spare capacity and ownership, guard-adjacent copies, empty no-access paths, rejected negative/null/reversed/oversized/overflow ranges before writes, eight workers and two drained lifetimes')
}
