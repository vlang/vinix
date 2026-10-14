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
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
type AlgebraProbe = fn (u64, &u64, u64, u64, &u64)
type AlgebraSign = fn (u64, u64) u64
struct AlgebraState {
mut:
	captured [16]u64
	calls int
	native bool
	mode int
	object u64
}
fn algebra_pair(op u32, first u32, second u32, base u32, offset u32) u32 {
	return op | ((offset / 8) << 15) | (second << 10) | (base << 5) | first
}
fn algebra_mov(destination u32, source u32) u32 { return 0xaa0003e0 | (source << 16) | destination }
fn algebra_emit(code u64) {
	// C caller -> Swift entry. Save callee registers, load all integer inputs,
	// preserve separate x8/x20/x21, and record the witness's returned registers.
	ops := [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xa90363f7,
		algebra_mov(16,0),algebra_mov(9,1),algebra_mov(20,2),algebra_mov(8,3),algebra_mov(19,4),u32(0x910003f6),
		algebra_pair(0xa9400000,0,1,9,0),algebra_pair(0xa9400000,2,3,9,16),algebra_pair(0xa9400000,4,5,9,32),algebra_pair(0xa9400000,6,7,9,48),
		u32(0xf9402135),u32(0xd2800000 | (0x5023 << 5) | 23),u32(0xd2800000 | (0x5024 << 5) | 24),u32(0xd63f0200),
		algebra_pair(0xa9000000,0,1,19,0),algebra_pair(0xa9000000,20,21,19,16),algebra_pair(0xa9000000,22,23,19,32),u32(0xf9001a78),
		u32(0xa94153f3),0xa9425bf5,0xa94363f7,0xa8c47bfd,0xd65f03c0]!
	for i, op in ops { write32(code + u64(i * 4), op) }
	// Capture at the exact witness entry before adapting to a V callback.
	for i, op in [algebra_pair(0xa9000000,0,1,20,0),algebra_pair(0xa9000000,2,3,20,16),
		algebra_pair(0xa9000000,4,5,20,32),algebra_pair(0xa9000000,6,7,20,48),
		algebra_pair(0xa9000000,8,20,20,64),algebra_pair(0xa9000000,21,22,20,80),
		algebra_pair(0xa9000000,23,24,20,96),u32(0x910003e9),algebra_pair(0xa9000000,9,30,20,112),
		u32(0xa9bf7bfd),algebra_mov(0,20),u32(0x580000b0),u32(0xd63f0200),u32(0xa8c17bfd),u32(0xd65f03c0),u32(0xd503201f)]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 192)) = u64(voidptr(algebra_witness)) }
	write32(code + 224,0xdac10020); write32(code + 228,0xd65f03c0) // Native PACIA.
}
fn algebra_keep(native bool, object u64) {
	$if macos { if native { C.CFRetain(voidptr(object)); return } }
	objc_retain(object)
}
fn algebra_drop(native bool, object u64) {
	$if macos { if native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}
fn algebra_refs(native bool, object u64) i64 {
	$if macos { if native { return C.CFGetRetainCount(voidptr(object)) } }
	return obj_header(object).refs
}
fn algebra_lookup() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj') or { panic(err) }
}
fn algebra_witness(context u64) SwiftStringWords {
	mut state := unsafe { &AlgebraState(context) }; state.calls++
	if state.mode != 0 {
		assert state.calls == 1 && read64(state.captured[0]) == state.object
		assert algebra_refs(state.native,state.object) == 2
		unsafe { *(&u64(state.captured[0])) = 0 }
		if state.mode == 2 { algebra_drop(state.native,state.object) }
		output := state.captured[8]
		for i in 0 .. 6 { unsafe { *(&u64(output + u64(i * 8))) = if i == 0 && state.mode == 1 { state.object } else { u64(i + 0xc080) } } }
		if !state.native { worker := spawn algebra_lookup(); assert worker.wait() == ios_runtime.swift_set_arena + 960 }
	}
	return SwiftStringWords{first:0xc011,second:0xc012}
}
fn algebra_case(entry u64, code u64, native bool, table u64, slot u64, guard u64, mode int, seed u64) {
	mut state := AlgebraState{native:native,mode:mode}
	mut source := [u64(0),0x101,0x102,0x103]!
	mut object := u64(0)
	if mode != 0 {
		$if macos { if native { object = u64(C.CFStringCreateMutable(unsafe { nil },0)) } }
		if !native { object = owned_string('SetAlgebra witness-owned source') }
		algebra_keep(native,object); source[0] = object; state.object = object
	}
	mut destination := [16]u64{}; for i in 0 .. 16 { destination[i] = 0xa5a5a5a5a5a5a5a5 }
	output := (u64(unsafe { &destination[0] }) + 39) & ~u64(31)
	mut args := [if mode == 0 { seed ^ 0x810080 } else { u64(unsafe { &source[0] }) },guard,guard + 3,guard + 5,table,0x55,0x66,seed ^ 0x77777777,seed ^ 0x21212121]!
	mut returned := [7]u64{}
	probe := unsafe { AlgebraProbe(voidptr(code)) }; receiver := u64(unsafe { &state })
	probe(entry & 0x0000ffffffffffff,unsafe { &args[0] },receiver,output,unsafe { &returned[0] })
	assert state.calls == 1
	for i in 0 .. 5 { assert state.captured[i] == args[i] }
	assert state.captured[5] == slot && state.captured[6] == read64(slot) && state.captured[7] == args[7]
	assert state.captured[8] == output && state.captured[9] == receiver && state.captured[10] == args[8]
	assert state.captured[11] == returned[4] && state.captured[14] == returned[4] && state.captured[15] == code + 72
	assert state.captured[12] == 0x5023 && state.captured[13] == 0x5024
	assert returned[0] == 0xc011 && returned[1] == 0xc012 && returned[2] == receiver && returned[3] == args[8]
	assert returned[5] == 0x5023 && returned[6] == 0x5024
	for i in 0 .. 16 {
		address := u64(unsafe { &destination[0] }) + u64(i * 8)
		if mode != 0 && address >= output && address < output + 48 {
			assert destination[i] == if address == output && mode == 1 { object } else { (address - output) / 8 + 0xc080 }
		} else { assert destination[i] == 0xa5a5a5a5a5a5a5a5 }
	}
	if mode != 0 {
		assert source[0] == 0 && source[1] == 0x101 && source[2] == 0x102 && source[3] == 0x103
		assert algebra_refs(native,object) == if mode == 1 { i64(2) } else { i64(1) }
		if mode == 1 { algebra_drop(native,object) }; algebra_drop(native,object)
	}
}
fn algebra_suite(entry u64, code u64, native bool, mapping u64, page u64) {
	slot := mapping + page; table := slot - 160
	target := code + 128
	sign := unsafe { AlgebraSign(voidptr(code + 224)) }
	unsafe { *(&u64(slot)) = if native { sign(target,slot | (u64(62039) << 48)) } else { target } }
	for seed in [u64(0),1,0x8000000000000000,u64(-1)]! { for mode in 0 .. 3 { algebra_case(entry,code,native,table,slot,mapping,mode,seed) } }
}
fn test_swift_set_algebra() {
	page := u64(C.getpagesize()); code := u64(C.mmap(unsafe { nil },usize(page),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	mapping := u64(C.mmap(unsafe { nil },usize(page * 3),C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && mapping != u64(-1)
	assert C.mprotect(voidptr(mapping + page),usize(page),C.PROT_READ | C.PROT_WRITE) == 0
	algebra_emit(code); C.__builtin___clear_cache(voidptr(code),voidptr(code + 232)); assert C.mprotect(voidptr(code),usize(page),C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW); assert core != unsafe { nil }
		entry := u64(C.dlsym(core,c'$ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj')); assert entry != 0
		algebra_suite(entry,code,true,mapping,page); assert C.dlclose(core) == 0
		println('IOS-SET-ALGEBRA-NATIVE: witness slot160 tail dispatch, x0-x4/x7/x8/x20/x21 and original stack/LR, selected slot x5/target x6, opaque metadata/table prefix guards, 32-byte-aligned 48-byte indirect results and witness-only source ownership')
	}
	for _ in 0 .. 2 {
		objc_start(); entry := algebra_lookup(); assert entry == ios_runtime.swift_set_arena + 960
		assert read32(entry) == 0xaa0403e5 && read32(entry + 4) == 0xf84a0ca6 && read32(entry + 8) == 0xd61f00c0
		algebra_suite(entry,code,false,mapping,page)
		for i in u64(0) .. 128 { algebra_case(entry,code,false,mapping + page - 160,mapping + page,mapping,0,i) }
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop(); assert ios_runtime.swift_set_arena == 0
	}
	assert C.munmap(voidptr(mapping),usize(page * 3)) == 0 && C.munmap(voidptr(code),usize(page)) == 0
	println('IOS-SET-ALGEBRA: generic caller-witness forwarding, preserved arguments/context/result/LR/SP, protected unused records, transfer/drop ownership delegated once, unlocked cross-thread lookup, repeated cached dispatch and two drained arena lifetimes')
}
