// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self() u32
	fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
	fn C.mach_port_deallocate(u32, u32) i32
}
type CkddProbe = fn (u64, u64, u64, u64, u64, u64, u64)
type CkddSign = fn (u64, u64) u64
type CkddBytes = fn (u64, u64) u64
type CkddDrop = fn (u64)
fn ckdd_emit(code u64) {
	// C(entry,metadata,CodingKey,Self,observed,returned,context) -> Swift.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5,
		0xaa0003f0, 0xaa0303f4, 0xaa0503f3, 0xaa0603f5,
		0xaa0403e7, 0xaa0103e0, 0xaa0203e1, 0xd28a4456,
		0xd63f0200, 0xa9000660, 0xa9015674, 0xf9001276,
		0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	for variant in 0 .. 2 {
		entry := code + 128 + u64(variant * 64)
		for i, op in [u32(0xa90004e0), 0xa90154f4, 0xf90010f6,
			0xd2800009 | (u32(0x6000 + variant) << 5), 0xf90014e9,
			0xa94304e0, 0xd65f03c0]! { write32(entry + u64(i * 4), op) }
	}
	write32(code + 256, 0xdac10020); write32(code + 260, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 264))
}
fn ckdd_symbol(native bool, symbol string) u64 {
	if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert core != unsafe { nil }
		address := u64(C.dlsym(core, symbol[1..].str)); assert address != 0; return address
	}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
}
fn ckdd_case(entry u64, code u64, metadata u64, coding_key u64, parent u64, source u64, variant int, bits u64, context u64) {
	mut observed := [u64(0), 0, 0, 0, 0, 0, bits, ~bits]!
	mut returned := [u64(0xcafe), 0, 0, 0, 0, 0, 0xbeef]!
	unsafe { CkddProbe(voidptr(code))(entry, metadata, coding_key, source, u64(&observed[0]), u64(&returned[1]), context) }
	assert observed[0] == metadata && observed[1] == parent && observed[2] == source && observed[3] == context && observed[4] == 0x5222
	assert observed[5] == u64(0x6000 + variant) && observed[6] == bits && observed[7] == ~bits
	assert returned == [u64(0xcafe), bits, ~bits, source, context, 0x5222, 0xbeef]!
}
fn ckdd_worker(entry u64, code u64, metadata u64, table u64, parent u64, source u64, variant int) {
	for i in 0 .. 64 { ckdd_case(entry, code, metadata, table, parent, source, variant, u64(i) | (u64(1) << 63), u64(i & 1) * 0xab21) }
}
fn ckdd_spans(entry u64, code u64, native bool) {
	page := usize(C.getpagesize())
	for placement in 0 .. 4 { for variant in 0 .. 2 {
		span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert span != ~u64(0)
		for offset in [u64(page), u64(page * 3)]! { assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0 }
		key_slot := span + u64(page) + if placement & 1 != 0 { u64(page) - 8 } else { u64(0) }
		parent_slot := span + u64(page * 3) + if placement & 2 != 0 { u64(page) - 8 } else { u64(0) }
		parent := parent_slot - 8; table := key_slot - 16
		mut getter := code + 128 + u64(variant * 64)
		if native { getter = unsafe { CkddSign(voidptr(code + 256))(getter, parent_slot | (u64(0x8be3) << 48)) } }
		unsafe { *(&u64(key_slot)) = parent; *(&u64(parent_slot)) = getter }
		for offset in [u64(page), u64(page * 3)]! { assert C.mprotect(voidptr(span + offset), page, C.PROT_READ) == 0 }
		for bits in [u64(0), 1, 0x7fffffffffffffff, 0x8000000000000000, ~u64(0)]! {
			for context in [u64(0), 0xab21, ~u64(0)]! { ckdd_case(entry, code, span, table, parent, span + u64(page * 2), variant, bits, context) }
		}
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn ckdd_worker(entry, code, span, table, parent, span + u64(page * 2), variant) }
		workers.wait(); unsafe { workers.free() }
		assert read64(key_slot) == parent && read64(parent_slot) == getter
		assert C.munmap(voidptr(span), page * 5) == 0
	} }
}
fn ckdd_owned(entry u64, code u64, native bool) {
	page := usize(C.getpagesize()); memory := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert memory != ~u64(0)
	integer := ckdd_symbol(native, '_$sSiN'); parent := ckdd_symbol(native, '_$sSis23CustomStringConvertiblesWP')
	unsafe { *(&u64(memory + 16)) = parent }
	assert C.mprotect(voidptr(memory), page, C.PROT_READ) == 0
	bytes := unsafe { CkddBytes(voidptr(ckdd_symbol(native, '_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg'))) }
	drop := unsafe { CkddDrop(voidptr(ckdd_symbol(native, '_swift_bridgeObjectRelease'))) }
	for value in [i64(0), -7, 9223372036854775807, -9223372036854775807 - 1]! {
		unsafe { *(&i64(memory + u64(page))) = value }; assert C.mprotect(voidptr(memory + u64(page)), page, C.PROT_READ) == 0
		mut observed := [8]u64{}; mut returned := [u64(0xcafe), 0, 0, 0, 0, 0, 0xbeef]!
		unsafe { CkddProbe(voidptr(code))(entry, integer, memory, memory + u64(page), u64(&observed[0]), u64(&returned[1]), 0xab21) }
		assert returned[0] == 0xcafe && returned[6] == 0xbeef && returned[3] == memory + u64(page) && returned[4] == 0xab21 && returned[5] == 0x5222
		buffer := bytes(returned[1], returned[2]); expected := value.str()
		assert read64(buffer + 16) == u64(expected.len + 1) && C.memcmp(voidptr(buffer + 32), expected.str, usize(expected.len)) == 0
		drop(buffer); drop(returned[2]); unsafe { expected.free() }
		assert read64(memory + u64(page)) == u64(value) && read64(memory + 16) == parent
		assert C.mprotect(voidptr(memory + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	assert C.munmap(voidptr(memory), page * 2) == 0
}
fn ckdd_mapping(address u64,mapped bool){
 $if macos{
  mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
  status:=C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)
  if mapped{assert status==0&&start<=address&&address+8<=start+size&&info[0]==C.PROT_READ|C.PROT_EXEC}else{assert status!=0||start>address}
  if object!=0{assert C.mach_port_deallocate(task,object)==0}
 }$else{
  mut found:=false;for line in (os.read_file('/proc/self/maps')or{panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64)or{panic(err)};end:=strconv.parse_uint(range[1],16,64)or{panic(err)};if address>=start&&address<end{assert mapped&&address+8<=end&&fields[1]=='r-xp';found=true;break}};assert found==mapped
 }
}

fn ckdd_publish()u64{return ckdd_symbol(false,'_$ss9CodingKeyPsE16debugDescriptionSSvg')}
fn test_swift_coding_key_debug_description(){
 $if !arm64{return}
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
 ckdd_emit(code);assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
 $if macos{
  entry:=ckdd_symbol(true,'_$ss9CodingKeyPsE16debugDescriptionSSvg');ckdd_spans(entry,code,true);ckdd_owned(entry,code,true)
  println('NATIVE-CODING-KEY-DEBUG-DESCRIPTION: inherited table16/getter8, arbitrary supplied description and exact result forwarding, protected Self/metadata, guarded readonly table slots, preserved x20/x21/x22, owned Int descriptions and eight callers')
 }
 assert swift_coding_key_debug_description_symbol('_$ss9CodingKeyPsE16debugDescriptionSSvg')==none
 for order in 0..2{
  objc_start();assert ios_runtime.swift_hash_code==0
  for symbol in ['_$ss9CodingKeyPsE16debugDescriptionSSvgExtra','$ss9CodingKeyPsE16debugDescriptionSSvg','_$ss9CodingKeyPsE11descriptionSSvg']!{assert swift_coding_key_debug_description_symbol(symbol)==none}
  for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib','/System/Library/Frameworks/Foundation.framework/Foundation']!{assert runtime_symbol(library,'_$ss9CodingKeyPsE16debugDescriptionSSvg')==none}
  ios_runtime.swift_concurrency_retired=true;assert swift_coding_key_debug_description_symbol('_$ss9CodingKeyPsE16debugDescriptionSSvg')==none&&ios_runtime.swift_hash_code==0;ios_runtime.swift_concurrency_retired=false
  if order==1{swift_hash_entry(1824)}
  mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn ckdd_publish()};entries:=publishers.wait();entry:=entries[0];for candidate in entries{assert candidate==entry};unsafe{publishers.free();entries.free()}
  assert entry==ios_runtime.swift_hash_code+1888;ckdd_mapping(entry,true);ckdd_spans(entry,code,false);ckdd_owned(entry,code,false)
  assert ios_runtime.objects.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_strings.len==0&&ios_runtime.swift_buffers.len==0
  ios_runtime.swift_concurrency_retired=true;assert swift_coding_key_debug_description_symbol('_$ss9CodingKeyPsE16debugDescriptionSSvg')==none
  objc_stop();assert ios_runtime.swift_hash_code==0;ckdd_mapping(entry,false)
 }
 assert C.munmap(voidptr(code),page)==0
 println('IOS-CODING-KEY-DEBUG-DESCRIPTION: supplied inherited description witness, no formatter or ARC work, protected Self/metadata and guarded readonly slots, exact returned bits and owned Strings, eight publishers/callers and both publication orders, two drained/unmapped lifetimes')
}
