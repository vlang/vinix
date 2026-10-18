// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
fn C.dlsym(voidptr,&char) voidptr
type DSSet = fn (u64,u64,voidptr,DispatchFunction)
type DSGet = fn (u64) voidptr
type DSDirect = fn (u64,u64) voidptr
type DSMake = fn (&char,u64) u64
type DSTarget = fn (&char,u64,u64) u64
type DSGlobal = fn (i64,u64) u64
type DSSync = fn (u64,voidptr,DispatchFunction)
type DSAsync = fn (u64,voidptr,DispatchFunction)
type DSRelease = fn (u64)
struct DSApi {
	native bool
	main_queue u64
	@[required] set DSSet
	@[required] get DSGet
	@[required] direct DSDirect
	@[required] make DSMake
	@[required] target DSTarget
	@[required] global DSGlobal
	@[required] sync_queue DSSync
	@[required] async_queue DSAsync
	@[required] release DSRelease
}
fn ds_api(native bool) DSApi {
	$if macos {if native{
		return DSApi{native:true,main_queue:u64(C.dlsym(voidptr(-2),c'_dispatch_main_q')),
			set:unsafe{DSSet(C.dlsym(voidptr(-2),c'dispatch_queue_set_specific'))},get:unsafe{DSGet(C.dlsym(voidptr(-2),c'dispatch_get_specific'))},direct:unsafe{DSDirect(C.dlsym(voidptr(-2),c'dispatch_queue_get_specific'))},make:unsafe{DSMake(C.dlsym(voidptr(-2),c'dispatch_queue_create'))},target:unsafe{DSTarget(C.dlsym(voidptr(-2),c'dispatch_queue_create_with_target$V2'))},global:unsafe{DSGlobal(C.dlsym(voidptr(-2),c'dispatch_get_global_queue'))},sync_queue:unsafe{DSSync(C.dlsym(voidptr(-2),c'dispatch_sync_f'))},async_queue:unsafe{DSAsync(C.dlsym(voidptr(-2),c'dispatch_async_f'))},release:unsafe{DSRelease(C.dlsym(voidptr(-2),c'dispatch_release'))}}
	}}
	return DSApi{main_queue:darwin_dispatch_get_main_queue(),set:unsafe{DSSet(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_dispatch_queue_set_specific') or {panic(err)}))},get:unsafe{DSGet(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_dispatch_get_specific') or {panic(err)}))},direct:unsafe{DSDirect(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_dispatch_queue_get_specific') or {panic(err)}))},make:darwin_dispatch_queue_create,target:darwin_dispatch_queue_create_with_target,global:darwin_dispatch_get_global_queue,sync_queue:darwin_dispatch_sync_f,async_queue:darwin_dispatch_async_f,release:darwin_dispatch_release}
}
struct DSProbe {
	api DSApi
	key u64
	expected u64
	nested u64
mut:
	calls int
}
fn ds_read(context voidptr){
	mut state:=unsafe{&DSProbe(context)}
	assert u64(state.api.get(state.key))==state.expected
	if state.nested!=0{
		mut inner:=DSProbe{api:state.api,key:state.key,expected:0x3344}
		state.api.sync_queue(state.nested,unsafe{&inner},ds_read);assert inner.calls==1
		assert u64(state.api.get(state.key))==state.expected
	}
	state.calls++
}
fn ds_check(api DSApi,queue u64,key u64,expected u64,nested u64){mut state:=DSProbe{api:api,key:key,expected:expected,nested:nested};api.sync_queue(queue,unsafe{&state},ds_read);assert state.calls==1}
fn ds_foreign(api DSApi,key u64){assert api.get(key)==unsafe{nil}}
fn ds_values(api DSApi,guard u64){
	parent:=api.make(c'vinix.specific.parent',0);child:=api.target(c'vinix.specific.child',0,parent);other:=api.make(c'vinix.specific.other',0)
	api.set(parent,guard,voidptr(0x1122),unsafe{nil});api.set(other,guard,voidptr(0x3344),unsafe{nil})
	assert u64(api.direct(parent,guard))==0x1122&&api.direct(child,guard)==unsafe{nil}&&api.get(guard)==unsafe{nil}
	ds_check(api,child,guard,0x1122,other)
	api.set(child,guard,voidptr(0x5566),unsafe{nil});ds_check(api,child,guard,0x5566,other)
	api.set(child,guard,unsafe{nil},unsafe{nil});ds_check(api,child,guard,0x1122,0)
	foreign:=spawn ds_foreign(api,guard);foreign.wait()
	for rounding in [i32(C.FE_TONEAREST),C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO]!{
		old:=C.fegetround();assert C.fesetround(rounding)==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO);flags:=C.fetestexcept(C.FE_ALL_EXCEPT)
		darwin_set_errno(42);api.set(child,guard+8,voidptr(0x1234),unsafe{nil});assert u64(api.direct(child,guard+8))==0x1234&&api.get(guard+8)==unsafe{nil}
		api.set(child,guard+8,unsafe{nil},unsafe{nil});assert C.fegetround()==rounding&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags
		if !api.native{assert unsafe{*C.ios_errno_address()}==42}
		assert C.fesetround(old)==0;C.feclearexcept(C.FE_ALL_EXCEPT)
	}
	api.set(api.main_queue,guard,voidptr(0x7788),unsafe{nil});assert u64(api.get(guard))==0x7788
	api.set(api.main_queue,guard,unsafe{nil},unsafe{nil})
	root:=api.global(0,0);api.set(root,guard,voidptr(0x99aa),unsafe{nil});assert u64(api.direct(root,guard))==0x99aa
	ds_check(api,root,guard,0x99aa,0)
	implicit:=api.make(c'vinix.specific.implicit',0);explicit:=api.target(c'vinix.specific.explicit',0,root)
	ds_check(api,implicit,guard,0,0);ds_check(api,explicit,guard,0x99aa,0)
	api.set(root,guard,unsafe{nil},unsafe{nil});api.release(implicit);api.release(explicit)
	api.release(child);api.release(parent);api.release(other)
}
struct DSRecord {
	api DSApi
	queue u64
	key u64
	creator u64
	shutdown bool
mut:
	calls i64
	observed u64
	started u64
	proceed u64
	finished u64
}
fn ds_count(record &DSRecord) u64{return C.ios_load_pointer(unsafe{&u64(&record.calls)})}
fn ds_reader(api DSApi,queue u64,key u64) u64{return u64(api.direct(queue,key))}
fn ds_destruct(context voidptr){
	mut state:=unsafe{&DSRecord(context)}
	assert state.api.get(state.key)==unsafe{nil}
	if !state.shutdown{assert u64(C.pthread_self())!=state.creator}
	if state.queue!=0{
		state.observed=u64(state.api.direct(state.queue,state.key))
		if !state.api.native{worker:=spawn ds_reader(state.api,state.queue,state.key);assert worker.wait()==state.observed}
	}
	C.ios_ref_change(unsafe{&state.calls},1)
}
fn ds_wait(record &DSRecord,count u64){deadline:=time.sys_mono_now()+5_000_000_000;for ds_count(record)!=count{assert time.sys_mono_now()<deadline;time.sleep(time.millisecond)}}
fn ds_blocking_job(context voidptr){
	mut state:=unsafe{&DSRecord(context)}
	assert state.api.get(state.key)==context
	C.ios_store_pointer(unsafe{&state.started},1)
	deadline:=time.sys_mono_now()+5_000_000_000
	for C.ios_load_pointer(unsafe{&state.proceed})==0{assert time.sys_mono_now()<deadline;time.sleep(time.millisecond)}
	assert state.api.get(state.key)==context
	C.ios_store_pointer(unsafe{&state.finished},1)
}
fn ds_lifetimes(api DSApi,guard u64){
	queue:=api.make(c'vinix.specific.lifetimes',0);creator:=u64(C.pthread_self())
	mut first:=DSRecord{api:api,queue:queue,key:guard,creator:creator};mut second:=DSRecord{api:api,queue:queue,key:guard,creator:creator}
	api.set(queue,0,unsafe{&first},ds_destruct);assert api.direct(queue,0)==unsafe{nil}&&api.get(0)==unsafe{nil}
	api.set(queue,guard,unsafe{&first},ds_destruct);api.set(queue,guard,unsafe{&second},ds_destruct);ds_wait(unsafe{&first},1)
	assert first.observed==u64(unsafe{&second})
	api.set(queue,guard,unsafe{nil},ds_destruct);ds_wait(unsafe{&second},1);assert second.observed==0
	api.set(queue,guard,unsafe{&first},ds_destruct);api.set(queue,guard,unsafe{&first},ds_destruct);ds_wait(unsafe{&first},2)
	api.set(queue,guard,unsafe{nil},unsafe{nil});ds_wait(unsafe{&first},3);api.release(queue)
	job_queue:=api.make(c'vinix.specific.pending-work',0);mut final:=DSRecord{api:api,key:guard,creator:creator}
	api.set(job_queue,guard,unsafe{&final},ds_destruct);api.async_queue(job_queue,unsafe{&final},ds_blocking_job)
	deadline:=time.sys_mono_now()+5_000_000_000;for C.ios_load_pointer(unsafe{&final.started})==0{assert time.sys_mono_now()<deadline;time.sleep(time.millisecond)}
	api.release(job_queue);assert ds_count(unsafe{&final})==0
	C.ios_store_pointer(unsafe{&final.proceed},1);ds_wait(unsafe{&final},1);assert C.ios_load_pointer(unsafe{&final.finished})==1
}
fn ds_worker(api DSApi,queue u64,key u64){for i in 1..65{api.set(queue,key,voidptr(i),unsafe{nil});assert u64(api.direct(queue,key))==u64(i);ds_check(api,queue,key,u64(i),0);api.set(queue,key,unsafe{nil},unsafe{nil})}}
fn ds_threads(api DSApi,guard u64){queue:=api.make(c'vinix.specific.shared',0);mut workers:=[]thread{cap:8};for i in 0..8{workers<<spawn ds_worker(api,queue,guard+u64(i*8))};workers.wait();unsafe{workers.free()};for i in 0..8{assert api.direct(queue,guard+u64(i*8))==unsafe{nil}};api.release(queue)}
fn ds_shutdown(api DSApi,guard u64){
	mut main_record:=DSRecord{api:api,key:guard,queue:api.main_queue,shutdown:true}
	mut root_record:=DSRecord{api:api,key:guard+8,queue:api.main_queue,shutdown:true}
	mut private_record:=DSRecord{api:api,key:guard+16,queue:api.main_queue,shutdown:true}
	mut pending:=DSRecord{api:api,key:guard+24,queue:api.main_queue,shutdown:true}
	root:=api.global(0,0);private:=api.make(c'vinix.specific.shutdown-owner',0)
	api.set(api.main_queue,guard,unsafe{&main_record},ds_destruct);api.set(root,guard+8,unsafe{&root_record},ds_destruct);api.set(private,guard+16,unsafe{&private_record},ds_destruct)
	// A future owned destructor exercises cancellation deterministically.
	mut entry:=unsafe{&DispatchSpecific(C.calloc(1,sizeof(DispatchSpecific)))};assert entry!=unsafe{nil};entry.context=unsafe{&pending};entry.destructor=ds_destruct
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut job:=dispatch_add_locked(dispatch_queue_locked(root),darwin_dispatch_time(0,60_000_000_000),0,entry,dispatch_specific_call,false);job.cleanup=dispatch_specific_cleanup
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	objc_stop();assert ds_count(unsafe{&pending})==1&&ds_count(unsafe{&main_record})==1&&ds_count(unsafe{&root_record})==1&&ds_count(unsafe{&private_record})==1
	for _,queue in dispatch_runtime.queues{assert queue.specific==unsafe{nil}}
	assert dispatch_runtime.jobs.len==0&&dispatch_runtime.worker_count==0
	for symbol in ['_dispatch_get_specific','_dispatch_queue_get_specific','_dispatch_queue_set_specific']!{mut rejected:=false;libsystem_symbol('/usr/lib/libobjc.A.dylib',symbol) or {rejected=true};assert rejected}
	system_data_stop();assert dispatch_runtime==unsafe{nil}
}
fn test_dispatch_specific(){
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
	$if macos{native:=ds_api(true);ds_values(native,guard);ds_lifetimes(native,guard);ds_threads(native,guard)}
	for _ in 0..2{objc_start();system_data_start()!;api:=ds_api(false);ds_values(api,guard);ds_lifetimes(api,guard);ds_threads(api,guard)
		child:=api.target(c'vinix.specific.main-child',0,api.main_queue);api.set(api.main_queue,guard,voidptr(0xabcd),unsafe{nil});mut probe:=DSProbe{api:api,key:guard,expected:0xabcd};api.async_queue(child,unsafe{&probe},ds_read);assert dispatch_main_drain()&&probe.calls==1&&u64(api.get(guard))==0xabcd;api.set(api.main_queue,guard,unsafe{nil},unsafe{nil});api.release(child)
		ds_shutdown(api,guard)
	}
	assert C.munmap(voidptr(guard),page)==0
	println('IOS-DISPATCH-SPECIFIC: native typed pointer-key ABI, target inheritance/override/removal, distinct implicit/global roots, main and foreign threads, nested TLS restoration, guarded keys/floating state/errno, asynchronous replacement and final-work destructors with unlocked queries, 1024 concurrent lifetimes, cancellation and two drained shutdowns passed')
}
