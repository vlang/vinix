// SPDX-License-Identifier: GPL-2.0-or-later
// Genuine generated V algorithms; only native thread/page/clock transport here.
@[translated]
module resvfixture

#include "contract.h"

struct C.dma_fence {}

struct C.dma_fence_array {}

struct C.irq_work {}

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
	set_deadline      fn (&C.dma_fence, i64)
}

struct C.dma_resv {}

struct C.dma_resv_iter {}

struct C.ww_class {}

struct C.ww_acquire_ctx {
mut:
	stamp       usize
	acquired    u32
	is_wait_die u16
}

fn C.dma_resv_init(&C.dma_resv)
fn C.dma_resv_fini(&C.dma_resv)
fn C.dma_resv_lock(&C.dma_resv, &C.ww_acquire_ctx) i32
fn C.dma_resv_lock_interruptible(&C.dma_resv, &C.ww_acquire_ctx) i32
fn C.dma_resv_lock_slow(&C.dma_resv, &C.ww_acquire_ctx)
fn C.dma_resv_trylock(&C.dma_resv) bool
fn C.dma_resv_is_locked(&C.dma_resv) bool
fn C.dma_resv_unlock(&C.dma_resv)
fn C.dma_resv_reserve_fences(&C.dma_resv, u32) i32
fn C.dma_resv_add_fence(&C.dma_resv, &C.dma_fence, u32)
fn C.dma_resv_replace_fences(&C.dma_resv, u64, &C.dma_fence, u32)
fn C.dma_resv_iter_first(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_next(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_first_unlocked(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_next_unlocked(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_copy_fences(&C.dma_resv, &C.dma_resv) i32
fn C.dma_resv_get_fences(&C.dma_resv, u32, &u32, &&&C.dma_fence) i32
fn C.dma_resv_get_singleton(&C.dma_resv, u32, &&C.dma_fence) i32
fn C.dma_resv_wait_timeout(&C.dma_resv, u32, bool, usize) isize
fn C.dma_resv_test_signaled(&C.dma_resv, u32) bool
fn C.dma_resv_set_deadline(&C.dma_resv, u32, i64)
fn C.rsh_begin(&C.dma_resv_iter, &C.dma_resv, u32)
fn C.rsh_end(&C.dma_resv_iter)
fn C.rsh_usage(&C.dma_resv_iter) u32
fn C.rsh_restarted(&C.dma_resv_iter) bool
fn C.rsh_cursor_fence(&C.dma_resv_iter) &C.dma_fence
fn C.rsh_list(&C.dma_resv) voidptr
fn C.rsh_count(&C.dma_resv) u32
fn C.rsh_capacity(&C.dma_resv) u32
fn C.rsh_tag(&C.dma_resv, u32) usize
fn C.rsh_tag_address(&C.dma_resv, u32) &voidptr
fn C.rsh_atomic_load_ptr(&voidptr) voidptr
fn C.rsh_class() &C.ww_class
fn C.rsh_wait_die() u32
fn C.rsh_ctx(&C.dma_resv) &C.ww_acquire_ctx
fn C.rsh_wait_list(&C.dma_resv) bool
fn C.rsh_usage_rw(bool) u32
fn C.rsh_array_count(&C.dma_fence) u32
fn C.rsh_array_ops(&C.dma_fence) bool
fn C.rsh_array_work(&C.dma_fence) &C.irq_work
fn C.ww_acquire_init(&C.ww_acquire_ctx, &C.ww_class)
fn C.ww_acquire_done(&C.ww_acquire_ctx)
fn C.ww_acquire_fini(&C.ww_acquire_ctx)
fn C.dma_fence_get(&C.dma_fence) &C.dma_fence
fn C.dma_fence_get_rcu(&C.dma_fence) &C.dma_fence
fn C.dma_fence_put(&C.dma_fence)
fn C.dma_fence_signal(&C.dma_fence) i32
fn C.dma_fence_enable_sw_signaling(&C.dma_fence)
fn C.dma_fence_is_signaled(&C.dma_fence) bool
fn C.dfh_refcount(&C.dma_fence) u32
fn C.dfh_lock_held(&C.dma_fence) u32
fn C.vdf_init(voidptr, voidptr, voidptr, u64, u64)
fn C.vkiw_bootstrap(u32) i32
fn C.vkiw_drain(u32)
fn C.vinix_linuxkpi_time_tick(u64)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_set_task_state(u32)
fn C.wake_up_process(&C.task_struct) i32
fn C.kmalloc_size_roundup(usize) usize
fn C.krealloc_array(voidptr, usize, usize, u32) voidptr
fn C.kfree(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.vkr_kmalloc(usize, u32) voidptr
fn C.vkr_page_allocation_size(voidptr) usize

struct FenceNode {
mut:
	fence          C.dma_fence
	lock           C.spinlock_t
	enables        u32
	deadlines      u32
	deadline       i64
	custom_calls   u32
	custom_timeout isize
	custom_result  isize
	peek_gate      bool
}

enum ResvOperation {
	lock
	intr
	wait
	copy
	get
	singleton
	iter
}

struct Actor {
mut:
	thread  C.pthread_t
	obj     &C.dma_resv = unsafe { nil }
	src     &C.dma_resv = unsafe { nil }
	ctx     &Context    = unsafe { nil }
	op      ResvOperation
	entered u32
	done    u32
	release u32
	result  isize
	timeout usize = 10
	intr    bool
	count   u32
	vector  &&C.dma_fence = unsafe { nil }
	fence   &C.dma_fence  = unsafe { nil }
	cursor  C.dma_resv_iter
}

struct WdActor {
mut:
	thread  C.pthread_t
	first   &C.dma_resv = unsafe { nil }
	second  &C.dma_resv = unsafe { nil }
	backoff u32
	done    u32
	result  i32
}

@[cinit]
__global (
	dma_clock_ns           u64
	dma_timer_observations u32
	dma_warnings           u32
	resv_ops               C.dma_fence_ops
	resv_wait_ops          C.dma_fence_ops
	gate_target            voidptr
	gate_owner             voidptr
	gate_entered           u32
	gate_release           u32 = 1
	gate_get               bool
	gate_alloc_count       u32
	gate_alloc_at          u32
	gate_alloc_fail        bool
	capture_page           bool
	reused_page            voidptr
	fatal_watched          bool
	fatal_obj              &C.dma_resv = unsafe { nil }
	fatal_fence            &C.dma_fence = unsafe { nil }
	fatal_obj_bytes        [48]u8
	fatal_fence_bytes      [64]u8
	fatal_list             voidptr
	fatal_list_bytes       [56]u8
	fatal_calls            u32
)

fn same(a voidptr, b voidptr) bool { return usize(a) == usize(b) }

fn new_fence(context_id u64, seqno u64) &FenceNode {
	unsafe {
		n := &FenceNode(C.vkr_kmalloc(sizeof(FenceNode), 3264 | 0x100))
		check(n != nil, @LINE)
		C.vdf_init(n, &resv_ops, &n.lock, context_id, seqno)
		return n
	}
}

fn add(obj &C.dma_resv, n &FenceNode, usage u32) {
	check(C.dma_resv_reserve_fences(obj, 1) == 0, @LINE)
	unsafe { C.dma_resv_add_fence(obj, &n.fence, usage) }
}

fn driver_name(fence &C.dma_fence) C.vdf_const_char_p {
	mut value := C.vdf_const_char_p{}
	text := unsafe { &char(c'resv-host') }
	unsafe { C.memcpy(&value, &text, sizeof(voidptr)) }
	return value
}

fn enable(fence &C.dma_fence) bool {
	unsafe {
		check(C.dfh_lock_held(fence) == 1 && !may_sleep(), @LINE)
		C.rcuh_add32(&(&FenceNode(fence)).enables, 1)
	}
	return true
}

fn deadline(fence &C.dma_fence, time i64) {
	unsafe {
		n := &FenceNode(fence)
		n.deadline = time
		C.rcuh_add32(&n.deadlines, 1)
	}
}

fn custom_wait(fence &C.dma_fence, intr bool, timeout isize) isize {
	unsafe {
		n := &FenceNode(fence)
		n.custom_timeout = timeout
		C.rcuh_add32(&n.custom_calls, 1)
		return n.custom_result
	}
}

fn signaled(fence &C.dma_fence) bool {
	unsafe {
		if (&FenceNode(fence)).peek_gate && same(context(), gate_owner) {
			C.rcuh_store32(&gate_entered, 1)
			for C.rcuh_load32(&gate_release) == 0 { C.sched_yield() }
		}
	}
	return false
}

// This boundary executes the same acquire pointer load, then optionally holds
// one actor before returning the untouched observed bits. Real RCU and
// get-unless-zero determine the subsequent retry and owned reference.
@[export:'rsh_load_ptr_gate']
pub fn load_ptr_gate(address &voidptr) voidptr {
	unsafe {
		observed := C.rsh_atomic_load_ptr(address)
		if gate_get && same(address, gate_target) && same(context(), gate_owner) {
			C.rcuh_store32(&gate_entered, 1)
			for C.rcuh_load32(&gate_release) == 0 { C.sched_yield() }
		}
		return observed
	}
}

// Physical-page transport selects OOM at an allocation ordinal. The real
// requested-size allocator and every reservation rollback body still execute.
fn page_should_fail() bool {
	unsafe {
		if C.rcuh_load32(&gate_alloc_at) != 0 {
			ordinal := C.rcuh_add32(&gate_alloc_count, 1) + 1
			if ordinal == C.rcuh_load32(&gate_alloc_at) {
				C.rcuh_store32(&gate_entered, 1)
				for C.rcuh_load32(&gate_release) == 0 { C.sched_yield() }
				if gate_alloc_fail { return true }
			}
		}
		return false
	}
}

fn set_gate(at u32, fail bool) {
	unsafe {
		gate_alloc_count = 0
		gate_alloc_at = at
		gate_alloc_fail = fail
		gate_entered = 0
		gate_release = 0
	}
}

fn clear_gate() {
	unsafe {
		C.rcuh_store32(&gate_alloc_at, 0)
		C.rcuh_store32(&gate_release, 1)
	}
}

@[export:'vinix_linuxkpi_irqwork_send_ipi']
pub fn send_ipi(cpu u32) { check(cpu < 4, @LINE) }

fn drain_all() {
	unsafe {
		for cpu := u32(0); cpu < 4; cpu++ {
			route(cpu)
			saved := irq_save()
			lock_context()
			context().depth++
			cpu_depth[cpu]++
			unlock_context()
			C.vkiw_drain(cpu)
			lock_context()
			context().depth--
			cpu_depth[cpu]--
			unlock_context()
			irq_restore(saved)
		}
		route(0)
	}
}

@[export:'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason C.rcuh_const_charp, line i32) {
	unsafe {
		if fatal_watched {
			mut obj := [48]u8{}
			mut fence := [64]u8{}
			C.memcpy(&obj[0], fatal_obj, 48)
			C.memcpy(&fence[0], fatal_fence, 64)
			for i := 0; i < 48; i++ { check(obj[i] == fatal_obj_bytes[i], @LINE) }
			for i := 0; i < 64; i++ { check(fence[i] == fatal_fence_bytes[i], @LINE) }
			if fatal_list != nil {
				mut list := [56]u8{}
				C.memcpy(&list[0], fatal_list, 56)
				for i := 0; i < 56; i++ { check(list[i] == fatal_list_bytes[i], @LINE) }
			}
			check(C.rcuh_load32(&page_calls) == fatal_calls, @LINE)
			C.fprintf(C.stderr, c'Reservation validation preserved original48/64 storage and allocation count\n')
		}
		C.fprintf(C.stderr, c'Reservation invariant: %s:%d\n', reason, line)
		C.abort()
	}
}

fn wd_actor_main(argument voidptr) voidptr {
	unsafe {
		a := &WdActor(argument)
		mut ctx := C.ww_acquire_ctx{}
		C.ww_acquire_init(&ctx, C.rsh_class())
		check(C.dma_resv_lock(a.second, &ctx) == 0 && ctx.acquired == 1, @LINE)
		a.result = C.dma_resv_lock(a.first, &ctx)
		check(a.result == -35 && ctx.acquired == 1, @LINE)
		C.dma_resv_unlock(a.second)
		C.rcuh_store32(&a.backoff, 1)
		C.dma_resv_lock_slow(a.first, &ctx)
		check(ctx.acquired == 1 && same(C.rsh_ctx(a.first), &ctx), @LINE)
		check(C.dma_resv_lock(a.second, &ctx) == 0 && ctx.acquired == 2, @LINE)
		C.ww_acquire_done(&ctx)
		C.dma_resv_unlock(a.second)
		C.dma_resv_unlock(a.first)
		C.ww_acquire_fini(&ctx)
		C.rcuh_store32(&a.done, 1)
		return nil
	}
}

fn wd_backoff_tests() {
	unsafe {
		mut first := C.dma_resv{}
		mut second := C.dma_resv{}
		C.dma_resv_init(&first)
		C.dma_resv_init(&second)
		mut older := C.ww_acquire_ctx{}
		C.ww_acquire_init(&older, C.rsh_class())
		check(C.dma_resv_lock(&first, &older) == 0, @LINE)
		mut actor := WdActor{ first: &first, second: &second }
		check(C.pthread_create(&actor.thread, nil, wd_actor_main, &actor) == 0, @LINE)
		await32(&actor.backoff, 1)
		check(C.rcuh_load32(&actor.done) == 0 && !C.dma_resv_is_locked(&second), @LINE)
		C.dma_resv_unlock(&first)
		C.ww_acquire_fini(&older)
		check(C.pthread_join(actor.thread, nil) == 0 && actor.done == 1 && actor.result == -35, @LINE)
		C.dma_resv_fini(&first)
		C.dma_resv_fini(&second)
	}
}

fn actor_main(argument voidptr) voidptr {
	unsafe {
		a := &Actor(argument)
		a.ctx = context()
		native_task_get(a.ctx)
		gate_owner = a.ctx
		C.rcuh_store32(&a.entered, 1)
		match a.op {
			.lock, .intr {
				a.result = if a.op == .intr {
					C.dma_resv_lock_interruptible(a.obj, nil)
				} else {
					C.dma_resv_lock(a.obj, nil)
				}
				if a.result == 0 {
					for C.rcuh_load32(&a.release) == 0 { C.sched_yield() }
					C.dma_resv_unlock(a.obj)
				}
			}
			.wait { a.result = C.dma_resv_wait_timeout(a.obj, 3, a.intr, a.timeout) }
			.copy {
				check(C.dma_resv_lock(a.obj, nil) == 0, @LINE)
				a.result = C.dma_resv_copy_fences(a.obj, a.src)
				C.dma_resv_unlock(a.obj)
			}
			.get { a.result = C.dma_resv_get_fences(a.obj, 3, &a.count, &a.vector) }
			.singleton { a.result = C.dma_resv_get_singleton(a.obj, 3, &a.fence) }
			.iter {
				gate_owner = a.ctx
				C.rsh_begin(&a.cursor, a.obj, 3)
				a.fence = C.dma_resv_iter_first_unlocked(&a.cursor)
				a.fence = C.dma_resv_iter_next_unlocked(&a.cursor)
			}
		}
		C.rcuh_store32(&a.done, 1)
		return nil
	}
}

fn start(a &Actor) {
	unsafe {
		check(C.pthread_create(&a.thread, nil, actor_main, a) == 0, @LINE)
		await32(&a.entered, 1)
	}
}

fn join(a &Actor) {
	unsafe {
		check(C.pthread_join(a.thread, nil) == 0 && C.rcuh_load32(&a.done) == 1, @LINE)
		native_task_put(a.ctx)
	}
}

fn free_vector(vector &&C.dma_fence, count u32) {
	unsafe {
		for i := u32(0); i < count; i++ { C.dma_fence_put(vector[i]) }
		C.kfree(vector)
	}
}

fn locking_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		check(C.rsh_wait_die() == 1 && !C.dma_resv_is_locked(&obj) && C.rsh_usage_rw(true) == 2 && C.rsh_usage_rw(false) == 1, @LINE)
		mut older := C.ww_acquire_ctx{}
		mut younger := C.ww_acquire_ctx{}
		C.ww_acquire_init(&older, C.rsh_class())
		C.ww_acquire_init(&younger, C.rsh_class())
		check(older.is_wait_die == 1 && younger.stamp == older.stamp + 1, @LINE)
		check(C.dma_resv_lock(&obj, &older) == 0 && same(C.rsh_ctx(&obj), &older) && older.acquired == 1, @LINE)
		check(C.dma_resv_lock(&obj, &older) == -114, @LINE)
		C.dma_resv_unlock(&obj)
		C.ww_acquire_done(&older)
		C.ww_acquire_fini(&older)
		C.ww_acquire_fini(&younger)
		check(C.dma_resv_trylock(&obj) && !C.dma_resv_trylock(&obj), @LINE)
		mut blocked := Actor{ obj: &obj }
		start(&blocked)
		for C.rcuh_load32(&blocked.ctx.parks) == 0 { C.sched_yield() }
		check(C.rcuh_load32(&blocked.done) == 0, @LINE)
		C.rcuh_store32(&blocked.release, 1)
		C.dma_resv_unlock(&obj)
		join(&blocked)
		check(blocked.result == 0 && !C.dma_resv_is_locked(&obj), @LINE)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		mut cancelled := Actor{ obj: &obj, op: .intr }
		start(&cancelled)
		for C.rcuh_load32(&cancelled.ctx.parks) == 0 { C.sched_yield() }
		C.rcuh_store32(&cancelled.ctx.pending, 1)
		C.wake_up_process(&cancelled.ctx.task)
		join(&cancelled)
		check(cancelled.result == -4 && !C.rsh_wait_list(&obj), @LINE)
		C.dma_resv_unlock(&obj)
		C.dma_resv_fini(&obj)
	}
}

fn allocator_tests() {
	unsafe {
		before := C.rcuh_load32(&page_calls)
		for n in [usize(0), 1, 16, 17, 64, 128, usize(-1)]! {
			check(C.kmalloc_size_roundup(n) == n, @LINE)
		}
		check(C.rcuh_load32(&page_calls) == before, @LINE)
		base := &u8(C.vkr_kmalloc(128, 3264))
		check(base != nil, @LINE)
		check(usize(base) % 128 == 0 && usize(C.krealloc_array(nil, 0, 8, 3264)) == 16 && usize(C.krealloc_array(nil, 7, 0, 3264)) == 16, @LINE)
		for i := 0; i < 128; i++ { base[i] = u8(i) }
		calls := C.rcuh_load32(&page_calls)
		check(C.krealloc_array(base, usize(-1), 2, 3264) == nil && C.rcuh_load32(&page_calls) == calls && C.vkr_page_allocation_size(base) == 128, @LINE)
		C.rcuh_store32(&page_fail, 1)
		check(C.krealloc_array(base, 256, 1, 3264) == nil && C.vkr_page_allocation_size(base) == 128, @LINE)
		C.rcuh_store32(&page_fail, 0)
		grown := &u8(C.krealloc_array(base, 256, 1, 3264))
		check(grown != nil && !same(base, grown) && C.vkr_page_allocation_size(grown) == 256, @LINE)
		for i := 0; i < 128; i++ { check(grown[i] == u8(i), @LINE) }
		shrunk := &u8(C.krealloc_array(grown, 64, 1, 3264))
		check(shrunk != nil && !same(shrunk, grown) && C.vkr_page_allocation_size(shrunk) == 64, @LINE)
		check(usize(grown) % 256 == 0 && usize(shrunk) % 64 == 0, @LINE)
		for i := 0; i < 64; i++ { check(shrunk[i] == u8(i), @LINE) }
		check(usize(C.krealloc_array(shrunk, 0, 8, 3264)) == 16, @LINE)
		fresh := C.krealloc_array(voidptr(16), 3, 8, 3264)
		check(fresh != nil && C.vkr_page_allocation_size(fresh) == 24, @LINE)
		C.kfree(fresh)
	}
}

fn usage_and_growth_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		mut nodes := [4]&FenceNode{}
		for i := u32(0); i < 4; i++ {
			nodes[i] = new_fence(100 + i, 1)
			add(&obj, nodes[i], i)
		}
		check(C.rsh_count(&obj) == 4 && C.rsh_capacity(&obj) == 4 && C.vkr_page_allocation_size(C.rsh_list(&obj)) == 56, @LINE)
		for usage := u32(0); usage < 4; usage++ {
			mut cursor := C.dma_resv_iter{}
			C.rsh_begin(&cursor, &obj, usage)
			mut fence := C.dma_resv_iter_first(&cursor)
			mut i := u32(0)
			for fence != nil {
				check(i <= usage && same(fence, &nodes[i].fence) && C.rsh_usage(&cursor) == i && C.dfh_refcount(fence) == 2 && C.rsh_cursor_fence(&cursor) == nil, @LINE)
				check(C.rsh_restarted(&cursor) == (i == 0), @LINE)
				i++
				fence = C.dma_resv_iter_next(&cursor)
			}
			check(i == usage + 1, @LINE)
			C.rsh_end(&cursor)
		}
		C.dma_fence_signal(&nodes[1].fence)
		mut signaled_cursor := C.dma_resv_iter{}
		C.rsh_begin(&signaled_cursor, &obj, 3)
		check(same(C.dma_resv_iter_first(&signaled_cursor), &nodes[0].fence) && same(C.dma_resv_iter_next(&signaled_cursor), &nodes[1].fence) && C.dfh_refcount(&nodes[1].fence) == 2, @LINE)
		C.rsh_end(&signaled_cursor)
		calls := C.rcuh_load32(&page_calls)
		old := C.rsh_list(&obj)
		check(C.dma_resv_reserve_fences(&obj, 0) == 0 && C.rsh_count(&obj) == 4 && C.rcuh_load32(&page_calls) == calls, @LINE)
		C.rcuh_store32(&page_fail, 1)
		check(C.dma_resv_reserve_fences(&obj, 1) == -12 && same(C.rsh_list(&obj), old) && C.dfh_refcount(&nodes[1].fence) == 2, @LINE)
		C.rcuh_store32(&page_fail, 0)
		check(C.dma_resv_reserve_fences(&obj, u32(-1)) == -12 && same(C.rsh_list(&obj), old), @LINE)
		check(C.dma_resv_reserve_fences(&obj, 1) == 0 && C.rsh_count(&obj) == 3 && C.rsh_capacity(&obj) == 8 && C.dfh_refcount(&nodes[1].fence) == 1, @LINE)
		for i := u32(0); i < 3; i++ {
			idx := if i == 0 { u32(0) } else { i + 1 }
			check(C.rsh_tag(&obj, i) == usize(&nodes[idx].fence) | usize(idx), @LINE)
		}
		C.dma_resv_unlock(&obj)
		for usage := u32(0); usage < 4; usage++ {
			mut cursor := C.dma_resv_iter{}
			C.rsh_begin(&cursor, &obj, usage)
			mut f := C.dma_resv_iter_first_unlocked(&cursor)
			mut count := u32(0)
			for f != nil {
				check(C.dfh_refcount(f) == 3 && C.rsh_usage(&cursor) <= usage, @LINE)
				count++
				f = C.dma_resv_iter_next_unlocked(&cursor)
			}
			check(count == if usage < 2 { 1 } else { usage }, @LINE)
			C.rsh_end(&cursor)
		}
		C.dma_resv_fini(&obj)
		for i := 0; i < 4; i++ { C.dma_fence_put(&nodes[i].fence) }
		C.rcu_barrier()
	}
}

fn replacement_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		a := new_fence(200, 10)
		b := new_fence(200, 11)
		c := new_fence(200, 9)
		replacement := new_fence(201, 1)
		add(&obj, a, 3)
		add(&obj, b, 2)
		check(C.rsh_count(&obj) == 1 && C.dfh_refcount(&a.fence) == 1 && C.rsh_tag(&obj, 0) == usize(&b.fence) | 2, @LINE)
		add(&obj, c, 1)
		add(&obj, b, 3)
		check(C.rsh_count(&obj) == 3 && C.dfh_refcount(&b.fence) == 3, @LINE)
		C.dma_resv_replace_fences(&obj, 200, &replacement.fence, 1)
		check(C.dfh_refcount(&b.fence) == 1 && C.dfh_refcount(&c.fence) == 1 && C.dfh_refcount(&replacement.fence) == 4, @LINE)
		for i := u32(0); i < 3; i++ {
			check(C.rsh_tag(&obj, i) == usize(&replacement.fence) | 1, @LINE)
		}
		C.dma_fence_signal(&replacement.fence)
		add(&obj, a, 0)
		check(C.rsh_count(&obj) == 3 && C.rsh_tag(&obj, 0) == usize(&a.fence) && C.dfh_refcount(&a.fence) == 2 && C.dfh_refcount(&replacement.fence) == 3, @LINE)
		C.dma_resv_unlock(&obj)
		C.dma_resv_fini(&obj)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&b.fence)
		C.dma_fence_put(&c.fence)
		C.dma_fence_put(&replacement.fence)
		C.rcu_barrier()
	}
}

