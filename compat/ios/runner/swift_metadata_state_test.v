// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type MsProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
type MsAccess=fn(u64,u64)SwiftAssociatedMetadata
type MsPair=fn(u64,u64,u64)SwiftAssociatedMetadata
type MsDictionary=fn(u64,u64,u64,u64)SwiftAssociatedMetadata
struct MsApi { native bool entry u64 code u64 guard u64 }
fn ms_symbol(native bool,name string)u64{
	$if macos {if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);result:=u64(C.dlsym(core,name[1..].str));assert result!=0,name;return result}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn ms_emit(code u64){
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,
		u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,
		0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn ms_case(api MsApi,request u64,metadata u64){
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{MsProbe(voidptr(api.code))(request,metadata,api.guard,api.guard,api.entry,&words[1],api.guard)}
	assert words==[u64(0xcafe),metadata,0,api.guard,0x5121,0x5222,0xbeef]!
}
fn ms_requests(api MsApi,metadata u64){
	for request in [u64(0),1,0x3f,0xff,0x100,0x101,0x13f,0x1ff]!{ms_case(api,request,metadata)}
}
fn ms_real(api MsApi){
	for name in ['_$sSiN','_$sSSN','_$sSbN','_$ss12StaticStringVN','_$ss11_MergeErrorON','_$ss6UInt64VN']!{
		ms_requests(api,ms_symbol(api.native,name))
	}
	for name in ['_$sypN','_$sytN']!{ms_requests(api,ms_symbol(api.native,name)+8)}
	integer:=ms_symbol(api.native,'_$sSiN');text:=ms_symbol(api.native,'_$sSSN')
	array_access:=unsafe{MsAccess(voidptr(ms_symbol(api.native,'_$sSaMa')))}
	optional:=unsafe{MsAccess(voidptr(ms_symbol(api.native,'_$sSqMa')))}
	for metadata in [array_access(0,text).metadata,array_access(0,array_access(0,integer).metadata).metadata,optional(0,text).metadata]!{ms_requests(api,metadata)}
	hashable:=ms_symbol(api.native,'_$sSSSHsWP')
	dictionary:=unsafe{MsDictionary(voidptr(ms_symbol(api.native,'_$sSDMa')))}
	set:=unsafe{MsPair(voidptr(ms_symbol(api.native,'_$sShMa')))}
	ms_requests(api,dictionary(0,text,integer,hashable).metadata);ms_requests(api,set(0,text,hashable).metadata)
	for name in ['_$ss22KeyedDecodingContainerVMa','_$ss22KeyedEncodingContainerVMa']!{
		keyed_access:=unsafe{MsPair(voidptr(ms_symbol(api.native,name)))}
		// The borrowed CodingKey witness identifies the specialization only.
		ms_requests(api,keyed_access(0,integer,api.guard+8).metadata)
	}
	if !api.native{
		swift_collection_table_checked(array_access(0,integer).metadata) or {panic(err)}
		for _,base in ios_runtime.swift_array_sequence_metadata{ms_requests(api,base+8)}
		for _,base in ios_runtime.swift_collection_metadata{ms_requests(api,base+8);ms_requests(api,base+168)}
		for base,_ in ios_runtime.swift_set_metadata{ms_requests(api,base+168)}
	}
}
// At either end of a readable page, nothing before or after the minimal
// header is accessible. In particular there is no value witness table.
fn ms_guarded(api MsApi){
	page:=u64(C.getpagesize());length:=usize(page*5)
	base:=u64(C.mmap(unsafe{nil},length,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	defer{assert C.munmap(voidptr(base),length)==0}
	for at_end in [false,true]!{
		for kind in [u64(0x302),0x303,0x304,0x305,0x306,0x301,0x200,0x201,0x202]!{
			bytes:=if kind in [u64(0x302),0x303,0x304,0x305,0x306]!{u64(8)}else{u64(16)}
			m:=base+page+if at_end{page-bytes}else{u64(0)}
			assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
			unsafe{*(&u64(m))=kind}
			if bytes==16{unsafe{*(&u64(m+8))=if kind==0x301{u64(0)}else{
				// Native descriptors carry pointer authentication. Reuse the
				// real descriptor word without stripping or manufacturing it.
				read64(ms_symbol(api.native,if kind==0x200{'_$sSiN'}else{'_$ss11_MergeErrorON'})+8)
			}}}
			assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
			ms_requests(api,m)
		}
	}
	if api.native{return}
	// Only the flags word of a borrowed descriptor is read. All relative
	// pointers, initialization code, cache words and generic arguments are guarded.
	d:=base+page*4-4;m:=base+page*2-16
	assert C.mprotect(voidptr(base+page*3),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	unsafe{*(&u64(m+8))=d}
	for kind in [u64(0x200),0x201,0x202]!{
		unsafe{*(&u64(m))=kind};flags:=if kind==0x200{u32(17)}else{u32(18)}
		for extra in [u32(0),0x40,0x10c00000]!{write32(d,flags|extra);ms_requests(api,m)}
		for extra in [u32(0x80),0x100,0x10000,0x20000,0x30000]!{write32(d,flags|extra);ms_bad(0,m)}
		write32(d,if kind==0x200{u32(18)}else{u32(17)});ms_bad(0,m)
	}
	for descriptor in [u64(0),1,~u64(3)]!{unsafe{*(&u64(m))=0x200;*(&u64(m+8))=descriptor};ms_bad(0,m)}
	for kind in [u64(0),0x203,0x300,0x400,0x500,~u64(0)]!{unsafe{*(&u64(m))=kind};ms_bad(0,m)}
	unsafe{*(&u64(m))=0x301;*(&u64(m+8))=1};ms_bad(0,m)
}
fn ms_bad(request u64,metadata u64){if _:=swift_metadata_state_checked(request,metadata){assert false,'unsupported metadata accepted'}}
fn ms_invalid(api MsApi){
	for request in [u64(2),0x3e,0x40,0xfe,0x102,0x200,~u64(0)]!{ms_bad(request,api.guard)}
	for metadata in [u64(0),1,~u64(7)]!{ms_bad(0,metadata)}
	// A usable VWT on raw generic allocation still does not create a cache
	// entry or establish transitive completion. Check the identity before reads.
	page:=u64(C.getpagesize());source:=u64(C.mmap(unsafe{nil},usize(page),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert source!=~u64(0)
	defer{assert C.munmap(voidptr(source),usize(page))==0}
	d:=source;p:=source+64;write32(d,0xd1);write32(p+8,0x40000000)
	integer:=swift_integer_metadata();w:=read64(integer-8)
	// An indirectable relative pointer must stay within signed 32-bit range.
	swift_protocol_relative(p+12,source+96);write32(p+12,read32(p+12)|1);unsafe{*(&u64(source+96))=w}
	m:=swift_generic_value_allocate_checked(d,api.guard,p,0) or {panic(err)}
	assert read64(m-8)==w;ms_bad(0,m)
	// Even altering the header to an always-complete kind cannot promote it.
	unsafe{*(&u64(m))=0x302};ms_bad(0,m)
	assert C.mprotect(voidptr(m-8),usize(page),C.PROT_NONE)==0;ms_bad(0,m)
	assert C.mprotect(voidptr(m-8),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	ios_runtime.swift_concurrency_retired=true;ms_bad(0,api.guard);ios_runtime.swift_concurrency_retired=false
	ios_runtime.swift_generic_value_retired=true;ms_bad(0,api.guard);ios_runtime.swift_generic_value_retired=false
}
fn ms_worker(api MsApi,metadata u64){for _ in 0..64{ms_requests(api,metadata)}}
fn test_swift_metadata_state(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	ms_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{api:=MsApi{true,ms_symbol(true,'_swift_checkMetadataState'),code,guard};ms_real(api);ms_guarded(api);println('NATIVE-METADATA-STATE: eight request forms, exact two-word metadata/Complete result, canonical and generic types, minimal read-only guarded headers without VWT or payload reads, unchanged x20/x21/x22 and guarded indirect result')}
	for _ in 0..2{
		objc_start();api:=MsApi{false,ms_symbol(false,'_swift_checkMetadataState'),code,guard}
		ms_real(api);ms_guarded(api);ms_invalid(api)
		metadata:=swift_array_access(0,swift_string_metadata()).metadata;mut workers:=[]thread{}
		for _ in 0..8{workers<<spawn ms_worker(api,metadata)};workers.wait();unsafe{workers.free()}
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0
		objc_stop();assert ios_runtime.live==0&&ios_runtime.swift_generic_value_allocations.len==0&&ios_runtime.swift_array_arena==0&&ios_runtime.swift_optional_arena==0&&ios_runtime.swift_dictionary_metadata_arena==0&&ios_runtime.swift_set_arena==0&&ios_runtime.swift_keyed_container_arena==0
		ms_bad(0,guard)
	}
	println('IOS-METADATA-STATE: bounded always-complete types and exact complete runtime specializations, eight requests and two-word Complete responses, guarded borrowed headers and descriptor flags without VWT inference, deferred/generic/raw allocations rejected before callbacks or cache reads, eight workers and two drained lifetimes')
}
