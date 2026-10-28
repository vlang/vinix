// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <mach/mach.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type OdTag = fn(u64,u64)u32
type OdDestroy = fn(u64,u64)

type OdAccess = fn (u64, u64) SwiftAssociatedMetadata
type OdNominal = fn (u64) SwiftAssociatedMetadata
type OdAllocate = fn (i64, u64) SwiftArrayAllocation
type OdLookup = fn (u64, u64, u64) u64
type OdKeep = fn (u64) u64
type OdDrop = fn (u64)
type OdInvoke = fn (u64, &u64, u64, u64, &u64)
type OdSign = fn (u64, u64) u64

type OdBox = fn (u64) SwiftArrayAllocation

struct OdApi {
	native     bool
	code       u64
	descriptor u64
	access     OdAccess @[required]
	lookup     OdLookup @[required]
	drop       OdDrop   @[required]
	keep_box   OdKeep   @[required]
	drop_box   OdDrop   @[required]
	box        u64
	elements   [4]u64
	witnesses  [4]u64
}

struct OdState {
	api              OdApi
	object           u64
	error_owner      u64
	count            u64
	kind             int
	failure          int
	profile          int
	reenter          bool
	decoder_shared   bool
	container_boxed  bool
	container_shared bool
	incoming u64
	result u64
	metadata u64
mut:
	draining bool
	element            u64
	decoder_metadata   u64
	decoder_table      u64
	container_metadata u64
	container_table    u64
	decoder_self       u64
	container_self     u64
	container_owner    u64
	getters            int
	ends               int
	decodes            int
	decoder_drops      int
	container_drops    int
}

fn od_symbol(native bool, library string, name string) u64 {
	$if macos {
		if native {
			handle := C.dlopen(library.str, 2)
			assert handle != unsafe { nil }
			address := u64(C.dlsym(handle, name[1..].str))
			assert address != 0, name
			return address
		}
	}
	return runtime_symbol(library, name) or { panic(err) }
}

fn od_api(native bool, code u64, guard u64) OdApi {
	core := '/usr/lib/swift/libswiftCore.dylib'
	foundation := '/System/Library/Frameworks/Foundation.framework/Foundation'
	lookup := unsafe { OdLookup(voidptr(od_symbol(native, core, '_swift_getWitnessTable'))) }
	date_access := unsafe { OdNominal(voidptr(od_symbol(native, foundation, '_$s10Foundation4DateVMa'))) }
	date := date_access(0).metadata
	date_table := lookup(od_symbol(native, foundation, '_$s10Foundation4DateVSeAAMc'), date, 0)
	return OdApi{
		native:     native
		code:       code
		descriptor: od_symbol(native, core, '_$sxSgSesSeRzlMc')
		access:     unsafe { OdAccess(voidptr(od_symbol(native, core, '_$sSqMa'))) }
		lookup:     lookup
		drop:       unsafe { OdDrop(voidptr(od_symbol(native, core, '_swift_bridgeObjectRelease'))) }
		keep_box:   unsafe { OdKeep(voidptr(od_symbol(native, core, '_swift_retain'))) }
		drop_box:   unsafe { OdDrop(voidptr(od_symbol(native, core, '_swift_release'))) }
		box:        if native { od_symbol(true, core, '_swift_allocBox') } else { u64(0) }
		elements:   [od_symbol(native, core, '_$sSiN'), od_symbol(native, core, '_$sSSN'), date, od_wide_metadata()]!
		witnesses:  [if native { od_symbol(true, core, '_$sSiSesWP') } else { guard },
			if native { od_symbol(true, core, '_$sSSSesWP') } else { guard + 8 }, date_table,
			if native { od_symbol(true, core, '_$sSiSesWP') } else { guard + 16 }]!
	}
}

