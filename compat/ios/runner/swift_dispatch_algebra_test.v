// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
type DispatchAlgebraProbe = fn (u64, &u64, u64, u64, &u64)
type DispatchAlgebraLookup = fn (u64, u64, u64) u64
type DispatchAlgebraAccess = fn (u64) SwiftAssociatedMetadata
type DispatchAlgebraArrayAccess = fn (u64, u64) SwiftAssociatedMetadata
type DispatchAlgebraAllocate = fn (i64, u64) SwiftArrayAllocation
type DispatchAlgebraKeep = fn (u64) u64
type DispatchAlgebraDrop = fn (u64)
type DispatchAlgebraAssociated = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata

fn dispatch_algebra_mov(destination u32, source u32) u32 { return 0xaa0003e0 | (source << 16) | destination }
fn dispatch_algebra_relative(field u64) u64 { return u64(i64(field) + i64(i32(read32(field)))) }
fn dispatch_algebra_pair(op u32, first u32, second u32, base u32, offset u32) u32 { return op | ((offset / 8) << 15) | (second << 10) | (base << 5) | first }
fn dispatch_algebra_probe(code u64) DispatchAlgebraProbe {
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xa90363f7,
		dispatch_algebra_mov(16,0),dispatch_algebra_mov(9,1),dispatch_algebra_mov(20,2),dispatch_algebra_mov(8,3),dispatch_algebra_mov(19,4),u32(0x910003f6),
		dispatch_algebra_pair(0xa9400000,0,1,9,0),dispatch_algebra_pair(0xa9400000,2,3,9,16),dispatch_algebra_pair(0xa9400000,4,5,9,32),dispatch_algebra_pair(0xa9400000,6,7,9,48),
		u32(0xf9402135),u32(0xd2800000 | (0x5023 << 5) | 23),u32(0xd2800000 | (0x5024 << 5) | 24),u32(0xd63f0200),
		dispatch_algebra_pair(0xa9000000,0,1,19,0),dispatch_algebra_pair(0xa9000000,20,21,19,16),dispatch_algebra_pair(0xa9000000,22,23,19,32),u32(0xf9001a78),
		u32(0xa94153f3),0xa9425bf5,0xa94363f7,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code + 112))
	assert C.mprotect(voidptr(code),usize(C.getpagesize()),C.PROT_READ | C.PROT_EXEC) == 0
	return unsafe { DispatchAlgebraProbe(voidptr(code)) }
}
fn dispatch_algebra_call(probe DispatchAlgebraProbe, entry u64, args &u64, receiver u64, output u64) u64 {
	mut returned := [7]u64{}
	probe(entry & 0x0000ffffffffffff,args,receiver,output,unsafe { &returned[0] })
	assert returned[2] == receiver && returned[3] == 0x5021 && returned[5] == 0x5023 && returned[6] == 0x5024
	return returned[0]
}
fn dispatch_algebra_scalar(probe DispatchAlgebraProbe, table u64, metadata u64) {
	for self_bits in [u64(0),1,3,6,0xffffffff,0x100000000,0x8000000000000000,~u64(0)]! {
		for member_bits in [u64(0),1,3,6,0xffffffff,0x100000000,0x8000000000000000,~u64(0)]! {
			for slot in 4..22 {
				if slot == 20 { continue }
				mut receiver := [u64(0xcafe),self_bits,0xbeef]!
				mut member := [u64(0xcafe),member_bits,0xbeef]!
				mut result := [u64(0xcafe),0xa5a5a5a5a5a5a5a5,0xa5a5a5a5a5a5a5a5,0xbeef]!
				output := u64(unsafe { &result[1] }); self_pointer := u64(unsafe { &receiver[1] })
				member_pointer := u64(unsafe { &member[1] })
				mut args := [if slot == 9 { output } else { member_pointer },if slot == 9 { member_pointer } else { metadata },table,u64(0),0,0,0,0,0x5021]!
				returned := dispatch_algebra_call(probe,read64(table + u64(slot * 8)),unsafe { &args[0] },self_pointer,output)
				assert receiver[0] == 0xcafe && receiver[2] == 0xbeef && member == [u64(0xcafe),member_bits,0xbeef]!
				assert result[0] == 0xcafe && result[3] == 0xbeef
				value := match slot { 4 { u64(0) } 6 { self_bits | member_bits } 7 { self_bits & member_bits } 8 { self_bits ^ member_bits } 9 { member_bits } 10,11 { self_bits & member_bits } 15 { self_bits & ~member_bits } else { u64(0xa5a5a5a5a5a5a5a5) } }
				assert result[1] == value
				assert result[2] == if slot in [10,11]! { u64(0xa5a5a5a5a5a5a500) | if value == 0 { u64(1) } else { u64(0) } } else { u64(0xa5a5a5a5a5a5a5a5) }
				assert receiver[1] == match slot { 9,11,12 { self_bits | member_bits } 10,21 { self_bits & ~member_bits } 13 { self_bits & member_bits } 14 { self_bits ^ member_bits } else { self_bits } }
				if slot in [5,9,16,17,18,19]! {
					expected := match slot { 5,18 { member_bits & ~self_bits == 0 } 9 { member_bits & ~self_bits != 0 } 16 { self_bits & ~member_bits == 0 } 17 { self_bits & member_bits == 0 } else { self_bits == 0 } }
					assert returned == if expected { u64(1) } else { u64(0) }
				}
			}
			mut left := self_bits; mut right := member_bits
			mut args := [u64(unsafe { &left }),u64(unsafe { &right }),metadata,read64(table + 8),u64(0),0,0,0,0x5021]!
			assert dispatch_algebra_call(probe,read64(read64(table + 8) + 8),unsafe { &args[0] },0x5020,0) == if self_bits == member_bits { u64(1) } else { u64(0) }
		}
	}
}
fn dispatch_algebra_constructors(probe DispatchAlgebraProbe, table u64, metadata u64, core voidptr, native bool, guard u64) {
	mut array_metadata := u64(0); mut sequence_table := u64(0); mut dispatcher := u64(0)
	if native {
		array_factory := unsafe { DispatchAlgebraArrayAccess(C.dlsym(core,c'$sSaMa')) }; array_metadata = array_factory(0,metadata).metadata
		lookup := unsafe { DispatchAlgebraLookup(C.dlsym(core,c'swift_getWitnessTable')) }
		sequence_table = lookup(u64(C.dlsym(core,c'$sSayxGSTsMc')),array_metadata,0)
		dispatcher = u64(C.dlsym(core,c'$ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj'))
	} else {
		array_metadata = swift_array_access(0,metadata).metadata
		sequence_table = swift_array_sequence_table_checked(array_metadata) or { panic(err) }
		dispatcher = runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj') or { panic(err) }
	}
	assert array_metadata != 0 && sequence_table != 0 && dispatcher != 0
	for count in [i64(0),1,3,8,9,33]! {
		for mode in 0..3 {
			mut allocation := SwiftArrayAllocation{}
			if native { allocate := unsafe { DispatchAlgebraAllocate(C.dlsym(core,c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) }; allocation = allocate(count,metadata) }
			else { allocation = swift_array_allocate(count,metadata) }
			mut expected := u64(0)
			for i in i64(0)..count { bits := if i % 3 == 0 { u64(0) } else { u64(1) << u64(i % 64) }; expected |= bits; unsafe { *(&u64(allocation.bytes + u64(i * 8))) = bits } }
			if native { keep := unsafe { DispatchAlgebraKeep(C.dlsym(core,c'swift_bridgeObjectRetain')) }; assert keep(allocation.owner) == allocation.owner }
			else { swift_bridge_retain(allocation.owner) }
			before := read64(allocation.owner + 8)
			mut source := [u64(0xcafe),allocation.owner,0xbeef]!
			mut result := [u64(0xcafe),0xa5a5a5a5a5a5a5a5,0xbeef]!
			mut args := [if mode == 0 { allocation.owner } else { u64(unsafe { &source[1] }) },array_metadata,sequence_table,metadata,table,u64(0),0,0,0x5021]!
			entry := if mode == 0 { read64(read64(table + 16) + 16) } else if mode == 1 { read64(table + 160) } else { dispatcher }
			dispatch_algebra_call(probe,entry,unsafe { &args[0] },guard,u64(unsafe { &result[1] }))
			assert result == [u64(0xcafe),expected,0xbeef]! && source[0] == 0xcafe && source[2] == 0xbeef
			assert read64(allocation.owner + 8) == if count == 0 { before } else { before - (u64(1) << 33) }
			if native { drop := unsafe { DispatchAlgebraDrop(C.dlsym(core,c'swift_bridgeObjectRelease')) }; drop(allocation.owner) }
			else { swift_bridge_release(allocation.owner); assert ios_runtime.swift_arrays.len == 0 }
		}
	}
}
fn dispatch_algebra_worker(first int) u64 {
	for _ in 0..256 {
		if first < 2 {
			symbol := if first == 0 { '_$s8Dispatch0A13WorkItemFlagsVs10SetAlgebraAAMc' } else { '_$sSo17OS_dispatch_queueC8DispatchE10AttributesVs10SetAlgebraACMc' }
			runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib',symbol) or { panic(err) }
		}
		base := swift_dispatch_flags_arena_checked() or { panic(err) }
		data := base + u64(C.getpagesize())
		assert swift_witness_table_checked(data + 256,data + 16,0) or { panic(err) } == data + 320
		assert swift_witness_table_checked(data + 1440,data + 1280,0) or { panic(err) } == data + 1504
	}
	return ios_runtime.swift_dispatch_flags_arena
}
fn test_swift_dispatch_algebra() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && guard != u64(-1); probe := dispatch_algebra_probe(code)
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib',2); core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		assert lib != unsafe { nil } && core != unsafe { nil }
		lookup := unsafe { DispatchAlgebraLookup(C.dlsym(core,c'swift_getWitnessTable')) }
		associated := unsafe { DispatchAlgebraAssociated(C.dlsym(core,c'swift_getAssociatedTypeWitness')) }
		protocol := u64(C.dlsym(core,c'$ss10SetAlgebraMp'))
		literal_protocol := u64(C.dlsym(core,c'$ss25ExpressibleByArrayLiteralMp'))
		for name in ['8Dispatch0A13WorkItemFlagsV','So17OS_dispatch_queueC8DispatchE10AttributesV']! {
			accessor := C.dlsym(lib,('\$s' + name + 'Ma').str)
			conformance := C.dlsym(lib,('\$s' + name + if name.starts_with('8') { 's10SetAlgebraAAMc' } else { 's10SetAlgebraACMc' }).str)
			assert accessor != unsafe { nil } && conformance != unsafe { nil }
			access := unsafe { DispatchAlgebraAccess(accessor) }; metadata := access(0).metadata
			table := lookup(u64(conformance),metadata,0)
			dispatch_algebra_scalar(probe,table,metadata); dispatch_algebra_constructors(probe,table,metadata,core,true,guard)
			assert associated(0,table,metadata,protocol + 40,protocol + 64).metadata == metadata
			assert associated(0,read64(table + 16),metadata,literal_protocol + 16,literal_protocol + 24).metadata == metadata
		}
		println('IOS-DISPATCH-ALGEBRA-NATIVE: Flags and Attributes scalar/inherited equality witnesses, zero/overlap/high-bit matrix, optional payload/tag guards, x20/x21 preservation, literal/direct/forwarded Array constructors and exact source consumption')
	}
	for _ in 0..2 {
		objc_start(); mut workers := []thread u64{}
		for i in 0..8 { workers << spawn dispatch_algebra_worker(i % 3) }
		bases := workers.wait(); base := bases[0]; for candidate in bases { assert candidate == base }
		data := base + u64(page)
		for kind in 0..2 {
			metadata := data + if kind == 0 { u64(16) } else { u64(1280) }
			other_metadata := data + if kind == 0 { u64(1280) } else { u64(16) }
			record := data + if kind == 0 { u64(256) } else { u64(1440) }
			table := swift_witness_table_checked(record,metadata,guard) or { panic(err) }
			assert table == data + if kind == 0 { u64(320) } else { u64(1504) }
			assert read32(record + 12) == 0 && read64(table) == record
			assert dispatch_algebra_relative(record) == data + 576 && dispatch_algebra_relative(record + 4) == read64(metadata + 8)
			assert read32(data + 576) == 0x30043 && read32(data + 588) == 2 && read32(data + 592) == 21
			assert swift_associated_type(0x1ff,table,metadata,data + 616,data + 640).metadata == metadata
			assert swift_associated_type(0,read64(table + 16),metadata,data + 816,data + 824).metadata == metadata
			assert read64(table + 8) == swift_witness_table_checked(record + 32,metadata,guard) or { panic(err) }
			assert read64(table + 16) == swift_witness_table_checked(record + 16,metadata,guard) or { panic(err) }
			dispatch_algebra_scalar(probe,table,metadata); dispatch_algebra_constructors(probe,table,metadata,unsafe { nil },false,guard)
			// Invalid identities reject before a protected source is ever read.
			for bad in [u64(0),guard,metadata + 8,swift_integer_metadata(),other_metadata]! {
				for i in 0..3 { if _ := swift_witness_table_checked(record + u64(i * 16),bad,0) { assert false } }
				if _ := swift_dispatch_sequence_checked(guard,bad,guard,guard,table,guard) { assert false }
			}
			for bad in [u64(0),guard,table + 8]! { if _ := swift_dispatch_sequence_checked(guard,metadata,guard,guard,bad,guard) { assert false } }
			if _ := swift_dispatch_sequence_checked(guard,metadata,guard,guard,table,guard) { assert false }
			if _ := swift_dispatch_array_fold_checked(guard,metadata,guard) { assert false }
			mut result := [u64(0xcafe),0xa5,0xbeef]!
			for bad in [u64(0),guard,~u64(0) - 7]! { if _ := swift_dispatch_array_fold_checked(bad,metadata,u64(unsafe { &result[1] })) { assert false } }
			foreign := swift_array_allocate(1,swift_integer_metadata()); unsafe { *(&u64(foreign.bytes)) = 0 }
			if _ := swift_dispatch_array_fold_checked(foreign.owner,metadata,u64(unsafe { &result[1] })) { assert false }
			swift_bridge_release(foreign.owner)
			foreign_nominal := swift_array_allocate(1,other_metadata)
			foreign_array := swift_array_access(0,other_metadata).metadata
			foreign_sequence := swift_array_sequence_table_checked(foreign_array) or { panic(err) }
			if _ := swift_dispatch_array_fold_checked(foreign_nominal.owner,metadata,u64(unsafe { &result[1] })) { assert false }
			if _ := swift_dispatch_array_fold_checked(guard,guard,u64(unsafe { &result[1] })) { assert false }
			canonical_array := swift_array_access(0,metadata).metadata
			canonical_sequence := swift_array_sequence_table_checked(canonical_array) or { panic(err) }
			other_table := swift_dispatch_algebra_table_checked(other_metadata) or { panic(err) }
			for identity in [[foreign_array,canonical_sequence,table]!,[canonical_array,foreign_sequence,table]!,[canonical_array,canonical_sequence,other_table]!]! {
				if _ := swift_dispatch_sequence_checked(guard,metadata,identity[0],identity[1],identity[2],u64(unsafe { &result[1] })) { assert false }
			}
			mut source := foreign_nominal.owner
			if _ := swift_dispatch_sequence_checked(u64(unsafe { &source }),metadata,canonical_array,canonical_sequence,table,u64(unsafe { &result[1] })) { assert false }
			assert read64(foreign_nominal.owner + 8) == 3
			swift_bridge_release(foreign_nominal.owner)
			owned := swift_array_allocate(1,metadata); unsafe { *(&u64(owned.bytes)) = 3; *(&u64(owned.owner + 16)) = 2 }
			if _ := swift_dispatch_array_fold_checked(owned.owner,metadata,u64(unsafe { &result[1] })) { assert false }
			assert result == [u64(0xcafe),0xa5,0xbeef]! && read64(owned.owner + 8) == 3
			unsafe { *(&u64(owned.owner + 16)) = 1 }; swift_bridge_release(owned.owner)
			assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0
		}
		objc_stop(); assert ios_runtime.swift_dispatch_flags_arena == 0
		$if macos { assert C.mprotect(voidptr(base),page * 2,C.PROT_READ) == -1 }
		$else { mut residency := [u8(0),0]!; assert C.mincore(voidptr(base),page * 2,unsafe { &residency[0] }) == -1 }
		for metadata in [data + 16,data + 1280]! { if _ := swift_dispatch_algebra_table_checked(metadata) { assert false } }
		if _ := swift_dispatch_flags_arena_checked() { assert false }
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(guard),page) == 0
	println('IOS-DISPATCH-ALGEBRA: distinct Flags and Attributes SetAlgebra/Equatable/array-literal tables, canonical associated Self metadata, scalar/optional ABI, owned Array OR/one-release constructors, protected foreign and cross-nominal rejection, eight-worker identity and two quiescent unmapped lifetimes')
}
