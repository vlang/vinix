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
type RawEqualityProbeCall = fn (u64,u64,u64,u64,u64,u64,&u64)
type RawEqualitySign = fn (u64,u64) u64
type RawEqualityStrip = fn (u64) u64
struct RawEqualityApi {
	native bool
	entry u64
	protocol u64
	string_metadata u64
	probe u64
}
struct RawEqualityScenario {
	api RawEqualityApi
	length u64
	left_source u64
	right_source u64
	left_payload u64
	right_payload u64
	owner u64
	string_value bool
	reenter bool
	word u64
mut:
	metadata u64
	raw_metadata u64
	raw_table u64
	equal_table u64
	left_temp u64
	right_temp u64
	phase int
	getters int
	comparisons int
	destructions int
}
fn raw_equality_refs(s &RawEqualityScenario) i64 {
	if s.owner == 0 { return 0 }
	$if macos { if s.api.native { return C.CFGetRetainCount(unsafe { voidptr(s.owner) }) } }
	return obj_header(s.owner).refs
}
fn raw_equality_retain(s &RawEqualityScenario) {
	if s.owner == 0 { return }
	$if macos { if s.api.native { C.CFRetain(unsafe { voidptr(s.owner) });return } }
	objc_retain(s.owner)
}
fn raw_equality_release(s &RawEqualityScenario) {
	if s.owner == 0 { return }
	$if macos { if s.api.native { C.CFRelease(unsafe { voidptr(s.owner) });return } }
	objc_release(s.owner)
}
fn raw_equality_lookup_worker() {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF') != none
}
fn raw_equality_reenter(s &RawEqualityScenario) {
	if s.reenter && !s.api.native { worker := spawn raw_equality_lookup_worker();worker.wait() }
}
fn raw_equality_getter(metadata u64,table u64,output u64,receiver u64) {
	mut s := unsafe { &RawEqualityScenario(read64(table + 32)) }
	assert metadata == s.metadata && table == s.raw_table && s.phase < 2 && output % 16 == 0
	assert receiver == if s.phase == 0 { s.left_source } else { s.right_source }
	if s.length != 0 { assert read64(receiver) == if s.phase == 0 { u64(0x1234) } else { u64(0x5678) } }
	assert raw_equality_refs(s) == if s.owner == 0 { i64(0) } else { i64(s.phase + 1) }
	if s.phase == 0 { s.left_temp = output } else { s.right_temp = output }
	raw_equality_retain(s)
	if s.length != 0 { C.memcpy(unsafe { voidptr(output) },unsafe { voidptr(if s.phase == 0 { s.left_payload } else { s.right_payload }) },usize(s.length)) }
	s.phase++;s.getters++;raw_equality_reenter(s)
}
fn raw_equality_compare(left u64,right u64,metadata u64,table u64,context u64) u64 {
	mut s := unsafe { &RawEqualityScenario(read64(table + 16)) }
	assert s.phase == 2 && metadata == s.raw_metadata && context == metadata && table == s.equal_table
	assert left == s.left_temp && right == s.right_temp
	if s.length != 0 {
		assert left != right && C.memcmp(unsafe { voidptr(left) },unsafe { voidptr(s.left_payload) },usize(s.length)) == 0
		assert C.memcmp(unsafe { voidptr(right) },unsafe { voidptr(s.right_payload) },usize(s.length)) == 0
	}
	assert raw_equality_refs(s) == if s.owner == 0 { i64(0) } else { i64(3) }
	s.phase = 3;s.comparisons++;raw_equality_reenter(s)
	// Deliberately return arbitrary high bits. Native masks only bit zero,
	// and witness semantics can differ from a bytewise comparison.
	return s.word
}
fn raw_equality_destroy(value u64,metadata u64) {
	mut s := unsafe { &RawEqualityScenario(read64(metadata + 8)) }
	assert metadata == s.raw_metadata && s.phase in [3,4]!
	assert value == if s.phase == 3 { s.right_temp } else { s.left_temp }
	if s.length != 0 { assert C.memcmp(unsafe { voidptr(value) },unsafe { voidptr(if s.phase == 3 { s.right_payload } else { s.left_payload }) },usize(s.length)) == 0 }
	assert raw_equality_refs(s) == if s.owner == 0 { i64(0) } else { i64(6 - s.phase) }
	raw_equality_release(s);s.phase++;s.destructions++;raw_equality_reenter(s)
}
fn raw_equality_probe_emit(code u64) {
	for i,op in [u32(0xa9be7bfd),0xa90153f3,0x910003fd,0xaa0603f3,0xaa0503f0,
		u32(0xd2800000 | (0x5020 << 5) | 20),0xd63f0200,0xf9000260,0xf9000674,
		0xa94153f3,0xa8c27bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
	// Native getter -> C callback with indirect result and Self context.
	write32(code + 64,0xaa0803e2);write32(code + 68,0xaa1403e3)
	write32(code + 72,0x58000090);write32(code + 76,0xd61f0200)
	unsafe { *(&u64(code + 88)) = u64(voidptr(raw_equality_getter)) }
	// Native static equality -> C callback, forwarding hidden x20 as x4.
	write32(code + 96,0xaa1403e4);write32(code + 100,0x58000070)
	write32(code + 104,0xd61f0200);write32(code + 108,0xd503201f)
	unsafe { *(&u64(code + 112)) = u64(voidptr(raw_equality_compare)) }
	write32(code + 128,0xdac10020);write32(code + 132,0xd65f03c0)
	write32(code + 144,0xdac10820);write32(code + 148,0xd65f03c0)
	write32(code + 160,0xdac147e0);write32(code + 164,0xd65f03c0)
}
fn raw_equality_case(api RawEqualityApi,length u64,word u64,reference bool,string_value bool,tagged bool,reenter bool) {
	page := u64(C.getpagesize());span := ((length + page - 1) / page + 2) * page
	left := u64(C.mmap(unsafe { nil },usize(span),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	right := u64(C.mmap(unsafe { nil },usize(span),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	sources := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert left != u64(-1) && right != u64(-1) && sources != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(left) },usize(span)) == 0;assert C.munmap(unsafe { voidptr(right) },usize(span)) == 0;assert C.munmap(unsafe { voidptr(sources) },usize(page * 2)) == 0 }
	left_payload := left + span - page - length;right_payload := right + span - page - length
	for i in u64(0) .. length { unsafe { *(&u8(left_payload + i)) = u8(i * 37 + 19);*(&u8(right_payload + i)) = u8(i * 37 + 20) } }
	mut owner := u64(0)
	if reference {
		$if macos { if api.native { owner = u64(C.CFStringCreateMutable(unsafe { nil },0)) } }
		if !api.native { owner = owned_string('') }
		if string_value {
			unsafe { *(&SwiftStringWords(left_payload)) = SwiftStringWords{second: owner | u64(0x4000000000000000)};*(&SwiftStringWords(right_payload)) = *(&SwiftStringWords(left_payload)) }
		} else { unsafe { *(&u64(left_payload)) = owner;*(&u64(right_payload)) = owner } }
	}
	unsafe { *(&u64(sources)) = 0x1234;*(&u64(sources + 8)) = 0x5678 }
	for base in [left,right]! {
		assert C.mprotect(unsafe { voidptr(base) },usize(span - page),C.PROT_READ) == 0
		assert C.mprotect(unsafe { voidptr(base + span - page) },usize(page),C.PROT_NONE) == 0
	}
	assert C.mprotect(unsafe { voidptr(sources) },usize(page),C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(sources + page) },usize(page),C.PROT_NONE) == 0
	mut s := RawEqualityScenario{api:api,length:length,left_source: if length == 0 { sources + page } else { sources },right_source: if length == 0 { sources + page + 8 } else { sources + 8 },left_payload:left_payload,right_payload:right_payload,owner:owner,string_value:string_value,reenter:reenter,word:word}
	mut record := [12]u64{};record_address := u64(unsafe { &record[0] })
	write32(record_address,17);write32(record_address + 4,28);record[2] = api.protocol;write32(record_address + 32,0x51)
	mut self_metadata := [u64(0x200),record_address + 32]!
	mut raw_metadata := [u64(0),0x200,u64(unsafe { &s })]!
	mut vwt := [u64(0),u64(unsafe { voidptr(raw_equality_destroy) }),0,0,0,0,0,0,length,if length == 0 { u64(1) } else { length },u64(0x10000)]!
	mut raw_table := [record_address,u64(0),0,api.probe + 64,u64(unsafe { &s })]!
	mut equal_table := [u64(0),api.probe + 96,u64(unsafe { &s })]!
	mut name := [u8(0xff),`S`,`S`,0,0,0,0,0]!
	s.metadata = u64(unsafe { &self_metadata[0] });s.raw_metadata = if string_value { api.string_metadata } else { u64(unsafe { &raw_metadata[1] }) }
	s.raw_table = u64(unsafe { &raw_table[0] });s.equal_table = u64(unsafe { &equal_table[0] })
	raw_metadata[0] = u64(unsafe { &vwt[0] });raw_table[1] = if tagged { u64(unsafe { &name[0] }) | 1 } else { s.raw_metadata }
	$if macos { if api.native {
		sign_code := unsafe { RawEqualitySign(voidptr(api.probe + 128)) };sign_data := unsafe { RawEqualitySign(voidptr(api.probe + 144)) }
		raw_table[1] = sign_data(raw_table[1],(s.raw_table + 8) | u64(0x617) << 48)
		raw_table[3] = sign_code(raw_table[3],(s.raw_table + 24) | u64(0x3d88) << 48)
		equal_table[1] = sign_code(equal_table[1],(s.equal_table + 8) | u64(0x97eb) << 48)
		vwt[1] = sign_code(vwt[1],u64(unsafe { &vwt[1] }) | u64(0x4f8) << 48)
		raw_metadata[0] = sign_data(raw_metadata[0],u64(unsafe { &raw_metadata[0] }) | u64(0x2e3f) << 48)
	} }
	call := unsafe { RawEqualityProbeCall(voidptr(api.probe)) }
	for _ in 0 .. 2 {
		s.phase = 0;mut returned := [u64(0),0]!
		call(s.left_source,s.right_source,s.metadata,s.raw_table,s.equal_table,api.entry,unsafe { &returned[0] })
		assert returned[0] == word & 1 && returned[1] == 0x5020
		assert s.phase == if string_value { 3 } else { 5 }
		assert raw_equality_refs(&s) == if owner == 0 { i64(0) } else { i64(1) }
		if length != 0 { assert read64(sources) == 0x1234 && read64(sources + 8) == 0x5678 }
	}
	assert s.getters == 4 && s.comparisons == 2 && s.destructions == if string_value { 0 } else { 4 }
	if tagged {
		mut value := raw_table[1]
		$if macos { if api.native { strip := unsafe { RawEqualityStrip(voidptr(api.probe + 160)) };value = strip(value) } }
		assert value == api.string_metadata
	}
	raw_equality_release(&s)
}
fn raw_equality_run(api RawEqualityApi) {
	for length in [u64(0),1,3,8,16,17,33,257,8193,65536]! {
		for word in [u64(0xfffffffe),0xffffffff]! { raw_equality_case(api,length,word,false,false,false,length == 17) }
	}
	raw_equality_case(api,8,3,true,false,false,true)
	raw_equality_case(api,16,2,true,true,false,true)
	raw_equality_case(api,16,3,true,true,true,true)
	mut workers := []thread{cap:8}
	for _ in 0 .. 8 { workers << spawn raw_equality_case(api,33,3,false,false,false,false) }
	workers.wait();unsafe { workers.free() }
}
fn raw_equality_invalid() {
	mut metadata := [u64(0),0x200,0]!
	mut vwt := [u64(0),1,0,0,0,0,0,0,8,8,7]!
	mut raw_table := [u64(0),u64(unsafe { &metadata[1] }),0,1]!
	mut equal_table := [u64(0),1]!
	meta := u64(unsafe { &metadata[1] });table := u64(unsafe { &raw_table[0] });eq := u64(unsafe { &equal_table[0] });metadata[0] = u64(unsafe { &vwt[0] })
	for args in [[u64(0),table,eq]!,[meta,u64(0),eq]!,[meta,table,u64(0)]!,[meta,table + 1,eq]!]! { if _ := swift_raw_equality_layout(args[0],args[1],args[2]) { assert false } }
	for size in [u64(65537),0x7fffffffffffffff,0xffffffffffffffff]! { vwt[8] = size;if _ := swift_raw_equality_layout(meta,table,eq) { assert false } }
	vwt[8] = 8
	for flags in [u64(2),31,0x00400007]! { vwt[10] = flags;if _ := swift_raw_equality_layout(meta,table,eq) { assert false } }
	vwt[10] = 7;vwt[9] = 7;if _ := swift_raw_equality_layout(meta,table,eq) { assert false };vwt[9] = 8
	for value in [u64(0),1,2]! { raw_table[1] = value;if _ := swift_raw_equality_layout(meta,table,eq) { assert false } };raw_table[1] = meta
	raw_table[3] = 0;if _ := swift_raw_equality_layout(meta,table,eq) { assert false };raw_table[3] = 1
	equal_table[1] = 0;if _ := swift_raw_equality_layout(meta,table,eq) { assert false };equal_table[1] = 1
	vwt[1] = 0;if _ := swift_raw_equality_layout(meta,table,eq) { assert false }
	if _ := swift_raw_equal_checked(0,1,meta,table,eq) { assert false }
}
fn test_swift_raw_representable_equality() {
	page := usize(C.getpagesize());code := C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	assert code != unsafe { voidptr(-1) };defer { assert C.munmap(code,page) == 0 }
	raw_equality_probe_emit(u64(code));C.__builtin___clear_cache(code,unsafe { voidptr(u64(code) + 168) });assert C.mprotect(code,page,C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW)
		api := RawEqualityApi{native:true,entry:u64(C.dlsym(core,c'$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF')),protocol:u64(C.dlsym(core,c'$sSYMp')),string_metadata:u64(C.dlsym(core,c'$sSSN')),probe:u64(code)}
		assert api.entry != 0 && api.protocol != 0 && api.string_metadata != 0;raw_equality_run(api)
		println('IOS-RAW-EQUALITY-NATIVE: two getter x8 outputs and borrowed Self contexts, static equality metadata x20, witness result low bit, right/left owned destruction, zero/odd/large protected payloads, references/String/tagged associated type and eight workers')
	}
	if _ := swift_raw_equal_checked(1,1,1,0,0) { assert false }
	for _ in 0 .. 2 {
		objc_start();baseline := ios_runtime.live
		api := RawEqualityApi{entry:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF') or { panic(err) },protocol:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSYMp') or { panic(err) },string_metadata:swift_string_metadata(),probe:u64(code)}
		raw_equality_run(api);raw_equality_invalid()
		for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library,'_$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','$ss2eeoiySbx_xtSYRzSQ8RawValueRpzlF') == none
		assert ios_runtime.live == baseline && ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_strings.len == 0
		arena := ios_runtime.swift_hash_code;objc_stop();assert ios_runtime.swift_hash_code == 0
		$if macos { assert C.mprotect(unsafe { voidptr(arena) },page,C.PROT_READ) == -1 } $else { mut state := u8(0);assert C.mincore(unsafe { voidptr(arena) },page,&state) == -1 }
	}
	println('IOS-RAW-EQUALITY: checked caller-owned ABI records, two aligned stack RawValues, witness semantics and Bool masking, balanced reverse destruction, protected borrowed Self/payloads, unlocked reentrant callbacks, eight workers, invalid layouts rejected before calls and two drained existing arenas')
}
