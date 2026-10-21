// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.CFStringCreateMutable(voidptr,i64)voidptr
fn C.CFRetain(voidptr)voidptr
fn C.CFGetRetainCount(voidptr)i64
fn C.objc_getClass(&char)voidptr
fn C.objc_allocateClassPair(voidptr,&char,usize)voidptr
fn C.objc_registerClassPair(voidptr)
fn C.objc_disposeClassPair(voidptr)
fn C.class_addMethod(voidptr,voidptr,voidptr,&char)bool
fn C.class_createInstance(voidptr,usize)voidptr
fn C.sel_registerName(&char)voidptr
fn C.object_dispose(voidptr)voidptr
type PcProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
type PcAllocate=fn(u64,u64,u64)u64
type PcRetain=fn(u64)u64
type PcRelease=fn(u64)
struct PcApi { native bool entry u64 code u64 guard u64 }
__global pc_callback_count=i64(0)
fn pc_symbol(native bool,name string)u64{
	$if macos{if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);result:=u64(C.dlsym(core,name[1..].str));assert result!=0,name;return result}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn pc_emit(code u64){
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,
		u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,
		0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn pc_call(api PcApi,owner u64,metadata u64,size u64,mask u64){
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{PcProbe(voidptr(api.code))(owner,metadata,size,mask,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
}
fn pc_bad(owner u64,metadata u64,size u64,mask u64){if _:=swift_partial_class_checked(owner,metadata,size,mask){assert false,'unsupported partial class accepted'}}
fn pc_worker(api PcApi,metadata u64){
	allocate:=unsafe{PcAllocate(voidptr(pc_symbol(api.native,'_swift_allocObject')))}
	for _ in 0..64{owner:=allocate(metadata,32,15);pc_call(api,owner,metadata,32,15)}
}
fn pc_native_heap(api PcApi){
	allocate:=unsafe{PcAllocate(voidptr(pc_symbol(api.native,'_swift_allocObject')))}
	retain_owner:=unsafe{PcRetain(voidptr(pc_symbol(api.native,'_swift_retain')))}
	release_owner:=unsafe{PcRelease(voidptr(pc_symbol(api.native,'_swift_release')))}
	page:=u64(C.getpagesize());length:=usize(page*3)
	base:=u64(C.mmap(unsafe{nil},length,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	defer{assert C.munmap(voidptr(base),length)==0}
	for at_end in [false,true]!{
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		m:=base+page+if at_end{page-48}else{u64(16)}
		C.memset(voidptr(m-16),0,64)
		unsafe{*(&u64(m-16))=api.guard;*(&u64(m+8))=api.guard;*(&u64(m+32))=2};write32(m+40,2)
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
		// The superclass and destructor are inaccessible. At the page end,
		// instance-size, descriptor and ivar-destroyer fields are inaccessible too.
		for size in [u64(16),32,48,4096]!{for mask in [u64(7),15,31,255,4095]!{
			owner:=allocate(m,size,mask);assert read64(owner+8)==3
			if size>16{C.memset(voidptr(owner+16),0x6b,usize(size-16))}
			pc_call(api,owner,m,size,mask)
			if !api.native{assert owner !in ios_runtime.swift_heap;pc_bad(owner,m,size,mask)}
		}}
		if !api.native{
			owner:=allocate(m,32,15);before:=ios_runtime.swift_heap.len
			for boundary in [u64(0),1,api.guard,m+8]!{pc_bad(owner,boundary,32,15)}
			for size in [u64(0),12,31,48,~u64(0)]!{pc_bad(owner,m,size,15)}
			for mask in [u64(0),5,7,31,~u64(0)]!{pc_bad(owner,m,32,mask)}
			retain_owner(owner);pc_bad(owner,m,32,15);release_owner(owner)
			for bits in [u64(0),0x100000003,0x8000000000000003,0x13]!{unsafe{*(&u64(owner+8))=bits};pc_bad(owner,m,32,15)}
			unsafe{*(&u64(owner+8))=3;*(&u64(owner))=api.guard};pc_bad(owner,m,32,15);unsafe{*(&u64(owner))=m}
			assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
			for kind in [u64(0x200),0x400,0x500]!{unsafe{*(&u64(m))=kind};pc_bad(owner,m,32,15)};unsafe{*(&u64(m))=0}
			write32(m+40,0);pc_bad(owner,m,32,15);write32(m+40,2);write32(m+44,8);pc_bad(owner,m,32,15);write32(m+44,0)
			assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
			assert ios_runtime.swift_heap.len==before&&read64(owner)==m&&read64(owner+8)==3
			pc_call(api,owner,m,32,15)
		}
		mut workers:=[]thread{};for _ in 0..8{workers<<spawn pc_worker(api,m)};workers.wait();unsafe{workers.free()}
	}
}
fn pc_lookup_worker()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_deallocPartialClassInstance') or {panic(err)}}
fn pc_objc_dealloc(owner u64,_selector &char){
	assert obj_header(owner).refs==0&&obj_header(owner).releasing
	worker:=spawn pc_lookup_worker();assert worker.wait()!=0 // must acquire the runtime lock
	C.ios_ref_change(unsafe{&pc_callback_count},1)
}
fn pc_native_dealloc(owner u64,_selector &char){
	C.ios_ref_change(unsafe{&pc_callback_count},1)
	$if macos{C.object_dispose(voidptr(owner))}
}
fn pc_native_objc(api PcApi){
	$if macos{
		owner:=C.CFStringCreateMutable(unsafe{nil},0);assert owner!=unsafe{nil}
		before:=C.CFGetRetainCount(owner);C.CFRetain(owner)
		pc_call(api,u64(owner),api.guard,12,7);assert C.CFGetRetainCount(owner)==before
		pc_call(api,u64(owner),api.guard,~u64(0),5)
		cls:=C.objc_allocateClassPair(C.objc_getClass(c'NSObject'),c'VinixPartialClassNative',0);assert cls!=unsafe{nil}
		callback:=u64(unsafe{voidptr(pc_native_dealloc)})
		assert C.class_addMethod(cls,C.sel_registerName(c'dealloc'),voidptr(callback),c'v16@0:8');C.objc_registerClassPair(cls)
		count:=pc_callback_count;value:=u64(C.class_createInstance(cls,0));assert value!=0
		pc_call(api,value,api.guard,0,~u64(0));assert pc_callback_count==count+1
		C.objc_disposeClassPair(cls)
	}
}
fn pc_objc(api PcApi){
	cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixPartialClass',0);assert cls!=0;objc_register_class(cls)
	objc_replace_method(cls,objc_selector(c'dealloc'),u64(unsafe{voidptr(pc_objc_dealloc)}),c'v16@0:8')
	for ignored in [[u64(12),7]!,[u64(0),~u64(0)]!,[~u64(0),5]!]!{
		owner:=objc_allocate(cls);count:=pc_callback_count;mut weak:=u64(0);objc_store_weak(unsafe{&weak},owner)
		child:=objc_allocate(ios_runtime.names['NSObject']);objc_set_associated(owner,api.guard,child,1);assert obj_header(child).refs==2
		objc_retain(owner);pc_call(api,owner,api.guard,ignored[0],ignored[1]);assert obj_header(owner).refs==1&&weak==owner&&pc_callback_count==count
		pc_call(api,owner,api.guard,ignored[0],ignored[1]);assert weak==0&&owner !in ios_runtime.objects&&pc_callback_count==count+1&&obj_header(child).refs==1
		objc_destroy_weak(unsafe{&weak});objc_release(child)
	}
	// Immutable registered placeholders contain only their isa word.
	page:=u64(C.getpagesize());span:=u64(C.mmap(unsafe{nil},usize(page*3),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
	for at_end in [false,true]!{
		assert C.mprotect(voidptr(span+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		owner:=span+page+if at_end{page-8}else{u64(0)};unsafe{*(&u64(owner))=cls}
		assert C.mprotect(voidptr(span+page),usize(page),C.PROT_READ)==0
		ios_runtime.constants[owner]=true;pc_call(api,owner,api.guard,12,7);assert read64(owner)==cls;ios_runtime.constants.delete(owner)
	}
	assert C.munmap(voidptr(span),usize(page*3))==0
	objc_dispose_class(cls)
	// Swift/ObjC prefixes need superclass and ivar cleanup, never plain release.
	swift_cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixPartialClassSwiftObjC',40);objc_register_class(swift_cls)
	unsafe{*(&u64(swift_cls+32))=2};owner:=objc_allocate(swift_cls);pc_bad(owner,swift_cls,12,7)
	assert obj_header(owner).refs==1;unsafe{*(&u64(swift_cls+32))=0};objc_release(owner);objc_dispose_class(swift_cls)
}
fn test_swift_partial_class(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
	guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	pc_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{api:=PcApi{true,pc_symbol(true,'_swift_deallocPartialClassInstance'),code,guard};pc_call(api,0,guard,~u64(0),5);pc_native_heap(api);pc_native_objc(api);println('NATIVE-PARTIAL-CLASS: four-argument C void ABI, nil and pure ObjC ignored inputs, shared CF ownership and custom dealloc, unique native class failure without destructor/ivar/superclass access, 40 aligned layouts, guarded metadata ends and x20/x21/x22, eight workers')}
	for _ in 0..2{
		objc_start();api:=PcApi{false,pc_symbol(false,'_swift_deallocPartialClassInstance'),code,guard};pc_call(api,0,guard,~u64(0),5)
		pc_native_heap(api);pc_objc(api)
		for owner in [u64(1),guard,~u64(7),0x8000000000000000]!{pc_bad(owner,guard,12,7)}
		ios_runtime.swift_concurrency_retired=true;pc_bad(guard,guard,12,7);pc_call(api,0,guard,0,0);ios_runtime.swift_concurrency_retired=false
		assert ios_runtime.swift_heap.len==0&&ios_runtime.live==0;objc_stop();pc_bad(guard,guard,12,7);pc_call(api,0,guard,0,0)
	}
	println('IOS-PARTIAL-CLASS: bounded unique native class boundary and exact allocation reclamation, ordinary ObjC release with ignored layout/type and shared/immutable storage, weak and associated cleanup, unlocked reentrant dealloc, malformed ownership/layout/hierarchy rejection before writes, eight workers and two drained lifetimes')
}