// Synthetic complete POD metadata; the conditional table is forwarded only
// to this fixture's container. Compare all 48 output bytes with native Swift.
fn od_wide_copy(destination u64, source u64, _metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), 48)
	return destination
}
fn od_wide_destroy(_value u64, _metadata u64) {}
fn od_wide_tag(value u64, cases u32, _metadata u64) u32 {
	return if cases == 0 || unsafe { *(&u8(value + 48)) } == 0 { u32(0) } else { read32(value) + u32(1) }
}
fn od_wide_store(value u64, which u32, cases u32, _metadata u64) {
	if cases == 0 { return }
	unsafe { *(&u8(value + 48)) = if which == 0 { u8(0) } else { u8(1) } }
	if which != 0 { C.memset(voidptr(value), 0, 48); write32(value, which - u32(1)) }
}
fn od_wide_metadata() u64 {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != ~u64(0)
	metadata := base + 8
	witness := base + 64
	unsafe { *(&u64(base)) = witness; *(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = base + 256 }
	for i, entry in [u64(unsafe { voidptr(od_wide_copy) }), u64(unsafe { voidptr(od_wide_destroy) }),
		u64(unsafe { voidptr(od_wide_copy) }), u64(unsafe { voidptr(od_wide_copy) }),
		u64(unsafe { voidptr(od_wide_copy) }), u64(unsafe { voidptr(od_wide_copy) }),
		u64(unsafe { voidptr(od_wide_tag) }), u64(unsafe { voidptr(od_wide_store) }),
		u64(48), 48, 0x20007, 0, 0, 0]! {
		unsafe { *(&u64(witness + u64(i * 8))) = entry }
	}
	assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
	return metadata
}

fn od_box(s &OdState, metadata u64, heap u64) SwiftArrayAllocation {
	if s.api.native { return unsafe { OdBox(voidptr(s.api.box))(metadata) } }
	owner := swift_heap_allocate(heap, 48, 7)
	return SwiftArrayAllocation{ owner: owner, bytes: owner + 16 }
}

fn od_getter(metadata u64, table u64, output u64, receiver u64, incoming u64) u64 {
	mut s := unsafe { &OdState(read64(receiver)) }
	assert metadata == s.decoder_metadata && table == s.decoder_table && receiver == s.decoder_self && incoming == s.incoming
	assert s.getters == 0 && s.ends == 0 && s.decodes == 0 && s.decoder_drops == 0
	s.getters++
	od_reenter(s)
	if s.failure == -2 {
		od_object_keep(s.api, s.error_owner)
		return s.error_owner
	}
	mut payload := output
	if s.container_boxed {
		box := od_box(s, s.container_metadata, read64(s.container_metadata + 8))
		s.container_owner = box.owner
		payload = box.bytes
		if s.container_shared { s.api.keep_box(box.owner) }
		unsafe { *(&u64(output)) = box.owner }
	}
	s.container_self = payload
	unsafe {
		*(&u64(payload)) = u64(s)
		*(&u64(payload + 8)) = 0
		*(&u64(payload + 16)) = 0x12345678
		*(&u64(output + 24)) = s.container_metadata
		*(&u64(output + 32)) = s.container_table
	}
	return 0
}

fn od_end(metadata u64, table u64, receiver u64) u64 {
 mut s := unsafe { &OdState(read64(receiver)) }
 assert metadata == s.container_metadata && table == s.container_table && receiver == s.container_self
 assert s.getters == 1 && s.ends == 0 && s.decodes == 0 && s.container_drops == 0 && s.decoder_drops == 0
 s.ends++; od_reenter(s)
 return if s.count == 0 { u64(0x81) } else { u64(0x80) }
}

fn od_decode(type_arg u64, metadata u64, element_table u64, container u64, table u64, output u64, receiver u64, incoming u64) u64 {
 mut s := unsafe { &OdState(read64(receiver)) }
 assert type_arg == s.element && metadata == s.element && element_table == s.api.witnesses[s.kind]
 assert container == s.container_metadata && table == s.container_table && receiver == s.container_self && incoming == 0
 assert s.count == 1 && s.ends == 1 && s.decodes == 0 && s.container_drops == 0 && s.decoder_drops == 0
 assert od_refs(s.api, s.object) == 1 && output != s.result
 s.decodes++; od_reenter(s)
 if s.failure == 0 { od_object_keep(s.api,s.error_owner); return s.error_owner }
 if s.kind == 1 { od_object_keep(s.api,s.object); unsafe { *(&SwiftStringWords(output)) = SwiftStringWords{second:s.object|0x5000000000000000} } }
 else { if s.kind==3{C.memset(voidptr(output),0x67,48)};unsafe { *(&u64(output)) = 0x8123456789abcdef } }
 return 0
}

fn od_destroy(value u64, metadata u64) {
 mut s := unsafe { &OdState(read64(value)) }
 assert read64(value+16) == 0x12345678
 produced := s.count == 1 && s.decodes == 1 && s.failure < 0
 success := s.failure != -2 && !(s.count == 1 && s.failure == 0) && s.profile in [0,2]!
 if metadata == s.decoder_metadata {
  assert value == s.decoder_self && s.getters == 1 && s.decoder_drops == 0
  if !s.container_shared { assert s.container_drops == if s.failure == -2 {0}else{1} }
  if !s.draining {
   assert od_refs(s.api,s.object) == 1 + if s.kind == 1 && produced && success {i64(1)}else{i64(0)}
   if success {
    vwt := read64(s.metadata-8)&0x0000ffffffffffff
    tag := unsafe { OdTag(voidptr(read64(vwt+88)&0x0000ffffffffffff)) }
    assert tag(s.result,s.metadata) == if s.count == 0 {u32(1)}else{u32(0)}
   } else { assert read64(s.result) == 0xfeedface }
  }
  s.decoder_drops++
 } else {
  assert metadata == s.container_metadata && value == s.container_self && s.container_drops == 0
  if !s.draining {
   assert s.decoder_drops == 0 && read64(s.result) == 0xfeedface
   assert od_refs(s.api,s.object) == 1 + if s.kind == 1 && produced {i64(1)}else{i64(0)}
  }
  s.container_drops++
 }
 od_reenter(s)
}

fn od_box_destroy(owner u64) {
	od_destroy(owner + 16, read64(read64(owner) + 8))
	swift_heap_deallocate(owner, 48, 7)
}

fn od_emit(code u64) {
	// C entry/arguments/output/capture -> Swift. Preserve and capture x20/x21.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203e8,
		0xaa0403f3, 0xd28a0414, 0xaa0303f5, 0xa9400520, 0xf9400922, 0xd63f0200, 0xa9005674, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e2, 0xaa1403e3, 0xaa1503e4, 0x580000d0, 0xd63f0200,
		0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 168)) = u64(voidptr(od_getter)) }
	// Generic decode -> ordinary C; indirect result in x5, Self x6, error x7.
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e5, 0xaa1403e6, 0xaa1503e7, 0x580000d0, 0xd63f0200,
		0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 192 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 232)) = u64(voidptr(od_decode)) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e2, 0x580000d0, 0xd63f0200, 0xd28acf15, 0xa8c17bfd,
		0xd65f03c0]! {
		write32(code + 256 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 288)) = u64(voidptr(od_end)) }
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 320 + u64(i * 4), op) }
	unsafe { *(&u64(code + 336)) = u64(voidptr(od_box_destroy)) }
	write32(code + 384, 0xdac10020)
	write32(code + 388, 0xd65f03c0)
	write32(code + 400, 0xdac10820)
	write32(code + 404, 0xd65f03c0)
}

