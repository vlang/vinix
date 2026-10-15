// SPDX-License-Identifier: MIT
@[translated]
module swfencefixture

#include "contract.h"

struct C.i915_sw_fence {}

struct C.i915_sw_dma_fence_cb {}

struct C.wait_queue_entry {}

struct C.dma_resv {}

struct C.dma_fence {}

struct C.timer_list {}

@[typedef]
struct C.swh_notify {}

@[typedef]
struct C.spinlock_t {
mut:
	locked u32
}

@[typedef]
struct C.vdf_const_char_p {}

struct C.dma_fence_ops {
mut:
	get_driver_name   fn (&C.dma_fence) C.vdf_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vdf_const_char_p
	enable_signaling  fn (&C.dma_fence) bool
}

fn C.__i915_sw_fence_init(&C.i915_sw_fence, fn (&C.i915_sw_fence, C.swh_notify) i32, voidptr, voidptr)
fn C.i915_sw_fence_reinit(&C.i915_sw_fence)
fn C.i915_sw_fence_await(&C.i915_sw_fence) bool
fn C.i915_sw_fence_complete(&C.i915_sw_fence)
fn C.i915_sw_fence_commit(&C.i915_sw_fence)
fn C.i915_sw_fence_await_sw_fence(&C.i915_sw_fence, &C.i915_sw_fence, &C.wait_queue_entry) i32
fn C.i915_sw_fence_await_sw_fence_gfp(&C.i915_sw_fence, &C.i915_sw_fence, u32) i32
fn C.i915_sw_fence_await_dma_fence(&C.i915_sw_fence, &C.dma_fence, usize, u32) i32
fn C.__i915_sw_fence_await_dma_fence(&C.i915_sw_fence, &C.dma_fence, &C.i915_sw_dma_fence_cb) i32
fn C.i915_sw_fence_await_reservation(&C.i915_sw_fence, &C.dma_resv, bool, usize, u32) i32
fn C.i915_sw_fence_signaled(&C.i915_sw_fence) bool
fn C.i915_sw_fence_done(&C.i915_sw_fence) bool
fn C.i915_sw_fence_wait(&C.i915_sw_fence)
fn C.swh_pending(&C.i915_sw_fence) i32
fn C.swh_error(&C.i915_sw_fence) i32
fn C.swh_set_error(&C.i915_sw_fence, i32)
fn C.swh_wait_empty(&C.i915_sw_fence) bool
fn C.swh_jiffies() usize
fn C.swh_expected_notice() &char
fn C.swh_timed_callback(&C.dma_fence) voidptr
fn C.swh_timed_work(voidptr) voidptr
fn C.vkiw_running_count(voidptr) u32
fn C.vdf_init(voidptr, voidptr, voidptr, u64, u64)
fn C.dma_fence_signal(&C.dma_fence) i32
fn C.dma_fence_signal_locked(&C.dma_fence) i32
fn C.dma_fence_set_error(&C.dma_fence, i32)
fn C.dma_fence_put(&C.dma_fence)
fn C.dfh_refcount(&C.dma_fence) u32
fn C.vkr_kmalloc(usize, u32) voidptr
fn C.kfree(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.vinix_linuxkpi_time_tick(u64)
fn C.vinix_linuxkpi_time_waiters() usize
fn C.vinix_linuxkpi_timer_tick()
fn C.vinix_linuxkpi_timer_dispatch() u32
fn C.vinix_linuxkpi_timer_active() usize
fn C.vkiw_bootstrap(u32) i32
fn C.vkiw_drain(u32)
fn C.dma_resv_init(&C.dma_resv)
fn C.dma_resv_fini(&C.dma_resv)
fn C.dma_resv_lock(&C.dma_resv, voidptr) i32
fn C.dma_resv_unlock(&C.dma_resv)
fn C.dma_resv_reserve_fences(&C.dma_resv, u32) i32
fn C.dma_resv_add_fence(&C.dma_resv, &C.dma_fence, u32)
fn C.dma_resv_replace_fences(&C.dma_resv, u64, &C.dma_fence, u32)
fn C.rsh_tag_address(&C.dma_resv, u32) &voidptr
fn C.rsh_atomic_load_ptr(&voidptr) voidptr

struct SwLedger {
mut:
	complete u32
	freed    u32
	error    i32
	decline  bool
	gate     bool
	entered  u32
	release  u32 = 1
}

struct SwNode {
mut:
	fence     C.i915_sw_fence
	ledger    &SwLedger = unsafe { nil }
	self_free bool
}

struct FenceNode {
mut:
	fence                C.dma_fence
	lock                 C.spinlock_t
	enables              u32
	fail_next            bool
	signal_during_enable bool
}

enum Action {
	wait
	dma
	timer
	irq
	reader
	sw
	resv
}

struct Actor {
mut:
	thread       C.pthread_t
	node         &SwNode     = unsafe { nil }
	signaler     &SwNode     = unsafe { nil }
	resv         &C.dma_resv = unsafe { nil }
	dma          &FenceNode  = unsafe { nil }
	ctx          &Context    = unsafe { nil }
	action       Action
	entered      u32
	done         u32
	result       i32
	timeout      usize
	gfp          u32 = 3264
	release      u32
	exit_entered u32
	exit_release u32 = 1
}

@[cinit]
__global (
	dma_clock_ns           u64
	dma_timer_observations u32
	dma_warnings           u32
	dma_ops                C.dma_fence_ops
	capture_page           bool
	reused_page            voidptr
	notices                u32
	notice_format          voidptr
	notice_driver          voidptr
	notice_timeline        voidptr
	notice_seqno           u64
	notice_hint            voidptr
	load_target            voidptr
	load_context           voidptr
	load_entered           u32
	load_release           u32 = 1
)

fn same(a voidptr, b voidptr) bool { return usize(a) == usize(b) }

fn page_should_fail() bool { return false }

@[export:'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason C.rcuh_const_charp, line i32) {
	unsafe {
		C.fprintf(C.stderr, c'SW host invariant: %s:%d\n', reason, line)
		C.abort()
	}
}

@[export:'vinix_linuxkpi_irqwork_send_ipi']
pub fn send_ipi(cpu u32) { check(cpu < 4, @LINE) }

@[export:'swh_printk']
pub fn printk(format C.rcuh_const_charp, driver C.rcuh_const_charp, timeline C.rcuh_const_charp, seqno u64, hint voidptr) i32 {
	unsafe {
		notice_format = voidptr(format)
		notice_driver = voidptr(driver)
		notice_timeline = voidptr(timeline)
		notice_seqno = seqno
		notice_hint = hint
		C.rcuh_add32(&notices, 1)
	}
	return 0
}

@[export:'swh_resv_load']
pub fn resv_load(address &voidptr) voidptr {
	unsafe {
		observed := C.rsh_atomic_load_ptr(address)
		if same(address, load_target) && same(context(), load_context) {
			C.rcuh_store32(&load_entered, 1)
			for C.rcuh_load32(&load_release) == 0 { C.sched_yield() }
		}
		return observed
	}
}

fn notify(fence &C.i915_sw_fence, state C.swh_notify) i32 {
	unsafe {
		n := &SwNode(fence)
		ledger := n.ledger
		mut kind := u32(0)
		C.memcpy(&kind, &state, 4)
		if kind == 0 {
			check(C.i915_sw_fence_signaled(fence) && !C.i915_sw_fence_done(fence) && C.swh_pending(fence) == 0, @LINE)
			ledger.error = C.swh_error(fence)
			C.rcuh_add32(&ledger.complete, 1)
			if ledger.gate {
				C.rcuh_store32(&ledger.entered, 1)
				for C.rcuh_load32(&ledger.release) == 0 { C.sched_yield() }
			}
			if ledger.decline { return 1 }
		} else {
			check(kind == 1 && C.i915_sw_fence_done(fence) && C.swh_wait_empty(fence), @LINE)
			C.rcuh_add32(&ledger.freed, 1)
			if n.self_free { C.kfree(n) }
		}
		return 0
	}
}

fn init_sw(node &SwNode, ledger &SwLedger) {
	unsafe {
		node.ledger = ledger
		C.__i915_sw_fence_init(&node.fence, notify, nil, nil)
		check(C.swh_pending(&node.fence) == 1, @LINE)
	}
}

fn driver_name(fence &C.dma_fence) C.vdf_const_char_p {
	mut value := C.vdf_const_char_p{}
	text := unsafe { &char(c'host-sw') }
	unsafe { C.memcpy(&value, &text, sizeof(voidptr)) }
	return value
}

fn enable(fence &C.dma_fence) bool {
	unsafe {
		n := &FenceNode(fence)
		C.rcuh_add32(&n.enables, 1)
		if n.fail_next { C.rcuh_store32(&page_fail, 1) }
		if n.signal_during_enable {
			C.dma_fence_set_error(fence, -19)
			check(C.dma_fence_signal_locked(fence) == 0, @LINE)
			return false
		}
	}
	return true
}

fn new_dma(id u64) &FenceNode {
	unsafe {
		n := &FenceNode(C.vkr_kmalloc(sizeof(FenceNode), 3264 | 0x100))
		check(n != nil, @LINE)
		C.vdf_init(n, &dma_ops, &n.lock, id, 1)
		return n
	}
}

fn drain_all() {
	unsafe {
		for cpu := u32(0); cpu < 4; cpu++ {
			route(cpu)
			flags := irq_save()
			lock_context()
			context().depth++
			cpu_depth[cpu]++
			unlock_context()
			C.vkiw_drain(cpu)
			lock_context()
			context().depth--
			cpu_depth[cpu]--
			unlock_context()
			irq_restore(flags)
		}
		route(0)
	}
}

fn actor_main(argument voidptr) voidptr {
	unsafe {
		a := &Actor(argument)
		a.ctx = context()
		native_task_get(a.ctx)
		if a.action == .timer { route(1) }
		if a.action == .reader {
			route(2)
			C.rcuh_read_lock()
		}
		if a.action == .irq { route(0) }
		if a.action == .resv {
			route(1)
			load_context = a.ctx
		}
		C.rcuh_store32(&a.entered, 1)
		match a.action {
			.wait { C.i915_sw_fence_wait(&a.node.fence) }
			.dma {
				a.result = C.i915_sw_fence_await_dma_fence(&a.node.fence, &a.dma.fence, a.timeout, a.gfp)
			}
			.timer { a.result = i32(C.vinix_linuxkpi_timer_dispatch()) }
			.irq {
				saved := irq_save()
				lock_context()
				context().depth++
				cpu_depth[0]++
				unlock_context()
				C.vkiw_drain(0)
				C.rcuh_store32(&a.exit_entered, 1)
				for C.rcuh_load32(&a.exit_release) == 0 { C.sched_yield() }
				lock_context()
				context().depth--
				cpu_depth[0]--
				unlock_context()
				irq_restore(saved)
			}
			.reader {
				for C.rcuh_load32(&a.release) == 0 { C.sched_yield() }
				C.rcuh_read_unlock()
			}
			.sw {
				a.result = C.i915_sw_fence_await_sw_fence_gfp(&a.node.fence, &a.signaler.fence, a.gfp)
			}
			.resv { a.result = C.i915_sw_fence_await_reservation(&a.node.fence, a.resv, true, 0, 3264) }
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
		check(C.pthread_join(a.thread, nil) == 0 && a.done == 1, @LINE)
		native_task_put(a.ctx)
	}
}

fn basic_tests() {
	unsafe {
		mut ledger := SwLedger{}
		mut node := SwNode{}
		init_sw(&node, &ledger)
		check(C.i915_sw_fence_await(&node.fence) && C.swh_pending(&node.fence) == 2, @LINE)
		C.i915_sw_fence_commit(&node.fence)
		check(!C.i915_sw_fence_done(&node.fence) && ledger.complete == 0, @LINE)
		mut waiter := Actor{ node: &node }
		start(&waiter)
		for C.rcuh_load32(&waiter.ctx.parks) == 0 { C.sched_yield() }
		C.swh_set_error(&node.fence, -5)
		C.swh_set_error(&node.fence, -11)
		C.i915_sw_fence_complete(&node.fence)
		join(&waiter)
		check(ledger.complete == 1 && ledger.freed == 1 && ledger.error == -5 && !C.i915_sw_fence_await(&node.fence), @LINE)
		C.i915_sw_fence_reinit(&node.fence)
		C.i915_sw_fence_commit(&node.fence)
		check(ledger.complete == 2 && ledger.freed == 2 && C.swh_error(&node.fence) == 0, @LINE)
		owned := &SwNode(C.vkr_kmalloc(sizeof(SwNode), 3264 | 0x100))
		init_sw(owned, &ledger)
		owned.self_free = true
		C.i915_sw_fence_commit(&owned.fence)
		check(ledger.complete == 3 && ledger.freed == 3, @LINE)
		// A declined COMPLETE is an isolated terminal state: there is no
		// public recovery protocol and no waiter or owned allocation here.
		mut declined := SwLedger{ decline: true }
		mut terminal := SwNode{}
		init_sw(&terminal, &declined)
		C.i915_sw_fence_commit(&terminal.fence)
		check(declined.complete == 1 && declined.freed == 0 && C.swh_pending(&terminal.fence) == 0 && C.i915_sw_fence_signaled(&terminal.fence) && !C.i915_sw_fence_done(&terminal.fence) && !C.i915_sw_fence_await(&terminal.fence), @LINE)
	}
}

fn immediate_dma_tests() {
	unsafe {
		for mode := 0; mode < 3; mode++ {
			baseline := C.rcuh_load32(&page_live)
			mut ledger := SwLedger{}
			mut node := SwNode{}
			init_sw(&node, &ledger)
			dma := new_dma(12)
			C.dma_fence_set_error(&dma.fence, -19)
			check(C.dma_fence_signal(&dma.fence) == 0, @LINE)
			mut supplied := C.i915_sw_dma_fence_cb{}
			calls := C.rcuh_load32(&page_calls)
			ret := if mode == 0 {
				C.__i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, &supplied)
			} else {
				C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, if mode == 2 {
					usize(5)
				} else {
					usize(0)
				}, 3264)
			}
			check(ret == 0 && C.rcuh_load32(&page_calls) == calls && C.swh_pending(&node.fence) == 1 && C.swh_error(&node.fence) == -19 && C.dfh_refcount(&dma.fence) == 1 && C.vinix_linuxkpi_timer_active() == 0, @LINE)
			C.i915_sw_fence_commit(&node.fence)
			check(ledger.complete == 1 && ledger.freed == 1, @LINE)
			C.dma_fence_put(&dma.fence)
			C.rcu_barrier()
			check(C.rcuh_load32(&page_live) == baseline, @LINE)
		}
		for mode := 0; mode < 3; mode++ {
			baseline := C.rcuh_load32(&page_live)
			mut ledger := SwLedger{}
			mut node := SwNode{}
			init_sw(&node, &ledger)
			dma := new_dma(13)
			dma.signal_during_enable = true
			mut supplied := C.i915_sw_dma_fence_cb{}
			ret := if mode == 0 {
				C.__i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, &supplied)
			} else {
				C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, if mode == 2 {
					usize(5)
				} else {
					usize(0)
				}, 3264)
			}
			check(ret == 0 && dma.enables == 1 && C.swh_pending(&node.fence) == 1 && C.swh_error(&node.fence) == -19 && ledger.complete == 0, @LINE)
			C.i915_sw_fence_commit(&node.fence)
			check(ledger.complete == 1 && ledger.freed == 1, @LINE)
			if mode == 2 {
				check(C.vinix_linuxkpi_timer_active() == 1 && C.dfh_refcount(&dma.fence) == 2, @LINE)
				drain_all()
				C.rcu_barrier()
			}
			check(C.vinix_linuxkpi_timer_active() == 0 && C.dfh_refcount(&dma.fence) == 1, @LINE)
			C.dma_fence_put(&dma.fence)
			C.rcu_barrier()
			check(C.rcuh_load32(&page_live) == baseline, @LINE)
		}
	}
}