fn collection_tests() {
	unsafe {
		mut src := C.dma_resv{}
		mut dst := C.dma_resv{}
		mut empty := C.dma_resv{}
		C.dma_resv_init(&src)
		C.dma_resv_init(&dst)
		C.dma_resv_init(&empty)
		a := new_fence(300, 1)
		b := new_fence(301, 1)
		check(C.dma_resv_lock(&src, nil) == 0, @LINE)
		add(&src, a, 1)
		add(&src, b, 3)
		C.dma_resv_unlock(&src)
		check(C.dma_resv_lock(&dst, nil) == 0 && C.dma_resv_copy_fences(&dst, &src) == 0, @LINE)
		check(C.rsh_count(&dst) == 2 && C.dfh_refcount(&a.fence) == 3 && C.dma_resv_copy_fences(&dst, &dst) == 0, @LINE)
		old := C.rsh_list(&dst)
		C.rcuh_store32(&page_fail, 1)
		check(C.dma_resv_copy_fences(&dst, &src) == -12 && same(C.rsh_list(&dst), old) && C.dfh_refcount(&a.fence) == 3, @LINE)
		C.rcuh_store32(&page_fail, 0)
		C.dma_resv_unlock(&dst)
		mut count := u32(999)
		mut vector := &&C.dma_fence(nil)
		check(C.dma_resv_get_fences(&src, 1, &count, &vector) == 0 && count == 1 && same(vector[0], &a.fence) && C.dfh_refcount(&a.fence) == 4, @LINE)
		free_vector(vector, count)
		C.rcuh_store32(&page_fail, 1)
		check(C.dma_resv_get_fences(&src, 3, &count, &vector) == -12 && count == 0 && vector == nil, @LINE)
		C.rcuh_store32(&page_fail, 0)
		mut singleton := &C.dma_fence(nil)
		check(C.dma_resv_get_singleton(&empty, 3, &singleton) == 0 && singleton == nil, @LINE)
		check(C.dma_resv_get_singleton(&src, 1, &singleton) == 0 && same(singleton, &a.fence) && C.dfh_refcount(singleton) == 4, @LINE)
		C.dma_fence_put(singleton)
		check(C.dma_resv_get_singleton(&src, 3, &singleton) == 0 && C.rsh_array_ops(singleton) && C.rsh_array_count(singleton) == 2, @LINE)
		C.dma_fence_enable_sw_signaling(singleton)
		C.dma_fence_signal(&a.fence)
		check(!C.dma_fence_is_signaled(singleton), @LINE)
		C.dma_fence_signal(&b.fence)
		drain_all()
		check(C.dma_fence_is_signaled(singleton), @LINE)
		C.dma_fence_put(singleton)
		check(C.dma_resv_lock(&dst, nil) == 0 && C.dma_resv_copy_fences(&dst, &empty) == 0 && C.rsh_list(&dst) == nil, @LINE)
		C.dma_resv_unlock(&dst)
		C.dma_resv_fini(&dst)
		C.dma_resv_fini(&src)
		C.dma_resv_fini(&empty)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&b.fence)
		C.rcu_barrier()
	}
}

