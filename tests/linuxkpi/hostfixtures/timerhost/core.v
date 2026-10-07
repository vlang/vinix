// SPDX-License-Identifier: GPL-2.0-or-later
// Independent timer queue, callback retirement and concurrent cancellation checks.
@[translated]
module timerhost
#include "timerhost_v_contract.h"

struct C.timer_list { mut: expires usize, function fn (&C.timer_list), flags u32 }
fn C.timer_setup_on_stack(&C.timer_list, fn (&C.timer_list), u32)
fn C.timer_setup(&C.timer_list, fn (&C.timer_list), u32)
fn C.destroy_timer_on_stack(&C.timer_list)
fn C.__TIMER_INITIALIZER(fn (&C.timer_list), u32) C.timer_list
fn C.timer_pending(&C.timer_list) bool
fn C.mod_timer(&C.timer_list, usize) i32
fn C.mod_timer_pending(&C.timer_list, usize) i32
fn C.timer_reduce(&C.timer_list, usize) i32
fn C.add_timer(&C.timer_list)
fn C.timer_delete(&C.timer_list) i32
fn C.timer_delete_sync(&C.timer_list) i32
fn C.try_to_del_timer_sync(&C.timer_list) i32
fn C.timer_shutdown(&C.timer_list) i32
fn C.timer_shutdown_sync(&C.timer_list) i32
fn C.vinix_linuxkpi_timer_selftest() i32
fn C.vinix_linuxkpi_timer_dispatch() i32
fn C.vinix_linuxkpi_timer_active() usize
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.preempt_count() u32
fn C.time_after_eq(usize, usize) bool
fn C.vmh_host_time_advance(C.vmh_u64)
fn C.atomic_read(&C.atomic_t) i32
fn C.kmalloc(usize, u32) voidptr
fn C.kfree(voidptr)
fn C.round_jiffies_up(usize) usize
fn C.round_jiffies_up_relative(usize) usize
fn C.round_jiffies(usize) usize
fn C.round_jiffies_relative(usize) usize
fn C.__round_jiffies_up(usize, i32) usize
fn C.vmh_timer_callback(&C.timer_list)
fn C.vmh_timer_static_callback(&C.timer_list)
fn C.vmh_timer_race_callback(&C.timer_list)
fn C.vmh_timer_dispatch_thread(voidptr) voidptr
fn C.vmh_timer_delete_thread(voidptr) voidptr
fn C.vmh_timer_race_thread(voidptr) voidptr
@[c_extern] __global (
 C.jiffies usize
 C.TIMER_IRQSAFE u32
 C.GFP_KERNEL u32
 C.HZ usize
)