fn graph_tests() {
	unsafe {
		baseline := C.rcuh_load32(&page_live)
		mut ledger := SwLedger{}
		mut a := SwNode{}
		mut b := SwNode{}
		mut c := SwNode{}
		init_sw(&a, &ledger)
		init_sw(&b, &ledger)
		init_sw(&c, &ledger)
		mut supplied := C.wait_queue_entry{}
		check(C.i915_sw_fence_await_sw_fence(&a.fence, &b.fence, &supplied) == 1 && C.i915_sw_fence_await_sw_fence_gfp(&a.fence, &c.fence, 3264) == 1, @LINE)
		C.i915_sw_fence_commit(&a.fence)
		C.swh_set_error(&b.fence, -7)
		C.i915_sw_fence_commit(&b.fence)
		check(!C.i915_sw_fence_done(&a.fence), @LINE)
		C.i915_sw_fence_commit(&c.fence)
		check(C.i915_sw_fence_done(&a.fence) && C.swh_error(&a.fence) == -7 && ledger.complete == 3 && ledger.freed == 3, @LINE)
		chain := &SwNode(C.vkr_kmalloc(512 * sizeof(SwNode), 3264 | 0x100))
		for i := 0; i < 512; i++ { init_sw(&chain[i], &ledger) }
		for i := 0; i < 511; i++ {
			check(C.i915_sw_fence_await_sw_fence_gfp(&chain[i].fence, &chain[i + 1].fence, 3264) == 1, @LINE)
			C.i915_sw_fence_commit(&chain[i].fence)
		}
		C.i915_sw_fence_commit(&chain[511].fence)
		check(ledger.complete == 515 && ledger.freed == 515, @LINE)
		for i := 0; i < 512; i++ { check(C.i915_sw_fence_done(&chain[i].fence), @LINE) }
		C.kfree(chain)
		check(C.rcuh_load32(&page_live) == baseline, @LINE)
	}
}

