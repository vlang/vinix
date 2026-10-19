// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.dlclose(voidptr)i32
$if macos {
	#include <objc/runtime.h>
	fn C.objc_getClass(&char)voidptr
	fn C.class_createInstance(voidptr,usize)voidptr
	fn C.objc_allocateClassPair(voidptr,&char,usize)voidptr
	fn C.objc_registerClassPair(voidptr)
	fn C.objc_disposeClassPair(voidptr)
}
type EHTCatch = fn (u64,u64,&u64,u32) bool
type EHTCatch3 = fn (u64,u64,&u64) bool
type EHTDrop = fn (u64)
type EHTFlag = fn (u64) bool
struct EHTApi { native bool foundation u64 core u64 objc u64 }

fn eht_resolve(api EHTApi, core bool) u64 {
	if api.native { return u64(C.dlsym(unsafe{voidptr(if core{api.core}else{api.foundation})},c'OBJC_EHTYPE_$_NSException')) }
	return runtime_symbol(if core{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/Foundation.framework/Foundation'},'_OBJC_EHTYPE_$_NSException') or {panic(err)}
}
fn eht_class(api EHTApi, name &char)u64 {
	$if macos {if api.native{return u64(C.objc_getClass(name))}}
	return ios_runtime.names[ctext(u64(name))]
}
fn eht_new(api EHTApi, cls u64)u64 {
	$if macos {if api.native{return u64(C.class_createInstance(unsafe{voidptr(cls)},0))}}
	return objc_new(cls)
}
fn eht_drop(api EHTApi, object u64){
	if api.native{unsafe{EHTDrop(C.dlsym(voidptr(api.objc),c'objc_release'))(object)};return}
	objc_release(object)
}
fn eht_subclass(api EHTApi, parent u64, name &char)u64{
	$if macos {if api.native{cls:=C.objc_allocateClassPair(unsafe{voidptr(parent)},name,0);assert cls!=unsafe{nil};C.objc_registerClassPair(cls);return u64(cls)}}
	cls:=objc_allocate_class(parent,name,0);assert cls!=0;objc_register_class(cls);return cls
}
fn eht_dispose(api EHTApi, cls u64){
	$if macos {if api.native{C.objc_disposeClassPair(unsafe{voidptr(cls)});return}}
	objc_dispose_class(cls)
}
fn eht_reader(api EHTApi, offset int)u64{
	mut record:=u64(0)
	for i in 0 .. 128{
		got:=eht_resolve(api,(i+offset)%2==0);assert got!=0&&got%8==0
		if record==0{record=got}else{assert record==got}
		assert ctext(read64(got+8))=='NSException'&&read64(got+16)==eht_class(api,c'NSException')
		vptr:=read64(got);id_type:=read64(vptr-8)
		assert read64(vptr-16)==0&&read64(id_type)==vptr&&ctext(read64(id_type+8))=='id'&&read64(id_type+16)==0
	}
	return record
}
fn eht_shared(api EHTApi)u64{
	mut workers:=[]thread u64{}
	for i in 0 .. 8{workers<<spawn eht_reader(api,i)}
	mut record:=u64(0)
	for i,worker in workers{got:=worker.wait();if i==0{record=got}else{assert got==record}}
	unsafe{workers.free()}
	vptr:=read64(record);id_type:=read64(vptr-8);root:=eht_class(api,c'NSException');other:=eht_class(api,c'NSObject')
	if !api.native{
		assert record==ios_runtime.ns_exception_type_arena&&vptr==record+80&&id_type==record+32
		assert read64(record+8)==record+192&&read64(id_type+8)==record+208
		assert record !in ios_runtime.constants&&id_type !in ios_runtime.constants&&ios_runtime.framework_objects.len==0
		assert '_OBJC_EHTYPE_$_NSException' !in ios_runtime.framework_data&&ios_runtime.live==0&&ios_runtime.objects.len==0
		assert objc_class_parent(root)==other
		for i in [2,3,5,6]!{assert !unsafe{EHTFlag(voidptr(read64(vptr+u64(i*8))))(record)}}
	}
	child:=eht_subclass(api,root,c'VinixEHExceptionChild');unrelated:=eht_subclass(api,other,c'VinixEHUnrelatedChild')
	catch:=unsafe{EHTCatch(voidptr(read64(vptr+32)))};catch3:=unsafe{EHTCatch3(voidptr(read64(vptr+32)))}
	for i,cls in [root,child,other,unrelated]!{
		object:=eht_new(api,cls);assert object!=0
		info:=[vptr,u64(c'probe'),cls]!;foreign:=[u64(0),u64(c'NSException'),root]!;weak:=[vptr,u64(c'missing'),u64(0)]!
		payload:=[object,u64(0)]!;before:=if api.native{i64(0)}else{ios_runtime.live}
		for _ in 0 .. 128{
			mut slot:=u64(unsafe{&payload[0]})
			assert catch(record,u64(unsafe{&info[0]}),unsafe{&slot},0xffffffff)==(i<2)&&slot==object
			slot=u64(unsafe{&payload[0]});assert catch3(record,u64(unsafe{&info[0]}),unsafe{&slot})==(i<2)&&slot==object
			slot=u64(unsafe{&payload[0]});assert !catch(record,u64(unsafe{&foreign[0]}),unsafe{&slot},0)&&slot==u64(unsafe{&payload[0]})
			slot=u64(unsafe{&payload[0]});assert catch(id_type,u64(unsafe{&info[0]}),unsafe{&slot},0)&&slot==object
			slot=u64(unsafe{&payload[0]});assert !catch(u64(unsafe{&weak[0]}),u64(unsafe{&info[0]}),unsafe{&slot},0)&&slot==object
		}
		if !api.native{assert ios_runtime.live==before&&ios_runtime.objects.len==1}
		eht_drop(api,object)
	}
	nil_info:=[vptr,u64(c'nil'),u64(0)]!;nil_payload:=[u64(0)]!;mut nil_slot:=u64(unsafe{&nil_payload[0]})
	assert catch(id_type,u64(unsafe{&nil_info[0]}),unsafe{&nil_slot},0)&&nil_slot==0
	nil_slot=u64(unsafe{&nil_payload[0]});assert !catch(record,u64(unsafe{&nil_info[0]}),unsafe{&nil_slot},0)&&nil_slot==0
	for i in 0 .. 2{unsafe{EHTDrop(voidptr(read64(vptr+u64(i*8))))(record)};assert read64(record)==vptr}
	eht_dispose(api,child);eht_dispose(api,unrelated)
	if !api.native{assert ios_runtime.live==0&&ios_runtime.objects.len==0}
	return record
}
__global eht_teardown_calls = 0
fn eht_teardown(object u64, selector &char){
	assert ios_runtime.swift_concurrency_retired
	record:=eht_resolve(EHTApi{},true);assert record==eht_resolve(EHTApi{},false)&&read64(record+16)==ios_runtime.names['NSException']
	assert objc_class_parent(read64(record+16))==ios_runtime.names['NSObject'];eht_teardown_calls++
}
fn test_ns_exception_type(){
	$if macos{
		api:=EHTApi{true,u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2)),u64(C.dlopen(c'/usr/lib/libobjc.A.dylib',2))}
		assert api.foundation!=0&&api.core!=0&&api.objc!=0;eht_shared(api)
		for handle in [api.objc,api.core,api.foundation]!{assert C.dlclose(unsafe{voidptr(handle)})==0}
		println('NATIVE-NS-EXCEPTION-TYPE: shared 24-byte metadata, vtable/id prefix, base/subclass/unrelated matching, foreign pointer preservation, weak/nil cases, three/four-argument callbacks and no-op destructors')
	}
	if _:=ns_exception_type_symbol('_OBJC_EHTYPE_$_NSException'){assert false}
	for _ in 0 .. 2{
		objc_start();assert ios_runtime.ns_exception_type_arena==0;ns_exception_type_stop();ios_runtime.swift_concurrency_retired=true
		if _:=ns_exception_type_symbol('_OBJC_EHTYPE_$_NSException'){assert false};ios_runtime.swift_concurrency_retired=false
		record:=eht_shared(EHTApi{});assert ios_runtime.ns_internal_exception_arena==0
		for library in ['/System/Library/Frameworks/UIKit.framework/UIKit','/usr/lib/libobjc.A.dylib','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(library,'_OBJC_EHTYPE_$_NSException'){assert false}}
		for symbol in ['_OBJC_EHTYPE_$_NSExceptionExtra','_OBJC_EHTYPE_$_NSObject','_OBJC_EHTYPE_id','_objc_ehtype_vtable']!{if _:=ns_exception_type_symbol(symbol){assert false}}
		probe:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixEHTypeTeardown',0);assert probe!=0
		assert objc_add_method(probe,u64(c'dealloc'),u64(unsafe{voidptr(eht_teardown)}),c'v16@0:8');objc_register_class(probe);objc_autorelease(objc_new(probe))
		ios_runtime.swift_concurrency_retired=true;assert eht_resolve(EHTApi{},false)==record
		before:=eht_teardown_calls;objc_stop();assert eht_teardown_calls==before+1&&ios_runtime.ns_exception_type_arena==0&&ios_runtime.live==0&&ios_runtime.objects.len==0
		if _:=ns_exception_type_symbol('_OBJC_EHTYPE_$_NSException'){assert false}
	}
	println('IOS-NS-EXCEPTION-TYPE: eight cold readers, sealed vptr/name/Class record and id/vtable prefix, base/subclass/unrelated and weak/nil matching, unchanged foreign pointers, three/four-argument callbacks, no-op destructors, no object ownership, isolated name storage, retirement guards, pool callback access and two drained/unmapped lifetimes; throwing and unwinding remain unsupported')
}
