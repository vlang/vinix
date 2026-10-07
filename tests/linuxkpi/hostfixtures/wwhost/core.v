// SPDX-License-Identifier: GPL-2.0-or-later
// Independent wound/wait and Wait-Die assertions from the original host fixture.
@[translated]
module wwhost

#include "wwhost_v_contract.h"

@[typedef] struct C.atomic_long_t {}
struct C.mutex {}
struct C.ww_class { mut: stamp C.atomic_long_t, is_wait_die u32 }
struct C.ww_acquire_ctx {
 mut:
 task &C.task_struct
 stamp usize
 acquired u32
 wounded u16
 is_wait_die u16
}
struct C.ww_mutex { mut: base C.mutex, ctx &C.ww_acquire_ctx }
fn C.DEFINE_WD_CLASS(C.ww_class)
fn C.DEFINE_WW_CLASS(C.ww_class)
fn C.atomic_long_set(&C.atomic_long_t, isize)
fn C.ww_mutex_init(&C.ww_mutex, &C.ww_class)
fn C.ww_mutex_destroy(&C.ww_mutex)
fn C.ww_mutex_is_locked(&C.ww_mutex) bool
fn C.ww_acquire_init(&C.ww_acquire_ctx, &C.ww_class)
fn C.ww_acquire_done(&C.ww_acquire_ctx)
fn C.ww_acquire_fini(&C.ww_acquire_ctx)
fn C.ww_mutex_lock(&C.ww_mutex, &C.ww_acquire_ctx) i32
fn C.ww_mutex_lock_interruptible(&C.ww_mutex, &C.ww_acquire_ctx) i32
fn C.ww_mutex_lock_slow(&C.ww_mutex, &C.ww_acquire_ctx)
fn C.ww_mutex_lock_slow_interruptible(&C.ww_mutex, &C.ww_acquire_ctx) i32
fn C.ww_mutex_unlock(&C.ww_mutex)
fn C.ww_mutex_trylock(&C.ww_mutex, &C.ww_acquire_ctx) i32
fn C.vmh_mutex_waiters(&C.mutex) u32
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vmh_ww_actor_thread(voidptr) voidptr
@[c_extern] __global (
 C.vmh_wd_class C.ww_class
 C.vmh_ww_class C.ww_class
 C.vmh_wait_die_class C.ww_class
 C.vmh_wound_wait_class C.ww_class
 C.EDEADLK i32
 C.EINTR i32
 C.EALREADY i32
 C.ULONG_MAX usize
)

