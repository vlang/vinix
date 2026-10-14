// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.mincore(voidptr,usize,&u8) i32
type BoolMetadataAccess = fn (u64) SwiftAssociatedMetadata
type BoolMetadataCopy = fn (u64,u64,u64) u64
type BoolMetadataDestroy = fn (u64,u64)
type BoolMetadataGet = fn (u64,u32,u64) u32
type BoolMetadataStore = fn (u64,u32,u32,u64)
type BoolMetadataGuard = fn (u64,u64,u64,u64,u64,&u64)
struct BoolMetadataApi {
	native bool
	metadata u64
	descriptor u64
	accessor u64
	witness u64
	name string
}
fn bool_metadata_relative(p u64) u64 {
	delta := i32(read32(p));return if delta == 0 { u64(0) } else { u64(i64(p) + i64(delta)) }
}
fn bool_metadata_function(api BoolMetadataApi,slot int) u64 {
	value := read64(api.witness + u64(slot * 8))
	return if api.native { value & 0x0000ffffffffffff } else { value }
}
fn bool_metadata_guard_emit(code u64) {
	// x0-x3 arguments, x4 function, x5 response/context output. Preserve the
	// Swift callee-saved x20/x21 around an ordinary indirect call.
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0x910003fd,0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20),u32(0xd2800000 | (0x5121 << 5) | 21),
		0xaa0403f0,0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
}
fn bool_metadata_guarded(probe u64,a u64,b u64,c u64,d u64,function u64) [4]u64 {
	mut output := [4]u64{}
	call := unsafe { BoolMetadataGuard(voidptr(probe)) };call(a,b,c,d,function,unsafe { &output[0] })
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output
}
fn bool_metadata_layout(api BoolMetadataApi,probe u64) {
	assert read64(api.metadata) == 0x200 && read64(api.metadata + 8) == api.descriptor && read64(api.metadata + 16) == 0
	assert read32(api.descriptor) == if api.native { u32(0x100051) } else { u32(0x51) } && read32(api.descriptor + 20) == 1 && read32(api.descriptor + 24) == 2
	assert unsafe { (&char(bool_metadata_relative(api.descriptor + 8))).vstring() } == api.name
	parent := bool_metadata_relative(api.descriptor + 4)
	assert read32(parent) == 0 && unsafe { (&char(bool_metadata_relative(parent + 8))).vstring() } == 'ObjectiveC'
	assert bool_metadata_relative(api.descriptor + 12) == api.accessor
	assert read64(api.witness + 64) == 1 && read64(api.witness + 72) == 1 && read32(api.witness + 80) == 0 && read32(api.witness + 84) == 254
	for slot in 0 .. 8 { assert bool_metadata_function(api,slot) != 0 }
	for request in [u64(0),0x3f,0xff,0x100,0x1ff,0xffffffffffffffff]! {
		access := unsafe { BoolMetadataAccess(voidptr(api.accessor)) };response := access(request)
		assert response.metadata == api.metadata && response.state == 0
		output := bool_metadata_guarded(probe,request,0,0,0,api.accessor)
		assert output[0] == api.metadata && output[1] == 0
	}
	if !api.native { assert bool_metadata_relative(api.descriptor + 16) == 0 }
}
fn bool_metadata_values(api BoolMetadataApi,probe u64) {
	page := u64(C.getpagesize())
	source := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	destination := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert source != u64(-1) && destination != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(source) },usize(page * 2)) == 0;assert C.munmap(unsafe { voidptr(destination) },usize(page * 2)) == 0 }
	assert C.mprotect(unsafe { voidptr(source + page) },usize(page),C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(destination + page) },usize(page),C.PROT_NONE) == 0
	src := source + page - 1;dst := destination + page - 1
	for value in 0 .. 256 {
		assert C.mprotect(unsafe { voidptr(source) },usize(page),C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { *(&u8(src)) = u8(value);*(&u8(src - 1)) = 0x67 }
		assert C.mprotect(unsafe { voidptr(source) },usize(page),C.PROT_READ) == 0
		for slot in [0,2,3,4,5]! {
			unsafe { *(&u8(dst)) = 0xa5;*(&u8(dst - 1)) = 0x5a }
			output := bool_metadata_guarded(probe,dst,src,api.metadata,0,bool_metadata_function(api,slot))
			assert output[0] == dst && unsafe { *(&u8(dst)) } == u8(value) && unsafe { *(&u8(dst - 1)) } == 0x5a
			copy_value := unsafe { BoolMetadataCopy(voidptr(bool_metadata_function(api,slot))) };assert copy_value(dst,dst,api.metadata) == dst
			assert unsafe { *(&u8(src)) } == u8(value) && unsafe { *(&u8(src - 1)) } == 0x67
		}
	}
	destroy := unsafe { BoolMetadataDestroy(voidptr(bool_metadata_function(api,1))) }
	destroy(source + page,api.metadata);bool_metadata_guarded(probe,source + page,api.metadata,0,0,bool_metadata_function(api,1))
}

