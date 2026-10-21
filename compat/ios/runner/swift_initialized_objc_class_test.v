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
type IcProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
struct IcApi { native bool entry u64 code u64 guard u64 }
struct IcState { mut: cls u64 api IcApi initials i64 selves i64 classes i64 order i64 recurse bool }
__global ic_states=[8]IcState{}
__global ic_order=i64(0)
fn ic_symbol(native bool)u64{
	$if macos{if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(core,c'swift_getInitializedObjCClass'));assert entry!=0;return entry}}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_getInitializedObjCClass') or {panic(err)}
}
fn ic_state(cls u64)&IcState{for i in 0..8{if ic_states[i].cls==cls{return unsafe{&ic_states[i]}}};panic('unknown initialized-class fixture')}
fn ic_call(api IcApi,cls u64)u64{
	mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
	unsafe{IcProbe(voidptr(api.code))(cls,api.guard,api.guard,api.guard,api.entry,&words[1],api.guard)}
	assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
	return words[1]
}
fn ic_lookup()u64{C.ios_objc_initialize_lock();defer{C.ios_objc_initialize_unlock()};return ic_symbol(false)}
fn ic_initialize(cls u64,_selector &char){
	mut state:=ic_state(cls);assert C.ios_ref_change(unsafe{&state.initials},1)==0
	state.order=C.ios_ref_change(unsafe{&ic_order},1)+1
	if state.recurse{assert ic_call(state.api,cls)==cls}
}
fn ic_self(cls u64,_selector &char)u64{
	mut state:=ic_state(cls);previous:=C.ios_ref_change(unsafe{&state.selves},1)
	if previous==0&&!state.api.native&&!state.recurse{worker:=spawn ic_lookup();assert worker.wait()==state.api.entry}
	// Never retain, inspect, or substitute this inaccessible result for cls.
	return state.api.guard
}
fn ic_class_override(cls u64,_selector &char)u64{mut state:=ic_state(cls);C.ios_ref_change(unsafe{&state.classes},1);return state.api.guard}
fn ic_create(api IcApi,parent u64,name &char,index int,methods bool,recurse bool)u64{
	mut cls:=u64(0)
	$if macos{if api.native{
		cls=u64(C.objc_allocateClassPair(voidptr(parent),name,0));assert cls!=0
		if methods{meta:=C.object_getClass(voidptr(cls));for pair in [[u64(C.sel_registerName(c'initialize')),u64(voidptr(ic_initialize))]!,[u64(C.sel_registerName(c'self')),u64(voidptr(ic_self))]!,[u64(C.sel_registerName(c'class')),u64(voidptr(ic_class_override))]!]!{assert C.class_addMethod(meta,voidptr(pair[0]),voidptr(pair[1]),if pair[0]==u64(C.sel_registerName(c'initialize')){c'v16@0:8'}else{c'@16@0:8'})}}
		C.objc_registerClassPair(voidptr(cls))
	}}
	if !api.native{
		cls=objc_allocate_class(parent,name,0);assert cls!=0
		if methods{meta:=read64(cls);assert objc_add_method(meta,objc_selector(c'initialize'),u64(voidptr(ic_initialize)),c'v16@0:8');assert objc_add_method(meta,objc_selector(c'self'),u64(voidptr(ic_self)),c'@16@0:8');assert objc_add_method(meta,objc_selector(c'class'),u64(voidptr(ic_class_override)),c'@16@0:8')}
		objc_register_class(cls)
	}
	ic_states[index]=IcState{cls:cls,api:api,recurse:recurse};return cls
}
fn ic_worker(api IcApi,cls u64){for _ in 0..32{assert ic_call(api,cls)==cls}}
fn ic_matrix(api IcApi){
	ic_states=[8]IcState{};ic_order=0
	mut root:=u64(0);$if macos{if api.native{root=u64(C.objc_getClass(c'NSObject'))}}
	if !api.native{root=ios_runtime.names['NSObject']}
	parent:=ic_create(api,root,c'VinixInitializedParent',0,true,false)
	child:=ic_create(api,parent,c'VinixInitializedChild',1,false,false)
	other:=ic_create(api,parent,c'VinixInitializedOverride',2,true,false)
	recurse:=ic_create(api,parent,c'VinixInitializedReentrant',3,true,true)
	cold:=ic_create(api,parent,c'VinixInitializedConcurrent',4,false,false)
	assert ic_order==0
	assert ic_call(api,child)==child&&ic_states[0].initials==1&&ic_states[1].initials==1
	assert ic_states[0].order<ic_states[1].order&&ic_states[0].selves==0&&ic_states[1].selves==1
	for cls in [parent,child,other,recurse]!{for _ in 0..3{assert ic_call(api,cls)==cls}}
	assert ic_states[0].selves==3&&ic_states[1].selves==4&&ic_states[2].selves==3&&ic_states[3].selves==4
	mut workers:=[]thread{};for _ in 0..8{workers<<spawn ic_worker(api,cold)};workers.wait();unsafe{workers.free()}
	for i in 0..5{assert ic_states[i].initials==1&&ic_states[i].classes==0}
	assert ic_states[4].selves==256&&ic_order==5
	for cls in [u64(0),root,parent,child]!{assert ic_call(api,cls)==cls}
	if !api.native{assert ios_runtime.swift_objc_metadata.len==0&&ios_runtime.live==0;for i:=4;i>=0;i--{objc_dispose_class(ic_states[i].cls)}}
}
fn ic_bad(cls u64){if _:=swift_initialized_objc_class_checked(cls){assert false,'unsupported initialized ObjC class accepted'}}
fn ic_invalid(api IcApi){
	for cls in [u64(1),~u64(0),api.guard]!{ic_bad(cls)}
	cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixInitializedInvalid',0);assert cls!=0;ic_bad(cls)
	objc_register_class(cls);ic_bad(read64(cls))
	wrapper:=swift_objc_metadata(cls);ic_bad(wrapper)
	data:=read64(cls+32);unsafe{*(&u64(cls+32))=data|2};ic_bad(cls);unsafe{*(&u64(cls+32))=data}
	mut info:=ios_runtime.classes[cls] or {panic('class')};parent:=info.parent
	info.parent=cls;ic_bad(cls);info.parent=parent
	ios_runtime.swift_concurrency_retired=true;ic_bad(api.guard);assert ic_call(api,0)==0;ios_runtime.swift_concurrency_retired=false
	// Published Swift wrappers keep their class alive until runtime teardown.
}
fn ic_borrowed(api IcApi){
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*3),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	cls:=base+page*2-40;parent:=ios_runtime.names['NSObject'];isa:=read64(parent);unsafe{*(&u64(cls))=isa;*(&u64(cls+8))=parent}
	ios_runtime.classes[cls]=&ObjClass{name:'BorrowedInitializedFixture',parent:parent,size:8}
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
	for _ in 0..8{assert ic_call(api,cls)==cls};assert read64(cls)==read64(parent)&&read64(cls+8)==parent
	objc_stop();assert read64(cls)==isa // class storage stays borrowed
	assert C.munmap(voidptr(base),usize(page*3))==0
}
fn test_swift_initialized_objc_class(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&guard!=~u64(0)
	defer{assert C.munmap(voidptr(code),page)==0;assert C.munmap(voidptr(guard),page)==0}
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{api:=IcApi{true,ic_symbol(true),code,guard};ic_matrix(api);println('NATIVE-INITIALIZED-OBJC-CLASS: scalar C class-pointer ABI, superclass-first once-only inherited/overridden +initialize, same-thread recursive initialization, +self every call with ignored inaccessible result, +class never sent, nil messaging, eight concurrent cold readers and preserved x20/x21/x22')}
	nil_result:=swift_initialized_objc_class_checked(0) or {panic(err)};assert nil_result==0
	for _ in 0..2{
		objc_start();api:=IcApi{false,ic_symbol(false),code,guard};ic_matrix(api);ic_invalid(api)
		for name in ['NSObject','NSString','NSUserDefaults','NSFileManager','NSProcessInfo']!{assert ic_call(api,ios_runtime.names[name])==ios_runtime.names[name]}
		ic_borrowed(api);ic_bad(guard);assert ic_call(api,0)==0
	}
	println('IOS-INITIALIZED-OBJC-CLASS: bounded registered pure ObjC classes, native init/self dispatch and pointer identity, inherited/overridden callbacks, recursive initialization and concurrent once-only initialization, +self callback runtime reentry outside registry lock, unknown/metaclass/unregistered/Swift/cyclic/retired rejection, borrowed readonly class boundary, no wrapper/ARC and two drained lifetimes')
}
