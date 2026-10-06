// SPDX-License-Identifier: GPL-2.0-only
// Independent original keyed/variable wait fixture; all stack records quiesce.
@[translated]
module waitbitfixture
#include "linuxkpi_wait_bit_fixture_v_contract.h"
struct C.task_struct { __state u32 vinix_thread voidptr }
struct C.completion {}
struct C.wait_queue_head {}
struct C.wait_queue_entry {}
struct C.wait_bit_key { flags voidptr bit_nr i32 }
@[typedef]
struct C.pthread_t {}
type BitThread = fn (voidptr) voidptr
type BitAction = fn (&C.wait_bit_key, i32) i32
fn C.vinix_linuxkpi_fixture_bit_thread(voidptr) voidptr
fn C.vinix_linuxkpi_fixture_bit_action_error(&C.wait_bit_key, i32) i32
fn C.vinix_linuxkpi_fixture_bit_action_clear(&C.wait_bit_key, i32) i32
fn C.pthread_create(voidptr, voidptr, BitThread, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.vinix_linuxkpi_test_task_signal(voidptr, u64)
fn C.vinix_linuxkpi_test_alloc_oom(i32)
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.completion_done(&C.completion) bool
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.wait_on_bit(&usize, i32, u32) i32
fn C.wait_on_bit_lock(&usize, i32, u32) i32
fn C.wait_on_bit_action(&usize, i32, BitAction, u32) i32
fn C.wait_on_bit_lock_action(&usize, i32, BitAction, u32) i32
fn C.wait_on_bit_timeout(&usize, i32, u32, usize) i32
fn C.bit_waitqueue(&usize, i32) &C.wait_queue_head
fn C.__var_waitqueue(voidptr) &C.wait_queue_head
fn C.wake_up_bit(&usize, i32)
fn C.wake_up_var(voidptr)
fn C.clear_and_wake_up_bit(i32, &usize)
fn C.clear_bit_unlock(i32, voidptr)
fn C.set_bit(i32, &usize)
fn C.test_bit(i32, &usize) bool
fn C.test_bit_acquire(i32, &usize) bool
fn C.init_wait_entry(&C.wait_queue_entry, i32)
fn C.prepare_to_wait(&C.wait_queue_head, &C.wait_queue_entry, i32)
fn C.finish_wait(&C.wait_queue_head, &C.wait_queue_entry)
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.wait_var_event(voidptr, u32)
fn C.wait_var_event_killable(voidptr, u32) i32
fn C.__wait_var_event_killable(voidptr, u32) i32
fn C.__wait_var_event_interruptible(voidptr, u32) i32
fn C.wait_var_event_timeout(voidptr, u32, usize) isize
fn C.READ_ONCE(u32) u32
fn C.WRITE_ONCE(u32, u32)
fn C.smp_mb()
fn C.smp_mb__after_atomic()
fn C.schedule()
fn C.cond_resched() i32
fn C.msleep(u32)
fn C.time_after_eq(usize, usize) bool
fn C.time_before(usize, usize) bool
fn C.__atomic_load_n(&u32, i32) u32
fn C.kmalloc(usize, u32) voidptr
fn C.kfree(voidptr)
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32
@[c_extern] __global C.current &C.task_struct
@[c_extern] __global C.jiffies usize
@[c_extern] __global C.TASK_DEAD u32
@[c_extern] __global C.TASK_UNINTERRUPTIBLE u32
@[c_extern] __global C.TASK_INTERRUPTIBLE u32
@[c_extern] __global C.TASK_KILLABLE u32
@[c_extern] __global C.GFP_KERNEL u32
@[c_extern] __global C.BITS_PER_LONG i32
@[c_extern] __global C.VKFW_TRACE i32
@[c_extern] __global C.EIO i32
@[c_extern] __global C.ENOMEM i32
@[c_extern] __global C.EAGAIN i32
@[c_extern] __global C.EINTR i32
@[c_extern] __global C.ENOSPC i32
@[c_extern] __global C.ERESTARTSYS i32

enum Operation { clear lock set var_wait var_killable }
struct BitTest {
mut:
 task &C.task_struct = unsafe { nil }
 thread C.pthread_t
 entered C.completion
 acquired C.completion
 release C.completion
 done C.completion
 word &usize = unsafe { nil }
 var voidptr = unsafe { nil }
 ready &u32 = unsafe { nil }
 payload &u32 = unsafe { nil }
 bit i32
 value i32
 result i32
 state u32
 operation Operation
 initialized bool
 started bool
}
@[export: 'vinix_linuxkpi_fixture_bit_thread']
pub fn worker(argument voidptr) voidptr {
 unsafe {
  mut test := &BitTest(argument)
  test.task = C.get_task_struct(C.current)
  C.complete(&test.entered)
  if test.operation == .clear {
   test.value = C.wait_on_bit(test.word, test.bit, test.state)
  } else if test.operation == .lock {
   test.value = C.wait_on_bit_lock(test.word, test.bit, test.state)
   if test.value == 0 {
    if !C.test_bit(test.bit, test.word) { test.result = -C.EIO }
    C.complete(&test.acquired)
    C.wait_for_completion(&test.release)
    C.clear_and_wake_up_bit(test.bit, test.word)
   }
  } else if test.operation == .set {
   mut wait := C.wait_queue_entry{}
   C.init_wait_entry(&wait, 0)
   queue := C.bit_waitqueue(test.word, test.bit)
   for {
    C.prepare_to_wait(queue, &wait, i32(C.TASK_UNINTERRUPTIBLE))
    if C.test_bit_acquire(test.bit, test.word) { break }
    C.schedule()
   }
   C.finish_wait(queue, &wait)
  } else if test.operation == .var_killable {
   test.value = C.wait_var_event_killable(test.var, C.READ_ONCE(*test.ready))
  } else {
   C.wait_var_event(test.var, C.READ_ONCE(*test.ready))
  }
  if test.value == 0 && test.payload != nil && C.READ_ONCE(*test.payload) != 42 { test.result = -C.EIO }
  C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, 0)
  if !C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() { test.result = -C.EIO }
  C.complete(&test.done)
  C.pthread_exit(nil)
  return nil
 }
}
fn start(test &BitTest, operation Operation, word &usize, bit i32, state u32, variable voidptr, ready &u32, payload &u32) i32 {
 unsafe {
  *test = BitTest{operation: operation, word: word, bit: bit, state: state, var: variable, ready: ready, payload: payload}
  C.init_completion(&test.entered); C.init_completion(&test.acquired)
  C.init_completion(&test.release); C.init_completion(&test.done)
  test.initialized = true
  if C.pthread_create(&test.thread, nil, C.vinix_linuxkpi_fixture_bit_thread, test) != 0 { return -C.ENOMEM }
  test.started = true
  return if C.wait_for_completion_timeout(&test.entered, 500) != 0 { i32(0) } else { -C.EIO }
 }
}
fn parked(test &BitTest) i32 {
 unsafe {
  deadline := C.jiffies + 500
  for C.__atomic_load_n(&test.task.__state, 2) != test.state || C.vinix_linuxkpi_task_queued(test.task.vinix_thread) {
   if C.time_after_eq(C.jiffies, deadline) { return -C.EIO }
   C.msleep(1)
  }
  return 0
 }
}
fn join(test &BitTest) i32 {
 unsafe {
  if !test.started { return 0 }
  C.BUG_ON(C.pthread_join(test.thread, nil) != 0)
  result := test.result
  for C.__atomic_load_n(&test.task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
  C.put_task_struct(test.task)
  test.started = false
  return result
 }
}
fn collision(words &usize, excluded u32) u32 {
 unsafe {
  queue := C.bit_waitqueue(words, 0)
  for i := u32(16); i < 1024; i++ { if i != excluded && usize(C.bit_waitqueue(&words[i], 0)) == usize(queue) { return i } }
  return 0
 }
}
fn keyed_body(tests &BitTest, words &usize, wrong_bit i32, collided u32, payload &u32) i32 {
 unsafe {
  mut result := i32(0)
  if start(&tests[0], .clear, words, 0, C.TASK_UNINTERRUPTIBLE, nil, nil, payload) != 0 ||
     start(&tests[1], .clear, words, wrong_bit, C.TASK_UNINTERRUPTIBLE, nil, nil, payload) != 0 ||
     start(&tests[2], .clear, &words[collided], 0, C.TASK_UNINTERRUPTIBLE, nil, nil, payload) != 0 { return -C.EIO }
  for i in 0 .. 3 { if parked(&tests[i]) != 0 { return -C.EIO } }
  C.WRITE_ONCE(*payload, u32(42))
  C.vinix_linuxkpi_test_alloc_oom(0)
  flags := C.vinix_linuxkpi_irq_save()
  C.clear_and_wake_up_bit(0, words)
  C.vinix_linuxkpi_irq_restore(flags)
  unexpected := C.kmalloc(1, C.GFP_KERNEL)
  C.vinix_linuxkpi_test_alloc_oom(-1)
  if unexpected != nil { C.kfree(unexpected); result = -C.EIO }
  if C.wait_for_completion_timeout(&tests[0].done, 500) == 0 || C.completion_done(&tests[1].done) ||
     C.completion_done(&tests[2].done) || !C.test_bit(wrong_bit, words) || !C.test_bit(0, &words[collided]) { result = -C.EIO }
  return result
 }
}
fn keyed() i32 {
 unsafe {
  mut words := [1024]usize{}
  mut tests := [3]BitTest{}
  mut payload := u32(0)
  mut wrong_bit := i32(0)
  for bit := i32(C.BITS_PER_LONG); bit < 1024 * C.BITS_PER_LONG; bit++ {
   if usize(C.bit_waitqueue(&words[0], bit)) == usize(C.bit_waitqueue(&words[0], 0)) { wrong_bit = bit; break }
  }
  if wrong_bit == 0 { return -C.EIO }
  collided := collision(&words[0], u32(wrong_bit / C.BITS_PER_LONG))
  if collided == 0 { return -C.EIO }
  C.set_bit(0, &words[0]); C.set_bit(wrong_bit, &words[0]); C.set_bit(0, &words[collided])
  mut result := keyed_body(&tests[0], &words[0], wrong_bit, collided, &payload)
  C.WRITE_ONCE(payload, u32(42))
  C.clear_and_wake_up_bit(0, &words[0]); C.clear_and_wake_up_bit(wrong_bit, &words[0]); C.clear_and_wake_up_bit(0, &words[collided])
  for i in 0 .. 3 { if join(&tests[i]) != 0 { result = -C.EIO } }
  if C.waitqueue_active(C.bit_waitqueue(&words[0], 0)) { result = -C.EIO }
  return result
 }
}
fn quota_body(tests &BitTest, words &usize, collided u32, payload &u32) i32 {
 unsafe {
  mut result := i32(0)
  for i in 0 .. 3 {
   word := if i != 0 { usize(words) } else { usize(&words[collided]) }
   if start(&tests[i], .lock, &usize(word), 0, C.TASK_UNINTERRUPTIBLE, nil, nil, payload) != 0 || parked(&tests[i]) != 0 { return -C.EIO }
  }
  C.clear_and_wake_up_bit(0, words)
  deadline := C.jiffies + 500
  for !C.completion_done(&tests[1].acquired) && !C.completion_done(&tests[2].acquired) {
   if C.time_after_eq(C.jiffies, deadline) { return -C.EIO }
   C.msleep(1)
  }
  first := if C.completion_done(&tests[1].acquired) { u32(1) } else { u32(2) }
  second := if first == 1 { u32(2) } else { u32(1) }
  if C.completion_done(&tests[0].acquired) || C.completion_done(&tests[second].acquired) || !C.test_bit(0, words) || parked(&tests[second]) != 0 { result = -C.EIO }
  C.complete(&tests[first].release)
  if C.wait_for_completion_timeout(&tests[second].acquired, 500) == 0 { result = -C.EIO }
  return result
 }
}
fn quota() i32 {
 unsafe {
  mut words := [1024]usize{}
  mut tests := [3]BitTest{}
  mut payload := u32(42)
  collided := collision(&words[0], 0)
  if collided == 0 { return -C.EIO }
  C.set_bit(0, &words[0]); C.set_bit(0, &words[collided])
  mut result := quota_body(&tests[0], &words[0], collided, &payload)
  for i in 0 .. 3 { if tests[i].initialized { C.complete_all(&tests[i].release) } }
  C.clear_and_wake_up_bit(0, &words[0]); C.clear_and_wake_up_bit(0, &words[collided])
  for i in 0 .. 3 { if join(&tests[i]) != 0 { result = -C.EIO } }
  if C.waitqueue_active(C.bit_waitqueue(&words[0], 0)) { result = -C.EIO }
  return result
 }
}
fn display() i32 {
 unsafe {
  mut word := usize(0); mut payload := u32(0); mut test := BitTest{}
  mut result := start(&test, .set, &word, 0, C.TASK_UNINTERRUPTIBLE, nil, nil, &payload)
  if result == 0 && parked(&test) != 0 { result = -C.EIO }
  C.WRITE_ONCE(payload, u32(42)); C.set_bit(0, &word); C.smp_mb__after_atomic(); C.wake_up_bit(&word, 0)
  if C.wait_for_completion_timeout(&test.done, 500) == 0 { result = -C.EIO }
  if join(&test) != 0 || C.waitqueue_active(C.bit_waitqueue(&word, 0)) { result = -C.EIO }
  return result
 }
}
fn interrupt() i32 {
 unsafe {
  mut word := usize(1); mut test := BitTest{}
  mut result := start(&test, .clear, &word, 0, C.TASK_INTERRUPTIBLE, nil, nil, nil)
  if result == 0 {
   if parked(&test) != 0 { result = -C.EIO }
   C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, u64(1) << 14)
   if C.wait_for_completion_timeout(&test.done, 500) == 0 || test.value != -C.EINTR || !C.test_bit(0, &word) { result = -C.EIO }
  }
  C.clear_and_wake_up_bit(0, &word)
  if join(&test) != 0 || C.waitqueue_active(C.bit_waitqueue(&word, 0)) { result = -C.EIO }
  return result
 }
}
fn variable_body(test &BitTest, killable bool, address voidptr, allocated &bool, ready &u32, payload &u32) i32 {
 unsafe {
  mut result := i32(0)
  started := start(test, if killable { Operation.var_killable } else { Operation.var_wait }, nil, 0,
     if killable { C.TASK_KILLABLE } else { C.TASK_UNINTERRUPTIBLE }, address, ready, payload)
  if started != 0 { return started }
  if parked(test) != 0 { return -C.EIO }
  if killable {
   C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, u64(1) << 14)
   if parked(test) != 0 || C.completion_done(&test.done) { result = -C.EIO }
   C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, u64(1) << 8)
   if C.wait_for_completion_timeout(&test.done, 500) == 0 || test.value != -C.ERESTARTSYS { result = -C.EIO }
  } else {
   if *allocated { C.kfree(address); *allocated = false }
   C.WRITE_ONCE(*payload, u32(42)); C.WRITE_ONCE(*ready, u32(1)); C.smp_mb()
   flags := C.vinix_linuxkpi_irq_save(); C.wake_up_var(address); C.vinix_linuxkpi_irq_restore(flags)
   if C.wait_for_completion_timeout(&test.done, 500) == 0 { result = -C.EIO }
  }
  return result
 }
}
fn variable(killable bool, inaccessible bool) i32 {
 unsafe {
  mut ready := u32(0); mut payload := u32(0); mut test := BitTest{}
  address := if inaccessible { voidptr(usize(1)) } else { C.kmalloc(64, C.GFP_KERNEL) }
  mut allocated := !inaccessible && address != nil
  if address == nil { return -C.ENOMEM }
  mut result := variable_body(&test, killable, address, &allocated, &ready, &payload)
  C.WRITE_ONCE(payload, u32(42)); C.WRITE_ONCE(ready, u32(1)); C.smp_mb(); C.wake_up_var(address)
  if join(&test) != 0 || C.waitqueue_active(C.__var_waitqueue(address)) { result = -C.EIO }
  if allocated { C.kfree(address) }
  return result
 }
}
@[export: 'vinix_linuxkpi_fixture_bit_action_error']
pub fn action_error(key &C.wait_bit_key, mode i32) i32 { return -C.ENOSPC }
@[export: 'vinix_linuxkpi_fixture_bit_action_clear']
pub fn action_clear(key &C.wait_bit_key, mode i32) i32 { C.clear_bit_unlock(key.bit_nr, key.flags); return -C.EINTR }
fn repeated() i32 {
 unsafe {
  mut word := usize(0); mut ready := u32(1); mut result := i32(0)
  for _ in 0 .. 256 {
   C.set_bit(0, &word)
   if C.wait_on_bit_timeout(&word, 0, C.TASK_UNINTERRUPTIBLE, 0) != -C.EAGAIN ||
      C.wait_on_bit_action(&word, 0, C.vinix_linuxkpi_fixture_bit_action_error, C.TASK_UNINTERRUPTIBLE) != -C.ENOSPC { result = -C.EIO }
   started := C.jiffies
   if C.wait_on_bit_timeout(&word, 0, C.TASK_UNINTERRUPTIBLE, 1) != -C.EAGAIN || C.time_before(C.jiffies, started + 1) { result = -C.EIO }
   if C.wait_on_bit_lock_action(&word, 0, C.vinix_linuxkpi_fixture_bit_action_clear, C.TASK_INTERRUPTIBLE) != 0 || !C.test_bit(0, &word) { result = -C.EIO }
   C.clear_and_wake_up_bit(0, &word)
   if C.wait_on_bit_timeout(&word, 0, C.TASK_UNINTERRUPTIBLE, 0) != 0 ||
      C.wait_var_event_timeout(&ready, C.READ_ONCE(ready), 0) != 1 || C.wait_var_event_timeout(&ready, u32(0), 1) != 0 { result = -C.EIO }
   if C.waitqueue_active(C.bit_waitqueue(&word, 0)) || C.waitqueue_active(C.__var_waitqueue(&ready)) { result = -C.EIO }
  }
  C.vinix_linuxkpi_test_task_signal(C.current.vinix_thread, u64(1) << 8)
  if C.wait_var_event_killable(&ready, C.READ_ONCE(ready)) != 0 ||
     C.__wait_var_event_killable(&ready, C.READ_ONCE(ready)) != 0 ||
     C.__wait_var_event_interruptible(&ready, C.READ_ONCE(ready)) != 0 ||
     C.wait_on_bit(&word, 0, C.TASK_INTERRUPTIBLE) != 0 { result = -C.EIO }
  C.vinix_linuxkpi_test_task_signal(C.current.vinix_thread, 0)
  if !C.task_is_running(C.current) || C.waitqueue_active(C.__var_waitqueue(&ready)) { result = -C.EIO }
  return result
 }
}
fn trace(message &char) { if C.VKFW_TRACE != 0 { C.kprintf(c'%s', message) } }
@[export: 'vinix_linuxkpi_wait_bit_native_selftest']
pub fn selftest() i32 {
 mut result := i32(0)
 trace(c'linuxkpi: wait-bit trace: repeated begin\n')
 if repeated() != 0 { C.kprintf(c'linuxkpi: wait-bit repeated/action/deadline checks failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: repeated end; keyed begin\n')
 if keyed() != 0 { C.kprintf(c'linuxkpi: wait-bit keyed collision/IRQ-off wake failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: keyed end; quota begin\n')
 if quota() != 0 { C.kprintf(c'linuxkpi: wait-bit exclusive quota failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: quota end; display begin\n')
 if display() != 0 { C.kprintf(c'linuxkpi: wait-bit ordinary SET waiter failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: display end; interrupt begin\n')
 if interrupt() != 0 { C.kprintf(c'linuxkpi: wait-bit signal cancellation failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: interrupt end; variable killable begin\n')
 if variable(true, false) != 0 { C.kprintf(c'linuxkpi: variable killable filtering failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: variable killable end; freed key begin\n')
 if variable(false, false) != 0 { C.kprintf(c'linuxkpi: variable freed-address wake failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: freed key end; inaccessible key begin\n')
 if variable(false, true) != 0 { C.kprintf(c'linuxkpi: variable inaccessible-address wake failed\n'); result = -C.EIO }
 trace(c'linuxkpi: wait-bit trace: inaccessible key end\n')
 return result
}
