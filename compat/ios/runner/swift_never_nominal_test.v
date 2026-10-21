// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type NnAccess = fn (u64) SwiftAssociatedMetadata
type NnGuard = fn (u64, u64, u64, u64, u64, &u64)
type NnGet = fn (u64, u32, u64) u32
type NnStore = fn (u64, u32, u32, u64)
type NnOptional = fn (u64, u64) SwiftAssociatedMetadata

struct NnApi {
	native     bool
	metadata   u64
	descriptor u64
	accessor   u64
	witness    u64
}

fn nn_relative(p u64) u64 { return u64(i64(p) + i64(i32(read32(p)))) }

fn nn_function(api NnApi, offset u64) u64 {
	entry := read64(api.witness + offset)
	return if api.native { entry & 0x0000ffffffffffff } else { entry }
}

fn nn_call(probe u64, a u64, b u64, c u64, d u64, entry u64) [4]u64 {
	mut output := [4]u64{}
	unsafe { NnGuard(voidptr(probe))(a, b, c, d, entry, &output[0]) }
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output
}

fn nn_layout(api NnApi, probe u64) {
	assert read64(api.metadata) == 0x201 && read64(api.metadata + 8) == api.descriptor
	assert read64(api.witness + 64) == 0 && read64(api.witness + 72) == 1
	assert read32(api.witness + 80) == 0 && read32(api.witness + 84) == 0
	assert read32(api.descriptor) == 0x52 && read32(api.descriptor + 20) == 0 && read32(api.descriptor + 24) == 0
	assert unsafe { (&char(nn_relative(api.descriptor + 8))).vstring() } == 'Never'
	parent := nn_relative(api.descriptor + 4)
	assert read32(parent) == 0 && unsafe { (&char(nn_relative(parent + 8))).vstring() } == 'Swift'
	assert nn_relative(api.descriptor + 12) == api.accessor
	for offset in [u64(0), 8, 16, 24, 32, 40, 48, 56]! {
		assert nn_function(api, offset) != 0
	}
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff, ~u64(0)]! {
		response := unsafe { NnAccess(voidptr(api.accessor))(request) }
		assert response.metadata == api.metadata && response.state == 0
		output := nn_call(probe, request, 0, 0, 0, api.accessor)
		assert output[0] == api.metadata && output[1] == 0
	}
	if !api.native {
		assert read32(api.descriptor + 16) == 0
	}
}

fn nn_values(api NnApi, probe u64, protected u64) {
	// A zero-sized value permits absent storage and pointers at either guard.
	for destination in [u64(0), protected, protected + u64(C.getpagesize())]! {
		for source in [u64(0), protected, ~u64(0)]! {
			for offset in [u64(0), 16, 24, 32, 40]! {
				assert nn_call(probe, destination, source, protected, 0, nn_function(api, offset))[0] == destination
			}
		}
		nn_call(probe, destination, protected, 0, 0, nn_function(api, 8))
	}
}