fn dma_tests() {
	unsafe {
		for caller_owned in [false, true]! {
			mut ledger := SwLedger{}
			mut node := SwNode{}
			init_sw(&node, &ledger)
			dma := new_dma(10)
			mut cb := C.i915_sw_dma_fence_cb{}
			ret := if caller_owned {
				C.__i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, &cb)
			} else {
				C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, 0, 3264)
			}
			check(ret == 1 && C.swh_pending(&node.fence) == 2, @LINE)
			C.i915_sw_fence_commit(&node.fence)
			C.dma_fence_set_error(&dma.fence, -13)
			check(C.dma_fence_signal(&dma.fence) == 0 && ledger.complete == 1 && ledger.error == -13, @LINE)
			C.dma_fence_put(&dma.fence)
			C.rcu_barrier()
		}
		mut ledger := SwLedger{}
		mut node := SwNode{}
		init_sw(&node, &ledger)
		dma := new_dma(11)
		calls := C.rcuh_load32(&page_calls)
		C.rcuh_store32(&page_fail, 1)
		check(C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, 5, 0) == -12 && C.swh_pending(&node.fence) == 1 && C.rcuh_load32(&page_calls) == calls + 1, @LINE)
		mut actor := Actor{ node: &node, dma: dma, action: .dma, timeout: 7 }
		start(&actor)
		for C.rcuh_load32(&actor.ctx.parks) == 0 { C.sched_yield() }
		check(C.vinix_linuxkpi_timer_active() == 0 && C.swh_pending(&node.fence) == 1, @LINE)
		C.dma_fence_signal(&dma.fence)
		join(&actor)
		C.rcuh_store32(&page_fail, 0)
		check(actor.result == 0, @LINE)
		C.i915_sw_fence_commit(&node.fence)
		C.dma_fence_put(&dma.fence)
		C.rcu_barrier()
	}
}

