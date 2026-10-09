// SPDX-License-Identifier: GPL-2.0-or-later
// Independent host ordered-work engine assertions and worker task model.
@[translated]
@[has_globals]
module hostwork
#include "hostwork_v_contract.h"
struct C.work_struct {}
struct C.workqueue_struct {}
struct C.completion {}
fn C.ATOMIC_INIT(i32) C.atomic_t
fn C.atomic_inc_return(&C.atomic_t) i32
fn C.atomic_dec(&C.atomic_t)
fn C.atomic_read(&C.atomic_t) i32
fn C.calloc(usize,usize) voidptr
fn C.kzalloc(usize,u32) voidptr
fn C.kfree(voidptr)
fn C.init_completion(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.complete(&C.completion)
fn C.current_work() &C.work_struct
fn C.INIT_WORK_ONSTACK(&C.work_struct,fn (&C.work_struct))
fn C.__WORK_INITIALIZER(C.work_struct,fn (&C.work_struct)) C.work_struct
fn C.alloc_workqueue(&char,u32,i32,...) &C.workqueue_struct
fn C.alloc_ordered_workqueue(&char,u32,...) &C.workqueue_struct
fn C.queue_work(&C.workqueue_struct,&C.work_struct) bool
fn C.queue_work_on(i32,&C.workqueue_struct,&C.work_struct) bool
fn C.work_busy(&C.work_struct) u32
fn C.work_pending(&C.work_struct) bool
fn C.cancel_work(&C.work_struct) bool
fn C.cancel_work_sync(&C.work_struct) bool
fn C.flush_work(&C.work_struct) bool
fn C.flush_workqueue(&C.workqueue_struct)
fn C.drain_workqueue(&C.workqueue_struct)
fn C.destroy_workqueue(&C.workqueue_struct)
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_maskable_irq_depth() u32
fn C.vinix_linuxkpi_workqueue_draining_for_test(voidptr) bool
fn C.vmh_work_static_callback(&C.work_struct)
fn C.vmh_work_callback(&C.work_struct)
fn C.vmh_work_operation_thread(voidptr) voidptr
fn C.vmh_work_producer_thread(voidptr) voidptr
@[c_extern] __global (
 C.WORK_BUSY_RUNNING u32
 C.WQ_UNBOUND u32
 C.WQ_MEM_RECLAIM u32
 C.WQ_HIGHPRI u32
 C.WQ_FREEZABLE u32
 C.GFP_KERNEL u32
)
__global work_workers C.atomic_t
@[export:'vmh_work_workers_pointer']
pub fn work_workers_pointer() &C.atomic_t { unsafe { return &work_workers } }
@[cinit] __global (
 static_calls u32
 static_work C.work_struct = C.__WORK_INITIALIZER(static_work,C.vmh_work_static_callback)
)
@[export:'vinix_linuxkpi_host_worker_enter']
pub fn worker_enter() { unsafe {
 model:=&C.native_task_model(C.calloc(1,sizeof(C.native_task_model)))
 C.assert(model!=nil)
 index:=u32(C.atomic_inc_return(&work_workers))
 C.vmh_sync_model_init(model,index);model.heap_owned=true
 C.vmh_native_task=model;C.vmh_current_cpu=index%4
} }
@[export:'vinix_linuxkpi_host_worker_leave']
pub fn worker_leave() { unsafe {
 model:=C.vmh_native_task
 C.assert(model.pins==1 && C.vinix_linuxkpi_may_sleep())
 C.__atomic_store_n(&model.dead,true,3);C.vinix_linuxkpi_task_dead(&model.storage[0])
 C.atomic_dec(&work_workers);C.vmh_native_task=nil
} }
struct WorkTest { mut:
 work C.work_struct
 wq &C.workqueue_struct = unsafe { nil }
 other &C.workqueue_struct = unsafe { nil }
 gate C.completion
 calls u32
 entered u32
 active u32
 limit u32
 count &u32 = unsafe { nil }
 order &u32 = unsafe { nil }
 index u32
 hold bool
 requeue_first bool
 free_self bool
 irq_context_test bool
 candidate &WorkTest = unsafe { nil }
}
@[export:'vmh_work_static_callback']
pub fn static_callback(work &C.work_struct) { unsafe {
 C.assert(usize(C.current_work())==usize(work) && C.vinix_linuxkpi_may_sleep());static_calls++
} }
@[export:'vmh_work_callback']
pub fn callback(work &C.work_struct) { unsafe {
 test:=&WorkTest(work)
 C.assert(C.vinix_linuxkpi_may_sleep() && usize(C.current_work())==usize(work))
 C.assert(C.__atomic_fetch_add(&test.active,u32(1),4)==0)
 calls:=u32(C.__atomic_add_fetch(&test.calls,u32(1),4))
 if test.count!=nil {
  slot:=u32(C.__atomic_fetch_add(test.count,u32(1),4))
  if test.order!=nil { test.order[slot]=test.index }
 }
 if test.requeue_first && calls==1 { C.assert(C.queue_work(if test.other!=nil { test.other } else { test.wq },work)) }
 if test.hold && calls==1 {
  C.__atomic_store_n(&test.entered,u32(1),3);C.wait_for_completion(&test.gate)
 }
 if test.irq_context_test {
  C.assert(C.vinix_linuxkpi_workqueue_draining_for_test(test.wq))
  C.assert(test.candidate!=nil && C.work_busy(&test.candidate.work)==0)
  C.vinix_linuxkpi_preempt_disable()
  flags:=C.vinix_linuxkpi_irq_save()
  C.assert(usize(C.current_work())==usize(work))
  C.vmh_native_task.maskable_irq_depth=1
  C.assert(C.vinix_linuxkpi_maskable_irq_depth()==1 && C.current_work()==nil)
  C.assert(!C.queue_work(test.wq,&test.candidate.work) && C.work_busy(&test.candidate.work)==0)
  C.vinix_linuxkpi_irq_restore(flags)
  C.assert(C.current_work()==nil && !C.vinix_linuxkpi_may_sleep())
  C.vmh_native_task.maskable_irq_depth=0
  flags2:=C.vinix_linuxkpi_irq_save()
  C.assert(usize(C.current_work())==usize(work))
  C.assert(C.queue_work(test.wq,&test.candidate.work))
  C.vinix_linuxkpi_irq_restore(flags2)
  C.vinix_linuxkpi_preempt_enable()
  C.assert(usize(C.current_work())==usize(work) && C.vinix_linuxkpi_may_sleep())
 }
 if calls<test.limit && !(test.requeue_first && calls==1) { C.queue_work(test.wq,work) }
 C.sched_yield();C.assert(C.__atomic_fetch_sub(&test.active,u32(1),4)==1)
 if test.free_self { C.kfree(test) }
} }
fn work_init(test &WorkTest,wq &C.workqueue_struct) { unsafe {
 *test=WorkTest{wq:wq};C.INIT_WORK_ONSTACK(&test.work,C.vmh_work_callback);C.init_completion(&test.gate)
} }
fn await_counter(counter &u32) { for C.__atomic_load_n(counter,2)==0 { C.sched_yield() } }
enum Operation { work_flush queue_flush work_cancel queue_drain queue_destroy }
struct WorkOperation { mut:
 model C.native_task_model
 wq &C.workqueue_struct = unsafe { nil }
 work &C.work_struct = unsafe { nil }
 operation Operation
 thread C.pthread_t
 done u32
 result bool
}
@[export:'vmh_work_operation_thread']
pub fn operation_thread(argument voidptr) voidptr { unsafe {
 test:=&WorkOperation(argument);C.vmh_native_task=&test.model
 if test.operation==.work_flush { test.result=C.flush_work(test.work) }
 if test.operation==.work_cancel { test.result=C.cancel_work_sync(test.work) }
 if test.operation==.queue_flush { C.flush_workqueue(test.wq) }
 if test.operation==.queue_drain { C.drain_workqueue(test.wq) }
 if test.operation==.queue_destroy { C.destroy_workqueue(test.wq) }
 C.__atomic_store_n(&test.done,u32(1),3);C.vmh_native_task=nil;return nil
} }
fn operation_start(test &WorkOperation,operation Operation,wq &C.workqueue_struct,work &C.work_struct) { unsafe {
 *test=WorkOperation{operation:operation,wq:wq,work:work}
 C.vmh_sync_model_init(&test.model,30);test.model.iteration=1
 C.assert(C.pthread_create(&test.thread,nil,C.vmh_work_operation_thread,test)==0)
 for C.__atomic_load_n(&test.model.parked,2)==0 && C.__atomic_load_n(&test.done,2)==0 { C.sched_yield() }
} }
fn operation_join(test &WorkOperation) { unsafe {
 C.assert(C.pthread_join(test.thread,nil)==0 && test.done!=0);C.vmh_sync_model_destroy(&test.model)
} }
fn irq_identity_tests(wq &C.workqueue_struct) { unsafe {
 for round:=u32(0);round<20;round++ {
  mut held:=WorkTest{};mut candidate:=WorkTest{}
  work_init(&held,wq);work_init(&candidate,wq)
  held.hold=true;held.irq_context_test=true;held.candidate=&candidate
  C.assert(C.queue_work(wq,&held.work));await_counter(&held.entered)
  mut drain:=WorkOperation{};operation_start(&drain,.queue_drain,wq,nil)
  C.assert(C.vinix_linuxkpi_workqueue_draining_for_test(wq))
  C.complete(&held.gate);operation_join(&drain)
  C.assert(held.calls==1 && candidate.calls==1 && C.work_busy(&candidate.work)==0)
 }
} }
fn order_tests(wq &C.workqueue_struct) { unsafe {
 mut tests:=[32]WorkTest{};mut held:=WorkTest{};mut order:=[32]u32{};mut count:=u32(0)
 work_init(&held,wq);held.hold=true
 C.assert(C.queue_work(wq,&held.work));await_counter(&held.entered)
 C.assert(C.work_busy(&held.work)==C.WORK_BUSY_RUNNING)
 for i:=u32(0);i<32;i++ {
  work_init(&tests[i],wq);tests[i].count=&count;tests[i].order=&order[0];tests[i].index=i
  C.assert(C.queue_work(wq,&tests[i].work));C.assert(!C.queue_work(wq,&tests[i].work));C.assert(C.work_pending(&tests[i].work))
 }
 C.assert(C.cancel_work(&tests[7].work) && !C.cancel_work(&tests[7].work))
 C.complete(&held.gate);C.flush_workqueue(wq);C.assert(count==31 && tests[7].calls==0)
 for i:=u32(0);i<count;i++ { C.assert(order[i]==i+u32(i>=7)) }
 C.assert(!C.flush_work(&held.work) && C.current_work()==nil)
 work_init(&held,wq);held.limit=100;C.assert(C.queue_work(wq,&held.work));C.drain_workqueue(wq)
 C.assert(held.calls==100 && C.work_busy(&held.work)==0)
} }
fn flush_tests(wq &C.workqueue_struct) { unsafe {
 for mode:=u32(0);mode<3;mode++ {
  mut first:=WorkTest{};mut target:=WorkTest{};mut later:=WorkTest{}
  work_init(&first,wq);first.hold=true;work_init(&target,wq);work_init(&later,wq);later.hold=true
  C.assert(C.queue_work(wq,&first.work));await_counter(&first.entered);C.assert(C.queue_work(wq,&target.work))
  mut operation:=WorkOperation{}
  operation_start(&operation,if mode==1 { .queue_flush } else { .work_flush },wq,&target.work)
  C.assert(operation.done==0)
  if mode==2 { C.assert(C.cancel_work(&target.work)) }
  C.assert(C.queue_work(wq,&later.work));C.complete(&first.gate);await_counter(&later.entered)
  operation_join(&operation);C.assert(target.calls==u32(mode!=2) && (mode==1 || operation.result))
  C.complete(&later.gate);C.drain_workqueue(wq)
 }
 mut test:=WorkTest{};work_init(&test,wq);test.hold=true
 C.assert(C.queue_work(wq,&test.work));await_counter(&test.entered)
 mut operation:=WorkOperation{};operation_start(&operation,.work_flush,wq,&test.work)
 C.assert(operation.done==0);C.complete(&test.gate);operation_join(&operation);C.assert(operation.result)
} }
fn cancel_tests(wq &C.workqueue_struct) { unsafe {
 for requeue:=u32(0);requeue<2;requeue++ {
  mut test:=WorkTest{};work_init(&test,wq);test.hold=true;test.limit=10;test.requeue_first=requeue!=0
  C.assert(C.queue_work(wq,&test.work));await_counter(&test.entered)
  mut operation:=WorkOperation{};operation_start(&operation,.work_cancel,wq,&test.work)
  C.assert(operation.done==0 && !C.queue_work(wq,&test.work));C.complete(&test.gate);operation_join(&operation)
  C.assert(operation.result==(requeue!=0) && test.calls==1 && C.work_busy(&test.work)==0)
  C.assert(C.queue_work(wq,&test.work));C.drain_workqueue(wq);C.assert(test.calls==10)
 }
} }
struct Producer { mut:
 model C.native_task_model
 test &WorkTest = unsafe { nil }
 wq &C.workqueue_struct = unsafe { nil }
 accepted u32
 canceled u32
}
@[export:'vmh_work_producer_thread']
pub fn producer_thread(argument voidptr) voidptr { unsafe {
 producer:=&Producer(argument);C.vmh_native_task=&producer.model
 for i:=u32(0);i<1000;i++ {
  producer.accepted+=u32(C.queue_work(producer.wq,&producer.test.work))
  producer.canceled+=u32(C.cancel_work(&producer.test.work));C.sched_yield()
 }
 C.vmh_native_task=nil;return nil
} }
// Storing borrowed counters through a synchronous typed helper keeps native
// stack ownership visible to the V backend under -manualfree.
fn set_count(test &WorkTest,count &u32) { unsafe { test.count=count } }
@[export:'vmh_workqueue_tests']
pub fn workqueue_tests() { unsafe {
 mut parent:=C.native_task_model{};C.vmh_sync_model_init(&parent,20);C.vmh_native_task=&parent
 before:=C.vmh_live_pages
 bound:=C.alloc_workqueue(c'concurrent',u32(0),i32(0));C.assert(bound!=nil);C.destroy_workqueue(bound)
 unbound:=C.alloc_workqueue(c'unbound',C.WQ_UNBOUND,i32(8));C.assert(unbound!=nil);C.destroy_workqueue(unbound)
 C.assert(C.alloc_ordered_workqueue(c'reclaim',C.WQ_MEM_RECLAIM)==nil)
 priority:=C.alloc_ordered_workqueue(c'priority',C.WQ_HIGHPRI);C.assert(priority!=nil);C.destroy_workqueue(priority)
 C.assert(C.alloc_ordered_workqueue(c'freezer',C.WQ_FREEZABLE)==nil)
 C.vmh_fail_allocation=true;C.assert(C.alloc_ordered_workqueue(c'oom-%u',u32(0),u32(1))==nil);C.vmh_fail_allocation=false
 a:=C.alloc_ordered_workqueue(c'test-%u',u32(0),u32(1));b:=C.alloc_ordered_workqueue(c'test-%u',u32(0),u32(2));C.assert(a!=nil && b!=nil)
 warnings:=C.atomic_read(&C.vmh_time_warnings)
 C.assert(!C.queue_work_on(4,a,&static_work) && !C.work_pending(&static_work))
 C.assert(C.atomic_read(&C.vmh_time_warnings)==warnings+1)
 irq_flags:=C.vinix_linuxkpi_irq_save();C.assert(C.queue_work(a,&static_work) && !C.vmh_interrupts && C.vmh_preempt_depth==0)
 C.vinix_linuxkpi_irq_restore(irq_flags);C.flush_workqueue(a)
 C.assert(static_calls==1 && C.work_busy(&static_work)==0)
 order_tests(a);flush_tests(a);cancel_tests(a);irq_identity_tests(a)
 for destroy:=u32(0);destroy<2;destroy++ {
  wq:=if destroy!=0 { C.alloc_ordered_workqueue(c'destroy-held',u32(0)) } else { a };C.assert(wq!=nil)
  mut held:=WorkTest{};mut extra:=WorkTest{};work_init(&held,wq);held.hold=true;held.limit=8;work_init(&extra,wq)
  C.assert(C.queue_work(wq,&held.work));await_counter(&held.entered)
  mut operation:=WorkOperation{};operation_start(&operation,if destroy!=0 { .queue_destroy } else { .queue_drain },wq,nil)
  C.assert(operation.done==0 && !C.queue_work(wq,&extra.work));C.complete(&held.gate);operation_join(&operation)
  C.assert(held.calls==8 && C.work_busy(&held.work)==0)
  if destroy==0 { C.assert(C.queue_work(wq,&extra.work));C.flush_workqueue(wq);C.assert(extra.calls==1) }
 }
 mut cross:=WorkTest{};work_init(&cross,a);cross.other=b;cross.requeue_first=true;cross.hold=true
 C.assert(C.queue_work(a,&cross.work));await_counter(&cross.entered)
 mut flush:=WorkOperation{};operation_start(&flush,.work_flush,b,&cross.work)
 C.assert(flush.done==0 && cross.calls==1);C.complete(&cross.gate);operation_join(&flush)
 C.assert(flush.result && cross.calls==2 && cross.active==0)
 work_init(&cross,a);cross.other=b;cross.requeue_first=true;cross.hold=true
 C.assert(C.queue_work(a,&cross.work));await_counter(&cross.entered);operation_start(&flush,.work_flush,b,&cross.work)
 C.assert(flush.done==0);flush.model.iteration=2;C.assert(C.cancel_work(&cross.work));C.flush_workqueue(b)
 for C.__atomic_load_n(&flush.model.parked,2)!=2 && C.__atomic_load_n(&flush.done,2)==0 { C.sched_yield() }
 C.assert(flush.done==0 && C.work_busy(&cross.work)==C.WORK_BUSY_RUNNING)
 C.complete(&cross.gate);operation_join(&flush);C.assert(flush.result && cross.calls==1 && C.work_busy(&cross.work)==0)
 mut freed:=u32(0)
 for i:=u32(0);i<200;i++ {
  test:=&WorkTest(C.kzalloc(sizeof(WorkTest),C.GFP_KERNEL));C.assert(test!=nil)
  work_init(test,a);test.free_self=true;set_count(test,&freed);C.assert(C.queue_work(a,&test.work))
 }
 C.flush_workqueue(a);C.assert(freed==200)
 mut shared:=WorkTest{};work_init(&shared,a);mut producers:=[4]Producer{};mut threads:=[4]C.pthread_t{}
 for i:=u32(0);i<4;i++ {
  producers[i]=Producer{test:&shared,wq:if i&1!=0 { a } else { b }}
  C.vmh_sync_model_init(&producers[i].model,i+40)
  C.assert(C.pthread_create(&threads[i],nil,C.vmh_work_producer_thread,&producers[i])==0)
 }
 mut accepted:=u32(0);mut canceled:=u32(0)
 for i:=u32(0);i<4;i++ {
  C.assert(C.pthread_join(threads[i],nil)==0);accepted+=producers[i].accepted;canceled+=producers[i].canceled
  C.vmh_sync_model_destroy(&producers[i].model)
 }
 canceled+=u32(C.cancel_work_sync(&shared.work));C.assert(accepted==canceled+shared.calls && C.work_busy(&shared.work)==0)
 C.destroy_workqueue(a);C.destroy_workqueue(b)
 for i:=u32(0);i<50;i++ {
  wq:=C.alloc_ordered_workqueue(c'lifetime-%u',u32(0),i);C.assert(wq!=nil)
  mut test:=WorkTest{};work_init(&test,wq);test.limit=10;C.assert(C.queue_work(wq,&test.work));C.destroy_workqueue(wq)
  C.assert(test.calls==10 && C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 }
 C.assert(C.vmh_live_pages==before && parent.pins==0)
 C.vmh_native_task=nil;C.vmh_sync_model_destroy(&parent)
} }
