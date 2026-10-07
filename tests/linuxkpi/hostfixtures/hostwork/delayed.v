// SPDX-License-Identifier: GPL-2.0-or-later
// Original delayed reservations, timer-transfer gates and cancellation races.
@[translated]
@[has_globals]
module hostwork
#include "hostwork_v_contract.h"
struct C.timer_list { mut: expires usize }
struct C.delayed_work { mut: work C.work_struct timer C.timer_list wq &C.workqueue_struct }
fn C.__DELAYED_WORK_INITIALIZER(C.delayed_work,fn (&C.work_struct),u32) C.delayed_work
fn C.to_delayed_work(&C.work_struct) &C.delayed_work
fn C.INIT_DELAYED_WORK_ONSTACK(&C.delayed_work,fn (&C.work_struct))
fn C.queue_delayed_work(&C.workqueue_struct,&C.delayed_work,usize) bool
fn C.queue_delayed_work_on(i32,&C.workqueue_struct,&C.delayed_work,usize) bool
fn C.mod_delayed_work(&C.workqueue_struct,&C.delayed_work,usize) bool
fn C.mod_delayed_work_on(i32,&C.workqueue_struct,&C.delayed_work,usize) bool
fn C.cancel_delayed_work(&C.delayed_work) bool
fn C.cancel_delayed_work_sync(&C.delayed_work) bool
fn C.flush_delayed_work(&C.delayed_work) bool
fn C.delayed_work_pending(&C.delayed_work) bool
fn C.timer_pending(&C.timer_list) bool
fn C.vinix_linuxkpi_timer_dispatch() i32
fn C.vinix_linuxkpi_timer_active() usize
fn C.time_after_eq(usize,usize) bool
fn C.vmh_host_time_advance(C.vmh_u64)
fn C.vmh_delayed_callback(&C.work_struct)
fn C.vmh_static_delayed_callback(&C.work_struct)
fn C.vmh_delayed_operation_thread(voidptr) voidptr
fn C.vmh_delayed_producer_thread(voidptr) voidptr
fn C.vmh_delayed_dispatch_thread(voidptr) voidptr
@[c_extern] __global C.jiffies usize
@[c_extern] __global C.WORK_BUSY_PENDING u32
struct TimerGate { mut: timer &C.timer_list = unsafe { nil } entered u32 release u32 }
__global delayed_gate &TimerGate = unsafe { nil }
@[export:'vinix_linuxkpi_host_delayed_timer_gate']
pub fn timer_gate(timer &C.timer_list) { unsafe {
 gate:=&TimerGate(C.__atomic_load_n(&delayed_gate,2))
 if gate==nil || usize(gate.timer)!=usize(timer) { return }
 C.assert(!C.vmh_interrupts && C.vmh_preempt_depth!=0)
 C.__atomic_store_n(&gate.entered,u32(1),3)
 for C.__atomic_load_n(&gate.release,2)==0 { C.sched_yield() }
} }
struct DelayedTest { mut:
 work C.delayed_work
 wq &C.workqueue_struct = unsafe { nil }
 entered C.completion
 gate C.completion
 calls u32
 limit u32
 active u32
 freed &u32 = unsafe { nil }
 hold bool
 free_self bool
 requeue_first bool
 delay usize
 earliest usize
}
@[export:'vmh_delayed_callback']
pub fn delayed_callback(work &C.work_struct) { unsafe {
 test:=&DelayedTest(C.to_delayed_work(work))
 C.assert(C.vinix_linuxkpi_may_sleep() && usize(C.current_work())==usize(work))
 C.assert(C.__atomic_fetch_add(&test.active,u32(1),4)==0)
 C.assert(C.time_after_eq(C.jiffies,test.earliest))
 calls:=u32(C.__atomic_add_fetch(&test.calls,u32(1),4))
 if test.requeue_first && calls==1 { C.assert(C.queue_delayed_work(test.wq,&test.work,test.delay)) }
 if test.hold && calls==1 { C.complete(&test.entered);C.wait_for_completion(&test.gate) }
 if calls<test.limit && !(test.requeue_first && calls==1) { C.queue_delayed_work(test.wq,&test.work,test.delay) }
 C.sched_yield();C.assert(C.__atomic_fetch_sub(&test.active,u32(1),4)==1)
 if test.free_self { C.__atomic_fetch_add(test.freed,u32(1),3);C.kfree(test) }
} }
fn delayed_init(test &DelayedTest,wq &C.workqueue_struct) { unsafe {
 *test=DelayedTest{wq:wq,earliest:C.jiffies}
 C.INIT_DELAYED_WORK_ONSTACK(&test.work,C.vmh_delayed_callback)
 C.init_completion(&test.entered);C.init_completion(&test.gate)
} }
fn advance_time(ticks u64) { mut native:=C.vmh_u64{};unsafe { C.memcpy(&native,&ticks,8) };C.vmh_host_time_advance(native) }
fn advance_delayed(ticks u32) { advance_time(ticks);C.vinix_linuxkpi_timer_dispatch() }
@[cinit] __global (
 static_delayed_calls u32
 static_delayed C.delayed_work = C.__DELAYED_WORK_INITIALIZER(static_delayed,C.vmh_static_delayed_callback,u32(0))
)
@[export:'vmh_static_delayed_callback']
pub fn static_delayed_callback(work &C.work_struct) { unsafe { static_delayed_calls++ } }
enum DelayedMode { modify cancel cancel_sync flush }
struct DelayedOperation { mut:
 model C.native_task_model
 test &DelayedTest = unsafe { nil }
 wq &C.workqueue_struct = unsafe { nil }
 mode DelayedMode
 delay usize
 started u32
 spins u32
 done u32
 result bool
 irq_off bool
 thread C.pthread_t
}
@[export:'vmh_delayed_operation_thread']
pub fn delayed_operation_thread(argument voidptr) voidptr { unsafe {
 operation:=&DelayedOperation(argument);C.vmh_native_task=&operation.model
 flags:=if operation.irq_off { C.vinix_linuxkpi_irq_save() } else { usize(1)<<9 }
 C.vmh_timer_sync_spins=&operation.spins;C.__atomic_store_n(&operation.started,u32(1),3)
 if operation.mode==.modify { operation.result=C.mod_delayed_work(operation.wq,&operation.test.work,operation.delay) }
 if operation.mode==.cancel { operation.result=C.cancel_delayed_work(&operation.test.work) }
 if operation.mode==.cancel_sync { operation.result=C.cancel_delayed_work_sync(&operation.test.work) }
 if operation.mode==.flush { operation.result=C.flush_delayed_work(&operation.test.work) }
 C.assert(C.vmh_interrupts==!operation.irq_off && C.vmh_preempt_depth==0)
 if operation.irq_off { C.vinix_linuxkpi_irq_restore(flags) }
 C.vmh_timer_sync_spins=nil;C.__atomic_store_n(&operation.done,u32(1),3)
 C.vmh_native_task=nil;return nil
} }
fn delayed_operation_start(operation &DelayedOperation,mode DelayedMode,test &DelayedTest,wq &C.workqueue_struct,delay usize,irq_off bool) { unsafe {
 *operation=DelayedOperation{mode:mode,test:test,wq:wq,delay:delay,irq_off:irq_off}
 C.vmh_sync_model_init(&operation.model,80);operation.model.iteration=1
 C.assert(C.pthread_create(&operation.thread,nil,C.vmh_delayed_operation_thread,operation)==0)
 await_counter(&operation.started)
} }
fn delayed_operation_join(operation &DelayedOperation) { unsafe {
 C.assert(C.pthread_join(operation.thread,nil)==0 && operation.done!=0);C.vmh_sync_model_destroy(&operation.model)
} }
fn delayed_queue_tests(a &C.workqueue_struct,b &C.workqueue_struct) { unsafe {
 mut test:=DelayedTest{};delayed_init(&test,a)
 C.assert(!C.cancel_delayed_work(&test.work) && !C.cancel_delayed_work_sync(&test.work))
 C.assert(!C.flush_delayed_work(&test.work));C.assert(C.queue_delayed_work(a,&test.work,10))
 C.assert(!C.queue_delayed_work(a,&test.work,1))
 C.assert(C.delayed_work_pending(&test.work) && C.timer_pending(&test.work.timer))
 C.assert(C.work_busy(&test.work.work)==C.WORK_BUSY_PENDING)
 C.flush_workqueue(a);C.drain_workqueue(a);C.assert(test.calls==0 && C.delayed_work_pending(&test.work))
 advance_delayed(9);C.flush_workqueue(a);C.assert(test.calls==0)
 advance_delayed(1);C.flush_workqueue(a);C.assert(test.calls==1)
 C.assert(!C.timer_pending(&test.work.timer) && C.work_busy(&test.work.work)==0)
 C.assert(!C.mod_delayed_work(a,&test.work,20));expires:=test.work.timer.expires
 C.assert(C.mod_delayed_work(a,&test.work,40) && test.work.timer.expires==expires+20)
 C.assert(C.mod_delayed_work(b,&test.work,2) && usize(test.work.wq)==usize(b))
 advance_delayed(1);C.flush_workqueue(b);C.assert(test.calls==1)
 advance_delayed(1);C.flush_workqueue(b);C.assert(test.calls==2)
 C.assert(C.queue_delayed_work(a,&test.work,100));C.assert(C.mod_delayed_work(b,&test.work,0))
 C.flush_workqueue(b);C.assert(test.calls==3 && !C.timer_pending(&test.work.timer))
 mut held:=WorkTest{};work_init(&held,a);held.hold=true
 C.assert(C.queue_work(a,&held.work));await_counter(&held.entered)
 C.assert(C.queue_delayed_work(a,&test.work,0));C.assert(C.mod_delayed_work(b,&test.work,10))
 C.assert(C.cancel_delayed_work(&test.work) && !C.cancel_delayed_work(&test.work))
 C.assert(C.queue_delayed_work(a,&test.work,0));C.assert(C.cancel_delayed_work_sync(&test.work))
 C.complete(&held.gate);C.drain_workqueue(a);C.assert(test.calls==3)
 C.assert(C.queue_delayed_work(a,&test.work,1));advance_time(1)
 C.assert(C.cancel_delayed_work(&test.work));C.assert(C.vinix_linuxkpi_timer_dispatch()==0 && test.calls==3)
 C.assert(C.queue_delayed_work(a,&static_delayed,1));advance_delayed(1);C.flush_workqueue(a);C.assert(static_delayed_calls==1)
 C.assert(!C.cancel_delayed_work_sync(&static_delayed));delayed_init(&test,a)
 warnings:=C.atomic_read(&C.vmh_time_warnings)
 C.assert(!C.queue_delayed_work_on(4,a,&test.work,1));C.assert(!C.mod_delayed_work_on(4,a,&test.work,1))
 C.assert(C.atomic_read(&C.vmh_time_warnings)==warnings+2 && !C.delayed_work_pending(&test.work))
 flags:=C.vinix_linuxkpi_irq_save();C.assert(C.queue_delayed_work(a,&test.work,10))
 C.assert(C.mod_delayed_work(a,&test.work,5));C.assert(C.cancel_delayed_work(&test.work))
 C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==0);C.vinix_linuxkpi_irq_restore(flags)
} }
fn delayed_flush_tests(wq &C.workqueue_struct) { unsafe {
 mut test:=DelayedTest{};delayed_init(&test,wq);test.hold=true;test.limit=2;test.delay=100
 C.assert(C.queue_delayed_work(wq,&test.work,10000));mut operation:=DelayedOperation{}
 delayed_operation_start(&operation,.flush,&test,wq,0,false);C.wait_for_completion(&test.entered)
 C.assert(operation.done==0 && !C.timer_pending(&test.work.timer));C.complete(&test.gate);delayed_operation_join(&operation)
 C.assert(operation.result && test.calls==1)
 C.assert(C.timer_pending(&test.work.timer) && C.delayed_work_pending(&test.work));C.assert(C.cancel_delayed_work_sync(&test.work))
} }
fn delayed_cancel_tests(wq &C.workqueue_struct) { unsafe {
 for requeue:=u32(0);requeue<2;requeue++ {
  mut test:=DelayedTest{};delayed_init(&test,wq);test.hold=true;test.limit=2;test.delay=100;test.requeue_first=requeue!=0
  C.assert(C.queue_delayed_work(wq,&test.work,0));C.wait_for_completion(&test.entered)
  mut operation:=DelayedOperation{};delayed_operation_start(&operation,.cancel_sync,&test,wq,0,false)
  for C.__atomic_load_n(&operation.model.parked,2)==0 { C.sched_yield() }
  C.assert(operation.done==0 && !C.queue_delayed_work(wq,&test.work,1))
  C.assert(C.mod_delayed_work(wq,&test.work,1));C.complete(&test.gate);delayed_operation_join(&operation)
  C.assert(operation.result==(requeue!=0) && test.calls==1 && C.work_busy(&test.work.work)==0)
  C.assert(!C.timer_pending(&test.work.timer) && C.vinix_linuxkpi_timer_active()==0)
  C.assert(C.queue_delayed_work(wq,&test.work,1));advance_delayed(1);C.flush_workqueue(wq)
  C.assert(test.calls==2 && !C.cancel_delayed_work_sync(&test.work))
 }
} }
struct DelayedDispatch { mut: model C.native_task_model result i32 }
@[export:'vmh_delayed_dispatch_thread']
pub fn delayed_dispatch_thread(argument voidptr) voidptr { unsafe {
 dispatch:=&DelayedDispatch(argument);C.vmh_native_task=&dispatch.model
 dispatch.result=C.vinix_linuxkpi_timer_dispatch();C.vmh_native_task=nil;return nil
} }
fn delayed_transfer_tests(a &C.workqueue_struct,b &C.workqueue_struct) { unsafe {
 for mode:=u32(0);mode<4;mode++ {
  mut test:=DelayedTest{};delayed_init(&test,a);mut held:=WorkTest{};work_init(&held,a);held.hold=true
  C.assert(C.queue_work(a,&held.work));await_counter(&held.entered);C.assert(C.queue_delayed_work(a,&test.work,1));advance_time(1)
  mut gate:=TimerGate{timer:&test.work.timer};C.__atomic_store_n(&delayed_gate,&gate,3)
  mut dispatch:=DelayedDispatch{};C.vmh_sync_model_init(&dispatch.model,90)
  mut caller:=C.pthread_t{};C.assert(C.pthread_create(&caller,nil,C.vmh_delayed_dispatch_thread,&dispatch)==0)
  await_counter(&gate.entered);mut operation:=DelayedOperation{}
  delayed_operation_start(&operation,DelayedMode(mode),&test,b,10,mode<2)
  await_counter(&operation.spins);C.assert(operation.done==0)
  C.__atomic_store_n(&gate.release,u32(1),3)
  C.assert(C.pthread_join(caller,nil)==0 && dispatch.result==1)
  C.__atomic_store_n(&delayed_gate,voidptr(nil),3);C.vmh_sync_model_destroy(&dispatch.model)
  if mode==3 { for C.__atomic_load_n(&operation.model.parked,2)==0 { C.sched_yield() };C.assert(operation.done==0 && test.calls==0);C.complete(&held.gate) }
  delayed_operation_join(&operation);C.assert(operation.result && test.calls==u32(mode==3))
  if mode==0 {
   C.assert(usize(test.work.wq)==usize(b) && C.timer_pending(&test.work.timer))
   advance_delayed(9);C.flush_workqueue(b);C.assert(test.calls==0)
   advance_delayed(1);C.flush_workqueue(b);C.assert(test.calls==1)
  } else { C.assert(!C.delayed_work_pending(&test.work) && C.vinix_linuxkpi_timer_active()==0) }
  if mode!=3 { C.complete(&held.gate) };C.drain_workqueue(a);C.assert(!C.cancel_delayed_work_sync(&test.work))
 }
} }
struct DelayedProducer { mut: model C.native_task_model test &DelayedTest = unsafe { nil } wq &C.workqueue_struct = unsafe { nil } done u32 }
@[export:'vmh_delayed_producer_thread']
pub fn delayed_producer_thread(argument voidptr) voidptr { unsafe {
 producer:=&DelayedProducer(argument);C.vmh_native_task=&producer.model
 for i:=u32(0);i<500;i++ {
  flags:=if i&1!=0 { C.vinix_linuxkpi_irq_save() } else { usize(1)<<9 }
  if i%3==0 { C.queue_delayed_work(producer.wq,&producer.test.work,usize(i&3)) }
  if i%3==1 { C.mod_delayed_work(producer.wq,&producer.test.work,usize(i&3)) }
  if i%3==2 { C.cancel_delayed_work(&producer.test.work) }
  C.assert(C.vmh_interrupts==(i&1==0) && C.vmh_preempt_depth==0)
  if i&1!=0 { C.vinix_linuxkpi_irq_restore(flags) };C.sched_yield()
 }
 C.__atomic_store_n(&producer.done,u32(1),3);C.vmh_native_task=nil;return nil
} }
fn delayed_race_tests(a &C.workqueue_struct,b &C.workqueue_struct) { unsafe {
 mut shared:=DelayedTest{};delayed_init(&shared,a);mut producers:=[4]DelayedProducer{};mut threads:=[4]C.pthread_t{}
 for i:=u32(0);i<4;i++ { producers[i]=DelayedProducer{test:&shared,wq:if i&1!=0 { a } else { b }};C.vmh_sync_model_init(&producers[i].model,i+100);C.assert(C.pthread_create(&threads[i],nil,C.vmh_delayed_producer_thread,&producers[i])==0) }
 for { advance_delayed(1);mut finished:=u32(0);for i:=u32(0);i<4;i++ { finished+=u32(C.__atomic_load_n(&producers[i].done,2)) };C.sched_yield();if finished==4 { break } }
 for i:=u32(0);i<4;i++ { C.assert(C.pthread_join(threads[i],nil)==0);C.vmh_sync_model_destroy(&producers[i].model) }
 C.cancel_delayed_work_sync(&shared.work);C.flush_workqueue(a);C.flush_workqueue(b)
 C.assert(C.work_busy(&shared.work.work)==0 && shared.active==0 && C.vinix_linuxkpi_timer_active()==0)
 calls:=shared.calls;C.assert(C.queue_delayed_work(b,&shared.work,1));advance_delayed(1);C.flush_workqueue(b)
 C.assert(shared.calls==calls+1 && !C.cancel_delayed_work_sync(&shared.work))
} }
fn set_delayed_freed(test &DelayedTest,freed &u32) { unsafe { test.freed=freed } }
@[export:'vmh_delayed_work_tests']
pub fn delayed_work_tests() { unsafe {
 mut parent:=C.native_task_model{};C.vmh_sync_model_init(&parent,70);C.vmh_native_task=&parent;before:=C.vmh_live_pages
 a:=C.alloc_ordered_workqueue(c'delayed-a',u32(0));b:=C.alloc_ordered_workqueue(c'delayed-b',u32(0));C.assert(a!=nil && b!=nil)
 delayed_queue_tests(a,b);delayed_flush_tests(a);delayed_cancel_tests(a);delayed_transfer_tests(a,b);delayed_race_tests(a,b)
 mut freed:=u32(0)
 for i:=u32(0);i<200;i++ { test:=&DelayedTest(C.kzalloc(sizeof(DelayedTest),C.GFP_KERNEL));C.assert(test!=nil);delayed_init(test,a);test.free_self=true;set_delayed_freed(test,&freed);C.assert(C.queue_delayed_work(a,&test.work,1));advance_delayed(1);C.flush_workqueue(a);C.assert(C.vinix_linuxkpi_timer_active()==0) }
 C.assert(freed==200);C.destroy_workqueue(a);C.destroy_workqueue(b)
 C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 C.vmh_native_task=nil;C.vmh_sync_model_destroy(&parent)
} }
