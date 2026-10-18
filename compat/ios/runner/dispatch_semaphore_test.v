// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import time
#include <dlfcn.h>
fn C.dlsym(voidptr,&char) voidptr
type DSCreate = fn(i64)u64
type DSWait = fn(u64,u64)i64
type DSSignal = fn(u64)i64
type DSControl = fn(u64)
type DSTime = fn(u64,i64)u64
type DSWall = fn(&DispatchTimespec,i64)u64
type DSContext = fn(u64,voidptr)
type DSGetContext = fn(u64)voidptr
type DSHandler = fn(u64,DispatchFunction)
type DSQueue = fn(&char,u64)u64
type DSBlock = fn(u64,u64)
type DSSync = fn(u64,voidptr,DispatchFunction)
type DSSource = fn(u64,u64,u64,u64)u64
type DSTimer = fn(u64,u64,u64,u64)
struct DSApi {
	native bool
	stack u64
	@[required] create DSCreate
	@[required] wait_sem DSWait
	@[required] signal DSSignal
	@[required] retain DSControl
	@[required] release DSControl
	@[required] deadline DSTime
	@[required] wall DSWall
	@[required] context DSContext
	@[required] get_context DSGetContext
	@[required] finalizer DSHandler
	@[required] queue DSQueue
	@[required] submit DSBlock
	@[required] sync_queue DSSync
}
fn ds_symbol(native bool,name string)voidptr{
	$if macos{if native{p:=C.dlsym(voidptr(-2),name.str);assert p!=unsafe{nil};return p}}
	return unsafe{voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_'+name) or {panic(err)})}
}
fn ds_api(native bool)DSApi{
	return DSApi{native:native,stack:if native{u64(ds_symbol(true,'_NSConcreteStackBlock'))}else{block_isa(0)},create:unsafe{DSCreate(ds_symbol(native,'dispatch_semaphore_create'))},wait_sem:unsafe{DSWait(ds_symbol(native,'dispatch_semaphore_wait'))},signal:unsafe{DSSignal(ds_symbol(native,'dispatch_semaphore_signal'))},retain:unsafe{DSControl(ds_symbol(native,'dispatch_retain'))},release:unsafe{DSControl(ds_symbol(native,'dispatch_release'))},deadline:unsafe{DSTime(ds_symbol(native,'dispatch_time'))},wall:unsafe{DSWall(ds_symbol(native,'dispatch_walltime'))},context:unsafe{DSContext(ds_symbol(native,'dispatch_set_context'))},get_context:unsafe{DSGetContext(ds_symbol(native,'dispatch_get_context'))},finalizer:unsafe{DSHandler(ds_symbol(native,'dispatch_set_finalizer_f'))},queue:unsafe{DSQueue(ds_symbol(native,'dispatch_queue_create'))},submit:unsafe{DSBlock(ds_symbol(native,'dispatch_async'))},sync_queue:unsafe{DSSync(ds_symbol(native,'dispatch_sync_f'))}}
}
struct DSState {
	api DSApi
	semaphore u64
	deadline u64 = ~u64(0)
mut:
	started u64
	finished u64
	result u64
	inside i64
	completed u64
	copies u64
	disposed u64
	finalized u64
}
struct DSLiteral {isa u64;flags u32;reserved u32;invoke u64;descriptor u64;state &DSState}
fn ds_load(p &u64)u64{return C.ios_load_pointer(p)}
fn ds_add(p &u64){C.ios_ref_change(unsafe{&i64(p)},1)}
fn ds_until(p &u64,value u64){limit:=time.sys_mono_now()+10_000_000_000;for ds_load(p)!=value{assert time.sys_mono_now()<limit;time.sleep(time.millisecond)}}
fn ds_waiter(state &DSState){ds_add(unsafe{&state.started});result:=state.api.wait_sem(state.semaphore,state.deadline);C.ios_store_pointer(unsafe{&state.result},u64(result)+1);ds_add(unsafe{&state.finished})}
fn ds_parked(api DSApi,semaphore u64,count u64){
	if api.native{time.sleep(20*time.millisecond);return}
	limit:=time.sys_mono_now()+10_000_000_000
	for{C.pthread_mutex_lock(dispatch_runtime.mutex);actual:=dispatch_semaphore_locked(semaphore).waiters;C.pthread_mutex_unlock(dispatch_runtime.mutex);if actual==count{return};assert time.sys_mono_now()<limit;time.sleep(time.millisecond)}
}
fn ds_finalized(context voidptr){state:=unsafe{&DSState(context)};ds_add(unsafe{&state.finalized})}
fn ds_nop(context voidptr){}
fn ds_basic(api DSApi){
	assert api.create(-1)==0
	for rounding in [i32(C.FE_TONEAREST),C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO]!{
		old:=C.fegetround();assert C.fesetround(rounding)==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO);flags:=C.fetestexcept(C.FE_ALL_EXCEPT);darwin_set_errno(42)
		semaphore:=api.create(2);assert semaphore!=0&&api.wait_sem(semaphore,api.deadline(0,-1))==0&&api.wait_sem(semaphore,0)==0
		assert api.wait_sem(semaphore,0)==49&&api.wait_sem(semaphore,api.deadline(0,-1))==49
		start:=time.sys_mono_now();assert api.wait_sem(semaphore,api.deadline(0,2_000_000))==49;assert time.sys_mono_now()-start>=1_000_000
		assert api.wait_sem(semaphore,api.wall(unsafe{nil},1_000_000))==49
		assert api.signal(semaphore)==0&&api.wait_sem(semaphore,0)==0
		assert api.signal(semaphore)==0&&api.signal(semaphore)==0;api.release(semaphore)
		assert C.fegetround()==rounding&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags
		if !api.native{assert unsafe{*C.ios_errno_address()}==42}
		assert C.fesetround(old)==0;C.feclearexcept(C.FE_ALL_EXCEPT)
	}
	large:=api.create(i64(0x7fff_ffff_ffff_ffff));assert large!=0;api.release(large)
}
fn ds_wake(api DSApi){
	semaphore:=api.create(0);mut state:=DSState{api:api,semaphore:semaphore};mut workers:=[]thread{cap:8}
	for _ in 0..8{workers<<spawn ds_waiter(unsafe{&state})};ds_until(unsafe{&state.started},8);ds_parked(api,semaphore,8)
	assert api.signal(semaphore)!=0;ds_until(unsafe{&state.finished},1);assert api.wait_sem(semaphore,0)==49
	for _ in 0..7{assert api.signal(semaphore)!=0};workers.wait();unsafe{workers.free()};assert state.finished==8&&state.result==1&&api.wait_sem(semaphore,0)==49
	api.release(semaphore)
}
fn ds_pool_worker(state &DSState){
	for _ in 0..256{
		assert state.api.wait_sem(state.semaphore,state.api.deadline(0,10_000_000_000))==0
		inside:=C.ios_ref_change(unsafe{&state.inside},1);assert inside>=0&&inside<3
		ds_add(unsafe{&state.completed});assert C.ios_ref_change(unsafe{&state.inside},-1)>0
		state.api.signal(state.semaphore)
	}
}
fn ds_pool(api DSApi){
	semaphore:=api.create(3);mut state:=DSState{api:api,semaphore:semaphore};mut workers:=[]thread{cap:8};for _ in 0..8{workers<<spawn ds_pool_worker(unsafe{&state})};workers.wait();unsafe{workers.free()}
	assert state.completed==2048&&state.inside==0
	for _ in 0..3{assert api.wait_sem(semaphore,0)==0};assert api.wait_sem(semaphore,0)==49;for _ in 0..3{assert api.signal(semaphore)==0};api.release(semaphore)
}
fn ds_timeout_race(api DSApi){
	for i in 0..64{
		semaphore:=api.create(0);mut state:=DSState{api:api,semaphore:semaphore,deadline:api.deadline(0,1_000_000)};worker:=spawn ds_waiter(unsafe{&state});if i%2!=0{time.sleep(2*time.millisecond)};api.signal(semaphore);worker.wait()
		if state.result==50{assert api.wait_sem(semaphore,0)==0}else{assert state.result==1};assert api.wait_sem(semaphore,0)==49;api.release(semaphore)
	}
}
fn ds_copy(dst u64,src u64){state:=unsafe{(&DSLiteral(src)).state};state.api.retain(state.semaphore);ds_add(unsafe{&state.copies})}
fn ds_dispose(block u64){state:=unsafe{(&DSLiteral(block)).state};state.api.release(state.semaphore);ds_add(unsafe{&state.disposed})}
fn ds_block(block u64){state:=unsafe{(&DSLiteral(block)).state};state.api.signal(state.semaphore)}
fn ds_blocks(api DSApi){
	semaphore:=api.create(0);queue:=api.queue(c'vinix.semaphore.capture',0);mut state:=DSState{api:api,semaphore:semaphore};api.context(semaphore,unsafe{&state});assert api.get_context(semaphore)==unsafe{&state};api.finalizer(semaphore,ds_finalized)
	descriptor:=[u64(0),u64(sizeof(DSLiteral)),u64(voidptr(ds_copy)),u64(voidptr(ds_dispose))]!
	literal:=DSLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(ds_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state}}
	api.submit(queue,u64(unsafe{&literal}));assert api.wait_sem(semaphore,api.deadline(0,10_000_000_000))==0;api.sync_queue(queue,unsafe{nil},ds_nop);assert state.copies==1&&state.disposed==1&&state.finalized==0
	api.retain(semaphore);api.release(semaphore);assert state.finalized==0;api.release(semaphore);ds_until(unsafe{&state.finalized},1);api.release(queue)
}
struct DSTimerState {api DSApi;source u64;semaphore u64;@[required] cancel DSControl}
fn ds_timer_event(context voidptr){state:=unsafe{&DSTimerState(context)};state.cancel(state.source);state.api.signal(state.semaphore)}
fn ds_timer(api DSApi){
	queue:=api.queue(c'vinix.semaphore.timer',0);semaphore:=api.create(0)
	create:=unsafe{DSSource(ds_symbol(api.native,'dispatch_source_create'))};source:=create(u64(ds_symbol(api.native,'_dispatch_source_type_timer')),0,0,queue)
	state:=DSTimerState{api:api,source:source,semaphore:semaphore,cancel:unsafe{DSControl(ds_symbol(api.native,'dispatch_source_cancel'))}}
	api.context(source,unsafe{&state});unsafe{DSHandler(ds_symbol(api.native,'dispatch_source_set_event_handler_f'))(source,ds_timer_event)}
	unsafe{DSTimer(ds_symbol(api.native,'dispatch_source_set_timer'))(source,api.deadline(0,2_000_000),~u64(0),0)};unsafe{DSControl(ds_symbol(api.native,'dispatch_resume'))(source)}
	assert api.wait_sem(semaphore,api.deadline(0,10_000_000_000))==0;api.sync_queue(queue,unsafe{nil},ds_nop);api.release(source);api.release(semaphore);api.release(queue)
}
fn ds_ownership(api DSApi){
	semaphore:=api.create(0);cls:=runtime_symbol('/usr/lib/libSystem.B.dylib','_OBJC_CLASS_$_OS_dispatch_semaphore') or {panic(err)}
	assert read64(semaphore)==cls&&objc_class_size(cls)==8&&objc_class_parent(cls)==ios_runtime.names['OS_dispatch_object']
	assert dispatch_objc_is_object(semaphore)&&!swift_unknown_is_native(semaphore)
	mut frame:=RegisterFrame{};assert dispatch_objc_dispatch(semaphore,'retainCount',mut frame)&&frame.x[0]==1;assert objc_retain(semaphore)==semaphore;swift_unknown_retain(semaphore)
	assert dispatch_objc_dispatch(semaphore,'retainCount',mut frame)&&frame.x[0]==3;swift_unknown_release(semaphore);objc_release(semaphore)
	pool:=objc_pool_push();objc_autorelease(objc_retain(semaphore));objc_pool_pop(pool);assert dispatch_objc_dispatch(semaphore,'retainCount',mut frame)&&frame.x[0]==1
	mut rejected:=false;dispatch_objc_allocation_checked(cls) or {assert err.msg().contains('dispatch factory');rejected=true};assert rejected;api.release(semaphore);assert dispatch_objc_view(semaphore)==none
	for symbol in ['_dispatch_semaphore_create','_dispatch_semaphore_wait','_dispatch_semaphore_signal']!{mut wrong:=false;libsystem_symbol('/usr/lib/libobjc.A.dylib',symbol) or {wrong=true};assert wrong}
}
fn ds_shutdown(api DSApi){
	semaphore:=api.create(0);mut state:=DSState{api:api,semaphore:semaphore};descriptor:=[u64(0),u64(sizeof(DSLiteral)),u64(voidptr(ds_copy)),u64(voidptr(ds_dispose))]!
	literal:=DSLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(ds_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state}}
	api.submit(darwin_dispatch_get_main_queue(),u64(unsafe{&literal}));api.release(semaphore);remaining:=api.create(3)
	objc_stop();assert state.copies==1&&state.disposed==1&&semaphore !in dispatch_runtime.semaphores&&remaining in dispatch_runtime.semaphores
	assert dispatch_runtime.jobs.len==0&&dispatch_runtime.worker_count==0;system_data_stop();assert dispatch_runtime==unsafe{nil}
}
fn ds_suite(api DSApi){ds_basic(api);ds_wake(api);ds_pool(api);ds_timeout_race(api);ds_blocks(api);ds_timer(api)}
fn test_dispatch_semaphore(){
	if os.args.len==2&&os.args[1]=='semaphore-unbalanced'{objc_start();system_data_start()!;semaphore:=darwin_dispatch_semaphore_create(1);assert darwin_dispatch_semaphore_wait(semaphore,0)==0;darwin_dispatch_release(semaphore);panic('unbalanced release unexpectedly returned')}
	$if macos{ds_suite(ds_api(true))}
	for cycle in 0..2{
		if cycle==0{objc_start();system_data_start()!}else{
			system_data_start()!;early:=darwin_dispatch_semaphore_create(0);assert read64(early)==0;objc_start()
			assert read64(early)==ios_runtime.names['OS_dispatch_semaphore'];objc_release(early)
		}
		api:=ds_api(false);ds_suite(api);ds_ownership(api);ds_shutdown(api)
	}
	mut child:=os.new_process(os.executable());child.set_args(['semaphore-unbalanced']);child.set_redirect_stdio_merged();child.run();log:=child.stdout_slurp();child.wait();status:=child.code;child.close()
	assert status!=0&&log.contains('dispatch semaphore destroyed while in use')&&!log.contains('ERROR: AddressSanitizer')&&!log.contains('runtime error:')&&!log.contains('unexpectedly returned'),log
	println('IOS-DISPATCH-SEMAPHORE: native count/null ABI, one grant per blocked waiter, 2048 bounded-pool handoffs, 64 timeout races, monotonic/wall deadlines, copied block captures, timer callback signaling, balanced finalizer, ObjC/Swift ownership, floating state, unbalanced-release diagnosis and two drained shutdowns passed')
}