fn timed_tests() {
	unsafe {
		for timeout_first in [false, true]! {
			baseline := C.rcuh_load32(&page_live)
			notice_before := C.rcuh_load32(&notices)
			mut ledger := SwLedger{}
			mut node := SwNode{}
			init_sw(&node, &ledger)
			dma := new_dma(20)
			check(C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, 5, 3264) == 1 && C.dfh_refcount(&dma.fence) == 2 && C.vinix_linuxkpi_timer_active() == 1, @LINE)
			C.i915_sw_fence_commit(&node.fence)
			if timeout_first {
				advance(2000)
				check(C.vinix_linuxkpi_timer_dispatch() == 1 && ledger.error == -110 && ledger.complete == 1, @LINE)
				check(C.dfh_refcount(&dma.fence) == 2 && C.rcuh_load32(&page_live) > baseline, @LINE)
			}
			check(C.rcuh_load32(&notices) == notice_before + if timeout_first {
				u32(1)
			} else {
				u32(0)
			}, @LINE)
			if timeout_first {
				check(C.strcmp(&char(notice_format), C.swh_expected_notice()) == 0 && C.strcmp(&char(notice_driver), c'host-sw') == 0 && C.strcmp(&char(notice_timeline), c'host-sw') == 0 && notice_seqno == 1 && same(notice_hint, voidptr(notify)), @LINE)
			}
			C.dma_fence_signal(&dma.fence)
			check(ledger.complete == 1 && ledger.freed == 1, @LINE)
			drain_all()
			check(C.vinix_linuxkpi_timer_active() == 0 && C.dfh_refcount(&dma.fence) == 1, @LINE)
			C.dma_fence_put(&dma.fence)
			C.rcu_barrier()
			check(C.rcuh_load32(&page_live) == baseline, @LINE)
		}
	}
}