fn iterator_restart_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		mut empty := C.dma_resv{}
		C.dma_resv_init(&obj)
		C.dma_resv_init(&empty)
		a := new_fence(400, 1)
		b := new_fence(401, 1)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		add(&obj, a, 0)
		add(&obj, b, 1)
		C.dma_resv_unlock(&obj)
		mut cursor := C.dma_resv_iter{}
		C.rsh_begin(&cursor, &obj, 3)
		check(same(C.dma_resv_iter_first_unlocked(&cursor), &a.fence) && C.dfh_refcount(&a.fence) == 3, @LINE)
		check(C.dma_resv_lock(&obj, nil) == 0 && C.dma_resv_reserve_fences(&obj, 4) == 0, @LINE)
		C.dma_resv_unlock(&obj)
		check(same(C.dma_resv_iter_next_unlocked(&cursor), &a.fence) && C.rsh_restarted(&cursor) && C.dfh_refcount(&a.fence) == 3, @LINE)
		check(C.dma_resv_lock(&obj, nil) == 0 && C.dma_resv_copy_fences(&obj, &empty) == 0, @LINE)
		C.dma_resv_unlock(&obj)
		check(C.dma_resv_iter_next_unlocked(&cursor) == nil && C.rsh_cursor_fence(&cursor) == nil && C.rsh_restarted(&cursor) && C.dfh_refcount(&a.fence) == 1, @LINE)
		C.rsh_end(&cursor)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&b.fence)
		C.dma_resv_fini(&obj)
		C.dma_resv_fini(&empty)
		C.rcu_barrier()
	}
}