fn od_case(api OdApi, kind int, count u64, boxed bool, shared bool, at_end bool, failure int, profile int) {
 assert count <= 1
 page := usize(C.getpagesize())
 span := u64(C.mmap(unsafe{nil},page*5,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span != ~u64(0)
 defer { assert C.munmap(voidptr(span),page*5)==0 }
 data := u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert data != ~u64(0)
 defer { assert C.munmap(voidptr(data),page)==0 }
 for offset in [u64(page),u64(page*3)]! { assert C.mprotect(voidptr(span+offset),page,C.PROT_READ|C.PROT_WRITE)==0 }
 decoder := span+u64(page)+if at_end {u64(page)-40}else{u64(0)}
 element := api.elements[kind];metadata := api.access(0,element).metadata
 vwt := read64(metadata-8)&0x0000ffffffffffff;size := read64(vwt+64);stride := read64(vwt+72)
 result := span+u64(page*3)+if at_end {u64(page)-stride}else{u64(0)}
 object := od_object(api);error_owner := od_object(api)
 defer { od_object_drop(api,object);od_object_drop(api,error_owner) }
 container_boxed := profile==2;container_shared := container_boxed&&shared
 unsupported := profile in [1,3,4,5,6]!
 arg := [api.witnesses[kind]]!;table := api.lookup(api.descriptor,metadata,u64(unsafe{&arg[0]}))
 mut s := OdState{api:api,object:object,error_owner:error_owner,count:count,kind:kind,failure:failure,profile:profile,
  incoming:if at_end{u64(0)}else{u64(0x1234)},result:result,metadata:metadata,reenter:!api.native&&kind==1,
  decoder_shared:boxed&&shared,container_boxed:container_boxed,container_shared:container_shared,element:element,
  decoder_metadata:data+16,decoder_table:data+640,container_metadata:data+192,container_table:data+704}
 for i in 0..2 {
  meta:=data+16+u64(i*176);witness:=data+64+u64(i*176);mut pointer:=witness;mut destroy:=u64(voidptr(od_destroy))
  out_of_line:=(i==0&&boxed)||(i==1&&container_boxed)
  $if macos { if api.native {
   pointer=unsafe{OdSign(voidptr(api.code+400))(witness,(meta-8)|(u64(0x2e3f)<<48))}
   destroy=unsafe{OdSign(voidptr(api.code+384))(destroy,(witness+8)|(u64(0x4f8)<<48))}
  } }
  unsafe { *(&u64(meta-8))=pointer;*(&u64(meta))=0x200;*(&u64(meta+8))=data+944+u64(i*64)
   *(&u64(witness+8))=destroy;*(&u64(witness+64))=if out_of_line{u64(32)}else{u64(24)}
   *(&u64(witness+72))=if out_of_line{u64(32)}else{u64(24)} }
  write32(witness+80,if out_of_line{u32(0x30007)}else{u32(0x10007)})
  heap:=data+944+u64(i*64);unsafe{*(&u64(heap-16))=api.code+320;*(&u64(heap))=0x400;*(&u64(heap+8))=meta}
 }
 for item in [[u64(680),api.code+128,0x3fd3]!,[u64(720),api.code+256,0x2d02]!,[u64(856),api.code+192,0xe7dc]!]! {
  slot:=data+item[0];mut callback:=item[1]
  $if macos {if api.native{callback=unsafe{OdSign(voidptr(api.code+384))(callback,slot|(item[2]<<48))}}}
  unsafe{*(&u64(slot))=if (profile==1&&item[0]==720)||(profile==3&&item[0]==856){u64(0)}else{callback}}
 }
 mut decoder_owner:=u64(0);mut payload:=decoder
 if boxed{box:=od_box(unsafe{&s},s.decoder_metadata,data+944);decoder_owner=box.owner;payload=box.bytes;if shared{api.keep_box(box.owner)}}
 s.decoder_self=payload
 unsafe{*(&u64(payload))=u64(&s);*(&u64(payload+8))=0;*(&u64(payload+16))=0x12345678
  if boxed{*(&u64(decoder))=decoder_owner};*(&u64(decoder+24))=s.decoder_metadata;*(&u64(decoder+32))=s.decoder_table}
 C.memset(voidptr(result),0xa5,usize(size));unsafe{*(&u64(result))=0xfeedface}
 assert C.mprotect(voidptr(span+u64(page)),page,C.PROT_READ)==0&&C.mprotect(voidptr(data),page,C.PROT_READ)==0
 throws:=failure == -2 || (count==1&&failure==0)
 target:=if profile==4{u64(0)}else if profile==5{u64(1)}else if profile==6{~u64(7)}else if throws||unsupported{span}else{result}
 args:=[decoder,metadata,table]!;mut capture:=[u64(0xaaaa),0,0,0xbbbb]!
 if unsupported{assert !api.native;if _:=swift_optional_decoding_checked(decoder,metadata,table,target,s.incoming){assert false}}
 else{unsafe{OdInvoke(voidptr(api.code))(read64(table+8)&0x0000ffffffffffff,&args[0],target,s.incoming,&capture[1])}
  assert capture==[u64(0xaaaa),0x5020,if throws{error_owner}else{u64(0)},0xbbbb]!}
 assert s.getters==1&&s.ends==if failure == -2||profile==1{0}else{1}
 assert s.decodes==if failure == -2||profile==1||profile==3||count==0{0}else{1}
 assert s.container_drops==if failure == -2||container_shared{0}else{1}
 assert s.decoder_drops==if s.decoder_shared{0}else{1}
 if !throws&&!unsupported{
  tag:=unsafe{OdTag(voidptr(read64(vwt+88)&0x0000ffffffffffff))};assert tag(result,metadata)==if count==0{u32(1)}else{u32(0)}
  if count==1{if kind==1{assert read64(result)==0&&read64(result+8)==object|0x5000000000000000}else{assert read64(result)==0x8123456789abcdef}}
  if count==1&&kind==3{for i in u64(8)..48{assert unsafe{*(&u8(result+i))}==0x67}}
  assert od_refs(api,object)==1+if kind==1{i64(count)}else{i64(0)}
  destroy:=unsafe{OdDestroy(voidptr(read64(vwt+8)&0x0000ffffffffffff))};destroy(result,metadata)
 }else{assert read64(result)==0xfeedface}
 assert od_refs(api,object)==1&&od_refs(api,error_owner)==if throws&&!unsupported{2}else{1}
 if throws&&!unsupported{od_object_drop(api,error_owner)}
 s.draining=true
 if container_shared&&failure != -2{api.drop_box(s.container_owner)}
 if s.decoder_shared{api.drop_box(decoder_owner)}
 assert s.decoder_drops==1&&s.container_drops==if failure == -2{0}else{1}
}

fn od_matrix(api OdApi) {
 for kind in 0..4{for count in [u64(0),1]!{for boxed in [false,true]!{for shared in [false,true]!{for at_end in [false,true]!{for failure in [-2,-1,0]!{for profile in [0,2]!{od_case(api,kind,count,boxed,shared,at_end,failure,profile)}}}}}}}
}

fn od_object(api OdApi) u64 {
	$if macos {
		if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) }
	}
	return owned_string('owned Optional decoding payload')
}

