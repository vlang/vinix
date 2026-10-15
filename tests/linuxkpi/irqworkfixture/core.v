// SPDX-License-Identifier: GPL-2.0-or-later
// Test observations and low-level CPU/IPI transport only; no IRQ queue model.
@[translated]
module irqworkfixture

#include "contract.h"
@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.pthread_key_t {}

@[typedef]
struct C.iwh_const_charp {}

struct C.irq_work {}

fn C.pthread_key_create(&C.pthread_key_t, voidptr) i32
fn C.pthread_key_delete(C.pthread_key_t) i32
fn C.pthread_getspecific(C.pthread_key_t) voidptr
fn C.pthread_setspecific(C.pthread_key_t, voidptr) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.sched_yield() i32
fn C.printf(&char, ...) i32
fn C.fprintf(voidptr, &char, ...) i32

@[c_extern]
__global C.stderr voidptr

@[noreturn]
fn C.abort()

fn C.atoi(&char) i32
fn C.iwh_load(&u32) u32
fn C.iwh_store(&u32, u32)
fn C.iwh_add(&u32, u32) u32
fn C.iwh_exchange(&u32, u32) u32
fn C.iwh_line(string) &char
fn C.iwh_flags(&C.irq_work) u32
fn C.iwh_set_flags(&C.irq_work, u32)
fn C.iwh_init(&C.irq_work, fn (&C.irq_work), u32)
fn C.iwh_next(&C.irq_work) usize
fn C.iwh_set_next(&C.irq_work, usize)
fn C.irq_work_queue(&C.irq_work) bool
fn C.irq_work_queue_on(&C.irq_work, i32) bool
fn C.irq_work_sync(&C.irq_work)
fn C.irq_work_is_pending(&C.irq_work) bool
fn C.irq_work_is_busy(&C.irq_work) bool
fn C.irq_work_needs_cpu() bool
fn C.vkiw_bootstrap(u32) i32
fn C.vkiw_ready() bool
fn C.vkiw_drain(u32)
fn C.vkiw_tick_all()
fn C.vkiw_running_count(voidptr) u32
fn C.vkiw_sync_wait_count() u64
fn C.vkm_cpu_masks_bootstrap(u32) i32

struct Context {
mut:
	cpu         u32
	flags       u64 = 0x202
	depth       u32
	pins        u32
	task        bool = true
	sync_waiter bool
}

struct Node {
mut:
	work     C.irq_work
	expected u32
	calls    u32
	entered  u32
	release  u32 = 1
	done     u32
	requeue  u32
}

struct Actor {
mut:
	thread  C.pthread_t
	cpu     u32
	started u32
	done    u32
	work    &C.irq_work = unsafe { nil }
	sync    bool
}

@[cinit]
__global (
	key                  C.pthread_key_t
	assertions           u32
	count                u32
	ipis                 [256]u32
	delivered            [256]u32
	transport_ready      u32 = 1
	rcu_domain_published u32 = 1
	allocation_calls     u32
	fail_alloc           u32 = 1
	abi_node             Node
	aba_started          [2]u32
	aba_release          [2]u32
	aba_done             [2]u32
	aba_calls            u32
	waiter_spins         u32
	fatal_head           &C.irq_work = unsafe { nil }
	fatal_flags          u32
	fatal_next           usize
	fatal_watch          bool
)

fn check(value bool, line string) {
	unsafe {
		C.iwh_add(&assertions, 1)
		if !value {
			C.fprintf(C.stderr, c'IRQ work assertion %s\n', C.iwh_line(line))
			C.abort()
		}
	}
}

fn ctx() &Context { return unsafe { &Context(C.pthread_getspecific(key)) } }

fn install(c &Context) { check(C.pthread_setspecific(unsafe { key }, c) == 0, @LINE) }

fn await_word(word &u32, value u32) {
	for turns := 0; turns < 20000000; turns++ {
		if C.iwh_load(word) >= value { return }
		C.sched_yield()
	}
	check(false, @LINE)
}

@[export:'vinix_linuxkpi_cpu_id']
pub fn cpu_id() u32 { return ctx().cpu }

@[export:'vinix_linuxkpi_preempt_count']
pub fn pins() u32 { return ctx().pins }

@[export:'vinix_linuxkpi_maskable_irq_depth']
pub fn depth() u32 { return ctx().depth }

@[export:'vinix_linuxkpi_irq_flags']
pub fn flags() usize { return usize(ctx().flags) }

@[export:'vinix_linuxkpi_irq_save']
pub fn irq_save() usize {
	unsafe {
		saved := ctx().flags
		ctx().flags &= ~u64(512)
		return usize(saved)
	}
}

@[export:'vinix_linuxkpi_irq_restore']
pub fn irq_restore(v usize) {
	unsafe { ctx().flags = u64(v) }
}

