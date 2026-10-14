// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type CocoaMetadata=fn (u64) SwiftAssociatedMetadata
type CocoaWitness=fn (u64,u64,u64) u64
type CocoaEqual=fn (u64,u64,u64,u64) bool
type CocoaCopy=fn (u64,u64,u64) u64
type CocoaDestroy=fn (u64,u64)
type CocoaTag=fn (u64,u32,u64) u32
type CocoaStore=fn (u64,u32,u32,u64)
type CocoaAssociated=fn (u64,u64,u64,u64,u64) SwiftAssociatedMetadata
type CocoaAssociatedConformance=fn (u64,u64,u64,u64,u64) u64
type CocoaSign=fn (u64,u64) u64
fn cocoa_relative(p u64) u64 {d:=i32(read32(p));return if d==0 {u64(0)}else{u64(i64(p)+i64(d))}}
fn cocoa_label(p u64) string {return unsafe{(&char(p)).vstring()}}
fn cocoa_values(metadata u64) {
	assert read64(metadata)==0x200
	witness:=read64(metadata-8);assert read64(witness+64)==8&&read64(witness+72)==8&&read32(witness+80)==0x02000007&&read32(witness+84)==0
	for bits in [u64(0),516,~u64(0),0x8000000000000000,0x1122334455667788]! {
		mut source:=bits
		for slot in [u64(0),2,3,4,5]! {call:=unsafe{CocoaCopy(voidptr(read64(witness+slot*8)&0x0000ffffffffffff))};mut output:=[u64(0xcafe),0,0xbeef]!;destination:=u64(unsafe{&output[1]})
			assert call(destination,u64(unsafe{&source}),metadata)==destination&&output==[u64(0xcafe),bits,0xbeef]!
			assert call(destination,destination,metadata)==destination&&output==[u64(0xcafe),bits,0xbeef]!
		}
	}
	get:=unsafe{CocoaTag(voidptr(read64(witness+48)&0x0000ffffffffffff))};put:=unsafe{CocoaStore(voidptr(read64(witness+56)&0x0000ffffffffffff))}
	for count in [u32(0),1,256,65536,0xffffffff]! {for tag in [u32(0),1,255,65535,0xffffffff]! {if tag>count {continue};mut value:=[u64(0xcafe),0x1122334455667788,0xabcdef00,0xbeef]!;p:=u64(unsafe{&value[1]});put(p,tag,count,metadata)
		assert value[0]==0xcafe&&value[3]==0xbeef&&get(p,count,metadata)==tag
	}}
}
fn cocoa_equality(table u64, metadata u64) {
	call:=unsafe{CocoaEqual(voidptr(read64(read64(table+8)+8)&0x0000ffffffffffff))}
	for left in [u64(0),516,~u64(0),0x8000000000000000]! {for right in [u64(0),516,~u64(0),0x8000000000000000]! {
		mut a:=left;mut b:=right;assert call(u64(unsafe{&a}),u64(unsafe{&b}),metadata,read64(table+8))==(left==right)
	}}
}
fn cocoa_publisher() u64 {
	mut table:=u64(0)
	for _ in 0..256 {entry:=runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation','_$s10Foundation10CocoaErrorV4CodeVMa') or {panic(err)};metadata:=unsafe{CocoaMetadata(voidptr(entry))(0xff)}.metadata
		descriptor:=runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_$s10Foundation10CocoaErrorV4CodeVAA01_cD8ProtocolAAMc') or {panic(err)};table=swift_witness_table(descriptor,metadata,0);cocoa_equality(table,metadata)
	};return table
}
fn test_swift_cocoa_error() {
	$if macos { if os.args.len==2&&os.args[1]=='--cocoa-stored-error' {
		objc_start();arena:=swift_cocoa_error_arena_checked() or {panic(err)};data:=arena+u64(C.getpagesize())
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe{nil}
		conform:=unsafe{CocoaAssociatedConformance(C.dlsym(core,c'swift_getAssociatedConformanceWitness'))}
		conform(data+640,data+16,data+48,data+372,data+388)
		panic('unexpected stored-error conformance publication')
	} }
	$if macos {
		foundation:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert foundation!=unsafe{nil}&&core!=unsafe{nil}
		access:=C.dlsym(foundation,c'$s10Foundation10CocoaErrorV4CodeVMa');descriptor:=u64(C.dlsym(foundation,c'$s10Foundation10CocoaErrorV4CodeVAA01_cD8ProtocolAAMc'));assert access!=unsafe{nil}&&descriptor!=0
		metadata:=unsafe{CocoaMetadata(access)(0)}.metadata;lookup:=unsafe{CocoaWitness(C.dlsym(core,c'swift_getWitnessTable'))};table:=lookup(descriptor,metadata,0)
		cocoa_values(metadata);cocoa_equality(table,metadata)
		proto:=cocoa_relative(descriptor);base:=proto+52
		associate:=unsafe{CocoaAssociated(C.dlsym(core,c'swift_getAssociatedTypeWitness'))};associated:=associate(0,table,metadata,base,base+24).metadata
		conform:=unsafe{CocoaAssociatedConformance(C.dlsym(core,c'swift_getAssociatedConformanceWitness'))};associated_table:=conform(table,metadata,associated,base,base+16);assert associated_table!=0
		assert read64(read64(associated-8)+64)==8&&read32(read64(associated-8)+80)==0x02010007
		println('IOS-COCOA-PROTOCOL-NATIVE: Code POD8 witnesses and integer equality, four-slot ErrorCodeProtocol table, associated CocoaError metadata and lazily resolved stored-error conformance')
	}
	if _:=swift_cocoa_error_arena_checked(){assert false}
	for _ in 0..2 {
		objc_start();mut workers:=[]thread u64{};for _ in 0..8 {workers<<spawn cocoa_publisher()};tables:=workers.wait();table:=tables[0];for candidate in tables {assert candidate==table}
		arena:=ios_runtime.swift_cocoa_error_arena;data:=arena+u64(C.getpagesize());metadata:=data+16;descriptor:=data+608
		entry:=runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_$s10Foundation10CocoaErrorV4CodeVMa') or {panic(err)}
		for request in [u64(0),0xff,0x100,0x1ff,~u64(0)]! {response:=unsafe{CocoaMetadata(voidptr(entry))(request)};assert response.metadata==metadata&&response.state==0}
		assert read64(metadata+8)==data+192&&read32(metadata+16)==0
		assert cocoa_label(cocoa_relative(data+192+8))=='Code'&&cocoa_relative(data+192+4)==data+224&&cocoa_label(cocoa_relative(data+224+8))=='CocoaError'
		assert read32(data+320+12)==3&&read32(data+320+16)==3&&read32(descriptor+12)==0
		assert table==data+640&&read64(table)==descriptor&&cocoa_relative(descriptor+4)==data+192
		cocoa_values(metadata);cocoa_equality(table,metadata)
		associated:=swift_associated_type(0xff,table,metadata,data+372,data+396).metadata;assert associated==data+48&&associated!=metadata
		$if macos { if ios_runtime.swift_cocoa_error_retired_arena==0 {
			core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe{nil}
			page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
			write32(code,0xdac10820);write32(code+4,0xd65f03c0);C.__builtin___clear_cache(voidptr(code),voidptr(code+8));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
			sign:=unsafe{CocoaSign(voidptr(code))};lookup:=unsafe{CocoaWitness(C.dlsym(core,c'swift_getWitnessTable'))}
			assert lookup(sign(descriptor,0xc6eb),metadata,0)&0x0000ffffffffffff==table
			native_associate:=unsafe{CocoaAssociated(C.dlsym(core,c'swift_getAssociatedTypeWitness'))}
			assert native_associate(0,table,metadata,data+372,data+396).metadata==associated
			assert C.munmap(voidptr(code),page)==0
		} }
		owner:=objc_allocate(ios_runtime.names['NSError']);mut source:=owner;mut copy:=u64(0);witness:=read64(associated-8)
		transfer:=unsafe{CocoaCopy(voidptr(read64(witness+16)))};destroy:=unsafe{CocoaDestroy(voidptr(read64(witness+8)))}
		assert transfer(u64(unsafe{&copy}),u64(unsafe{&source}),associated)==u64(unsafe{&copy})&&copy==owner&&obj_header(owner).refs==2
		destroy(u64(unsafe{&copy}),associated);objc_release(owner)
		if _:=swift_witness_table_checked(descriptor,swift_integer_metadata(),0){assert false}
		if _:=swift_cocoa_error_associated_checked(associated,metadata,table){assert false}
		for unsupported in ['_$s10Foundation10CocoaErrorVMa','_$s10Foundation10CocoaErrorV4CodeVMn','_$s10Foundation10CocoaErrorVAA21_BridgedStoredNSErrorAAMc']! {if _:=swift_foundation_symbol(unsupported){assert false}}
		assert ios_runtime.live==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0
		objc_stop();assert ios_runtime.swift_cocoa_error_arena==0&&ios_runtime.swift_cocoa_error_retired
		if _:=swift_witness_table_checked(descriptor,metadata,0){assert false}
		if _:=swift_cocoa_error_arena_checked(){assert false}
	}
	$if macos {
		mut child:=os.new_process(os.executable());child.set_args(['--cocoa-stored-error']);child.set_redirect_stdio_merged();child.run();output:=child.stdout_slurp();child.wait();status:=child.code;child.close()
		assert status!=0&&output.contains('CocoaError _BridgedStoredNSError witnesses are not implemented')&&!output.contains('unexpected stored-error conformance publication'),output
	}
	println('IOS-COCOA-PROTOCOL: canonical Code metadata and concrete conformance/equality, direct associated CocoaError reference layout/ARC, concurrent publication and two drained retirements; wider stored-error witnesses explicitly rejected before incomplete table publication')
}
