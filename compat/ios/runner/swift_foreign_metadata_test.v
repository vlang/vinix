// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type ForeignMetadataCall=fn (u64,u64) SwiftAssociatedMetadata
type ForeignMetadataProbe=fn (u64,u64,u64,&u64)
type ForeignMetadataSign=fn (u64,u64) u64
fn foreign_test_relative(field u64,target u64) {write32(field,u32(i32(i64(target)-i64(field))))}
fn foreign_test_record(base u64,witness u64,name string,alias bool,sign ForeignMetadataSign,native bool) u64 {
	metadata:=base+8;descriptor:=base+32;parent:=base+112;identity:=base+160
	text:=if alias {'SwiftAlias\x00N'+name+'\x00\x00'}else{name+'\x00\x00'}
	assert text.len<128;C.memcpy(voidptr(identity),text.str,usize(text.len))
	unsafe {*(&u64(metadata-8))=witness;*(&u64(metadata))=0x201;*(&u64(metadata+8))=descriptor}
	write32(descriptor,0x60012);write32(descriptor+24,4);foreign_test_relative(descriptor+4,parent);foreign_test_relative(descriptor+8,identity)
	foreign_test_relative(parent+8,base+304);C.memcpy(voidptr(base+304),c'__C',4)
	$if macos {if native {
		unsafe {*(&u64(metadata-8))=sign(witness,(metadata-8)|(u64(11839)<<48));*(&u64(metadata+8))=sign(descriptor,(metadata+8)|(u64(44678)<<48))}
	}}
	return metadata
}
fn foreign_test_response(probe ForeignMetadataProbe,entry u64,request u64,metadata u64,expected u64) {
	mut words:=[u64(0x1234),0,0,0,0,0x5678]!
	probe(request,metadata,entry,unsafe {&words[1]})
	assert words==[u64(0x1234),expected,0,0x5020,0x5021,0x5678]!
}
fn foreign_test_native(probe ForeignMetadataProbe,sign ForeignMetadataSign) {
	$if macos {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe {nil};entry:=u64(C.dlsym(core,c'swift_getForeignTypeMetadata'))
		page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe {nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
		mut records:=[12]u64{}
		for i,width in [u64(1),2,4,8]! {
			name:='VinixNativeForeignScalar'+width.str();symbol:='$sBi'+(width*8).str()+'_WV';witness:=u64(C.dlsym(core,symbol.str));assert witness!=0
			for j in 0..3 {records[i*3+j]=foreign_test_record(base+u64(i*1536+j*512),witness,if j==2 {name+'Other'}else{name},j==1,sign,true)}
		}
		assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==0
		for i in 0..4 {for j in 0..3 {for request in [u64(0),0x3f,0xff,0x100,0x1ff,0xffffffffffffffff]! {for _ in 0..32 {foreign_test_response(probe,entry,request,records[i*3+j],records[i*3+if j==1 {0}else{j}])}}}}
		// Native cache borrows these read-only templates/names until process exit.
		println('IOS-FOREIGN-METADATA-NATIVE: complete scalar enums1/2/4/8, identity/alias/different-name canonicalization, all request bits including nonblocking/abstract, x0/x1 response and x20/x21, read-only templates/witnesses, repeated borrowed requests with no input writes')
	}
}
fn foreign_test_worker(metadata u64) u64 {
	mut canonical:=u64(0)
	for _ in 0..1000 {response:=swift_foreign_metadata(0x100,metadata);assert response.state==0;if canonical==0 {canonical=response.metadata}else{assert response.metadata==canonical}}
	return canonical
}
fn foreign_test_rejected(metadata u64) {if _:=swift_foreign_metadata_checked(0,metadata) {assert false,'unsupported foreign template accepted'}}
fn foreign_test_suite(probe ForeignMetadataProbe,sign ForeignMetadataSign,base u64) {
	entry:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getForeignTypeMetadata') or {panic(err)}
	mut records:=[12]u64{}
	for i,width in [u64(1),2,4,8]! {
		witness:=base+6144+u64(i*128);unsafe {*(&u64(witness+64))=width;*(&u64(witness+72))=width};write32(witness+80,u32(width-1))
		name:='VinixForeignScalar'+width.str()
		for j in 0..3 {records[i*3+j]=foreign_test_record(base+u64(i*1536+j*512),witness,if j==2 {name+'Other'}else{name},j==1,sign,false)}
	}
	page:=usize(C.getpagesize());assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==0
	for i in 0..4 {for j in 0..3 {for request in [u64(0),0x3f,0xff,0x100,0x1ff,0xffffffffffffffff]! {foreign_test_response(probe,entry,request,records[i*3+j],records[i*3+if j==1 {0}else{j}])}}}
	assert ios_runtime.swift_foreign_metadata_count==8&&ios_runtime.swift_metadata_arena==0&&ios_runtime.swift_error_arena==0
	mut workers:=[]thread u64{};for i in 0..8 {workers<<spawn foreign_test_worker(records[i%2])};for metadata in workers.wait() {assert metadata==records[0]}
	assert C.mprotect(voidptr(base),page*2,C.PROT_READ|C.PROT_WRITE)==0
	bad:=base+8192;witness:=base+6144;metadata:=foreign_test_record(bad,witness,'VinixRejectedForeign',false,sign,false);descriptor:=bad+32
	for mode in 0..8 {
		write32(descriptor,if mode==0 {u32(0x60092)}else{u32(0x60012)});write32(descriptor+16,if mode==1 {u32(4)}else{u32(0)});write32(descriptor+20,if mode==2 {u32(1)}else{u32(0)})
		write32(descriptor+28,if mode==3 {u32(4)}else{u32(0)});write32(descriptor+32,if mode==4 {u32(4)}else{u32(0)})
		write32(witness+80,if mode==5 {u32(0x400000)}else{u32(0)});write32(witness+84,if mode==6 {u32(1)}else{u32(0)})
		unsafe {*(&u64(metadata))=if mode==7 {u64(0x204)}else{u64(0x201)}};foreign_test_rejected(metadata)
	}
	write32(witness+80,0);write32(witness+84,0);unsafe {*(&u64(metadata))=0x201};write32(descriptor+16,0);write32(descriptor+20,0);write32(descriptor+28,0);write32(descriptor+32,0)
	for text in ['Bad\x00RRelated\x00\x00','Bad\x00NNamed\x00NAgain\x00\x00','Bad\x00SNamespace\x00\x00']! {C.memset(voidptr(bad+160),0,128);C.memcpy(voidptr(bad+160),text.str,usize(text.len));foreign_test_rejected(metadata)}
	assert ios_runtime.swift_foreign_metadata_count==8
	for invalid in [u64(0),1,~u64(0)-7]! {foreign_test_rejected(invalid)}
	// Fill the bounded cache; rejection of a65th name cannot overwrite entries.
	for i in 0..56 {slot:=base+12288+u64(i*512);item:=foreign_test_record(slot,witness,'VinixCacheFill'+i.str(),false,sign,false);assert swift_foreign_metadata(0,item).metadata==item}
	assert ios_runtime.swift_foreign_metadata_count==64
	last:=foreign_test_record(base+40960,witness,'VinixCacheOverflow',false,sign,false);foreign_test_rejected(last);assert swift_foreign_metadata(0,records[0]).metadata==records[0]
	ios_runtime.swift_concurrency_retired=true;foreign_test_rejected(0);ios_runtime.swift_concurrency_retired=false
	if _:=runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_swift_getForeignTypeMetadata') {assert false}
	if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','__swift_getForeignTypeMetadata') {assert false}
}
fn test_swift_foreign_metadata() {
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe {nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,word in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0303f3,0xaa0203f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+u64(i*4),word)}
	write32(code+64,0xdac10820);write32(code+68,0xd65f03c0);C.__builtin___clear_cache(voidptr(code),voidptr(code+72));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	probe:=unsafe {ForeignMetadataProbe(voidptr(code))};sign:=unsafe {ForeignMetadataSign(voidptr(code+64))};foreign_test_native(probe,sign)
	base:=u64(C.mmap(unsafe {nil},65536,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	for _ in 0..2 {C.memset(voidptr(base),0,65536);objc_start();foreign_test_suite(probe,sign,base);assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0;objc_stop();assert ios_runtime.swift_foreign_metadata_count==0;for entry in ios_runtime.swift_foreign_metadata {assert entry==SwiftForeignMetadataEntry{}}}
	assert C.munmap(voidptr(base),65536)==0&&C.munmap(voidptr(code),page)==0
	println('IOS-FOREIGN-METADATA: exact Core-only complete scalar-enum response, native imported-name canonicalization and all request bits, bounded allocation-free borrowed cache, preserved registers/read-only records, eight publication readers, guarded unsupported callbacks/layouts/names/capacity, two emptied cache lifetimes before caller unmapping')
}
