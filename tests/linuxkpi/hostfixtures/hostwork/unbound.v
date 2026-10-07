// SPDX-License-Identifier: GPL-2.0-or-later
// Independent unbound concurrency, publication and generation boundaries.
@[translated]
@[has_globals]
module hostwork
#include "hostwork_v_contract.h"
fn C.vinix_linuxkpi_workqueue_shutdown_for_test()
fn C.vinix_linuxkpi_workqueue_bootstrap() i32
fn C.vinix_linuxkpi_host_workqueue_stopped(&C.workqueue_struct) bool
fn C.vmh_unbound_nested_callback(&C.work_struct)
@[c_extern] __global C.system_unbound_wq &C.workqueue_struct
@[c_extern] __global C.ENOMEM i32
struct PublishGate { mut: wq &C.workqueue_struct = unsafe { nil } cpu u32 entered u32 release u32 }
__global publish_gate &PublishGate = unsafe { nil }
@[export:'vinix_linuxkpi_host_pool_publish_gate']
pub fn pool_publish_gate(wq &C.workqueue_struct,cpu u32) { unsafe {
 gate:=&PublishGate(C.__atomic_load_n(&publish_gate,2))
 if gate==nil || usize(gate.wq)!=usize(wq) || gate.cpu!=cpu { return }
 C.__atomic_store_n(&gate.entered,u32(1),3)
 for C.__atomic_load_n(&gate.release,2)==0 { C.sched_yield() }
} }
fn unbound_publish_destroy() { unsafe {
 wq:=C.alloc_workqueue(c'publish-destroy',C.WQ_UNBOUND,2);C.assert(wq!=nil)
 mut held:=WorkTest{};mut extra:=WorkTest{};work_init(&held,wq);held.hold=true;work_init(&extra,wq)
 C.assert(C.queue_work(wq,&held.work));await_counter(&held.entered)
 mut gate:=PublishGate{wq:wq};C.__atomic_store_n(&publish_gate,&gate,3)
 C.assert(C.queue_work(wq,&extra.work));await_counter(&gate.entered);await_counter(&extra.calls)
 for C.work_busy(&extra.work)!=0 { C.sched_yield() }
 mut destroy:=WorkOperation{};operation_start(&destroy,.queue_destroy,wq,nil);C.complete(&held.gate)
 for !C.vinix_linuxkpi_host_workqueue_stopped(wq) { C.sched_yield() };C.assert(destroy.done==0)
 C.__atomic_store_n(&gate.release,u32(1),3);operation_join(&destroy)
 C.__atomic_store_n(&publish_gate,voidptr(nil),3)
 C.assert(extra.calls==1 && held.calls==1 && C.atomic_read(&work_workers)==0)
} }
fn unbound_limit(limit u32) { unsafe {
 wq:=C.alloc_workqueue(c'limit-%u',C.WQ_UNBOUND,i32(limit),limit);C.assert(wq!=nil)
 mut held:=[4]WorkTest{};mut extra:=WorkTest{}
 for i:=u32(0);i<limit;i++ { work_init(&held[i],wq);held[i].hold=true;C.assert(C.queue_work(wq,&held[i].work)) }
 for i:=u32(0);i<limit;i++ { await_counter(&held[i].entered) }
 work_init(&extra,wq);C.assert(C.queue_work(wq,&extra.work));C.assert(C.work_busy(&extra.work)==C.WORK_BUSY_PENDING)
 C.assert(u32(C.atomic_read(&work_workers))==limit+u32(limit>1));C.complete(&held[0].gate)
 C.assert(C.flush_work(&extra.work) || extra.calls==1);C.assert(extra.calls==1 && extra.active==0)
 for i:=u32(1);i<limit;i++ { C.assert(C.work_busy(&held[i].work)==C.WORK_BUSY_RUNNING);C.complete(&held[i].gate) }
 C.destroy_workqueue(wq)
} }
fn unbound_flush(wq &C.workqueue_struct) { unsafe {
 mut old:=[2]WorkTest{};mut later:=WorkTest{}
 for i:=u32(0);i<2;i++ { work_init(&old[i],wq);old[i].hold=true;C.assert(C.queue_work(wq,&old[i].work));await_counter(&old[i].entered) }
 mut flush:=WorkOperation{};operation_start(&flush,.queue_flush,wq,nil);C.assert(flush.done==0)
 work_init(&later,wq);later.hold=true;C.assert(C.queue_work(wq,&later.work));await_counter(&later.entered)
 C.complete(&old[0].gate);C.assert(C.flush_work(&old[0].work) || old[0].calls==1);C.assert(flush.done==0)
 C.complete(&old[1].gate);operation_join(&flush);C.assert(C.work_busy(&later.work)==C.WORK_BUSY_RUNNING)
 C.complete(&later.gate);C.drain_workqueue(wq)
 work_init(&old[0],wq);old[0].hold=true;work_init(&old[1],wq);old[1].hold=true;work_init(&later,wq);later.hold=true
 C.assert(C.queue_work(wq,&old[0].work));await_counter(&old[0].entered);operation_start(&flush,.queue_flush,wq,nil)
 C.assert(C.queue_work(wq,&old[1].work));await_counter(&old[1].entered)
 mut second:=WorkOperation{};operation_start(&second,.queue_flush,wq,nil)
 C.assert(C.queue_work(wq,&later.work));await_counter(&later.entered)
 C.complete(&old[0].gate);operation_join(&flush);C.assert(second.done==0)
 C.complete(&old[1].gate);operation_join(&second);C.assert(C.work_busy(&later.work)==C.WORK_BUSY_RUNNING)
 C.complete(&later.gate);C.drain_workqueue(wq)
} }
struct UnboundNested { mut: work C.work_struct wq &C.workqueue_struct = unsafe { nil } target WorkTest done C.completion }
@[export:'vmh_unbound_nested_callback']
pub fn unbound_nested_callback(work &C.work_struct) { unsafe {
 nested:=&UnboundNested(work);C.assert(C.queue_work(nested.wq,&nested.target.work))
 C.assert(C.flush_work(&nested.target.work) || nested.target.calls==1)
 C.assert(nested.target.calls==1 && nested.target.active==0);C.complete(&nested.done)
} }
fn unbound_items(wq &C.workqueue_struct,other &C.workqueue_struct) { unsafe {
 mut nested:=UnboundNested{wq:wq};C.INIT_WORK_ONSTACK(&nested.work,C.vmh_unbound_nested_callback)
 work_init(&nested.target,wq);C.init_completion(&nested.done);C.assert(C.queue_work(wq,&nested.work))
 C.wait_for_completion(&nested.done);C.flush_workqueue(wq)
 mut shared:=WorkTest{};mut independent:=WorkTest{};work_init(&shared,other);shared.hold=true;shared.other=wq;shared.requeue_first=true
 C.assert(C.queue_work(other,&shared.work));await_counter(&shared.entered);work_init(&independent,wq)
 C.assert(C.queue_work(wq,&independent.work));C.assert(C.flush_work(&independent.work) || independent.calls==1)
 C.assert(shared.calls==1 && independent.calls==1);mut item_flush:=WorkOperation{}
 operation_start(&item_flush,.work_flush,wq,&shared.work);C.assert(item_flush.done==0);C.complete(&shared.gate)
 operation_join(&item_flush);C.assert(item_flush.result && shared.calls==2 && shared.active==0)
 C.drain_workqueue(other);C.drain_workqueue(wq)
} }
fn unbound_generations(wq &C.workqueue_struct,other &C.workqueue_struct) { unsafe {
 mut shared:=WorkTest{};mut later:=WorkTest{};work_init(&shared,other);shared.hold=true;shared.requeue_first=true;shared.other=wq
 C.assert(C.queue_work(other,&shared.work));await_counter(&shared.entered)
 mut flush:=WorkOperation{};operation_start(&flush,.queue_flush,wq,nil)
 work_init(&later,wq);later.hold=true;C.assert(C.queue_work(wq,&later.work));await_counter(&later.entered)
 C.assert(flush.done==0 && shared.calls==1);C.complete(&shared.gate);operation_join(&flush)
 C.assert(shared.calls==2 && shared.active==0);C.assert(C.work_busy(&later.work)==C.WORK_BUSY_RUNNING)
 C.complete(&later.gate);C.drain_workqueue(wq);C.drain_workqueue(other)
 mut held:=WorkTest{};work_init(&held,wq);held.hold=true;C.assert(C.queue_work(wq,&held.work));await_counter(&held.entered)
 mut flushes:=[20]WorkOperation{}
 for i:=u32(0);i<20;i++ { operation_start(&flushes[i],.queue_flush,wq,nil) }
 work_init(&later,wq);later.hold=true;C.assert(C.queue_work(wq,&later.work));await_counter(&later.entered);C.complete(&held.gate)
 for i:=u32(0);i<20;i++ { operation_join(&flushes[i]) }
 C.assert(C.work_busy(&later.work)==C.WORK_BUSY_RUNNING);C.complete(&later.gate);C.drain_workqueue(wq)
} }
@[export:'vmh_unbound_work_tests']
pub fn unbound_work_tests() { unsafe {
 mut parent:=C.native_task_model{};C.vmh_sync_model_init(&parent,120);C.vmh_native_task=&parent;before:=C.vmh_live_pages
 unbound_limit(1);unbound_limit(2);unbound_limit(4);unbound_publish_destroy()
 wq:=C.alloc_workqueue(c'parallel',C.WQ_UNBOUND,4);other:=C.alloc_ordered_workqueue(c'other',u32(0));C.assert(wq!=nil && other!=nil)
 unbound_flush(wq);unbound_items(wq,other);unbound_generations(wq,other)
 cancel_tests(wq);delayed_cancel_tests(wq);delayed_race_tests(wq,other)
 mut freed:=u32(0)
 for i:=u32(0);i<200;i++ { test:=&WorkTest(C.kzalloc(sizeof(WorkTest),C.GFP_KERNEL));C.assert(test!=nil);work_init(test,wq);test.free_self=true;set_count(test,&freed);C.assert(C.queue_work(wq,&test.work)) }
 C.flush_workqueue(wq);C.assert(freed==200);C.destroy_workqueue(wq);C.destroy_workqueue(other)
 C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 C.vmh_fail_allocation=true;C.assert(C.vinix_linuxkpi_workqueue_bootstrap()==-C.ENOMEM && C.system_unbound_wq==nil);C.vmh_fail_allocation=false
 C.assert(C.vinix_linuxkpi_workqueue_bootstrap()==0 && C.system_unbound_wq!=nil);system:=C.system_unbound_wq
 C.assert(C.vinix_linuxkpi_workqueue_bootstrap()==0 && usize(C.system_unbound_wq)==usize(system));unbound_flush(system)
 mut delayed:=DelayedTest{};delayed_init(&delayed,system);C.assert(C.queue_delayed_work(system,&delayed.work,10000))
 C.assert(C.flush_delayed_work(&delayed.work) && delayed.calls==1);C.assert(!C.cancel_delayed_work_sync(&delayed.work))
 C.vinix_linuxkpi_workqueue_shutdown_for_test();C.assert(C.system_unbound_wq==nil && C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 C.vmh_native_task=nil;C.vmh_sync_model_destroy(&parent)
} }