fn reused_list_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		mut empty := C.dma_resv{}
		C.dma_resv_init(&obj)
		C.dma_resv_init(&empty)
		mut nodes := [5]&FenceNode{}
		for i := 0; i < 5; i++ { nodes[i] = new_fence(600 + u64(i), 1) }
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		for i := 0; i < 4; i++ { add(&obj, nodes[i], 0) }
		C.dma_resv_unlock(&obj)
		mut cursor := C.dma_resv_iter{}
		C.rsh_begin(&cursor, &obj, 3)
		check(same(C.dma_resv_iter_first_unlocked(&cursor), &nodes[0].fence), @LINE)
		previous := C.rsh_list(&obj)
		capture_page = true
		check(C.dma_resv_lock(&obj, nil) == 0 && C.dma_resv_copy_fences(&obj, &empty) == 0, @LINE)
		C.dma_resv_unlock(&obj)
		C.rcu_barrier()
		check(reused_page != nil && !capture_page, @LINE)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		add(&obj, nodes[4], 1)
		C.dma_resv_unlock(&obj)
		check(same(previous, C.rsh_list(&obj)) && C.rsh_count(&obj) == 1 && reused_page == nil, @LINE)
		check(same(C.dma_resv_iter_next_unlocked(&cursor), &nodes[4].fence) && C.rsh_restarted(&cursor) && C.dfh_refcount(&nodes[0].fence) == 1 && C.dfh_refcount(&nodes[4].fence) == 3, @LINE)
		C.rsh_end(&cursor)
		// An ordinary in-place append preserves the original cached count.
		C.rsh_begin(&cursor, &obj, 3)
		check(same(C.dma_resv_iter_first_unlocked(&cursor), &nodes[4].fence), @LINE)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		add(&obj, nodes[0], 2)
		C.dma_resv_unlock(&obj)
		check(C.dma_resv_iter_next_unlocked(&cursor) == nil && !C.rsh_restarted(&cursor), @LINE)
		C.rsh_end(&cursor)
		C.dma_resv_fini(&obj)
		C.dma_resv_fini(&empty)
		for i := 0; i < 5; i++ { C.dma_fence_put(&nodes[i].fence) }
		C.rcu_barrier()
	}
}