fn od_object_keep(api OdApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRetain(voidptr(owner))
			return
		}
	}
	objc_retain(owner)
}

fn od_object_drop(api OdApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(owner))
			return
		}
	}
	objc_release(owner)
}

fn od_refs(api OdApi, owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(owner)) }
	}
	return obj_header(owner).refs
}

fn od_relative(at u64) u64 { return u64(i64(at) + i64(i32(read32(at)))) }

fn od_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sxSgSesSeRzlMc') or { panic(err) }
}

fn od_reenter(s &OdState) {
	if s.reenter {
		t := spawn od_resolve()
		assert t.wait() == s.api.descriptor
	}
}

fn od_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + length <= start + size
		assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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
				assert address + length <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found
	}
}

fn od_descriptor(api OdApi, guard u64) {
	d := api.descriptor
	protocol := od_relative(d)
	nominal := od_relative(d + 4)
	assert read32(d + 12) == 0x20100 && read32(d + 16) == 0x80 && read32(d + 28) == 0x30002 && read32(d + 32) == 0
	assert unsafe { (&char(voidptr(od_relative(protocol + 8)))).vstring() } == 'Decodable'
	assert unsafe { (&char(voidptr(od_relative(nominal + 8)))).vstring() } == 'Optional'
	assert unsafe { (&char(voidptr(od_relative(d + 20)))).vstring() } == 'x' && od_relative(d + 24) == protocol
	pattern := od_relative(d + 8)
	assert read64(pattern) == d && read64(pattern + 8) != 0
	if !api.native {
		od_protection(d, 80, false)
		od_protection(pattern, 16, false)
		od_protection(read64(pattern + 8), 32, true)
		cache := od_relative(d + 36)
		for i in 0 .. 16 {
			assert read64(cache + u64(i * 8)) == 0
		}
	}
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	defer { assert C.munmap(voidptr(base), page * 2) == 0 }
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	args := base + u64(page) - 8
	nested := api.access(0, api.elements[1]).metadata
	nestedarg := [api.witnesses[1]]!
	nestedtable := api.lookup(d, nested, u64(unsafe { &nestedarg[0] }))
	for pair in [[api.elements[0], api.witnesses[0]]!, [api.elements[1], api.witnesses[1]]!,
		[api.elements[2], api.witnesses[2]]!, [nested, nestedtable]!]! {
		metadata := api.access(0, pair[0]).metadata
		assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { *(&u64(args)) = pair[1] }
		assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
		table := api.lookup(d, metadata, args)
		assert table != od_relative(d + 8) && read64(table) == d && read64(table - 8) == pair[1]
		if !api.native { od_protection(table - 8, 24, false) }
		assert C.mprotect(voidptr(base), page, C.PROT_NONE) == 0
		for expired in [u64(0), args, guard]! {
			for _ in 0 .. 32 {
				assert api.lookup(d, metadata, expired) == table
			}
		}
	}
}

