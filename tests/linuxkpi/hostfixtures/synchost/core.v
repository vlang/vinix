// SPDX-License-Identifier: GPL-2.0-or-later
// Independent mutex/wait/completion assertions from the original host fixture.
@[translated]
module synchost

#include "synchost_v_contract.h"
struct C.list_head { mut: next &C.list_head, prev &C.list_head }
@[typedef] struct C.spinlock_t {}
struct C.mutex { mut: wait_lock C.spinlock_t, wait_list C.list_head }
struct C.wait_queue_head { mut: lock C.spinlock_t, head C.list_head }
struct C.wait_queue_entry { mut: entry C.list_head }
struct C.swait_queue_head {}
struct C.completion { mut: done u32, @wait C.swait_queue_head }
@[typedef] struct C.refcount_t {}
fn C.DEFINE_MUTEX(C.mutex)
fn C.DECLARE_WAIT_QUEUE_HEAD(C.wait_queue_head)
fn C.ATOMIC_INIT(i32) C.atomic_t
fn C.REFCOUNT_INIT(u32) C.refcount_t
fn C.atomic_read(&C.atomic_t) i32
fn C.refcount_read(&C.refcount_t) u32
fn C.atomic_dec_and_mutex_lock(&C.atomic_t, &C.mutex) bool
fn C.refcount_dec_and_mutex_lock(&C.refcount_t, &C.mutex) bool
fn C.mutex_init(&C.mutex)
fn C.mutex_destroy(&C.mutex)
fn C.mutex_is_locked(&C.mutex) bool
fn C.mutex_trylock(&C.mutex) i32
fn C.mutex_lock(&C.mutex)
fn C.mutex_lock_nested(&C.mutex, u32)
fn C.mutex_lock_interruptible(&C.mutex) i32
fn C.mutex_lock_killable(&C.mutex) i32
fn C.mutex_unlock(&C.mutex)
fn C.raw_spin_lock_irqsave(&C.spinlock_t, usize)
fn C.raw_spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.spin_lock_irqsave(&C.spinlock_t, usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.list_empty(&C.list_head) bool
fn C.list_del_init(&C.list_head)
fn C.INIT_LIST_HEAD(&C.list_head)
fn C.init_waitqueue_func_entry(&C.wait_queue_entry, fn (&C.wait_queue_entry, u32, i32, voidptr) i32)
fn C.add_wait_queue_exclusive(&C.wait_queue_head, &C.wait_queue_entry)
fn C.add_wait_queue(&C.wait_queue_head, &C.wait_queue_entry)
fn C.add_wait_queue_priority(&C.wait_queue_head, &C.wait_queue_entry)
fn C.remove_wait_queue(&C.wait_queue_head, &C.wait_queue_entry)
fn C.__wake_up(&C.wait_queue_head, u32, i32, voidptr) i32
fn C.__wake_up_locked_key(&C.wait_queue_head, u32, voidptr)
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.swait_active(&C.swait_queue_head) bool
fn C.init_waitqueue_head(&C.wait_queue_head)
fn C.init_swait_queue_head(&C.swait_queue_head)
fn C.init_completion(&C.completion)
fn C.reinit_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.try_wait_for_completion(&C.completion) bool
fn C.completion_done(&C.completion) bool
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_state(&C.completion, u32) i32
fn C.wait_for_completion_interruptible(&C.completion) i32
fn C.swait_event_interruptible_exclusive(C.swait_queue_head, ...) i32
fn C.swait_event_exclusive(C.swait_queue_head, ...)
fn C.wait_event_interruptible_exclusive(C.wait_queue_head, ...) i32
fn C.wait_event_killable(C.wait_queue_head, ...) i32
fn C.wait_event_interruptible(C.wait_queue_head, ...) i32
fn C.wait_event(C.wait_queue_head, ...)
fn C.wake_up_all(&C.wait_queue_head)
fn C.swake_up_all(&C.swait_queue_head)
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_sync_selftest() i32
fn C.vmh_sync_mutex_worker(voidptr) voidptr
fn C.vmh_sync_event_worker(voidptr) voidptr
fn C.vmh_sync_record_wake(&C.wait_queue_entry, u32, i32, voidptr) i32
@[c_extern] __global (
 C.TASK_NORMAL u32
 C.TASK_INTERRUPTIBLE u32
 C.TASK_UNINTERRUPTIBLE u32
 C.TASK_KILLABLE u32
 C.EINTR i32
 C.ERESTARTSYS i32
 C.UINT_MAX u32
)

// This list count is also consumed by the independently compiled WW fixture.
fn list_count(head &C.list_head) u32 {
 unsafe {
  mut count := u32(0)
  mut entry := head.next
  for usize(entry) != usize(head) { count++; entry = entry.next }
  return count
 }
}
@[export: 'vmh_mutex_waiters']
pub fn mutex_waiters(mutexp &C.mutex) u32 {
 mut flags := usize(0)
 unsafe {
  C.raw_spin_lock_irqsave(&mutexp.wait_lock, flags)
  count := list_count(&mutexp.wait_list)
  C.raw_spin_unlock_irqrestore(&mutexp.wait_lock, flags)
  return count
 }
}
@[export: 'vmh_queue_waiters']
pub fn queue_waiters(head &C.wait_queue_head) u32 {
 mut flags := usize(0)
 unsafe {
  C.spin_lock_irqsave(&head.lock, flags)
  count := list_count(&head.head)
  C.spin_unlock_irqrestore(&head.lock, flags)
  return count
 }
}
struct MutexFixture {
 mut:
 lock C.mutex
 counter u32
 acquired u32
 order [4]u32
 release [4]u32
 fifo bool
}
struct MutexWorker {
 mut:
 model C.native_task_model
 fixture &MutexFixture
 index u32
 killable bool
 result i32
}
@[export: 'vmh_sync_mutex_worker']
pub fn mutex_worker(argument voidptr) voidptr {
 unsafe {
  test := &MutexWorker(argument)
  fixture := test.fixture
  C.vmh_native_task = &test.model
  C.vmh_current_cpu = test.index
  if fixture.fifo {
   test.result = if test.killable { C.mutex_lock_killable(&fixture.lock) } else { C.mutex_lock_interruptible(&fixture.lock) }
   if test.result == 0 {
    slot := u32(C.__atomic_load_n(&fixture.acquired, 0))
    fixture.order[slot] = test.index
    C.__atomic_store_n(&fixture.acquired, slot + 1, i32(3))
    for C.__atomic_load_n(&fixture.release[test.index], 2) == 0 { C.sched_yield() }
    C.mutex_unlock(&fixture.lock)
   }
  } else {
   for i := u32(0); i < 1000; i++ {
    C.mutex_lock(&fixture.lock)
    previous := fixture.counter
    C.sched_yield()
    fixture.counter = previous + 1
    C.mutex_unlock(&fixture.lock)
   }
  }
  C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.vmh_native_task = nil
  return nil
 }
}
fn mutex_tests() {
 unsafe {
  C.DEFINE_MUTEX(C.fixture_static_lock)
  C.assert(!C.mutex_is_locked(&C.fixture_static_lock) && C.mutex_trylock(&C.fixture_static_lock) == 1)
  C.assert(C.mutex_is_locked(&C.fixture_static_lock) && C.mutex_trylock(&C.fixture_static_lock) == 0)
  C.mutex_unlock(&C.fixture_static_lock)
  C.mutex_lock_nested(&C.fixture_static_lock, 1)
  C.mutex_unlock(&C.fixture_static_lock)
  mut count := C.ATOMIC_INIT(2)
  C.assert(!C.atomic_dec_and_mutex_lock(&count, &C.fixture_static_lock) && C.atomic_read(&count) == 1)
  C.assert(C.atomic_dec_and_mutex_lock(&count, &C.fixture_static_lock) && C.atomic_read(&count) == 0)
  C.mutex_unlock(&C.fixture_static_lock)
  mut refs := C.REFCOUNT_INIT(2)
  C.assert(!C.refcount_dec_and_mutex_lock(&refs, &C.fixture_static_lock) && C.refcount_read(&refs) == 1)
  C.assert(C.refcount_dec_and_mutex_lock(&refs, &C.fixture_static_lock) && C.refcount_read(&refs) == 0)
  C.mutex_unlock(&C.fixture_static_lock)
  C.vmh_native_task.pending = u64(1) << 14
  C.assert(C.mutex_lock_interruptible(&C.fixture_static_lock) == 0)
  C.mutex_unlock(&C.fixture_static_lock)
  C.vmh_native_task.pending = 0
  C.mutex_destroy(&C.fixture_static_lock)
  mut fixture := MutexFixture{}
  C.mutex_init(&fixture.lock)
  mut workers := [4]MutexWorker{}
  mut threads := [4]C.pthread_t{}
  for i := u32(0); i < 4; i++ {
   workers[i] = MutexWorker{fixture: &fixture, index: i}
   C.vmh_sync_model_init(&workers[i].model, i)
   C.assert(C.pthread_create(&threads[i], nil, C.vmh_sync_mutex_worker, voidptr(&workers[i])) == 0)
  }
  for i := u32(0); i < 4; i++ {
   C.assert(C.pthread_join(threads[i], nil) == 0)
   C.vmh_sync_model_destroy(&workers[i].model)
  }
  C.assert(fixture.counter == 4000 && mutex_waiters(&fixture.lock) == 0)
  C.mutex_destroy(&fixture.lock)
  fixture = MutexFixture{fifo: true}
  C.mutex_init(&fixture.lock)
  C.mutex_lock(&fixture.lock)
  for i := u32(0); i < 4; i++ {
   workers[i] = MutexWorker{fixture: &fixture, index: i, killable: i == 3}
   C.vmh_sync_model_init(&workers[i].model, i)
   C.assert(C.pthread_create(&threads[i], nil, C.vmh_sync_mutex_worker, voidptr(&workers[i])) == 0)
   for mutex_waiters(&fixture.lock) != i + 1 { C.sched_yield() }
  }
  C.__atomic_store_n(&C.vmh_u64(&workers[1].model.pending), u64(1) << 14, i32(3))
  C.assert(C.vinix_linuxkpi_task_enqueue(&workers[1].model))
  C.assert(C.pthread_join(threads[1], nil) == 0 && workers[1].result == -C.EINTR)
  C.__atomic_store_n(&C.vmh_u64(&workers[3].model.pending), u64(1) << 14, i32(3))
  C.assert(C.vinix_linuxkpi_task_enqueue(&workers[3].model))
  for C.vinix_linuxkpi_task_queued(&workers[3].model) { C.sched_yield() }
  C.assert(mutex_waiters(&fixture.lock) == 3)
  C.__atomic_store_n(&C.vmh_u64(&workers[3].model.pending), u64(1) << 8, i32(3))
  C.assert(C.vinix_linuxkpi_task_enqueue(&workers[3].model))
  C.assert(C.pthread_join(threads[3], nil) == 0 && workers[3].result == -C.EINTR)
  C.assert(mutex_waiters(&fixture.lock) == 2)
  C.mutex_unlock(&fixture.lock)
  for slot := u32(0); slot < 2; slot++ {
   for C.__atomic_load_n(&fixture.acquired, 2) <= slot { C.sched_yield() }
   C.assert(fixture.order[slot] == slot * 2 && C.mutex_trylock(&fixture.lock) == 0)
   C.__atomic_store_n(&fixture.release[slot * 2], u32(1), i32(3))
   C.assert(C.pthread_join(threads[slot * 2], nil) == 0 && workers[slot * 2].result == 0)
  }
  C.assert(!C.mutex_is_locked(&fixture.lock) && mutex_waiters(&fixture.lock) == 0)
  for i := u32(0); i < 4; i++ { C.vmh_sync_model_destroy(&workers[i].model) }
  C.mutex_destroy(&fixture.lock)
  fixture = MutexFixture{fifo: true, release: [u32(1), u32(0), u32(0), u32(0)]!}
  C.mutex_init(&fixture.lock)
  C.mutex_lock(&fixture.lock)
  workers[0] = MutexWorker{fixture: &fixture}
  C.vmh_sync_model_init(&workers[0].model, 0)
  workers[0].model.iteration = 1
  C.assert(C.pthread_create(&threads[0], nil, C.vmh_sync_mutex_worker, voidptr(&workers[0])) == 0)
  for C.__atomic_load_n(&workers[0].model.parked, 2) != 1 { C.sched_yield() }
  C.__atomic_store_n(&C.vmh_u64(&workers[0].model.pending), u64(1) << 14, i32(3))
  C.mutex_unlock(&fixture.lock)
  C.assert(C.pthread_join(threads[0], nil) == 0 && workers[0].result == 0 && fixture.acquired == 1)
  C.vmh_sync_model_destroy(&workers[0].model)
  C.mutex_destroy(&fixture.lock)
 }
}
@[c_extern] __global C.fixture_static_lock C.mutex
@[c_extern] __global C.fixture_wait_head C.wait_queue_head
struct CallbackTest {
 mut:
 wait C.wait_queue_entry
 id u32
 order &u32
 count &u32
 key voidptr
 result i32
 remove bool
}
@[export: 'vmh_sync_record_wake']
pub fn record_wake(wait &C.wait_queue_entry, mode u32, flags i32, key voidptr) i32 {
 unsafe {
  test := &CallbackTest(wait)
  C.assert(mode == C.TASK_NORMAL && flags == 0 && usize(key) == usize(test.key))
  C.assert(!C.vmh_interrupts && C.vmh_preempt_depth == 1)
  slot := *test.count
  (*test.count)++
  test.order[slot] = test.id
  if test.remove { C.list_del_init(&wait.entry) }
  return test.result
 }
}
fn wait_callback_tests() {
 unsafe {
  C.DECLARE_WAIT_QUEUE_HEAD(C.fixture_wait_head)
  mut order := [8]u32{}
  mut count := u32(0)
  mut key := i32(0)
  mut tests := [5]CallbackTest{}
  for i := u32(0); i < 5; i++ {
   tests[i] = CallbackTest{id: i, order: &order[0], count: &count, key: &key, result: 1}
   C.init_waitqueue_func_entry(&tests[i].wait, C.vmh_sync_record_wake)
   C.INIT_LIST_HEAD(&tests[i].wait.entry)
  }
  C.add_wait_queue_exclusive(&C.fixture_wait_head, &tests[2].wait)
  C.add_wait_queue_exclusive(&C.fixture_wait_head, &tests[3].wait)
  C.add_wait_queue(&C.fixture_wait_head, &tests[0].wait)
  C.add_wait_queue(&C.fixture_wait_head, &tests[1].wait)
  C.add_wait_queue_priority(&C.fixture_wait_head, &tests[4].wait)
  C.assert(C.__wake_up(&C.fixture_wait_head, C.TASK_NORMAL, 1, &key) == 1 && count == 1 && order[0] == 4)
  C.remove_wait_queue(&C.fixture_wait_head, &tests[4].wait)
  count = 0
  tests[1].remove = true
  tests[2].result = 0
  C.assert(C.__wake_up(&C.fixture_wait_head, C.TASK_NORMAL, 1, &key) == 1 && count == 4)
  C.assert(order[0] == 1 && order[1] == 0 && order[2] == 2 && order[3] == 3)
  C.assert(C.list_empty(&tests[1].wait.entry))
  count = 0
  tests[0].result = -1
  mut flags := usize(0)
  C.spin_lock_irqsave(&C.fixture_wait_head.lock, flags)
  C.__wake_up_locked_key(&C.fixture_wait_head, C.TASK_NORMAL, &key)
  C.spin_unlock_irqrestore(&C.fixture_wait_head.lock, flags)
  C.assert(count == 1 && order[0] == 0)
  tests[0].result = 1; tests[2].result = 1
  count = 0
  C.assert(C.__wake_up(&C.fixture_wait_head, C.TASK_NORMAL, 0, &key) == 2 && count == 3)
  for i := u32(0); i < 5; i++ { C.remove_wait_queue(&C.fixture_wait_head, &tests[i].wait) }
  C.assert(!C.waitqueue_active(&C.fixture_wait_head))
 }
}
struct EventFixture {
 mut:
 queue C.wait_queue_head
 simple C.swait_queue_head
 completion C.completion
 condition u32
 payload u32
}
struct EventWorker {
 mut:
 model C.native_task_model
 fixture &EventFixture
 kind u32
 index u32
 state u32
 result i32
}
@[export: 'vmh_sync_event_worker']
pub fn event_worker(argument voidptr) voidptr {
 unsafe {
  test := &EventWorker(argument)
  fixture := test.fixture
  C.vmh_native_task = &test.model
  C.vmh_current_cpu = test.index
  if test.kind == 2 { test.result = C.wait_for_completion_state(&fixture.completion, test.state) }
  else if test.kind == 1 {
   if test.state == C.TASK_INTERRUPTIBLE { test.result = C.swait_event_interruptible_exclusive(fixture.simple, C.__atomic_load_n(&fixture.condition, 2)) }
   else { C.swait_event_exclusive(fixture.simple, C.__atomic_load_n(&fixture.condition, 2)) }
  } else if test.state == C.TASK_INTERRUPTIBLE {
   test.result = C.wait_event_interruptible_exclusive(fixture.queue, C.__atomic_load_n(&fixture.condition, 2))
  } else if test.state == C.TASK_KILLABLE {
   test.result = C.wait_event_killable(fixture.queue, C.__atomic_load_n(&fixture.condition, 2))
  } else { C.wait_event(fixture.queue, C.__atomic_load_n(&fixture.condition, 2)) }
  if test.result == 0 { C.assert(fixture.payload == 0x1234) }
  C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.vmh_native_task = nil
  return nil
 }
}
fn event_init(fixture &EventFixture) {
 unsafe {
  *fixture = EventFixture{}
  C.init_waitqueue_head(&fixture.queue)
  C.init_swait_queue_head(&fixture.simple)
  C.init_completion(&fixture.completion)
 }
}
fn event_empty(fixture &EventFixture) {
 unsafe {
  C.assert(!C.waitqueue_active(&fixture.queue) && !C.swait_active(&fixture.simple))
  C.assert(!C.swait_active(&fixture.completion.@wait))
 }
}
fn condition_after_signal(checks &u32) bool {
 unsafe {
  (*checks)++
  if *checks == 2 { C.vmh_native_task.pending = u64(1) << 14 }
  return *checks >= 3
 }
}
fn event_tests() {
 unsafe {
  mut fixture := EventFixture{}
  event_init(&fixture)
  mut workers := [4]EventWorker{}
  mut threads := [4]C.pthread_t{}
  for kind in u32(0) .. u32(3) {
   for early := u32(0); early < 2; early++ {
    event_init(&fixture)
    if early != 0 {
     fixture.payload = 0x1234; fixture.condition = 1
     if kind == 2 { for i in u32(0) .. u32(4) { C.complete(&fixture.completion) } }
    }
    for i := u32(0); i < 4; i++ {
     workers[i] = EventWorker{fixture: &fixture, kind: kind, index: i, state: if i & 1 != 0 { C.TASK_INTERRUPTIBLE } else { C.TASK_UNINTERRUPTIBLE }}
     C.vmh_sync_model_init(&workers[i].model, i)
     C.assert(C.pthread_create(&threads[i], nil, C.vmh_sync_event_worker, voidptr(&workers[i])) == 0)
    }
    if early == 0 {
     for i := u32(0); i < 4; i++ { for C.vinix_linuxkpi_task_queued(&workers[i].model) { C.sched_yield() } }
     if kind == 0 { C.assert(queue_waiters(&fixture.queue) == 4) }
     fixture.payload = 0x1234
     C.__atomic_store_n(&fixture.condition, u32(1), i32(3))
     if kind == 0 { C.wake_up_all(&fixture.queue) }
     if kind == 1 { C.swake_up_all(&fixture.simple) }
     if kind == 2 { C.complete_all(&fixture.completion) }
    }
    for i := u32(0); i < 4; i++ {
     C.assert(C.pthread_join(threads[i], nil) == 0 && workers[i].result == 0)
     C.vmh_sync_model_destroy(&workers[i].model)
    }
    event_empty(&fixture)
   }
   event_init(&fixture)
   workers[0] = EventWorker{fixture: &fixture, kind: kind, state: C.TASK_INTERRUPTIBLE}
   C.vmh_sync_model_init(&workers[0].model, 0)
   C.assert(C.pthread_create(&threads[0], nil, C.vmh_sync_event_worker, voidptr(&workers[0])) == 0)
   for C.vinix_linuxkpi_task_queued(&workers[0].model) { C.sched_yield() }
   C.__atomic_store_n(&C.vmh_u64(&workers[0].model.pending), u64(1) << 14, i32(3))
   C.assert(C.vinix_linuxkpi_task_enqueue(&workers[0].model))
   C.assert(C.pthread_join(threads[0], nil) == 0 && workers[0].result == -C.ERESTARTSYS)
   C.vmh_sync_model_destroy(&workers[0].model)
   event_empty(&fixture)
   C.wake_up_all(&fixture.queue); C.swake_up_all(&fixture.simple); C.complete_all(&fixture.completion)
  }
  for sequence in u32(0) .. u32(2) {
   kind := sequence * 2
   event_init(&fixture)
   workers[0] = EventWorker{fixture: &fixture, kind: kind, state: C.TASK_KILLABLE}
   C.vmh_sync_model_init(&workers[0].model, 0)
   C.assert(C.pthread_create(&threads[0], nil, C.vmh_sync_event_worker, voidptr(&workers[0])) == 0)
   for C.vinix_linuxkpi_task_queued(&workers[0].model) { C.sched_yield() }
   C.__atomic_store_n(&C.vmh_u64(&workers[0].model.pending), u64(1) << 14, i32(3))
   C.assert(C.vinix_linuxkpi_task_enqueue(&workers[0].model))
   for C.vinix_linuxkpi_task_queued(&workers[0].model) { C.sched_yield() }
   C.__atomic_store_n(&C.vmh_u64(&workers[0].model.pending), u64(1) << 8, i32(3))
   C.assert(C.vinix_linuxkpi_task_enqueue(&workers[0].model))
   C.assert(C.pthread_join(threads[0], nil) == 0 && workers[0].result == -C.ERESTARTSYS)
   C.vmh_sync_model_destroy(&workers[0].model)
   event_empty(&fixture)
  }
  event_init(&fixture)
  mut checks := u32(0)
  C.assert(C.wait_event_interruptible(fixture.queue, condition_after_signal(&checks)) == 0 && checks == 3)
  C.assert(C.task_is_running(C.current) && !C.waitqueue_active(&fixture.queue))
  C.vmh_native_task.pending = 0
  checks = 0
  C.assert(C.swait_event_interruptible_exclusive(fixture.simple, condition_after_signal(&checks)) == 0 && checks == 3)
  C.assert(C.task_is_running(C.current) && !C.swait_active(&fixture.simple))
  C.vmh_native_task.pending = u64(1) << 14
  C.assert(C.wait_event_interruptible(fixture.queue, false) == -C.ERESTARTSYS)
  C.assert(C.swait_event_interruptible_exclusive(fixture.simple, false) == -C.ERESTARTSYS)
  C.assert(C.wait_for_completion_interruptible(&fixture.completion) == -C.ERESTARTSYS)
  C.assert(C.task_is_running(C.current))
  C.assert(C.wait_event_interruptible(fixture.queue, true) == 0)
  C.complete(&fixture.completion)
  C.assert(C.wait_for_completion_interruptible(&fixture.completion) == 0)
  C.vmh_native_task.pending = 0
  event_empty(&fixture)
  C.assert(!C.try_wait_for_completion(&fixture.completion) && !C.completion_done(&fixture.completion))
  C.complete(&fixture.completion); C.complete(&fixture.completion)
  C.assert(C.completion_done(&fixture.completion))
  C.wait_for_completion(&fixture.completion)
  C.assert(C.try_wait_for_completion(&fixture.completion) && !C.try_wait_for_completion(&fixture.completion))
  fixture.completion.done = C.UINT_MAX - 1
  flags := C.vinix_linuxkpi_irq_save()
  C.complete(&fixture.completion); C.complete(&fixture.completion)
  C.assert(C.completion_done(&fixture.completion) && C.try_wait_for_completion(&fixture.completion))
  C.assert(fixture.completion.done == C.UINT_MAX)
  C.vinix_linuxkpi_irq_restore(flags)
  C.reinit_completion(&fixture.completion)
  C.assert(!C.completion_done(&fixture.completion))
  C.complete_all(&fixture.completion)
  for i := u32(0); i < 10; i++ { C.wait_for_completion(&fixture.completion) }
  C.assert(fixture.completion.done == C.UINT_MAX)
  C.reinit_completion(&fixture.completion)
  event_empty(&fixture)
 }
}
@[export: 'vmh_sync_tests']
pub fn sync_tests() {
 unsafe {
  mut controller := C.native_task_model{}
  C.vmh_sync_model_init(&controller, 20)
  C.vmh_native_task = &controller
  for i := u32(0); i < 200; i++ { C.assert(C.vinix_linuxkpi_sync_selftest() == 0) }
  mutex_tests(); wait_callback_tests(); event_tests()
  C.assert(C.vmh_interrupts && C.vmh_preempt_depth == 0 && C.vmh_live_pages == C.vmh_permanent_pages)
  C.vmh_native_task = nil
  C.vmh_sync_model_destroy(&controller)
 }
}