fn zero_ref_retry_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		a := new_fence(700, 1)
		b := new_fence(701, 1)
		replacement := new_fence(702, 1)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		add(&obj, a, 0)
		add(&obj, b, 1)
		C.dma_resv_unlock(&obj)
		gate_target = C.rsh_tag_address(&obj, 1)
		gate_get = true
		gate_entered = 0
		gate_release = 0
		mut reader := Actor{ obj: &obj, op: .iter }
		start(&reader)
		await32(&gate_entered, 1)
		// The actual iterator has loaded old b under its real RCU scope, but
		// has not acquired b yet. Retire the last owner on the writer side.
		C.dma_fence_put(&b.fence)
		frees := C.rcuh_load32(&page_frees)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		C.dma_resv_replace_fences(&obj, 701, &replacement.fence, 2)
		C.dma_resv_unlock(&obj)
		attempt := attempts(reader.ctx.cpu)
		await_attempt(reader.ctx.cpu, attempt)
		check(C.rcuh_load32(&page_frees) == frees && C.rcuh_load32(&reader.done) == 0, @LINE)
		C.rcuh_store32(&gate_release, 1)
		join(&reader)
		gate_get = false
		check(same(reader.fence, &a.fence) && C.rsh_restarted(&reader.cursor) && C.dfh_refcount(&a.fence) == 3, @LINE)
		C.rsh_end(&reader.cursor)
		C.rcu_barrier()
		check(C.rcuh_load32(&page_frees) == frees + 1, @LINE)
		C.dma_resv_fini(&obj)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&replacement.fence)
		C.rcu_barrier()
	}
}