fn self_free_dma_tests() {
	unsafe {
		for timed in [false, true]! {
			baseline := C.rcuh_load32(&page_live)
			mut ledger := SwLedger{}
			node := &SwNode(C.vkr_kmalloc(sizeof(SwNode), 3264 | 0x100))
			init_sw(node, &ledger)
			node.self_free = true
			dma := new_dma(24)
			check(C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, if timed {
				usize(5)
			} else {
				usize(0)
			}, 3264) == 1, @LINE)
			C.i915_sw_fence_commit(&node.fence)
			C.dma_fence_signal(&dma.fence)
			check(ledger.complete == 1 && ledger.freed == 1, @LINE)
			if timed {
				drain_all()
				C.rcu_barrier()
			}
			C.dma_fence_put(&dma.fence)
			C.rcu_barrier()
			check(C.rcuh_load32(&page_live) == baseline, @LINE)
		}
	}
}

fn reservation_rcu_retry_test() {
	unsafe {
		baseline := C.rcuh_load32(&page_live)
		mut resv := C.dma_resv{}
		C.dma_resv_init(&resv)
		a := new_dma(50)
		b := new_dma(51)
		replacement := new_dma(52)
		check(C.dma_resv_lock(&resv, nil) == 0 && C.dma_resv_reserve_fences(&resv, 2) == 0, @LINE)
		C.dma_resv_add_fence(&resv, &a.fence, 0)
		C.dma_resv_add_fence(&resv, &b.fence, 1)
		C.dma_resv_unlock(&resv)
		mut ledger := SwLedger{}
		mut node := SwNode{}
		init_sw(&node, &ledger)
		load_target = C.rsh_tag_address(&resv, 1)
		load_entered = 0
		load_release = 0
		mut actor := Actor{ node: &node, resv: &resv, action: .resv }
		start(&actor)
		await32(&load_entered, 1)
		frees := C.rcuh_load32(&page_frees)
		C.dma_fence_put(&b.fence)
		check(C.dma_resv_lock(&resv, nil) == 0, @LINE)
		C.dma_resv_replace_fences(&resv, 51, &replacement.fence, 1)
		C.dma_resv_unlock(&resv)
		before := attempts(1)
		await_attempt(1, before)
		check(C.rcuh_load32(&page_frees) == frees, @LINE)
		C.rcuh_store32(&load_release, 1)
		join(&actor)
		load_target = nil
		check(actor.result == 1 && C.swh_pending(&node.fence) == 4, @LINE)
		C.i915_sw_fence_commit(&node.fence)
		C.dma_fence_signal(&a.fence)
		check(!C.i915_sw_fence_done(&node.fence), @LINE)
		C.dma_fence_signal(&replacement.fence)
		check(ledger.complete == 1 && ledger.freed == 1, @LINE)
		C.dma_resv_fini(&resv)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&replacement.fence)
		C.rcu_barrier()
		check(C.rcuh_load32(&page_live) == baseline, @LINE)
	}
}

