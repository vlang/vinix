// SPDX-License-Identifier: GPL-2.0-or-later
// Observe SRCU only through its original public reader/callback interfaces.
@[translated]
@[has_globals]
module hostwork
#include "hostwork_v_contract.h"
struct C.srcu_struct {}
struct C.srcu_data {}
struct C.srcu_usage {}
struct C.rcu_head {}
fn C.__SRCU_USAGE_INIT(C.srcu_usage) C.srcu_usage
fn C.__SRCU_STRUCT_INIT(C.srcu_struct,C.srcu_usage,C.srcu_data) C.srcu_struct
fn C.init_srcu_struct(&C.srcu_struct) i32
fn C.cleanup_srcu_struct(&C.srcu_struct)
fn C.srcu_read_lock(&C.srcu_struct) i32
fn C.srcu_read_unlock(&C.srcu_struct,i32)
fn C.synchronize_srcu(&C.srcu_struct)
fn C.synchronize_srcu_expedited(&C.srcu_struct)
fn C.srcu_barrier(&C.srcu_struct)
fn C.call_srcu(&C.srcu_struct,&C.rcu_head,fn (&C.rcu_head))
fn C.get_state_synchronize_srcu(&C.srcu_struct) usize
fn C.start_poll_synchronize_srcu(&C.srcu_struct) usize
fn C.poll_state_synchronize_srcu(&C.srcu_struct,usize) bool
fn C.srcu_dereference(voidptr,&C.srcu_struct) voidptr
fn C.srcu_init()
fn C.__atomic_exchange_n(voidptr,...) voidptr
fn C.msleep(u32)
fn C.vinix_linuxkpi_srcu_static_quiesce_for_test(&C.srcu_struct)
fn C.vinix_linuxkpi_srcu_bootstrap_limit_for_test(u32) i32
fn C.vinix_linuxkpi_srcu_shutdown_for_test()
fn C.vinix_linuxkpi_srcu_queue_for_test() &C.workqueue_struct
fn C.vmh_srcu_clock_thread(voidptr) voidptr
fn C.vmh_srcu_waiter_thread(voidptr) voidptr
fn C.vmh_srcu_callback(&C.rcu_head)
fn C.vmh_srcu_stress_thread(voidptr) voidptr
fn C.vmh_srcu_system_wait(&C.work_struct)
@[cinit] __global (
 srcu_static_data C.srcu_data
 srcu_static_usage C.srcu_usage = C.__SRCU_USAGE_INIT(srcu_static_usage)
 srcu_static_domain C.srcu_struct = C.__SRCU_STRUCT_INIT(srcu_static_domain,srcu_static_usage,srcu_static_data)
)
struct SrcuClock { mut: model C.native_task_model thread C.pthread_t stop u32 }
@[export:'vmh_srcu_clock_thread']
pub fn srcu_clock_thread(argument voidptr) voidptr { unsafe {
 clock:=&SrcuClock(argument);C.vmh_native_task=&clock.model;C.vmh_current_cpu=3
 for C.__atomic_load_n(&clock.stop,2)==0 { advance_delayed(1);C.sched_yield() }
 C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0);C.vmh_native_task=nil;return nil
} }
fn srcu_pump() { advance_delayed(1);C.sched_yield() }
fn srcu_wait(value &u32,target u32) { unsafe {
 for spin:=u32(0);spin<1000000;spin++ { if u32(C.__atomic_load_n(value,2))>=target { return };srcu_pump() }
 C.assert(&char(c'SRCU operation did not make progress')==nil)
} }
fn srcu_wait_flip(ssp &C.srcu_struct,old i32) i32 { unsafe {
 for spin:=u32(0);spin<1000000;spin++ { idx:=C.srcu_read_lock(ssp);C.assert(idx==0 || idx==1);C.srcu_read_unlock(ssp,idx);if idx!=old { return idx };srcu_pump() }
 C.assert(&char(c'SRCU reader bank did not change')==nil);return -1
} }
enum SrcuOperation { sync expedited barrier }
struct SrcuWaiter { mut: model C.native_task_model ssp &C.srcu_struct = unsafe { nil } thread C.pthread_t operation SrcuOperation entered u32 done u32 }
@[export:'vmh_srcu_waiter_thread']
pub fn srcu_waiter_thread(argument voidptr) voidptr { unsafe {
 waiter:=&SrcuWaiter(argument);C.vmh_native_task=&waiter.model;C.vmh_current_cpu=1;C.__atomic_store_n(&waiter.entered,u32(1),3)
 if waiter.operation==.sync { C.synchronize_srcu(waiter.ssp) } else if waiter.operation==.expedited { C.synchronize_srcu_expedited(waiter.ssp) } else { C.srcu_barrier(waiter.ssp) }
 C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0 && C.task_is_running(C.current))
 C.__atomic_store_n(&waiter.done,u32(1),3);C.vmh_native_task=nil;return nil
} }
fn srcu_waiter_start(waiter &SrcuWaiter,ssp &C.srcu_struct,operation SrcuOperation) { unsafe {
 *waiter=SrcuWaiter{ssp:ssp,operation:operation};C.vmh_sync_model_init(&waiter.model,180);waiter.model.iteration=1
 C.assert(C.pthread_create(&waiter.thread,nil,C.vmh_srcu_waiter_thread,waiter)==0);srcu_wait(&waiter.entered,1)
} }
fn srcu_waiter_join(waiter &SrcuWaiter) { unsafe { srcu_wait(&waiter.done,1);C.assert(C.pthread_join(waiter.thread,nil)==0);C.vmh_sync_model_destroy(&waiter.model) } }
struct SrcuCallback { mut:
 head C.rcu_head
 ssp &C.srcu_struct = unsafe { nil }
 calls u32
 limit u32
 index u32
 entered u32
 release u32
 order &u32 = unsafe { nil }
 count &u32 = unsafe { nil }
 freed &u32 = unsafe { nil }
 gated bool
 free_self bool
}
@[export:'vmh_srcu_callback']
pub fn srcu_callback(head &C.rcu_head) { unsafe {
 test:=&SrcuCallback(head);C.assert(C.vmh_preempt_depth!=0 && !C.vinix_linuxkpi_may_sleep())
 call:=u32(C.__atomic_add_fetch(&test.calls,u32(1),4))
 if test.count!=nil { slot:=u32(C.__atomic_fetch_add(test.count,u32(1),4));if test.order!=nil { test.order[slot]=test.index } }
 if test.gated { C.__atomic_store_n(&test.entered,u32(1),3);for C.__atomic_load_n(&test.release,2)==0 { C.sched_yield() } }
 if call<test.limit { C.call_srcu(test.ssp,&test.head,C.vmh_srcu_callback) }
 else if test.free_self { freed:=test.freed;C.kfree(test);C.__atomic_fetch_add(freed,u32(1),3) }
} }
fn srcu_callback_init(test &SrcuCallback,ssp &C.srcu_struct) { unsafe { *test=SrcuCallback{ssp:ssp,limit:1} } }
fn srcu_grace_periods(ssp &C.srcu_struct) { unsafe {
 for expedited:=u32(0);expedited<2;expedited++ {
  C.vmh_current_cpu=0;old:=C.srcu_read_lock(ssp);nested:=C.srcu_read_lock(ssp);C.assert(old==nested && C.vmh_interrupts && C.vmh_preempt_depth==0)
  mut waiter:=SrcuWaiter{};srcu_waiter_start(&waiter,ssp,if expedited!=0 { .expedited } else { .sync })
  newer:=srcu_wait_flip(ssp,old);C.vmh_current_cpu=2;late:=C.srcu_read_lock(ssp);C.assert(late==newer)
  C.vmh_current_cpu=3;C.srcu_read_unlock(ssp,nested);C.assert(C.__atomic_load_n(&waiter.done,2)==0);C.srcu_read_unlock(ssp,old);srcu_waiter_join(&waiter)
  C.vmh_current_cpu=1;C.srcu_read_unlock(ssp,late)
 }
} }
fn srcu_polling(ssp &C.srcu_struct) { unsafe {
 C.vmh_current_cpu=0;old:=C.srcu_read_lock(ssp);mut waiter:=SrcuWaiter{};srcu_waiter_start(&waiter,ssp,.sync)
 bank:=srcu_wait_flip(ssp,old);C.vmh_current_cpu=2;late:=C.srcu_read_lock(ssp);C.assert(late==bank)
 observed:=C.get_state_synchronize_srcu(ssp);requested:=C.start_poll_synchronize_srcu(ssp)
 C.assert(!C.poll_state_synchronize_srcu(ssp,observed));C.assert(!C.poll_state_synchronize_srcu(ssp,requested))
 C.vmh_current_cpu=3;C.srcu_read_unlock(ssp,old);srcu_waiter_join(&waiter)
 C.assert(!C.poll_state_synchronize_srcu(ssp,observed));C.assert(!C.poll_state_synchronize_srcu(ssp,requested));C.vmh_current_cpu=0;C.srcu_read_unlock(ssp,late)
 for spin:=u32(0);spin<1000000;spin++ { if C.poll_state_synchronize_srcu(ssp,requested) { break };srcu_pump() }
 C.assert(C.poll_state_synchronize_srcu(ssp,requested));C.assert(C.poll_state_synchronize_srcu(ssp,observed))
} }
fn srcu_late_callback(ssp &C.srcu_struct) { unsafe {
 mut first:=SrcuCallback{};mut late:=SrcuCallback{};srcu_callback_init(&first,ssp);srcu_callback_init(&late,ssp)
 C.vmh_current_cpu=0;old:=C.srcu_read_lock(ssp);C.call_srcu(ssp,&first.head,C.vmh_srcu_callback);bank:=srcu_wait_flip(ssp,old)
 C.vmh_current_cpu=2;held:=C.srcu_read_lock(ssp);C.assert(held==bank);C.call_srcu(ssp,&late.head,C.vmh_srcu_callback)
 C.vmh_current_cpu=3;C.srcu_read_unlock(ssp,old);srcu_wait(&first.calls,1);C.assert(C.__atomic_load_n(&late.calls,2)==0)
 C.vmh_current_cpu=1;C.srcu_read_unlock(ssp,held);srcu_wait(&late.calls,1);C.srcu_barrier(ssp)
} }
fn srcu_barrier_boundary(ssp &C.srcu_struct) { unsafe {
 mut first:=SrcuCallback{};mut late:=SrcuCallback{};srcu_callback_init(&first,ssp);first.gated=true;srcu_callback_init(&late,ssp)
 C.call_srcu(ssp,&first.head,C.vmh_srcu_callback);srcu_wait(&first.entered,1)
 mut sync:=SrcuWaiter{};mut barriers:=[20]SrcuWaiter{};srcu_waiter_start(&sync,ssp,.sync);srcu_waiter_join(&sync)
 for i:=u32(0);i<20;i++ { srcu_waiter_start(&barriers[i],ssp,.barrier);srcu_wait(&barriers[i].model.parked,1);C.assert(C.__atomic_load_n(&barriers[i].done,2)==0) }
 reader:=C.srcu_read_lock(ssp);C.call_srcu(ssp,&late.head,C.vmh_srcu_callback);C.__atomic_store_n(&first.release,u32(1),3)
 for i:=u32(0);i<20;i++ { srcu_waiter_join(&barriers[i]) };C.assert(C.__atomic_load_n(&late.calls,2)==0)
 C.srcu_read_unlock(ssp,reader);srcu_wait(&late.calls,1);C.srcu_barrier(ssp)
} }
// These borrowed controller counters remain stack values until the barrier.
fn srcu_set_counts(test &SrcuCallback,order &u32,count &u32,freed &u32) { unsafe { test.order=order;test.count=count;test.freed=freed } }
fn srcu_callbacks(ssp &C.srcu_struct) { unsafe {
 mut order:=[200]u32{};mut count:=u32(0);mut freed:=u32(0);reader:=C.srcu_read_lock(ssp)
 for i:=u32(0);i<200;i++ {
  test:=&SrcuCallback(C.kzalloc(sizeof(SrcuCallback),C.GFP_KERNEL));C.assert(test!=nil);srcu_callback_init(test,ssp)
  test.index=i;srcu_set_counts(test,&order[0],&count,&freed);test.free_self=true;C.call_srcu(ssp,&test.head,C.vmh_srcu_callback)
 }
 C.srcu_read_unlock(ssp,reader);srcu_wait(&freed,200);C.srcu_barrier(ssp);C.assert(count==200)
 for i:=u32(0);i<200;i++ { C.assert(order[i]==i) }
 requeue:=&SrcuCallback(C.kzalloc(sizeof(SrcuCallback),C.GFP_KERNEL));C.assert(requeue!=nil);srcu_callback_init(requeue,ssp)
 requeue.limit=20;srcu_set_counts(requeue,nil,&count,&freed);requeue.free_self=true;C.call_srcu(ssp,&requeue.head,C.vmh_srcu_callback)
 srcu_wait(&freed,201);C.srcu_barrier(ssp);C.assert(count==220)
 mut atomic_call:=SrcuCallback{};srcu_callback_init(&atomic_call,ssp);before:=C.vmh_live_pages;C.vmh_fail_allocation=true
 flags:=C.vinix_linuxkpi_irq_save();C.call_srcu(ssp,&atomic_call.head,C.vmh_srcu_callback);C.assert(!C.vmh_interrupts)
 C.vinix_linuxkpi_irq_restore(flags);C.vmh_fail_allocation=false;srcu_wait(&atomic_call.calls,1);C.srcu_barrier(ssp)
 C.vinix_linuxkpi_srcu_static_quiesce_for_test(ssp);C.assert(C.vmh_live_pages==before)
} }
const srcu_magic=usize(0xc001facedeadbeef)
struct SrcuPayload { mut: magic usize }
struct SrcuStress { mut: ssp &C.srcu_struct = unsafe { nil } payload &SrcuPayload = unsafe { nil } ready u32 go u32 done u32 }
struct SrcuStressWorker { mut: model C.native_task_model test &SrcuStress = unsafe { nil } writer bool index u32 }
@[export:'vmh_srcu_stress_thread']
pub fn srcu_stress_thread(argument voidptr) voidptr { unsafe {
 worker:=&SrcuStressWorker(argument);test:=worker.test;C.vmh_native_task=&worker.model;C.vmh_current_cpu=worker.index%4
 C.__atomic_fetch_add(&test.ready,u32(1),3);for C.__atomic_load_n(&test.go,2)==0 { C.sched_yield() }
 for round:=u32(0);round<if worker.writer { u32(40) } else { u32(200) };round++ {
  if worker.writer {
   next:=&SrcuPayload(C.kzalloc(sizeof(SrcuPayload),C.GFP_KERNEL));C.assert(next!=nil);next.magic=srcu_magic
   old:=&SrcuPayload(C.__atomic_exchange_n(&test.payload,next,4))
   if round&1!=0 { C.synchronize_srcu_expedited(test.ssp) } else { C.synchronize_srcu(test.ssp) };C.kfree(old)
  } else {
   outer:=C.srcu_read_lock(test.ssp);inner:=C.srcu_read_lock(test.ssp);payload:=&SrcuPayload(C.srcu_dereference(test.payload,test.ssp))
   C.assert(payload!=nil && payload.magic==srcu_magic);if round%4==0 { C.msleep(1) } else { C.sched_yield() }
   C.assert(payload.magic==srcu_magic);C.vmh_current_cpu=(C.vmh_current_cpu+1)%4;C.srcu_read_unlock(test.ssp,inner)
   C.vmh_current_cpu=(C.vmh_current_cpu+1)%4;C.srcu_read_unlock(test.ssp,outer)
  }
 }
 C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0);C.__atomic_fetch_add(&test.done,u32(1),3);C.vmh_native_task=nil;return nil
} }
fn srcu_concurrency(ssp &C.srcu_struct) { unsafe {
 before:=C.vmh_live_pages;mut test:=SrcuStress{ssp:ssp};test.payload=&SrcuPayload(C.kzalloc(sizeof(SrcuPayload),C.GFP_KERNEL));C.assert(test.payload!=nil);test.payload.magic=srcu_magic
 mut workers:=[8]SrcuStressWorker{};mut threads:=[8]C.pthread_t{}
 for i:=u32(0);i<8;i++ { workers[i]=SrcuStressWorker{test:&test,index:i,writer:i>=4};C.vmh_sync_model_init(&workers[i].model,190+i);C.assert(C.pthread_create(&threads[i],nil,C.vmh_srcu_stress_thread,&workers[i])==0) }
 srcu_wait(&test.ready,8);C.__atomic_store_n(&test.go,u32(1),3);srcu_wait(&test.done,8)
 for i:=u32(0);i<8;i++ { C.assert(C.pthread_join(threads[i],nil)==0);C.vmh_sync_model_destroy(&workers[i].model) }
 C.kfree(test.payload);C.assert(C.vmh_live_pages==before)
} }
fn srcu_dynamic_lifetimes() { unsafe {
 before:=C.vmh_live_pages;mut failures:=u32(0);mut successes:=u32(0)
 for stage:=i32(0);stage<8;stage++ {
  mut domain:=C.srcu_struct{};C.vmh_allocation_failure_after=stage;result:=C.init_srcu_struct(&domain);C.vmh_allocation_failure_after=-1
  if result!=0 { C.assert(result==-C.ENOMEM && C.vmh_live_pages==before);failures++;C.assert(C.init_srcu_struct(&domain)==0) } else { successes++ }
  idx:=C.srcu_read_lock(&domain);C.vmh_current_cpu=(C.vmh_current_cpu+1)%4;C.srcu_read_unlock(&domain,idx);C.cleanup_srcu_struct(&domain);C.assert(C.vmh_live_pages==before)
 }
 C.assert(failures!=0 && successes!=0)
 for round:=u32(0);round<200;round++ {
  mut domain:=C.srcu_struct{};C.assert(C.init_srcu_struct(&domain)==0);outer:=C.srcu_read_lock(&domain);inner:=C.srcu_read_lock(&domain)
  C.vmh_current_cpu=(C.vmh_current_cpu+1)%4;C.srcu_read_unlock(&domain,inner);C.vmh_current_cpu=(C.vmh_current_cpu+1)%4;C.srcu_read_unlock(&domain,outer)
  mut callback:=SrcuCallback{};srcu_callback_init(&callback,&domain);C.call_srcu(&domain,&callback.head,C.vmh_srcu_callback);srcu_wait(&callback.calls,1);C.srcu_barrier(&domain)
  if round&1!=0 { C.synchronize_srcu_expedited(&domain) } else { C.synchronize_srcu(&domain) };C.cleanup_srcu_struct(&domain);C.assert(C.vmh_live_pages==before)
 }
} }
fn srcu_waiting_domains() { unsafe {
 mut blocked:=[3]C.srcu_struct{};mut ready:=C.srcu_struct{};mut callbacks:=[3]SrcuCallback{};mut independent:=SrcuCallback{};mut readers:=[3]i32{};before:=C.vmh_live_pages
 for i:=u32(0);i<3;i++ { C.assert(C.init_srcu_struct(&blocked[i])==0);readers[i]=C.srcu_read_lock(&blocked[i]);srcu_callback_init(&callbacks[i],&blocked[i]);C.call_srcu(&blocked[i],&callbacks[i].head,C.vmh_srcu_callback);srcu_wait_flip(&blocked[i],readers[i]) }
 C.assert(C.init_srcu_struct(&ready)==0);srcu_callback_init(&independent,&ready);C.call_srcu(&ready,&independent.head,C.vmh_srcu_callback)
 srcu_wait(&independent.calls,1);C.cleanup_srcu_struct(&ready)
 for i:=u32(0);i<3;i++ { C.assert(C.__atomic_load_n(&callbacks[i].calls,2)==0);C.vmh_current_cpu=(C.vmh_current_cpu+1)%4;C.srcu_read_unlock(&blocked[i],readers[i]) }
 for i:=u32(0);i<3;i++ { srcu_wait(&callbacks[i].calls,1);C.cleanup_srcu_struct(&blocked[i]) };C.assert(C.vmh_live_pages==before)
} }
struct SrcuSystemWaiter { mut: work C.work_struct ssp &C.srcu_struct = unsafe { nil } entered &u32 = unsafe { nil } done &u32 = unsafe { nil } }
@[export:'vmh_srcu_system_wait']
pub fn srcu_system_wait(work &C.work_struct) { unsafe {
 waiter:=&SrcuSystemWaiter(work);C.assert(C.vinix_linuxkpi_may_sleep());C.__atomic_fetch_add(waiter.entered,u32(1),3)
 C.synchronize_srcu(waiter.ssp);C.__atomic_fetch_add(waiter.done,u32(1),3)
} }
fn srcu_system_saturation() { unsafe {
 mut domain:=C.srcu_struct{};mut ready:=C.srcu_struct{};C.assert(C.init_srcu_struct(&domain)==0 && C.init_srcu_struct(&ready)==0)
 reader:=C.srcu_read_lock(&domain);mut waiters:=[256]SrcuSystemWaiter{};mut entered:=u32(0);mut done:=u32(0)
 for i:=u32(0);i<256;i++ {
  waiters[i]=SrcuSystemWaiter{ssp:&domain,entered:&entered,done:&done};C.INIT_WORK_ONSTACK(&waiters[i].work,C.vmh_srcu_system_wait);C.assert(C.queue_work(C.system_unbound_wq,&waiters[i].work))
 }
 srcu_wait(&entered,256);C.assert(C.__atomic_load_n(&done,2)==0);mut independent:=SrcuCallback{};srcu_callback_init(&independent,&ready)
 C.call_srcu(&ready,&independent.head,C.vmh_srcu_callback);srcu_wait(&independent.calls,1);C.cleanup_srcu_struct(&ready)
 C.srcu_read_unlock(&domain,reader);srcu_wait(&done,256)
 for i:=u32(0);i<256;i++ { C.assert(C.flush_work(&waiters[i].work) || done==256) };C.cleanup_srcu_struct(&domain)
} }
@[export:'vmh_srcu_tests']
pub fn srcu_tests() { unsafe {
 mut parent:=C.native_task_model{};C.vmh_sync_model_init(&parent,170);C.vmh_native_task=&parent;saved_cpu:=C.vmh_current_cpu;before:=C.vmh_live_pages
 C.assert(C.system_unbound_wq==nil && C.system_wq==nil && C.system_highpri_wq==nil);C.assert(C.vinix_linuxkpi_workqueue_bootstrap()==0)
 system_pages:=C.vmh_live_pages;system_workers:=C.atomic_read(&work_workers);C.vmh_fail_allocation=true
 C.assert(C.vinix_linuxkpi_srcu_bootstrap_limit_for_test(2)==-C.ENOMEM);C.vmh_fail_allocation=false
 C.assert(C.vmh_live_pages==system_pages && C.atomic_read(&work_workers)==system_workers)
 mut bootstrap_failures:=u32(0);mut bootstrap_successes:=u32(0)
 for stage:=i32(0);stage<8;stage++ {
  C.vmh_allocation_failure_after=stage;result:=C.vinix_linuxkpi_srcu_bootstrap_limit_for_test(2);C.vmh_allocation_failure_after=-1
  if result!=0 { C.assert(result==-C.ENOMEM);bootstrap_failures++;C.assert(C.vinix_linuxkpi_srcu_bootstrap_limit_for_test(2)==0) } else { bootstrap_successes++ }
  initialized:=C.vinix_linuxkpi_srcu_queue_for_test();C.assert(C.vinix_linuxkpi_srcu_bootstrap_limit_for_test(2)==0)
  C.assert(usize(C.vinix_linuxkpi_srcu_queue_for_test())==usize(initialized));C.vinix_linuxkpi_srcu_shutdown_for_test()
  C.assert(C.vmh_live_pages==system_pages && C.atomic_read(&work_workers)==system_workers)
 }
 C.assert(bootstrap_failures!=0 && bootstrap_successes!=0);C.assert(C.vinix_linuxkpi_srcu_bootstrap_limit_for_test(2)==0);C.srcu_init()
 mut clock:=SrcuClock{};C.vmh_sync_model_init(&clock.model,179);C.assert(C.pthread_create(&clock.thread,nil,C.vmh_srcu_clock_thread,&clock)==0)
 queue:=C.vinix_linuxkpi_srcu_queue_for_test();C.assert(queue!=nil && usize(queue)!=usize(C.system_unbound_wq));mut warm:=[2]WorkTest{}
 for i:=u32(0);i<2;i++ { work_init(&warm[i],queue);warm[i].hold=true;C.assert(C.queue_work(queue,&warm[i].work)) }
 for i:=u32(0);i<2;i++ { srcu_wait(&warm[i].entered,1) };for i:=u32(0);i<2;i++ { C.complete(&warm[i].gate) }
 for i:=u32(0);i<2;i++ { C.assert(C.flush_work(&warm[i].work) || warm[i].calls==1) }
 srcu_system_saturation();warmed:=C.vmh_live_pages;srcu_waiting_domains()
 C.vmh_current_cpu=0;C.vmh_fail_allocation=true;static_reader:=C.srcu_read_lock(&srcu_static_domain);C.assert(C.vmh_live_pages==warmed);C.vmh_fail_allocation=false
 mut static_waiter:=SrcuWaiter{};srcu_waiter_start(&static_waiter,&srcu_static_domain,.sync);srcu_wait_flip(&srcu_static_domain,static_reader)
 C.assert(C.__atomic_load_n(&static_waiter.done,2)==0);C.vmh_current_cpu=3;C.srcu_read_unlock(&srcu_static_domain,static_reader);srcu_waiter_join(&static_waiter)
 srcu_grace_periods(&srcu_static_domain);srcu_polling(&srcu_static_domain);srcu_late_callback(&srcu_static_domain);srcu_barrier_boundary(&srcu_static_domain)
 srcu_callbacks(&srcu_static_domain);srcu_concurrency(&srcu_static_domain);C.assert(C.vmh_live_pages==warmed)
 srcu_dynamic_lifetimes();C.assert(C.vmh_live_pages==warmed);C.vinix_linuxkpi_srcu_static_quiesce_for_test(&srcu_static_domain)
 C.vinix_linuxkpi_srcu_shutdown_for_test();C.vinix_linuxkpi_workqueue_shutdown_for_test();C.__atomic_store_n(&clock.stop,u32(1),3)
 C.assert(C.pthread_join(clock.thread,nil)==0);C.vmh_sync_model_destroy(&clock.model);C.assert(C.vmh_live_pages==before && C.atomic_read(&work_workers)==0)
 C.vmh_current_cpu=saved_cpu;C.vmh_native_task=nil;C.vmh_sync_model_destroy(&parent)
} }