fn collection_restart_tests() {
	unsafe {
		for kind := u32(0); kind < 4; kind++ {
			mut src := C.dma_resv{}
			mut dst := C.dma_resv{}
			C.dma_resv_init(&src)
			C.dma_resv_init(&dst)
			a := new_fence(800, 1)
			b := new_fence(801, 1)
			original := new_fence(802, 1)
			// A producer-defined signaled hook provides a host debugging
			// pause while the genuine RCU/preemption scope remains live.
			mut callback_ops := resv_ops
			callback_ops.signaled = signaled
			C.vdf_init(&b.fence, &callback_ops, &b.lock, 801, 1)
			b.peek_gate = true
			check(C.dma_resv_lock(&src, nil) == 0, @LINE)
			add(&src, a, 0)
			add(&src, b, 1)
			C.dma_resv_unlock(&src)
			check(C.dma_resv_lock(&dst, nil) == 0, @LINE)
			add(&dst, original, 2)
			C.dma_resv_unlock(&dst)
			gate_entered = 0
			gate_release = 0
			mut actor := Actor{ obj: if kind < 2 { &dst } else { &src }, src: &src, op: if kind < 2 {
				ResvOperation.copy
			} else {
				ResvOperation.get
			} }
			start(&actor)
			await32(&gate_entered, 1)
			// One accumulator prefix and b's cursor reference are already
			// owned. Real growth makes iteration restart on its next check.
			check(C.dma_resv_lock(&src, nil) == 0 && C.dma_resv_reserve_fences(&src, 4) == 0, @LINE)
			C.dma_resv_unlock(&src)
			b.peek_gate = false
			gate_alloc_count = 0
			gate_alloc_at = 1
			gate_alloc_fail = kind % 2 == 1
			C.rcuh_store32(&gate_release, 1)
			join(&actor)
			clear_gate()
			if kind % 2 == 1 {
				check(actor.result == -12 && C.dfh_refcount(&a.fence) == 2 && C.dfh_refcount(&b.fence) == 2, @LINE)
				if kind < 2 {
					check(C.rsh_count(&dst) == 1 && C.dfh_refcount(&original.fence) == 2, @LINE)
				} else {
					check(actor.count == 0 && actor.vector == nil, @LINE)
				}
			} else {
				check(actor.result == 0, @LINE)
				if kind < 2 {
					check(C.rsh_count(&dst) == 2 && C.dfh_refcount(&a.fence) == 3 && C.dfh_refcount(&original.fence) == 1, @LINE)
				} else {
					check(actor.count == 2 && C.dfh_refcount(&a.fence) == 3, @LINE)
					free_vector(actor.vector, actor.count)
				}
			}
			C.dma_resv_fini(&src)
			C.dma_resv_fini(&dst)
			C.dma_fence_put(&a.fence)
			C.dma_fence_put(&b.fence)
			C.dma_fence_put(&original.fence)
			C.rcu_barrier()
		}
		// Fail the actual array allocation after successful vector ownership.
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		a := new_fence(810, 1)
		b := new_fence(811, 1)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		add(&obj, a, 0)
		add(&obj, b, 1)
		C.dma_resv_unlock(&obj)
		set_gate(2, true)
		C.rcuh_store32(&gate_release, 1)
		mut fence := &C.dma_fence(nil)
		check(C.dma_resv_get_singleton(&obj, 3, &fence) == -12 && C.dfh_refcount(&a.fence) == 2 && C.dfh_refcount(&b.fence) == 2, @LINE)
		clear_gate()
		C.dma_resv_fini(&obj)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&b.fence)
		C.rcu_barrier()
	}
}

