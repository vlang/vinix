// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
fn C.dup2(i32,i32)i32
$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFArray.h>
	fn C.objc_getClass(&char)voidptr
	fn C.sel_registerName(&char)voidptr
	fn C.CFArrayGetCount(voidptr)i64
	fn C.CFArrayGetTypeID()u64
	fn C.CFGetTypeID(voidptr)u64
	fn C.CFEqual(voidptr,voidptr)bool
	fn C.CFHash(voidptr)u64
}
type NEASend = fn (u64,u64,u64,u64,u64)u64
type NEAPush = fn ()u64
type NEAPop = fn (u64)
struct NEAApi { native bool foundation u64 core u64 objc u64 }
fn nea_resolve(api NEAApi, core bool, direct bool)u64{
	if api.native{return u64(C.dlsym(unsafe{voidptr(if core{api.core}else{api.foundation})},if direct{c'__NSArray0__struct'}else{c'__NSArray0__'}))}
	return runtime_symbol(if core{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/Foundation.framework/Foundation'},if direct{'___NSArray0__struct'}else{'___NSArray0__'}) or {panic(err)}
}
fn nea_class(api NEAApi,name &char)u64{
	$if macos{if api.native{return u64(C.objc_getClass(name))}}
	return ios_runtime.names[ctext(u64(name))]
}
fn nea_message(api NEAApi,object u64,selector &char,a u64,b u64,c u64)u64{
	$if macos{if api.native{return unsafe{NEASend(C.dlsym(voidptr(api.objc),c'objc_msgSend'))(object,u64(C.sel_registerName(selector)),a,b,c)}}}
	mut frame:=RegisterFrame{};frame.x[0]=object;frame.x[1]=u64(selector);frame.x[2]=a;frame.x[3]=b;frame.x[4]=c
	assert objc_dispatch(mut frame,0)==0;return frame.x[0]
}
fn nea_pool(api NEAApi)u64{if api.native{return unsafe{NEAPush(C.dlsym(voidptr(api.objc),c'objc_autoreleasePoolPush'))()}};return objc_pool_push()}
fn nea_pop(api NEAApi,pool u64){if api.native{unsafe{NEAPop(C.dlsym(voidptr(api.objc),c'objc_autoreleasePoolPop'))(pool)};return};objc_pool_pop(pool)}
fn nea_count(api NEAApi,object u64)i64{
	$if macos{if api.native{return C.CFArrayGetCount(voidptr(object))}}
	return cf_array_count(object)
}
fn nea_equal_hash(api NEAApi,left u64,right u64){
	$if macos{if api.native{assert C.CFEqual(voidptr(left),voidptr(right))&&C.CFEqual(voidptr(right),voidptr(left))&&C.CFHash(voidptr(left))==C.CFHash(voidptr(right));return}}
	assert object_equal(left,right)&&object_equal(right,left)&&cf_hash(left)==cf_hash(right)
}
fn nea_reader(api NEAApi,offset int)u64{
	mut cell:=u64(0)
	for i in 0..128{
		got:=nea_resolve(api,(i+offset)%2==0,false);assert got!=0&&got%8==0
		if cell==0{cell=got}else{assert got==cell}
		assert read64(got)!=0&&read64(got)!=got&&nea_resolve(api,(i+offset)%2!=0,true)==read64(got)
	}
	return cell
}
fn nea_shared(api NEAApi)u64{
	mut workers:=[]thread u64{}
	for i in 0..8{workers<<spawn nea_reader(api,i)}
	mut cell:=u64(0)
	for i,worker in workers{got:=worker.wait();if i==0{cell=got}else{assert got==cell}}
	unsafe{workers.free()}
	object:=read64(cell)
	if !api.native{assert cell==ios_runtime.empty_array_cell&&object==ios_runtime.empty_array&&object in ios_runtime.constants&&ios_runtime.live==1&&ios_runtime.objects.len==1&&ios_runtime.framework_objects.len==0&&ios_runtime.framework_data.len==0;assert cf_type_id(object)==cf_array_id()}
	$if macos{if api.native{assert C.CFGetTypeID(voidptr(object))==C.CFArrayGetTypeID()}}
	assert nea_message(api,object,c'isKindOfClass:',nea_class(api,c'NSArray'),0,0)==1&&nea_message(api,object,c'isKindOfClass:',nea_class(api,c'NSMutableArray'),0,0)==0
	pool:=nea_pool(api)
	assert nea_count(api,object)==0&&nea_message(api,object,c'count',0,0,0)==0&&nea_message(api,object,c'firstObject',0,0,0)==0
	for selector in [c'copy',c'copyWithZone:',c'mutableCopy',c'mutableCopyWithZone:',c'hash',c'isEqual:',c'isEqualToArray:']!{
		$if macos{if api.native{assert nea_message(api,object,c'respondsToSelector:',u64(C.sel_registerName(selector)),0,0)==1}else{assert objc_responds(object,selector)}}
		$else{assert objc_responds(object,selector)}
	}
	for selector in [c'copy',c'copyWithZone:']!{assert nea_message(api,object,selector,0,0,0)==object;nea_message(api,object,c'release',0,0,0)}
	for selector in [c'mutableCopy',c'mutableCopyWithZone:']!{
		cloned:=nea_message(api,object,selector,0,0,0);assert cloned!=object&&nea_count(api,cloned)==0&&nea_message(api,cloned,c'isKindOfClass:',nea_class(api,c'NSMutableArray'),0,0)==1
		nea_equal_hash(api,object,cloned);assert nea_message(api,object,c'isEqual:',cloned,0,0)==1&&nea_message(api,object,c'isEqualToArray:',cloned,0,0)==1
		nea_message(api,cloned,c'addObject:',object,0,0);assert nea_count(api,cloned)==1&&nea_count(api,object)==0&&nea_message(api,object,c'isEqual:',cloned,0,0)==0
		nea_message(api,cloned,c'removeAllObjects',0,0,0);nea_message(api,cloned,c'release',0,0,0)
	}
	assert nea_message(api,object,c'isEqual:',0,0,0)==0
	for count in [u64(0),1,4]!{
		mut state:=[8]u64{};mut buffer:=[u64(0xcafe),0xbeef,0xf00d,0xfeed,0xdead]!
		assert nea_message(api,object,c'countByEnumeratingWithState:objects:count:',u64(unsafe{&state[0]}),u64(unsafe{&buffer[0]}),count)==0&&buffer==[u64(0xcafe),0xbeef,0xf00d,0xfeed,0xdead]!
	}
	values:=[object,object]!
	array:=nea_message(api,nea_class(api,c'NSArray'),c'arrayWithObjects:count:',u64(unsafe{&values[0]}),2,0)
	dictionary:=nea_message(api,nea_class(api,c'NSDictionary'),c'dictionaryWithObjects:forKeys:count:',u64(unsafe{&values[0]}),u64(unsafe{&values[0]}),1)
	nea_message(api,array,c'retain',0,0,0);nea_message(api,dictionary,c'retain',0,0,0)
	for _ in 0..20{assert nea_message(api,object,c'retain',0,0,0)==object;nea_message(api,object,c'release',0,0,0);nea_message(api,object,c'release',0,0,0)}
	assert nea_message(api,object,c'autorelease',0,0,0)==object;nea_pop(api,pool)
	assert read64(cell)==object&&nea_count(api,object)==0&&nea_count(api,array)==2&&nea_message(api,array,c'objectAtIndex:',1,0,0)==object&&nea_message(api,dictionary,c'objectForKey:',object,0,0)==object
	nea_message(api,array,c'release',0,0,0);nea_message(api,dictionary,c'release',0,0,0)
	if !api.native{
		mut weak:=u64(0);assert objc_store_weak(unsafe{&weak},object)==object&&objc_load_weak(unsafe{&weak})==object;objc_release(object);assert weak==object;objc_destroy_weak(unsafe{&weak});assert weak==0
		assert ios_runtime.live==1&&ios_runtime.objects.len==1&&obj_header(object).refs==1&&obj_header(object).items.len==0
	}
	return cell
}
fn nea_reject_mutation(object u64){
	for selector in [c'addObject:',c'removeObjectAtIndex:',c'removeAllObjects',c'setObject:atIndexedSubscript:',c'setObject:forKeyedSubscript:',c'setObject:forKey:',c'removeObjectForKey:']!{
		mut descriptors:=[2]i32{};assert C.pipe(unsafe{&descriptors[0]})==0;pid:=C.ios_fork();assert pid>=0
		if pid==0{C.close(descriptors[0]);assert C.dup2(descriptors[1],2)==2;C.close(descriptors[1]);nea_message(NEAApi{},object,selector,object,object,0);C._exit(0)}
		C.close(descriptors[1]);mut bytes:=[16384]u8{};mut length:=0
		for{assert length<bytes.len;count:=C.read(descriptors[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
		C.close(descriptors[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
		output:=unsafe{tos(&bytes[0],length)};assert output.contains('mutation of the immutable empty array')&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
	}
}
__global nea_teardown_calls=0
fn nea_teardown(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;cell:=nea_resolve(NEAApi{},true,false);assert read64(cell)==ios_runtime.empty_array&&nea_count(NEAApi{},read64(cell))==0&&nea_resolve(NEAApi{},false,true)==read64(cell);nea_teardown_calls++}
fn test_ns_empty_array(){
	$if macos{
		api:=NEAApi{true,u64(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2)),u64(C.dlopen(c'/usr/lib/libobjc.A.dylib',2))};assert api.foundation!=0&&api.core!=0&&api.objc!=0;nea_shared(api)
		for handle in [api.objc,api.core,api.foundation]!{assert C.dlclose(unsafe{voidptr(handle)})==0}
		println('NATIVE-NS-EMPTY-ARRAY: pointer cell and direct struct alias, immutable copies, independent mutable copies, guarded enumeration and nested container ownership')
	}
	if _:=ns_empty_array_symbol('___NSArray0__'){assert false}
	for _ in 0..2{
		objc_start();assert ios_runtime.empty_array_cell==0&&ios_runtime.empty_array==0;ns_empty_array_stop();ios_runtime.swift_concurrency_retired=true
		if _:=ns_empty_array_symbol('___NSArray0__'){assert false};ios_runtime.swift_concurrency_retired=false
		cell:=nea_shared(NEAApi{});nea_reject_mutation(read64(cell))
		for library in ['/System/Library/Frameworks/UIKit.framework/UIKit','/usr/lib/libobjc.A.dylib','/usr/lib/libSystem.B.dylib']!{for symbol in ['___NSArray0__','___NSArray0__struct']!{if _:=runtime_symbol(library,symbol){assert false}}}
		for symbol in ['___NSArray0__extra','___NSArray0','___NSArray0__structExtra']!{if _:=ns_empty_array_symbol(symbol){assert false}}
		probe:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixEmptyArrayTeardown',0);assert probe!=0;assert objc_add_method(probe,u64(c'dealloc'),u64(unsafe{voidptr(nea_teardown)}),c'v16@0:8');objc_register_class(probe);objc_autorelease(objc_new(probe))
		ios_runtime.swift_concurrency_retired=true;assert nea_resolve(NEAApi{},false,false)==cell;before:=nea_teardown_calls;objc_stop()
		assert nea_teardown_calls==before+1&&ios_runtime.empty_array_cell==0&&ios_runtime.empty_array==0&&ios_runtime.live==0&&ios_runtime.objects.len==0
		if _:=ns_empty_array_symbol('___NSArray0__'){assert false}
	}
	println('IOS-NS-EMPTY-ARRAY: eight cold readers, shared pointer cell and direct struct alias, immutable copy identity and independent mutable copies, guarded empty enumeration, seven rejected mutations, retained array/dictionary ownership across pool drain, isolated cache ownership, retirement guards, pool callback access and two drained/unmapped lifetimes')
}
