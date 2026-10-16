// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type DCName=fn(&char)u64
type DCMessage=fn(u64,u64,u64,u64,u64)u64
type DCRetain=fn(u64)u64
type DCDrop=fn(u64)
type DCPool=fn()u64
type DCText=fn(u64,&char,i64,u32)bool
struct DCApi { native bool device u64 objc u64 core u64 }
__global devicecheck_teardown_calls=0
fn dc_cell(api DCApi)u64 {
	if api.native { return u64(C.dlsym(unsafe{voidptr(api.device)},c'DCErrorDomain')) }
	return runtime_symbol('/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck','_DCErrorDomain') or {panic(err)}
}
fn dc_class(api DCApi,name &char)u64 {
	if api.native { return unsafe{DCName(C.dlsym(voidptr(api.objc),c'objc_getClass'))(name)} }
	return ios_runtime.names[ctext(u64(name))]
}
fn dc_message(api DCApi,object u64,name &char,a u64,b u64,c u64)u64 {
	if api.native { selector:=unsafe{DCName(C.dlsym(voidptr(api.objc),c'sel_registerName'))(name)};return unsafe{DCMessage(C.dlsym(voidptr(api.objc),c'objc_msgSend'))(object,selector,a,b,c)} }
	return unsafe{DCMessage(voidptr(C.ios_objc_builtin))(object,u64(name),a,b,c)}
}
fn dc_retain(api DCApi,value u64)u64 {
	if api.native { return unsafe{DCRetain(C.dlsym(voidptr(api.objc),c'objc_retain'))(value)} }
	return objc_retain(value)
}
fn dc_drop(api DCApi,value u64) {
	if api.native { unsafe{DCDrop(C.dlsym(voidptr(api.objc),c'objc_release'))(value)};return }
	objc_release(value)
}
fn dc_pool(api DCApi)u64 {
	if api.native { return unsafe{DCPool(C.dlsym(voidptr(api.objc),c'objc_autoreleasePoolPush'))()} }
	return objc_pool_push()
}
fn dc_pop(api DCApi,pool u64) {
	if api.native { unsafe{DCDrop(C.dlsym(voidptr(api.objc),c'objc_autoreleasePoolPop'))(pool)};return }
	objc_pool_pop(pool)
}
fn dc_text(api DCApi,value u64) {
	assert value!=0
	mut bytes:=[64]u8{}
	if api.native { assert unsafe{DCText(C.dlsym(voidptr(api.core),c'CFStringGetCString'))(value,&char(&bytes[0]),64,0x08000100)};assert C.strcmp(unsafe{&char(&bytes[0])},c'com.apple.devicecheck.error')==0 }
	else { assert string_text(value)=='com.apple.devicecheck.error' }
}
fn dc_reader(api DCApi)u64 {
	mut first:=u64(0)
	for _ in 0..32 {
		pool:=dc_pool(api);cell:=dc_cell(api);assert cell!=0&&cell%8==0
		if first==0 { first=cell }else{assert cell==first}
		value:=read64(cell);assert value!=0&&value!=cell;dc_text(api,value)
		assert dc_retain(api,value)==value;dc_drop(api,value)
		assert dc_message(api,dc_retain(api,value),c'autorelease',0,0,0)==value
		dc_pop(api,pool)
	}
	return first
}
fn dc_shared(api DCApi) {
	mut workers:=[]thread u64{}
	for _ in 0..8 { workers<<spawn dc_reader(api) }
	mut cell:=u64(0)
	for worker in workers { result:=worker.wait();if cell==0{cell=result}else{assert result==cell} }
	unsafe{workers.free()}
	pool:=dc_pool(api);domain:=read64(cell)
	equal:=dc_message(api,dc_class(api,c'NSString'),c'stringWithUTF8String:',u64(c'com.apple.devicecheck.error'),0,0)
	assert dc_message(api,domain,c'isEqualToString:',equal,0,0)==1
	error_object:=dc_message(api,dc_class(api,c'NSError'),c'errorWithDomain:code:userInfo:',domain,3,0)
	assert error_object!=0&&dc_retain(api,error_object)==error_object;dc_pop(api,pool)
	assert dc_message(api,error_object,c'code',0,0,0)==3
	got:=dc_message(api,error_object,c'domain',0,0,0);dc_text(api,got)
	pool2:=dc_pool(api);equal2:=dc_message(api,dc_class(api,c'NSString'),c'stringWithUTF8String:',u64(c'com.apple.devicecheck.error'),0,0)
	assert dc_message(api,got,c'isEqualToString:',equal2,0,0)==1
	dc_drop(api,error_object);dc_pop(api,pool2);dc_text(api,read64(cell))
	if !api.native { assert ios_runtime.live==0&&ios_runtime.objects.len==0 }
}
fn dc_teardown(_object u64,_selector &char) {
	assert ios_runtime.swift_concurrency_retired
	cell:=devicecheck_symbol('_DCErrorDomain') or {panic('DeviceCheck domain retired before pool callback')}
	assert string_text(read64(cell))=='com.apple.devicecheck.error';devicecheck_teardown_calls++
}
fn test_devicecheck_domain() {
	$if macos {
		api:=DCApi{true,u64(C.dlopen(c'/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck',2)),u64(C.dlopen(c'/usr/lib/libobjc.A.dylib',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};assert api.device!=0&&api.objc!=0&&api.core!=0;dc_shared(api)
		println('IOS-DEVICECHECK-NATIVE: DCErrorDomain NSString pointer cell,exact value,concurrent readers,NSError domain/code/equality and retained pool lifetime')
	}
	if _:=devicecheck_symbol('_DCErrorDomain'){assert false}
	for _ in 0..2 {
		objc_start();assert ios_runtime.devicecheck_arena==0
		ios_runtime.swift_concurrency_retired=true;if _:=devicecheck_symbol('_DCErrorDomain'){assert false};assert ios_runtime.devicecheck_arena==0;ios_runtime.swift_concurrency_retired=false
		if _:=devicecheck_symbol('_DCInventedErrorDomain'){assert false};assert ios_runtime.devicecheck_arena==0
		dc_shared(DCApi{})
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/UIKit.framework/UIKit','/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation','/usr/lib/libSystem.B.dylib']! {if _:=runtime_symbol(library,'_DCErrorDomain'){assert false}}
		probe:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixDeviceCheckTeardownProbe',0);assert probe!=0&&objc_add_method(probe,u64(c'dealloc'),u64(unsafe{voidptr(dc_teardown)}),c'v16@0:8');objc_register_class(probe);objc_autorelease(objc_new(probe))
		ios_runtime.swift_concurrency_retired=true;before:=devicecheck_teardown_calls;objc_stop()
		assert devicecheck_teardown_calls==before+1&&ios_runtime.devicecheck_arena==0&&ios_runtime.live==0&&ios_runtime.objects.len==0
		if _:=devicecheck_symbol('_DCErrorDomain'){assert false}
	}
	println('IOS-DEVICECHECK: exact framework scope,sealed stable NSString pointer cell,contended first publication,NSError ownership,pool destructor availability and two drained/unmapped runtimes')
}
