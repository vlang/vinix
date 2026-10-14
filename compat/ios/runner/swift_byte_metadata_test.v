// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.mincore(voidptr,usize,&u8) i32
type ByteMetadataAccess = fn (u64) SwiftAssociatedMetadata
type ByteMetadataCopy = fn (u64,u64,u64) u64
type ByteMetadataDestroy = fn (u64,u64)
type ByteMetadataGet = fn (u64,u32,u64) u32
type ByteMetadataStore = fn (u64,u32,u32,u64)
type ByteMetadataGuard = fn (u64,u64,u64,u64,u64,&u64)
struct ByteMetadataApi {
	native bool
	metadata u64
	descriptor u64
	accessor u64
	witness u64
	name string
}
fn byte_metadata_relative(p u64) u64 {
	delta := i32(read32(p));return if delta == 0 { u64(0) } else { u64(i64(p) + i64(delta)) }
}
fn byte_metadata_function(api ByteMetadataApi,slot int) u64 {
	value := read64(api.witness + u64(slot * 8))
	return if api.native { value & 0x0000ffffffffffff } else { value }
}
fn byte_metadata_guard_emit(code u64) {
	// x0-x3 arguments, x4 function, x5 response/context output. Preserve the
	// Swift callee-saved x20/x21 around an ordinary indirect call.
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0x910003fd,0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20),u32(0xd2800000 | (0x5121 << 5) | 21),
		0xaa0403f0,0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
}
fn byte_metadata_guarded(probe u64,a u64,b u64,c u64,d u64,function u64) [4]u64 {
	mut output := [4]u64{}
	call := unsafe { ByteMetadataGuard(voidptr(probe)) };call(a,b,c,d,function,unsafe { &output[0] })
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output
}
fn byte_metadata_layout(api ByteMetadataApi,probe u64) {
	assert read64(api.metadata) == 0x200 && read64(api.metadata + 8) == api.descriptor && read64(api.metadata + 16) == 0
	assert read32(api.descriptor) == 0x51 && read32(api.descriptor + 20) == 1 && read32(api.descriptor + 24) == 2
	assert unsafe { (&char(byte_metadata_relative(api.descriptor + 8))).vstring() } == api.name
	parent := byte_metadata_relative(api.descriptor + 4)
	assert read32(parent) == 0 && unsafe { (&char(byte_metadata_relative(parent + 8))).vstring() } == 'Swift'
	assert byte_metadata_relative(api.descriptor + 12) == api.accessor
	assert read64(api.witness + 64) == 1 && read64(api.witness + 72) == 1 && read64(api.witness + 80) == 0
	for slot in 0 .. 8 { assert byte_metadata_function(api,slot) != 0 }
	for request in [u64(0),0x3f,0xff,0x100,0x1ff,0xffffffffffffffff]! {
		access := unsafe { ByteMetadataAccess(voidptr(api.accessor)) };response := access(request)
		assert response.metadata == api.metadata && response.state == 0
		output := byte_metadata_guarded(probe,request,0,0,0,api.accessor)
		assert output[0] == api.metadata && output[1] == 0
	}
	if !api.native { assert byte_metadata_relative(api.descriptor + 16) == 0 }
}
fn byte_metadata_values(api ByteMetadataApi,probe u64) {
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
			output := byte_metadata_guarded(probe,dst,src,api.metadata,0,byte_metadata_function(api,slot))
			assert output[0] == dst && unsafe { *(&u8(dst)) } == u8(value) && unsafe { *(&u8(dst - 1)) } == 0x5a
			copy_value := unsafe { ByteMetadataCopy(voidptr(byte_metadata_function(api,slot))) };assert copy_value(dst,dst,api.metadata) == dst
			assert unsafe { *(&u8(src)) } == u8(value) && unsafe { *(&u8(src - 1)) } == 0x67
		}
	}
	destroy := unsafe { ByteMetadataDestroy(voidptr(byte_metadata_function(api,1))) }
	destroy(source + page,api.metadata);byte_metadata_guarded(probe,source + page,api.metadata,0,0,byte_metadata_function(api,1))
}
fn byte_metadata_enums(api ByteMetadataApi,probe u64) {
	// Widths measured independently from native VWT bytes at every transition.
	for pair in [[u32(0),0]!,[u32(1),1]!,[u32(256),1]!,[u32(65024),1]!,[u32(65025),2]!,
		[u32(65536),2]!,[u32(16776704),2]!,[u32(16776705),4]!,[u32(0xffffff00),4]!,[u32(0xffffff01),0]!,[u32(0xffffffff),0]!]! {
		cases := pair[0];width := pair[1];length := u64(width + 1);page := u64(C.getpagesize())
		base := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0));assert base != u64(-1)
		defer { assert C.munmap(unsafe { voidptr(base) },usize(page * 2)) == 0 }
		assert C.mprotect(unsafe { voidptr(base + page) },usize(page),C.PROT_NONE) == 0
		value := base + page - length
		get := unsafe { ByteMetadataGet(voidptr(byte_metadata_function(api,6))) };store := unsafe { ByteMetadataStore(voidptr(byte_metadata_function(api,7))) }
		for tag in [u32(0),1,255,256,257,65024,65025,65535,65536,16776704,16776705,0xffffff00,0xffffff01,0xffffffff]! {
			if tag > cases { continue }
			C.memset(unsafe { voidptr(value - 1) },0x5a,usize(length + 1))
			byte_metadata_guarded(probe,value,tag,cases,api.metadata,byte_metadata_function(api,7))
			assert unsafe { *(&u8(value - 1)) } == 0x5a
			assert unsafe { *(&u8(value)) } == if tag == 0 { u8(0x5a) } else { u8(tag - 1) }
			encoded := if tag == 0 { u32(0) } else { ((tag - 1) >> 8) + 1 }
			for i in u32(0) .. width { assert unsafe { *(&u8(value + 1 + i)) } == u8(encoded >> (i * 8)) }
			expected := if width == 0 { u32(0) } else { tag }
			assert get(value,cases,api.metadata) == expected
			output := byte_metadata_guarded(probe,value,cases,api.metadata,0,byte_metadata_function(api,6));assert u32(output[0]) == expected
			store(value,tag,cases,api.metadata);assert get(value,cases,api.metadata) == expected
		}
		if width == 0 { assert get(base + page,cases,api.metadata) == 0;store(base + page,0,cases,api.metadata) }
	}
}
fn byte_metadata_worker(signed_api ByteMetadataApi,unsigned_api ByteMetadataApi) {
	for _ in 0 .. 64 {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss4Int8VN') or { panic(err) } == signed_api.metadata
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5UInt8VMn') or { panic(err) } == unsigned_api.descriptor
		assert read64(signed_api.metadata - 8) == read64(unsigned_api.metadata - 8)
	}
}
fn byte_metadata_integration(api ByteMetadataApi) {
	// Symbolic nominal resolution follows each real relative accessor.
	// The indirect descriptor cell stays near the bounded symbolic name;
	// its canonical descriptor can live anywhere in the address space.
	page := usize(C.getpagesize());record := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert record != u64(-1);defer { assert C.munmap(unsafe { voidptr(record) },page) == 0 }
	unsafe { *(&u8(record)) = 2;*(&u8(record + 1)) = 15;*(&u8(record + 5)) = 0;*(&u64(record + 16)) = api.descriptor }
	assert swift_mangled_lookup_checked(record,5,0,0) or { panic(err) } == api.metadata
	array := swift_array_access(0,api.metadata);assert read64(array.metadata + 16) == api.metadata
	buffer := swift_array_allocate(257,api.metadata);storage := ios_runtime.swift_arrays[buffer.owner] or { panic('missing byte storage') }
	assert storage.element == api.metadata && storage.stride == 1 && storage.destroy == 0 && buffer.bytes == buffer.owner + storage.tail
	for i in u64(0) .. 257 { unsafe { *(&u8(buffer.bytes + i)) = u8(i) } }
	swift_array_destroy_elements(buffer.bytes,257,api.metadata)
	for i in u64(0) .. 257 { assert unsafe { *(&u8(buffer.bytes + i)) } == u8(i) }
	swift_bridge_release(buffer.owner)
}
fn test_swift_byte_nominal_metadata_and_witnesses() {
	page := usize(C.getpagesize());probe := C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0);assert probe != unsafe { voidptr(-1) }
	defer { assert C.munmap(probe,page) == 0 }
	byte_metadata_guard_emit(u64(probe));C.__builtin___clear_cache(probe,unsafe { voidptr(u64(probe) + 60) });assert C.mprotect(probe,page,C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);mut shared_witness := u64(0)
		for names in [['$ss4Int8VN','$ss4Int8VMn','$ss4Int8VMa','Int8']!,['$ss5UInt8VN','$ss5UInt8VMn','$ss5UInt8VMa','UInt8']!]! {
			metadata := u64(C.dlsym(core,unsafe { &char(names[0].str) }));witness := read64(metadata - 8) & 0x0000ffffffffffff
			api := ByteMetadataApi{native:true,metadata:metadata,descriptor:u64(C.dlsym(core,unsafe { &char(names[1].str) })),accessor:u64(C.dlsym(core,unsafe { &char(names[2].str) })),witness:witness,name:names[3]}
			if shared_witness == 0 { shared_witness = witness } else { assert shared_witness == witness }
			byte_metadata_layout(api,u64(probe));byte_metadata_values(api,u64(probe));byte_metadata_enums(api,u64(probe))
		}
		assert u64(C.dlsym(core,c'$sBi8_WV')) == shared_witness
		println('IOS-BYTE-METADATA-NATIVE: distinct Int8/UInt8 descriptors and complete accessors, shared Builtin.Int8 one-byte POD VWT, all256 bits through five copy/take slots at protected boundaries, no-read destroy, exact enum tag bytes/width transitions and UInt32 wrapping, preserved x20/x21')
	}
	for _ in 0 .. 2 {
		objc_start();mut apis := []ByteMetadataApi{cap:2}
		for names in [['_$ss4Int8VN','_$ss4Int8VMn','_$ss4Int8VMa','Int8']!,['_$ss5UInt8VN','_$ss5UInt8VMn','_$ss5UInt8VMa','UInt8']!]! {
			library := '/usr/lib/swift/libswiftCore.dylib';metadata := runtime_symbol(library,names[0]) or { panic(err) }
			api := ByteMetadataApi{metadata:metadata,descriptor:runtime_symbol(library,names[1]) or { panic(err) },accessor:runtime_symbol(library,names[2]) or { panic(err) },witness:read64(metadata - 8),name:names[3]}
			byte_metadata_layout(api,u64(probe));byte_metadata_values(api,u64(probe));byte_metadata_enums(api,u64(probe));byte_metadata_integration(api);apis << api
			for foreign in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! { for symbol in names[..3] { assert runtime_symbol(foreign,symbol) == none } }
			assert runtime_symbol(library,names[0][1..]) == none
		}
		assert apis[0].metadata != apis[1].metadata && apis[0].descriptor != apis[1].descriptor && apis[0].witness == apis[1].witness
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sBi8_WV') or { panic(err) } == apis[0].witness
		assert apis[0].metadata != swift_integer_metadata() && apis[0].witness != read64(swift_integer_metadata() - 8)
		mut workers := []thread{cap:8};for _ in 0 .. 8 { workers << spawn byte_metadata_worker(apis[0],apis[1]) };workers.wait();unsafe { workers.free();apis.free() }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_integer_arena;objc_stop();assert ios_runtime.swift_integer_arena == 0
		for offset in [u64(0),u64(page)]! {
			$if macos { assert C.mprotect(unsafe { voidptr(arena + offset) },page,C.PROT_READ) == -1 } $else { mut state := u8(0);assert C.mincore(unsafe { voidptr(arena + offset) },page,&state) == -1 }
		}
	}
	println('IOS-BYTE-METADATA: canonical distinct nominal metadata, shared one-byte witnesses and complete accessors in existing sealed integer arena, protected byte/tag spans, exact native UInt32 enum arithmetic, symbolic lookup, typed Array storage/POD destruction, eight readers and two drained arena lifetimes')
}
