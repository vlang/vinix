// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.CFStringCreateMutable(voidptr,i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr,usize,&u8) i32
type AnyProbe = fn (u64,u64,u64,u64,u64,&u64)
type AnySign = fn (u64,u64) u64
type AnyAllocateBox = fn (u64) SwiftArrayAllocation
type AnyRelease = fn (u64)
type AnyTagGet = fn (u64,u32,u64) u32
type AnyTagStore = fn (u64,u32,u32,u64)
struct AnyApi { native bool full u64 metadata u64 witness u64 integer u64 string_type u64 probe u64 }
fn any_api_function(api AnyApi,slot int) u64 {
	entry := read64(api.witness + u64(slot * 8));return if api.native { entry & 0x0000ffffffffffff } else { entry }
}
fn any_probe_emit(code u64) {
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0x910003fd,0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20),u32(0xd2800000 | (0x5121 << 5) | 21),
		0xaa0403f0,0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
	write32(code + 64,0xdac10020);write32(code + 68,0xd65f03c0)
	write32(code + 80,0xdac10820);write32(code + 84,0xd65f03c0)
}
fn any_call(api AnyApi,slot int,a u64,b u64,c u64,d u64) u64 {
	mut result := [4]u64{};call := unsafe { AnyProbe(voidptr(api.probe)) }
	call(a,b,c,d,any_api_function(api,slot),unsafe { &result[0] });assert result[2] == 0x5020 && result[3] == 0x5121;return result[0]
}
fn any_keep(api AnyApi,owner u64) {
	$if macos { if api.native { C.CFRetain(unsafe { voidptr(owner) });return } };objc_retain(owner)
}
fn any_drop(api AnyApi,owner u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) });return } };objc_release(owner)
}
fn any_refs(api AnyApi,owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } };return obj_header(owner).refs
}
fn any_owner(api AnyApi) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateMutable(unsafe { nil },0)) } };return owned_string('')
}
fn any_release_box(api AnyApi,owner u64) {
	$if macos { if api.native { core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);release_box := unsafe { AnyRelease(C.dlsym(core,c'swift_release')) };release_box(owner);return } };swift_release(owner)
}
fn any_box(api AnyApi,owner u64) SwiftArrayAllocation {
	mut box := SwiftArrayAllocation{}
	$if macos { if api.native { core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);allocate := unsafe { AnyAllocateBox(C.dlsym(core,c'swift_allocBox')) };box = allocate(api.metadata) } }
	if !api.native { owner_box := swift_any_box_allocate();box = SwiftArrayAllocation{owner:owner_box,bytes:owner_box + 16} }
	assert box.bytes == box.owner + 16 && read64(box.owner + 8) == 3
	C.memset(unsafe { voidptr(box.bytes) },0x5a,32)
	if owner == 0 { unsafe { *(&u64(box.bytes)) = 0x1234;*(&u64(box.bytes + 24)) = api.integer } }
	else { any_keep(api,owner);unsafe { *(&u64(box.bytes)) = 0;*(&u64(box.bytes + 8)) = owner | u64(0x4000000000000000);*(&u64(box.bytes + 24)) = api.string_type } }
	return box
}
fn any_owned_cases(api AnyApi) {
	owner := any_owner(api);assert any_refs(api,owner) == 1
	padding := u64(0x5a5a5a5a5a5a5a5a)
	for slot in [2,4,3,5]! {
		mut source := [u64(0),owner | u64(0x4000000000000000),0x5a5a5a5a5a5a5a5a,api.string_type]!
		mut destination := [padding,padding,padding,api.integer]!
		any_keep(api,owner)
		src := u64(unsafe { &source[0] });dst := u64(unsafe { &destination[0] })
		assert any_call(api,slot,dst,src,api.metadata,0) == dst
		assert destination[0] == 0 && destination[1] == source[1] && destination[2] == padding && destination[3] == api.string_type
		assert any_refs(api,owner) == if slot in [2,3]! { i64(3) } else { i64(2) }
		any_call(api,1,dst,api.metadata,0,0)
		if slot in [2,3]! { any_call(api,1,src,api.metadata,0,0) }
		assert any_refs(api,owner) == 1
	}
	for slot in [0,2,4,3,5]! {
		new_box := any_box(api,owner)
		mut source := [new_box.owner,u64(0x1122),0x3344,api.metadata]!
		mut destination := [padding,padding,padding,api.metadata]!
		mut old := u64(0)
		if slot in [3,5]! { old_box := any_box(api,0);old = old_box.owner;destination[0] = old }
		src := u64(unsafe { &source[0] });dst := u64(unsafe { &destination[0] })
		returned := any_call(api,slot,dst,src,api.metadata,0)
		assert returned == if slot == 0 { new_box.bytes } else { dst }
		assert destination[0] == new_box.owner && any_refs(api,owner) == 2
		if slot == 4 { assert destination[1] == source[1] && destination[2] == source[2] }
		else { assert destination[1] == padding && destination[2] == padding }
		assert read64(new_box.owner + 8) == if slot in [0,2,3]! { u64(0x200000003) } else { u64(3) }
		if !api.native && old != 0 { assert old !in ios_runtime.swift_heap }
		if slot == 0 { any_release_box(api,destination[0]);any_release_box(api,source[0]) }
		else { any_call(api,1,dst,api.metadata,0,0);if slot in [2,3]! { any_call(api,1,src,api.metadata,0,0) } }
		assert any_refs(api,owner) == 1
	}
	any_drop(api,owner)
}
fn any_guarded_spans(api AnyApi) {
	page := u64(C.getpagesize())
	source := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	destination := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert source != u64(-1) && destination != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(source) },usize(page * 2)) == 0;assert C.munmap(unsafe { voidptr(destination) },usize(page * 2)) == 0 }
	for base in [source,destination]! { assert C.mprotect(unsafe { voidptr(base + page) },usize(page),C.PROT_NONE) == 0 }
	src := source + page - 32;dst := destination + page - 32
	C.memset(unsafe { voidptr(src) },0x67,32);unsafe { *(&u64(src + 24)) = api.integer }
	assert C.mprotect(unsafe { voidptr(source) },usize(page),C.PROT_READ) == 0
	for slot in [2,4,3,5]! {
		C.memset(unsafe { voidptr(dst) },0x5a,32);unsafe { *(&u64(dst + 24)) = api.integer }
		assert any_call(api,slot,dst,src,api.metadata,0) == dst && read64(dst) == read64(src) && read64(dst + 24) == api.integer
		if slot == 4 { assert C.memcmp(unsafe { voidptr(dst) },unsafe { voidptr(src) },32) == 0 }
		else { assert read64(dst + 8) == 0x5a5a5a5a5a5a5a5a && read64(dst + 16) == 0x5a5a5a5a5a5a5a5a }
		any_call(api,1,dst,api.metadata,0,0)
	}
	guard := source + page
	assert any_call(api,3,guard,guard,api.metadata,0) == guard && any_call(api,5,guard,guard,api.metadata,0) == guard
	assert C.mprotect(unsafe { voidptr(source) },usize(page),C.PROT_READ | C.PROT_WRITE) == 0
	box := any_box(api,0);buffer := source + page - 24;copied := destination + page - 24
	unsafe { *(&u64(buffer)) = box.owner };C.memset(unsafe { voidptr(copied) },0x5a,24)
	assert C.mprotect(unsafe { voidptr(source) },usize(page),C.PROT_READ) == 0
	assert any_call(api,0,copied,buffer,api.metadata,0) == box.bytes && read64(copied) == box.owner
	assert read64(copied + 8) == 0x5a5a5a5a5a5a5a5a && read64(copied + 16) == 0x5a5a5a5a5a5a5a5a
	any_release_box(api,box.owner);any_release_box(api,box.owner)
}
fn any_collection_boxes(api AnyApi) {
	array_type := swift_array_access(0,api.integer)
	table := swift_collection_table_checked(array_type.metadata) or { panic(err) }
	slice_type := read64(table + 48)
	for iterator in [false,true]! {
		metadata := slice_type + if iterator { u64(160) } else { u64(0) }
		array := swift_array_allocate(3,api.integer)
		for i in 0 .. 3 { unsafe { *(&u64(array.bytes + u64(i * 8))) = u64(i + 42) } }
		box := swift_collection_box_allocate(metadata)
		unsafe { *(&u64(box + 16)) = array.owner;*(&u64(box + 24)) = array.bytes;*(&u64(box + 32)) = 0;*(&u64(box + 40)) = 7 }
		if iterator { unsafe { *(&u64(box + 48)) = 0 } }
		mut source := [box,u64(0),0,metadata]!;mut destination := [u64(0),0,0,0]!
		src := u64(unsafe { &source[0] });dst := u64(unsafe { &destination[0] })
		assert any_call(api,2,dst,src,api.metadata,0) == dst && destination[0] == box && destination[3] == metadata
		assert read64(box + 8) == 0x200000003 && read64(array.owner + 8) == 3
		any_call(api,1,dst,api.metadata,0,0);assert read64(box + 8) == 3
		any_call(api,1,src,api.metadata,0,0);assert box !in ios_runtime.swift_heap && array.owner !in ios_runtime.swift_arrays
	}
}
struct AnyTrace {
	api AnyApi
mut:
	events [16]int
	count int
	type_a u64
	type_b u64
	size_a u64
	size_b u64
	destination u64
	expected_metadata u64
}
fn any_lookup_worker() { assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sypN') != none }
fn any_trace_event(destination u64,source u64,metadata u64,kind int) u64 {
	mut trace := unsafe { &AnyTrace(read64(metadata + 8)) }
	assert trace.count < 16 && read64(trace.destination + 24) == trace.expected_metadata
	trace.events[trace.count] = kind;trace.count++
	size := if metadata == trace.type_a { trace.size_a } else { assert metadata == trace.type_b;trace.size_b }
	if kind != 1 { C.memmove(unsafe { voidptr(destination) },unsafe { voidptr(source) },usize(size)) }
	if !trace.api.native { worker := spawn any_lookup_worker();worker.wait() }
	return destination
}
fn any_trace_destroy(value u64,metadata u64) { any_trace_event(value,value,metadata,1) }
fn any_trace_copy(destination u64,source u64,metadata u64) u64 { return any_trace_event(destination,source,metadata,2) }
fn any_trace_assign_copy(destination u64,source u64,metadata u64) u64 { return any_trace_event(destination,source,metadata,3) }
fn any_trace_take(destination u64,source u64,metadata u64) u64 {
	mut trace := unsafe { &AnyTrace(read64(metadata + 8)) }
	if destination != trace.destination { trace.expected_metadata = trace.type_a }
	result := any_trace_event(destination,source,metadata,4)
	if destination != trace.destination { trace.expected_metadata = trace.type_b }
	return result
}
fn any_trace_assign_take(destination u64,source u64,metadata u64) u64 { return any_trace_event(destination,source,metadata,5) }
fn any_trace_cases(api AnyApi) {
	for sizes in [[u64(0),0]!,[u64(1),3]!,[u64(8),16]!,[u64(24),24]!]! {
		mut trace := AnyTrace{api:api,size_a:sizes[0],size_b:sizes[1]}
		mut vwt_a := [11]u64{};mut vwt_b := [11]u64{}
		for slot,entry in [u64(0),u64(unsafe { voidptr(any_trace_destroy) }),u64(unsafe { voidptr(any_trace_copy) }),u64(unsafe { voidptr(any_trace_assign_copy) }),u64(unsafe { voidptr(any_trace_take) }),u64(unsafe { voidptr(any_trace_assign_take) })]! { vwt_a[slot] = entry;vwt_b[slot] = entry }
		vwt_a[8] = sizes[0];vwt_a[9] = if sizes[0] == 0 { u64(1) } else { sizes[0] }
		vwt_b[8] = sizes[1];vwt_b[9] = if sizes[1] == 0 { u64(1) } else { sizes[1] }
		mut meta_a := [u64(unsafe { &vwt_a[0] }),u64(0x200),u64(unsafe { &trace })]!
		mut meta_b := [u64(unsafe { &vwt_b[0] }),u64(0x200),u64(unsafe { &trace })]!
		trace.type_a = u64(unsafe { &meta_a[1] });trace.type_b = u64(unsafe { &meta_b[1] })
		$if macos { if api.native {
			sign_code := unsafe { AnySign(voidptr(api.probe + 64)) };sign_data := unsafe { AnySign(voidptr(api.probe + 80)) }
			for slot,discriminator in [u64(0),0x04f8,0xe3ba,0x8751,0x48d8,0xefda]! { if slot == 0 { continue };vwt_a[slot] = sign_code(vwt_a[slot],u64(unsafe { &vwt_a[slot] }) | (discriminator << 48));vwt_b[slot] = sign_code(vwt_b[slot],u64(unsafe { &vwt_b[slot] }) | (discriminator << 48)) }
			meta_a[0] = sign_data(meta_a[0],u64(unsafe { &meta_a[0] }) | (u64(0x2e3f) << 48));meta_b[0] = sign_data(meta_b[0],u64(unsafe { &meta_b[0] }) | (u64(0x2e3f) << 48))
		} }
		for slot in [2,4,3,5]! {
			for different in [false,true]! {
				mut destination := [u64(0x1234),0x5678,0x9abc,trace.type_a]!
				mut source := [u64(0x2234),0x6678,0xaabc,if different { trace.type_b } else { trace.type_a }]!
				dst := u64(unsafe { &destination[0] });src := u64(unsafe { &source[0] });trace.destination = dst;trace.count = 0
				trace.expected_metadata = if slot == 4 { trace.type_a } else { source[3] }
				assert any_call(api,slot,dst,src,api.metadata,0) == dst
				if slot == 4 { assert trace.count == 0 && destination == source }
				else if slot == 2 { assert trace.count == 1 && trace.events[0] == 2 }
				else if different { assert trace.count == 3 && trace.events[0] == 4 && trace.events[1] == if slot == 3 { 2 } else { 4 } && trace.events[2] == 1 }
				else { assert trace.count == 1 && trace.events[0] == slot }
				trace.expected_metadata = destination[3];any_call(api,1,dst,api.metadata,0,0)
				before := trace.count;assert any_call(api,3,dst,dst,api.metadata,0) == dst && any_call(api,5,dst,dst,api.metadata,0) == dst;assert trace.count == before
			}
		}
	}
}
fn any_enum_cases(api AnyApi) {
	for cases in [u32(0),1,0x7fffffff,0x80000000,0xffffffff]! {
		length := if cases & 0x80000000 != 0 { u64(33) } else { u64(32) };page := u64(C.getpagesize())
		base := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0));assert base != u64(-1)
		defer { assert C.munmap(unsafe { voidptr(base) },usize(page * 2)) == 0 }
		assert C.mprotect(unsafe { voidptr(base + page) },usize(page),C.PROT_NONE) == 0;value := base + page - length
		get := unsafe { AnyTagGet(voidptr(any_api_function(api,6))) };store := unsafe { AnyTagStore(voidptr(any_api_function(api,7))) }
		for tag in [u32(0),1,17,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]! {
			if tag > cases { continue };C.memset(unsafe { voidptr(value - 1) },0x5a,usize(length + 1));store(value,tag,cases,api.metadata)
			assert get(value,cases,api.metadata) == tag && unsafe { *(&u8(value - 1)) } == 0x5a
			for i in 0 .. 32 {
				expected := if tag == 0 { u8(0x5a) } else if tag & 0x80000000 != 0 { if i < 4 { u8((tag & 0x7fffffff) >> (i * 8)) } else { u8(0) } } else if i < 24 { u8(0x5a) } else { u8(u64(tag - 1) >> ((i - 24) * 8)) }
				assert unsafe { *(&u8(value + u64(i))) } == expected
			}
			if length == 33 { assert unsafe { *(&u8(value + 32)) } == if tag & 0x80000000 != 0 { u8(1) } else { u8(0) } }
		}
	}
}
fn any_invalid() {
	mut value := [u64(0),0,0,0]!
	mut vwt := [11]u64{};vwt[8] = 8;vwt[9] = 8;mut metadata := [u64(unsafe { &vwt[0] }),u64(0x200)]!
	p := u64(unsafe { &value[0] });m := u64(unsafe { &metadata[1] });mut output := [u64(0x5a),0x5a,0x5a,0x5a]!
	if _ := swift_any_layout(p) { assert false };value[3] = m
	for flags in [u64(2),15,0x400000]! { vwt[10] = flags;if _ := swift_any_layout(p) { assert false } };vwt[10] = 0
	vwt[8] = 25;vwt[9] = 25;if _ := swift_any_layout(p) { assert false };vwt[8] = 8;vwt[9] = 8
	if _ := swift_any_copy_checked(u64(unsafe { &output[0] }),p) { assert false };assert output == [u64(0x5a),0x5a,0x5a,0x5a]!
	vwt[10] = 0x20000;if _ := swift_any_layout(p) { assert false }
	assert swift_any_assign_checked(0,0,false) or { panic(err) } == 0
}
fn any_reader() { for _ in 0 .. 64 { full := runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sypN') or { panic(err) };assert read64(full + 8) == 0x303 && read64(full + 16) == 0x80000000 } }
fn test_swift_any_metadata_and_value_witnesses() {
	page := usize(C.getpagesize());probe := C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0);assert probe != unsafe { voidptr(-1) }
	defer { assert C.munmap(probe,page) == 0 };any_probe_emit(u64(probe));C.__builtin___clear_cache(probe,unsafe { voidptr(u64(probe) + 88) });assert C.mprotect(probe,page,C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);full := u64(C.dlsym(core,c'$sypN'))
		api := AnyApi{native:true,full:full,metadata:full + 8,witness:read64(full) & 0x0000ffffffffffff,integer:u64(C.dlsym(core,c'$sSiN')),string_type:u64(C.dlsym(core,c'$sSSN')),probe:u64(probe)}
		any_owned_cases(api);any_guarded_spans(api);any_trace_cases(api);any_enum_cases(api)
		println('IOS-ANY-NATIVE: full existential metadata/header and32-byte layout, inline String ownership, registered boxed Any payload/buffer sharing and exact take/copy refcounts, same/different type witness sequences, source transfer/self assignment, reentrant callback contexts, protected unaligned enum bytes through UINT32_MAX and x20/x21')
	}
	for _ in 0 .. 2 {
		objc_start();full := runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sypN') or { panic(err) }
		api := AnyApi{full:full,metadata:full + 8,witness:read64(full),integer:swift_integer_metadata(),string_type:swift_string_metadata(),probe:u64(probe)}
		assert read64(api.metadata) == 0x303 && read64(api.metadata + 8) == 0x80000000 && read64(api.witness + 64) == 32 && read64(api.witness + 72) == 32 && read64(api.witness + 80) == 0x7fffffff00030007
		any_owned_cases(api);any_guarded_spans(api);any_trace_cases(api);any_enum_cases(api);any_collection_boxes(api);any_invalid()
		mut workers := []thread{cap:8};for _ in 0 .. 8 { workers << spawn any_reader() };workers.wait();unsafe { workers.free() }
		for foreign in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(foreign,'_$sypN') == none };assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','$sypN') == none
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_error_arena;objc_stop();assert ios_runtime.swift_error_arena == 0
		for offset in [u64(0),u64(page)]! { $if macos { assert C.mprotect(unsafe { voidptr(arena + offset) },page,C.PROT_READ) == -1 } $else { mut state := u8(0);assert C.mincore(unsafe { voidptr(arena + offset) },page,&state) == -1 } }
	}
	println('IOS-ANY: canonical full metadata and complete VWT in existing error arena, checked inline witnesses and known registered box provenance, exact assignment publication/destruction order, balanced String/nested box ownership, native enum bytes, invalid layouts rejected before writes, unlocked reentry, eight readers and two drained heap/arena lifetimes')
}