fn od_worker(api OdApi, i int) { od_case(api, i % 3, u64(i % 2), i % 2 == 0, true, true, i % 3 - 2, 2) }

fn test_swift_optional_decoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	od_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 408))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		api := od_api(true, code, guard)
		od_descriptor(api, guard)
		od_matrix(api)
		println('NATIVE-OPTIONAL-DECODING: 384 Int/String/Date/48-byte POD some/nil cases, shared Decoder/container boxes, nested conditional witnesses, decodeNil low bit, original owned errors, container cleanup before result publication and Decoder consumption')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn od_resolve() }
		identities := publishers.wait()
		api := od_api(false, code, guard)
		for descriptor in identities {
			assert descriptor == api.descriptor
		}
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn od_worker(api, i) }
		workers.wait()
		unsafe {
			workers.free()
			identities.free()
			publishers.free()
		}
		od_descriptor(api, guard)
		od_matrix(api)
  for count in [u64(0),1]! { od_case(api,1,count,true,false,true,-1,1) }
  od_case(api,1,1,true,false,true,-1,3)
  for count in [u64(0),1]! { for profile in [4,5,6]! { od_case(api,1,count,true,false,true,-1,profile) } }
		for metadata in [u64(0), 1, guard, ~u64(7)]! {
			if _ := swift_witness_table_checked(api.descriptor, metadata, guard) {
				assert false
			}
		}
		opaque := api.access(0, (swift_bool_metadata_arena_checked() or {panic(err)}) + u64(page) + 16).metadata
		for args in [u64(0), 1, ~u64(7)]! {
			if _ := swift_witness_table_checked(api.descriptor, opaque, args) {
				assert false
			}
		}
		for invalid in [u64(0), 1]! {
			args := [invalid]!
			if _ := swift_witness_table_checked(api.descriptor, opaque, u64(unsafe { &args[0] })) {
				assert false
			}
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sxSgSesSeRzlMc') == none
		}
		ios_runtime.swift_concurrency_retired = true
		assert swift_optional_decoding_symbol('_$sxSgSesSeRzlMc') == none
		if _ := swift_witness_table_checked(api.descriptor, opaque, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		tables := ios_runtime.swift_optional_decoding.values()
		arena := ios_runtime.swift_optional_decoding_arena
		objc_stop()
		assert C.munmap(voidptr(api.elements[3] - 8), page) == 0
		assert ios_runtime.swift_optional_decoding.len == 0 && ios_runtime.swift_optional_decoding_arena == 0
		if _ := swift_witness_table_checked(api.descriptor, opaque, guard) {
			assert false
		}
		for address in tables.map(it - 8) {
			$if macos {
				assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(address), page, unsafe { &resident }) == -1
			}
		}
		$if macos {
			assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
		} $else {
			mut resident := u8(0)
			assert C.mincore(voidptr(arena), page, unsafe { &resident }) == -1
		}
		unsafe { tables.free() }
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-OPTIONAL-DECODING: canonical conditional witnesses and single-value nil/generic decoding, exact owned payload moves, original error transfer and unwritten failure output, shared boxes, guarded readonly Decoder, eight cold publishers/workers, reentrant callbacks and two drained/unmapped lifetimes; unsupported Wrapped layouts remain rejected')
}