@[export:'vinix_linuxkpi_preempt_disable']
pub fn preempt_disable() {
	unsafe { ctx().pins++ }
}

@[export:'vinix_linuxkpi_preempt_enable']
pub fn preempt_enable() {
	unsafe {
		check(ctx().pins > 0, @LINE)
		ctx().pins--
	}
}

@[export:'vinix_linuxkpi_may_sleep']
pub fn may_sleep() bool {
	return ctx().task && ctx().pins == 0 && ctx().depth == 0 && (ctx().flags & 512) != 0
}

@[export:'vinix_linuxkpi_smp_task_present']
pub fn task_present() bool { return ctx().task }

@[export:'vinix_linuxkpi_smp_boot_context']
pub fn boot_context() bool { return may_sleep() }

@[export:'vks_smp_ready']
pub fn smp_ready() bool { return unsafe { C.iwh_load(&transport_ready) != 0 } }

// Constructor input only. These callbacks retain storage and never execute a
// grace period or deferred free; the native fixture validates real RCU use.
@[export:'vkr_rcu_ready']
pub fn rcu_ready_observation() bool { return unsafe { C.iwh_load(&rcu_domain_published) != 0 } }

@[export:'vinix_linuxkpi_spin_wait']
pub fn spin_wait() {
	unsafe { if ctx().sync_waiter { C.iwh_add(&waiter_spins, 1) } }
	C.sched_yield()
}

@[export:'vinix_linuxkpi_cond_resched']
pub fn resched() i32 {
	if may_sleep() {
		unsafe { if ctx().sync_waiter { C.iwh_add(&waiter_spins, 1) } }
		C.sched_yield()
		return 1
	}
	return 0
}

@[export:'vinix_linuxkpi_irqwork_send_ipi']
pub fn send_ipi(cpu u32) {
	unsafe {
		check(cpu < count, @LINE)
		C.iwh_add(&ipis[cpu], 1)
	}
}

@[export:'vkp_spin_init']
pub fn spin_init(p voidptr) {
	unsafe { C.iwh_store(&u32(p), 0) }
}

@[export:'vkp_spin_lock_irqsave']
pub fn spin_lock(p voidptr) usize {
	preempt_disable()
	saved := irq_save()
	unsafe {
		for C.iwh_exchange(&u32(p), 1) != 0 { C.sched_yield() }
	}
	return saved
}

@[export:'vkp_spin_unlock_irqrestore']
pub fn spin_unlock(p voidptr, saved usize) {
	unsafe { C.iwh_store(&u32(p), 0) }
	preempt_enable()
	irq_restore(saved)
}

@[export:'kmalloc']
pub fn unexpected_allocate(_bytes usize, _flags u32) voidptr {
	unsafe {
		C.iwh_add(&allocation_calls, 1)
		check(C.iwh_load(&fail_alloc) != 0, @LINE)
	}
	return unsafe { nil }
}

@[export:'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason C.iwh_const_charp, line i32) {
	unsafe {
		if fatal_watch {
			check(C.iwh_flags(fatal_head) == fatal_flags && C.iwh_next(fatal_head) == fatal_next, @LINE)
			C.fprintf(C.stderr, c'IRQ work validation preserved node\n')
		}
		C.fprintf(C.stderr, c'IRQ work invariant: %s:%d\n', reason, line)
		C.abort()
	}
}

fn deliver(cpu u32) {
	unsafe {
		old := ctx()
		mut c := Context{ cpu: cpu, flags: 2, depth: 1, task: false }
		install(&c)
		C.vkiw_drain(cpu)
		check(c.flags == 2 && c.depth == 1 && c.pins == 0, @LINE)
		install(old)
		C.iwh_add(&delivered[cpu], 1)
	}
}

fn actor_run(argument voidptr) voidptr {
	unsafe {
		a := &Actor(argument)
		mut c := Context{ cpu: a.cpu, sync_waiter: a.sync }
		install(&c)
		C.iwh_store(&a.started, 1)
		if a.sync { C.irq_work_sync(a.work) } else { deliver(a.cpu) }
		check(may_sleep(), @LINE)
		C.iwh_store(&a.done, 1)
		return nil
	}
}

fn start(a &Actor) {
	unsafe {
		check(C.pthread_create(&a.thread, nil, actor_run, a) == 0, @LINE)
		await_word(&a.started, 1)
	}
}

fn join(a &Actor) {
	unsafe { check(C.pthread_join(a.thread, nil) == 0 && C.iwh_load(&a.done) == 1, @LINE) }
}

