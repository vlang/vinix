// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native I/O accounting and mutex I/O fixture assertions.
@[translated]
@[has_globals]
module hostio
#include "hostio_v_contract.h"
struct C.wait_bit_key {}
struct C.wait_queue_head {}
@[typedef] struct C.atomic_long_t {}
struct C.mutex { owner C.atomic_long_t }
fn C.vinix_linuxkpi_task_in_iowait(voidptr) bool
fn C.vinix_linuxkpi_task_dequeue(voidptr)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_iowait_block(voidptr)
fn C.vinix_linuxkpi_iowait_count(u32) u32
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_preempt_count() u32
fn C.io_schedule_prepare() i32
fn C.io_schedule_finish(i32)
fn C.io_schedule()
fn C.io_schedule_timeout(isize) isize
fn C.wait_on_bit_io(&usize,i32,u32) i32
fn C.wait_on_bit_lock_io(&usize,i32,u32) i32
fn C.bit_wait_io_timeout(&C.wait_bit_key,i32) i32
fn C.out_of_line_wait_on_bit_timeout(voidptr,i32,fn (&C.wait_bit_key,i32) i32,u32,usize) i32
fn C.clear_and_wake_up_bit(i32,&usize)
fn C.set_bit(i32,&usize)
fn C.test_bit(i32,&usize) bool
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.bit_waitqueue(voidptr,i32) &C.wait_queue_head
fn C.nr_iowait() u32
fn C.nr_iowait_cpu(i32) u32
fn C.vmh_host_time_advance(C.vmh_u64)
fn C.vmh_mutex_waiters(&C.mutex) u32
fn C.mutex_init(&C.mutex)
fn C.mutex_destroy(&C.mutex)
fn C.mutex_lock(&C.mutex)
fn C.mutex_lock_io(&C.mutex)
fn C.mutex_lock_io_nested(&C.mutex,u32)
fn C.mutex_lock_interruptible(&C.mutex) i32
fn C.mutex_unlock(&C.mutex)
fn C.mutex_trylock(&C.mutex) i32
fn C.mutex_is_locked(&C.mutex) bool
fn C.atomic_long_read(&C.atomic_long_t) isize
fn C.vmh_io_actor_thread(voidptr) voidptr
fn C.vmh_io_wake_before_block(&C.native_task_model)
fn C.vmh_mutex_io_thread(voidptr) voidptr
fn C.vmh_mutex_io_before_block(&C.native_task_model)
@[c_extern] __global (
 C.TASK_UNINTERRUPTIBLE u32
 C.TASK_INTERRUPTIBLE u32
 C.EINTR i32
 C.EAGAIN i32
)
__global iowait_counts [4]u32
@[export: 'vmh_iowait_end_locked']
pub fn iowait_end_locked(task &C.native_task_model) { unsafe {
 if task.iowait_cpu_plus_one == 0 { return }
 C.assert(!task.queued)
 cpu:=task.iowait_cpu_plus_one-1
 C.assert(cpu<4)
 C.assert(C.__atomic_fetch_sub(&iowait_counts[cpu],u32(1),4)!=0)
 task.iowait_cpu_plus_one=0
} }
@[export: 'vinix_linuxkpi_iowait_block']
pub fn iowait_block(owner voidptr) { unsafe {
 task:=&C.native_task_model(owner)
 C.assert(usize(task)==usize(C.vmh_native_task))
 if C.vmh_host_iowait_before_block != unsafe { nil } {
  hook:=C.vmh_host_iowait_before_block
  C.vmh_host_iowait_before_block=unsafe { nil }
  hook(task)
 }
 C.assert(C.pthread_mutex_lock(&task.queue_lock)==0)
 if !task.queued && !task.dead && C.vinix_linuxkpi_task_in_iowait(&task.storage[0]) {
  C.assert(task.iowait_cpu_plus_one==0 && C.vmh_current_cpu<4)
  C.__atomic_fetch_add(&iowait_counts[C.vmh_current_cpu],u32(1),4)
  task.iowait_cpu_plus_one=C.vmh_current_cpu+1
 }
 C.assert(C.pthread_mutex_unlock(&task.queue_lock)==0)
} }
@[export: 'vinix_linuxkpi_iowait_count']
pub fn iowait_count(cpu u32) u32 { unsafe {
 C.assert(cpu<4)
 return u32(C.__atomic_load_n(&iowait_counts[cpu],2))
} }
fn wait_value(value &u32, expected u32) {
 for spin:=u32(0);spin<1000000;spin++ {
  if C.__atomic_load_n(value,2)>=expected { return }
  C.sched_yield()
 }
 C.assert(false) // Original I/O waiter progress assertion.
}
fn advance(ticks u64) { unsafe {
 mut native:=C.vmh_u64{}
 C.memcpy(&native,&ticks,8)
 C.vmh_host_time_advance(native)
} }
// Numeric values retain the original enum declaration order.
const direct=u32(0)
const timed=u32(1)
const plain=u32(2)
const bit=u32(3)
const bit_lock=u32(4)
const bit_timeout=u32(5)
const nested=u32(6)
struct IoActor { mut:
 model C.native_task_model
 thread C.pthread_t
 word &usize
 operation u32
 cpu u32
 state u32
 entered u32
 returned u32
 release u32
 done u32
 before_block_calls u32
 timeout isize
 result isize
 signal_before_block bool
}
@[export: 'vmh_io_wake_before_block']
pub fn wake_before_block(task &C.native_task_model) { unsafe {
 actor:=&IoActor(C.vmh_io_test_current)
 C.assert(actor!=nil && actor.signal_before_block)
 C.__atomic_fetch_add(&actor.before_block_calls,u32(1),3)
 C.__atomic_store_n(&C.vmh_u64(&task.pending),u64(1)<<14,3)
 C.assert(C.vinix_linuxkpi_task_enqueue(task))
} }
@[export: 'vmh_io_actor_thread']
pub fn io_thread(argument voidptr) voidptr { unsafe {
 actor:=&IoActor(argument)
 C.vmh_native_task=&actor.model
 C.vmh_current_cpu=actor.cpu
 C.vmh_io_test_current=actor
 if actor.signal_before_block { C.vmh_host_iowait_before_block=C.vmh_io_wake_before_block }
 C.__atomic_store_n(&actor.entered,u32(1),3)
 if actor.operation==bit { actor.result=C.wait_on_bit_io(actor.word,3,actor.state) }
 else if actor.operation==bit_lock { actor.result=C.wait_on_bit_lock_io(actor.word,3,actor.state) }
 else if actor.operation==bit_timeout { actor.result=C.out_of_line_wait_on_bit_timeout(actor.word,3,C.bit_wait_io_timeout,actor.state,usize(actor.timeout)) }
 else if actor.operation==nested {
  outer:=C.io_schedule_prepare();inner:=C.io_schedule_prepare()
  C.assert(outer==0 && inner==1 && C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0]))
  C.set_current_state(actor.state);C.io_schedule()
  C.assert(C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0]))
  C.io_schedule_finish(inner)
  C.assert(C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0]))
  C.io_schedule_finish(outer)
 } else {
  C.set_current_state(actor.state)
  if actor.operation==timed { actor.result=C.io_schedule_timeout(actor.timeout) }
  else if actor.operation==plain { C.schedule() }
  else { C.io_schedule() }
 }
 C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth==0)
 C.assert(!C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0]))
 C.assert(actor.model.iowait_cpu_plus_one==0 && C.vmh_host_iowait_before_block==unsafe { nil })
 C.__atomic_store_n(&actor.returned,u32(1),3)
 if actor.operation==bit_lock && actor.result==0 {
  C.assert(C.test_bit(3,actor.word))
  wait_value(&actor.release,1)
  C.clear_and_wake_up_bit(3,actor.word)
 }
 C.__atomic_store_n(&actor.done,u32(1),3)
 C.vmh_native_task=nil;C.vmh_io_test_current=nil
 return nil
} }
fn start(actor &IoActor, operation u32, cpu u32,state u32) { unsafe {
 actor.operation=operation;actor.cpu=cpu;actor.state=state
 C.vmh_sync_model_init(&actor.model,240+cpu);actor.model.iteration=1
 C.assert(C.pthread_create(&actor.thread,nil,C.vmh_io_actor_thread,actor)==0)
 wait_value(&actor.entered,1)
} }
fn parked(actor &IoActor) { unsafe {
 wait_value(&actor.model.parked,1)
 C.assert(!C.vinix_linuxkpi_task_queued(&actor.model))
 if actor.operation==plain { C.assert(actor.model.iowait_cpu_plus_one==0) }
 else { C.assert(C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0]));C.assert(actor.model.iowait_cpu_plus_one==actor.cpu+1) }
} }
fn join(actor &IoActor) { unsafe {
 wait_value(&actor.done,1);C.assert(C.pthread_join(actor.thread,nil)==0)
 C.assert(actor.model.iowait_cpu_plus_one==0)
 C.vmh_sync_model_destroy(&actor.model)
} }
fn zero_counts() { C.assert(C.nr_iowait()==0);for cpu:=u32(0);cpu<4;cpu++ { C.assert(C.nr_iowait_cpu(i32(cpu))==0) } }
fn count_wait(cpu u32,expected u32) {
 for spin:=u32(0);spin<1000000;spin++ { if C.nr_iowait_cpu(i32(cpu))==expected { return };C.sched_yield() }
 C.assert(false) // Original I/O accounting progress assertion.
}
fn tokens() { unsafe {
 zero_counts();C.assert(!C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 outer:=C.io_schedule_prepare();C.assert(outer==0 && C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 inner:=C.io_schedule_prepare();C.assert(inner==1 && C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 mut child:=C.native_task_model{};C.vmh_sync_model_init(&child,250)
 C.vinix_linuxkpi_task_inherit(&child.storage[0],&child,child.pid,child.tgid,&C.vmh_native_task.storage[0])
 C.assert(!C.vinix_linuxkpi_task_in_iowait(&child.storage[0]));C.vmh_sync_model_destroy(&child)
 zero_counts();C.io_schedule();C.set_current_state(C.TASK_UNINTERRUPTIBLE)
 C.assert(C.io_schedule_timeout(0)==0)
 C.assert(C.task_is_running(C.current) && C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 zero_counts();C.io_schedule_finish(inner)
 C.assert(C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 C.io_schedule_finish(outer);C.assert(!C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 C.vmh_native_task.pending=u64(1)<<14;C.set_current_state(C.TASK_INTERRUPTIBLE)
 C.assert(C.io_schedule_timeout(10)==10)
 C.assert(C.task_is_running(C.current) && !C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 C.vmh_native_task.pending=0;zero_counts();C.assert(C.vinix_linuxkpi_time_waiters()==0)
} }
fn cpu_counts() { unsafe {
 mut actors:=[4]IoActor{};cpus:=[u32(1),1,3,2]!
 for i:=u32(0);i<4;i++ { start(&actors[i],if i==3 { plain } else { direct },cpus[i],C.TASK_UNINTERRUPTIBLE);parked(&actors[i]) }
 C.assert(C.nr_iowait()==3 && C.nr_iowait_cpu(1)==2 && C.nr_iowait_cpu(3)==1)
 C.assert(C.nr_iowait_cpu(0)==0 && C.nr_iowait_cpu(2)==0);C.vmh_current_cpu=0
 for i:=u32(0);i<4;i++ {
  C.assert(C.wake_up_process(&C.task_struct(&actors[i].model.storage[0]))!=0)
  C.assert(actors[i].model.iowait_cpu_plus_one==0)
  C.assert(C.wake_up_process(&C.task_struct(&actors[i].model.storage[0]))==0)
  C.assert(C.nr_iowait()==if i<3 { 2-i } else { u32(0) });join(&actors[i])
 }
 zero_counts()
} }
fn deadlines() { unsafe {
 for outcome:=u32(0);outcome<3;outcome++ {
  mut actor:=IoActor{timeout:10};start(&actor,timed,outcome,C.TASK_INTERRUPTIBLE);parked(&actor)
  C.assert(C.nr_iowait_cpu(i32(outcome))==1 && C.nr_iowait()==1 && C.vinix_linuxkpi_time_waiters()==1)
  advance(if outcome!=0 { u64(3) } else { u64(10) })
  if outcome==1 { C.assert(C.wake_up_process(&C.task_struct(&actor.model.storage[0]))!=0) }
  else if outcome==2 { C.__atomic_store_n(&C.vmh_u64(&actor.model.pending),u64(1)<<14,3);C.assert(C.vinix_linuxkpi_task_enqueue(&actor.model)) }
  zero_counts();join(&actor)
  C.assert(actor.result==if outcome!=0 { isize(7) } else { isize(0) } && C.vinix_linuxkpi_time_waiters()==0)
 }
} }
fn bits() { unsafe {
 mut word:=usize(0)
 for round:=u32(0);round<32;round++ { for operation:=bit;operation<=bit_timeout;operation++ { for cancel:=u32(0);cancel<2;cancel++ {
  C.set_bit(3,&word);mut actor:=IoActor{word:&word,timeout:10}
  start(&actor,operation,round%4,C.TASK_INTERRUPTIBLE);parked(&actor)
  C.assert(C.nr_iowait()==1 && C.nr_iowait_cpu(i32(round%4))==1)
  if cancel!=0 { C.__atomic_store_n(&C.vmh_u64(&actor.model.pending),u64(1)<<14,3);C.assert(C.vinix_linuxkpi_task_enqueue(&actor.model)) }
  else { C.clear_and_wake_up_bit(3,&word) }
  zero_counts()
  if cancel==0 && operation==bit_lock { wait_value(&actor.returned,1);C.__atomic_store_n(&actor.release,u32(1),3) }
  join(&actor);C.assert(actor.result==if cancel!=0 { isize(-C.EINTR) } else { isize(0) })
  C.assert(!C.waitqueue_active(C.bit_waitqueue(&word,3)) && C.vinix_linuxkpi_time_waiters()==0)
  C.clear_and_wake_up_bit(3,&word)
 } } }
 C.set_bit(3,&word)
 C.assert(C.out_of_line_wait_on_bit_timeout(&word,3,C.bit_wait_io_timeout,C.TASK_UNINTERRUPTIBLE,0)==-C.EAGAIN)
 C.clear_and_wake_up_bit(3,&word)
 C.assert(C.wait_on_bit_io(&word,3,C.TASK_UNINTERRUPTIBLE)==0)
 C.assert(C.wait_on_bit_lock_io(&word,3,C.TASK_UNINTERRUPTIBLE)==0)
 C.clear_and_wake_up_bit(3,&word);zero_counts();C.set_bit(3,&word)
 mut actor:=IoActor{word:&word,timeout:10};start(&actor,bit_timeout,3,C.TASK_UNINTERRUPTIBLE);parked(&actor)
 advance(3);C.assert(C.wake_up_process(&C.task_struct(&actor.model.storage[0]))!=0)
 count_wait(3,1);C.assert(C.nr_iowait()==1);advance(7);join(&actor)
 C.assert(actor.result==-C.EAGAIN && C.test_bit(3,&word))
 C.assert(!C.waitqueue_active(C.bit_waitqueue(&word,3)) && C.vinix_linuxkpi_time_waiters()==0)
 C.clear_and_wake_up_bit(3,&word);zero_counts()
} }
fn dying_dequeue() { unsafe {
 controller:=C.vmh_native_task;mut dying:=C.native_task_model{}
 C.vmh_sync_model_init(&dying,251);C.vmh_native_task=&dying;C.vmh_current_cpu=1
 token:=C.io_schedule_prepare();C.assert(token==0)
 C.vinix_linuxkpi_task_dequeue(&dying);C.vinix_linuxkpi_iowait_block(&dying)
 C.assert(C.nr_iowait()==1 && C.nr_iowait_cpu(1)==1)
 C.__atomic_store_n(&dying.dead,true,3);C.vinix_linuxkpi_task_dead(&dying.storage[0])
 C.assert(!C.vinix_linuxkpi_task_enqueue(&dying));C.assert(C.nr_iowait_cpu(1)==1)
 C.vinix_linuxkpi_task_dequeue(&dying);zero_counts();C.io_schedule_finish(token)
 C.assert(!C.vinix_linuxkpi_task_in_iowait(&dying.storage[0]))
 C.vmh_native_task=controller;C.vmh_sync_model_destroy(&dying)
} }
fn queue_edges() { unsafe {
 mut actor:=IoActor{};start(&actor,nested,2,C.TASK_UNINTERRUPTIBLE);parked(&actor)
 C.assert(C.nr_iowait_cpu(2)==1);C.assert(C.pthread_mutex_lock(&actor.model.queue_lock)==0)
 actor.model.reject_enqueue=true;C.assert(C.pthread_mutex_unlock(&actor.model.queue_lock)==0)
 C.assert(!C.vinix_linuxkpi_task_enqueue(&actor.model))
 C.assert(C.nr_iowait_cpu(2)==1 && !C.vinix_linuxkpi_task_queued(&actor.model))
 C.assert(C.pthread_mutex_lock(&actor.model.queue_lock)==0);actor.model.reject_enqueue=false
 C.assert(C.pthread_mutex_unlock(&actor.model.queue_lock)==0)
 C.assert(C.wake_up_process(&C.task_struct(&actor.model.storage[0]))!=0);zero_counts();join(&actor)
 for round:=u32(0);round<64;round++ {
  actor=IoActor{signal_before_block:true};start(&actor,direct,round%4,C.TASK_INTERRUPTIBLE);join(&actor)
  C.assert(actor.before_block_calls==1 && actor.model.iowait_cpu_plus_one==0);zero_counts()
 }
} }
@[export: 'vmh_io_tests']
pub fn io_tests() { unsafe {
 mut controller:=C.native_task_model{};C.vmh_sync_model_init(&controller,249)
 C.vmh_native_task=&controller;C.vmh_current_cpu=0;before:=C.vmh_live_pages
 C.assert(!C.vmh_fail_allocation);C.vmh_fail_allocation=true
 tokens();cpu_counts();deadlines();bits();queue_edges();dying_dequeue()
 C.assert(C.vmh_live_pages==before && C.vinix_linuxkpi_time_waiters()==0);zero_counts()
 C.vmh_fail_allocation=false;C.vmh_native_task=nil;C.vmh_sync_model_destroy(&controller)
} }
const mutex_direct=u32(0)
const mutex_nested=u32(1)
const mutex_ordinary=u32(2)
const mutex_interruptible=u32(3)
struct MutexActor { mut:
 model C.native_task_model
 lockp &C.mutex
 thread C.pthread_t
 operation u32
 cpu u32
 entered u32
 acquired u32
 release u32
 done u32
 block_calls u32
 result i32
 prior_intent bool
}
@[export: 'vmh_mutex_io_before_block']
pub fn mutex_before_block(task &C.native_task_model) { unsafe {
 actor:=&MutexActor(C.vmh_mutex_io_current)
 C.assert(actor!=nil && usize(task)==usize(&actor.model))
 C.__atomic_fetch_add(&actor.block_calls,u32(1),3)
 C.vmh_host_iowait_before_block=C.vmh_mutex_io_before_block
} }
@[export: 'vmh_mutex_io_thread']
pub fn mutex_thread(argument voidptr) voidptr { unsafe {
 actor:=&MutexActor(argument)
 C.vmh_native_task=&actor.model;C.vmh_current_cpu=actor.cpu;C.vmh_mutex_io_current=actor
 outer:=if actor.prior_intent { C.io_schedule_prepare() } else { i32(-1) }
 if outer>=0 { C.assert(outer==0) }
 if actor.operation!=mutex_ordinary { C.vmh_host_iowait_before_block=C.vmh_mutex_io_before_block }
 C.__atomic_store_n(&actor.entered,u32(1),3)
 if actor.operation==mutex_direct { C.mutex_lock_io(actor.lockp) }
 else if actor.operation==mutex_nested { C.mutex_lock_io_nested(actor.lockp,u32(1)) }
 else if actor.operation==mutex_ordinary { C.mutex_lock(actor.lockp) }
 else {
  token:=C.io_schedule_prepare();actor.result=C.mutex_lock_interruptible(actor.lockp);C.io_schedule_finish(token)
 }
 C.vmh_host_iowait_before_block=unsafe { nil }
 C.assert(C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0])==actor.prior_intent)
 C.assert(actor.model.iowait_cpu_plus_one==0 && C.task_is_running(C.current))
 C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0)
 if actor.result==0 {
  C.assert(C.atomic_long_read(&actor.lockp.owner)==isize(C.current))
  C.__atomic_store_n(&actor.acquired,u32(1),3)
  wait_value(&actor.release,1);C.mutex_unlock(actor.lockp)
 }
 if outer>=0 { C.io_schedule_finish(outer) }
 C.assert(!C.vinix_linuxkpi_task_in_iowait(&actor.model.storage[0]))
 C.__atomic_store_n(&C.vmh_u64(&actor.model.pending),u64(0),3);C.__atomic_store_n(&actor.done,u32(1),3)
 C.vmh_mutex_io_current=nil;C.vmh_native_task=nil
 return nil
} }
fn mutex_start(actor &MutexActor,lockp &C.mutex,operation u32,cpu u32,prior bool) { unsafe {
 *actor=MutexActor{lockp:lockp,operation:operation,cpu:cpu,prior_intent:prior}
 C.vmh_sync_model_init(&actor.model,280+cpu);actor.model.iteration=1
 C.assert(C.pthread_create(&actor.thread,nil,C.vmh_mutex_io_thread,actor)==0)
 wait_value(&actor.entered,1);wait_value(&actor.model.parked,1)
 C.assert(!C.vinix_linuxkpi_task_queued(&actor.model))
 C.assert(actor.model.iowait_cpu_plus_one==if operation==mutex_ordinary { u32(0) } else { cpu+1 })
} }
fn mutex_join(actor &MutexActor) { unsafe {
 wait_value(&actor.done,1);C.assert(C.pthread_join(actor.thread,nil)==0)
 C.assert(actor.model.iowait_cpu_plus_one==0);C.vmh_sync_model_destroy(&actor.model)
} }
fn lock_argument(lockp &C.mutex,calls &u32) &C.mutex { unsafe { (*calls)++;return lockp } }
fn next_subclass(subclass &u32) u32 { unsafe { value:=*subclass;(*subclass)++;return value } }
fn mutex_fast() { unsafe {
 mut lockp:=C.mutex{};C.mutex_init(&lockp)
 mut calls:=u32(0);mut subclass:=u32(0)
 irq:=C.vinix_linuxkpi_irq_flags();depth:=C.vinix_linuxkpi_preempt_count()
 for round:=u32(0);round<128;round++ {
  C.mutex_lock_io(lock_argument(&lockp,&calls))
  C.assert(C.atomic_long_read(&lockp.owner)==isize(C.current))
  C.assert(!C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
  C.assert(C.vmh_native_task.dequeued==0 && C.vmh_native_task.iowait_cpu_plus_one==0)
  zero_counts();C.mutex_unlock(&lockp)
  outer:=C.io_schedule_prepare();C.assert(outer==0)
  // Keep the side effect inside the imported macro so the public header's
  // CONFIG_DEBUG_LOCK_ALLOC=n discarded annotation remains observable.
  C.mutex_lock_io_nested(lock_argument(&lockp,&calls),next_subclass(&subclass))
  C.assert(C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
  C.assert(C.vmh_native_task.dequeued==0 && C.vmh_native_task.iowait_cpu_plus_one==0)
  zero_counts();C.mutex_unlock(&lockp)
  C.assert(C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
  C.io_schedule_finish(outer);C.assert(!C.vinix_linuxkpi_task_in_iowait(&C.vmh_native_task.storage[0]))
 }
 C.assert(calls==256 && subclass==0)
 C.assert(irq==C.vinix_linuxkpi_irq_flags() && depth==C.vinix_linuxkpi_preempt_count())
 C.assert(C.vmh_mutex_waiters(&lockp)==0);C.mutex_destroy(&lockp)
} }
fn mutex_fifo_and_cancel() { unsafe {
 mut lockp:=C.mutex{};C.mutex_init(&lockp);C.mutex_lock(&lockp)
 mut actors:=[4]MutexActor{};cpus:=[u32(1),2,3,1]!
 operations:=[mutex_direct,mutex_interruptible,mutex_ordinary,mutex_nested]!
 for i:=u32(0);i<4;i++ {
  mutex_start(&actors[i],&lockp,operations[i],cpus[i],i<2)
  C.assert(C.vmh_mutex_waiters(&lockp)==i+1)
 }
 C.assert(C.nr_iowait()==3 && C.nr_iowait_cpu(1)==2 && C.nr_iowait_cpu(2)==1)
 C.assert(C.nr_iowait_cpu(0)==0 && C.nr_iowait_cpu(3)==0)
 C.__atomic_store_n(&C.vmh_u64(&actors[1].model.pending),u64(1)<<14,3)
 C.assert(C.vinix_linuxkpi_task_enqueue(&actors[1].model));mutex_join(&actors[1])
 C.assert(actors[1].result==-C.EINTR && C.__atomic_load_n(&actors[1].acquired,2)==0)
 C.assert(C.vmh_mutex_waiters(&lockp)==3 && C.nr_iowait()==2 && C.nr_iowait_cpu(2)==0)
 for round:=u32(0);round<2;round++ {
  C.__atomic_store_n(&C.vmh_u64(&actors[3].model.pending),u64(1)<<if round!=0 { u32(8) } else { u32(14) },3)
  C.assert(C.vinix_linuxkpi_task_enqueue(&actors[3].model))
  wait_value(&actors[3].block_calls,round+2);count_wait(1,2)
  C.assert(!C.vinix_linuxkpi_task_queued(&actors[3].model))
  C.assert(C.vmh_mutex_waiters(&lockp)==3 && C.__atomic_load_n(&actors[3].acquired,2)==0 && C.nr_iowait()==2)
 }
 C.vmh_current_cpu=0;C.mutex_unlock(&lockp);order:=[u32(0),2,3]!
 for slot:=u32(0);slot<3;slot++ {
  index:=order[slot];wait_value(&actors[index].acquired,1)
  C.assert(C.atomic_long_read(&lockp.owner)==isize(&actors[index].model.storage[0]))
  C.assert(C.mutex_trylock(&lockp)==0)
  C.assert(C.nr_iowait()==if slot<2 { u32(1) } else { u32(0) })
  C.assert(C.nr_iowait_cpu(1)==if slot<2 { u32(1) } else { u32(0) })
  if slot+1<3 { C.assert(C.__atomic_load_n(&actors[order[slot+1]].acquired,2)==0) }
  C.__atomic_store_n(&actors[index].release,u32(1),3);mutex_join(&actors[index])
  C.assert(actors[index].result==0)
 }
 C.assert(!C.mutex_is_locked(&lockp) && C.vmh_mutex_waiters(&lockp)==0)
 zero_counts();C.mutex_destroy(&lockp)
} }
fn mutex_handoff_wins_signal() { unsafe {
 mut lockp:=C.mutex{};C.mutex_init(&lockp);C.mutex_lock(&lockp)
 mut actor:=MutexActor{};mutex_start(&actor,&lockp,mutex_interruptible,3,true)
 C.assert(C.nr_iowait_cpu(3)==1)
 C.__atomic_store_n(&C.vmh_u64(&actor.model.pending),u64(1)<<14,3);C.mutex_unlock(&lockp)
 wait_value(&actor.acquired,1);zero_counts()
 C.__atomic_store_n(&actor.release,u32(1),3);mutex_join(&actor)
 C.assert(actor.result==0 && C.vmh_mutex_waiters(&lockp)==0);C.mutex_destroy(&lockp)
} }
@[export: 'vmh_mutex_io_tests']
pub fn mutex_io_tests() { unsafe {
 mut controller:=C.native_task_model{};C.vmh_sync_model_init(&controller,279)
 C.vmh_native_task=&controller;C.vmh_current_cpu=0;before:=C.vmh_live_pages
 C.assert(!C.vmh_fail_allocation);C.vmh_fail_allocation=true
 mutex_fast()
 for round:=u32(0);round<16;round++ { mutex_fifo_and_cancel();mutex_handoff_wins_signal() }
 zero_counts();C.assert(C.vmh_live_pages==before && controller.iowait_cpu_plus_one==0)
 C.vmh_fail_allocation=false;C.vmh_native_task=nil;C.vmh_sync_model_destroy(&controller)
} }