enum Mode { count rearm hold free stop }
struct TimerTest {
 mut:
 timer C.timer_list // Original from_timer member is first.
 calls u32
 entered u32
 release u32
 irq_safe bool
 rearm_held bool
 mode Mode
 rearm_delay usize
 free_count &u32 = unsafe { nil }
}
@[export: 'vmh_timer_callback']
pub fn callback(timer &C.timer_list) {
 unsafe {
  test := &TimerTest(timer)
  C.assert(!C.vinix_linuxkpi_may_sleep() && C.preempt_count() != 0)
  C.assert((C.vinix_linuxkpi_irq_flags() & (usize(1) << 9) != 0) != test.irq_safe)
  C.assert(!C.timer_pending(timer) && C.time_after_eq(C.jiffies, timer.expires))
  C.__atomic_fetch_add(&test.calls, u32(1), 3)
  C.assert(C.try_to_del_timer_sync(timer) == -1)
  if test.mode == .rearm { C.assert(C.mod_timer(timer, C.jiffies) == 0) }
  if test.mode == .hold {
   if test.rearm_held { C.assert(C.mod_timer(timer, C.jiffies + test.rearm_delay) == 0) }
   C.__atomic_store_n(&test.entered, u32(1), 3)
   for C.__atomic_load_n(&test.release, 2) == 0 { C.sched_yield() }
  }
  if test.mode == .stop {
   C.assert(C.timer_shutdown(timer) == 0)
   C.assert(C.mod_timer(timer, C.jiffies) == 0)
  }
  if test.mode == .free {
   C.__atomic_fetch_add(test.free_count, u32(1), 3)
   C.kfree(test)
  }
 }
}
fn test_init(test &TimerTest, mode Mode, irq_safe bool) {
 unsafe {
  *test = TimerTest{mode: mode, irq_safe: irq_safe}
  C.timer_setup_on_stack(&test.timer, C.vmh_timer_callback, if irq_safe { C.TIMER_IRQSAFE } else { u32(0) })
 }
}
// The controller owns this stack counter through every synchronous dispatch.
fn set_free_count(test &TimerTest, counter &u32) { unsafe { test.free_count = counter } }
@[cinit] __global (
 static_timer_calls u32
 static_timer C.timer_list = C.__TIMER_INITIALIZER(C.vmh_timer_static_callback, u32(0))
)
@[export: 'vmh_timer_static_callback']
pub fn static_callback(timer &C.timer_list) { unsafe { static_timer_calls++ } }
fn advance(ticks u64) {
 mut word := C.vmh_u64{}
 unsafe { C.memcpy(&word, &ticks, 8) }
 C.vmh_host_time_advance(word)
}
fn queue_tests() {
 unsafe {
  mut test := TimerTest{}
  test_init(&test, .count, false)
  C.assert(C.vinix_linuxkpi_timer_selftest() == 0)
  C.assert(!C.timer_pending(&test.timer) && C.mod_timer_pending(&test.timer, C.jiffies) == 0)
  expires := C.jiffies + 10
  C.assert(C.mod_timer(&test.timer, expires) == 0 && C.timer_pending(&test.timer))
  C.assert(C.mod_timer(&test.timer, expires) == 1)
  warnings := C.atomic_read(&C.vmh_time_warnings)
  C.add_timer(&test.timer); C.add_timer(&test.timer)
  C.assert(test.timer.expires == expires && C.atomic_read(&C.vmh_time_warnings) == warnings + 1)
  C.assert(C.timer_reduce(&test.timer, expires + 2) == 1 && test.timer.expires == expires)
  C.assert(C.timer_reduce(&test.timer, expires - 1) == 1 && test.timer.expires == expires - 1)
  C.assert(C.mod_timer_pending(&test.timer, expires) == 1 && test.timer.expires == expires)
  advance(9)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 0 && test.calls == 0)
  advance(1)
  C.assert(C.timer_pending(&test.timer) && C.vinix_linuxkpi_timer_active() == 1)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 1 && test.calls == 1)
  C.assert(!C.timer_pending(&test.timer) && C.timer_delete(&test.timer) == 0)
  test.timer.expires = C.jiffies - 3
  C.add_timer(&test.timer)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 0)
  advance(1)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 1 && test.calls == 2)
  C.assert(C.mod_timer(&test.timer, C.jiffies + 2) == 0)
  advance(2)
  C.assert(C.timer_delete(&test.timer) == 1)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 0)
  C.assert(C.timer_reduce(&test.timer, C.jiffies + 2) == 0)
  C.assert(C.timer_shutdown_sync(&test.timer) == 1 && test.timer.function == nil)
  C.assert(C.mod_timer(&test.timer, C.jiffies) == 0 && C.mod_timer_pending(&test.timer, C.jiffies) == 0)
  test.timer.expires = C.jiffies
  C.add_timer(&test.timer)
  C.assert(!C.timer_pending(&test.timer))
  C.timer_setup(&test.timer, C.vmh_timer_callback, 0)
  C.assert(C.mod_timer(&test.timer, C.jiffies + 1) == 0)
  C.assert(C.timer_delete_sync(&test.timer) == 1 && test.timer.function != nil)
  C.destroy_timer_on_stack(&test.timer)
  static_timer.expires = C.jiffies + 1
  C.add_timer(&static_timer)
  advance(1)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 1 && static_timer_calls == 1)
  C.assert(C.timer_shutdown_sync(&static_timer) == 0)
  for safe in u32(0)..u32(2) {
   test_init(&test, .rearm, safe != 0)
   C.assert(C.mod_timer(&test.timer, C.jiffies) == 0)
   for i in u32(1)..u32(21) {
    advance(1)
    C.assert(C.vinix_linuxkpi_timer_dispatch() == 1 && test.calls == i)
    C.assert(C.vinix_linuxkpi_timer_dispatch() == 0 && C.timer_pending(&test.timer))
   }
   C.assert(C.timer_shutdown_sync(&test.timer) == 1)
   C.assert(C.vmh_interrupts && C.vmh_preempt_depth == 0)
  }
  test_init(&test, .stop, false)
  C.assert(C.mod_timer(&test.timer, C.jiffies) == 0)
  advance(1)
  C.assert(C.vinix_linuxkpi_timer_dispatch() == 1 && test.timer.function == nil)
  test_init(&test, .count, true)
  C.assert(C.mod_timer(&test.timer, C.jiffies + 10) == 0)
  flags := C.vinix_linuxkpi_irq_save()
  C.assert(C.timer_delete_sync(&test.timer) == 1 && !C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.assert(C.timer_shutdown_sync(&test.timer) == 0 && !C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.vinix_linuxkpi_irq_restore(flags)
  C.assert(C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.assert(C.vinix_linuxkpi_timer_active() == 0)
 }
}
struct ThreadTest {
 mut:
 model C.native_task_model
 test &TimerTest = unsafe { nil }
 spins u32
 finished u32
 shutdown bool
 result i32
}
@[export: 'vmh_timer_dispatch_thread']
pub fn dispatch_thread(argument voidptr) voidptr {
 unsafe {
  test := &ThreadTest(argument)
  C.vmh_native_task = &test.model
  test.result = C.vinix_linuxkpi_timer_dispatch()
  C.vmh_native_task = nil
  return nil
 }
}
@[export: 'vmh_timer_delete_thread']
pub fn delete_thread(argument voidptr) voidptr {
 unsafe {
  test := &ThreadTest(argument)
  C.vmh_native_task = &test.model
  C.vmh_timer_sync_spins = &test.spins
  test.result = if test.shutdown { C.timer_shutdown_sync(&test.test.timer) } else { C.timer_delete_sync(&test.test.timer) }
  C.vmh_timer_sync_spins = nil
  C.__atomic_store_n(&test.finished, u32(1), 3)
  C.vmh_native_task = nil
  return nil
 }
}
fn running_tests() {
 unsafe {
  for shutdown in u32(0)..u32(2) {
   for rearm in u32(0)..u32(2) {
    mut test := TimerTest{}
    test_init(&test, .hold, shutdown != 0)
    test.rearm_held = rearm != 0
    if shutdown != 0 { test.rearm_delay = 100 }
    mut dispatch := ThreadTest{test: &test}
    mut deletion := ThreadTest{test: &test, shutdown: shutdown != 0}
    C.vmh_sync_model_init(&dispatch.model, 1); C.vmh_sync_model_init(&deletion.model, 2)
    C.assert(C.mod_timer(&test.timer, C.jiffies) == 0)
    advance(1)
    mut caller := C.pthread_t{}
    mut deleter := C.pthread_t{}
    C.assert(C.pthread_create(&caller, nil, C.vmh_timer_dispatch_thread, &dispatch) == 0)
    for C.__atomic_load_n(&test.entered, 2) == 0 { C.sched_yield() }
    C.assert(C.try_to_del_timer_sync(&test.timer) == -1)
    advance(1)
    C.assert(C.vinix_linuxkpi_timer_dispatch() == 0)
    C.assert(C.pthread_create(&deleter, nil, C.vmh_timer_delete_thread, &deletion) == 0)
    for C.__atomic_load_n(&deletion.spins, 2) == 0 { C.sched_yield() }
    C.assert(C.__atomic_load_n(&deletion.finished, 2) == 0)
    if shutdown == 0 { C.assert(C.timer_delete(&test.timer) == i32(rearm)) }
    C.__atomic_store_n(&test.release, u32(1), 3)
    C.assert(C.pthread_join(caller, nil) == 0 && C.pthread_join(deleter, nil) == 0)
    C.assert(dispatch.result == 1 && deletion.result == i32(shutdown != 0 && rearm != 0) && test.calls == 1)
    C.assert(!C.timer_pending(&test.timer) && (test.timer.function != nil) != (shutdown != 0))
    C.vmh_sync_model_destroy(&dispatch.model); C.vmh_sync_model_destroy(&deletion.model)
    advance(20)
    C.assert(C.vinix_linuxkpi_timer_dispatch() == 0 && C.vinix_linuxkpi_timer_active() == 0)
   }
  }
  mut test := TimerTest{}
  test_init(&test, .hold, false)
  mut dispatch := ThreadTest{test: &test}
  C.vmh_sync_model_init(&dispatch.model, 1)
  C.assert(C.mod_timer(&test.timer, C.jiffies) == 0)
  advance(1)
  mut caller := C.pthread_t{}
  C.assert(C.pthread_create(&caller, nil, C.vmh_timer_dispatch_thread, &dispatch) == 0)
  for C.__atomic_load_n(&test.entered, 2) == 0 { C.sched_yield() }
  C.assert(C.timer_shutdown(&test.timer) == 0 && C.mod_timer(&test.timer, C.jiffies) == 0)
  C.__atomic_store_n(&test.release, u32(1), 3)
  C.assert(C.pthread_join(caller, nil) == 0 && C.timer_shutdown_sync(&test.timer) == 0)
  C.vmh_sync_model_destroy(&dispatch.model)
 }
}
struct RaceWorker {
 mut:
 model C.native_task_model
 timer &C.timer_list = unsafe { nil }
 done u32
}
@[export: 'vmh_timer_race_callback']
pub fn race_callback(timer &C.timer_list) { C.assert(!C.vinix_linuxkpi_may_sleep() && C.vmh_interrupts) }
@[export: 'vmh_timer_race_thread']
pub fn race_thread(argument voidptr) voidptr {
 unsafe {
  worker := &RaceWorker(argument)
  C.vmh_native_task = &worker.model
  for i in u32(0)..u32(500) {
   C.mod_timer(worker.timer, C.jiffies + i % 5)
   C.timer_reduce(worker.timer, C.jiffies + 1)
   C.mod_timer_pending(worker.timer, C.jiffies + 2)
   if i % 3 != 0 { C.timer_delete(worker.timer) } else { C.timer_delete_sync(worker.timer) }
  }
  C.__atomic_store_n(&worker.done, u32(1), 3)
  C.vmh_native_task = nil
  return nil
 }
}
fn race_tests() {
 unsafe {
  mut shared := C.timer_list{}
  C.timer_setup_on_stack(&shared, C.vmh_timer_race_callback, 0)
  mut workers := [4]RaceWorker{}
  mut threads := [4]C.pthread_t{}
  for i in u32(0)..u32(4) {
   workers[i] = RaceWorker{timer: &shared}
   C.vmh_sync_model_init(&workers[i].model, i)
   C.assert(C.pthread_create(&threads[i], nil, C.vmh_timer_race_thread, &workers[i]) == 0)
  }
  for {
   advance(1)
   C.vinix_linuxkpi_timer_dispatch()
   mut finished := u32(0)
   for i in u32(0)..u32(4) { finished += u32(C.__atomic_load_n(&workers[i].done, 2)) }
   C.sched_yield()
   if finished == 4 { break }
  }
  for i in u32(0)..u32(4) {
   C.assert(C.pthread_join(threads[i], nil) == 0)
   C.vmh_sync_model_destroy(&workers[i].model)
  }
  C.timer_shutdown_sync(&shared); C.destroy_timer_on_stack(&shared)
  C.assert(C.vinix_linuxkpi_timer_active() == 0)
 }
}
@[export: 'vmh_timer_tests']
pub fn timer_tests() {
 unsafe {
  mut controller := C.native_task_model{}
  C.vmh_sync_model_init(&controller, 20); C.vmh_native_task = &controller
  queue_tests(); running_tests()
  mut freed := u32(0)
  for i in u32(0)..u32(200) {
   test := &TimerTest(C.kmalloc(sizeof(TimerTest), C.GFP_KERNEL))
   C.assert(test != nil)
   test_init(test, .free, i & 1 != 0)
   set_free_count(test, &freed)
   C.assert(C.mod_timer(&test.timer, C.jiffies) == 0)
   advance(1)
   C.assert(C.vinix_linuxkpi_timer_dispatch() == 1)
   advance(20)
   C.assert(C.vinix_linuxkpi_timer_dispatch() == 0 && C.vinix_linuxkpi_timer_active() == 0)
   C.assert(C.vmh_live_pages == C.vmh_permanent_pages)
  }
  C.assert(freed == 200)
  for cpu in u32(0)..u32(4) {
   C.vmh_current_cpu = cpu
   for offset in usize(0)..usize(2000) {
    requested := C.jiffies + offset
    mut rounded := C.round_jiffies_up(requested)
    C.assert(C.time_after_eq(rounded, requested))
    C.assert((rounded + cpu * 3) % C.HZ == 0 || rounded == requested)
    C.assert(C.round_jiffies_up_relative(offset) == rounded - C.jiffies)
    rounded = C.round_jiffies(requested)
    C.assert((rounded + cpu * 3) % C.HZ == 0 || rounded == requested)
    C.assert(C.round_jiffies_relative(offset) == rounded - C.jiffies)
    C.assert(C.__round_jiffies_up(C.jiffies - 2000, i32(cpu)) == C.jiffies - 2000)
   }
  }
  C.vmh_current_cpu = 0
  race_tests()
  C.assert(C.vmh_interrupts && C.vmh_preempt_depth == 0 && C.vmh_live_pages == C.vmh_permanent_pages)
  C.vmh_native_task = nil; C.vmh_sync_model_destroy(&controller)
 }
}