fn nn_enums(api NnApi, probe u64, span u64) {
	page := u64(C.getpagesize())
	get := unsafe { NnGet(voidptr(nn_function(api, 48))) }
	store := unsafe { NnStore(voidptr(nn_function(api, 56))) }
	for cases in [u32(0), 1, 2, 254, 255, 256, 65534, 65535, 65536, 0xfffffffe, 0xffffffff]! {
		// Independent width expectation includes Swift's UInt32 addition wrap.
		width := if cases == 0 || cases == 0xffffffff {
			u64(0)
		} else if cases < 255 {
			u64(1)
		} else if cases < 65535 {
			u64(2)
		} else {
			u64(4)
		}
		for at_end in [false, true]! {
			value := span + page + if at_end { page - width } else { u64(0) }
			for tag in [u32(0), 1, 2, 254, 255, 256, 65534, 65535, 65536, 0xfffffffe, 0xffffffff]! {
				assert C.mprotect(voidptr(span + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
				C.memset(voidptr(span + page), 0xa5, usize(page))
				store(value, tag, cases, api.metadata)
				nn_call(probe, value, tag, cases, api.metadata, nn_function(api, 56))
				for i in u64(0) .. 8 {
					address := if at_end { value - 4 + i } else { value + i }
					if address < span + page || address >= span + page * 2 { continue }
					expected := if address >= value && address - value < width {
						u8(tag >> u32((address - value) * 8))
					} else {
						u8(0xa5)
					}
					assert unsafe { *(&u8(address)) } == expected
				}
				assert C.mprotect(voidptr(span + page), usize(page), C.PROT_READ) == 0
				expected := if width == 0 {
					u32(0)
				} else if width == 1 {
					u32(u8(tag))
				} else if width == 2 {
					u32(u16(tag))
				} else {
					tag
				}
				assert get(value, cases, api.metadata) == expected
				assert u32(nn_call(probe, value, cases, api.metadata, 0, nn_function(api, 48))[0]) == expected
			}
		}
	}
}


fn nn_resolve() u64 {
 return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5NeverOMn') or { panic(err) }
}
fn nn_integration(api NnApi, span u64, native bool) {
 page:=u64(C.getpagesize());cell:=span+page;name:=span+page*2-5
 assert C.mprotect(voidptr(cell),usize(page),C.PROT_READ|C.PROT_WRITE)==0
 unsafe{*(&u64(cell))=api.descriptor}
 for tag in [u8(1),2]!{
  // The shared-cache descriptor may be outside a signed relative-pointer
  // span. Native checks use the same nearby indirect cell as the IPA.
  if native&&tag==1{continue}
  unsafe{*(&u8(name))=tag}
  target:=if tag==1{api.descriptor}else{cell}
  swiftui_opacity_symbolic_relative(name+1,target)
  assert C.mprotect(voidptr(cell),usize(page),C.PROT_READ)==0
  if native{
   $if macos{
    core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
    lookup:=unsafe{NnLookup(C.dlsym(core,c'swift_getTypeByMangledNameInContext'))}
    assert lookup(name,5,span,span)==api.metadata
   }
  }else{
   for request in [u64(0),0x3f,0xff,0x100,0x1ff,~u64(0)]!{
    assert swift_mangled_lookup_request_checked(request,name,5,span,span) or {panic(err)} == api.metadata
   }
  }
  assert C.mprotect(voidptr(cell),usize(page),C.PROT_READ|C.PROT_WRITE)==0
 }
 if !native{
  // Reserve capacity only: Never has no initialized elements.
  owner:=swift_array_buffer_allocate(257,api.metadata)
  assert ios_runtime.swift_arrays[owner].stride==1&&ios_runtime.swift_arrays[owner].destroy==0&&read64(owner+16)==0
  swift_bridge_release(owner)
 }
}
type NnLookup=fn(u64,u64,u64,u64)u64
fn nn_worker(expected u64){for _ in 0..128{assert nn_resolve()==expected}}
__global nn_teardown_count=0
fn nn_teardown(object u64,selector &char){
 assert ios_runtime.swift_concurrency_retired
 d:=nn_resolve();assert d==ios_runtime.swiftui_opacity_arena+u64(C.getpagesize())+384
 assert swift_mangled_nominal(d) or {panic(err)} == ios_runtime.swiftui_opacity_arena+u64(C.getpagesize())+264
 nn_teardown_count++
}
fn nn_reject(){
 assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5NeverOMn')==none
}
fn test_swift_never_nominal(){
 $if !arm64{return}
 page:=usize(C.getpagesize())
 probe:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
 span:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert probe!=~u64(0)&&span!=~u64(0)
 defer{assert C.munmap(voidptr(probe),page)==0;assert C.munmap(voidptr(span),page*3)==0}
 for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0x910003fd,0xaa0503f3,
  u32(0xd2800000|(0x5020<<5)|20),u32(0xd2800000|(0x5121<<5)|21),0xaa0403f0,
  0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!{write32(probe+u64(i*4),op)}
 C.__builtin___clear_cache(voidptr(probe),voidptr(probe+60));assert C.mprotect(voidptr(probe),page,C.PROT_READ|C.PROT_EXEC)==0
 $if macos{
  core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);metadata:=u64(C.dlsym(core,c'$ss5NeverON'));assert metadata!=0
  api:=NnApi{native:true,metadata:metadata,descriptor:u64(C.dlsym(core,c'$ss5NeverOMn')),accessor:u64(C.dlsym(core,c'$ss5NeverOMa')),witness:read64(metadata-8)&0x0000ffffffffffff}
  nn_layout(api,probe);nn_values(api,probe,span);nn_enums(api,probe,span);nn_integration(api,span,true)
  println('NATIVE-NEVER-NOMINAL: zero-case enum descriptor and complete accessor, eight zero-size witnesses, protected absent values, native UInt32 tag widths/wrap, indirect symbolic references at protected bounds, preserved x20/x21')
 }
 nn_reject()
 for order in 0..2{
  objc_start();assert ios_runtime.swiftui_opacity_arena==0&&!ios_runtime.swiftui_opacity_retired
  ios_runtime.swift_concurrency_retired=true;nn_reject();assert ios_runtime.swiftui_opacity_arena==0;ios_runtime.swift_concurrency_retired=false
  for symbol in ['_$ss5NeverON','_$ss5NeverOMa','_$ss5NeverOWV','_$ss5NeverOMnExtra','$ss5NeverOMn']!{assert swift_never_nominal_symbol(symbol)==none}
  for library in ['/usr/lib/libSystem.B.dylib','/System/Library/Frameworks/SwiftUI.framework/SwiftUI','/System/Library/Frameworks/Foundation.framework/Foundation']!{assert runtime_symbol(library,'_$ss5NeverOMn')==none}
  assert ios_runtime.swiftui_opacity_arena==0
  if order==1{assert runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$ss5NeverO7SwiftUI4ViewACWP') or {panic(err)} != 0}
  mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn nn_resolve()};identities:=publishers.wait();for identity in identities{assert identity==identities[0]}
  descriptor:=identities[0];base:=ios_runtime.swiftui_opacity_arena;data:=base+u64(page);metadata:=data+264
  api:=NnApi{metadata:metadata,descriptor:descriptor,accessor:nn_relative(descriptor+12),witness:read64(metadata-8)}
  assert descriptor==data+384&&api.accessor==base+32
  nn_layout(api,probe);nn_values(api,probe,span);nn_enums(api,probe,span);nn_integration(api,span,false)
  table:=runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$ss5NeverO7SwiftUI4ViewACWP') or {panic(err)}
  assert table==data+960&&read64(table+16)==metadata&&read64(data+1040)==descriptor&&read64(data+480+16)==metadata
  assert read32(descriptor+16)==0&&ios_runtime.swift_void_arena==0
  mut workers:=[]thread{};for _ in 0..8{workers<<spawn nn_worker(descriptor)};workers.wait()
  assert ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.objects.len==0&&ios_runtime.live==0
  cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixNeverNominalTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(nn_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
  before:=nn_teardown_count;ios_runtime.swift_concurrency_retired=true;assert nn_resolve()==descriptor;objc_stop()
  assert nn_teardown_count==before+1&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swiftui_opacity_retired&&ios_runtime.objects.len==0&&ios_runtime.live==0;nn_reject()
  for offset in [usize(0),page]!{
   $if macos{assert C.mprotect(voidptr(base+u64(offset)),page,C.PROT_READ)==-1}
   $else{mut state:=u8(0);assert C.mincore(voidptr(base+u64(offset)),page,unsafe{&state})==-1}
  }
 }
 println('IOS-NEVER-NOMINAL: exact Core-only descriptor export, canonical SwiftUI Never identity in both resolution orders, native complete accessor/eight zero-size witnesses and guarded tag widths, protected direct/indirect symbolic lookup and unused context/args, empty typed capacity, eight cold publishers/readers, callback access and two drained/unmapped lifetimes; no new arena/cache or graph support')
}