fn wait_value(value &u32, target u32) {
 for spin := u32(0); spin < 1000000; spin++ {
  if C.__atomic_load_n(value, 2) >= target { return }
  C.sched_yield()
 }
 C.assert(unsafe { usize(c'WW operation did not make progress') } == 0)
}
fn wait_queue(mutexp &C.ww_mutex, target u32) {
 unsafe {
  for spin := u32(0); spin < 1000000; spin++ {
   if C.vmh_mutex_waiters(&mutexp.base) == target { return }
   C.sched_yield()
  }
 }
 C.assert(unsafe { usize(c'WW waiter did not attach or detach') } == 0)
}
struct Actor {
 mut:
 model C.native_task_model
 ctx C.ww_acquire_ctx
 klass &C.ww_class
 first &C.ww_mutex
 target &C.ww_mutex
 thread C.pthread_t
 ready u32
 go u32
 returned u32
 dropped u32
 retry u32
 locked u32
 release u32
 done u32
 order &u32
 count &u32
 index u32
 result i32
 no_context bool
 interruptible bool
 recover bool
 slow bool
}
@[export: 'vmh_ww_actor_thread']
pub fn actor_thread(argument voidptr) voidptr {
 unsafe {
  actor := &Actor(argument)
  C.vmh_native_task = &actor.model
  C.vmh_current_cpu = actor.index % 4
  mut ctx := &C.ww_acquire_ctx(nil)
  if !actor.no_context { ctx = &actor.ctx }
  if ctx != nil { C.ww_acquire_init(ctx, actor.klass) }
  stamp := if ctx != nil { ctx.stamp } else { usize(0) }
  if actor.first != nil { C.assert(C.ww_mutex_lock(actor.first, ctx) == 0) }
  C.__atomic_store_n(&actor.ready, u32(1), 3)
  wait_value(&actor.go, 1)
  if actor.target != nil {
   if actor.slow {
    if actor.interruptible { actor.result = C.ww_mutex_lock_slow_interruptible(actor.target, ctx) }
    else { C.ww_mutex_lock_slow(actor.target, ctx); actor.result = 0 }
   } else {
    actor.result = if actor.interruptible { C.ww_mutex_lock_interruptible(actor.target, ctx) }
     else { C.ww_mutex_lock(actor.target, ctx) }
   }
  }
  C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.__atomic_store_n(&actor.returned, u32(1), 3)
  if actor.result != 0 {
   C.assert(actor.result == -C.EDEADLK || actor.result == -C.EINTR)
   if actor.first != nil { C.ww_mutex_unlock(actor.first) }
   C.assert(ctx == nil || ctx.acquired == 0)
   C.__atomic_store_n(&actor.dropped, u32(1), 3)
   if actor.recover {
    C.assert(ctx != nil && actor.result == -C.EDEADLK)
    wait_value(&actor.retry, 1)
    C.ww_mutex_lock_slow(actor.target, ctx)
    C.assert(ctx.stamp == stamp && ctx.acquired == 1)
    if actor.first != nil { C.assert(C.ww_mutex_lock(actor.first, ctx) == 0) }
   }
  }
  if actor.result == 0 || actor.recover {
   if ctx != nil {
    C.assert(ctx.stamp == stamp)
    C.assert(ctx.acquired == u32(actor.first != nil) + u32(actor.target != nil))
    if actor.target != nil { C.assert(usize(actor.target.ctx) == usize(ctx)) }
    C.ww_acquire_done(ctx)
   }
   if actor.count != nil {
    slot := u32(C.__atomic_fetch_add(actor.count, u32(1), 4))
    actor.order[slot] = actor.index
   }
   C.__atomic_store_n(&actor.locked, u32(1), 3)
   wait_value(&actor.release, 1)
   if actor.target != nil { C.ww_mutex_unlock(actor.target) }
   if actor.first != nil { C.ww_mutex_unlock(actor.first) }
  }
  if ctx != nil { C.assert(ctx.acquired == 0); C.ww_acquire_fini(ctx) }
  C.assert(C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.__atomic_store_n(&actor.done, u32(1), 3)
  C.vmh_native_task = nil
  return nil
 }
}
fn actor_start(actor &Actor, klass &C.ww_class, first &C.ww_mutex, target &C.ww_mutex,
 index u32, no_context bool, interruptible bool) {
 unsafe {
  *actor = Actor{klass: klass, first: first, target: target, index: index,
   no_context: no_context, interruptible: interruptible}
  C.vmh_sync_model_init(&actor.model, 210 + index)
  actor.model.iteration = 1
  C.assert(C.pthread_create(&actor.thread, nil, C.vmh_ww_actor_thread, actor) == 0)
  wait_value(&actor.ready, 1)
 }
}
fn actor_go(actor &Actor) { unsafe { C.__atomic_store_n(&actor.go, u32(1), 3) } }
fn actor_release(actor &Actor) { unsafe { C.__atomic_store_n(&actor.release, u32(1), 3) } }
fn actor_join(actor &Actor) {
 unsafe {
  wait_value(&actor.done, 1)
  C.assert(C.pthread_join(actor.thread, nil) == 0)
  C.vmh_sync_model_destroy(&actor.model)
 }
}
fn basic(klass &C.ww_class) {
 unsafe {
  mut a := C.ww_mutex{}
  mut b := C.ww_mutex{}
  mut ctx := C.ww_acquire_ctx{}
  C.ww_mutex_init(&a, klass); C.ww_mutex_init(&b, klass)
  C.ww_acquire_init(&ctx, klass)
  C.assert(usize(ctx.task) == usize(C.current) && ctx.acquired == 0 && ctx.wounded == 0)
  C.assert(u32(ctx.is_wait_die) == klass.is_wait_die && !C.ww_mutex_is_locked(&a))
  ctx.wounded = 1
  C.vmh_native_task.pending = u64(1) << 14
  C.assert(C.ww_mutex_lock_interruptible(&a, &ctx) == 0)
  C.vmh_native_task.pending = 0
  C.assert(ctx.wounded == 0 && ctx.acquired == 1 && usize(a.ctx) == usize(&ctx))
  C.assert(C.ww_mutex_lock(&a, &ctx) == -C.EALREADY)
  C.assert(C.ww_mutex_lock_interruptible(&a, &ctx) == -C.EALREADY)
  C.assert(C.ww_mutex_trylock(&a, &ctx) == 0 && ctx.acquired == 1)
  flags := C.vinix_linuxkpi_irq_save()
  C.assert(C.ww_mutex_trylock(&b, &ctx) != 0)
  C.vinix_linuxkpi_irq_restore(flags)
  C.assert(ctx.acquired == 2 && usize(b.ctx) == usize(&ctx))
  C.ww_acquire_done(&ctx)
  C.ww_mutex_unlock(&a); C.assert(ctx.acquired == 1 && a.ctx == nil)
  C.ww_mutex_unlock(&b); C.assert(ctx.acquired == 0)
  C.ww_acquire_fini(&ctx)
  C.assert(C.ww_mutex_trylock(&a, nil) != 0)
  C.assert(a.ctx == nil && C.ww_mutex_is_locked(&a))
  C.ww_mutex_unlock(&a)
  C.assert(C.ww_mutex_lock_interruptible(&b, nil) == 0)
  C.ww_mutex_unlock(&b)
  C.ww_mutex_destroy(&a); C.ww_mutex_destroy(&b)
 }
}
fn wait_die_inversion(wrap bool) {
 unsafe {
  C.DEFINE_WD_CLASS(C.vmh_wd_class)
  if wrap { C.atomic_long_set(&C.vmh_wd_class.stamp, -2) }
  mut a := C.ww_mutex{}
  mut b := C.ww_mutex{}
  C.ww_mutex_init(&a, &C.vmh_wd_class); C.ww_mutex_init(&b, &C.vmh_wd_class)
  mut old := C.ww_acquire_ctx{}
  C.ww_acquire_init(&old, &C.vmh_wd_class)
  C.assert(C.ww_mutex_lock(&a, &old) == 0)
  mut young := Actor{}
  actor_start(&young, &C.vmh_wd_class, &b, &a, 0, false, false)
  young.recover = true
  stamp := young.ctx.stamp
  if wrap { C.assert(old.stamp == C.ULONG_MAX && stamp == 0) }
  actor_go(&young)
  wait_value(&young.dropped, 1)
  C.assert(young.result == -C.EDEADLK && young.ctx.acquired == 0 && C.vmh_mutex_waiters(&a.base) == 0)
  C.assert(C.ww_mutex_lock(&b, &old) == 0)
  C.ww_mutex_unlock(&b)
  C.__atomic_store_n(&young.retry, u32(1), 3)
  wait_queue(&a, 1)
  wait_value(&young.model.parked, 1)
  C.assert(young.ctx.stamp == stamp && young.ctx.acquired == 0)
  C.ww_mutex_unlock(&a)
  wait_value(&young.locked, 1)
  C.assert(young.ctx.stamp == stamp && young.ctx.acquired == 2)
  actor_release(&young); actor_join(&young)
  C.ww_acquire_fini(&old)
  C.ww_mutex_destroy(&a); C.ww_mutex_destroy(&b)
 }
}
fn wait_die_three_cycle() {
 unsafe {
  C.DEFINE_WD_CLASS(C.vmh_wd_class)
  mut locks := [3]C.ww_mutex{}
  mut actors := [3]Actor{}
  for i in u32(0)..u32(3) { C.ww_mutex_init(&locks[i], &C.vmh_wd_class) }
  for i in u32(0)..u32(3) {
   actor_start(&actors[i], &C.vmh_wd_class, &locks[i], &locks[(i + 1) % 3], i, false, false)
  }
  actors[2].recover = true
  actor_go(&actors[0]); wait_queue(&locks[1], 1)
  wait_value(&actors[0].model.parked, 1)
  actor_go(&actors[1]); wait_queue(&locks[2], 1)
  wait_value(&actors[1].model.parked, 1)
  actor_go(&actors[2]); wait_value(&actors[2].dropped, 1)
  C.assert(actors[2].result == -C.EDEADLK)
  wait_value(&actors[1].locked, 1)
  actor_release(&actors[1]); actor_join(&actors[1])
  wait_value(&actors[0].locked, 1)
  actor_release(&actors[0]); actor_join(&actors[0])
  C.__atomic_store_n(&actors[2].retry, u32(1), 3)
  wait_value(&actors[2].locked, 1)
  actor_release(&actors[2]); actor_join(&actors[2])
  for i in u32(0)..u32(3) { C.ww_mutex_destroy(&locks[i]) }
 }
}
fn wait_die_queued_older() {
 unsafe {
  C.DEFINE_WD_CLASS(C.vmh_wd_class)
  mut target := C.ww_mutex{}
  mut private := [3]C.ww_mutex{}
  C.ww_mutex_init(&target, &C.vmh_wd_class)
  for i in u32(0)..u32(3) { C.ww_mutex_init(&private[i], &C.vmh_wd_class) }
  C.assert(C.ww_mutex_lock(&target, nil) == 0)
  mut older := Actor{}
  mut younger := Actor{}
  actor_start(&older, &C.vmh_wd_class, &private[0], &target, 0, false, false)
  actor_start(&younger, &C.vmh_wd_class, &private[1], &target, 1, false, false)
  actor_go(&younger); wait_value(&younger.model.parked, 1)
  actor_go(&older); wait_value(&younger.dropped, 1)
  C.assert(younger.result == -C.EDEADLK && younger.ctx.acquired == 0)
  actor_join(&younger); wait_queue(&target, 1)
  mut arriving := Actor{}
  actor_start(&arriving, &C.vmh_wd_class, &private[2], &target, 2, false, false)
  actor_go(&arriving); wait_value(&arriving.dropped, 1)
  C.assert(arriving.result == -C.EDEADLK && arriving.model.parked == 0)
  actor_join(&arriving); wait_queue(&target, 1)
  C.ww_mutex_unlock(&target)
  wait_value(&older.locked, 1)
  actor_release(&older); actor_join(&older)
  C.ww_mutex_destroy(&target)
  for i in u32(0)..u32(3) { C.ww_mutex_destroy(&private[i]) }
 }
}
fn wound_blocked_elsewhere() {
 unsafe {
  C.DEFINE_WW_CLASS(C.vmh_ww_class)
  mut a := C.ww_mutex{}
  mut b := C.ww_mutex{}
  mut old := C.ww_acquire_ctx{}
  C.ww_mutex_init(&a, &C.vmh_ww_class); C.ww_mutex_init(&b, &C.vmh_ww_class)
  C.ww_acquire_init(&old, &C.vmh_ww_class)
  C.assert(C.ww_mutex_lock(&a, &old) == 0)
  mut young := Actor{}
  actor_start(&young, &C.vmh_ww_class, &b, &a, 0, false, false)
  young.recover = true
  actor_go(&young); wait_value(&young.model.parked, 1)
  C.assert(C.__atomic_load_n(&young.ctx.wounded, 2) == 0)
  C.assert(C.ww_mutex_lock(&b, &old) == 0)
  wait_value(&young.dropped, 1)
  C.assert(young.result == -C.EDEADLK && young.ctx.wounded != 0 && old.acquired == 2)
  C.__atomic_store_n(&young.retry, u32(1), 3)
  wait_queue(&a, 1)
  C.assert(young.ctx.wounded == 0 && young.ctx.acquired == 0)
  C.ww_mutex_unlock(&b); C.ww_mutex_unlock(&a)
  wait_value(&young.locked, 1)
  C.assert(young.ctx.wounded == 0)
  actor_release(&young); actor_join(&young)
  C.ww_acquire_fini(&old)
  C.ww_mutex_destroy(&a); C.ww_mutex_destroy(&b)
 }
}
fn first_lock(klass &C.ww_class) {
 unsafe {
  mut mutexp := C.ww_mutex{}
  mut old := C.ww_acquire_ctx{}
  C.ww_mutex_init(&mutexp, klass); C.ww_acquire_init(&old, klass)
  C.assert(C.ww_mutex_lock(&mutexp, &old) == 0)
  mut first := Actor{}
  actor_start(&first, klass, nil, &mutexp, 0, false, false)
  actor_go(&first); wait_value(&first.model.parked, 1)
  C.assert(C.__atomic_load_n(&first.returned, 2) == 0 && first.ctx.acquired == 0)
  C.__atomic_store_n(&C.vmh_u64(&first.model.pending), u64(1) << 14, 3)
  C.assert(C.vinix_linuxkpi_task_enqueue(&first.model))
  for spin := u32(0); spin < 1000000; spin++ {
   if !C.vinix_linuxkpi_task_queued(&first.model) { break }
   C.sched_yield()
  }
  C.assert(!C.vinix_linuxkpi_task_queued(&first.model))
  C.assert(C.__atomic_load_n(&first.returned, 2) == 0)
  C.ww_mutex_unlock(&mutexp)
  wait_value(&first.locked, 1)
  actor_release(&first); actor_join(&first)
  C.ww_acquire_fini(&old); C.ww_mutex_destroy(&mutexp)
 }
}
fn first_request_does_not_wound() {
 unsafe {
  C.DEFINE_WW_CLASS(C.vmh_ww_class)
  mut mutexp := C.ww_mutex{}
  C.ww_mutex_init(&mutexp, &C.vmh_ww_class)
  mut older := Actor{}
  mut younger := Actor{}
  actor_start(&older, &C.vmh_ww_class, nil, &mutexp, 0, false, false)
  actor_start(&younger, &C.vmh_ww_class, &mutexp, nil, 1, false, false)
  actor_go(&younger); wait_value(&younger.locked, 1)
  mut tryctx := C.ww_acquire_ctx{}
  C.ww_acquire_init(&tryctx, &C.vmh_ww_class); tryctx.wounded = 1
  C.assert(C.ww_mutex_trylock(&mutexp, &tryctx) == 0 && tryctx.wounded == 0 && tryctx.acquired == 0)
  C.ww_acquire_fini(&tryctx)
  actor_go(&older); wait_value(&older.model.parked, 1)
  C.assert(C.__atomic_load_n(&younger.ctx.wounded, 2) == 0)
  actor_release(&younger); actor_join(&younger)
  wait_value(&older.locked, 1)
  actor_release(&older); actor_join(&older)
  C.ww_mutex_destroy(&mutexp)
 }
}
fn wounded_free_lock() {
 unsafe {
  C.DEFINE_WW_CLASS(C.vmh_ww_class)
  mut a := C.ww_mutex{}
  mut b := C.ww_mutex{}
  mut free_lock := C.ww_mutex{}
  C.ww_mutex_init(&a, &C.vmh_ww_class); C.ww_mutex_init(&b, &C.vmh_ww_class)
  C.ww_mutex_init(&free_lock, &C.vmh_ww_class)
  mut older := Actor{}
  actor_start(&older, &C.vmh_ww_class, &b, &a, 0, false, false)
  mut young := C.ww_acquire_ctx{}
  C.ww_acquire_init(&young, &C.vmh_ww_class)
  C.assert(C.ww_mutex_lock(&a, &young) == 0)
  actor_go(&older); wait_value(&older.model.parked, 1)
  C.assert(C.__atomic_load_n(&young.wounded, 2) != 0)
  C.assert(C.ww_mutex_lock(&free_lock, &young) == 0)
  C.assert(young.wounded != 0 && young.acquired == 2)
  C.assert(C.ww_mutex_trylock(&b, &young) == 0)
  C.assert(C.ww_mutex_lock(&b, &young) == -C.EDEADLK)
  C.assert(young.acquired == 2 && young.wounded != 0)
  C.ww_mutex_unlock(&a); C.ww_mutex_unlock(&free_lock)
  wait_value(&older.locked, 1)
  actor_release(&older); actor_join(&older)
  C.assert(C.ww_mutex_lock(&free_lock, &young) == 0)
  C.assert(young.wounded == 0 && young.acquired == 1)
  C.ww_mutex_unlock(&free_lock); C.ww_acquire_fini(&young)
  C.ww_mutex_destroy(&a); C.ww_mutex_destroy(&b); C.ww_mutex_destroy(&free_lock)
 }
}
fn waiter_fairness(klass &C.ww_class) {
 unsafe {
  mut mutexp := C.ww_mutex{}
  C.ww_mutex_init(&mutexp, klass)
  C.assert(C.ww_mutex_lock(&mutexp, nil) == 0)
  mut actors := [6]Actor{}
  mut order := [6]u32{}
  mut count := u32(0)
  starts := [u32(1), 2, 3, 0, 4, 5]!
  arrivals := [u32(0), 3, 4, 1, 5, 2]!
  for i in u32(0)..u32(6) {
   index := starts[i]
   actor_start(&actors[index], klass, nil, &mutexp, index, index == 0 || index >= 4, false)
   actors[index].order = &order[0]; actors[index].count = &count
  }
  for i in u32(0)..u32(6) {
   actor_go(&actors[arrivals[i]])
   wait_queue(&mutexp, i + 1)
   wait_value(&actors[arrivals[i]].model.parked, 1)
  }
  C.ww_mutex_unlock(&mutexp)
  for i in u32(0)..u32(6) {
   wait_value(&actors[i].locked, 1)
   C.assert(C.__atomic_load_n(&count, 2) == i + 1 && order[i] == i)
   C.assert(C.ww_mutex_trylock(&mutexp, nil) == 0)
   actor_release(&actors[i]); actor_join(&actors[i])
  }
  C.assert(C.vmh_mutex_waiters(&mutexp.base) == 0)
  C.ww_mutex_destroy(&mutexp)
 }
}
fn interrupt_and_handoff(klass &C.ww_class) {
 unsafe {
  mut mutexp := C.ww_mutex{}
  mut private := C.ww_mutex{}
  C.ww_mutex_init(&mutexp, klass); C.ww_mutex_init(&private, klass)
  mut actor := Actor{}
  for round in u32(0)..u32(200) {
   C.assert(C.ww_mutex_lock(&mutexp, nil) == 0)
   actor_start(&actor, klass, &private, &mutexp, 0, false, true)
   actor_go(&actor); wait_value(&actor.model.parked, 1)
   C.__atomic_store_n(&C.vmh_u64(&actor.model.pending), u64(1) << 14, 3)
   if klass.is_wait_die == 0 { C.__atomic_store_n(&actor.ctx.wounded, u16(1), 3) }
   if round & 1 == 0 {
    C.assert(C.vinix_linuxkpi_task_enqueue(&actor.model))
    wait_value(&actor.dropped, 1)
    C.assert(actor.result == -C.EINTR && actor.ctx.acquired == 0)
    actor_join(&actor)
    C.assert(C.vmh_mutex_waiters(&mutexp.base) == 0 && C.ww_mutex_is_locked(&mutexp))
    C.ww_mutex_unlock(&mutexp)
   } else {
    C.ww_mutex_unlock(&mutexp)
    wait_value(&actor.locked, 1)
    C.assert(actor.result == 0 && actor.ctx.acquired == 2)
    actor_release(&actor); actor_join(&actor)
   }
   C.assert(C.vmh_mutex_waiters(&mutexp.base) == 0 && C.vmh_mutex_waiters(&private.base) == 0)
  }
  C.assert(C.ww_mutex_lock(&mutexp, nil) == 0)
  actor_start(&actor, klass, nil, &mutexp, 0, false, true)
  actor.slow = true
  actor_go(&actor); wait_value(&actor.model.parked, 1)
  C.__atomic_store_n(&C.vmh_u64(&actor.model.pending), u64(1) << 14, 3)
  C.assert(C.vinix_linuxkpi_task_enqueue(&actor.model))
  actor_join(&actor)
  C.assert(actor.result == -C.EINTR && C.vmh_mutex_waiters(&mutexp.base) == 0)
  C.ww_mutex_unlock(&mutexp)
  C.ww_mutex_destroy(&mutexp); C.ww_mutex_destroy(&private)
 }
}
fn wounded_handoff() {
 unsafe {
  C.DEFINE_WW_CLASS(C.vmh_ww_class)
  mut target := C.ww_mutex{}
  mut private := C.ww_mutex{}
  C.ww_mutex_init(&target, &C.vmh_ww_class); C.ww_mutex_init(&private, &C.vmh_ww_class)
  C.assert(C.ww_mutex_lock(&target, nil) == 0)
  mut actor := Actor{}
  actor_start(&actor, &C.vmh_ww_class, &private, &target, 0, false, false)
  actor_go(&actor); wait_value(&actor.model.parked, 1)
  C.__atomic_store_n(&actor.ctx.wounded, u16(1), 3)
  C.ww_mutex_unlock(&target)
  wait_value(&actor.locked, 1)
  C.assert(actor.result == 0 && actor.ctx.wounded != 0 && actor.ctx.acquired == 2)
  actor_release(&actor); actor_join(&actor)
  C.ww_mutex_destroy(&target); C.ww_mutex_destroy(&private)
 }
}
@[export: 'vmh_ww_mutex_tests']
pub fn ww_mutex_tests() {
 unsafe {
  mut controller := C.native_task_model{}
  C.vmh_sync_model_init(&controller, 209); C.vmh_native_task = &controller
  saved_cpu := C.vmh_current_cpu
  before := C.vmh_live_pages
  C.DEFINE_WD_CLASS(C.vmh_wait_die_class)
  C.DEFINE_WW_CLASS(C.vmh_wound_wait_class)
  C.vmh_fail_allocation = true
  basic(&C.vmh_wait_die_class); basic(&C.vmh_wound_wait_class)
  wait_die_inversion(false); wait_die_inversion(true)
  wait_die_three_cycle(); wait_die_queued_older()
  wound_blocked_elsewhere(); wounded_free_lock()
  first_lock(&C.vmh_wait_die_class); first_lock(&C.vmh_wound_wait_class)
  first_request_does_not_wound()
  waiter_fairness(&C.vmh_wait_die_class); waiter_fairness(&C.vmh_wound_wait_class)
  interrupt_and_handoff(&C.vmh_wait_die_class); interrupt_and_handoff(&C.vmh_wound_wait_class)
  wounded_handoff()
  mut a := C.ww_mutex{}
  mut b := C.ww_mutex{}
  mut ac := C.ww_acquire_ctx{}
  mut bc := C.ww_acquire_ctx{}
  C.ww_mutex_init(&a, &C.vmh_wait_die_class); C.ww_mutex_init(&b, &C.vmh_wound_wait_class)
  C.ww_acquire_init(&ac, &C.vmh_wait_die_class); C.ww_acquire_init(&bc, &C.vmh_wound_wait_class)
  C.assert(C.ww_mutex_lock(&a, &ac) == 0 && C.ww_mutex_lock(&b, &bc) == 0)
  C.ww_mutex_unlock(&b); C.ww_mutex_unlock(&a)
  C.ww_acquire_fini(&bc); C.ww_acquire_fini(&ac)
  C.ww_mutex_destroy(&b); C.ww_mutex_destroy(&a)
  C.vmh_fail_allocation = false
  C.assert(C.vmh_live_pages == before && C.task_is_running(C.current) && C.vmh_interrupts && C.vmh_preempt_depth == 0)
  C.vmh_current_cpu = saved_cpu; C.vmh_native_task = nil
  C.vmh_sync_model_destroy(&controller)
 }
}