fn timer_shutdown_race() {
	unsafe {
		baseline := C.rcuh_load32(&page_live)
		mut ledger := SwLedger{ gate: true, release: 0 }
		mut node := SwNode{}
		init_sw(&node, &ledger)
		dma := new_dma(25)
		check(C.i915_sw_fence_await_dma_fence(&node.fence, &dma.fence, 5, 3264) == 1, @LINE)
		owner := C.swh_timed_callback(&dma.fence)
		work := C.swh_timed_work(owner)
		C.i915_sw_fence_commit(&node.fence)
		advance(2000)
		mut reader := Actor{ action: .reader }
		start(&reader)
		mut timer := Actor{ action: .timer }
		start(&timer)
		await32(&ledger.entered, 1)
		check(C.dma_fence_signal(&dma.fence) == 0, @LINE)
		route(3)
		mut irq := Actor{ action: .irq, exit_release: 0 }
		start(&irq)
		for C.vkiw_running_count(work) == 0 { C.sched_yield() }
		check(C.rcuh_load32(&irq.done) == 0 && C.vinix_linuxkpi_timer_active() == 1 && C.dfh_refcount(&dma.fence) == 2, @LINE)
		C.rcuh_store32(&ledger.release, 1)
		join(&timer)
		await32(&irq.exit_entered, 1)
		check(ledger.complete == 1 && ledger.freed == 1 && ledger.error == -110 && C.dfh_refcount(&dma.fence) == 1 && C.vinix_linuxkpi_timer_active() == 0, @LINE)
		check(C.rcuh_load32(&page_live) == baseline + 2, @LINE)
		C.rcuh_store32(&reader.release, 1)
		join(&reader)
		before := attempts(0)
		await_attempt(0, before)
		check(C.rcuh_load32(&page_live) == baseline + 2 && C.vkiw_running_count(work) == 0, @LINE)
		C.rcuh_store32(&irq.exit_release, 1)
		join(&irq)
		C.rcu_barrier()
		check(C.rcuh_load32(&page_live) == baseline + 1, @LINE)
		C.dma_fence_put(&dma.fence)
		C.rcu_barrier()
		route(0)
		check(C.rcuh_load32(&page_live) == baseline, @LINE)
	}
}