fn callback(w &C.irq_work) {
	unsafe {
		node := &Node(w)
		check(cpu_id() == node.expected && depth() == 1 && (flags() & 512) == 0 && !may_sleep(), @LINE)
		C.iwh_add(&node.calls, 1)
		check(!C.irq_work_is_pending(w) && C.irq_work_is_busy(w), @LINE)
		C.iwh_store(&node.entered, 1)
		await_word(&node.release, 1)
		if node.requeue != 0 {
			node.requeue--
			check(C.irq_work_queue(w), @LINE)
		}
		C.iwh_add(&node.done, 1)
	}
}

fn test_cpu(target u32, lazy bool) {
	unsafe {
		mut node := Node{ expected: target }
		C.iwh_init(&node.work, callback, if lazy { u32(4) } else { u32(0) })
		old_cpu := ctx().cpu
		ctx().cpu = target
		saved := irq_save()
		before := C.iwh_load(&ipis[target])
		check(C.irq_work_queue(&node.work), @LINE)
		check(!C.irq_work_queue(&node.work) && node.calls == 0 && pins() == 0 && (flags() & 512) == 0, @LINE)
		check(C.irq_work_needs_cpu() == lazy, @LINE)
		check(C.iwh_load(&ipis[target]) == before + if lazy { u32(0) } else { u32(1) }, @LINE)
		irq_restore(saved)
		if lazy {
			mut tick := Context{ cpu: 0, flags: 2, depth: 1, task: false }
			old := ctx()
			install(&tick)
			C.vkiw_tick_all()
			install(old)
			check(C.iwh_load(&ipis[target]) > before, @LINE)
		}
		deliver(target)
		C.irq_work_sync(&node.work)
		check(node.calls == 1 && node.done == 1 && !C.irq_work_is_busy(&node.work) && C.iwh_load(&allocation_calls) == 0, @LINE)
		check(!C.irq_work_needs_cpu(), @LINE)
		ctx().cpu = old_cpu
	}
}

fn test_remote() {
	unsafe {
		if count < 2 { return }
		mut node := Node{ expected: count - 1 }
		C.iwh_init(&node.work, callback, 4)
		before := C.iwh_load(&ipis[count - 1])
		check(C.irq_work_queue_on(&node.work, i32(count - 1)), @LINE)
		check(node.calls == 0 && C.iwh_load(&ipis[count - 1]) == before + 1, @LINE)
		deliver(count - 1)
		C.irq_work_sync(&node.work)
		check(node.calls == 1, @LINE)
	}
}

fn test_requeue() {
	unsafe {
		mut node := Node{ expected: 0, requeue: 3 }
		C.iwh_init(&node.work, callback, 0)
		check(C.irq_work_queue(&node.work), @LINE)
		for index := 0; index < 4; index++ { deliver(0) }
		C.irq_work_sync(&node.work)
		check(node.calls == 4 && node.done == 4 && !C.irq_work_is_busy(&node.work), @LINE)
	}
}

fn test_batch_doorbell() {
	unsafe {
		mut first := Node{ expected: 0 }
		mut second := Node{ expected: 0 }
		C.iwh_init(&first.work, callback, 0)
		C.iwh_init(&second.work, callback, 8)
		before := C.iwh_load(&ipis[0])
		saved := irq_save()
		check(C.irq_work_queue(&first.work) && C.irq_work_queue(&second.work), @LINE)
		check(C.iwh_load(&ipis[0]) == before + 1 && first.calls == 0 && second.calls == 0, @LINE)
		irq_restore(saved)
		deliver(0)
		C.irq_work_sync(&first.work)
		C.irq_work_sync(&second.work)
		check(first.calls == 1 && second.calls == 1 && C.iwh_flags(&second.work) == 0x28, @LINE)
	}
}

fn aba_callback(w &C.irq_work) {
	unsafe {
		index := cpu_id()
		check(index < 2 && depth() == 1 && !C.irq_work_is_pending(w), @LINE)
		C.iwh_add(&aba_calls, 1)
		C.iwh_store(&aba_started[index], 1)
		await_word(&aba_release[index], 1)
		C.iwh_store(&aba_done[index], 1)
	}
}

