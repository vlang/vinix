// SPDX-License-Identifier: GPL-2.0-or-later
// Production fence/task/time/RCU algorithms; native queue/page/clock transport.
@[translated]
module dmafencefixture

#include "contract.h"

struct C.dma_fence {}

struct C.dma_fence_cb {}

@[typedef]
struct C.spinlock_t {
mut:
	locked u32
}

@[typedef]
struct C.vdf_const_char_p {}

struct C.dma_fence_ops {
mut:
	use_64bit_seqno   bool
	get_driver_name   fn (&C.dma_fence) C.vdf_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vdf_const_char_p
	enable_signaling  fn (&C.dma_fence) bool
	signaled          fn (&C.dma_fence) bool
	@wait             fn (&C.dma_fence, bool, isize) isize
	release           fn (&C.dma_fence)
	set_deadline      fn (&C.dma_fence, i64)
}

fn C.dma_fence_init(&C.dma_fence, &C.dma_fence_ops, &C.spinlock_t, u64, u64)
fn C.dma_fence_add_callback(&C.dma_fence, &C.dma_fence_cb, fn (&C.dma_fence, &C.dma_fence_cb)) i32
fn C.dma_fence_remove_callback(&C.dma_fence, &C.dma_fence_cb) bool
fn C.dma_fence_signal(&C.dma_fence) i32
fn C.dma_fence_signal_timestamp(&C.dma_fence, i64) i32
fn C.dma_fence_get_status(&C.dma_fence) i32
fn C.dma_fence_wait_timeout(&C.dma_fence, bool, isize) isize
fn C.dma_fence_default_wait(&C.dma_fence, bool, isize) isize
fn C.dma_fence_enable_sw_signaling(&C.dma_fence)
fn C.dma_fence_get(&C.dma_fence) &C.dma_fence
fn C.dma_fence_get_rcu(&C.dma_fence) &C.dma_fence
fn C.dma_fence_get_rcu_safe(&&C.dma_fence) &C.dma_fence
fn C.dma_fence_put(&C.dma_fence)
fn C.dma_fence_set_error(&C.dma_fence, i32)
fn C.dma_fence_allocate_private_stub(i64) &C.dma_fence
fn C.dma_fence_get_stub() &C.dma_fence
fn C.dma_fence_is_signaled(&C.dma_fence) bool
fn C.dma_fence_is_later(&C.dma_fence, &C.dma_fence) bool
fn C.dma_fence_is_later_or_same(&C.dma_fence, &C.dma_fence) bool
fn C.dma_fence_context_alloc(u32) u64
fn C.dma_fence_set_deadline(&C.dma_fence, i64)
fn C.dma_fence_wait_any_timeout(&&C.dma_fence, u32, bool, isize, &u32) isize
fn C.dma_fence_signal_locked(&C.dma_fence) i32
fn C.wake_up_process(&C.task_struct) i32
fn C.vkp_spin_lock_irqsave(voidptr) usize
fn C.vkp_spin_unlock_irqrestore(voidptr, usize)
fn C.dfh_flags(&C.dma_fence) u64
fn C.dfh_set_flags(&C.dma_fence, u64)
fn C.dfh_refcount(&C.dma_fence) u32
fn C.dfh_cb_empty(&C.dma_fence_cb) bool
fn C.dfh_list_empty(&C.dma_fence) bool
fn C.dfh_lock_held(&C.dma_fence) u32
fn C.dfh_timestamp(&C.dma_fence) i64
fn C.dfh_error(&C.dma_fence) i32
fn C.vinix_linuxkpi_time_tick(u64)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_set_task_state(u32)
fn C.vdf_init(voidptr, voidptr, voidptr, u64, u64)
fn C.kfree(voidptr)

struct FenceNode {
mut:
	fence           C.dma_fence
	lock            C.spinlock_t
	enables         u32
	peek            u32
	custom_waits    u32
	releases        u32
	complete        bool
	enable_result   bool = true
	wait_result     isize
	deadlines       u32
	deadline        i64
	release_witness &u32 = unsafe { nil }
	free_owner      bool
}

struct FenceCallback {
mut:
	base      C.dma_fence_cb
	calls     &u32 = unsafe { nil }
	free_self bool
	order     &u32 = unsafe { nil }
	index     u32
	error     &i32 = unsafe { nil }
}

struct FenceWaiter {
mut:
	thread  C.pthread_t
	node    &FenceNode = unsafe { nil }
	ctx     &Context   = unsafe { nil }
	entered u32
	done    u32
	intr    bool
	timeout isize
	result  isize
	any     bool
	fences  [3]&C.dma_fence
	count   u32 = 3
	winner  u32 = 999
}

enum RaceOperation {
	enable
	signal
	remove
	add
	context_ids
}