fn empty_collection_prefix_tests() {
	unsafe {
		for copying in [true, false]! {
			mut src := C.dma_resv{}
			mut dst := C.dma_resv{}
			mut empty := C.dma_resv{}
			C.dma_resv_init(&src)
			C.dma_resv_init(&dst)
			C.dma_resv_init(&empty)
			a := new_fence(820, 1)
			b := new_fence(821, 1)
			mut callback_ops := resv_ops
			callback_ops.signaled = signaled
			C.vdf_init(&b.fence, &callback_ops, &b.lock, 821, 1)
			b.peek_gate = true
			check(C.dma_resv_lock(&src, nil) == 0, @LINE)
			add(&src, a, 0)
			add(&src, b, 1)
			C.dma_resv_unlock(&src)
			gate_entered = 0
			gate_release = 0
			mut actor := Actor{ obj: if copying { &dst } else { &src }, src: &src, op: if copying {
				ResvOperation.copy
			} else {
				ResvOperation.get
			} }
			start(&actor)
			await32(&gate_entered, 1)
			check(C.dma_resv_lock(&src, nil) == 0 && C.dma_resv_copy_fences(&src, &empty) == 0, @LINE)
			C.dma_resv_unlock(&src)
			b.peek_gate = false
			C.rcuh_store32(&gate_release, 1)
			join(&actor)
			// A restart returning no next fence preserves the pinned weak
			// aggregate prefix; only the cursor's current owner is discarded.
			check(actor.result == 0 && C.dfh_refcount(&a.fence) == 2 && C.dfh_refcount(&b.fence) == 1, @LINE)
			if copying {
				check(C.rsh_count(&dst) == 1 && C.rsh_tag(&dst, 0) == usize(&a.fence), @LINE)
			} else {
				check(actor.count == 1 && same(actor.vector[0], &a.fence), @LINE)
				free_vector(actor.vector, actor.count)
			}
			C.dma_resv_fini(&src)
			C.dma_resv_fini(&dst)
			C.dma_resv_fini(&empty)
			C.dma_fence_put(&a.fence)
			C.dma_fence_put(&b.fence)
			C.rcu_barrier()
		}
	}
}

