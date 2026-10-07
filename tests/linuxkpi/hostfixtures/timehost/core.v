// SPDX-License-Identifier: GPL-2.0-or-later
// Independent conversions and timed-wait assertions from the original host fixture.
@[translated]
module timehost
#include "timehost_v_contract.h"

@[typedef] struct C.vmh_time_i128 {}
struct C.vmh_time_volatile_address { mut: value usize }
@[typedef] struct C.vmh_time_volatile_uint {}
struct C.timespec64 { mut: tv_sec i64, tv_nsec isize }
struct C.wait_queue_head {}
struct C.swait_queue_head {}
struct C.completion { mut: @wait C.swait_queue_head }
fn C.vmh_host_time_advance(C.vmh_u64)
fn C.vmh_time_expire_before_park()
fn C.vmh_timed_wait_worker(voidptr) voidptr
fn C.vinix_linuxkpi_time_tick(u64)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_time_selftest() i32
fn C.get_jiffies_64() u64
fn C.ktime_get_ns() u64
fn C.ktime_get_raw_ns() u64
fn C.ktime_get_coarse_ns() u64
fn C.ktime_get_resolution_ns() u32
fn C.ktime_get_ts64(&C.timespec64)
fn C.ktime_get_raw_ts64(&C.timespec64)
fn C.timespec64_to_ns(&C.timespec64) i64
fn C.jiffies_to_msecs(usize) u32
fn C.jiffies_to_usecs(usize) u32
fn C.jiffies64_to_msecs(C.vmh_u64) u64
fn C.jiffies64_to_nsecs(C.vmh_u64) u64
fn C.jiffies_to_clock_t(usize) usize
fn C.jiffies_64_to_clock_t(C.vmh_u64) u64
fn C.clock_t_to_jiffies(usize) usize
fn C.msecs_to_jiffies(u32) usize
fn C.usecs_to_jiffies(u32) usize
fn C.nsecs_to_jiffies64(C.vmh_u64) u64
fn C.time_after(usize, usize) bool
fn C.time_before(usize, usize) bool
fn C.time_after_eq(usize, usize) bool
fn C.time_in_range(usize, usize, usize) bool
fn C.time_after64(C.vmh_u64, C.vmh_u64) bool
fn C.time_before64(C.vmh_u64, C.vmh_u64) bool
fn C.ns_to_timespec64(i64) C.timespec64
fn C.set_normalized_timespec64(&C.timespec64, i64, isize)
fn C.jiffies_to_timespec64(usize, &C.timespec64)
fn C.timespec64_to_jiffies(&C.timespec64) usize
fn C.ktime_add_safe(i64, i64) i64
fn C.ktime_set(i64, usize) i64
fn C.ktime_to_us(i64) i64
fn C.ktime_to_ms(i64) i64
fn C.ktime_compare(i64, i64) i32
fn C.ktime_us_delta(i64, i64) i64
fn C.ktime_before(i64, i64) bool
fn C.__builtin_mul_overflow(i64, ...) bool
fn C.__builtin_add_overflow(C.vmh_time_i128, ...) bool
fn C.READ_ONCE(C.vmh_time_volatile_uint) u32
fn C.init_waitqueue_head(&C.wait_queue_head)
fn C.init_swait_queue_head(&C.swait_queue_head)
fn C.init_completion(&C.completion)
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.swait_active(&C.swait_queue_head) bool
fn C.complete(&C.completion)
fn C.completion_done(&C.completion) bool
fn C.schedule_timeout(isize) isize
fn C.wait_event_interruptible_timeout(C.wait_queue_head, ...) isize
fn C.wait_event_timeout(C.wait_queue_head, ...) isize
fn C.swait_event_interruptible_timeout_exclusive(C.swait_queue_head, ...) isize
fn C.swait_event_timeout_exclusive(C.swait_queue_head, ...) isize
fn C.msleep_interruptible(u32) usize
fn C.msleep(u32)
fn C.wait_for_completion_interruptible_timeout(&C.completion, usize) isize
fn C.wait_for_completion_killable_timeout(&C.completion, usize) isize
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.wake_up_all(&C.wait_queue_head)
fn C.swake_up_all(&C.swait_queue_head)
fn C.atomic_read(&C.atomic_t) i32
fn C.DECLARE_WAIT_QUEUE_HEAD(C.wait_queue_head)
fn C.DECLARE_COMPLETION_ONSTACK(C.completion)
@[c_extern] __global (
 C.jiffies usize
 C.jiffies_64 u64
 C.INITIAL_JIFFIES usize
 C.TICK_NSEC u64
 C.NSEC_PER_SEC i64
 C.UINT_MAX u32
 C.ULONG_MAX usize
 C.MAX_JIFFY_OFFSET usize
 C.U64_MAX u64
 C.S64_MAX i64
 C.S64_MIN i64
 C.KTIME_MAX i64
 C.KTIME_SEC_MAX i64
 C.TASK_INTERRUPTIBLE u32
 C.TASK_UNINTERRUPTIBLE u32
 C.TASK_KILLABLE u32
 C.ERESTARTSYS i32
 C.MAX_SCHEDULE_TIMEOUT isize
 C.vmh_time_queue C.wait_queue_head
 C.vmh_time_completion C.completion
)

