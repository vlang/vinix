// SPDX-License-Identifier: GPL-2.0-or-later
// Original task-view storage and 1,000-round native wait/wake race fixture.
@[translated]
module hosttask
#include "hosttask_v_contract.h"
fn C.task_pid_nr(&C.task_struct) i32
fn C.task_tgid_nr(&C.task_struct) i32
fn C.memchr_inv(voidptr,i32,usize) voidptr
fn C.signal_pending(&C.task_struct) i32
fn C.fatal_signal_pending(&C.task_struct) i32
fn C.signal_pending_state(u32,&C.task_struct) i32
fn C.__set_current_state(u32)
fn C.preempt_disable()
fn C.preempt_enable_no_resched()
fn C.need_resched() bool
fn C.cond_resched() i32
fn C.vmh_task_worker(voidptr) voidptr
fn C.vmh_task_wait_worker(voidptr) voidptr
@[c_extern] __global (
 C.TASK_INTERRUPTIBLE u32
 C.TASK_UNINTERRUPTIBLE u32
 C.TASK_KILLABLE u32
 C.TASK_IDLE u32
 C.TASK_WAKEKILL u32
 C.TASK_NOLOAD u32
 C.TASK_RUNNING u32
 C.TASK_DEAD u32
 C.PF_EXITING u32
)
@[export:'vmh_task_worker']
pub fn task_worker(argument voidptr) voidptr { unsafe {
 index:=*&u32(argument)
 mut model:=C.native_task_model{pid:i32(100+index),tgid:100,name:c'long-task-name-needs-truncation'}
 C.vmh_model_queue_init(&model);C.vmh_native_task=&model;C.vmh_current_cpu=index
 mut initial:=[13]char{};C.memcpy(&initial[0],c'initial-name',13)
 C.vinix_linuxkpi_task_init(&model.storage[0],&model,model.pid,model.tgid,&initial[0],12)
 C.memset(&initial[0],120,sizeof(initial));task:=C.current
 C.assert(usize(C.get_task_struct(task))==usize(task) && model.pins==1)
 C.put_task_struct(task);C.assert(model.pins==0 && C.task_is_running(task))
 C.assert(C.task_pid_nr(task)==model.pid && C.task_tgid_nr(task)==100)
 C.assert(C.strcmp(&task.comm[0],c'long-task-name-')==0 && task.flags==0)
 for i:=u32(0);i<1000;i++ {
  C.assert(C.vinix_linuxkpi_task_selftest()==0);C.vmh_current_cpu=(C.vmh_current_cpu+1)%4
  C.assert(usize(C.current)==usize(task) && C.task_pid_nr(task)==model.pid)
 }
 model.name=c'short'
 C.assert(C.strcmp(&C.current.comm[0],c'short')==0 && C.memchr_inv(&task.comm[5],0,11)==nil)
 mut child:=C.native_task_model{pid:i32(200+index),tgid:200}
 C.vinix_linuxkpi_task_inherit(&child.storage[0],&child,child.pid,child.tgid,task)
 child_view:=&C.task_struct(C.vinix_linuxkpi_task_view(&child.storage[0],&child,child.pid,child.tgid,nil,0,false))
 C.assert(C.strcmp(&child_view.comm[0],c'short')==0 && usize(child_view)!=usize(task))
 model.name=c'';C.assert(C.strcmp(&C.current.comm[0],c'initial-name')==0)
 C.assert(C.signal_pending(task)==0 && C.fatal_signal_pending(task)==0)
 model.pending=u64(1)<<14
 C.assert(C.signal_pending(task)!=0 && C.fatal_signal_pending(task)==0)
 C.set_current_state(C.TASK_INTERRUPTIBLE);C.schedule()
 C.assert(C.task_is_running(task) && C.vinix_linuxkpi_task_queued(&model))
 C.set_current_state(C.TASK_KILLABLE);C.assert(C.signal_pending_state(C.TASK_KILLABLE,task)==0)
 C.__set_current_state(C.TASK_RUNNING);model.masked=model.pending
 C.assert(C.signal_pending(task)==0 && C.fatal_signal_pending(task)==0)
 model.pending=model.pending|(u64(1)<<8);C.assert(C.signal_pending(task)!=0 && C.fatal_signal_pending(task)!=0)
 C.set_current_state(C.TASK_KILLABLE);C.schedule()
 C.assert(C.task_is_running(task) && C.vinix_linuxkpi_task_queued(&model))
 model.pending=0;model.masked=0;model.must_exit=true
 C.assert(C.signal_pending(task)!=0 && C.fatal_signal_pending(task)!=0 && C.current.flags&C.PF_EXITING!=0)
 model.must_exit=false;model.exiting=true;C.assert(C.current.flags&C.PF_EXITING!=0)
 model.exiting=false;C.assert(C.current.flags==C.PF_EXITING)
 C.vmh_resched_pending=true;C.preempt_disable()
 C.assert(C.need_resched() && C.cond_resched()==0 && C.need_resched())
 C.preempt_enable_no_resched();C.assert(C.need_resched() && C.cond_resched()==1 && !C.need_resched())
 C.assert(C.vmh_preempt_depth==0 && C.vmh_interrupts && model.yields==1001)
 C.assert(C.pthread_mutex_destroy(&model.queue_lock)==0 && C.pthread_cond_destroy(&model.queue_changed)==0)
 C.vmh_native_task=nil;return nil
} }
struct WaitTest { mut:
 model C.native_task_model
 task &C.task_struct = unsafe { nil }
 armed u32
 proceed u32
 completed u32
}
@[export:'vmh_task_wait_worker']
pub fn wait_worker(argument voidptr) voidptr { unsafe {
 test:=&WaitTest(argument);C.vmh_native_task=&test.model;task:=C.current
 test.task=C.get_task_struct(task)
 states:=[C.TASK_INTERRUPTIBLE,C.TASK_UNINTERRUPTIBLE,C.TASK_KILLABLE,C.TASK_IDLE]!
 for i:=u32(1);i<=1000;i++ {
  test.model.iteration=i;C.set_current_state(states[i%4]);C.__atomic_store_n(&test.armed,i,3)
  if i%3==0 { for C.__atomic_load_n(&test.proceed,2)<i { C.vinix_linuxkpi_spin_wait() } }
  C.schedule();C.assert(C.task_is_running(task) && C.vinix_linuxkpi_task_queued(C.vmh_native_task))
  C.__atomic_store_n(&test.completed,i,3)
 }
 C.__atomic_store_n(&test.model.dead,true,3);C.vinix_linuxkpi_task_dead(&test.model.storage[0])
 C.vmh_native_task=nil;return nil
} }
@[export:'vmh_task_wait_tests']
pub fn task_wait_tests() { unsafe {
 mut test:=WaitTest{model:C.native_task_model{pid:123,tgid:123,name:c'waiter'}}
 C.vmh_model_queue_init(&test.model)
 C.vinix_linuxkpi_task_init(&test.model.storage[0],&test.model,123,123,c'waiter',6)
 mut worker:=C.pthread_t{};C.assert(C.pthread_create(&worker,nil,C.vmh_task_wait_worker,&test)==0)
 for i:=u32(1);i<=1000;i++ {
  for C.__atomic_load_n(&test.armed,2)<i { C.vinix_linuxkpi_spin_wait() }
  if i%3==1 { for C.__atomic_load_n(&test.model.dequeued,2)<i { C.vinix_linuxkpi_spin_wait() } }
  if i%3==2 { for C.__atomic_load_n(&test.model.parked,2)<i { C.vinix_linuxkpi_spin_wait() } }
  if i%4!=0 { C.assert(C.wake_up_state(test.task,C.TASK_INTERRUPTIBLE)==0) }
  if i%3!=0 && i%4!=0 {
   C.__atomic_store_n(&C.vmh_u64(&test.model.pending),u64(1)<<14,0)
   C.assert(C.vinix_linuxkpi_task_enqueue(&test.model))
   for C.vinix_linuxkpi_task_queued(&test.model) { C.vinix_linuxkpi_spin_wait() }
   C.assert(C.__atomic_load_n(&test.completed,2)<i);C.assert(!C.task_is_running(test.task))
   C.__atomic_store_n(&C.vmh_u64(&test.model.pending),u64(0),0)
  }
  if i%4==2 { C.assert(C.wake_up_state(test.task,C.TASK_WAKEKILL)==1) }
  else if i%4==3 { C.assert(C.wake_up_state(test.task,C.TASK_NOLOAD)==1) }
  else { C.assert(C.wake_up_process(test.task)==1) }
  if i%3==0 { C.__atomic_store_n(&test.proceed,i,3) }
  for C.__atomic_load_n(&test.completed,2)<i { C.vinix_linuxkpi_spin_wait() }
 }
 C.assert(C.pthread_join(worker,nil)==0)
 C.assert(test.model.pins==1 && !C.task_is_running(test.task))
 C.assert(test.task.__state==C.TASK_DEAD && test.task.flags&C.PF_EXITING!=0)
 C.assert(C.wake_up_process(test.task)==0 && !C.vinix_linuxkpi_task_enqueue(&test.model))
 C.put_task_struct(test.task);C.assert(test.model.pins==0)
 C.assert(C.pthread_mutex_destroy(&test.model.queue_lock)==0 && C.pthread_cond_destroy(&test.model.queue_changed)==0)
} }
@[export:'vmh_task_tests']
pub fn task_tests() { unsafe {
 mut threads:=[4]C.pthread_t{};indexes:=[u32(0),1,2,3]!
 for i:=u32(0);i<4;i++ { C.assert(C.pthread_create(&threads[i],nil,C.vmh_task_worker,&indexes[i])==0) }
 for i:=u32(0);i<4;i++ { C.assert(C.pthread_join(threads[i],nil)==0) }
 C.assert(C.vmh_live_pages==C.vmh_permanent_pages)
} }
