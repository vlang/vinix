// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type DDCreate = fn (u64,u64,u64,u64) u64
type DDConcat = fn (u64,u64) u64
type DDMap = fn (u64,&u64,&u64) u64
type DDSize = fn (u64) u64
type DDControl = fn (u64)
type DDQueue = fn (&char,u64) u64
type DDSync = fn (u64,voidptr,DispatchFunction)
struct DDApi {
	native bool
	empty u64
	stack_isa u64
	@[required]
	create DDCreate
	@[required]
	concat DDConcat
	@[required]
	map_data DDMap
	@[required]
	size DDSize
	@[required]
	retain DDControl
	@[required]
	release DDControl
}
fn dd_api(native bool) DDApi {
	$if macos { if native {
		h:=C.dlopen(c'/usr/lib/libSystem.B.dylib',2);assert h!=unsafe{nil}
		return DDApi{native:true,empty:u64(C.dlsym(h,c'_dispatch_data_empty')),stack_isa:u64(C.dlsym(h,c'_NSConcreteStackBlock')),
			create:unsafe{DDCreate(C.dlsym(h,c'dispatch_data_create'))},concat:unsafe{DDConcat(C.dlsym(h,c'dispatch_data_create_concat'))},map_data:unsafe{DDMap(C.dlsym(h,c'dispatch_data_create_map'))},size:unsafe{DDSize(C.dlsym(h,c'dispatch_data_get_size'))},retain:unsafe{DDControl(C.dlsym(h,c'dispatch_retain'))},release:unsafe{DDControl(C.dlsym(h,c'dispatch_release'))}}
	} }
	return DDApi{empty:runtime_symbol('/usr/lib/libSystem.B.dylib','__dispatch_data_empty') or {panic(err)},stack_isa:block_isa(0),
		create:unsafe{DDCreate(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_dispatch_data_create') or {panic(err)}))},concat:darwin_dispatch_data_create_concat,map_data:darwin_dispatch_data_create_map,size:darwin_dispatch_data_get_size,retain:darwin_dispatch_retain,release:darwin_dispatch_release}
}
fn dd_bytes(api DDApi,data u64,expected []u8){
	mut pointer:=u64(0);mut size:=u64(0)
	mapped:=api.map_data(data,unsafe{&pointer},unsafe{&size});assert size==u64(expected.len)&&api.size(mapped)==size
	for i,value in expected{assert unsafe{*(&u8(pointer+u64(i)))}==value}
	api.release(mapped)
}
fn dd_defaults(api DDApi,guard u64){
	assert api.empty!=0&&api.create(guard,0,guard,0)==api.empty
	mut pointer:=u64(99);mut length:=u64(99)
	mapped:=api.map_data(api.empty,unsafe{&pointer},unsafe{&length});assert mapped==api.empty&&pointer==0&&length==0
	api.release(mapped);api.retain(api.empty);api.release(api.empty)
	mut input:=[u8(1),2,3,4,5,6,7,8]!
	for rounding in [i32(C.FE_TONEAREST),C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO]!{
		old:=C.fegetround();assert C.fesetround(rounding)==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO);flags:=C.fetestexcept(C.FE_ALL_EXCEPT)
		darwin_set_errno(42);data:=api.create(u64(unsafe{&input[0]}),8,0,0);assert data!=0&&api.size(data)==8
		input[0]=99;dd_bytes(api,data,[u8(1),2,3,4,5,6,7,8]);input[0]=1
		joined:=api.concat(data,data);assert api.size(joined)==16
		api.release(data);dd_bytes(api,joined,[u8(1),2,3,4,5,6,7,8,1,2,3,4,5,6,7,8])
		assert api.concat(api.empty,joined)==joined;api.release(joined)
		assert api.concat(joined,api.empty)==joined;api.release(joined)
		api.release(api.map_data(joined,unsafe{nil},unsafe{nil}));api.release(joined)
		assert unsafe{*C.ios_errno_address()}==42&&C.fegetround()==rounding&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags
		assert C.fesetround(old)==0;C.feclearexcept(C.FE_ALL_EXCEPT)
	}
}
struct DDState {
	api DDApi
	owner u64
	queue u64
mut:
	copies i64
	disposes i64
	calls i64
	buffer u64
}
__global dd_descriptor=[4]u64{}
fn dd_copy(_destination u64,source u64){
	mut state:=unsafe{&DDState(read64(source+32))}
	state.api.retain(state.owner)
	C.ios_ref_change(unsafe{&state.copies},1)
}
fn dd_dispose(block u64){
	mut state:=unsafe{&DDState(read64(block+32))}
	state.api.release(state.owner)
	C.ios_ref_change(unsafe{&state.disposes},1)
}
fn dd_unlocked_reader(owner u64) bool { return dispatch_objc_is_object(owner) }
fn dd_body(block u64){
	mut state:=unsafe{&DDState(read64(block+32))}
	assert state.api.size(state.owner)==1
	if !state.api.native {worker:=spawn dd_unlocked_reader(state.owner);assert worker.wait()}
	if state.buffer!=0{assert unsafe{*(&u8(state.buffer))}==99;C.free(unsafe{voidptr(state.buffer)});state.buffer=0}
	C.ios_ref_change(unsafe{&state.calls},1)
}
fn dd_noop(_context voidptr){}
fn dd_count(value &i64) u64 {return C.ios_load_pointer(unsafe{&u64(value)})}
fn dd_queue(api DDApi) u64 {
	$if macos {if api.native{
		make_queue:=unsafe{DDQueue(C.dlsym(voidptr(-2),c'dispatch_queue_create'))};queue:=make_queue(c'vinix.native.data',0)
		unsafe{DDControl(C.dlsym(voidptr(-2),c'dispatch_suspend'))(queue)};return queue
	}}
	return darwin_dispatch_queue_create_with_target(c'vinix.data.main',0,darwin_dispatch_get_main_queue())
}
fn dd_flush(api DDApi,queue u64){
	$if macos {if api.native{
		unsafe{DDControl(C.dlsym(voidptr(-2),c'dispatch_resume'))(queue)}
		unsafe{DDSync(C.dlsym(voidptr(-2),c'dispatch_sync_f'))(queue,unsafe{nil},dd_noop)};return
	}}
	assert dispatch_main_drain()
}
fn dd_custom(api DDApi,length u64,shutdown bool){
	queue:=dd_queue(api);mut byte:=u8(7);owner:=api.create(u64(unsafe{&byte}),1,0,0)
	mut state:=DDState{api:api,owner:owner,queue:queue,buffer:if length==0{0}else{u64(C.malloc(8))}}
	if length!=0 {C.memset(unsafe{voidptr(state.buffer)},99,8)}
	mut literal:=[api.stack_isa,u64(1)<<25,u64(unsafe{voidptr(dd_body)}),u64(unsafe{&dd_descriptor[0]}),u64(unsafe{&state})]!
	data:=api.create(state.buffer,length,queue,u64(unsafe{&literal[0]}));assert data!=0&&dd_count(unsafe{&state.copies})==1
	literal[4]=1
	if length!=0 {dd_bytes(api,data,[u8(99),99,99,99,99,99,99,99])}else{assert data==api.empty}
	combined:=api.concat(data,data);api.release(data)
	assert dd_count(unsafe{&state.calls})==0
	if shutdown {
		api.release(queue);api.release(owner)
		// Keep a composite application owner and a pending zero-size destructor.
		// Shutdown must finish both before ObjC block/runtime storage retires.
		objc_stop();assert dd_count(unsafe{&state.calls})==1&&dd_count(unsafe{&state.disposes})==1
		assert ios_runtime.block_refs.len==0&&dispatch_runtime.data.len==1
		return
	}
	api.release(combined);api.release(owner)
	dd_flush(api,queue)
	deadline:=time.sys_mono_now()+3_000_000_000
	for dd_count(unsafe{&state.calls})!=1||dd_count(unsafe{&state.disposes})!=1{assert time.sys_mono_now()<deadline;time.sleep(time.millisecond)}
	assert state.buffer==0
	api.release(queue)
}
fn dd_worker(api DDApi){
	for _ in 0..64{mut bytes:=[u8(3),4,5,6]!;data:=api.create(u64(unsafe{&bytes[0]}),4,0,0);combined:=api.concat(data,data);api.release(data);dd_bytes(api,combined,[u8(3),4,5,6,3,4,5,6]);api.release(combined)}
}
fn test_dispatch_data(){
	dd_descriptor=[u64(0),40,u64(unsafe{voidptr(dd_copy)}),u64(unsafe{voidptr(dd_dispose)})]!
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
	$if macos {native:=dd_api(true);dd_defaults(native,guard);dd_custom(native,0,false);dd_custom(native,8,false)}
	for _ in 0..2{
		objc_start();system_data_start()!
		api:=dd_api(false);dd_defaults(api,guard);dd_custom(api,0,false);dd_custom(api,8,false)
		mut workers:=[]thread{cap:8};for _ in 0..8{workers<<spawn dd_worker(api)};workers.wait();unsafe{workers.free()}
		mut byte:=u8(9);leaf:=api.create(u64(unsafe{&byte}),1,0,0);mut rope:=api.empty
		for _ in 0..4096{joined:=api.concat(rope,leaf);api.release(rope);rope=joined};api.release(leaf)
		mut pointer:=u64(0);mut size:=u64(0);mapped:=api.map_data(rope,unsafe{&pointer},unsafe{&size});api.release(rope);assert size==4096
		for i in 0..4096{assert unsafe{*(&u8(pointer+u64(i)))}==9};api.release(mapped)
		data:=api.create(u64(unsafe{&byte}),1,0,0);assert !dispatch_objc_is_queue(data)&&dispatch_objc_is_object(data)
		assert read64(data)==ios_runtime.names['OS_dispatch_data']&&objc_is_kind(data,ios_runtime.names['NSData'])
		assert objc_retain(data)==data;swift_unknown_release(data)
		pool:=objc_pool_push();objc_autorelease(data);objc_pool_pop(pool);assert !dispatch_objc_is_object(data)
		assert dispatch_runtime.data.len==1&&ios_runtime.block_refs.len==0
		dd_custom(api,8,true);system_data_stop();assert dispatch_runtime==unsafe{nil}
	}
	// Pending empty-data callbacks use the cancellation cleanup at shutdown.
	objc_start();system_data_start()!;dd_custom(dd_api(false),0,true);system_data_stop()
	assert C.munmap(voidptr(guard),page)==0
	println('IOS-DISPATCH-DATA: native copy/borrow/empty and concat/map ABI, promoted block captures with exactly-once queued destructors, unlocked reentrant disposal, guarded zero buffers, floating state/errno, 1024 concurrent lifetimes, 4096-node iterative ropes, ObjC/Swift ownership and three drained shutdowns passed')
}
