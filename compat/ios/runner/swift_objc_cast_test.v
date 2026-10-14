// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <objc/runtime.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr,&char,usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.objc_disposeClassPair(voidptr)
fn C.class_createInstance(voidptr,usize) voidptr
fn C.sel_registerName(&char) voidptr
type ObjCCastImp = fn ()
fn C.class_addMethod(voidptr,voidptr,ObjCCastImp,&char) bool
type ObjCCastCall = fn (u64,u64) u64
type ObjCCastProbe = fn (u64,u64,u64,&u64)
type ObjCCastDrop = fn (u64)
type ObjCCastCount = fn (u64,u64) u64
__global objc_cast_native_override_calls = i64(0)
fn objc_cast_native_formal(_owner u64,_selector u64) u64 {objc_cast_native_override_calls++;return u64(C.objc_getClass(c'NSObject'))}
fn objc_cast_native_kind(_owner u64,_selector u64,_target u64) u8 {objc_cast_native_override_calls++;return 1}
fn objc_cast_probe_case(probe ObjCCastProbe,entry u64,owner u64,target u64,result u64) {
	mut output:=[u64(0x1234),0,0,0,0x5678]!
	probe(owner,target,entry,unsafe {&output[1]})
	assert output==[u64(0x1234),result,0x5020,0x5021,0x5678]!
}
fn objc_cast_native(probe ObjCCastProbe,guard u64) {
	$if macos {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);objc:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2);assert core!=unsafe {nil}&&objc!=unsafe {nil}
		entry:=u64(C.dlsym(core,c'swift_dynamicCastObjCClass'));cast:=unsafe {ObjCCastCall(voidptr(entry))}
		drop:=unsafe {ObjCCastDrop(C.dlsym(objc,c'objc_release'))};count:=unsafe {ObjCCastCount(C.dlsym(objc,c'objc_msgSend'))};selector:=u64(C.sel_registerName(c'retainCount'))
		root:=u64(C.objc_getClass(c'NSObject'));base:=u64(C.objc_allocateClassPair(voidptr(root),c'VinixNativeObjCCastBase',0));assert base!=0;C.objc_registerClassPair(voidptr(base))
		leaf:=u64(C.objc_allocateClassPair(voidptr(base),c'VinixNativeObjCCastLeaf',0));assert leaf!=0;C.objc_registerClassPair(voidptr(leaf))
		other:=u64(C.objc_allocateClassPair(voidptr(root),c'VinixNativeObjCCastOther',0));assert other!=0;C.objc_registerClassPair(voidptr(other))
		for cls in [base,leaf,other]! {
			owner:=u64(C.class_createInstance(voidptr(cls),0));assert count(owner,selector)==1
			for _ in 0..128 {for target in [root,base,leaf,other]! {expected:=if target==root||target==cls||(cls==leaf&&target==base) {owner}else{u64(0)};objc_cast_probe_case(probe,entry,owner,target,expected)}}
			assert count(owner,selector)==1;drop(owner)
		}
		for target in [u64(0),1,guard,root,base]! {objc_cast_probe_case(probe,entry,0,target,0)}
		formal:=u64(C.objc_allocateClassPair(voidptr(root),c'VinixNativeObjCCastFormal',0));assert formal!=0
		formal_imp:=unsafe {ObjCCastImp(voidptr(objc_cast_native_formal))}
		assert C.class_addMethod(voidptr(formal),C.sel_registerName(c'class'),formal_imp,c'#16@0:8');C.objc_registerClassPair(voidptr(formal))
		formal_owner:=u64(C.class_createInstance(voidptr(formal),0));objc_cast_native_override_calls=0
		assert cast(formal_owner,formal)==0&&cast(formal_owner,base)==0&&cast(formal_owner,root)==formal_owner
		assert objc_cast_native_override_calls>=3
		println('IOS-OBJC-CAST-NATIVE-FORMAL: formal-class override changes matching, callback count='+objc_cast_native_override_calls.str());assert count(formal_owner,selector)==1;drop(formal_owner)
		kind:=u64(C.objc_allocateClassPair(voidptr(root),c'VinixNativeObjCCastKind',0));assert kind!=0
		kind_imp:=unsafe {ObjCCastImp(voidptr(objc_cast_native_kind))}
		assert C.class_addMethod(voidptr(kind),C.sel_registerName(c'isKindOfClass:'),kind_imp,c'B24@0:8#16');C.objc_registerClassPair(voidptr(kind))
		kind_owner:=u64(C.class_createInstance(voidptr(kind),0));objc_cast_native_override_calls=0
		assert cast(kind_owner,base)==kind_owner;assert objc_cast_native_override_calls>0&&count(kind_owner,selector)==1;drop(kind_owner)
		for cls in [kind,formal,leaf,base,other]! {C.objc_disposeClassPair(voidptr(cls))}
		println('IOS-OBJC-CAST-NATIVE: raw ObjC class argument, matching/ancestor/incompatible casts borrow ownership, nil ignores protected target, x20/x21 and guarded output, default physical ancestry and native isKindOfClass override behavior')
	}
}
fn objc_cast_worker(owner u64,target u64) {
	for _ in 0..1000 {assert swift_dynamic_cast_objc_class(owner,target)==owner}
}
fn objc_cast_reject(owner u64,target u64) {
	if _:=swift_dynamic_cast_objc_class_checked(owner,target) {assert false,'unsupported cast accepted'}
}
fn objc_cast_override(_owner u64,_selector u64,_target u64) u8 {panic('unsupported class override executed')}
struct ObjCCastCleanup {root u64 peer u64 mut: calls int}
fn objc_cast_cleanup(owner u64,_selector &char) {
	mut state:=unsafe {&ObjCCastCleanup(obj_header(owner).tag)}
	objc_cast_reject(owner,state.root)
	worker:=spawn objc_cast_worker(state.peer,state.root);worker.wait();state.calls++
	assert objc_destruct_instance(owner)==owner;C.free(voidptr(owner))
}
fn objc_cast_suite(probe ObjCCastProbe,guard u64) {
	entry:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_dynamicCastObjCClass') or {panic(err)}
	root:=ios_runtime.names['NSObject'];base:=objc_allocate_class(root,c'VinixObjCCastBase',0);objc_register_class(base)
	leaf:=objc_allocate_class(base,c'VinixObjCCastLeaf',0);objc_register_class(leaf)
	other:=objc_allocate_class(root,c'VinixObjCCastOther',0);objc_register_class(other)
	for cls in [base,leaf,other]! {
		owner:=objc_allocate(cls);assert obj_header(owner).refs==1
		for _ in 0..128 {for target in [root,base,leaf,other]! {expected:=if target==root||target==cls||(cls==leaf&&target==base) {owner}else{u64(0)};objc_cast_probe_case(probe,entry,owner,target,expected)}}
		mut workers:=[]thread{};for _ in 0..8 {workers<<spawn objc_cast_worker(owner,root)};workers.wait();assert obj_header(owner).refs==1
		objc_release(owner);objc_cast_reject(owner,root)
	}
	for target in [u64(0),1,guard,root,base]! {objc_cast_probe_case(probe,entry,0,target,0)}
	assert ios_runtime.swift_error_arena==0&&ios_runtime.swift_objc_metadata.len==0
	owner:=objc_allocate(base);assert objc_set_class(owner,leaf)==base
	objc_cast_probe_case(probe,entry,owner,leaf,owner);assert objc_set_class(owner,base)==leaf
	objc_cast_probe_case(probe,entry,owner,leaf,0)
	for target in [u64(0),1,guard,read64(base),swift_objc_metadata(base),cf_error_type_id()]! {objc_cast_reject(owner,target)}
	for invalid in [u64(1),guard,0xdeadbeef,0x8000000000000001,base,read64(base)]! {objc_cast_reject(invalid,root)}
	mut header:=obj_header(owner)
	for flag in 0..4 {header.releasing=flag==0;header.destroying=flag==1;header.destroyed=flag==2;header.refs=if flag==3 {i64(0)}else{i64(1)};objc_cast_reject(owner,root)}
	header.releasing=false;header.destroying=false;header.destroyed=false;header.refs=1
	unsafe {*(&u64(owner))=other};objc_cast_reject(owner,root);unsafe {*(&u64(owner))=base}
	mut base_info:=ios_runtime.classes[base] or {panic('missing fixture base')};parent:=base_info.parent;base_info.parent=base;objc_cast_reject(owner,root);base_info.parent=parent
	assert header.refs==1;objc_release(owner)
	private_error:=objc_allocate(cf_error_type_id());objc_cast_reject(private_error,root);objc_release(private_error)
	for selector in [c'class',c'isKindOfClass:']! {
		cls:=objc_allocate_class(root,if selector==c'class' {c'VinixObjCCastFormal'}else{c'VinixObjCCastKind'},0);objc_register_class(cls)
		objc_replace_method(cls,objc_selector(selector),u64(voidptr(objc_cast_override)),if selector==c'class' {c'#16@0:8'}else{c'B24@0:8#16'})
		object:=objc_allocate(cls);objc_cast_reject(object,root);assert obj_header(object).refs==1;objc_release(object)
	}
	swift_cls:=objc_allocate_class(root,c'VinixObjCCastSwiftPrefix',40);objc_register_class(swift_cls);unsafe {*(&u64(swift_cls+32))=2}
	swift_owner:=objc_allocate(swift_cls);objc_cast_reject(swift_owner,root);owner2:=objc_allocate(root);objc_cast_reject(owner2,swift_cls);objc_release(owner2);objc_release(swift_owner);objc_dispose_class(swift_cls)
	mut constant:=[ios_runtime.names['NSString'],u64(0),0,0]!;address:=u64(unsafe {&constant[0]});ios_runtime.constants[address]=true
	objc_cast_probe_case(probe,entry,address,root,address);objc_cast_probe_case(probe,entry,address,ios_runtime.names['NSString'],address);objc_cast_probe_case(probe,entry,address,base,0);ios_runtime.constants.delete(address)
	cleanup_cls:=objc_allocate_class(root,c'VinixObjCCastCleanup',0);objc_register_class(cleanup_cls);objc_replace_method(cleanup_cls,objc_selector(c'dealloc'),u64(voidptr(objc_cast_cleanup)),c'v16@0:8')
	peer:=objc_allocate(root);mut state:=ObjCCastCleanup{root:root,peer:peer};cleanup_owner:=objc_allocate(cleanup_cls);obj_header(cleanup_owner).tag=i64(unsafe {&state});objc_release(cleanup_owner);assert state.calls==1&&obj_header(peer).refs==1;objc_release(peer)
	ios_runtime.swift_concurrency_retired=true;objc_cast_reject(guard,guard);assert swift_dynamic_cast_objc_class(0,guard)==0;ios_runtime.swift_concurrency_retired=false
	if _:=runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_swift_dynamicCastObjCClass') {assert false}
	if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','__swift_dynamicCastObjCClass') {assert false}
	assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.swift_heap.len==0
}
fn test_swift_objc_cast() {
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe {nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,word in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0303f3,0xaa0203f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9005260,0xf9000a75,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+u64(i*4),word)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+56));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	guard:=code+u64(page);assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0;probe:=unsafe {ObjCCastProbe(voidptr(code))}
	objc_cast_native(probe,guard)
	for _ in 0..2 {objc_start();objc_cast_suite(probe,guard);objc_stop();assert ios_runtime.live==0&&ios_runtime.swift_objc_metadata.len==0}
	assert C.munmap(voidptr(code),page*2)==0
	println('IOS-OBJC-CAST: exact Core-only borrowed raw-class export, native conditional/nil/ancestry ABI and x20/x21, no class metadata factory, eight workers, constants/object_setClass, guarded stale/invalid/private/override/Swift-class rejection, bounded cycles and unlocked deallocation with two drained lifetimes')
}