fn native_word(value u64) C.vmh_u64 {
 mut word := C.vmh_u64{}
 unsafe { C.memcpy(&word, &value, 8) }
 return word
}
@[export: 'vmh_host_time_advance']
pub fn host_time_advance(native_ticks C.vmh_u64) {
 mut ticks := u64(0)
 unsafe { C.memcpy(&ticks, &native_ticks, 8) }
 now := u64(C.__atomic_add_fetch(&C.vmh_u64(&C.vmh_host_clock_ns), ticks * C.TICK_NSEC, 4))
 C.vinix_linuxkpi_time_tick(now)
}
fn advance(ticks u64) { C.vmh_host_time_advance(native_word(ticks)) }
// The compiler performs the original signed 128-bit reconstruction. Its native
// arithmetic intrinsics write borrowed, correctly typed stack output records.
fn reconstructs(ts &C.timespec64, nanos i64) bool {
 unsafe {
  mut product := C.vmh_time_i128{}
  mut total := C.vmh_time_i128{}
  mut expected := C.vmh_time_i128{}
  multiply_overflow := C.__builtin_mul_overflow(ts.tv_sec, C.NSEC_PER_SEC, &product)
  add_overflow := C.__builtin_add_overflow(product, ts.tv_nsec, &total)
  conversion_overflow := C.__builtin_mul_overflow(nanos, i64(1), &expected)
  return !multiply_overflow && !add_overflow && !conversion_overflow &&
   C.memcmp(&total, &expected, 16) == 0
 }
}
fn conversions() {
 unsafe {
  mut native_address := C.vmh_time_volatile_address{}
  native_address.value = usize(&C.jiffies)
  tick_address := native_address.value
  C.assert(tick_address == usize(&C.jiffies_64) && tick_address % 64 == 0)
  C.assert(C.jiffies == C.INITIAL_JIFFIES && C.get_jiffies_64() == C.INITIAL_JIFFIES)
  advance(3)
  C.assert(C.jiffies == C.INITIAL_JIFFIES + 3)
  C.vinix_linuxkpi_time_tick(0)
  C.assert(C.jiffies == C.INITIAL_JIFFIES + 3)
  C.assert(C.ktime_get_ns() == 3 * C.TICK_NSEC && C.ktime_get_raw_ns() == C.ktime_get_ns())
  C.assert(C.ktime_get_coarse_ns() == 3 * C.TICK_NSEC)
  C.assert(C.ktime_get_resolution_ns() == 1000000)
  mut ts := C.timespec64{}
  C.ktime_get_ts64(&ts)
  C.assert(ts.tv_sec == 0 && ts.tv_nsec == isize(3 * C.TICK_NSEC))
  C.ktime_get_raw_ts64(&ts)
  C.assert(C.timespec64_to_ns(&ts) == i64(C.ktime_get_raw_ns()))
  values := [usize(0), 1, 999, 1000, usize(C.UINT_MAX), C.MAX_JIFFY_OFFSET, C.ULONG_MAX]!
  for value in values {
   C.assert(C.jiffies_to_msecs(value) == u32(value))
   C.assert(C.jiffies_to_usecs(value) == u32(value * 1000))
   C.assert(C.jiffies64_to_msecs(native_word(u64(value))) == value)
   C.assert(C.jiffies64_to_nsecs(native_word(u64(value))) == u64(value) * C.TICK_NSEC)
   C.assert(usize(C.jiffies_to_clock_t(value)) == usize(value / 10))
   C.assert(C.jiffies_64_to_clock_t(native_word(u64(value))) == u64(value) / 10)
   C.assert(C.clock_t_to_jiffies(value) == if value >= C.ULONG_MAX / 10 { C.ULONG_MAX } else { value * 10 })
  }
  for value in u32(0)..u32(10000) {
   // Borrow the original native volatile integer storage for the runtime path.
   mut runtime_storage := value
   runtime_view := &C.vmh_time_volatile_uint(&runtime_storage)
   runtime_value := C.READ_ONCE(*runtime_view)
   C.assert(C.msecs_to_jiffies(runtime_value) == value)
   C.assert(C.usecs_to_jiffies(runtime_value) == (value + 999) / 1000)
   C.assert(C.nsecs_to_jiffies64(native_word(u64(value) * C.TICK_NSEC + 123)) == value)
  }
  C.assert(C.msecs_to_jiffies(C.UINT_MAX) == C.MAX_JIFFY_OFFSET)
  mut huge_storage := C.UINT_MAX
  huge_view := &C.vmh_time_volatile_uint(&huge_storage)
  huge := C.READ_ONCE(*huge_view)
  C.assert(C.msecs_to_jiffies(huge) == C.MAX_JIFFY_OFFSET)
  C.assert(C.usecs_to_jiffies(huge) == C.MAX_JIFFY_OFFSET)
  C.assert(C.time_after(usize(1), C.ULONG_MAX) && C.time_before(C.ULONG_MAX, usize(1)))
  C.assert(C.time_after_eq(C.ULONG_MAX, C.ULONG_MAX))
  C.assert(C.time_in_range(usize(0), C.ULONG_MAX - 1, usize(1)))
  C.assert(C.time_after64(native_word(1), native_word(C.U64_MAX)) && C.time_before64(native_word(C.U64_MAX), native_word(1)))
  nanos := [i64(0), 1, -1, C.NSEC_PER_SEC, -C.NSEC_PER_SEC - 1, C.S64_MAX, C.S64_MIN]!
  for nano in nanos {
   ts = C.ns_to_timespec64(nano)
   C.assert(ts.tv_nsec >= 0 && ts.tv_nsec < C.NSEC_PER_SEC)
   C.assert(reconstructs(&ts, nano))
  }
  C.set_normalized_timespec64(&ts, 5, -1)
  C.assert(ts.tv_sec == 4 && ts.tv_nsec == C.NSEC_PER_SEC - 1)
  for ticks in usize(0)..usize(10000) {
   C.jiffies_to_timespec64(ticks, &ts)
   C.assert(C.timespec64_to_ns(&ts) == i64(ticks) * i64(C.TICK_NSEC))
   C.assert(C.timespec64_to_jiffies(&ts) == ticks)
  }
  ts = C.timespec64{tv_nsec: 1}
  C.assert(C.timespec64_to_jiffies(&ts) == 1)
  ts = C.timespec64{tv_sec: C.S64_MAX}
  C.assert(C.timespec64_to_jiffies(&ts) <= C.MAX_JIFFY_OFFSET)
  C.assert(C.ktime_add_safe(C.KTIME_MAX, 1) == C.KTIME_MAX && C.ktime_add_safe(12, 15) == 27)
  C.assert(C.ktime_set(C.KTIME_SEC_MAX, 0) == C.KTIME_MAX)
  C.assert(C.ktime_to_us(12345) == 12 && C.ktime_to_ms(1234567) == 1)
  C.assert(C.ktime_compare(5, 6) < 0 && C.ktime_compare(5, 5) == 0)
  C.assert(C.ktime_us_delta(12000, 5000) == 7 && C.ktime_before(1, 2))
 }
}
enum Kind { task queue simple completion msleep }
struct TimedWait {
 mut:
 model C.native_task_model
 queue C.wait_queue_head
 simple C.swait_queue_head
 completion C.completion
 condition u32
 payload u32
 state u32
 armed u32
 proceed u32
 kind Kind
 timeout isize
 result isize
 delay_before_arm bool
 expire_before_park bool
 complete_at_expiry bool
 signal_at_expiry bool
}
@[export: 'vmh_time_expire_before_park']
pub fn expire_before_park() {
 unsafe {
  test := &TimedWait(C.vmh_expiry_test)
  if C.vinix_linuxkpi_time_waiters() == 0 {
   C.vmh_host_irq_restore_hook = C.vmh_time_expire_before_park
   return
  }
  advance(u64(test.timeout))
  if test.signal_at_expiry { C.__atomic_store_n(&C.vmh_u64(&test.model.pending), u64(1) << 14, 3) }
  if test.complete_at_expiry { test.payload = 0x1234; C.complete(&test.completion) }
  C.vmh_expiry_test = nil
 }
}
@[export: 'vmh_timed_wait_worker']
pub fn timed_wait_worker(argument voidptr) voidptr {
 unsafe {
  test := &TimedWait(argument)
  C.vmh_native_task = &test.model
  if test.expire_before_park {
   C.vmh_expiry_test = test
   C.vmh_host_irq_restore_hook = C.vmh_time_expire_before_park
  }
  task := C.current
  if test.kind == .task {
   C.set_current_state(test.state)
   C.__atomic_store_n(&test.armed, u32(1), 3)
   if test.delay_before_arm {
    for C.__atomic_load_n(&test.proceed, 2) == 0 { C.sched_yield() }
   }
   test.result = C.schedule_timeout(test.timeout)
  } else if test.kind == .queue {
   if test.state == C.TASK_INTERRUPTIBLE {
    test.result = C.wait_event_interruptible_timeout(test.queue, C.__atomic_load_n(&test.condition, 2), test.timeout)
   } else { test.result = C.wait_event_timeout(test.queue, C.__atomic_load_n(&test.condition, 2), test.timeout) }
  } else if test.kind == .simple {
   if test.state == C.TASK_INTERRUPTIBLE {
    test.result = C.swait_event_interruptible_timeout_exclusive(test.simple, C.__atomic_load_n(&test.condition, 2), test.timeout)
   } else { test.result = C.swait_event_timeout_exclusive(test.simple, C.__atomic_load_n(&test.condition, 2), test.timeout) }
  } else if test.kind == .msleep {
   if test.state == C.TASK_INTERRUPTIBLE { test.result = isize(C.msleep_interruptible(u32(test.timeout))) }
   else { C.msleep(u32(test.timeout)) }
  } else if test.state == C.TASK_INTERRUPTIBLE {
   test.result = C.wait_for_completion_interruptible_timeout(&test.completion, usize(test.timeout))
  } else if test.state == C.TASK_KILLABLE {
   test.result = C.wait_for_completion_killable_timeout(&test.completion, usize(test.timeout))
  } else { test.result = isize(C.wait_for_completion_timeout(&test.completion, usize(test.timeout))) }
  if test.kind != .task && test.kind != .msleep && test.result > 0 { C.assert(test.payload == 0x1234) }
  C.assert(C.task_is_running(task) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.assert(C.vmh_host_irq_restore_hook == unsafe { nil } && C.vmh_expiry_test == nil)
  C.vmh_native_task = nil
  return nil
 }
}
fn wait_init(test &TimedWait, kind Kind, state u32) {
 unsafe {
  *test = TimedWait{kind: kind, state: state, timeout: 10}
  C.vmh_sync_model_init(&test.model, 0)
  test.model.iteration = 1
  C.init_waitqueue_head(&test.queue)
  C.init_swait_queue_head(&test.simple)
  C.init_completion(&test.completion)
 }
}
fn cleanup(test &TimedWait, worker C.pthread_t) {
 unsafe {
  C.assert(C.pthread_join(worker, nil) == 0)
  C.assert(C.vinix_linuxkpi_time_waiters() == 0)
  C.assert(!C.waitqueue_active(&test.queue) && !C.swait_active(&test.simple))
  C.assert(!C.swait_active(&test.completion.@wait))
  C.vmh_sync_model_destroy(&test.model)
 }
}
fn parked(test &TimedWait) {
 unsafe {
  for C.__atomic_load_n(&test.model.parked, 2) != 1 { C.sched_yield() }
  C.assert(C.vinix_linuxkpi_time_waiters() == 1)
 }
}
fn timed_wait_tests() {
 unsafe {
  mut test := TimedWait{}
  mut worker := C.pthread_t{}
  for round in u32(0)..u32(10) {
   for kind_value in u32(0)..u32(4) {
    kind := Kind(kind_value)
    for mode in u32(0)..u32(2) {
     for outcome in u32(0)..u32(3) {
      wait_init(&test, kind, if mode != 0 { C.TASK_INTERRUPTIBLE } else { C.TASK_UNINTERRUPTIBLE })
      C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
      parked(&test)
      advance(3)
      if outcome == 0 { advance(7) }
      else if outcome == 1 {
       test.payload = 0x1234
       C.__atomic_store_n(&test.condition, u32(1), 3)
       if kind == .task { C.assert(C.wake_up_process(&C.task_struct(&test.model.storage[0])) != 0) }
       if kind == .queue { C.wake_up_all(&test.queue) }
       if kind == .simple { C.swake_up_all(&test.simple) }
       if kind == .completion { C.complete(&test.completion) }
      } else {
       C.__atomic_store_n(&C.vmh_u64(&test.model.pending), u64(1) << 14, 3)
       C.assert(C.vinix_linuxkpi_task_enqueue(&test.model))
       if mode == 0 {
        for C.vinix_linuxkpi_task_queued(&test.model) { C.sched_yield() }
        advance(7)
       }
      }
      cleanup(&test, worker)
      expected := if outcome == 0 || (outcome == 2 && mode == 0) { isize(0) }
       else if outcome == 2 && kind != .task { isize(-C.ERESTARTSYS) } else { isize(7) }
      C.assert(test.result == expected)
      advance(20)
     }
    }
   }
  }
  wait_init(&test, .task, C.TASK_UNINTERRUPTIBLE)
  test.delay_before_arm = true
  C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
  for C.__atomic_load_n(&test.armed, 2) == 0 { C.sched_yield() }
  C.assert(C.wake_up_process(&C.task_struct(&test.model.storage[0])) != 0)
  C.__atomic_store_n(&test.proceed, u32(1), 3)
  cleanup(&test, worker)
  C.assert(test.result == 10)
  for kind_value in u32(0)..u32(4) {
   wait_init(&test, Kind(kind_value), C.TASK_UNINTERRUPTIBLE)
   test.expire_before_park = true
   C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
   cleanup(&test, worker)
   C.assert(test.result == 0 && test.model.dequeued == 0 && test.model.parked == 0)
  }
  wait_init(&test, .completion, C.TASK_INTERRUPTIBLE)
  test.expire_before_park = true; test.signal_at_expiry = true
  C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
  cleanup(&test, worker)
  C.assert(test.result == 0)
  wait_init(&test, .completion, C.TASK_INTERRUPTIBLE)
  test.expire_before_park = true; test.complete_at_expiry = true; test.signal_at_expiry = true
  C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
  cleanup(&test, worker)
  C.assert(test.result == 1 && !C.completion_done(&test.completion))
  for fatal in u32(0)..u32(2) {
   wait_init(&test, .completion, C.TASK_KILLABLE)
   C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
   parked(&test)
   C.__atomic_store_n(&C.vmh_u64(&test.model.pending), u64(1) << if fatal != 0 { u32(8) } else { u32(14) }, 3)
   C.assert(C.vinix_linuxkpi_task_enqueue(&test.model))
   if fatal == 0 {
    for C.vinix_linuxkpi_task_queued(&test.model) { C.sched_yield() }
    advance(10)
   }
   cleanup(&test, worker)
   C.assert(test.result == if fatal != 0 { isize(-C.ERESTARTSYS) } else { isize(0) })
  }
  wait_init(&test, .task, C.TASK_UNINTERRUPTIBLE)
  test.timeout = C.MAX_SCHEDULE_TIMEOUT
  C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
  for C.__atomic_load_n(&test.model.parked, 2) != 1 { C.sched_yield() }
  C.assert(C.vinix_linuxkpi_time_waiters() == 0)
  advance(100)
  C.assert(C.wake_up_process(&C.task_struct(&test.model.storage[0])) != 0)
  cleanup(&test, worker)
  C.assert(test.result == C.MAX_SCHEDULE_TIMEOUT)
  wait_init(&test, .msleep, C.TASK_UNINTERRUPTIBLE)
  C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
  parked(&test)
  advance(3)
  C.assert(C.wake_up_process(&C.task_struct(&test.model.storage[0])) != 0)
  for C.vinix_linuxkpi_task_queued(&test.model) { C.sched_yield() }
  advance(8)
  cleanup(&test, worker)
  wait_init(&test, .msleep, C.TASK_INTERRUPTIBLE)
  C.assert(C.pthread_create(&worker, nil, C.vmh_timed_wait_worker, &test) == 0)
  parked(&test)
  advance(3)
  C.__atomic_store_n(&C.vmh_u64(&test.model.pending), u64(1) << 14, 3)
  C.assert(C.vinix_linuxkpi_task_enqueue(&test.model))
  cleanup(&test, worker)
  C.assert(test.result == 8)
 }
}
@[export: 'vmh_time_tests']
pub fn time_tests() {
 unsafe {
  mut controller := C.native_task_model{}
  C.vmh_sync_model_init(&controller, 20); C.vmh_native_task = &controller
  conversions()
  C.assert(C.vinix_linuxkpi_time_selftest() == 0)
  C.DECLARE_WAIT_QUEUE_HEAD(C.vmh_time_queue)
  C.assert(C.wait_event_timeout(C.vmh_time_queue, true, isize(0)) == 1)
  C.assert(C.wait_event_timeout(C.vmh_time_queue, false, isize(0)) == 0)
  warnings := C.atomic_read(&C.vmh_time_warnings)
  C.set_current_state(C.TASK_INTERRUPTIBLE)
  C.assert(C.schedule_timeout(-1) == 0 && C.task_is_running(C.current))
  C.assert(C.atomic_read(&C.vmh_time_warnings) == warnings + 1)
  C.set_current_state(C.TASK_UNINTERRUPTIBLE)
  C.assert(C.schedule_timeout(0) == 0 && C.task_is_running(C.current))
  C.DECLARE_COMPLETION_ONSTACK(C.vmh_time_completion)
  C.assert(C.wait_for_completion_timeout(&C.vmh_time_completion, 0) == 0)
  C.complete(&C.vmh_time_completion)
  C.assert(C.wait_for_completion_timeout(&C.vmh_time_completion, 0) == 1 && !C.completion_done(&C.vmh_time_completion))
  timed_wait_tests()
  C.assert(C.vinix_linuxkpi_time_waiters() == 0 && C.vmh_live_pages == C.vmh_permanent_pages)
  C.vmh_native_task = nil
  C.vmh_sync_model_destroy(&controller)
 }
}
