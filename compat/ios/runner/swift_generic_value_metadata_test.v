// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.mincore(voidptr,usize,&u8)i32
type GvAllocate = fn(u64,u64,u64,u64)u64

struct GvInput {
	base u64
	length usize
	descriptor u64
	pattern u64
	arguments u64
	witness u64
	source u64
	extra u64
	keys int
	prefix u64
	size u64
	kind u32
}
fn gv_input(kind u32,keys int,partial bool,indirect bool,extra u64,at_end bool)GvInput{
	page:=u64(C.getpagesize());length:=usize(page*12)
	base:=u64(C.mmap(unsafe{nil},length,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	for i in [u64(1),3,5,7,9]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ|C.PROT_WRITE)==0}
	// Include a key protocol witness and a nonkey same-type constraint. Their
	// referents, the VWT and instantiation/completion functions are guarded.
	params:=if keys>1{keys-1}else{keys};requirements:=if keys>1{2}else{0}
	descriptor_size:=u64(44+((params+3)&~3)+requirements*12)
	descriptor:=base+page+if at_end{page-descriptor_size}else{u64(0)}
	pattern_size:=if partial{u64(24)}else{u64(16)}
	pattern:=base+page*3+if at_end{page-pattern_size}else{u64(0)}
	arguments:=if keys==0{base}else{base+page*5+if at_end{page-u64(keys*8)}else{u64(0)}}
	witness:=if at_end{base}else{base+page*10} // PROT_NONE, with signed relative references in both directions.
	cell:=base+if indirect{page+256}else{page*7}
	prefix:=if partial{u64(keys*8)}else{u64(0)}
	size:=if partial{extra-prefix}else{u64(0)}
	source:=base+if indirect{page+512}else{page*9+if at_end{page-size}else{u64(0)}}
	assert !partial || (extra>=prefix && size%8==0 && size<=page-8)
	write32(descriptor,if kind==0x200{u32(0xd1)}else{u32(0xd2)})
	write32(descriptor+36,u32(params)|(u32(requirements)<<16));write32(descriptor+40,u32(keys))
	for i in 0..params{unsafe{*(&u8(descriptor+44+u64(i)))=0x80}}
	if requirements!=0{r:=descriptor+44+u64((params+3)&~3);write32(r,0x80);write32(r+12,1)}
	swift_protocol_relative(pattern,base);swift_protocol_relative(pattern+4,base)
	write32(pattern+8,(kind<<21)|if partial{u32(1)}else{u32(0)})
	swift_protocol_relative(pattern+12,if indirect{cell}else{witness})
	if indirect{write32(pattern+12,read32(pattern+12)|1)}
	unsafe{*(&u64(cell))=witness}
	if partial{swift_protocol_relative(pattern+16,source);write32(pattern+20,u32(prefix/8)|(u32(size/8)<<16))}
	for i in 0..keys{unsafe{*(&u64(arguments+u64(i*8)))=if i%2==0{base}else{u64(0)}}}
	for i in u64(0)..size{unsafe{*(&u8(source+i))=u8(i*19+11)}}
	for i in [u64(1),3,5,7,9]!{assert C.mprotect(voidptr(base+page*i),usize(page),C.PROT_READ)==0}
	return GvInput{base,length,descriptor,pattern,arguments,witness,source,extra,keys,prefix,size,kind}
}
fn gv_check(allocate GvAllocate,input GvInput)u64{
	m:=allocate(input.descriptor,input.arguments,input.pattern,input.extra)
	assert m!=0 && m&7==0 && read64(m)==input.kind
	assert read64(m+8)&0x0000ffffffffffff==input.descriptor && read64(m-8)&0x0000ffffffffffff==input.witness
	for i in 0..input.keys{assert read64(m+16+u64(i*8))==read64(input.arguments+u64(i*8))}
	if input.size!=0{assert C.memcmp(voidptr(m+16+input.prefix),voidptr(input.source),usize(input.size))==0}
	if input.extra!=0{last:=unsafe{*(&u8(m+15+input.extra))};unsafe{*(&u8(m+15+input.extra))=0x6f};assert unsafe{*(&u8(m+15+input.extra))}==0x6f;unsafe{*(&u8(m+15+input.extra))=last}}
	unsafe{*(&u64(m))=input.kind;*(&u64(m+8))=input.descriptor}
	return m
}
fn gv_matrix(allocate GvAllocate){
	for kind in [u32(0x200),0x201]!{for at_end in [false,true]!{for indirect in [false,true]!{
		for keys in [0,1,2,64]!{
			for extra in [u64(keys*8),65536]!{input:=gv_input(kind,keys,false,indirect,extra,at_end);first:=gv_check(allocate,input);second:=gv_check(allocate,input);assert first!=second;assert C.munmap(voidptr(input.base),input.length)==0}
			input:=gv_input(kind,keys,true,indirect,u64(keys*8+16),at_end);gv_check(allocate,input);assert C.munmap(voidptr(input.base),input.length)==0
		}
	}}}
	// Partial patterns can overlap arguments; arguments win after copying.
	input:=gv_input(0x200,1,true,false,24,false);page:=usize(C.getpagesize());assert C.mprotect(voidptr(input.pattern&~u64(page-1)),page,C.PROT_READ|C.PROT_WRITE)==0
	write32(input.pattern+20,0x30000);assert C.mprotect(voidptr(input.source&~u64(page-1)),page,C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u64(input.source+16))=0xabcdef};m:=gv_check(allocate,GvInput{...input,prefix:0,size:0});assert read64(m+16)==read64(input.arguments)&&read64(m+32)==0xabcdef
	assert C.munmap(voidptr(input.base),input.length)==0
}
fn gv_worker(allocate GvAllocate,input GvInput)u64{return gv_check(allocate,input)}
fn gv_bad(input GvInput){
	before:=ios_runtime.swift_generic_value_allocations.len
	for bad in [u64(0),1,~u64(3)]!{
		if _:=swift_generic_value_allocate_checked(bad,input.arguments,input.pattern,input.extra){assert false}
		if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,bad,input.extra){assert false}
	}
	for bad in [u64(0),1,~u64(7)]!{if _:=swift_generic_value_allocate_checked(input.descriptor,bad,input.pattern,input.extra){assert false}}
	if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,65537){assert false}
	if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,0){assert false}
	page:=u64(C.getpagesize());descriptor_page:=input.descriptor&~(page-1);pattern_page:=input.pattern&~(page-1)
	assert C.mprotect(voidptr(descriptor_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	for flags in [u32(0x51),0xd0,0x1d1]!{write32(input.descriptor,flags);if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,input.extra){assert false}}
	write32(input.descriptor,0xd1)
	for header in [u32(0x10001),65,0x410001]!{write32(input.descriptor+40,header);if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,input.extra){assert false}}
	write32(input.descriptor+40,u32(input.keys));unsafe{*(&u8(input.descriptor+44))=0x81};if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,input.extra){assert false};unsafe{*(&u8(input.descriptor+44))=0x80}
	assert C.mprotect(voidptr(pattern_page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	for flags in [u32(0x40200001),0x40000003]!{write32(input.pattern+8,flags);if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,input.extra){assert false}}
	write32(input.pattern+8,0x40000001);write32(input.pattern+20,0x10000);if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,input.extra){assert false}
	write32(input.pattern+20,0x20001);write32(input.pattern+12,0);if _:=swift_generic_value_allocate_checked(input.descriptor,input.arguments,input.pattern,input.extra){assert false}
	assert ios_runtime.swift_generic_value_allocations.len==before
}
fn test_swift_generic_value_metadata(){
	$if macos{
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe{nil}
		allocate:=unsafe{GvAllocate(C.dlsym(core,c'swift_allocateGenericValueMetadata'))};gv_matrix(allocate)
		println('NATIVE-GENERIC-VALUE-METADATA: fresh mutable struct/enum metadata, direct/indirect incomplete VWT, zero to 64 borrowed arguments, 64 KiB extra storage, partial patterns and argument overlap, protected span ends and unused inputs')
	}
	for _ in 0..2{
		objc_start();allocate:=unsafe{GvAllocate(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_allocateGenericValueMetadata') or {panic(err)}))}
		input:=gv_input(0x200,1,true,true,24,true)
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn gv_worker(allocate,input)};values:=workers.wait();unsafe{workers.free()}
		for i,value in values{for j,other in values{if i!=j{assert value!=other}}};unsafe{values.free()}
		gv_matrix(allocate)
		gv_bad(input);assert C.munmap(voidptr(input.base),input.length)==0
		ios_runtime.swift_concurrency_retired=true;if _:=swift_generic_value_allocate_checked(input.base,input.base,input.base,8){assert false};ios_runtime.swift_concurrency_retired=false
		mut mappings:=[]u64{};for base,_ in ios_runtime.swift_generic_value_allocations{mappings<<base};assert mappings.len>100
		objc_stop();assert ios_runtime.swift_generic_value_allocations.len==0
		for base in mappings{$if macos{assert C.mprotect(voidptr(base),usize(C.getpagesize()),C.PROT_READ)==-1}$else{mut resident:=u8(0);assert C.mincore(voidptr(base),usize(C.getpagesize()),unsafe{&resident})==-1}};unsafe{mappings.free()}
		if _:=swift_generic_value_allocate_checked(input.base,input.base,input.base,8){assert false}
	}
	println('IOS-GENERIC-VALUE-METADATA: bounded fresh incomplete metadata, borrowed direct/indirect witnesses and key arguments, mutable extra data and partial-pattern precedence, guarded spans and invalid layouts, eight cold workers, two drained/unmapped lifetimes; generic metadata completion, uniquing and packs remain unsupported')
}
