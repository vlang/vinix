// SPDX-License-Identifier: GPL-2.0-or-later
// Independent minimum/absolute-expiry, signal and wake observations.
@[translated]
module usleephost
#include "usleephost_v_contract.h"

fn C.vinix_linuxkpi_time_tick(u64)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_clock_ns() u64
fn C.vinix_linuxkpi_irq_flags() usize
fn C.usleep_range(usize, usize)
fn C.usleep_idle_range(usize, usize)
fn C.usleep_range_state(usize, usize, u32)
fn C.vmh_usleep_first_sample()
fn C.vmh_usleep_expire_before_park()
fn C.vmh_usleep_host_worker(voidptr) voidptr
@[c_extern] __global (
 C.NSEC_PER_USEC u64
 C.TICK_NSEC u64
 C.TASK_UNINTERRUPTIBLE u32
 C.TASK_IDLE u32
 C.TASK_INTERRUPTIBLE u32
 C.TASK_KILLABLE u32
 C.TASK_RUNNING u32
)
enum Call { direct ordinary idle }
struct Test {
 mut:
 model C.native_task_model
 min usize
 max usize
 state u32
 sampled u32
 done u32
 call Call
 begin u64
 end u64
 expire_before_arm bool
 expire_before_park bool
}
fn advance(nanoseconds u64) {
 now := u64(C.__atomic_add_fetch(&C.vmh_u64(&C.vmh_host_clock_ns), nanoseconds, 4))
 C.vinix_linuxkpi_time_tick(now)
}
@[export: 'vmh_usleep_first_sample']
pub fn first_sample() {
 unsafe {
  test := &Test(C.vmh_usleep_host_current)
  if test.expire_before_arm {
   C.__atomic_fetch_add(&C.vmh_u64(&C.vmh_host_clock_ns), test.min * C.NSEC_PER_USEC + C.TICK_NSEC, 4)
  }
  C.__atomic_store_n(&test.sampled, u32(1), 3)
 }
}
@[export: 'vmh_usleep_expire_before_park']
pub fn expire_before_park() {
 unsafe {
  test := &Test(C.vmh_usleep_host_current)
  if C.vinix_linuxkpi_time_waiters() == 0 {
   C.vmh_host_irq_restore_hook = C.vmh_usleep_expire_before_park
   return
  }
  advance(test.min * C.NSEC_PER_USEC)
 }
}
@[export: 'vmh_usleep_host_worker']
pub fn worker(argument voidptr) voidptr {
 unsafe {
  test := &Test(argument)
  C.vmh_native_task = &test.model
  C.vmh_current_cpu = 3
  task := C.current
  flags := C.vinix_linuxkpi_irq_flags()
  depth := C.vmh_preempt_depth
  test.begin = C.vinix_linuxkpi_clock_ns()
  C.vmh_usleep_host_current = test
  C.vmh_host_clock_read_hook = C.vmh_usleep_first_sample
  if test.expire_before_park { C.vmh_host_irq_restore_hook = C.vmh_usleep_expire_before_park }
  if test.call == .ordinary { C.usleep_range(test.min, test.max) }
  else if test.call == .idle { C.usleep_idle_range(test.min, test.max) }
  else { C.usleep_range_state(test.min, test.max, test.state) }
  test.end = C.vinix_linuxkpi_clock_ns()
  C.assert(test.end - test.begin >= test.min * C.NSEC_PER_USEC)
  C.assert(usize(C.current) == usize(task) && C.task_is_running(task) && C.vmh_current_cpu == 3)
  C.assert(C.vinix_linuxkpi_irq_flags() == flags && C.vmh_preempt_depth == depth)
  C.assert(C.vmh_host_clock_read_hook == nil && C.vmh_host_irq_restore_hook == nil)
  C.vmh_usleep_host_current = nil
  C.__atomic_store_n(&test.done, u32(1), 3)
  C.vmh_native_task = nil
  return nil
 }
}
fn test_init(test &Test, min usize, max usize, state u32) {
 unsafe {
  *test = Test{min: min, max: max, state: state}
  C.vmh_sync_model_init(&test.model, 71)
  test.model.iteration = 1
 }
}
fn sampled(test &Test) {
 unsafe {
  for spin in u32(0)..u32(10000000) {
   if C.__atomic_load_n(&test.sampled, 2) != 0 { return }
   C.sched_yield()
  }
 }
 C.assert(usize(c'usleep worker did not sample its initial clock') == 0)
}
fn dequeued(test &Test) {
 unsafe {
  for spin in u32(0)..u32(10000000) {
   if C.__atomic_load_n(&test.model.dequeued, 2) == 1 { return }
   C.sched_yield()
  }
 }
 C.assert(usize(c'usleep worker did not evaluate its pending accepted signal') == 0)
}
fn parked(test &Test, total usize) {
 unsafe {
  for spin in u32(0)..u32(10000000) {
   if C.__atomic_load_n(&test.model.parked, 2) == 1 &&
    !C.vinix_linuxkpi_task_queued(&test.model) && C.vinix_linuxkpi_time_waiters() == total {
    task := &C.task_struct(&test.model.storage[0])
    C.assert(C.__atomic_load_n(&task.__state, 2) == test.state)
    return
   }
   C.sched_yield()
  }
 }
 C.assert(usize(c'usleep worker did not park with its real deadline') == 0)
}
fn join(test &Test, worker C.pthread_t, remaining usize) {
 unsafe {
  for spin in u32(0)..u32(10000000) {
   if C.__atomic_load_n(&test.done, 2) != 0 { break }
   C.sched_yield()
  }
  C.assert(C.__atomic_load_n(&test.done, 2) != 0)
  C.assert(C.pthread_join(worker, nil) == 0)
  C.assert(C.vinix_linuxkpi_time_waiters() == remaining)
  C.vmh_sync_model_destroy(&test.model)
 }
}
@[export: 'vmh_usleep_range_tests']
pub fn tests() {
 unsafe {
  C.assert(C.vmh_native_task == nil && C.vinix_linuxkpi_time_waiters() == 0)
  pages := C.vmh_live_pages
  C.vmh_fail_allocation = true
  mut test := Test{}
  mut worker := C.pthread_t{}
  states := [C.TASK_UNINTERRUPTIBLE, C.TASK_IDLE, C.TASK_INTERRUPTIBLE, C.TASK_KILLABLE]!
  ranges := [[usize(0), 0]!, [usize(0), 500]!, [usize(1), 1]!, [usize(6), 60]!,
   [usize(10), 30]!, [usize(25), 50]!, [usize(100), 250]!, [usize(400), 500]!,
   [usize(518), 1000]!, [usize(1000), 1500]!, [usize(2000), 3000]!, [usize(10000), 15000]!]!
  for mode in u32(0)..u32(4) {
   for i in u32(0)..u32(12) {
    test_init(&test, ranges[i][0], ranges[i][1], states[mode])
    if mode == 0 { test.call = .ordinary }
    if mode == 1 { test.call = .idle }
    C.assert(C.pthread_create(&worker, nil, C.vmh_usleep_host_worker, &test) == 0)
    if test.min != 0 {
     parked(&test, 1)
     advance(test.min * C.NSEC_PER_USEC - 1)
     C.assert(C.__atomic_load_n(&test.done, 2) == 0)
     C.assert(!C.vinix_linuxkpi_task_queued(&test.model))
     C.assert(C.vinix_linuxkpi_time_waiters() == 1)
     advance(1)
    }
    join(&test, worker, 0)
    C.assert(test.end - test.begin == test.min * C.NSEC_PER_USEC)
    if test.min == 0 { C.assert(test.model.dequeued == 0 && test.model.parked == 0) }
    advance(C.TICK_NSEC)
   }
  }
  for mode in u32(0)..u32(4) {
   test_init(&test, 10000, 10000, states[mode])
   C.assert(C.pthread_create(&worker, nil, C.vmh_usleep_host_worker, &test) == 0)
   parked(&test, 1)
   for wake in u32(0)..u32(8) {
    advance(C.TICK_NSEC)
    C.assert(C.wake_up_process(&C.task_struct(&test.model.storage[0])) != 0)
    parked(&test, 1)
    C.assert(C.__atomic_load_n(&test.done, 2) == 0)
   }
   advance(2 * C.TICK_NSEC - 1)
   C.assert(C.__atomic_load_n(&test.done, 2) == 0)
   advance(1)
   join(&test, worker, 0)
   C.assert(test.end - test.begin == 10 * C.TICK_NSEC)
  }
  for mode in u32(0)..u32(5) {
   state := if mode == 4 { C.TASK_RUNNING } else { states[mode] }
   test_init(&test, 1000, 1000, state)
   test.model.pending = u64(1) << if state == C.TASK_KILLABLE { u32(8) } else { u32(14) }
   C.assert(C.pthread_create(&worker, nil, C.vmh_usleep_host_worker, &test) == 0)
   if state == C.TASK_UNINTERRUPTIBLE || state == C.TASK_IDLE { parked(&test, 1) }
   else if state == C.TASK_RUNNING { sampled(&test) }
   else { dequeued(&test) }
   advance(C.TICK_NSEC - 1)
   C.assert(C.__atomic_load_n(&test.done, 2) == 0)
   advance(1)
   join(&test, worker, 0)
   C.assert(test.model.pending == (u64(1) << if state == C.TASK_KILLABLE { u32(8) } else { u32(14) }))
   if state == C.TASK_INTERRUPTIBLE || state == C.TASK_KILLABLE || state == C.TASK_RUNNING {
    C.assert(test.model.parked == 0)
   }
  }
  test_init(&test, 1000, 1000, C.TASK_KILLABLE)
  test.model.pending = u64(1) << 14
  C.assert(C.pthread_create(&worker, nil, C.vmh_usleep_host_worker, &test) == 0)
  parked(&test, 1)
  advance(C.TICK_NSEC - 1)
  C.assert(C.__atomic_load_n(&test.done, 2) == 0)
  advance(1)
  join(&test, worker, 0)
  C.assert(test.model.pending == u64(1) << 14)
  for point in u32(0)..u32(2) {
   test_init(&test, 1000, 2000, C.TASK_UNINTERRUPTIBLE)
   test.expire_before_arm = point == 0
   test.expire_before_park = point != 0
   C.assert(C.pthread_create(&worker, nil, C.vmh_usleep_host_worker, &test) == 0)
   join(&test, worker, 0)
   C.assert(test.model.dequeued == 0 && test.model.parked == 0)
   C.vinix_linuxkpi_time_tick(C.vinix_linuxkpi_clock_ns())
  }
  mut second := Test{}
  mut second_worker := C.pthread_t{}
  test_init(&test, 100, 200, C.TASK_UNINTERRUPTIBLE)
  test_init(&second, 400, 500, C.TASK_IDLE)
  C.assert(C.pthread_create(&worker, nil, C.vmh_usleep_host_worker, &test) == 0)
  parked(&test, 1)
  C.assert(C.pthread_create(&second_worker, nil, C.vmh_usleep_host_worker, &second) == 0)
  parked(&second, 2)
  advance(100 * C.NSEC_PER_USEC)
  join(&test, worker, 1)
  C.assert(C.__atomic_load_n(&second.done, 2) == 0)
  advance(300 * C.NSEC_PER_USEC)
  join(&second, second_worker, 0)
  advance(100 * C.TICK_NSEC)
  C.vmh_fail_allocation = false
  C.assert(C.vmh_live_pages == pages && C.vmh_native_task == nil && C.vmh_interrupts && C.vmh_preempt_depth == 0)
 }
}
