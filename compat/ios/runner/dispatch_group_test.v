// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
fn C.dlsym(voidptr,&char) voidptr
type DGCreate = fn () u64
type DGControl = fn (u64)
type DGWait = fn (u64,u64) i64
type DGAsync = fn (u64,u64,voidptr,DispatchFunction)
type DGBlock = fn (u64,u64,u64)
type DGQueue = fn (&char,u64) u64
type DGTime = fn (u64,i64) u64
type DGWall = fn (&DispatchTimespec,i64) u64
type DGContext = fn (u64,voidptr)
type DGFinalizer = fn (u64,DispatchFunction)
struct DGApi {
	native bool
	stack_isa u64
	@[required] create DGCreate
	@[required] enter DGControl
	@[required] leave DGControl
	@[required] wait_group DGWait
	@[required] submit DGAsync
	@[required] notify DGAsync
	@[required] submit_block DGBlock
	@[required] notify_block DGBlock
	@[required] make DGQueue
	@[required] retain DGControl
	@[required] release DGControl
	@[required] deadline DGTime
	@[required] wall DGWall
	@[required] set_context DGContext
	@[required] set_finalizer DGFinalizer
}
fn dg_symbol(native bool,symbol string) voidptr {
	$if macos { if native { p:=C.dlsym(voidptr(-2),symbol.str);assert p!=unsafe{nil};return p } }
	return unsafe{voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_'+symbol) or {panic(err)})}
}
fn dg_api(native bool) DGApi {
	return DGApi{native:native,stack_isa:if native{u64(C.dlsym(voidptr(-2),c'_NSConcreteStackBlock'))}else{block_isa(0)},create:unsafe{DGCreate(dg_symbol(native,'dispatch_group_create'))},enter:unsafe{DGControl(dg_symbol(native,'dispatch_group_enter'))},leave:unsafe{DGControl(dg_symbol(native,'dispatch_group_leave'))},wait_group:unsafe{DGWait(dg_symbol(native,'dispatch_group_wait'))},submit:unsafe{DGAsync(dg_symbol(native,'dispatch_group_async_f'))},notify:unsafe{DGAsync(dg_symbol(native,'dispatch_group_notify_f'))},submit_block:unsafe{DGBlock(dg_symbol(native,'dispatch_group_async'))},notify_block:unsafe{DGBlock(dg_symbol(native,'dispatch_group_notify'))},make:unsafe{DGQueue(dg_symbol(native,'dispatch_queue_create'))},retain:unsafe{DGControl(dg_symbol(native,'dispatch_retain'))},release:unsafe{DGControl(dg_symbol(native,'dispatch_release'))},deadline:unsafe{DGTime(dg_symbol(native,'dispatch_time'))},wall:unsafe{DGWall(dg_symbol(native,'dispatch_walltime'))},set_context:unsafe{DGContext(dg_symbol(native,'dispatch_set_context'))},set_finalizer:unsafe{DGFinalizer(dg_symbol(native,'dispatch_set_finalizer_f'))}}
}
struct DGState {
	api DGApi
	group u64
	gate bool
	retain_capture bool
	queue u64
mut:
	called u64
	copies u64
	disposing u64
	proceed u64
	disposed u64
	started u64
	finished u64
	finalized u64
	notified u64
}
struct DGLiteral { isa u64;flags u32;reserved u32;invoke u64;descriptor u64;state &DGState }
fn dg_load(p &u64) u64 {return C.ios_load_pointer(p)}
fn dg_wait(p &u64,value u64){deadline:=time.sys_mono_now()+10_000_000_000;for dg_load(p)!=value{assert time.sys_mono_now()<deadline;time.sleep(time.millisecond)}}
fn dg_add(p &u64){C.ios_ref_change(unsafe{&i64(p)},1)}
fn dg_count(context voidptr){mut state:=unsafe{&DGState(context)};dg_add(unsafe{&state.called})}
fn dg_nested(context voidptr){state:=unsafe{&DGState(context)};state.api.submit(state.group,state.queue,context,dg_count)}
fn dg_notify(context voidptr){mut state:=unsafe{&DGState(context)};dg_add(unsafe{&state.notified})}
fn dg_finalizer(context voidptr){mut state:=unsafe{&DGState(context)};dg_add(unsafe{&state.finalized})}
fn dg_block_call(block u64){state:=unsafe{(&DGLiteral(block)).state};dg_count(state)}
fn dg_copy(dst u64,src u64){state:=unsafe{(&DGLiteral(src)).state};dg_add(unsafe{&state.copies});if state.retain_capture{state.api.retain(state.group)}}
fn dg_dispose(block u64){state:=unsafe{(&DGLiteral(block)).state};C.ios_store_pointer(unsafe{&state.disposing},1);if state.gate{dg_wait(unsafe{&state.proceed},1)};if state.retain_capture{state.api.release(state.group)};dg_add(unsafe{&state.disposed})}
fn dg_gate(context voidptr){mut state:=unsafe{&DGState(context)};C.ios_store_pointer(unsafe{&state.started},1);dg_wait(unsafe{&state.proceed},1);C.ios_store_pointer(unsafe{&state.finished},1)}
fn dg_basic(api DGApi){
	group:=api.create();assert group!=0&&api.wait_group(group,0)==0&&api.wait_group(group,api.deadline(0,-1))==0
	for rounding in [i32(C.FE_TONEAREST),C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO]!{
		old:=C.fegetround();assert C.fesetround(rounding)==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO);flags:=C.fetestexcept(C.FE_ALL_EXCEPT)
		darwin_set_errno(42);api.enter(group);api.enter(group);assert api.wait_group(group,0)!=0
		assert api.wait_group(group,api.deadline(0,1_000_000))!=0
		assert api.wait_group(group,api.wall(unsafe{nil},1_000_000))!=0
		api.leave(group);assert api.wait_group(group,0)!=0;api.leave(group);assert api.wait_group(group,0)==0
		assert C.fegetround()==rounding&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags
		if !api.native{assert unsafe{*C.ios_errno_address()}==42}
		assert C.fesetround(old)==0;C.feclearexcept(C.FE_ALL_EXCEPT)
	}
	api.release(group)
}
fn dg_worker(api DGApi,group u64,queue u64,state &DGState){for _ in 0..128{api.enter(group);api.submit(group,queue,state,dg_count);api.leave(group)}}
fn dg_members(api DGApi){
	group:=api.create();queue:=api.make(c'vinix.group.members',0);mut state:=DGState{api:api,group:group}
	api.enter(group);api.notify(group,queue,unsafe{&state},dg_notify)
	mut workers:=[]thread{cap:8};for _ in 0..8{workers<<spawn dg_worker(api,group,queue,unsafe{&state})};workers.wait();unsafe{workers.free()}
	assert dg_load(unsafe{&state.notified})==0;api.leave(group);assert api.wait_group(group,api.deadline(0,10_000_000_000))==0;assert dg_load(unsafe{&state.called})==1024;dg_wait(unsafe{&state.notified},1)
	for _ in 0..8{api.enter(group);api.submit(group,queue,unsafe{&state},dg_count);api.leave(group);assert api.wait_group(group,~u64(0))==0}
	assert dg_load(unsafe{&state.called})==1032
	mut nested:=DGState{api:api,group:group,queue:queue};api.submit(group,queue,unsafe{&nested},dg_nested);assert api.wait_group(group,~u64(0))==0&&dg_load(unsafe{&nested.called})==1
	api.release(group);api.release(queue)
}
fn dg_blocks(api DGApi){
	group:=api.create();queue:=api.make(c'vinix.group.block',0);mut state:=DGState{api:api,group:group,gate:true,retain_capture:true}
	api.set_context(group,unsafe{&state});api.set_finalizer(group,dg_finalizer)
	descriptor:=[u64(0),u64(sizeof(DGLiteral)),u64(voidptr(dg_copy)),u64(voidptr(dg_dispose))]!
	literal:=DGLiteral{isa:api.stack_isa,flags:u32(1)<<25,invoke:u64(voidptr(dg_block_call)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state}}
	api.submit_block(group,queue,u64(unsafe{&literal}));dg_wait(unsafe{&state.disposing},1)
	assert dg_load(unsafe{&state.copies})==1&&dg_load(unsafe{&state.called})==1&&api.wait_group(group,0)!=0
	C.ios_store_pointer(unsafe{&state.proceed},1);assert api.wait_group(group,~u64(0))==0&&dg_load(unsafe{&state.disposed})==1
	global_literal:=DGLiteral{isa:if api.native{u64(C.dlsym(voidptr(-2),c'_NSConcreteGlobalBlock'))}else{block_isa(1)},flags:u32(1)<<28,invoke:u64(voidptr(dg_block_call)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state}}
	api.submit_block(group,queue,u64(unsafe{&global_literal}));assert api.wait_group(group,~u64(0))==0
	assert dg_load(unsafe{&state.called})==2&&dg_load(unsafe{&state.copies})==1&&dg_load(unsafe{&state.disposed})==1
	api.enter(group);api.release(group);assert dg_load(unsafe{&state.finalized})==0;api.leave(group);dg_wait(unsafe{&state.finalized},1);api.release(queue)
}
fn dg_empty_notify(api DGApi){
	group:=api.create();busy:=api.create();queue:=api.make(c'vinix.group.notify',0);mut gate:=DGState{api:api,group:busy};mut state:=DGState{api:api,group:group}
	api.submit(busy,queue,unsafe{&gate},dg_gate);dg_wait(unsafe{&gate.started},1)
	descriptor:=[u64(0),u64(sizeof(DGLiteral)),u64(voidptr(dg_copy)),u64(voidptr(dg_dispose))]!
	literal:=DGLiteral{isa:api.stack_isa,flags:u32(1)<<25,invoke:u64(voidptr(dg_block_call)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state}}
	api.notify_block(group,queue,u64(unsafe{&literal}));assert dg_load(unsafe{&state.copies})==1&&dg_load(unsafe{&state.called})==0&&dg_load(unsafe{&state.disposed})==0
	api.release(group);api.release(queue);C.ios_store_pointer(unsafe{&gate.proceed},1);assert api.wait_group(busy,~u64(0))==0;dg_wait(unsafe{&state.disposed},1);assert dg_load(unsafe{&state.called})==1;api.release(busy)
}
fn dg_waiter(state &DGState){C.ios_store_pointer(unsafe{&state.started},1);assert state.api.wait_group(state.group,~u64(0))==0;C.ios_store_pointer(unsafe{&state.finished},1)}
fn dg_generation(api DGApi){
	group:=api.create();mut state:=DGState{api:api,group:group};api.enter(group);worker:=spawn dg_waiter(unsafe{&state});dg_wait(unsafe{&state.started},1)
	if api.native{time.sleep(20*time.millisecond)}else{
		deadline:=time.sys_mono_now()+5_000_000_000
		for{C.pthread_mutex_lock(dispatch_runtime.mutex);refs:=dispatch_group_locked(group).refs;C.pthread_mutex_unlock(dispatch_runtime.mutex);if refs==3{break};assert time.sys_mono_now()<deadline;time.sleep(time.millisecond)}
	}
	api.leave(group);api.enter(group);dg_wait(unsafe{&state.finished},1);worker.wait();assert api.wait_group(group,0)!=0;api.leave(group);api.release(group)
}
fn dg_main_and_ownership(api DGApi){
	group:=api.create();cls:=runtime_symbol('/usr/lib/libSystem.B.dylib','_OBJC_CLASS_$_OS_dispatch_group') or {panic(err)}
	assert read64(group)==cls&&objc_class_parent(cls)==ios_runtime.names['OS_dispatch_object']
	assert dispatch_objc_is_object(group)&&!swift_unknown_is_native(group)
	mut frame:=RegisterFrame{};assert dispatch_objc_dispatch(group,'retainCount',mut frame)&&frame.x[0]==1
	assert objc_retain(group)==group;swift_unknown_retain(group);assert dispatch_objc_dispatch(group,'retainCount',mut frame)&&frame.x[0]==3
	swift_unknown_release(group);objc_release(group);mut rejected:=false;dispatch_objc_allocation_checked(cls) or {assert err.msg().contains('dispatch factory');rejected=true};assert rejected
	mut state:=DGState{api:api,group:group};main_queue:=darwin_dispatch_get_main_queue()
	api.submit(group,main_queue,unsafe{&state},dg_count);api.notify(group,main_queue,unsafe{&state},dg_notify)
	assert api.wait_group(group,0)!=0&&state.called==0&&state.notified==0;assert dispatch_main_drain();assert state.called==1&&state.notified==0&&api.wait_group(group,0)==0;assert dispatch_main_drain()&&state.notified==1
	api.release(group)
}
fn dg_shutdown(api DGApi){
	member:=api.create();pending:=api.create();main_queue:=darwin_dispatch_get_main_queue();mut first:=DGState{api:api,group:member,retain_capture:true};mut second:=DGState{api:api,group:pending,retain_capture:true}
	descriptor:=[u64(0),u64(sizeof(DGLiteral)),u64(voidptr(dg_copy)),u64(voidptr(dg_dispose))]!
	literal1:=DGLiteral{isa:api.stack_isa,flags:u32(1)<<25,invoke:u64(voidptr(dg_block_call)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&first}}
	literal2:=DGLiteral{isa:api.stack_isa,flags:u32(1)<<25,invoke:u64(voidptr(dg_block_call)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&second}}
	api.submit_block(member,main_queue,u64(unsafe{&literal1}));api.enter(pending);api.notify_block(pending,main_queue,u64(unsafe{&literal2}));api.release(member);api.release(pending)
	objc_stop();assert first.called==0&&second.called==0&&first.copies==1&&second.copies==1&&first.disposed==1&&second.disposed==1
	assert member !in dispatch_runtime.groups&&dispatch_runtime.jobs.len==0&&dispatch_runtime.worker_count==0
	for _,group in dispatch_runtime.groups{assert group.head==unsafe{nil}&&group.tail==unsafe{nil}}
	system_data_stop();assert dispatch_runtime==unsafe{nil}
}
fn test_dispatch_group(){
	$if macos{native:=dg_api(true);dg_basic(native);dg_members(native);dg_blocks(native);dg_empty_notify(native);dg_generation(native)}
	for _ in 0..2{objc_start();system_data_start()!;api:=dg_api(false);dg_basic(api);dg_members(api);dg_blocks(api);dg_empty_notify(api);dg_generation(api);dg_main_and_ownership(api);dg_shutdown(api)}
	println('IOS-DISPATCH-GROUP: native typed function/stack/global block ABI, nested membership, 1024 concurrent submissions, monotonic/wall timeouts, notification queue ownership, copied capture disposal before completion, explicit-enter lifetime, generation reuse, main delivery, ObjC/Swift ownership and two drained cancellations passed')
}
