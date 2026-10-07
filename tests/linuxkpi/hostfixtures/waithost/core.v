// SPDX-License-Identifier: GPL-2.0-or-later
// Independent keyed waits, collisions, signal filtering and absolute deadlines.
@[translated]
module waithost
#include "waithost_v_contract.h"

struct C.wait_queue_head {}
struct C.wait_queue_entry {}
struct C.wait_bit_key { mut: flags &usize, bit_nr i32, timeout usize }
struct C.wait_bit_queue_entry {}
type Action = fn (&C.wait_bit_key, i32) i32
fn C.vmh_wait_bit_action(&C.wait_bit_key, i32) i32
fn C.vmh_wait_bit_custom_action(&C.wait_bit_key, i32) i32
fn C.vmh_wait_bit_clear_hook()
fn C.vmh_wait_bit_expiry_hook()
fn C.vmh_wait_bit_actor_thread(voidptr) voidptr
fn C.vmh_queue_waiters(&C.wait_queue_head) u32
fn C.vmh_host_time_advance(C.vmh_u64)
fn C.bit_wait(&C.wait_bit_key, i32) i32
fn C.bit_wait_timeout(&C.wait_bit_key, i32) i32
fn C.wait_bit_init() i32
fn C.bit_waitqueue(&usize, i32) &C.wait_queue_head
fn C.__var_waitqueue(voidptr) &C.wait_queue_head
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.wait_on_bit(&usize, i32, u32) i32
fn C.wait_on_bit_action(&usize, i32, Action, u32) i32
fn C.wait_on_bit_lock(&usize, i32, u32) i32
fn C.wait_on_bit_lock_action(&usize, i32, Action, u32) i32
fn C.wait_on_bit_timeout(&usize, i32, u32, usize) i32
fn C.out_of_line_wait_on_bit_timeout(&usize, i32, Action, u32, usize) i32
fn C.DEFINE_WAIT(C.wait_queue_entry)
fn C.DECLARE_WAIT_QUEUE_HEAD(C.wait_queue_head)
fn C.DEFINE_WAIT_BIT(C.wait_bit_queue_entry, &usize, i32)
fn C.prepare_to_wait(&C.wait_queue_head, &C.wait_queue_entry, u32)
fn C.finish_wait(&C.wait_queue_head, &C.wait_queue_entry)
fn C.__wait_on_bit_lock(&C.wait_queue_head, &C.wait_bit_queue_entry, Action, u32) i32
fn C.__wait_on_bit(&C.wait_queue_head, &C.wait_bit_queue_entry, Action, u32) i32
fn C.set_bit(i32, &usize)
fn C.clear_bit(i32, &usize)
fn C.test_bit(i32, &usize) bool
fn C.test_bit_acquire(i32, &usize) bool
fn C.wake_up_bit(&usize, i32)
fn C.clear_and_wake_up_bit(i32, &usize)
fn C.test_and_clear_wake_up_bit(i32, &usize) bool
fn C.store_release_wake_up(&u32, u32)
fn C.smp_mb()
fn C.smp_mb__after_atomic()
fn C.wake_up_var(voidptr)
fn C.wait_var_event(voidptr, ...)
fn C.wait_var_event_interruptible(voidptr, ...) i32
fn C.wait_var_event_killable(voidptr, ...) i32
fn C.__wait_var_event_interruptible(voidptr, ...) i32
fn C.__wait_var_event_killable(voidptr, ...) i32
fn C.wait_var_event_timeout(voidptr, ...) isize
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.READ_ONCE(usize) usize
fn C.WRITE_ONCE(usize, usize)
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
@[c_extern] __global (
 C.jiffies usize
 C.BITS_PER_LONG i32
 C.TASK_INTERRUPTIBLE u32
 C.TASK_UNINTERRUPTIBLE u32
 C.TASK_KILLABLE u32
 C.EIO i32
 C.EINTR i32
 C.EAGAIN i32
 C.ERESTARTSYS i32
 C.ULONG_MAX usize
 C.PROT_NONE i32
 C.MAP_PRIVATE i32
 C.MAP_ANONYMOUS i32
 C.MAP_FAILED voidptr
 C.vmh_set_wait C.wait_queue_entry
 C.vmh_custom_queue C.wait_queue_head
 C.vmh_custom_wait C.wait_bit_queue_entry
)
fn wait_value(value &u32, target u32) {
 for spin in u32(0)..u32(1000000) {
  if C.__atomic_load_n(value, 2) >= target { return }
  C.sched_yield()
 }
 C.assert(usize(c'bit/variable wait did not make progress') == 0)
}
enum Operation { normal lock timed set var_normal var_interrupt var_killable var_timed }
struct Actor {
 mut:
 model C.native_task_model
 thread C.pthread_t
 word &usize = unsafe { nil }
 key voidptr
 condition &u32 = unsafe { nil }
 payload &u32 = unsafe { nil }
 operation Operation
 state u32
 started u32
 actions u32
 awakened u32
 action_release u32
 returned u32
 release u32
 done u32
 bit i32
 timeout isize
 result isize
 gate_action bool
 clear_before_park bool
 success_at_expiry bool
 track_timeout bool
}
fn advance(ticks u64) {
 mut word := C.vmh_u64{}
 unsafe { C.memcpy(&word, &ticks, 8) }
 C.vmh_host_time_advance(word)
}
@[export: 'vmh_wait_bit_action']
pub fn action(key &C.wait_bit_key, mode i32) i32 {
 unsafe {
  actor := &Actor(C.vmh_wait_bit_test_current)
  C.assert(actor != nil && usize(key.flags) == usize(actor.word) && key.bit_nr == actor.bit)
  C.__atomic_fetch_add(&actor.actions, u32(1), 3)
  result := if actor.operation == .timed { C.bit_wait_timeout(key, mode) } else { C.bit_wait(key, mode) }
  C.__atomic_fetch_add(&actor.awakened, u32(1), 3)
  if actor.gate_action { wait_value(&actor.action_release, 1) }
  return result
 }
}
@[export: 'vmh_wait_bit_clear_hook']
pub fn clear_hook() {
 unsafe {
  actor := &Actor(C.vmh_wait_bit_test_current)
  C.assert(actor != nil && actor.clear_before_park)
  if C.vmh_queue_waiters(C.bit_waitqueue(actor.word, actor.bit)) == 0 {
   C.vmh_host_irq_restore_hook = C.vmh_wait_bit_clear_hook
   return
  }
  if actor.payload != nil { *actor.payload = 0xabc123 }
  C.clear_and_wake_up_bit(actor.bit, actor.word)
 }
}
@[export: 'vmh_wait_bit_expiry_hook']
pub fn expiry_hook() {
 unsafe {
  actor := &Actor(C.vmh_wait_bit_test_current)
  C.assert(actor != nil && actor.success_at_expiry)
  if C.vinix_linuxkpi_time_waiters() == 0 {
   C.vmh_host_irq_restore_hook = C.vmh_wait_bit_expiry_hook
   return
  }
  advance(u64(actor.timeout))
  if actor.payload != nil { *actor.payload = 0xabc123 }
  C.store_release_wake_up(actor.condition, 1)
 }
}
@[export: 'vmh_wait_bit_actor_thread']
pub fn actor_thread(argument voidptr) voidptr {
 unsafe {
  actor := &Actor(argument)
  C.vmh_native_task = &actor.model
  C.vmh_current_cpu = u32(actor.model.pid % 4)
  C.vmh_wait_bit_test_current = actor
  C.__atomic_store_n(&actor.started, u32(1), 3)
  if actor.clear_before_park { C.vmh_host_irq_restore_hook = C.vmh_wait_bit_clear_hook }
  if actor.success_at_expiry { C.vmh_host_irq_restore_hook = C.vmh_wait_bit_expiry_hook }
  match actor.operation {
   .normal { actor.result = C.wait_on_bit_action(actor.word, actor.bit, C.vmh_wait_bit_action, actor.state) }
   .lock { actor.result = C.wait_on_bit_lock_action(actor.word, actor.bit, C.vmh_wait_bit_action, actor.state) }
   .timed {
    actor.result = if actor.track_timeout {
     C.out_of_line_wait_on_bit_timeout(actor.word, actor.bit, C.vmh_wait_bit_action, actor.state, usize(actor.timeout))
    } else { C.wait_on_bit_timeout(actor.word, actor.bit, actor.state, usize(actor.timeout)) }
   }
   .set {
    queue := C.bit_waitqueue(actor.word, actor.bit)
    C.DEFINE_WAIT(C.vmh_set_wait)
    for {
     C.prepare_to_wait(queue, &C.vmh_set_wait, actor.state)
     if C.test_bit_acquire(actor.bit, actor.word) { break }
     C.schedule()
    }
    C.finish_wait(queue, &C.vmh_set_wait)
   }
   .var_normal { C.wait_var_event(actor.key, C.__atomic_load_n(actor.condition, 2)) }
   .var_interrupt { actor.result = C.wait_var_event_interruptible(actor.key, C.__atomic_load_n(actor.condition, 2)) }
   .var_killable { actor.result = C.wait_var_event_killable(actor.key, C.__atomic_load_n(actor.condition, 2)) }
   .var_timed { actor.result = C.wait_var_event_timeout(actor.key, C.__atomic_load_n(actor.condition, 2), actor.timeout) }
  }
  C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.assert(C.vmh_host_irq_restore_hook == nil)
  if actor.payload != nil && actor.result >= 0 { C.assert(*actor.payload == 0xabc123) }
  C.__atomic_store_n(&actor.returned, u32(1), 3)
  if actor.operation == .lock && actor.result == 0 {
   C.assert(C.test_bit(actor.bit, actor.word))
   wait_value(&actor.release, 1)
   C.clear_and_wake_up_bit(actor.bit, actor.word)
  }
  C.__atomic_store_n(&actor.done, u32(1), 3)
  C.vmh_wait_bit_test_current = nil; C.vmh_native_task = nil
  return nil
 }
}
fn start(actor &Actor, operation Operation, word &usize, bit i32, state u32) {
 unsafe {
  actor.operation = operation; actor.word = word
  if actor.key == nil { actor.key = word }
  actor.bit = bit; actor.state = state
  C.vmh_sync_model_init(&actor.model, 220)
  actor.model.iteration = 1
  C.assert(C.pthread_create(&actor.thread, nil, C.vmh_wait_bit_actor_thread, actor) == 0)
  wait_value(&actor.started, 1)
 }
}
fn parked(actor &Actor) {
 unsafe {
  wait_value(&actor.model.parked, 1)
  C.assert(!C.vinix_linuxkpi_task_queued(&actor.model))
  queue := if actor.operation >= .var_normal { C.__var_waitqueue(actor.key) } else { C.bit_waitqueue(actor.word, actor.bit) }
  C.assert(C.waitqueue_active(queue))
 }
}
fn join(actor &Actor) {
 unsafe {
  wait_value(&actor.done, 1)
  C.assert(C.pthread_join(actor.thread, nil) == 0)
  C.vmh_sync_model_destroy(&actor.model)
 }
}
fn signal_actor(actor &Actor, signal u64) {
 unsafe {
  C.__atomic_store_n(&C.vmh_u64(&actor.model.pending), signal, 3)
  C.assert(C.vinix_linuxkpi_task_enqueue(&actor.model))
 }
}
fn basics() {
 unsafe {
  mut words := [3]usize{}
  C.assert(C.wait_on_bit(&words[0], C.BITS_PER_LONG + 5, C.TASK_UNINTERRUPTIBLE) == 0)
  C.assert(C.wait_on_bit_timeout(&words[0], 3, C.TASK_INTERRUPTIBLE, 0) == 0)
  C.assert(C.wait_on_bit_lock(&words[0], C.BITS_PER_LONG + 5, C.TASK_UNINTERRUPTIBLE) == 0)
  C.assert(C.test_bit(C.BITS_PER_LONG + 5, &words[0]))
  C.clear_and_wake_up_bit(C.BITS_PER_LONG + 5, &words[0])
  for early in u32(0)..u32(2) {
   mut payload := u32(0)
   C.set_bit(C.BITS_PER_LONG + 5, &words[0])
   mut actor := Actor{payload: &payload, clear_before_park: early != 0}
   start(&actor, .normal, &words[0], C.BITS_PER_LONG + 5, C.TASK_UNINTERRUPTIBLE)
   if early == 0 {
    parked(&actor)
    flags := C.vinix_linuxkpi_irq_save()
    payload = 0xabc123
    C.clear_and_wake_up_bit(C.BITS_PER_LONG + 5, &words[0])
    C.assert(!C.vmh_interrupts)
    C.vinix_linuxkpi_irq_restore(flags)
   }
   join(&actor)
   C.assert(actor.result == 0 && !C.waitqueue_active(C.bit_waitqueue(&words[0], C.BITS_PER_LONG + 5)))
   if early != 0 { C.assert(actor.model.parked == 0) }
  }
  mut set_actor := Actor{}
  start(&set_actor, .set, &words[0], 11, C.TASK_UNINTERRUPTIBLE)
  parked(&set_actor)
  C.set_bit(11, &words[0]); C.smp_mb__after_atomic(); C.wake_up_bit(&words[0], 11)
  join(&set_actor)
  C.assert(set_actor.result == 0 && C.test_bit(11, &words[0]))
  C.clear_and_wake_up_bit(11, &words[0])
 }
}
fn collision_bits(word &usize, first &i32, second &i32) {
 unsafe {
  *first = -1; *second = -1
  for a := i32(0); a < 8 * C.BITS_PER_LONG && *first < 0; a++ {
   mut b := if a + 1 > C.BITS_PER_LONG { a + 1 } else { C.BITS_PER_LONG }
   for b < 8 * C.BITS_PER_LONG {
    if usize(C.bit_waitqueue(word, a)) == usize(C.bit_waitqueue(word, b)) {
     *first = a; *second = b; break
    }
    b++
   }
  }
  C.assert(*first >= 0 && *second > *first)
 }
}
fn collision_addresses(storage voidptr, stride usize, count usize, variable bool, first &voidptr, second &voidptr) {
 unsafe {
  mut buckets := [256]&C.wait_queue_head{}
  mut keys := [256]voidptr{}
  mut used := u32(0)
  *first = nil; *second = nil
  for i := usize(0); i < count; i++ {
   key := voidptr(&u8(storage) + i * stride)
   bucket := if variable { C.__var_waitqueue(key) } else { C.bit_waitqueue(&usize(key), 0) }
   for j := u32(0); j < used; j++ {
    if usize(buckets[j]) == usize(bucket) { *first = keys[j]; *second = key; return }
   }
   C.assert(used < 256)
   buckets[used] = bucket; keys[used] = key; used++
  }
 }
 C.assert(usize(c'sample did not contain a keyed wait collision') == 0)
}
fn collisions() {
 unsafe {
  mut words := [1024][8]usize{}
  mut address_first := voidptr(nil)
  mut address_second := voidptr(nil)
  mut first := i32(0)
  mut second := i32(0)
  collision_bits(&words[0][0], &first, &second)
  collision_addresses(&words[0][0], sizeof(words[0]), 1024, false, &address_first, &address_second)
  for different_address in u32(0)..u32(2) {
   matching_word := if different_address != 0 { &usize(address_first) } else { &words[0][0] }
   wrong_word := if different_address != 0 { &usize(address_second) } else { &words[0][0] }
   matching_bit := if different_address != 0 { i32(0) } else { first }
   wrong_bit := if different_address != 0 { i32(0) } else { second }
   C.set_bit(matching_bit, matching_word); C.set_bit(wrong_bit, wrong_word)
   mut matching := Actor{}
   mut wrong := Actor{}
   start(&wrong, .normal, wrong_word, wrong_bit, C.TASK_UNINTERRUPTIBLE); parked(&wrong)
   start(&matching, .normal, matching_word, matching_bit, C.TASK_UNINTERRUPTIBLE); parked(&matching)
   C.assert(C.vmh_queue_waiters(C.bit_waitqueue(matching_word, matching_bit)) == 2)
   C.wait_bit_init()
   C.wake_up_bit(matching_word, matching_bit)
   C.assert(!C.vinix_linuxkpi_task_queued(&matching.model))
   C.assert(!C.vinix_linuxkpi_task_queued(&wrong.model))
   C.assert(C.test_and_clear_wake_up_bit(matching_bit, matching_word))
   C.assert(!C.test_and_clear_wake_up_bit(matching_bit, matching_word))
   join(&matching)
   C.assert(C.__atomic_load_n(&wrong.returned, 2) == 0)
   C.assert(!C.vinix_linuxkpi_task_queued(&wrong.model))
   C.assert(C.vmh_queue_waiters(C.bit_waitqueue(matching_word, matching_bit)) == 1)
   C.clear_and_wake_up_bit(wrong_bit, wrong_word)
   join(&wrong)
   C.assert(matching.result == 0 && wrong.result == 0)
   C.assert(!C.waitqueue_active(C.bit_waitqueue(matching_word, matching_bit)))
  }
 }
}
fn wake_quota() {
 unsafe {
  mut words := [1024][8]usize{}
  mut first := voidptr(nil)
  mut second := voidptr(nil)
  collision_addresses(&words[0][0], sizeof(words[0]), 1024, false, &first, &second)
  word := &usize(first)
  other := &usize(second)
  bit := i32(0)
  C.set_bit(bit, word); C.set_bit(bit, other)
  mut wrong := Actor{gate_action: true}
  mut lockers := [Actor{gate_action: true}, Actor{gate_action: true}]!
  mut normal := [Actor{gate_action: true}, Actor{gate_action: true}, Actor{gate_action: true}]!
  start(&wrong, .lock, other, bit, C.TASK_UNINTERRUPTIBLE); parked(&wrong)
  for i in u32(0)..u32(2) { start(&lockers[i], .lock, word, bit, C.TASK_UNINTERRUPTIBLE); parked(&lockers[i]) }
  for i in u32(0)..u32(3) { start(&normal[i], .normal, word, bit, C.TASK_UNINTERRUPTIBLE); parked(&normal[i]) }
  flags := C.vinix_linuxkpi_irq_save()
  C.clear_and_wake_up_bit(bit, word)
  C.assert(!C.vmh_interrupts)
  C.vinix_linuxkpi_irq_restore(flags)
  for i in u32(0)..u32(3) { wait_value(&normal[i].awakened, 1) }
  wait_value(&lockers[0].awakened, 1)
  C.assert(!C.vinix_linuxkpi_task_queued(&wrong.model))
  C.assert(!C.vinix_linuxkpi_task_queued(&lockers[1].model))
  C.assert(wrong.awakened == 0 && lockers[1].awakened == 0)
  C.assert(C.vmh_queue_waiters(C.bit_waitqueue(word, bit)) == 2)
  for i in u32(0)..u32(3) {
   C.__atomic_store_n(&normal[i].action_release, u32(1), 3)
   join(&normal[i]); C.assert(normal[i].result == 0)
  }
  C.__atomic_store_n(&lockers[0].action_release, u32(1), 3)
  wait_value(&lockers[0].returned, 1)
  C.assert(lockers[0].result == 0 && C.test_bit(bit, word))
  C.__atomic_store_n(&lockers[0].release, u32(1), 3); join(&lockers[0])
  wait_value(&lockers[1].awakened, 1)
  C.__atomic_store_n(&lockers[1].action_release, u32(1), 3)
  wait_value(&lockers[1].returned, 1)
  C.assert(lockers[1].result == 0 && C.test_bit(bit, word))
  C.__atomic_store_n(&lockers[1].release, u32(1), 3); join(&lockers[1])
  C.__atomic_store_n(&wrong.action_release, u32(1), 3)
  C.__atomic_store_n(&wrong.release, u32(1), 3)
  C.clear_and_wake_up_bit(bit, other); join(&wrong)
  C.assert(wrong.result == 0 && !C.waitqueue_active(C.bit_waitqueue(word, bit)))
 }
}
@[cinit] __global (
 custom_calls u32
 custom_result i32
 custom_clear bool
)
@[export: 'vmh_wait_bit_custom_action']
pub fn custom_action(key &C.wait_bit_key, mode i32) i32 {
 unsafe {
  C.assert(C.current.__state == u32(mode))
  custom_calls++
  if custom_clear { C.clear_bit(key.bit_nr, key.flags) }
  return custom_result
 }
}
fn actions() {
 unsafe {
  mut word := usize(1) << 7
  C.DECLARE_WAIT_QUEUE_HEAD(C.vmh_custom_queue)
  C.DEFINE_WAIT_BIT(C.vmh_custom_wait, &word, 7)
  for lock_mode in u32(0)..u32(2) {
   for clear in u32(0)..u32(2) {
    for positive in u32(0)..u32(2) {
     C.set_bit(7, &word)
     custom_calls = 0
     custom_result = if positive != 0 { i32(7) } else { -C.EIO }
     custom_clear = clear != 0
     result := if lock_mode != 0 {
      C.__wait_on_bit_lock(&C.vmh_custom_queue, &C.vmh_custom_wait, C.vmh_wait_bit_custom_action, C.TASK_INTERRUPTIBLE)
     } else { C.__wait_on_bit(&C.vmh_custom_queue, &C.vmh_custom_wait, C.vmh_wait_bit_custom_action, C.TASK_INTERRUPTIBLE) }
     C.assert(result == if lock_mode != 0 && clear != 0 { i32(0) } else { custom_result })
     C.assert(custom_calls == 1 && !C.waitqueue_active(&C.vmh_custom_queue))
     C.assert(C.task_is_running(C.current))
     C.assert(C.test_bit(7, &word) == (lock_mode != 0 || clear == 0))
    }
   }
  }
  C.clear_and_wake_up_bit(7, &word)
 }
}
fn signals() {
 unsafe {
  mut word := usize(1) << 9
  for round in u32(0)..u32(32) {
   for kind in u32(0)..u32(3) {
    mut actor := Actor{timeout: 10}
    start(&actor, Operation(kind), &word, 9, C.TASK_INTERRUPTIBLE); parked(&actor)
    signal_actor(&actor, u64(1) << 14); join(&actor)
    C.assert(actor.result == -C.EINTR && C.test_bit(9, &word))
    C.assert(!C.waitqueue_active(C.bit_waitqueue(&word, 9)) && C.vinix_linuxkpi_time_waiters() == 0)
   }
  }
  for lock_mode in u32(0)..u32(2) {
   mut actor := Actor{}
   start(&actor, if lock_mode != 0 { Operation.lock } else { Operation.normal }, &word, 9, C.TASK_KILLABLE)
   parked(&actor); signal_actor(&actor, u64(1) << 14)
   for C.vinix_linuxkpi_task_queued(&actor.model) { C.sched_yield() }
   C.assert(C.__atomic_load_n(&actor.returned, 2) == 0)
   C.assert(C.__atomic_load_n(&actor.actions, 2) == 1)
   signal_actor(&actor, u64(1) << 8); join(&actor)
   C.assert(actor.result == -C.EINTR && C.test_bit(9, &word))
  }
  for lock_mode in u32(0)..u32(2) {
   mut actor := Actor{gate_action: true}
   start(&actor, if lock_mode != 0 { Operation.lock } else { Operation.normal }, &word, 9, C.TASK_INTERRUPTIBLE)
   parked(&actor); signal_actor(&actor, u64(1) << 14)
   wait_value(&actor.awakened, 1)
   C.clear_and_wake_up_bit(9, &word)
   C.__atomic_store_n(&actor.action_release, u32(1), 3)
   if lock_mode != 0 {
    wait_value(&actor.returned, 1)
    C.assert(actor.result == 0 && C.test_bit(9, &word))
    C.__atomic_store_n(&actor.release, u32(1), 3)
   }
   join(&actor)
   C.assert(actor.result == if lock_mode != 0 { isize(0) } else { isize(-C.EINTR) })
   C.assert(!C.waitqueue_active(C.bit_waitqueue(&word, 9)))
   C.set_bit(9, &word)
  }
  C.clear_and_wake_up_bit(9, &word)
  C.vmh_native_task.pending = u64(1) << 14
  C.assert(C.wait_on_bit(&word, 9, C.TASK_INTERRUPTIBLE) == 0)
  C.assert(C.wait_on_bit_lock(&word, 9, C.TASK_INTERRUPTIBLE) == 0)
  C.clear_and_wake_up_bit(9, &word)
  C.vmh_native_task.pending = 0
 }
}
fn deadlines() {
 unsafe {
  mut word := usize(1) << 12
  C.assert(C.wait_on_bit_timeout(&word, 12, C.TASK_UNINTERRUPTIBLE, 0) == -C.EAGAIN)
  C.assert(!C.waitqueue_active(C.bit_waitqueue(&word, 12)) && C.vinix_linuxkpi_time_waiters() == 0)
  mut actor := Actor{timeout: 10, track_timeout: true}
  start(&actor, .timed, &word, 12, C.TASK_UNINTERRUPTIBLE); parked(&actor)
  C.assert(C.vinix_linuxkpi_time_waiters() == 1)
  advance(3)
  C.wake_up_process(&C.task_struct(&actor.model.storage[0]))
  wait_value(&actor.actions, 2)
  for C.vinix_linuxkpi_time_waiters() == 0 || C.vinix_linuxkpi_task_queued(&actor.model) { C.sched_yield() }
  advance(3)
  C.wake_up_process(&C.task_struct(&actor.model.storage[0]))
  wait_value(&actor.actions, 3)
  for C.vinix_linuxkpi_time_waiters() == 0 || C.vinix_linuxkpi_task_queued(&actor.model) { C.sched_yield() }
  advance(4)
  join(&actor)
  C.assert(actor.result == -C.EAGAIN && C.test_bit(12, &word))
  C.assert(C.vinix_linuxkpi_time_waiters() == 0 && !C.waitqueue_active(C.bit_waitqueue(&word, 12)))
  actor = Actor{timeout: 10}
  start(&actor, .timed, &word, 12, C.TASK_UNINTERRUPTIBLE); parked(&actor)
  advance(4)
  C.clear_and_wake_up_bit(12, &word); join(&actor)
  C.assert(actor.result == 0 && C.vinix_linuxkpi_time_waiters() == 0)
  C.assert(C.vinix_linuxkpi_time_waiters() == 0)
  actual_jiffies := C.READ_ONCE(C.jiffies)
  C.WRITE_ONCE(C.jiffies, C.ULONG_MAX - 3)
  C.set_bit(12, &word)
  C.vmh_native_task.pending = u64(1) << 14
  C.assert(C.wait_on_bit_timeout(&word, 12, C.TASK_INTERRUPTIBLE, 6) == -C.EINTR)
  C.vmh_native_task.pending = 0
  C.WRITE_ONCE(C.jiffies, usize(2))
  mut key := C.wait_bit_key{flags: &word, bit_nr: 12, timeout: C.ULONG_MAX - 3}
  C.assert(C.bit_wait_timeout(&key, i32(C.TASK_UNINTERRUPTIBLE)) == -C.EAGAIN)
  C.WRITE_ONCE(C.jiffies, actual_jiffies)
  C.assert(C.task_is_running(C.current) && C.vinix_linuxkpi_time_waiters() == 0)
  C.clear_and_wake_up_bit(12, &word)
 }
}
fn variables() {
 unsafe {
  mut values := [1024]u32{}
  mut address_first := voidptr(nil)
  mut address_second := voidptr(nil)
  collision_addresses(&values[0], sizeof(values[0]), 1024, true, &address_first, &address_second)
  variable := &u32(address_first)
  other := &u32(address_second)
  mut conditions := [2]u32{}
  mut payload := u32(0)
  mut wrong := Actor{key: other, condition: &conditions[1]}
  mut matching := Actor{key: variable, condition: &conditions[0]}
  start(&wrong, .var_normal, nil, 0, C.TASK_UNINTERRUPTIBLE); parked(&wrong)
  start(&matching, .var_normal, nil, 0, C.TASK_UNINTERRUPTIBLE); parked(&matching)
  C.__atomic_store_n(&conditions[0], u32(1), 3); C.smp_mb(); C.wake_up_var(variable)
  join(&matching)
  C.assert(!C.vinix_linuxkpi_task_queued(&wrong.model))
  C.assert(C.vmh_queue_waiters(C.__var_waitqueue(variable)) == 1)
  C.__atomic_store_n(&conditions[1], u32(1), 3); C.smp_mb(); C.wake_up_var(other)
  join(&wrong)
  C.assert(!C.waitqueue_active(C.__var_waitqueue(variable)))
  for round in u32(0)..u32(32) {
   for killable in u32(0)..u32(2) {
    mut condition := u32(0)
    mut actor := Actor{key: &condition, condition: &condition}
    start(&actor, if killable != 0 { Operation.var_killable } else { Operation.var_interrupt },
     nil, 0, if killable != 0 { C.TASK_KILLABLE } else { C.TASK_INTERRUPTIBLE })
    parked(&actor)
    signal_actor(&actor, u64(1) << if killable != 0 { u32(8) } else { u32(14) })
    join(&actor)
    C.assert(actor.result == -C.ERESTARTSYS && !C.waitqueue_active(C.__var_waitqueue(&condition)))
   }
  }
  mut condition := u32(1)
  C.vmh_native_task.pending = u64(1) << 14
  C.assert(C.wait_var_event_interruptible(&condition, condition) == 0)
  C.assert(C.__wait_var_event_interruptible(&condition, condition) == 0)
  C.vmh_native_task.pending = u64(1) << 8
  C.assert(C.__wait_var_event_killable(&condition, condition) == 0)
  C.assert(!C.waitqueue_active(C.__var_waitqueue(&condition)) && C.task_is_running(C.current))
  C.assert(C.wait_var_event_timeout(&condition, condition, isize(0)) == 1)
  condition = 0
  C.assert(C.wait_var_event_timeout(&condition, condition, isize(0)) == 0)
  C.vmh_native_task.pending = 0
  mut mixed_words := [1024][8]usize{}
  mut mixed_word := &usize(nil)
  mut mixed_bit := i32(-1)
  for i := usize(0); i < 1024 && mixed_word == nil; i++ {
   for bit := i32(0); bit < 8 * C.BITS_PER_LONG; bit++ {
    if usize(C.bit_waitqueue(&mixed_words[i][0], bit)) == usize(C.__var_waitqueue(&mixed_words[i][0])) {
     mixed_word = &mixed_words[i][0]; mixed_bit = bit; break
    }
   }
  }
  C.assert(mixed_word != nil && mixed_bit >= 0)
  for var_first in u32(0)..u32(2) {
   condition = 0
   C.set_bit(mixed_bit, mixed_word)
   mut bit_actor := Actor{}
   mut var_actor := Actor{key: mixed_word, condition: &condition}
   start(&bit_actor, .normal, mixed_word, mixed_bit, C.TASK_UNINTERRUPTIBLE); parked(&bit_actor)
   start(&var_actor, .var_normal, nil, 0, C.TASK_UNINTERRUPTIBLE); parked(&var_actor)
   if var_first != 0 {
    C.__atomic_store_n(&condition, u32(1), 3); C.smp_mb(); C.wake_up_var(mixed_word)
    join(&var_actor)
    C.assert(!C.vinix_linuxkpi_task_queued(&bit_actor.model))
    C.clear_and_wake_up_bit(mixed_bit, mixed_word); join(&bit_actor)
   } else {
    C.clear_and_wake_up_bit(mixed_bit, mixed_word); join(&bit_actor)
    C.assert(!C.vinix_linuxkpi_task_queued(&var_actor.model))
    C.__atomic_store_n(&condition, u32(1), 3); C.smp_mb(); C.wake_up_var(mixed_word)
    join(&var_actor)
   }
   C.assert(!C.waitqueue_active(C.__var_waitqueue(mixed_word)))
  }
  for outcome in u32(0)..u32(3) {
   condition = 0; payload = 0
   mut actor := Actor{key: &condition, condition: &condition, timeout: 10, success_at_expiry: outcome == 2}
   if outcome != 0 { actor.payload = &payload }
   start(&actor, .var_timed, nil, 0, C.TASK_UNINTERRUPTIBLE)
   if outcome != 2 {
    parked(&actor)
    advance(if outcome != 0 { u64(4) } else { u64(10) })
    if outcome != 0 { payload = 0xabc123; C.store_release_wake_up(&condition, 1) }
   }
   join(&actor)
   C.assert(actor.result == if outcome == 0 { isize(0) } else if outcome == 1 { isize(6) } else { isize(1) })
   C.assert(C.vinix_linuxkpi_time_waiters() == 0 && !C.waitqueue_active(C.__var_waitqueue(&condition)))
  }
  for unmap in u32(0)..u32(2) {
   key := C.mmap(nil, 4096, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
   C.assert(usize(key) != usize(C.MAP_FAILED))
   condition = 0
   mut actor := Actor{key: key, condition: &condition}
   start(&actor, .var_normal, nil, 0, C.TASK_UNINTERRUPTIBLE); parked(&actor)
   if unmap != 0 { C.assert(C.munmap(key, 4096) == 0) }
   C.__atomic_store_n(&condition, u32(1), 3); C.smp_mb(); C.wake_up_var(key)
   join(&actor)
   C.assert(!C.waitqueue_active(C.__var_waitqueue(key)))
   if unmap == 0 { C.assert(C.munmap(key, 4096) == 0) }
  }
 }
}
@[export: 'vmh_wait_bit_tests']
pub fn tests() {
 unsafe {
  mut controller := C.native_task_model{}
  C.vmh_sync_model_init(&controller, 221); C.vmh_native_task = &controller
  before := C.vmh_live_pages
  C.assert(!C.vmh_fail_allocation)
  C.vmh_fail_allocation = true
  C.wait_bit_init()
  basics(); collisions(); wake_quota(); actions(); signals(); deadlines(); variables()
  C.assert(C.vmh_live_pages == before && C.vinix_linuxkpi_time_waiters() == 0)
  C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.vmh_fail_allocation = false; C.vmh_native_task = nil
  C.vmh_sync_model_destroy(&controller)
 }
}
