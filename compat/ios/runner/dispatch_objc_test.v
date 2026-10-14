// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
type QueueObjcSend = fn (u64,u64,u64,u64,u64) u64
type QueueObjcCreate = fn (&char,u64) u64
type QueueObjcGlobal = fn (i64,u64) u64
type QueueObjcMetadata = fn (u64) u64
type QueueObjcCopy = fn (u64,u64,u64) u64
type QueueObjcDestroy = fn (u64,u64)
type QueueObjcProbe = fn (u64,u64,u64,&u64)
struct QueueObjcApi {
	native bool
	lib voidptr
	core voidptr
	getter u64
	main_queue u64
	@[required]
	create QueueObjcCreate
	@[required]
	global QueueObjcGlobal
	@[required]
	metadata QueueObjcMetadata
}
fn queue_objc_api(native bool) QueueObjcApi {
	$if macos {if native {
		lib:=C.dlopen(c'/usr/lib/libSystem.B.dylib',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		overlay:=C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib',2);objc:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		assert lib!=unsafe{nil}&&core!=unsafe{nil}&&overlay!=unsafe{nil}&&objc!=unsafe{nil}
		return QueueObjcApi{native:true,lib:objc,core:core,main_queue:u64(C.dlsym(lib,c'_dispatch_main_q')),
			getter:u64(C.dlsym(overlay,c'$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ')),
			create:unsafe{QueueObjcCreate(C.dlsym(lib,c'dispatch_queue_create'))},global:unsafe{QueueObjcGlobal(C.dlsym(lib,c'dispatch_get_global_queue'))},
			metadata:unsafe{QueueObjcMetadata(C.dlsym(core,c'swift_getObjCClassMetadata'))}}
	}}
	return QueueObjcApi{getter:runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ') or {panic(err)},
		main_queue:darwin_dispatch_get_main_queue(),create:darwin_dispatch_queue_create,global:darwin_dispatch_get_global_queue,metadata:swift_objc_metadata}
}
fn queue_objc_class(api QueueObjcApi,name &char) u64 {
	$if macos {if api.native {return u64(C.objc_getClass(name))}}
	return objc_get_class(name)
}
fn queue_objc_parent(api QueueObjcApi,cls u64) u64 {
	$if macos {if api.native {return u64(C.class_getSuperclass(voidptr(cls)))}}
	return objc_class_parent(cls)
}
fn queue_objc_meta(api QueueObjcApi,cls u64) u64 {
	$if macos {if api.native {return u64(C.object_getClass(voidptr(cls)))}}
	return objc_object_class(cls)
}
fn queue_objc_size(api QueueObjcApi,cls u64) u64 {
	$if macos {if api.native {return u64(C.class_getInstanceSize(voidptr(cls)))}}
	return objc_class_size(cls)
}
fn queue_objc_send(api QueueObjcApi,owner u64,selector &char,argument u64) u64 {
	$if macos {if api.native {return unsafe{QueueObjcSend(C.dlsym(api.lib,c'objc_msgSend'))(owner,u64(C.sel_registerName(selector)),argument,0,0)}}}
	return unsafe{QueueObjcSend(voidptr(C.ios_objc_builtin))(owner,u64(selector),argument,0,0)}
}
fn queue_objc_refs(api QueueObjcApi,owner u64) u64 {return queue_objc_send(api,owner,c'retainCount',0)}
fn queue_objc_worker(api QueueObjcApi,owner u64,cls u64) {
	for _ in 0..128 {
		assert queue_objc_send(api,owner,c'retain',0)==owner
		assert queue_objc_send(api,owner,c'class',0)==cls
		assert queue_objc_send(api,owner,c'isKindOfClass:',queue_objc_class(api,c'OS_dispatch_queue'))==1
		queue_objc_send(api,owner,c'release',0)
	}
}
fn queue_objc_suite(api QueueObjcApi,code u64,guard u64) {
	assert api.getter!=0&&api.main_queue!=0
	parents:=[c'NSObject',c'OS_object',c'OS_dispatch_object',c'OS_dispatch_queue',c'OS_dispatch_queue_serial_executor',c'OS_dispatch_queue_serial',c'OS_dispatch_queue_main']!
	mut previous:=u64(0)
	for i,name in parents {
		cls:=queue_objc_class(api,name);assert cls!=0
		if i!=0 {assert queue_objc_parent(api,cls)==previous;assert queue_objc_size(api,cls)==8;assert queue_objc_parent(api,queue_objc_meta(api,cls))==queue_objc_meta(api,previous)}
		assert queue_objc_send(api,cls,c'self',0)==cls
		if i!=0 {
			metadata:=api.metadata(cls);assert metadata!=0&&read64(metadata)==0x305&&read64(metadata+8)==cls
			for _ in 0..8 {assert api.metadata(cls)==metadata}
		}
		previous=cls
	}
	base:=queue_objc_class(api,c'OS_dispatch_queue')
	serial:=api.create(c'vinix.objc.queue',0);global:=api.global(0,0);assert serial!=0&&global!=0
	assert queue_objc_parent(api,queue_objc_class(api,c'OS_dispatch_queue_global'))==base
	for pair in [[api.main_queue,queue_objc_class(api,c'OS_dispatch_queue_main')],[serial,queue_objc_class(api,c'OS_dispatch_queue_serial')],[global,queue_objc_class(api,c'OS_dispatch_queue_global')]] {
		owner:=pair[0];cls:=pair[1]
		assert queue_objc_meta(api,owner)==cls&&queue_objc_send(api,owner,c'class',0)==cls
		assert queue_objc_send(api,owner,c'self',0)==owner
		assert queue_objc_send(api,owner,c'superclass',0)==queue_objc_parent(api,cls)
		assert queue_objc_send(api,owner,c'isMemberOfClass:',cls)==1&&queue_objc_send(api,owner,c'isMemberOfClass:',base)==0
		assert queue_objc_send(api,owner,c'isKindOfClass:',base)==1&&queue_objc_send(api,owner,c'isKindOfClass:',queue_objc_class(api,c'NSObject'))==1
		assert queue_objc_send(api,owner,c'isEqual:',owner)==1&&queue_objc_send(api,owner,c'isEqual:',0)==0
		assert queue_objc_send(api,owner,c'hash',0)==owner
	}
	before:=queue_objc_refs(api,serial);assert before==1
	assert queue_objc_send(api,serial,c'retain',0)==serial&&queue_objc_refs(api,serial)==before+1
	queue_objc_send(api,serial,c'release',0);assert queue_objc_refs(api,serial)==before
	metadata:=api.metadata(base);table:=read64(metadata-8)
	copy_value:=unsafe{QueueObjcCopy(voidptr(read64(table+16)&0x0000ffffffffffff))}
	destroy:=unsafe{QueueObjcDestroy(voidptr(read64(table+8)&0x0000ffffffffffff))}
	for _ in 0..64 {
		mut source:=[u64(0xcafe),serial,0xbeef]!;mut result:=[u64(0xcafe),0,0xbeef]!
		assert copy_value(u64(unsafe{&result[1]}),u64(unsafe{&source[1]}),metadata)==u64(unsafe{&result[1]})
		assert result==source&&queue_objc_refs(api,serial)==before+1
		destroy(u64(unsafe{&result[1]}),metadata);assert queue_objc_refs(api,serial)==before
	}
	mut workers:=[]thread{}
	for _ in 0..8 {workers<<spawn queue_objc_worker(api,serial,queue_objc_class(api,c'OS_dispatch_queue_serial'))}
	workers.wait();assert queue_objc_refs(api,serial)==before
	mut result:=[u64(0xcafe),0,0,0,0xbeef]!
	unsafe{QueueObjcProbe(voidptr(code))(api.getter,metadata,guard,&result[1])}
	assert result==[u64(0xcafe),api.main_queue,metadata,0x5121,0xbeef]!
	queue_objc_send(api,result[1],c'release',0)
	queue_objc_send(api,serial,c'release',0)
}
fn queue_objc_reject_child(mode string,guard u64) {
	objc_start();system_data_start() or {panic(err)}
	cls:=ios_runtime.names['OS_dispatch_queue'];queue:=darwin_dispatch_queue_create(c'vinix.reject.queue',0)
	match mode {
		'allocate' {objc_allocate(cls)}
		'construct' {objc_construct_instance(cls,guard)}
		'change-to' {objc_set_class(objc_new(ios_runtime.names['NSObject']),cls)}
		'change-from' {objc_set_class(queue,ios_runtime.names['NSObject'])}
		'copy' {queue_objc_send(queue_objc_api(false),queue,c'copy',0)}
		'init' {queue_objc_send(queue_objc_api(false),queue,c'init',0)}
		'retired' {objc_stop();queue_objc_send(QueueObjcApi{create:darwin_dispatch_queue_create,global:darwin_dispatch_get_global_queue,metadata:swift_objc_metadata},queue,c'class',0)}
		else {panic('bad child mode')}
	}
	assert false
}
fn test_dispatch_objc() {
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	assert guard!=u64(-1)
	if os.args.len==3&&os.args[1]=='queue-objc-reject' {queue_objc_reject_child(os.args[2],guard);return}
	code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0303f3,0xaa0003f0,0xaa0103f4,0xaa0203e8,0xd28a2435,0xd63f0200,0xf9000260,0xf9000674,0xf9000a75,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+64));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos {
		queue_objc_suite(queue_objc_api(true),code,guard)
		println('IOS-DISPATCH-OBJC-NATIVE: public/private queue hierarchy and metaclasses, opaque isa, canonical Swift wrappers, real main/serial/global queues, owned class-typed main getter, value-witness ARC and eight concurrent readers')
	}
	assert dispatch_objc_symbol('_OBJC_CLASS_$_OS_dispatch_queue')==none
	for cycle in 0..2 {
		if cycle==0 {objc_start();system_data_start()!}
		else {
			system_data_start()!
			early:=darwin_dispatch_queue_create(c'vinix.before.objc',0)
			darwin_dispatch_get_global_queue(0,0)
			assert read64(early)==0&&read64(darwin_dispatch_get_main_queue())==0
			objc_start()
			assert read64(early)==ios_runtime.names['OS_dispatch_queue_serial']
			assert read64(darwin_dispatch_get_main_queue())==ios_runtime.names['OS_dispatch_queue_main']
			objc_release(early)
		}
		api:=queue_objc_api(false);queue_objc_suite(api,code,guard)
		for prefix in ['_OBJC_CLASS_$_','_OBJC_METACLASS_$_']! {
			cls:=runtime_symbol('/usr/lib/libSystem.B.dylib',prefix+'OS_dispatch_queue')!
			assert cls==if prefix=='_OBJC_CLASS_$_'{ios_runtime.names['OS_dispatch_queue']}else{read64(ios_runtime.names['OS_dispatch_queue'])}
			if _:=runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation',prefix+'OS_dispatch_queue') {assert false}
			for name in ['OS_object','OS_dispatch_object','OS_dispatch_queue_serial_executor','OS_dispatch_queue_serial','OS_dispatch_queue_main','OS_dispatch_queue_global']! {assert runtime_symbol('/usr/lib/libSystem.B.dylib',prefix+name)! == if prefix=='_OBJC_CLASS_$_'{ios_runtime.names[name]}else{read64(ios_runtime.names[name])}}
		}
		assert dispatch_objc_symbol('_OBJC_CLASS_$_OS_dispatch_queue_extra')==none
		assert dispatch_objc_symbol('_OBJC_METACLASS_$_')==none
		if _:=dispatch_objc_allocation_checked(guard) {assert false}
		if _:=dispatch_objc_allocation_checked(ios_runtime.names['OS_dispatch_queue']) {assert false}
		subclass:=objc_allocate_class(ios_runtime.names['OS_dispatch_queue'],c'VinixQueueConstructionReject',0);objc_register_class(subclass)
		if _:=dispatch_objc_allocation_checked(subclass) {assert false};objc_dispose_class(subclass)
		queue:=darwin_dispatch_queue_create(c'vinix.autorelease.queue',0)
		pool:=objc_pool_push();assert objc_retain(queue)==queue;objc_autorelease(queue);assert (dispatch_objc_view(queue) or {panic('missing queue')}).refs==2
		objc_pool_pop(pool);assert (dispatch_objc_view(queue) or {panic('missing queue')}).refs==1
		objc_release(queue);assert dispatch_objc_view(queue)==none
		for owner in [u64(1),guard,~u64(0)]! {assert dispatch_objc_view(owner)==none}
		assert ios_runtime.live==0&&ios_runtime.swift_heap.len==0
		objc_stop();assert dispatch_objc_symbol('_OBJC_CLASS_$_OS_dispatch_queue')==none
		if _:=dispatch_objc_allocation_checked(guard) {assert false}
		system_data_stop();assert dispatch_runtime==unsafe{nil}
	}
	for mode in ['allocate','construct','change-to','change-from','copy','init','retired']! {
		mut child:=os.new_process(os.executable());child.set_args(['queue-objc-reject',mode]);child.set_redirect_stdio_merged();child.run();s:=child.stdout_slurp();child.wait();status:=child.code;child.close()
		assert status!=0&&s.contains('iOS:')&&!s.contains('ERROR: AddressSanitizer')&&!s.contains('runtime error:')&&!s.contains('signal 11'),s
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-DISPATCH-OBJC: canonical libSystem queue class/metadata, scheduler-backed isa and ARC, real queue class messages/getter/value witnesses, eight workers, pool ownership, factory-only construction/isa and copy/init rejection, protected foreign lookups, both startup orders and two drained lifetimes')
}