struct RaceActor {
mut:
	thread    C.pthread_t
	node      &FenceNode     = unsafe { nil }
	cb        &FenceCallback = unsafe { nil }
	gate      &u32           = unsafe { nil }
	operation RaceOperation
	entered   u32
	done      u32
	result    i32
	context   u64
}

@[cinit]
__global (
	dma_clock_ns           u64
	dma_warnings           u32
	dma_names              u32
	dma_callback_calls     u32
	dma_release_calls      u32
	dma_timer_observations u32
	dma_fatal_watch        bool
	dma_fatal_fence        &C.dma_fence = unsafe { nil }
	dma_fatal_bytes        [64]u8
	dma_fatal_allocations  u32
	dma_ops                C.dma_fence_ops
)

@[export:'vinix_linuxkpi_task_get']
pub fn native_task_get(owner voidptr) {
	unsafe { C.rcuh_add32(&(&Context(owner)).refs, 1) }
}

@[export:'vinix_linuxkpi_task_put']
pub fn native_task_put(owner voidptr) {
	unsafe { release_context(&Context(owner)) }
}

@[export:'vinix_linuxkpi_task_signal_pending']
pub fn native_pending(owner C.rcuh_const_voidp, fatal bool) bool {
	return unsafe { C.rcuh_load32(&(&Context(voidptr(owner))).pending) != 0 }
}

@[export:'vinix_linuxkpi_task_dequeue']
pub fn native_dequeue(owner voidptr) {
	unsafe { C.rcuh_store32(&(&Context(owner)).queued, 0) }
}

@[export:'vinix_linuxkpi_task_enqueue']
pub fn native_enqueue(owner voidptr) bool {
	unsafe {
		C.rcuh_exchange32(&(&Context(owner)).queued, 1)
		return true
	}
}

@[export:'vinix_linuxkpi_task_is_dead']
pub fn native_dead(owner C.rcuh_const_voidp) bool {
	return unsafe { C.rcuh_load32(&(&Context(voidptr(owner))).retired) != 0 }
}

@[export:'vinix_linuxkpi_task_park']
pub fn native_park() {
	unsafe {
		c := context()
		C.rcuh_add32(&c.parks, 1)
		for C.rcuh_load32(&c.queued) == 0 { C.sched_yield() }
	}
}

@[export:'vinix_linuxkpi_iowait_block']
pub fn unsupported_iowait(owner voidptr) { check(false, @LINE) }

@[export:'vinix_linuxkpi_clock_ns']
pub fn native_clock() u64 {
	return unsafe { C.rcuh_load64(&dma_clock_ns) }
}

@[export:'vinix_linuxkpi_timer_tick']
pub fn timer_observation() {
	unsafe { C.rcuh_add32(&dma_timer_observations, 1) }
}

@[export:'vkp_spin_lock']
pub fn plain_lock(p voidptr) {
	preempt_disable()
	unsafe { for C.rcuh_exchange32(&u32(p), 1) != 0 { C.sched_yield() }
	 }
}

@[export:'vkp_spin_unlock']
pub fn plain_unlock(p voidptr) {
	unsafe { C.rcuh_store32(&u32(p), 0) }
	preempt_enable()
}

@[export:'vkp_warn']
pub fn warning(file C.rcuh_const_charp, line i32) {
	unsafe { C.rcuh_add32(&dma_warnings, 1) }
}

@[export:'vkp_warn_note']
pub fn warning_note(file C.rcuh_const_charp, line i32) {}

@[export:'vkp_refcount_warning']
pub fn refcount_warning(kind i32) { check(false, @LINE) }

@[export:'vkp_refcount_note']
pub fn refcount_note(kind i32) {}

@[export:'vkp_refcount_dec_and_test']
pub fn unsupported_refcount_lock(owner voidptr) bool {
	check(false, @LINE)
	return false
}

@[export:'vkp_mutex_lock']
pub fn unsupported_mutex(owner voidptr) { check(false, @LINE) }

@[export:'vkp_mutex_unlock']
pub fn unsupported_mutex_unlock(owner voidptr) { check(false, @LINE) }

@[export:'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason C.rcuh_const_charp, line i32) {
	unsafe {
		if dma_fatal_watch {
			mut bytes := [64]u8{}
			C.memcpy(&bytes[0], dma_fatal_fence, 64)
			for i := 0; i < 64; i++ { check(bytes[i] == dma_fatal_bytes[i], @LINE) }
			check(C.rcuh_load32(&page_calls) == dma_fatal_allocations, @LINE)
			C.fprintf(C.stderr, c'DMA wait validation preserved fence\n')
		}
		C.fprintf(C.stderr, c'DMA-fence invariant: %s:%d\n', reason, line)
		C.abort()
	}
}

