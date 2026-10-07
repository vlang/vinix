// SPDX-License-Identifier: GPL-2.0-or-later
// Independent per-CPU routing, runnable-worker and priority assertions.
@[translated]
@[has_globals]
module hostwork
#include "hostwork_v_contract.h"
fn C.vinix_linuxkpi_worker_nice() i32
fn C.vinix_linuxkpi_worker_timeslice() u32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.schedule_work(&C.work_struct) bool
fn C.schedule_work_on(i32,&C.work_struct) bool
fn C.vmh_bound_callback(&C.work_struct)
fn C.vmh_bound_delayed_callback(&C.work_struct)
fn C.vmh_bound_irq_cpu_switch()
@[c_extern] __global C.system_wq &C.workqueue_struct
@[c_extern] __global C.system_highpri_wq &C.workqueue_struct
struct BoundCase { mut:
 work C.work_struct
 gate C.completion
 expected_cpu [4]u32
 observed_cpu [4]u32
 calls u32
 entered u32
 active u32
 request_sleep u32
 freed &u32 = unsafe { nil }
 expected_nice i32
 hold_first bool
 spin_first bool
 free_self bool
 check_cpu bool
}
@[export:'vmh_bound_callback']
pub fn bound_callback(work &C.work_struct) { unsafe {
 test:=&BoundCase(work)
 C.assert(usize(C.current_work())==usize(work) && C.vinix_linuxkpi_may_sleep())
 C.assert(C.__atomic_fetch_add(&test.active,u32(1),4)==0)
 call:=u32(C.__atomic_fetch_add(&test.calls,u32(1),4));C.assert(call<4)
 C.assert(C.vinix_linuxkpi_worker_nice()==test.expected_nice)
 C.assert(C.vinix_linuxkpi_worker_timeslice()==if test.expected_nice<0 { u32(10000) } else { u32(5000) })
 test.observed_cpu[call]=C.vinix_linuxkpi_cpu_id()
 C.assert(!test.check_cpu || test.observed_cpu[call]==test.expected_cpu[call])
 C.sched_yield();C.assert(!test.check_cpu || C.vinix_linuxkpi_cpu_id()==test.expected_cpu[call])
 if call==0 {
  C.__atomic_store_n(&test.entered,u32(1),3)
  if test.spin_first { for C.__atomic_load_n(&test.request_sleep,2)==0 { C.sched_yield() } }
  if test.hold_first { C.wait_for_completion(&test.gate) }
  C.assert(!test.check_cpu || C.vinix_linuxkpi_cpu_id()==test.expected_cpu[call])
  C.assert(C.vinix_linuxkpi_worker_nice()==test.expected_nice)
 }
 C.assert(C.__atomic_fetch_sub(&test.active,u32(1),4)==1)
 if test.free_self { C.__atomic_fetch_add(test.freed,u32(1),3);C.kfree(test) }
} }
fn bound_init(test &BoundCase,cpu u32) { unsafe {
 *test=BoundCase{check_cpu:true};for i:=u32(0);i<4;i++ { test.expected_cpu[i]=cpu }
 C.INIT_WORK_ONSTACK(&test.work,C.vmh_bound_callback);C.init_completion(&test.gate)
} }
@[export:'vmh_bound_irq_cpu_switch']
pub fn bound_irq_cpu_switch() { unsafe { C.vmh_current_cpu=(C.vmh_current_cpu+1)%4 } }
fn bound_routing() { unsafe {
 wq:=C.alloc_workqueue(c'bound-route',u32(0),1);C.assert(wq!=nil)
 for cpu:=u32(0);cpu<4;cpu++ {
  mut test:=BoundCase{};bound_init(&test,cpu);C.vmh_current_cpu=(cpu+1)%4
  flags:=C.vinix_linuxkpi_irq_save();C.assert(C.queue_work_on(i32(cpu),wq,&test.work))
  C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==0);C.vinix_linuxkpi_irq_restore(flags)
  C.flush_workqueue(wq);C.assert(test.calls==1 && C.work_busy(&test.work)==0)
 }
 mut local:=BoundCase{};bound_init(&local,2);C.vmh_current_cpu=2
 C.vmh_host_irq_restore_hook=C.vmh_bound_irq_cpu_switch;C.assert(C.queue_work(wq,&local.work))
 C.assert(C.vmh_current_cpu==3 && C.vmh_host_irq_restore_hook==unsafe { nil })
 C.flush_workqueue(wq);C.assert(local.calls==1 && local.observed_cpu[0]==2)
 bound_init(&local,1);C.vmh_current_cpu=1;flags:=C.vinix_linuxkpi_irq_save()
 C.assert(C.queue_work(wq,&local.work));C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==0)
 C.vinix_linuxkpi_irq_restore(flags);C.flush_workqueue(wq);C.assert(local.calls==1)
 bound_init(&local,0);C.assert(!C.queue_work_on(4,wq,&local.work));C.assert(!C.queue_work_on(-1,wq,&local.work))
 C.assert(!C.work_pending(&local.work));C.destroy_workqueue(wq)
} }
fn bound_limit(limit u32) { unsafe {
 wq:=C.alloc_workqueue(c'bound-limit-%u',u32(0),i32(limit),limit);C.assert(wq!=nil)
 mut held:=[4][2]BoundCase{};mut extra:=[4]BoundCase{}
 for cpu:=u32(0);cpu<4;cpu++ {
  for slot:=u32(0);slot<limit;slot++ { bound_init(&held[cpu][slot],cpu);held[cpu][slot].hold_first=true;C.assert(C.queue_work_on(i32(cpu),wq,&held[cpu][slot].work));await_counter(&held[cpu][slot].entered) }
  bound_init(&extra[cpu],cpu);C.assert(C.queue_work_on(i32(cpu),wq,&extra[cpu].work));C.assert(C.work_busy(&extra[cpu].work)==C.WORK_BUSY_PENDING)
 }
 for cpu:=u32(0);cpu<4;cpu++ {
  C.assert(extra[cpu].calls==0);C.complete(&held[cpu][0].gate)
  C.assert(C.flush_work(&extra[cpu].work) || extra[cpu].calls==1);C.assert(extra[cpu].calls==1)
  for other:=cpu+1;other<4;other++ { C.assert(extra[other].calls==0) }
  for slot:=u32(1);slot<limit;slot++ { C.assert(C.work_busy(&held[cpu][slot].work)==C.WORK_BUSY_RUNNING);C.complete(&held[cpu][slot].gate) }
 }
 C.destroy_workqueue(wq)
} }
fn bound_runnable() { unsafe {
 wq:=C.alloc_workqueue(c'bound-runnable',u32(0),2);other:=C.alloc_workqueue(c'bound-runnable-other',u32(0),2)
 highpri:=C.alloc_workqueue(c'bound-runnable-highpri',C.WQ_HIGHPRI,2);C.assert(wq!=nil && other!=nil && highpri!=nil)
 mut running:=BoundCase{};mut next:=BoundCase{};mut cross_owner:=BoundCase{};mut priority:=BoundCase{}
 bound_init(&running,1);running.hold_first=true;running.spin_first=true;bound_init(&next,1)
 C.assert(C.queue_work_on(1,wq,&running.work));await_counter(&running.entered);C.assert(C.queue_work_on(1,wq,&next.work))
 bound_init(&cross_owner,1);C.assert(C.queue_work_on(1,other,&cross_owner.work));bound_init(&priority,1);priority.expected_nice=-20
 C.assert(C.queue_work_on(1,highpri,&priority.work));C.assert(C.flush_work(&priority.work) || priority.calls==1)
 for i:=u32(0);i<10000;i++ { C.sched_yield() }
 C.assert(next.calls==0 && cross_owner.calls==0 && C.work_busy(&next.work)==C.WORK_BUSY_PENDING)
 C.__atomic_store_n(&running.request_sleep,u32(1),3);await_counter(&next.entered);await_counter(&cross_owner.entered)
 C.assert(C.flush_work(&next.work) || next.calls==1);C.assert(C.flush_work(&cross_owner.work) || cross_owner.calls==1)
 C.assert(C.work_busy(&running.work)==C.WORK_BUSY_RUNNING && running.calls==1)
 C.complete(&running.gate);C.destroy_workqueue(wq);C.destroy_workqueue(other);C.destroy_workqueue(highpri)
} }
fn bound_priority() { unsafe {
 C.assert(C.vinix_linuxkpi_worker_nice()==0 && C.vinix_linuxkpi_worker_timeslice()==5000)
 for mode:=u32(0);mode<3;mode++ {
  wq:=if mode==2 { C.alloc_ordered_workqueue(c'priority-ordered',C.WQ_HIGHPRI) } else { C.alloc_workqueue(c'priority-%u',C.WQ_HIGHPRI | if mode!=0 { C.WQ_UNBOUND } else { u32(0) },2,mode) };C.assert(wq!=nil)
  mut test:=BoundCase{};bound_init(&test,3);test.expected_nice=-20;test.check_cpu=mode==0;test.hold_first=true
  C.assert(if mode!=0 { C.queue_work(wq,&test.work) } else { C.queue_work_on(3,wq,&test.work) });await_counter(&test.entered)
  C.assert(C.vinix_linuxkpi_worker_nice()==0 && C.vinix_linuxkpi_worker_timeslice()==5000)
  C.complete(&test.gate);C.destroy_workqueue(wq);C.assert(test.calls==1 && C.vinix_linuxkpi_worker_nice()==0)
 }
 normal:=C.alloc_ordered_workqueue(c'priority-normal',u32(0));C.assert(normal!=nil)
 mut test:=BoundCase{};bound_init(&test,0);test.check_cpu=false;C.assert(C.queue_work(normal,&test.work));C.destroy_workqueue(normal);C.assert(test.calls==1)
} }
fn bound_migration() { unsafe {
 a:=C.alloc_workqueue(c'bound-owner-a',u32(0),2);b:=C.alloc_workqueue(c'bound-owner-b',u32(0),2);C.assert(a!=nil && b!=nil)
 mut shared:=BoundCase{};mut independent:=BoundCase{};bound_init(&shared,1);shared.hold_first=true
 C.assert(C.queue_work_on(1,a,&shared.work));await_counter(&shared.entered);C.vmh_current_cpu=3;C.assert(C.queue_work_on(3,a,&shared.work))
 C.assert(C.work_busy(&shared.work)==C.WORK_BUSY_RUNNING|C.WORK_BUSY_PENDING);C.complete(&shared.gate);C.drain_workqueue(a)
 C.assert(shared.calls==2 && shared.observed_cpu[1]==1)
 bound_init(&shared,1);shared.expected_cpu[1]=3;shared.hold_first=true;C.assert(C.queue_work_on(1,a,&shared.work));await_counter(&shared.entered)
 C.assert(C.queue_work_on(3,b,&shared.work));bound_init(&independent,3);C.assert(C.queue_work_on(3,b,&independent.work))
 C.assert(C.flush_work(&independent.work) || independent.calls==1);C.assert(independent.calls==1 && shared.calls==1)
 mut item_flush:=WorkOperation{};operation_start(&item_flush,.work_flush,b,&shared.work);C.assert(item_flush.done==0)
 C.complete(&shared.gate);operation_join(&item_flush);C.assert(item_flush.result && shared.calls==2 && shared.observed_cpu[1]==3)
 C.destroy_workqueue(a);C.destroy_workqueue(b)
} }
fn bound_flush() { unsafe {
 wq:=C.alloc_workqueue(c'bound-flush',u32(0),2);C.assert(wq!=nil)
 mut old:=[4]BoundCase{};mut later:=[4]BoundCase{}
 for cpu:=u32(0);cpu<4;cpu++ { bound_init(&old[cpu],cpu);old[cpu].hold_first=true;C.assert(C.queue_work_on(i32(cpu),wq,&old[cpu].work));await_counter(&old[cpu].entered) }
 mut first:=WorkOperation{};operation_start(&first,.queue_flush,wq,nil);C.assert(first.done==0)
 for cpu:=u32(0);cpu<4;cpu++ { bound_init(&later[cpu],cpu);later[cpu].hold_first=true;C.assert(C.queue_work_on(i32(cpu),wq,&later[cpu].work));await_counter(&later[cpu].entered) }
 mut second:=WorkOperation{};operation_start(&second,.queue_flush,wq,nil)
 for cpu:=u32(0);cpu<4;cpu++ { C.complete(&old[cpu].gate) };operation_join(&first);C.assert(second.done==0)
 for cpu:=u32(0);cpu<4;cpu++ { C.assert(C.work_busy(&later[cpu].work)==C.WORK_BUSY_RUNNING);C.complete(&later[cpu].gate) }
 operation_join(&second);C.destroy_workqueue(wq)
} }
struct BoundDelayed { mut: work C.delayed_work gate C.completion expected_cpu [2]u32 observed_cpu [2]u32 calls u32 entered u32 active u32 hold_first bool }
@[export:'vmh_bound_delayed_callback']
pub fn bound_delayed_callback(work &C.work_struct) { unsafe {
 test:=&BoundDelayed(C.to_delayed_work(work));C.assert(C.vinix_linuxkpi_may_sleep() && usize(C.current_work())==usize(work))
 C.assert(C.__atomic_fetch_add(&test.active,u32(1),4)==0);call:=u32(C.__atomic_fetch_add(&test.calls,u32(1),4));C.assert(call<2)
 test.observed_cpu[call]=C.vinix_linuxkpi_cpu_id();C.assert(test.observed_cpu[call]==test.expected_cpu[call])
 if call==0 { C.__atomic_store_n(&test.entered,u32(1),3);if test.hold_first { C.wait_for_completion(&test.gate) } }
 C.assert(C.vinix_linuxkpi_cpu_id()==test.expected_cpu[call]);C.assert(C.__atomic_fetch_sub(&test.active,u32(1),4)==1)
} }
fn bound_delayed_init(test &BoundDelayed,cpu u32) { unsafe {
 *test=BoundDelayed{expected_cpu:[cpu,cpu]!};C.INIT_DELAYED_WORK_ONSTACK(&test.work,C.vmh_bound_delayed_callback);C.init_completion(&test.gate)
} }
fn bound_delayed() { unsafe {
 wq:=C.alloc_workqueue(c'bound-delayed',u32(0),2);C.assert(wq!=nil);mut test:=BoundDelayed{}
 bound_delayed_init(&test,3);C.vmh_current_cpu=0;mut flags:=C.vinix_linuxkpi_irq_save()
 C.assert(C.queue_delayed_work_on(3,wq,&test.work,5));C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==0)
 C.vinix_linuxkpi_irq_restore(flags);C.vmh_current_cpu=1;advance_delayed(5);C.flush_workqueue(wq);C.assert(test.calls==1 && test.observed_cpu[0]==3)
 bound_delayed_init(&test,2);C.assert(C.queue_delayed_work_on(0,wq,&test.work,10));flags=C.vinix_linuxkpi_irq_save()
 C.assert(C.mod_delayed_work_on(2,wq,&test.work,2));C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==0)
 C.vinix_linuxkpi_irq_restore(flags);C.vmh_current_cpu=3;advance_delayed(2);C.flush_workqueue(wq);C.assert(test.calls==1 && test.observed_cpu[0]==2)
 bound_delayed_init(&test,1);test.expected_cpu[1]=3;test.hold_first=true
 C.assert(C.queue_delayed_work_on(1,wq,&test.work,0));await_counter(&test.entered);C.assert(C.queue_delayed_work_on(3,wq,&test.work,5))
 C.complete(&test.gate);C.flush_workqueue(wq);C.assert(test.calls==1 && C.timer_pending(&test.work.timer))
 advance_delayed(5);C.flush_workqueue(wq);C.assert(test.calls==2 && test.observed_cpu[1]==3)
 bound_delayed_init(&test,0);C.assert(!C.queue_delayed_work_on(4,wq,&test.work,1));C.assert(!C.mod_delayed_work_on(-1,wq,&test.work,1))
 C.assert(!C.delayed_work_pending(&test.work) && !C.timer_pending(&test.work.timer));C.vmh_current_cpu=0;delayed_cancel_tests(wq);C.destroy_workqueue(wq)
} }
fn bound_failure() { unsafe {
 before:=C.vmh_live_pages;mut failures:=u32(0);mut successes:=u32(0)
 for allocation:=i32(0);allocation<24;allocation++ {
  C.vmh_allocation_failure_after=allocation;wq:=C.alloc_workqueue(c'bound-partial-oom',u32(0),2);C.vmh_allocation_failure_after=-1
  if wq!=nil { successes++;C.destroy_workqueue(wq) } else { failures++ };C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 }
 C.assert(failures!=0 && successes!=0);C.vmh_worker_bind_failure_after=0
 C.assert(C.alloc_workqueue(c'bound-constructor-bind-failure',u32(0),2)==nil);C.vmh_worker_bind_failure_after=-1
 C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 wq:=C.alloc_workqueue(c'bound-bind-failure',u32(0),2);C.assert(wq!=nil);mut test:=BoundCase{};bound_init(&test,2)
 failed:=C.__atomic_load_n(&C.vmh_worker_bind_failures,2);C.vmh_worker_bind_failure_after=0;C.assert(C.queue_work_on(2,wq,&test.work))
 for C.__atomic_load_n(&C.vmh_worker_bind_failures,2)==failed { C.sched_yield() };C.vmh_worker_bind_failure_after=-1
 for C.__atomic_load_n(&test.entered,2)==0 { advance_delayed(1);C.sched_yield() }
 C.flush_workqueue(wq);C.assert(test.calls==1);C.destroy_workqueue(wq);C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
} }
fn bound_publish_destroy() { unsafe {
 wq:=C.alloc_workqueue(c'bound-publish-destroy',u32(0),2);C.assert(wq!=nil)
 mut held:=BoundCase{};mut extra:=BoundCase{};bound_init(&held,2);held.hold_first=true;bound_init(&extra,3)
 C.assert(C.queue_work_on(2,wq,&held.work));await_counter(&held.entered)
 mut gate:=PublishGate{wq:wq,cpu:3};C.__atomic_store_n(&publish_gate,&gate,3)
 C.assert(C.queue_work_on(3,wq,&extra.work));await_counter(&gate.entered);await_counter(&extra.entered)
 for C.work_busy(&extra.work)!=0 { C.sched_yield() };mut destroy:=WorkOperation{};operation_start(&destroy,.queue_destroy,wq,nil)
 C.complete(&held.gate);for !C.vinix_linuxkpi_host_workqueue_stopped(wq) { C.sched_yield() };C.assert(destroy.done==0)
 C.__atomic_store_n(&gate.release,u32(1),3);operation_join(&destroy);C.__atomic_store_n(&publish_gate,voidptr(nil),3)
 C.assert(held.calls==1 && extra.calls==1 && C.atomic_read(&work_workers)==0)
} }
fn bound_system() { unsafe {
 before:=C.vmh_live_pages;mut failures:=u32(0);mut successes:=u32(0)
 C.assert(C.system_wq==nil && C.system_highpri_wq==nil && C.system_unbound_wq==nil)
 for allocation:=i32(0);allocation<32;allocation++ {
  C.vmh_allocation_failure_after=allocation;result:=C.vinix_linuxkpi_workqueue_bootstrap();C.vmh_allocation_failure_after=-1
  if result!=0 { failures++;C.assert(result==-C.ENOMEM && C.system_wq==nil && C.system_highpri_wq==nil && C.system_unbound_wq==nil) }
  else { successes++;C.assert(C.system_wq!=nil && C.system_highpri_wq!=nil && C.system_unbound_wq!=nil);C.vinix_linuxkpi_workqueue_shutdown_for_test() }
  C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 }
 C.assert(failures!=0 && successes!=0);C.assert(C.vinix_linuxkpi_workqueue_bootstrap()==0)
 normal:=C.system_wq;highpri:=C.system_highpri_wq;unbound:=C.system_unbound_wq;C.assert(C.vinix_linuxkpi_workqueue_bootstrap()==0)
 C.assert(usize(C.system_wq)==usize(normal) && usize(C.system_highpri_wq)==usize(highpri) && usize(C.system_unbound_wq)==usize(unbound))
 mut local:=BoundCase{};mut remote:=BoundCase{};mut priority:=BoundCase{};mut generic:=BoundCase{};C.vmh_current_cpu=2
 bound_init(&local,2);C.assert(C.schedule_work(&local.work));bound_init(&remote,3);C.assert(C.schedule_work_on(3,&remote.work))
 bound_init(&priority,1);priority.expected_nice=-20;C.assert(C.queue_work_on(1,C.system_highpri_wq,&priority.work))
 bound_init(&generic,0);generic.check_cpu=false;C.assert(C.queue_work(C.system_unbound_wq,&generic.work))
 C.assert(C.flush_work(&local.work) || local.calls==1);C.assert(C.flush_work(&remote.work) || remote.calls==1)
 C.assert(C.flush_work(&priority.work) || priority.calls==1);C.assert(C.flush_work(&generic.work) || generic.calls==1)
 C.assert(local.calls==1 && remote.calls==1 && priority.calls==1 && generic.calls==1);C.assert(C.vinix_linuxkpi_worker_nice()==0)
 C.vinix_linuxkpi_workqueue_shutdown_for_test();C.assert(C.system_wq==nil && C.system_highpri_wq==nil && C.system_unbound_wq==nil)
 C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
} }
fn set_bound_freed(test &BoundCase,freed &u32) { unsafe { test.freed=freed } }
@[export:'vmh_bound_work_tests']
pub fn bound_work_tests() { unsafe {
 mut parent:=C.native_task_model{};C.vmh_sync_model_init(&parent,130);C.vmh_native_task=&parent
 previous_cpu:=C.vmh_current_cpu;before:=C.vmh_live_pages
 bound_routing();bound_limit(1);bound_limit(2);bound_runnable();bound_priority();bound_migration();bound_flush()
 bound_delayed();bound_failure();bound_publish_destroy();bound_system()
 wq:=C.alloc_workqueue(c'bound-free',u32(0),1);C.assert(wq!=nil);mut freed:=u32(0)
 for i:=u32(0);i<200;i++ { test:=&BoundCase(C.kzalloc(sizeof(BoundCase),C.GFP_KERNEL));C.assert(test!=nil);bound_init(test,i%4);test.free_self=true;set_bound_freed(test,&freed);C.assert(C.queue_work_on(i32(i%4),wq,&test.work)) }
 C.flush_workqueue(wq);C.assert(freed==200);C.vmh_current_cpu=0;order_tests(wq);cancel_tests(wq);C.destroy_workqueue(wq)
 C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0);C.vmh_current_cpu=previous_cpu
 C.vmh_native_task=nil;C.vmh_sync_model_destroy(&parent)
} }