fn test_overlap_aba() {
	unsafe {
		if count < 2 { return }
		C.iwh_init(&abi_node.work, aba_callback, 0)
		check(C.irq_work_queue_on(&abi_node.work, 0), @LINE)
		mut first := Actor{ cpu: 0 }
		start(&first)
		await_word(&aba_started[0], 1)
		check(C.irq_work_queue_on(&abi_node.work, 1), @LINE)
		mut second := Actor{ cpu: 1 }
		start(&second)
		await_word(&aba_started[1], 1)
		check(C.vkiw_running_count(&abi_node.work) == 2, @LINE)
		C.iwh_store(&aba_release[0], 1)
		join(&first)
		check(!C.irq_work_is_busy(&abi_node.work) && C.iwh_load(&aba_done[1]) == 0, @LINE)
		check(C.vkiw_running_count(&abi_node.work) == 1, @LINE)
		waits_before := C.vkiw_sync_wait_count()
		mut waiter := Actor{ cpu: 0, sync: true, work: &abi_node.work }
		start(&waiter)
		for turns := 0; turns < 20000000; turns++ {
			check(C.iwh_load(&waiter.done) == 0, @LINE)
			if C.vkiw_sync_wait_count() > waits_before { break }
			C.sched_yield()
		}
		check(C.vkiw_sync_wait_count() > waits_before, @LINE)
		check(C.iwh_load(&waiter.done) == 0, @LINE)
		C.iwh_store(&aba_release[1], 1)
		join(&second)
		join(&waiter)
		check(aba_calls == 2 && !C.irq_work_is_busy(&abi_node.work), @LINE)
	}
}

fn invalid(mode i32) {
	unsafe {
		mut node := Node{}
		C.iwh_init(&node.work, callback, 0)
		fatal_head = &node.work
		fatal_flags = C.iwh_flags(fatal_head)
		fatal_next = C.iwh_next(fatal_head)
		fatal_watch = true
		match mode {
			10 { C.irq_work_queue_on(&node.work, -1) }
			11 { C.irq_work_queue_on(&node.work, i32(count)) }
			12 {
				C.iwh_set_flags(&node.work, 0x40)
				fatal_flags = 0x40
				C.irq_work_queue(&node.work)
			}
			13 {
				irq_save()
				C.irq_work_sync(&node.work)
			}
			14 {
				preempt_disable()
				C.irq_work_sync(&node.work)
			}
			15 {
				ctx().depth = 1
				C.irq_work_sync(&node.work)
			}
			16 {
				ctx().task = false
				C.irq_work_sync(&node.work)
			}
			17 {
				C.iwh_set_flags(&node.work, 0x10)
				fatal_flags = 0x10
				C.irq_work_queue(&node.work)
			}
			18 {
				C.iwh_init(&node.work, nil, 0)
				C.irq_work_queue(&node.work)
			}
			else { check(false, @LINE) }
		}
		check(false, @LINE)
	}
}

@[export:'main']
pub fn main(argc i32, argv &&char) i32 {
	unsafe {
		check(argc == 3 && C.pthread_key_create(&key, nil) == 0, @LINE)
		count = u32(C.atoi(argv[1]))
		mode := C.atoi(argv[2])
		mut c := Context{}
		install(&c)
		check(count > 0 && count <= 256 && C.vkm_cpu_masks_bootstrap(count) == 0, @LINE)
		check(!C.vkiw_ready(), @LINE)
		C.iwh_store(&transport_ready, 0)
		check(C.vkiw_bootstrap(count) == -22 && !C.vkiw_ready(), @LINE)
		C.iwh_store(&transport_ready, 1)
		C.iwh_store(&rcu_domain_published, 0)
		check(C.vkiw_bootstrap(count) == -22 && !C.vkiw_ready(), @LINE)
		C.iwh_store(&rcu_domain_published, 1)
		check(C.vkiw_bootstrap(0) == -22 && C.vkiw_bootstrap(257) == -22, @LINE)
		if count > 1 { check(C.vkiw_bootstrap(count - 1) == -22, @LINE) }
		saved := irq_save()
		check(C.vkiw_bootstrap(count) == -1, @LINE)
		irq_restore(saved)
		preempt_disable()
		check(C.vkiw_bootstrap(count) == -1, @LINE)
		preempt_enable()
		c.depth = 1
		check(C.vkiw_bootstrap(count) == -1, @LINE)
		c.depth = 0
		c.task = false
		check(C.vkiw_bootstrap(count) == -1, @LINE)
		c.task = true
		check(C.vkiw_bootstrap(count) == 0 && C.vkiw_ready(), @LINE)
		check(C.vkiw_bootstrap(count) == -114 && C.iwh_load(&allocation_calls) == 0, @LINE)
		if mode >= 10 { invalid(mode) }
		for cpu in [u32(0), count - 1, u32(63), u32(64), u32(127), u32(128), u32(255)]! {
			if cpu < count {
				test_cpu(cpu, false)
				test_cpu(cpu, true)
			}
		}
		test_remote()
		test_requeue()
		test_batch_doorbell()
		test_overlap_aba()
		check(C.iwh_load(&allocation_calls) == 0 && may_sleep() && C.pthread_setspecific(key, nil) == 0 && C.pthread_key_delete(key) == 0, @LINE)
		C.printf(c'PASS: %u CPUs original IRQ work, actual V queues, lazy/IPI routing, requeue, concurrent BUSY ABA synchronization; %u assertions\n', count, C.iwh_load(&assertions))
		return 0
	}
}