fn advance(ticks u64) {
	unsafe {
		now := C.rcuh_add64(&dma_clock_ns, ticks * 1000000) + ticks * 1000000
		C.vinix_linuxkpi_time_tick(now)
	}
}

fn driver_name(fence &C.dma_fence) C.vdf_const_char_p {
	mut native := C.vdf_const_char_p{}
	text := unsafe { &char(c'host-dma') }
	unsafe {
		C.rcuh_add32(&dma_names, 1)
		C.memcpy(&native, &text, sizeof(voidptr))
	}
	return native
}

fn enable(fence &C.dma_fence) bool {
	unsafe {
		node := &FenceNode(fence)
		check(C.dfh_lock_held(fence) == 1 && !may_sleep(), @LINE)
		C.rcuh_add32(&node.enables, 1)
		return node.enable_result
	}
}

fn signaled(fence &C.dma_fence) bool {
	unsafe {
		node := &FenceNode(fence)
		C.rcuh_add32(&node.peek, 1)
		return node.complete
	}
}

fn custom_wait(fence &C.dma_fence, intr bool, timeout isize) isize {
	unsafe {
		node := &FenceNode(fence)
		check(may_sleep(), @LINE)
		C.rcuh_add32(&node.custom_waits, 1)
		return node.wait_result
	}
}

fn release(fence &C.dma_fence) {
	unsafe {
		node := &FenceNode(fence)
		witness := node.release_witness
		owns := node.free_owner
		C.rcuh_add32(&node.releases, 1)
		if witness != nil { C.rcuh_add32(witness, 1) }
		if owns { C.kfree(node) }
	}
}

fn deadline(fence &C.dma_fence, value i64) {
	unsafe {
		node := &FenceNode(fence)
		check(C.dfh_lock_held(fence) == 0, @LINE)
		node.deadline = value
		C.rcuh_add32(&node.deadlines, 1)
	}
}

fn callback(fence &C.dma_fence, base &C.dma_fence_cb) {
	unsafe {
		cb := &FenceCallback(base)
		calls := cb.calls
		owns := cb.free_self
		order := cb.order
		index := cb.index
		error := cb.error
		check(C.dfh_lock_held(fence) == 1 && (flags() & 512) == 0 && C.dfh_cb_empty(base) && (C.dfh_flags(fence) & 3) == 3, @LINE)
		position := C.rcuh_add32(calls, 1)
		if order != nil { order[position] = index }
		if error != nil { *error = C.dfh_error(fence) }
		if owns { C.kfree(cb) }
	}
}

fn initialize(node &FenceNode) {
	unsafe { C.vdf_init(node, &dma_ops, &node.lock, 7, 1) }
}

fn wait_actor(argument voidptr) voidptr {
	unsafe {
		waiter := &FenceWaiter(argument)
		waiter.ctx = context()
		native_task_get(waiter.ctx)
		C.rcuh_store32(&waiter.entered, 1)
		waiter.result = if waiter.any {
			C.dma_fence_wait_any_timeout(&waiter.fences[0], waiter.count, waiter.intr, waiter.timeout, &waiter.winner)
		} else {
			C.dma_fence_wait_timeout(&waiter.node.fence, waiter.intr, waiter.timeout)
		}
		check(waiter.ctx.task.__state == 0 && C.rcuh_load32(&waiter.ctx.refs) == 2, @LINE)
		C.rcuh_store32(&waiter.done, 1)
		return nil
	}
}

fn start_wait(waiter &FenceWaiter) {
	unsafe {
		check(C.pthread_create(&waiter.thread, nil, wait_actor, waiter) == 0, @LINE)
		await32(&waiter.entered, 1)
	}
}

fn join_wait(waiter &FenceWaiter) {
	unsafe {
		check(C.pthread_join(waiter.thread, nil) == 0 && C.rcuh_load32(&waiter.done) == 1, @LINE)
		release_context(waiter.ctx)
	}
}

fn await_deadline() {
	for turns := 0; turns < 20000000; turns++ {
		if C.vinix_linuxkpi_time_waiters() != 0 { return }
		C.sched_yield()
	}
	check(false, @LINE)
}

fn race_actor(argument voidptr) voidptr {
	unsafe {
		a := &RaceActor(argument)
		context()
		C.rcuh_store32(&a.entered, 1)
		for C.rcuh_load32(a.gate) == 0 { C.sched_yield() }
		match a.operation {
			.enable { C.dma_fence_enable_sw_signaling(&a.node.fence) }
			.signal { a.result = C.dma_fence_signal(&a.node.fence) }
			.remove { a.result = i32(C.dma_fence_remove_callback(&a.node.fence, &a.cb.base)) }
			.add { a.result = C.dma_fence_add_callback(&a.node.fence, &a.cb.base, callback) }
			.context_ids { a.context = C.dma_fence_context_alloc(3) }
		}
		C.rcuh_store32(&a.done, 1)
		return nil
	}
}