fn graph_oom_tests() {
	unsafe {
		mut ledger := SwLedger{}
		mut a := SwNode{}
		mut b := SwNode{}
		init_sw(&a, &ledger)
		init_sw(&b, &ledger)
		calls := C.rcuh_load32(&page_calls)
		C.rcuh_store32(&page_fail, 1)
		check(C.i915_sw_fence_await_sw_fence_gfp(&a.fence, &b.fence, 0) == -12 && C.swh_pending(&a.fence) == 1 && C.rcuh_load32(&page_calls) == calls + 1, @LINE)
		mut actor := Actor{ node: &a, signaler: &b, action: .sw }
		start(&actor)
		for C.rcuh_load32(&actor.ctx.parks) == 0 { C.sched_yield() }
		C.swh_set_error(&b.fence, -17)
		C.i915_sw_fence_commit(&b.fence)
		join(&actor)
		C.rcuh_store32(&page_fail, 0)
		check(actor.result == 0 && C.swh_pending(&a.fence) == 1 && C.swh_error(&a.fence) == -17, @LINE)
		C.i915_sw_fence_commit(&a.fence)
	}
}

fn reservation_tests() {
	unsafe {
		for write in [false, true]! {
			mut resv := C.dma_resv{}
			C.dma_resv_init(&resv)
			check(C.dma_resv_lock(&resv, nil) == 0 && C.dma_resv_reserve_fences(&resv, 4) == 0, @LINE)
			mut fences := [4]&FenceNode{}
			for i := u32(0); i < 4; i++ {
				fences[i] = new_dma(30 + i)
				C.dma_resv_add_fence(&resv, &fences[i].fence, i)
			}
			C.dma_resv_unlock(&resv)
			mut ledger := SwLedger{}
			mut node := SwNode{}
			init_sw(&node, &ledger)
			check(C.i915_sw_fence_await_reservation(&node.fence, &resv, write, 0, 3264) == 1 && C.swh_pending(&node.fence) == if write {
				4
			} else {
				3
			}, @LINE)
			C.i915_sw_fence_commit(&node.fence)
			for i := 0; i < 2; i++ { C.dma_fence_signal(&fences[i].fence) }
			check(C.i915_sw_fence_done(&node.fence) == !write, @LINE)
			for i := 2; i < 4; i++ { C.dma_fence_signal(&fences[i].fence) }
			check(ledger.complete == 1 && ledger.freed == 1, @LINE)
			C.dma_resv_fini(&resv)
			for i := 0; i < 4; i++ { C.dma_fence_put(&fences[i].fence) }
			C.rcu_barrier()
		}
		mut resv := C.dma_resv{}
		C.dma_resv_init(&resv)
		check(C.dma_resv_lock(&resv, nil) == 0 && C.dma_resv_reserve_fences(&resv, 2) == 0, @LINE)
		a := new_dma(40)
		b := new_dma(41)
		a.fail_next = true
		C.dma_resv_add_fence(&resv, &a.fence, 0)
		C.dma_resv_add_fence(&resv, &b.fence, 1)
		C.dma_resv_unlock(&resv)
		mut ledger := SwLedger{}
		mut node := SwNode{}
		init_sw(&node, &ledger)
		check(C.i915_sw_fence_await_reservation(&node.fence, &resv, true, 0, 0) == -12 && C.swh_pending(&node.fence) == 2 && C.swh_error(&node.fence) == 0, @LINE)
		C.rcuh_store32(&page_fail, 0)
		C.i915_sw_fence_commit(&node.fence)
		C.dma_fence_signal(&a.fence)
		check(ledger.complete == 1 && ledger.freed == 1, @LINE)
		C.dma_fence_signal(&b.fence)
		C.dma_resv_fini(&resv)
		C.dma_fence_put(&a.fence)
		C.dma_fence_put(&b.fence)
		C.rcu_barrier()
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
		dma_ops = C.dma_fence_ops{ get_driver_name: driver_name, get_timeline_name: driver_name, enable_signaling: enable }
		check(C.vkm_cpu_masks_bootstrap(4) == 0 && C.vkr_rcu_bootstrap(4) == 0 && C.vkiw_bootstrap(4) == 0, @LINE)
		basic_tests()
		graph_tests()
		graph_oom_tests()
		dma_tests()
		immediate_dma_tests()
		timed_tests()
		self_free_dma_tests()
		timer_shutdown_race()
		reservation_tests()
		reservation_rcu_retry_test()
		C.rcu_barrier()
		C.vkr_rcu_shutdown_for_test()
		check(C.rcuh_load32(&page_live) == 0 && C.vinix_linuxkpi_timer_active() == 0 && C.vinix_linuxkpi_time_waiters() == 0, @LINE)
		check(C.rcuh_load32(&ctx.refs) == 1 && C.pthread_setspecific(context_key, nil) == 0, @LINE)
		context_destructor(ctx)
		check(C.rcuh_load32(&context_live) == 0 && C.pthread_key_delete(context_key) == 0, @LINE)
		C.printf(c'PASS: whole unchanged i915 SW fence with actual V timer/IRQ/fence/reservation/RCU, %u assertions\n', C.rcuh_load32(&assertions))
		return 0
	}
}