fn wait_deadline_tests() {
	unsafe {
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		check(C.dma_resv_wait_timeout(&obj, 3, false, 0) == 1 && C.dma_resv_test_signaled(&obj, 3), @LINE)
		check(C.dma_resv_wait_timeout(&obj, 3, false, usize(-1)) == -1 && C.dma_resv_wait_timeout(&obj, 3, false, usize(0x7fffffffffffffff)) == isize(0x7fffffffffffffff), @LINE)
		a := new_fence(500, 1)
		b := new_fence(501, 1)
		check(C.dma_resv_lock(&obj, nil) == 0, @LINE)
		add(&obj, a, 1)
		add(&obj, b, 3)
		C.dma_resv_unlock(&obj)
		check(!C.dma_resv_test_signaled(&obj, 1) && C.dfh_refcount(&a.fence) == 2 && C.dma_resv_test_signaled(&obj, 0), @LINE)
		C.dma_resv_set_deadline(&obj, 1, 12345)
		check(a.deadlines == 1 && a.deadline == 12345 && b.deadlines == 0, @LINE)
		check(C.dma_resv_wait_timeout(&obj, 3, false, 0) == 0, @LINE)
		mut timed := Actor{ obj: &obj, op: .wait, timeout: 5 }
		start(&timed)
		for C.vinix_linuxkpi_time_waiters() == 0 { C.sched_yield() }
		advance(2)
		C.dma_fence_signal(&a.fence)
		for b.enables == 0 || C.vinix_linuxkpi_time_waiters() == 0 { C.sched_yield() }
		advance(3)
		join(&timed)
		check(timed.result == 0 && C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		mut interrupted := Actor{ obj: &obj, op: .wait, timeout: 20, intr: true }
		start(&interrupted)
		for C.vinix_linuxkpi_time_waiters() == 0 { C.sched_yield() }
		C.rcuh_store32(&interrupted.ctx.pending, 1)
		C.wake_up_process(&interrupted.ctx.task)
		join(&interrupted)
		check(interrupted.result == -512 && C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		mut infinite := Actor{ obj: &obj, op: .wait, timeout: usize(0x7fffffffffffffff) }
		start(&infinite)
		for C.rcuh_load32(&infinite.ctx.parks) == 0 { C.sched_yield() }
		C.dma_fence_signal(&b.fence)
		join(&infinite)
		check(infinite.result == isize(0x7fffffffffffffff) && C.vinix_linuxkpi_time_waiters() == 0 && C.dma_resv_wait_timeout(&obj, 3, false, 0) == 1 && C.dma_resv_test_signaled(&obj, 3), @LINE)
		C.dma_resv_fini(&obj)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&b.fence)
		C.rcu_barrier()
		mut custom := C.dma_resv{}
		C.dma_resv_init(&custom)
		c := new_fence(510, 1)
		d := new_fence(511, 1)
		C.vdf_init(&c.fence, &resv_wait_ops, &c.lock, 510, 1)
		C.vdf_init(&d.fence, &resv_wait_ops, &d.lock, 511, 1)
		c.custom_result = 7
		d.custom_result = -5
		check(C.dma_resv_lock(&custom, nil) == 0, @LINE)
		add(&custom, c, 0)
		add(&custom, d, 1)
		C.dma_resv_unlock(&custom)
		check(C.dma_resv_wait_timeout(&custom, 3, false, 20) == -5 && c.custom_timeout == 20 && d.custom_timeout == 7 && c.custom_calls == 1 && d.custom_calls == 1, @LINE)
		check(C.dma_resv_wait_timeout(&custom, 3, false, usize(0x7fffffffffffffff)) == -5 && c.custom_timeout == isize(0x7fffffffffffffff) && d.custom_timeout == 7, @LINE)
		check(C.dfh_refcount(&c.fence) == 2 && C.dfh_refcount(&d.fence) == 2, @LINE)
		C.dma_resv_fini(&custom)
		C.dma_fence_put(&c.fence)
		C.dma_fence_put(&d.fence)
		C.rcu_barrier()
	}
}

fn fatal(mode i32) {
	unsafe {
		mut obj := C.dma_resv{}
		C.dma_resv_init(&obj)
		fence := new_fence(900, 1)
		if mode != 11 { check(C.dma_resv_lock(&obj, nil) == 0, @LINE) }
		if mode != 11 { check(C.dma_resv_reserve_fences(&obj, 1) == 0, @LINE) }
		if mode == 15 {
			for i := u32(0); i < 4; i++ {
				entry := new_fence(910 + i, 1)
				C.dma_resv_add_fence(&obj, &entry.fence, 0)
			}
			check(C.rsh_count(&obj) == 4 && C.rsh_capacity(&obj) == 4, @LINE)
		}
		fatal_obj = &obj
		fatal_fence = &fence.fence
		C.memcpy(&fatal_obj_bytes[0], fatal_obj, 48)
		C.memcpy(&fatal_fence_bytes[0], fatal_fence, 64)
		fatal_list = C.rsh_list(&obj)
		if fatal_list != nil { C.memcpy(&fatal_list_bytes[0], fatal_list, 56) }
		fatal_calls = C.rcuh_load32(&page_calls)
		fatal_watched = true
		if mode == 10 {
			C.dma_resv_add_fence(&obj, &fence.fence, 4)
		} else if mode == 11 {
			C.dma_resv_reserve_fences(&obj, 1)
		} else if mode == 12 {
			C.dma_resv_add_fence(&obj, nil, 1)
		} else if mode == 13 {
			C.dma_resv_replace_fences(&obj, 900, &fence.fence, 4)
		} else if mode == 14 {
			C.dma_resv_get_fences(&obj, 4, nil, nil)
		} else if mode == 15 {
			C.dma_resv_add_fence(&obj, &fence.fence, 1)
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
		resv_ops = C.dma_fence_ops{ get_driver_name: driver_name, get_timeline_name: driver_name, enable_signaling: enable, set_deadline: deadline }
		resv_wait_ops = C.dma_fence_ops{ get_driver_name: driver_name, get_timeline_name: driver_name, enable_signaling: enable, @wait: custom_wait, set_deadline: deadline }
		check(C.vkm_cpu_masks_bootstrap(4) == 0 && C.vkr_rcu_bootstrap(4) == 0 && C.vkiw_bootstrap(4) == 0, @LINE)
		mode := if argc > 1 { C.atoi(argv[1]) } else { 0 }
		if mode != 0 { fatal(mode) }
		locking_tests()
		wd_backoff_tests()
		allocator_tests()
		usage_and_growth_tests()
		replacement_tests()
		collection_tests()
		iterator_restart_tests()
		reused_list_tests()
		zero_ref_retry_tests()
		collection_restart_tests()
		empty_collection_prefix_tests()
		wait_deadline_tests()
		C.rcu_barrier()
		C.vkr_rcu_shutdown_for_test()
		check(C.rcuh_load32(&page_live) == 0 && C.vinix_linuxkpi_time_waiters() == 0 && C.rcuh_load32(&ctx.refs) == 1, @LINE)
		check(C.pthread_setspecific(context_key, nil) == 0, @LINE)
		context_destructor(ctx)
		check(C.rcuh_load32(&context_live) == 0 && C.pthread_key_delete(context_key) == 0, @LINE)
		C.printf(c'PASS: actual reservation/WD/fence/array/IRQ/task/time/page/RCU, %u assertions\n', C.rcuh_load32(&assertions))
		return 0
	}
}