fn start_race(a &RaceActor) {
	unsafe {
		check(C.pthread_create(&a.thread, nil, race_actor, a) == 0, @LINE)
		await32(&a.entered, 1)
	}
}

fn join_race(a &RaceActor) {
	unsafe { check(C.pthread_join(a.thread, nil) == 0 && C.rcuh_load32(&a.done) == 1, @LINE) }
}

fn callback_tests() {
	unsafe {
		mut node := FenceNode{}
		initialize(&node)
		C.dfh_set_flags(&node.fence, 0x80)
		dma_callback_calls = 0
		mut order := [8]u32{}
		mut callbacks := [8]FenceCallback{}
		before := C.rcuh_load32(&page_live)
		for i := 0; i < 8; i++ {
			callbacks[i].calls = &dma_callback_calls
			callbacks[i].order = &order[0]
			callbacks[i].index = u32(i)
			check(C.dma_fence_add_callback(&node.fence, &callbacks[i].base, callback) == 0, @LINE)
		}
		check(C.dma_fence_remove_callback(&node.fence, &callbacks[3].base) && !C.dma_fence_remove_callback(&node.fence, &callbacks[3].base), @LINE)
		self := &FenceCallback(C.vkr_kmalloc(sizeof(FenceCallback), 3264 | 0x100))
		self.calls = &dma_callback_calls
		self.free_self = true
		check(C.dma_fence_add_callback(&node.fence, &self.base, callback) == 0, @LINE)
		C.dma_fence_set_error(&node.fence, -5)
		check(C.dma_fence_get_status(&node.fence) == 0, @LINE)
		check(C.dma_fence_signal(&node.fence) == 0 && dma_callback_calls == 8 && C.dma_fence_get_status(&node.fence) == -5 && C.dfh_flags(&node.fence) == 0x87, @LINE)
		for i, value in [u32(0), 1, 2, 4, 5, 6, 7]! { check(order[i] == value, @LINE) }
		check(C.rcuh_load32(&page_live) == before, @LINE)
		C.dma_fence_put(&node.fence)
		mut failed := FenceNode{ enable_result: false }
		initialize(&failed)
		mut denied := FenceCallback{ calls: &dma_callback_calls }
		check(C.dma_fence_add_callback(&failed.fence, &denied.base, callback) == -2 && failed.enables == 1 && dma_callback_calls == 8, @LINE)
		check(C.dma_fence_is_signaled(&failed.fence) && C.dfh_cb_empty(&denied.base), @LINE)
		C.dma_fence_put(&failed.fence)
		mut polled := FenceNode{ complete: true }
		initialize(&polled)
		check(C.dma_fence_is_signaled(&polled.fence) && polled.peek == 1, @LINE)
		C.dma_fence_put(&polled.fence)
		mut locked := FenceNode{}
		initialize(&locked)
		saved := C.vkp_spin_lock_irqsave(&locked.lock)
		check(C.dma_fence_signal_locked(&locked.fence) == 0, @LINE)
		C.vkp_spin_unlock_irqrestore(&locked.lock, saved)
		C.dma_fence_put(&locked.fence)
	}
}

fn ops_tests() {
	unsafe {
		dma_ops.@wait = custom_wait
		dma_ops.set_deadline = deadline
		mut node := FenceNode{ wait_result: -62 }
		initialize(&node)
		check(C.dma_fence_wait_timeout(&node.fence, true, 0) == -62 && node.custom_waits == 1 && node.enables == 1, @LINE)
		node.wait_result = 17
		check(C.dma_fence_wait_timeout(&node.fence, false, 23) == 17 && node.custom_waits == 2, @LINE)
		check(C.dma_fence_default_wait(&node.fence, false, 0) == 0 && node.custom_waits == 2, @LINE)
		check(C.dma_fence_default_wait(&node.fence, false, -7) == -7, @LINE)
		check(C.dma_fence_wait_timeout(&node.fence, false, -7) == -22, @LINE)
		saved := irq_save()
		check(C.dma_fence_default_wait(&node.fence, false, -7) == -7 && (flags() & 512) == 0, @LINE)
		irq_restore(saved)
		C.rcuh_store32(&context().pending, 1)
		check(C.dma_fence_default_wait(&node.fence, true, -7) == -512, @LINE)
		C.rcuh_store32(&context().pending, 0)
		C.dma_fence_set_deadline(&node.fence, 89)
		check(node.deadlines == 1 && node.deadline == 89, @LINE)
		C.dma_fence_signal(&node.fence)
		C.dma_fence_set_deadline(&node.fence, 90)
		check(node.deadlines == 1, @LINE)
		C.dma_fence_put(&node.fence)
		dma_ops.@wait = nil
		dma_ops.set_deadline = nil
		dma_release_calls = 0
		owner := &FenceNode(C.vkr_kmalloc(sizeof(FenceNode), 3264 | 0x100))
		initialize(owner)
		owner.release_witness = &dma_release_calls
		owner.free_owner = true
		C.dma_fence_put(&owner.fence)
		check(dma_release_calls == 1, @LINE)
		name_calls := C.rcuh_load32(&dma_names)
		mut pending := FenceNode{}
		initialize(&pending)
		check(C.rcuh_load32(&dma_names) == name_calls, @LINE)
		mut calls := u32(0)
		mut error := i32(0)
		mut cb := FenceCallback{ calls: &calls, error: &error }
		check(C.dma_fence_add_callback(&pending.fence, &cb.base, callback) == 0, @LINE)
		C.dma_fence_put(&pending.fence)
		check(pending.releases == 1 && calls == 1 && error == -35 && C.dfh_cb_empty(&cb.base) && C.rcuh_load32(&dma_names) == name_calls + 2, @LINE)
	}
}