fn bool_metadata_enums(api BoolMetadataApi,probe u64) {
	for pair in [[u32(0),0]!,[u32(1),0]!,[u32(254),0]!,[u32(255),1]!,[u32(65278),1]!,[u32(65279),2]!,
		[u32(0x00fffefe),2]!,[u32(0x00fffeff),4]!,[u32(0xfffffffe),4]!,[u32(0xffffffff),1]!]! {
		cases := pair[0];width := pair[1];length := u64(width + 1);page := u64(C.getpagesize())
		base := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0));assert base != u64(-1)
		assert C.mprotect(unsafe { voidptr(base + page) },usize(page),C.PROT_NONE) == 0
		value := base + page - length
		get_tag := unsafe { BoolMetadataGet(voidptr(bool_metadata_function(api,6))) }
		store_tag := unsafe { BoolMetadataStore(voidptr(bool_metadata_function(api,7))) }
		// Every payload bit pattern, including the 254 extra inhabitants. With
		// an external tag, exercise UInt32 truncation as well as zero tag fallback.
		for payload in 0 .. 256 {
			for external in [u32(0),1,254,255,256,65535,65536,0x00ffffff,0xffffffff]! {
				unsafe { *(&u8(value)) = u8(payload) }
				mut encoded := u32(0)
				for i in u32(0) .. width {
					part := u8(external >> (i * 8));unsafe { *(&u8(value + 1 + i)) = part };encoded |= u32(part) << (i * 8)
				}
				expected := if cases == 0 { u32(0) } else if encoded != 0 { (encoded << 8 | u32(payload)) - u32(1) } else if payload < 2 { u32(0) } else { u32(payload - 1) }
				assert get_tag(value,cases,api.metadata) == expected
				output := bool_metadata_guarded(probe,value,cases,api.metadata,0,bool_metadata_function(api,6));assert u32(output[0]) == expected
			}
		}
		for tag in [u32(0),1,2,253,254,255,256,257,65278,65279,65535,65536,0x00fffefe,0x00fffeff,0xfffffffe,0xffffffff]! {
			for original in [u8(0),1,0x5a,0xff]! {
				C.memset(unsafe { voidptr(value - 1) },0x67,usize(length + 1));unsafe { *(&u8(value)) = original }
				bool_metadata_guarded(probe,value,tag,cases,api.metadata,bool_metadata_function(api,7))
				assert unsafe { *(&u8(value - 1)) } == 0x67
				assert unsafe { *(&u8(value)) } == if tag == 0 { original } else if tag <= 254 { u8(tag + 1) } else { u8(tag - 255) }
				encoded := if tag <= 254 { u32(0) } else { ((tag - 255) >> 8) + 1 }
				for i in u32(0) .. width { assert unsafe { *(&u8(value + 1 + i)) } == u8(encoded >> (i * 8)) }
				mut before := [5]u8{};for i in u64(0) .. length { before[i] = unsafe { *(&u8(value + i)) } }
				store_tag(value,tag,cases,api.metadata)
				for i in u64(0) .. length { assert before[i] == unsafe { *(&u8(value + i)) } }
				if tag <= cases && cases != 0 && !(cases == 0xffffffff && tag > 65534) && tag != 0 { assert get_tag(value,cases,api.metadata) == tag }
			}
		}
		if cases == 0 { assert get_tag(base + page,0,api.metadata) == 0;store_tag(base + page,0,0,api.metadata) }
		assert C.munmap(unsafe { voidptr(base) },usize(page * 2)) == 0
	}
}
fn bool_metadata_worker(api BoolMetadataApi) {
	for _ in 0 .. 64 {
		assert runtime_symbol("/usr/lib/swift/libswiftObjectiveC.dylib","_$s10ObjectiveC8ObjCBoolVN") or { panic(err) } == api.metadata
		assert runtime_symbol("/usr/lib/swift/libswiftObjectiveC.dylib","_$s10ObjectiveC8ObjCBoolVMn") or { panic(err) } == api.descriptor
		assert runtime_symbol("/usr/lib/swift/libswiftObjectiveC.dylib","_$s10ObjectiveC8ObjCBoolVMa") or { panic(err) } == api.accessor
	}
}
fn bool_metadata_integration(api BoolMetadataApi) {
	page := usize(C.getpagesize());record := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert record != u64(-1);defer { assert C.munmap(unsafe { voidptr(record) },page) == 0 }
	unsafe { *(&u8(record)) = 2;*(&u8(record + 1)) = 15;*(&u8(record + 5)) = 0;*(&u64(record + 16)) = api.descriptor }
	assert swift_mangled_lookup_checked(record,5,0,0) or { panic(err) } == api.metadata
	array_type := swift_array_access(0,api.metadata);assert read64(array_type.metadata + 16) == api.metadata
	buffer := swift_array_allocate(257,api.metadata);storage := ios_runtime.swift_arrays[buffer.owner] or { panic("missing boolean storage") }
	assert storage.element == api.metadata && storage.stride == 1 && storage.destroy == 0 && buffer.bytes == buffer.owner + storage.tail
	for i in u64(0) .. 257 { unsafe { *(&u8(buffer.bytes + i)) = u8(i) } }
	swift_array_destroy_elements(buffer.bytes,257,api.metadata)
	for i in u64(0) .. 257 { assert unsafe { *(&u8(buffer.bytes + i)) } == u8(i) }
	swift_bridge_release(buffer.owner)
}
fn bool_metadata_reject() {
	for symbol in ["_$s10ObjectiveC8ObjCBoolVN","_$s10ObjectiveC8ObjCBoolVMn","_$s10ObjectiveC8ObjCBoolVMa"]! {
		assert runtime_symbol("/usr/lib/swift/libswiftObjectiveC.dylib",symbol) == none
	}
	if _ := swift_objc_bool_arena_checked() { assert false }
}
fn test_swift_objc_bool_nominal_metadata_and_witnesses() {
	page := usize(C.getpagesize());probe := C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0);assert probe != unsafe { voidptr(-1) }
	defer { assert C.munmap(probe,page) == 0 }
	bool_metadata_guard_emit(u64(probe));C.__builtin___clear_cache(probe,unsafe { voidptr(u64(probe) + 60) });assert C.mprotect(probe,page,C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		library := C.dlopen(c"/usr/lib/swift/libswiftObjectiveC.dylib",C.RTLD_NOW);assert library != unsafe { nil }
		metadata := u64(C.dlsym(library,c"$s10ObjectiveC8ObjCBoolVN"));assert metadata != 0
		api := BoolMetadataApi{native:true,metadata:metadata,descriptor:u64(C.dlsym(library,c"$s10ObjectiveC8ObjCBoolVMn")),accessor:u64(C.dlsym(library,c"$s10ObjectiveC8ObjCBoolVMa")),witness:read64(metadata - 8) & 0x0000ffffffffffff,name:"ObjCBool"}
		bool_metadata_layout(api,u64(probe));bool_metadata_values(api,u64(probe));bool_metadata_enums(api,u64(probe))
		println("IOS-OBJC-BOOL-METADATA-NATIVE: complete ObjectiveC.ObjCBool metadata, one-byte POD witnesses with254 extra inhabitants, protected copy/take spans, all256 payloads, enum width transitions and UInt32 count/tag wrapping, preserved x20/x21")
	}
	bool_metadata_reject()
	for _ in 0 .. 2 {
		objc_start();library := "/usr/lib/swift/libswiftObjectiveC.dylib"
		metadata := runtime_symbol(library,"_$s10ObjectiveC8ObjCBoolVN") or { panic(err) }
		api := BoolMetadataApi{metadata:metadata,descriptor:runtime_symbol(library,"_$s10ObjectiveC8ObjCBoolVMn") or { panic(err) },accessor:runtime_symbol(library,"_$s10ObjectiveC8ObjCBoolVMa") or { panic(err) },witness:read64(metadata - 8),name:"ObjCBool"}
		bool_metadata_layout(api,u64(probe));bool_metadata_values(api,u64(probe));bool_metadata_enums(api,u64(probe));bool_metadata_integration(api)
		assert api.metadata != swift_integer_metadata() && api.witness != read64(swift_integer_metadata() - 8)
		for symbol in ["_$s10ObjectiveC8ObjCBoolVN","_$s10ObjectiveC8ObjCBoolVMn","_$s10ObjectiveC8ObjCBoolVMa"]! {
			assert runtime_symbol(library,symbol[1..]) == none
			for foreign in ["/usr/lib/swift/libswiftCore.dylib","/usr/lib/swift/libswiftFoundation.dylib","/usr/lib/libSystem.B.dylib"]! { assert runtime_symbol(foreign,symbol) == none }
		}
		for unsupported in ["_$s10ObjectiveC8ObjCBoolVSQAAMc","_$s10ObjectiveC8ObjCBoolVwst","_$sSo8NSObjectCSH10ObjectiveCMc"]! { assert runtime_symbol(library,unsupported) == none }
		mut workers := []thread{cap:8};for _ in 0 .. 8 { workers << spawn bool_metadata_worker(api) };workers.wait();unsafe { workers.free() }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_objc_bool_arena;objc_stop();assert ios_runtime.swift_objc_bool_arena == 0 && ios_runtime.swift_objc_bool_retired
		bool_metadata_reject()
		for offset in [u64(0),u64(page)]! {
			$if macos { assert C.mprotect(unsafe { voidptr(arena + offset) },page,C.PROT_READ) == -1 } $else { mut state := u8(0);assert C.mincore(unsafe { voidptr(arena + offset) },page,&state) == -1 }
		}
	}
	println("IOS-OBJC-BOOL-METADATA: canonical sealed nominal metadata/accessor and exact254-inhabitant byte witnesses, scoped exports, protected values/tag widths and UInt32 wrap, symbolic descriptor lookup, typed Array/POD destruction, eight readers and two drained/unmapped lifetimes")
}
