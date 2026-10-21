// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <objc/runtime.h>
}
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.objc_getClass(&char)voidptr
fn C.objc_allocateClassPair(voidptr,&char,usize)voidptr
fn C.objc_registerClassPair(voidptr)
fn C.object_getClass(voidptr)voidptr
fn C.sel_registerName(&char)voidptr
fn C.class_addMethod(voidptr,voidptr,voidptr,&char)bool
type CmGet=fn(u64)u64
type CmProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
type CmAllocate=fn(i64,u64)SwiftArrayAllocation
type CmRelease=fn(u64)
struct CmApi { native bool entry u64 metadata u64 code u64 guard u64 }
fn cm_forbidden(_cls u64,_sel &char)u64{panic('metadata conversion dispatched an Objective-C method')}
fn cm_call(api CmApi,metadata u64)u64{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{CmProbe(voidptr(api.code))(metadata,api.guard,api.guard,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
	return words[1]
}
fn cm_symbols(native bool,code u64,guard u64)CmApi{
	$if macos{if native{
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe{nil}
		entry:=u64(C.dlsym(core,c'swift_getObjCClassFromMetadata'));metadata:=u64(C.dlsym(core,c'swift_getObjCClassMetadata'));assert entry!=0&&metadata!=0
		return CmApi{true,entry,metadata,code,guard}
	}}
	entry:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getObjCClassFromMetadata') or {panic(err)}
	metadata:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getObjCClassMetadata') or {panic(err)}
	return CmApi{false,entry,metadata,code,guard}
}
fn cm_worker(api CmApi,metadata u64,cls u64){for _ in 0..128{assert cm_call(api,metadata)==cls}}
fn cm_readers(api CmApi,metadata u64,cls u64){mut workers:=[]thread{};for _ in 0..8{workers<<spawn cm_worker(api,metadata,cls)};workers.wait();unsafe{workers.free()}}
fn cm_bad(metadata u64){if _:=swift_objc_class_from_metadata_checked(metadata){assert false,'unsupported metadata accepted'}}
fn cm_suite(api CmApi){
	mut parent:=u64(0);mut cls:=u64(0)
	$if macos{if api.native{
		parent=u64(C.objc_getClass(c'NSObject'));cls=u64(C.objc_allocateClassPair(voidptr(parent),c'VinixClassFromMetadataCold',0));assert cls!=0
		meta:=C.object_getClass(voidptr(cls));imp:=u64(voidptr(cm_forbidden))
		for name in [c'initialize',c'self',c'class']!{assert C.class_addMethod(meta,C.sel_registerName(name),voidptr(imp),c'@16@0:8')}
		C.objc_registerClassPair(voidptr(cls))
	}}
	if !api.native{
		parent=ios_runtime.names['NSObject'];cls=objc_allocate_class(parent,c'VinixClassFromMetadataCold',0);assert cls!=0
		for name in [c'initialize',c'self',c'class']!{assert objc_add_method(read64(cls),objc_selector(name),u64(voidptr(cm_forbidden)),c'@16@0:8')};objc_register_class(cls)
	}
	get_metadata:=unsafe{CmGet(voidptr(api.metadata))};wrapper:=get_metadata(cls)
	assert wrapper!=cls&&read64(wrapper)==0x305&&read64(wrapper+8)==cls
	for candidate in [cls,parent]!{metadata:=get_metadata(candidate);assert cm_call(api,metadata)==candidate&&get_metadata(candidate)==metadata}
	cm_readers(api,wrapper,cls);assert cm_call(api,0)==0
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*3),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	// Exact wrapper spans at both page edges: neither a VWT before the
	// address point nor a trailing class descriptor is required.
	for metadata in [base+page,base+page*2-16]!{unsafe{*(&u64(metadata))=0x305;*(&u64(metadata+8))=cls}}
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
	for metadata in [base+page,base+page*2-16]!{cm_readers(api,metadata,cls)}
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	// Swift's class kind may be zero or a non-enumerated isa. The conversion
	// reads only the type-metadata bit in the 40-byte prefix, even for an
	// artificial class; all other prefix pointers are deliberately inaccessible.
	metadata:=base+page*2-40
	for kind in [u64(0),api.guard]!{
		for offset in [u64(0),8,16,24]!{unsafe{*(&u64(metadata+offset))=api.guard}}
		unsafe{*(&u64(metadata))=kind;*(&u64(metadata+32))=2}
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
		cm_readers(api,metadata,metadata)
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	}
	if !api.native{
		assert !ios_runtime.classes[cls].initialized&&ios_runtime.live==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_objc_metadata.len==2
		for bad in [u64(1),~u64(0),~u64(7),metadata+1]!{cm_bad(bad)}
		// Reject each nonclass kind with only its eight-byte header readable.
		header:=base+page*2-8
		for kind in [u64(1),0x200,0x201,0x202,0x203,0x300,0x301,0x302,0x303,0x304,0x306,0x400,0x500,0x501,0x7ff]!{unsafe{*(&u64(header))=kind};cm_bad(header)}
		unsafe{*(&u64(metadata))=0;*(&u64(metadata+32))=0};cm_bad(metadata);cm_bad(parent);cm_bad(read64(cls))
		unregistered:=objc_allocate_class(parent,c'VinixClassFromMetadataUnregistered',0);assert unregistered!=0
		for payload in [u64(0),1,api.guard,read64(cls),unregistered]!{unsafe{*(&u64(metadata))=0x305;*(&u64(metadata+8))=payload};cm_bad(metadata)}
		objc_dispose_class(unregistered)
		ios_runtime.swift_concurrency_retired=true;cm_bad(api.guard);assert cm_call(api,0)==0;ios_runtime.swift_concurrency_retired=false
		// Keep a caller-owned wrapper/class prefix mapped across runtime stop.
		unsafe{*(&u64(base+page))=0x305;*(&u64(base+page+8))=cls;*(&u64(metadata))=api.guard;*(&u64(metadata+32))=2}
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
		objc_stop();assert read64(base+page)==0x305&&read64(base+page+8)==cls&&read64(metadata+32)==2
		cm_bad(api.guard);assert cm_call(api,0)==0
	}
	assert C.munmap(voidptr(base),usize(page*3))==0
}
fn cm_native_swift(api CmApi){
	$if macos{
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		allocate:=unsafe{CmAllocate(C.dlsym(core,c'$ss27_allocateUninitializedArrayySayxG_BptBwlF'))};release:=unsafe{CmRelease(C.dlsym(core,c'swift_release'))}
		array:=allocate(1,u64(C.dlsym(core,c'$sSiN')));assert array.owner!=0;unsafe{*(&u64(array.bytes))=0}
		metadata:=read64(array.owner)&0x0000ffffffffffff;assert read64(metadata+32)&2!=0
		cm_readers(api,metadata,metadata)
		// The same genuine native Swift class is borrowed by the compatibility
		// conversion without needing registration or an instance allocation.
		objc_start();cm_readers(cm_symbols(false,api.code,api.guard),metadata,metadata);assert ios_runtime.swift_objc_metadata.len==0&&ios_runtime.live==0;objc_stop()
		release(array.owner)
	}
}
fn test_swift_objc_class_from_metadata(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{api:=cm_symbols(true,code,guard);cm_suite(api);cm_native_swift(api);println('NATIVE-OBJC-CLASS-FROM-METADATA: scalar C conversion, canonical and borrowed exact 16-byte wrappers, genuine Swift class metadata, zero/isa class kinds and exact 40-byte artificial class prefix, no initialization/self/class messaging, nil and eight concurrent readers preserving x20/x21/x22 with inaccessible x8')}
	assert (swift_objc_class_from_metadata_checked(0) or {panic(err)})==0
	for _ in 0..2{objc_start();cm_suite(cm_symbols(false,code,guard))}
	println('IOS-OBJC-CLASS-FROM-METADATA: native wrapper and Swift class identity without initialization/ARC/allocation, guarded borrowed readonly spans, no VWT/descriptor/ancestry reads, invalid kind/class/metaclass/unregistered/retired rejection, eight readers and two drained lifetimes')
}