fn race_tests() {
	unsafe {
		mut node := FenceNode{}
		initialize(&node)
		mut gate := u32(0)
		mut actors := [16]RaceActor{}
		for i := 0; i < 16; i++ {
			actors[i].node = &node
			actors[i].gate = &gate
			start_race(&actors[i])
		}
		C.rcuh_store32(&gate, 1)
		for i := 0; i < 16; i++ { join_race(&actors[i]) }
		check(node.enables == 1, @LINE)
		C.dma_fence_put(&node.fence)
		for iteration := 0; iteration < 100; iteration++ {
			mut target := FenceNode{}
			initialize(&target)
			mut calls := u32(0)
			mut cb := FenceCallback{ calls: &calls }
			check(C.dma_fence_add_callback(&target.fence, &cb.base, callback) == 0, @LINE)
			gate = 0
			mut remove := RaceActor{ node: &target, cb: &cb, gate: &gate, operation: .remove }
			mut signaler := RaceActor{ node: &target, gate: &gate, operation: .signal }
			start_race(&remove)
			start_race(&signaler)
			C.rcuh_store32(&gate, 1)
			join_race(&remove)
			join_race(&signaler)
			check(signaler.result == 0 && calls == u32(1 - remove.result) && C.dfh_cb_empty(&cb.base), @LINE)
			C.dma_fence_put(&target.fence)
		}
		for iteration := 0; iteration < 100; iteration++ {
			mut target := FenceNode{}
			initialize(&target)
			mut calls := u32(0)
			mut cb := FenceCallback{ calls: &calls }
			gate = 0
			mut add := RaceActor{ node: &target, cb: &cb, gate: &gate, operation: .add }
			mut first := RaceActor{ node: &target, gate: &gate, operation: .signal }
			mut second := RaceActor{ node: &target, gate: &gate, operation: .signal }
			start_race(&add)
			start_race(&first)
			start_race(&second)
			C.rcuh_store32(&gate, 1)
			join_race(&add)
			join_race(&first)
			join_race(&second)
			check((first.result == 0 && second.result == -22) || (first.result == -22 && second.result == 0), @LINE)
			check((add.result == 0 && calls == 1) || (add.result == -2 && calls == 0), @LINE)
			check(C.dfh_cb_empty(&cb.base), @LINE)
			C.dma_fence_put(&target.fence)
		}
		gate = 0
		for i := 0; i < 16; i++ {
			actors[i] = RaceActor{ gate: &gate, operation: .context_ids }
			start_race(&actors[i])
		}
		C.rcuh_store32(&gate, 1)
		for i := 0; i < 16; i++ {
			join_race(&actors[i])
			check(actors[i].context != 0, @LINE)
			for j := 0; j < i; j++ {
				left := actors[i].context
				right := actors[j].context
				check(left + 3 <= right || right + 3 <= left, @LINE)
			}
		}
		mut earlier := FenceNode{}
		mut later := FenceNode{}
		initialize(&earlier)
		C.vdf_init(&later, &dma_ops, &later.lock, 7, 0x100000001)
		C.vdf_init(&earlier, &dma_ops, &earlier.lock, 7, 0xfffffffe)
		check(C.dma_fence_is_later(&later.fence, &earlier.fence), @LINE)
		dma_ops.use_64bit_seqno = true
		check(C.dma_fence_is_later(&later.fence, &earlier.fence) && C.dma_fence_is_later_or_same(&later.fence, &later.fence), @LINE)
		dma_ops.use_64bit_seqno = false
		C.dma_fence_put(&earlier.fence)
		C.dma_fence_put(&later.fence)
		mut first64 := FenceNode{}
		mut second64 := FenceNode{}
		C.vdf_init(&first64, &dma_ops, &first64.lock, 8, 1)
		C.vdf_init(&second64, &dma_ops, &second64.lock, 8, 0x100000000)
		check(!C.dma_fence_is_later(&second64.fence, &first64.fence), @LINE)
		dma_ops.use_64bit_seqno = true
		check(C.dma_fence_is_later(&second64.fence, &first64.fence), @LINE)
		dma_ops.use_64bit_seqno = false
		C.dma_fence_put(&first64.fence)
		C.dma_fence_put(&second64.fence)
	}
}

