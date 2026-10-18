// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
fn C.dlsym(voidptr,&char) voidptr
type STCreate = fn (u64,u64,u64,u64) u64
type STQueue = fn (&char,u64) u64
type STGlobal = fn (i64,u64) u64
type STControl = fn (u64)
type STContext = fn (u64,voidptr)
type STHandler = fn (u64,DispatchFunction)
type STBlock = fn (u64,u64)
type STTimer = fn (u64,u64,u64,u64)
type STRead = fn (u64) u64
type STCancel = fn (u64) i64
type STTime = fn (u64,i64) u64
type STWall = fn (&DispatchTimespec,i64) u64
type STSync = fn (u64,voidptr,DispatchFunction)
type STTarget = fn (u64,u64)
struct STApi {
	native bool
	kind u64
	stack u64
	@[required] create STCreate
	@[required] queue STQueue
	@[required] global STGlobal
	@[required] context STContext
	@[required] event STHandler
	@[required] cancel_handler STHandler
	@[required] event_block STBlock
	@[required] cancel_block STBlock
	@[required] timer STTimer
	@[required] resume STControl
	@[required] suspend STControl
	@[required] cancel STControl
	@[required] retain STControl
	@[required] release STControl
	@[required] finalizer STHandler
	@[required] data STRead
	@[required] testcancel STCancel
	@[required] deadline STTime
	@[required] wall STWall
	@[required] sync_queue STSync
	@[required] target STTarget
}
fn st_symbol(native bool,name string) voidptr {
	$if macos{if native{p:=C.dlsym(voidptr(-2),name.str);assert p!=unsafe{nil};return p}}
	return unsafe{voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_'+name) or {panic(err)})}
}
fn st_api(native bool) STApi {
	return STApi{native:native,kind:u64(st_symbol(native,'_dispatch_source_type_timer')),stack:if native{u64(C.dlsym(voidptr(-2),c'_NSConcreteStackBlock'))}else{block_isa(0)},create:unsafe{STCreate(st_symbol(native,'dispatch_source_create'))},queue:unsafe{STQueue(st_symbol(native,'dispatch_queue_create'))},global:unsafe{STGlobal(st_symbol(native,'dispatch_get_global_queue'))},context:unsafe{STContext(st_symbol(native,'dispatch_set_context'))},event:unsafe{STHandler(st_symbol(native,'dispatch_source_set_event_handler_f'))},cancel_handler:unsafe{STHandler(st_symbol(native,'dispatch_source_set_cancel_handler_f'))},event_block:unsafe{STBlock(st_symbol(native,'dispatch_source_set_event_handler'))},cancel_block:unsafe{STBlock(st_symbol(native,'dispatch_source_set_cancel_handler'))},timer:unsafe{STTimer(st_symbol(native,'dispatch_source_set_timer'))},resume:unsafe{STControl(st_symbol(native,'dispatch_resume'))},suspend:unsafe{STControl(st_symbol(native,'dispatch_suspend'))},cancel:unsafe{STControl(st_symbol(native,'dispatch_source_cancel'))},retain:unsafe{STControl(st_symbol(native,'dispatch_retain'))},release:unsafe{STControl(st_symbol(native,'dispatch_release'))},finalizer:unsafe{STHandler(st_symbol(native,'dispatch_set_finalizer_f'))},data:unsafe{STRead(st_symbol(native,'dispatch_source_get_data'))},testcancel:unsafe{STCancel(st_symbol(native,'dispatch_source_testcancel'))},deadline:unsafe{STTime(st_symbol(native,'dispatch_time'))},wall:unsafe{STWall(st_symbol(native,'dispatch_walltime'))},sync_queue:unsafe{STSync(st_symbol(native,'dispatch_sync_f'))},target:unsafe{STTarget(st_symbol(native,'dispatch_set_target_queue'))}}
}
struct STRecord {mut: events u64;cancelled u64;finalized u64;data u64;event_kind u64;cancel_kind u64;final_kind u64;started u64;proceed u64;inside i64;copies u64;disposed u64}
struct STState {api STApi;source u64;record &STRecord;kind u64;cancel_event bool;gate bool;capture u64}
struct STLiteral {isa u64;flags u32;reserved u32;invoke u64;descriptor u64;state &STState;cancel bool}
fn st_load(p &u64)u64{return C.ios_load_pointer(p)}
fn st_add(p &u64,delta i64){C.ios_ref_change(unsafe{&i64(p)},delta)}
fn st_wait(p &u64,value u64){limit:=time.sys_mono_now()+10_000_000_000;for st_load(p)!=value{assert time.sys_mono_now()<limit;time.sleep(time.millisecond)}}
fn st_positive(p &u64){limit:=time.sys_mono_now()+10_000_000_000;for st_load(p)==0{assert time.sys_mono_now()<limit;time.sleep(time.millisecond)}}
fn st_event(context voidptr){
	s:=unsafe{&STState(context)};r:=s.record;assert C.ios_ref_change(unsafe{&r.inside},1)==0
	data:=s.api.data(s.source);assert data>0;st_add(unsafe{&r.data},i64(data));C.ios_store_pointer(unsafe{&r.event_kind},s.kind)
	if s.gate{C.ios_store_pointer(unsafe{&r.started},1);st_wait(unsafe{&r.proceed},1);assert st_load(unsafe{&r.cancelled})==0}
	if s.cancel_event{s.api.cancel(s.source)}
	st_add(unsafe{&r.events},1);assert C.ios_ref_change(unsafe{&r.inside},-1)==1
}
fn st_cancelled(context voidptr){s:=unsafe{&STState(context)};r:=s.record;assert C.ios_ref_change(unsafe{&r.inside},0)==0&&s.api.testcancel(s.source)!=0;C.ios_store_pointer(unsafe{&r.cancel_kind},s.kind);st_add(unsafe{&r.cancelled},1)}
fn st_finalized(context voidptr){s:=unsafe{&STState(context)};r:=s.record;C.ios_store_pointer(unsafe{&r.final_kind},s.kind);st_add(unsafe{&r.finalized},1)}
fn st_nop(context voidptr){}
fn st_copy(dst u64,src u64){s:=unsafe{(&STLiteral(src)).state};st_add(unsafe{&s.record.copies},1);if s.capture!=0{s.api.retain(s.capture)}}
fn st_dispose(block u64){s:=unsafe{(&STLiteral(block)).state};if s.capture!=0{s.api.release(s.capture)};st_add(unsafe{&s.record.disposed},1)}
fn st_block(block u64){literal:=unsafe{&STLiteral(block)};if literal.cancel{st_cancelled(literal.state)}else{st_event(literal.state)}}
fn st_configure(api STApi,source u64,state &STState){api.context(source,state);api.event(source,st_event);api.cancel_handler(source,st_cancelled);api.finalizer(source,st_finalized)}
fn st_finish(api STApi,source u64,record &STRecord){st_wait(unsafe{&record.cancelled},1);api.release(source);st_wait(unsafe{&record.finalized},1)}
fn st_contexts(api STApi){
	queue:=api.queue(c'vinix.source.contexts',0);api.suspend(queue);source:=api.create(api.kind,0,0,queue);mut r:=STRecord{}
	first:=STState{api:api,source:source,record:unsafe{&r},kind:1,cancel_event:true};second:=STState{api:api,source:source,record:unsafe{&r},kind:2,cancel_event:true};third:=STState{api:api,source:source,record:unsafe{&r},kind:3,cancel_event:true}
	api.context(source,unsafe{&first});api.event(source,st_event);api.context(source,unsafe{&second});api.cancel_handler(source,st_cancelled);api.context(source,unsafe{&third});api.finalizer(source,st_finalized)
	api.timer(source,api.deadline(0,1_000_000),1_000_000,0);api.resume(source);time.sleep(20*time.millisecond);assert r.events==0;api.resume(queue);st_finish(api,source,unsafe{&r});assert r.events==1&&r.event_kind==3&&r.cancel_kind==3&&r.final_kind==3&&r.data>1
	installed:=api.create(api.kind,0,0,queue);mut t:=STRecord{};a:=STState{api:api,source:installed,record:unsafe{&t},kind:4,cancel_event:true};b:=STState{api:api,source:installed,record:unsafe{&t},kind:5};c:=STState{api:api,source:installed,record:unsafe{&t},kind:6}
	api.context(installed,unsafe{&a});api.event(installed,st_event);api.resume(installed);api.sync_queue(queue,unsafe{nil},st_nop)
	api.context(installed,unsafe{&b});api.cancel_handler(installed,st_cancelled);api.sync_queue(queue,unsafe{nil},st_nop);api.context(installed,unsafe{&c});api.finalizer(installed,st_finalized)
	api.timer(installed,0,~u64(0),0);st_finish(api,installed,unsafe{&t});assert t.events==1&&t.event_kind==4&&t.cancel_kind==6&&t.final_kind==6
	api.release(queue)
}
fn st_deadlines(api STApi){
	queue:=api.queue(c'vinix.source.clocks',0);source:=api.create(api.kind,0,1,queue);mut r:=STRecord{};state:=STState{api:api,source:source,record:unsafe{&r},kind:7};st_configure(api,source,unsafe{&state});api.timer(source,~u64(0),~u64(0),0);api.resume(source);api.sync_queue(queue,unsafe{nil},st_nop);time.sleep(5*time.millisecond);assert r.events==0
	api.timer(source,api.wall(unsafe{nil},2_000_000),~u64(0),0);st_wait(unsafe{&r.events},1);api.sync_queue(queue,unsafe{nil},st_nop);time.sleep(5*time.millisecond);assert r.events==1
	api.timer(source,api.deadline(0,2_000_000),~u64(0),0);st_wait(unsafe{&r.events},2);api.sync_queue(queue,unsafe{nil},st_nop)
	api.suspend(source);api.suspend(source);api.cancel(source);time.sleep(5*time.millisecond);assert r.cancelled==0;api.resume(source);time.sleep(5*time.millisecond);assert r.cancelled==0;api.resume(source);st_finish(api,source,unsafe{&r});assert r.events==2;api.release(queue)
}
fn st_running_update(api STApi){
	queue:=api.queue(c'vinix.source.update-running',0);source:=api.create(api.kind,0,0,queue);mut r:=STRecord{}
	first:=STState{api:api,source:source,record:unsafe{&r},kind:15,gate:true};second:=STState{api:api,source:source,record:unsafe{&r},kind:16,cancel_event:true}
	st_configure(api,source,unsafe{&first});api.timer(source,0,~u64(0),0);api.resume(source);st_wait(unsafe{&r.started},1)
	api.context(source,unsafe{&second});api.event(source,st_event);C.ios_store_pointer(unsafe{&r.proceed},1)
	// Setter application is asynchronous within the source. Keep the context
	// stable and repeat until the replacement observes an event and cancels.
	api.timer(source,api.deadline(0,1_000_000),1_000_000,0);st_finish(api,source,unsafe{&r});assert r.events>=2&&r.event_kind==16&&r.cancel_kind==16&&r.final_kind==16;api.release(queue)
}
fn st_running_cancel(api STApi){
	queue:=api.global(0,0);source:=api.create(api.kind,0,0,queue);mut r:=STRecord{};state:=STState{api:api,source:source,record:unsafe{&r},kind:8,gate:true};st_configure(api,source,unsafe{&state});api.timer(source,0,1_000_000,0);api.resume(source);st_wait(unsafe{&r.started},1)
	api.cancel(source);api.cancel(source);api.release(source);time.sleep(10*time.millisecond);assert r.cancelled==0&&r.finalized==0;C.ios_store_pointer(unsafe{&r.proceed},1);st_wait(unsafe{&r.cancelled},1);st_wait(unsafe{&r.finalized},1);assert r.events==1
	abandoned:=api.create(api.kind,0,0,0);mut a:=STRecord{};owner:=STState{api:api,source:abandoned,record:unsafe{&a},kind:9};st_configure(api,abandoned,unsafe{&owner});api.resume(abandoned);api.release(abandoned);st_wait(unsafe{&a.finalized},1);assert a.events==0&&a.cancelled==0
	early:=api.create(api.kind,0,0,queue);mut e:=STRecord{};early_owner:=STState{api:api,source:early,record:unsafe{&e},kind:10};st_configure(api,early,unsafe{&early_owner});api.cancel(early);time.sleep(5*time.millisecond);assert e.cancelled==0;api.resume(early);st_finish(api,early,unsafe{&e});assert e.events==0
}
fn st_blocks(api STApi){
	queue:=api.queue(c'vinix.source.blocks',0);source:=api.create(api.kind,0,0,queue);mut r:=STRecord{};state:=STState{api:api,source:source,record:unsafe{&r},kind:11,cancel_event:true,capture:source};old_state:=STState{api:api,source:source,record:unsafe{&r},kind:99,cancel_event:true,capture:source}
	descriptor:=[u64(0),u64(sizeof(STLiteral)),u64(voidptr(st_copy)),u64(voidptr(st_dispose))]!
	old:=STLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(st_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&old_state}}
	event:=STLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(st_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state}}
	cancel:=STLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(st_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&state},cancel:true}
	api.context(source,unsafe{&state});api.finalizer(source,st_finalized);api.event_block(source,u64(unsafe{&old}));api.event_block(source,u64(unsafe{&event}));api.cancel_block(source,u64(unsafe{&cancel}));assert r.copies==3
	api.timer(source,api.deadline(0,1_000_000),~u64(0),0);api.release(queue);api.resume(source);st_wait(unsafe{&r.cancelled},1);st_wait(unsafe{&r.disposed},3);api.release(source);st_wait(unsafe{&r.finalized},1);assert r.events==1&&r.event_kind==11
}
fn st_worker(api STApi){for _ in 0..16{source:=api.create(api.kind,0,0,api.global(0,0));mut r:=STRecord{};state:=STState{api:api,source:source,record:unsafe{&r},kind:12,cancel_event:true};st_configure(api,source,unsafe{&state});api.timer(source,0,~u64(0),0);api.resume(source);st_finish(api,source,unsafe{&r});assert r.events==1}}
fn st_threads(api STApi){mut workers:=[]thread{cap:8};for _ in 0..8{workers<<spawn st_worker(api)};workers.wait();unsafe{workers.free()}}
fn st_retarget_and_main(api STApi){
	queue:=api.queue(c'vinix.source.old',0);target:=api.queue(c'vinix.source.new',0);api.suspend(target);source:=api.create(api.kind,0,0,queue);api.target(source,target);api.release(queue);mut r:=STRecord{};state:=STState{api:api,source:source,record:unsafe{&r},kind:13,cancel_event:true};st_configure(api,source,unsafe{&state});api.timer(source,0,~u64(0),0);api.resume(source);time.sleep(5*time.millisecond);assert r.events==0;api.resume(target);st_finish(api,source,unsafe{&r});api.release(target)
	child:=api.queue(c'vinix.source.child',0);parent:=api.queue(c'vinix.source.parent',0);api.target(child,parent);api.suspend(parent);mut called:=u64(0);darwin_dispatch_async_f(child,unsafe{&called},st_queue_count);assert st_load(unsafe{&called})==0;api.resume(parent);api.sync_queue(child,unsafe{nil},st_nop);assert called==1;api.release(child);api.release(parent)
	main_source:=api.create(api.kind,0,0,darwin_dispatch_get_main_queue());cls:=runtime_symbol('/usr/lib/libSystem.B.dylib','_OBJC_CLASS_$_OS_dispatch_source') or {panic(err)};assert read64(main_source)==cls&&objc_class_size(cls)==8&&objc_class_parent(cls)==ios_runtime.names['OS_dispatch_object'];assert !swift_unknown_is_native(main_source)
	assert objc_retain(main_source)==main_source;swift_unknown_release(main_source);mut rejected:=false;dispatch_objc_allocation_checked(cls) or {rejected=true};assert rejected
	mut m:=STRecord{};owner:=STState{api:api,source:main_source,record:unsafe{&m},kind:14,cancel_event:true};st_configure(api,main_source,unsafe{&owner});api.timer(main_source,0,~u64(0),0);api.resume(main_source);assert m.events==0;assert dispatch_main_drain()&&m.events==1&&m.cancelled==0;assert dispatch_main_drain()&&m.cancelled==1;api.release(main_source);assert dispatch_main_drain()&&m.finalized==1
}
fn st_queue_count(p voidptr){C.ios_store_pointer(unsafe{&u64(p)},1)}
fn st_floating(api STApi){for rounding in [i32(C.FE_TONEAREST),C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO]!{old:=C.fegetround();assert C.fesetround(rounding)==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO);flags:=C.fetestexcept(C.FE_ALL_EXCEPT);darwin_set_errno(42);source:=api.create(api.kind,0,0,0);api.timer(source,~u64(0),~u64(0),0);assert api.testcancel(source)==0;api.cancel(source);api.resume(source);assert api.testcancel(source)!=0;assert C.fegetround()==rounding&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags;if !api.native{assert unsafe{*C.ios_errno_address()}==42};api.release(source);assert C.fesetround(old)==0;C.feclearexcept(C.FE_ALL_EXCEPT)}}
fn st_shutdown(api STApi){
	a:=api.create(api.kind,0,0,0);b:=api.create(api.kind,0,0,0);c:=api.create(api.kind,0,0,darwin_dispatch_get_main_queue());mut ra:=STRecord{};mut rb:=STRecord{};mut rc:=STRecord{}
	sa:=STState{api:api,source:a,record:unsafe{&ra},capture:b};sb:=STState{api:api,source:b,record:unsafe{&rb},capture:a};sc:=STState{api:api,source:c,record:unsafe{&rc},capture:c}
	descriptor:=[u64(0),u64(sizeof(STLiteral)),u64(voidptr(st_copy)),u64(voidptr(st_dispose))]!
	la:=STLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(st_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&sa}};lb:=STLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(st_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&sb}};lc:=STLiteral{isa:api.stack,flags:u32(1)<<25,invoke:u64(voidptr(st_block)),descriptor:u64(unsafe{&descriptor[0]}),state:unsafe{&sc}}
	api.event_block(a,u64(unsafe{&la}));api.event_block(b,u64(unsafe{&lb}));api.event_block(c,u64(unsafe{&lc}));api.timer(c,0,~u64(0),0);api.resume(c);api.release(a);api.release(b);api.release(c)
	objc_stop();assert ra.disposed==1&&rb.disposed==1&&rc.disposed==1&&ra.events==0&&rb.events==0&&rc.events==0;assert dispatch_runtime.jobs.len==0&&dispatch_runtime.worker_count==0;for _,source in dispatch_runtime.sources{assert source.event==unsafe{nil}&&source.cancel==unsafe{nil}&&source.updates==unsafe{nil}&&!source.work_pending};system_data_stop();assert dispatch_runtime==unsafe{nil}
}
fn test_dispatch_source(){
	$if macos{st_suite(st_api(true))}
	for _ in 0..2{objc_start();system_data_start()!;api:=st_api(false);st_suite(api);println('Source fixture: target/main');st_retarget_and_main(api);println('Source fixture: shutdown');st_shutdown(api)}
	println('IOS-DISPATCH-SOURCE: native timer ABI, deferred function contexts, one-shot/rearmed/wall deadlines, coalesced expirations, nested suspension, nonreentrant callbacks, explicit and implicit cancellation, copied handler replacement/capture ownership, 128 concurrent lifetimes, source/queue targets, main delivery, ObjC/Swift ownership, floating state and two drained shutdowns passed')
}
fn st_suite(api STApi){
	println('Source fixture native='+api.native.str()+': contexts');st_contexts(api)
	println('Source fixture: clocks/suspension');st_deadlines(api)
	println('Source fixture: running update');st_running_update(api)
	println('Source fixture: running cancellation');st_running_cancel(api)
	println('Source fixture: blocks');st_blocks(api)
	println('Source fixture: concurrent lifetimes');st_threads(api)
	println('Source fixture: floating state');st_floating(api)
}
