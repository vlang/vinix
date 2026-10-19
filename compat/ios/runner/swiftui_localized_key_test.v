// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
fn C.mincore(voidptr,usize,&u8)i32
$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self()u32
	fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32)i32
	fn C.mach_port_deallocate(u32,u32)i32
}
type LocalizedKeyProbe = fn (u64,u64,u64,&u64,u64)
type LocalizedKeyLiteral = fn (&u8,i64,bool)SwiftStringWords
type LocalizedKeyCString = fn (&u8)SwiftStringWords
type LocalizedKeyInterpolation = fn (i64,i64)SwiftStringWords
type LocalizedKeyKeep = fn (u64)u64
type LocalizedKeyDrop = fn (u64)
struct LocalizedKeyApi {
	native bool
	entry u64
	empty u64
	literal LocalizedKeyLiteral
	keep LocalizedKeyKeep
	drop LocalizedKeyDrop
	cstring LocalizedKeyCString
	interpolate LocalizedKeyInterpolation
}
fn localized_key_ascii(text string)bool{for byte in text{if byte>=128{return false}};return true}
fn localized_key_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC') or {panic(err)}}
fn localized_key_empty(owner u64){assert owner!=0&&read64(owner)!=0&&read64(owner+8)==0x80000004ffffffff&&read64(owner+16)==0&&read64(owner+24)==1}
fn localized_key_protection(address u64,length u64,execute bool){
	$if macos{
		mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
		assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0
		assert start<=address&&address+length<=start+size&&info[0]==(C.PROT_READ|if execute{C.PROT_EXEC}else{0})
		if object!=0{assert C.mach_port_deallocate(task,object)==0}
	}$else{
		mut found:=false;for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)};if address>=start&&address<end{assert address+length<=end&&fields[1]==if execute{'r-xp'}else{'r--p'};found=true;break}};assert found
	}
}
fn localized_key_call(api LocalizedKeyApi,probe LocalizedKeyProbe,words SwiftStringWords,guard u64){
	mut result:=[u64(0xcafe),0,0,0,0,0,0,0xbeef]!
	probe(words.first,words.second,api.entry,unsafe{&result[1]},guard)
	assert result==[u64(0xcafe),words.first,words.second,u64(0),api.empty,u64(0x5020),u64(0x5021),0xbeef]!
	localized_key_empty(result[4]);api.drop(result[4]);localized_key_empty(api.empty)
}
fn localized_key_owned(text string)SwiftStringWords{
	words:=swift_interpolation_init(i64(text.len+32),0);mut storage:=[words.first,words.second]!
	swift_string_append_bytes(u64(unsafe{&storage[0]}),u64(text.str),u64(text.len))
	return SwiftStringWords{storage[0],storage[1]}
}
fn localized_key_suite(api LocalizedKeyApi,probe LocalizedKeyProbe,guard u64){
	for text in ['','A','Fortnite','123456789012345','1234567890123456','é 🎮','a longer key with é and 🎮','%@ %d %%','a\x00b']!{
		words:=api.literal(text.str,text.len,localized_key_ascii(text));localized_key_call(api,probe,words,guard);api.drop(words.second)
	}
	// Raw ABI span probes: transfer opaque register bits without reading them.
	for words in [SwiftStringWords{0x1000000000000010,guard},SwiftStringWords{0,guard|(u64(1)<<60)},SwiftStringWords{0,guard|(u64(1)<<62)}]!{localized_key_call(api,probe,words,guard)}
	for alias in [false,true]!{for text in ['','a consuming owned SwiftUI key','a longer key with é and 🎮','owned\x00embedded\x00bytes']!{
		if api.native&&text.contains('\x00'){continue}
		words:=if api.native{if text.len==0{api.interpolate(40,0)}else{api.cstring(text.str)}}else{localized_key_owned(text)}
		owner:=words.second&swift_address_mask;assert words.second>>63==0
		before:=read64(owner+8);if alias{assert api.keep(words.second)==words.second}
		refs:=read64(owner+8);localized_key_call(api,probe,words,guard);assert read64(owner+8)==refs
		api.drop(words.second)
		if alias{assert read64(owner+8)==before;api.drop(words.second)}
	}}
}
fn localized_key_reader(probe LocalizedKeyProbe,guard u64)u64{
	mut entry:=u64(0);for _ in 0..128{candidate:=localized_key_resolve();if entry==0{entry=candidate}else{assert candidate==entry};api:=LocalizedKeyApi{entry:entry,empty:ios_runtime.swift_empty_array,drop:swift_bridge_release};localized_key_call(api,probe,swift_string_literal(c'worker',6,true),guard)};return entry
}
__global localized_key_teardown_calls=0
__global localized_key_probe_address=u64(0)
__global localized_key_guard_address=u64(0)
fn localized_key_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;entry:=localized_key_resolve();api:=LocalizedKeyApi{entry:entry,empty:ios_runtime.swift_empty_array,drop:swift_bridge_release};localized_key_call(api,unsafe{LocalizedKeyProbe(voidptr(localized_key_probe_address))},swift_string_empty(),localized_key_guard_address);localized_key_teardown_calls++}
fn test_swiftui_localized_key(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f0,0xaa0303f3,0xd28a0414,0xd28a0435,0xaa0403e8,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+64));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{LocalizedKeyProbe(voidptr(code))};localized_key_probe_address=code;localized_key_guard_address=guard
	$if macos{
		ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil}
		api:=LocalizedKeyApi{native:true,entry:u64(C.dlsym(ui,c'$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC')),empty:u64(C.dlsym(core,c'_swiftEmptyArrayStorage')),literal:unsafe{LocalizedKeyLiteral(C.dlsym(core,c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC'))},keep:unsafe{LocalizedKeyKeep(C.dlsym(core,c'swift_bridgeObjectRetain'))},drop:unsafe{LocalizedKeyDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))},cstring:unsafe{LocalizedKeyCString(C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC'))},interpolate:unsafe{LocalizedKeyInterpolation(C.dlsym(core,c'$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC'))}}
		assert api.entry!=0;localized_key_suite(api,probe,guard);assert C.dlclose(ui)==0&&C.dlclose(core)==0
		println('NATIVE-SWIFTUI-LOCALIZED-KEY: four direct result registers, consuming unchanged String bits and reference counts, formatting false, canonical empty arguments, protected x8/opaque inputs and preserved x20/x21')
	}
	if _:=swiftui_localized_key_arena_checked(){assert false}
	for _ in 0..2{
		objc_start();assert ios_runtime.swiftui_localized_key_arena==0&&!ios_runtime.swiftui_localized_key_retired&&ios_runtime.swift_empty_array==0
		ios_runtime.swift_concurrency_retired=true;if _:=swiftui_localized_key_arena_checked(){assert false};ios_runtime.swift_concurrency_retired=false
		for symbol in ['_$s7SwiftUI18LocalizedStringKeyVMa','_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfCExtra','_$s7SwiftUICore18LocalizedStringKeyV13stringLiteralACSS_tcfC']!{if _:=swiftui_localized_key_symbol(symbol){assert false}};assert ios_runtime.swiftui_localized_key_arena==0&&ios_runtime.swift_empty_array==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn localized_key_reader(probe,guard)};mut entry:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{entry=candidate}else{assert candidate==entry}};unsafe{workers.free()}
		assert read32(entry)==0xd2800002&&read32(entry+4)==0x58000063&&read32(entry+8)==0xd65f03c0&&read32(entry+12)==0xd503201f&&read64(entry+16)==ios_runtime.swift_empty_array
		api:=LocalizedKeyApi{entry:entry,empty:ios_runtime.swift_empty_array,literal:swift_string_literal,keep:swift_bridge_retain,drop:swift_bridge_release,interpolate:swift_interpolation_init};localized_key_suite(api,probe,guard)
		for _ in 0..300{words:=localized_key_owned('repeated owned key storage');localized_key_call(api,probe,words,guard);api.drop(words.second);assert ios_runtime.swift_strings.len==0}
		localized_key_protection(entry,24,true);localized_key_protection(api.empty,32,false)
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC'){assert false}}
		assert ios_runtime.swift_strings.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixLocalizedKeyTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(localized_key_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
		before:=localized_key_teardown_calls;empty_page:=api.empty-8;ios_runtime.swift_concurrency_retired=true;assert localized_key_resolve()==entry;objc_stop();assert localized_key_teardown_calls==before+1&&ios_runtime.swiftui_localized_key_retired&&ios_runtime.swiftui_localized_key_arena==0&&ios_runtime.swift_empty_array==0&&ios_runtime.live==0
		$if macos{assert C.mprotect(voidptr(entry),page,C.PROT_READ)==-1&&C.mprotect(voidptr(empty_page),page,C.PROT_READ)==-1}$else{mut r:=u8(0);assert C.mincore(voidptr(entry),page,&r)==-1&&C.mincore(voidptr(empty_page),page,&r)==-1};if _:=swiftui_localized_key_arena_checked(){assert false};assert ios_runtime.swift_empty_array==0
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-SWIFTUI-LOCALIZED-KEY: eight cold readers, canonical sealed RX initializer and empty Array, four direct result registers, exact consuming String transfer with unchanged alias reference counts, inline/immortal/owned Unicode NUL and percent keys, protected x8 and opaque inputs, 600 released owned calls, callback access and two drained/unmapped lifetimes; localization, interpolation and Text rendering remain unsupported')
}