fn stub_tests() {
	unsafe {
		baseline := C.rcuh_load32(&page_live)
		global := C.dma_fence_get_stub()
		stamp := C.dfh_timestamp(global)
		second := C.dma_fence_get_stub()
		check(usize(global) == usize(second) && C.dfh_refcount(global) == 3 && C.dma_fence_is_signaled(global) && C.dfh_timestamp(second) == stamp, @LINE)
		C.dma_fence_put(global)
		C.dma_fence_put(second)
		check(C.dfh_refcount(global) == 1, @LINE)
		C.rcuh_store32(&page_fail, 1)
		check(C.dma_fence_allocate_private_stub(77) == nil, @LINE)
		C.rcuh_store32(&page_fail, 0)
		private := C.dma_fence_allocate_private_stub(123)
		check(private != nil && C.dfh_timestamp(private) == 123 && C.dma_fence_is_signaled(private), @LINE)
		route(1)
		C.rcuh_read_lock()
		mut published := private
		got := C.dma_fence_get_rcu_safe(&published)
		check(usize(got) == usize(private) && C.dfh_refcount(private) == 2, @LINE)
		C.dma_fence_put(got)
		frees := C.rcuh_load32(&page_frees)
		C.rcuh_store32(&page_fail, 1)
		C.dma_fence_put(private)
		attempt := attempts(1)
		await_attempt(1, attempt)
		check(C.rcuh_load32(&page_frees) == frees && C.dma_fence_get_rcu(private) == nil, @LINE)
		C.rcuh_read_unlock()
		route(0)
		C.rcuh_store32(&page_fail, 0)
		C.rcu_barrier()
		check(C.rcuh_load32(&page_live) == baseline, @LINE)
	}
}

fn wait_tests() {
	unsafe {
		mut poll := FenceNode{}
		initialize(&poll)
		check(C.dma_fence_wait_timeout(&poll.fence, false, 0) == 0, @LINE)
		C.rcuh_store32(&context().pending, 1)
		check(C.dma_fence_wait_timeout(&poll.fence, true, 0) == -512, @LINE)
		C.rcuh_store32(&context().pending, 0)
		C.dma_fence_signal(&poll.fence)
		check(C.dma_fence_wait_timeout(&poll.fence, true, 0) == 1, @LINE)
		C.dma_fence_put(&poll.fence)
		mut interrupted := FenceNode{}
		initialize(&interrupted)
		mut intr := FenceWaiter{ node: &interrupted, intr: true, timeout: 50 }
		start_wait(&intr)
		await_deadline()
		C.rcuh_store32(&intr.ctx.pending, 1)
		C.wake_up_process(&intr.ctx.task)
		join_wait(&intr)
		check(intr.result == -512 && C.dfh_list_empty(&interrupted.fence) && C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		C.dma_fence_put(&interrupted.fence)
		mut forever := FenceNode{}
		initialize(&forever)
		mut infinite := FenceWaiter{ node: &forever, timeout: isize(0x7fffffffffffffff) }
		start_wait(&infinite)
		await32(&infinite.ctx.parks, 1)
		check(C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		C.dma_fence_signal(&forever.fence)
		join_wait(&infinite)
		check(infinite.result == isize(0x7fffffffffffffff), @LINE)
		C.dma_fence_put(&forever.fence)
		mut spurious := FenceNode{}
		initialize(&spurious)
		mut retry := FenceWaiter{ node: &spurious, timeout: 50 }
		start_wait(&retry)
		await_deadline()
		await32(&retry.ctx.parks, 1)
		C.rcuh_store32(&retry.ctx.pending, 1)
		C.wake_up_process(&retry.ctx.task)
		await32(&retry.ctx.parks, 2)
		check(C.rcuh_load32(&retry.done) == 0, @LINE)
		C.dma_fence_signal(&spurious.fence)
		join_wait(&retry)
		check(retry.result > 0, @LINE)
		C.dma_fence_put(&spurious.fence)
	}
}

fn any_tests() {
	unsafe {
		mut nodes := [3]FenceNode{}
		mut fences := [3]&C.dma_fence{}
		for i := 0; i < 3; i++ {
			initialize(&nodes[i])
			fences[i] = &nodes[i].fence
		}
		mut index := u32(777)
		check(C.dma_fence_wait_any_timeout(&fences[0], 0, false, 1, &index) == -22 && index == 777, @LINE)
		check(C.dma_fence_wait_any_timeout(&fences[0], 3, false, -1, &index) == -22 && C.dma_fence_wait_any_timeout(&fences[0], 3, false, 0, &index) == 0, @LINE)
		baseline := C.rcuh_load32(&page_live)
		C.rcuh_store32(&page_fail, 1)
		check(C.dma_fence_wait_any_timeout(&fences[0], 3, false, 9, &index) == -12 && C.rcuh_load32(&context().refs) == 1, @LINE)
		C.rcuh_store32(&page_fail, 0)
		for i := 0; i < 3; i++ { check(C.dfh_list_empty(fences[i]), @LINE) }
		C.dma_fence_signal(fences[1])
		check(C.dma_fence_wait_any_timeout(&fences[0], 3, false, 11, &index) == 11 && index == 1 && C.dfh_list_empty(fences[0]), @LINE)
		check(C.dma_fence_wait_any_timeout(&fences[0], 3, false, 0, &index) == 1 && index == 1, @LINE)
		for i := 0; i < 3; i++ { C.dma_fence_put(fences[i]) }
		check(C.rcuh_load32(&page_live) == baseline, @LINE)
		for round := 0; round < 3; round++ {
			for i := 0; i < 3; i++ {
				nodes[i] = FenceNode{}
				initialize(&nodes[i])
				fences[i] = &nodes[i].fence
			}
			mut waiter := FenceWaiter{ any: true, fences: fences, timeout: 10, intr: round == 2 }
			start_wait(&waiter)
			await_deadline()
			if round == 0 {
				C.dma_fence_signal(fences[2])
			} else if round == 1 {
				advance(10)
			} else {
				C.rcuh_store32(&waiter.ctx.pending, 1)
				C.wake_up_process(&waiter.ctx.task)
			}
			join_wait(&waiter)
			if round == 0 {
				check(waiter.result > 0 && waiter.winner == 2, @LINE)
			} else if round == 1 {
				check(waiter.result == 0 && waiter.winner == 999, @LINE)
			} else {
				check(waiter.result == -512 && waiter.winner == 999, @LINE)
			}
			for i := 0; i < 3; i++ {
				if i != 2 || round != 0 { check(C.dfh_list_empty(fences[i]), @LINE) }
				C.dma_fence_put(fences[i])
			}
			check(C.vinix_linuxkpi_time_waiters() == 0 && C.rcuh_load32(&page_live) == baseline, @LINE)
		}
	}
}

fn atomic_fastpaths() {
	unsafe {
		mut done := FenceNode{}
		initialize(&done)
		C.dma_fence_signal(&done.fence)
		mut waiting := FenceNode{}
		initialize(&waiting)
		for kind := 0; kind < 3; kind++ {
			mut saved := flags()
			if kind == 0 || kind == 2 { saved = irq_save() }
			if kind == 1 { preempt_disable() }
			if kind == 2 {
				lock_context()
				context().depth++
				cpu_depth[context().cpu]++
				unlock_context()
			}
			before_flags := flags()
			before_pins := pins()
			before_depth := depth()
			before_alloc := C.rcuh_load32(&page_calls)
			check(C.dma_fence_default_wait(&done.fence, false, 19) == 19, @LINE)
			C.rcuh_store32(&context().pending, 1)
			check(C.dma_fence_default_wait(&waiting.fence, true, 19) == -512, @LINE)
			C.rcuh_store32(&context().pending, 0)
			check(flags() == before_flags && pins() == before_pins && depth() == before_depth && C.rcuh_load32(&page_calls) == before_alloc, @LINE)
			if kind == 2 {
				lock_context()
				context().depth--
				cpu_depth[context().cpu]--
				unlock_context()
			}
			if kind == 1 { preempt_enable() }
			if kind == 0 || kind == 2 { irq_restore(saved) }
		}
		C.dma_fence_put(&done.fence)
		C.dma_fence_put(&waiting.fence)
	}
}

fn simple_tests() {
	unsafe {
		mut node := FenceNode{}
		initialize(&node)
		check(C.dfh_refcount(&node.fence) == 1 && C.dfh_list_empty(&node.fence), @LINE)
		mut calls := u32(0)
		mut cb := FenceCallback{ calls: &calls }
		check(C.dma_fence_add_callback(&node.fence, &cb.base, callback) == 0, @LINE)
		check(C.dma_fence_get_status(&node.fence) == 0 && node.enables == 1, @LINE)
		C.dma_fence_enable_sw_signaling(&node.fence)
		check(node.enables == 1, @LINE)
		check(C.dma_fence_signal_timestamp(&node.fence, 1234567) == 0 && calls == 1 && C.dfh_timestamp(&node.fence) == 1234567, @LINE)
		check(C.dma_fence_signal(&node.fence) == -22 && C.dma_fence_get_status(&node.fence) == 1 && !C.dma_fence_remove_callback(&node.fence, &cb.base), @LINE)
		check(C.dma_fence_add_callback(&node.fence, &cb.base, callback) == -2 && calls == 1, @LINE)
		C.dma_fence_put(&node.fence)
		check(node.releases == 1, @LINE)
		mut other := FenceNode{}
		initialize(&other)
		mut waiter := FenceWaiter{ node: &other, timeout: 20 }
		start_wait(&waiter)
		for C.vinix_linuxkpi_time_waiters() == 0 { C.sched_yield() }
		check(C.dma_fence_signal(&other.fence) == 0, @LINE)
		join_wait(&waiter)
		check(waiter.result > 0 && C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		C.dma_fence_put(&other.fence)
		mut timed := FenceNode{}
		initialize(&timed)
		mut timeout := FenceWaiter{ node: &timed, timeout: 3 }
		start_wait(&timeout)
		for C.vinix_linuxkpi_time_waiters() == 0 { C.sched_yield() }
		advance(3)
		join_wait(&timeout)
		check(timeout.result == 0 && C.dfh_list_empty(&timed.fence), @LINE)
		C.dma_fence_put(&timed.fence)
	}
}

fn fatal(mode i32) {
	unsafe {
		mut node := FenceNode{}
		initialize(&node)
		if mode == 19 { C.dma_fence_signal(&node.fence) }
		dma_fatal_fence = &node.fence
		C.memcpy(&dma_fatal_bytes[0], dma_fatal_fence, 64)
		dma_fatal_allocations = C.rcuh_load32(&page_calls)
		dma_fatal_watch = true
		if mode == 10 || mode == 19 {
			irq_save()
		} else if mode == 11 {
			preempt_disable()
		} else if mode == 12 {
			context().depth = 1
		} else if mode == 13 {
			context().present = false
		} else if mode == 14 || mode == 15 {
			irq_save()
		}
		if mode == 14 {
			C.dma_fence_default_wait(&node.fence, false, 2)
		} else if mode == 15 {
			mut fences := [&node.fence, &node.fence]!
			mut winner := u32(0)
			C.dma_fence_wait_any_timeout(&fences[0], 2, false, 2, &winner)
		} else if mode == 16 {
			C.vdf_init(&node.fence, &dma_ops, nil, 7, 1)
		} else if mode == 17 {
			mut bad := C.dma_fence_ops{}
			C.vdf_init(&node.fence, &bad, &node.lock, 7, 1)
		} else if mode == 18 {
			C.vdf_init(&node.fence, nil, &node.lock, 7, 1)
		} else {
			C.dma_fence_wait_timeout(&node.fence, false, 2)
		}
		check(false, @LINE)
	}
}

@[export:'main']
pub fn main(argc i32, argv &&char) i32 {
	unsafe {
		check(C.pthread_key_create(&context_key, context_destructor) == 0, @LINE)
		configured_cpus = 4
		smp_transport_ready = 1
		ctx := context()
		ctx.constructor = true
		dma_ops = C.dma_fence_ops{ get_driver_name: driver_name, get_timeline_name: driver_name, enable_signaling: enable, signaled: signaled, release: release }
		check(C.vkm_cpu_masks_bootstrap(4) == 0 && C.vkr_rcu_bootstrap(4) == 0, @LINE)
		mode := if argc > 1 { C.atoi(argv[1]) } else { 0 }
		if mode != 0 { fatal(mode) }
		simple_tests()
		callback_tests()
		ops_tests()
		race_tests()
		stub_tests()
		wait_tests()
		any_tests()
		atomic_fastpaths()
		C.rcu_barrier()
		C.vkr_rcu_shutdown_for_test()
		check(C.rcuh_load32(&page_live) == 0 && C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		check(C.rcuh_load32(&ctx.refs) == 1, @LINE)
		check(C.pthread_setspecific(context_key, nil) == 0, @LINE)
		context_destructor(ctx)
		check(C.rcuh_load32(&context_live) == 0, @LINE)
		check(C.pthread_key_delete(context_key) == 0, @LINE)
		C.printf(c'PASS: actual DMA fence/task/time/RCU and native transport observations; %u assertions\n', C.rcuh_load32(&assertions))
		return 0
	}
}
