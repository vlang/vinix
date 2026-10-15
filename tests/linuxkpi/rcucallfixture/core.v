// SPDX-License-Identifier: GPL-2.0-or-later
// Independent CPU/thread/IRQ observations. No grace-period or queue model.
@[translated]
module rcucallfixture

#include "rcucall_host_contract.h"

@[typedef] struct C.pthread_key_t {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.rcuh_const_charp {}
@[typedef] struct C.rcuh_const_voidp {}
struct C.task_struct { vinix_thread voidptr, __state u32 }
struct C.callback_head {}
struct C.vkw_completion { mut: done u32 }
struct C.vkw_swait_head { mut: lock u32, task_list C.vkw_list }
struct C.vkw_list { mut: next &C.vkw_list, prev &C.vkw_list }
struct C.timespec { tv_sec isize, tv_nsec isize }
fn C.pthread_key_create(&C.pthread_key_t, fn (voidptr)) i32
fn C.pthread_key_delete(C.pthread_key_t) i32
fn C.pthread_getspecific(C.pthread_key_t) voidptr
fn C.pthread_setspecific(C.pthread_key_t, voidptr) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32
@[noreturn] fn C.pthread_exit(voidptr)
fn C.nanosleep(&C.timespec, voidptr) i32
fn C.sched_yield() i32
fn C.calloc(usize, usize) voidptr
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.free(voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.printf(&char, ...) i32
fn C.fprintf(voidptr, &char, ...) i32
@[c_extern] __global C.stderr voidptr
@[noreturn] fn C.abort()
fn C.atoi(&char) i32
fn C.rcuh_load32(&u32) u32
fn C.rcuh_store32(&u32, u32)
fn C.rcuh_add32(&u32, u32) u32
fn C.rcuh_exchange32(&u32, u32) u32
fn C.rcuh_compare32(&u32, &u32, u32) bool
fn C.rcuh_load64(&u64) u64
fn C.rcuh_store64(&u64, u64)
fn C.rcuh_add64(&u64, u64) u64
fn C.rcuh_line(string) &char
fn C.rcuh_head_bytes() usize
fn C.rcuh_head_alignment() usize
fn C.rcuh_read_lock()
fn C.rcuh_read_unlock()
fn C.vkr_rcu_bootstrap(u32) i32
fn C.vkr_rcu_ready() bool
fn C.vkr_rcu_quiescent(u32)
fn C.vkr_rcu_shutdown_for_test()
fn C.vkm_cpu_masks_bootstrap(u32) i32
fn C.call_rcu(&C.callback_head, fn (&C.callback_head))
fn C.synchronize_rcu()
fn C.synchronize_rcu_expedited()
fn C.rcu_barrier()
fn C.get_state_synchronize_rcu() usize
fn C.start_poll_synchronize_rcu() usize
fn C.poll_state_synchronize_rcu(usize) bool
fn C.cond_synchronize_rcu(usize)
fn C.compatcore__rcu_sequence_exact_done(u64, u64) bool

struct Context {
mut:
	task C.task_struct
	cpu u32
	flags usize = 0x202
	pins u32
	depth u32
	refs u32 = 1
	retired u32
	worker bool
	constructor bool
	waiter &Waiter = unsafe { nil }
}
struct Ledger {
mut:
	calls u32
	entered u32
	release u32 = 1
	terminal u32
	freed u32
	order &u32 = unsafe { nil }
}
struct Node {
mut:
	head C.callback_head
	ledger &Ledger = unsafe { nil }
	index u32
	remaining u32 = 1
	free_self bool
	free_before_wait bool
}
enum Operation { synchronize expedited barrier conditional }
struct Waiter {
mut:
	thread C.pthread_t
	cookie usize
	operation Operation
	entered u32
	done u32
	parks u32
}
struct Reader {
mut:
	thread C.pthread_t
	cpu u32
	ready u32
	quit u32
}
struct CookieBoundary {
	observed u64
	cookie u64
	expected bool
}

@[cinit]
__global (
	context_key C.pthread_key_t
	context_guard u32
	assertions u32
	configured_cpus u32
	smp_transport_ready u32
	cpu_pins [256]u32
	cpu_irq_off [256]u32
	cpu_depth [256]u32
	ipi_attempts [256]u64
	ipi_returns [256]u64
	allocation_calls u32
	allocation_live u32
	allocation_fail_after i32 = -1
	create_calls u32
	create_fail_after i32 = -1
	context_live u32
	worker_live u32
	worker_enters u32
	worker_exits u32
	retirement_queries u32
	order_next u32
	batch [4097]Node
	batch_order [4097]u32
)

fn check(value bool, line string) {
	unsafe {
		C.rcuh_add32(&assertions, 1)
		if !value { C.fprintf(C.stderr, c'RCU assertion line %s; number %u\n', C.rcuh_line(line), C.rcuh_load32(&assertions)); C.abort() }
	}
}
fn lock_context() { unsafe { for C.rcuh_exchange32(&context_guard, 1) != 0 { C.sched_yield() } } }
fn unlock_context() { unsafe { C.rcuh_store32(&context_guard, 0) } }
fn pause() { mut t := C.timespec{ tv_nsec: 100000 }; C.nanosleep(&t, unsafe { nil }) }
fn context() &Context {
	unsafe {
		mut ctx := &Context(C.pthread_getspecific(context_key))
		if ctx != nil { return ctx }
		ctx = &Context(C.calloc(1, sizeof(Context)))
		check(ctx != nil, @LINE)
		ctx.flags = 0x202
		ctx.refs = 1
		ctx.task.vinix_thread = ctx
		check(C.pthread_setspecific(context_key, ctx) == 0, @LINE)
		C.rcuh_add32(&context_live, 1)
		return ctx
	}
}
fn release_context(ctx &Context) {
	unsafe {
		if C.rcuh_add32(&ctx.refs, u32(-1)) == 1 {
			check(C.rcuh_load32(&ctx.retired) != 0, @LINE)
			C.rcuh_add32(&context_live, u32(-1))
			C.free(ctx)
		}
	}
}
fn context_destructor(argument voidptr) {
	unsafe {
		ctx := &Context(argument)
		check(ctx.pins == 0 && ctx.depth == 0 && (ctx.flags & 512) != 0, @LINE)
		ctx.task.__state = 128
		C.rcuh_store32(&ctx.retired, 1)
		release_context(ctx)
	}
}
fn route(cpu u32) {
	unsafe {
		ctx := context()
		check(cpu < configured_cpus && ctx.pins == 0 && ctx.depth == 0 && (ctx.flags & 512) != 0, @LINE)
		ctx.cpu = cpu
	}
}
fn await32(word &u32, expected u32) {
	for turns := 0; turns < 100000; turns++ { if C.rcuh_load32(word) >= expected { return }; pause() }
	check(false, @LINE)
}
fn await_attempt(cpu u32, before u64) {
	unsafe {
		for turns := 0; turns < 100000; turns++ { if C.rcuh_load64(&ipi_attempts[cpu]) > before { return }; pause() }
		check(false, @LINE)
	}
}
fn attempts(cpu u32) u64 { return unsafe { C.rcuh_load64(&ipi_attempts[cpu]) } }
fn returns(cpu u32) u64 { return unsafe { C.rcuh_load64(&ipi_returns[cpu]) } }
fn await_return(cpu u32, before u64) {
	for turns := 0; turns < 100000; turns++ { if returns(cpu) > before { return }; pause() }
	check(false, @LINE)
}
fn await_poll(cookie usize) {
	for turns := 0; turns < 100000; turns++ { if C.poll_state_synchronize_rcu(cookie) { return }; pause() }
	check(false, @LINE)
}

@[export: 'vinix_linuxkpi_cpu_id'] pub fn cpu_id() u32 { return context().cpu }
@[export: 'vinix_linuxkpi_preempt_count'] pub fn pins() u32 { return context().pins }
@[export: 'vinix_linuxkpi_maskable_irq_depth'] pub fn depth() u32 { return context().depth }
@[export: 'vinix_linuxkpi_irq_flags'] pub fn flags() usize { return context().flags }
@[export: 'vks_smp_ready'] pub fn smp_ready() bool { return unsafe { C.rcuh_load32(&smp_transport_ready) != 0 } }
@[export: 'vinix_linuxkpi_smp_task_present'] pub fn task_present() bool { return true }
@[export: 'vinix_linuxkpi_smp_boot_context'] pub fn boot_context() bool {
	ctx := context()
	return ctx.constructor && ctx.pins == 0 && ctx.depth == 0 && (ctx.flags & 512) != 0
}
@[export: 'vinix_linuxkpi_may_sleep'] pub fn may_sleep() bool {
	ctx := context()
	return ctx.pins == 0 && ctx.depth == 0 && (ctx.flags & 512) != 0
}
@[export: 'vinix_linuxkpi_preempt_disable'] pub fn preempt_disable() {
	unsafe {
		ctx := context(); lock_context()
		ctx.pins++; cpu_pins[ctx.cpu]++
		unlock_context()
	}
}
@[export: 'vinix_linuxkpi_preempt_enable'] pub fn preempt_enable() {
	unsafe {
		ctx := context(); lock_context()
		check(ctx.pins != 0 && cpu_pins[ctx.cpu] != 0, @LINE)
		ctx.pins--; cpu_pins[ctx.cpu]--
		unlock_context()
	}
}
@[export: 'vinix_linuxkpi_irq_save'] pub fn irq_save() usize {
	unsafe {
		ctx := context(); lock_context()
		old := ctx.flags
		if (old & 512) != 0 { cpu_irq_off[ctx.cpu]++; ctx.flags &= ~usize(512) }
		unlock_context()
		return old
	}
}
@[export: 'vinix_linuxkpi_irq_restore'] pub fn irq_restore(value usize) {
	unsafe {
		ctx := context(); lock_context()
		if (ctx.flags & 512) == 0 && (value & 512) != 0 { check(cpu_irq_off[ctx.cpu] != 0, @LINE); cpu_irq_off[ctx.cpu]-- }
		if (ctx.flags & 512) != 0 && (value & 512) == 0 { cpu_irq_off[ctx.cpu]++ }
		ctx.flags = value
		unlock_context()
	}
}
@[export: 'vinix_linuxkpi_spin_wait'] pub fn spin_wait() { C.sched_yield() }
@[export: 'vinix_linuxkpi_cond_resched'] pub fn reschedule() i32 { check(may_sleep(), @LINE); C.sched_yield(); return 1 }
@[export: 'msleep'] pub fn sleep(_milliseconds u32) {
	check(may_sleep(), @LINE)
	unsafe { ctx := context(); if ctx.waiter != nil { C.rcuh_add32(&ctx.waiter.parks, 1) } }
	pause()
}
@[export: 'vinix_linuxkpi_bug'; noreturn] pub fn bug(reason C.rcuh_const_charp, line i32) {
	unsafe { C.fprintf(C.stderr, c'RCU invariant: %s:%d\n', reason, line) }; C.abort()
}

// Transport tests CPU scopes, not the production's epoch or callback state.
// An eligible externally observed boundary runs only this trusted hook while
// the CPU-context mutex excludes entry into another modeled atomic region.
@[export: 'vinix_linuxkpi_rcu_force_quiescence'] pub fn force_quiescence() {
	unsafe {
		original := context()
		for cpu := u32(0); cpu < configured_cpus; cpu++ {
			C.rcuh_add64(&ipi_attempts[cpu], 1)
			lock_context()
			if cpu_pins[cpu] == 0 && cpu_irq_off[cpu] == 0 && cpu_depth[cpu] == 0 {
				mut returned := Context{cpu: cpu, flags: 2}
				check(C.pthread_setspecific(context_key, &returned) == 0, @LINE)
				C.vkr_rcu_quiescent(cpu)
				check(returned.flags == 2 && returned.pins == 0 && returned.depth == 0, @LINE)
				check(C.pthread_setspecific(context_key, original) == 0, @LINE)
				C.rcuh_add64(&ipi_returns[cpu], 1)
			}
			unlock_context()
		}
	}
}
@[export: 'vkp_spin_init'] pub fn spin_init(storage voidptr) { unsafe { C.rcuh_store32(&u32(storage), 0) } }
@[export: 'vkp_spin_lock_irqsave'] pub fn spin_lock(storage voidptr) usize {
	preempt_disable(); saved := irq_save()
	unsafe { for C.rcuh_exchange32(&u32(storage), 1) != 0 { C.sched_yield() } }
	return saved
}
@[export: 'vkp_spin_unlock_irqrestore'] pub fn spin_unlock(storage voidptr, saved usize) {
	unsafe { C.rcuh_store32(&u32(storage), 0) }; preempt_enable(); irq_restore(saved)
}
@[export: 'rcuh_completion_init'] pub fn completion_init(storage voidptr) {
	unsafe { head := &C.vkw_swait_head(storage); head.lock = 0; head.task_list.next = &head.task_list; head.task_list.prev = &head.task_list }
}
@[export: 'rcuh_completion_complete'] pub fn completion_complete(storage voidptr) {
	unsafe { C.rcuh_add32(&(&C.vkw_completion(storage)).done, 1) }
}
@[export: 'rcuh_completion_wait'] pub fn completion_wait(storage voidptr) {
	unsafe {
		check(may_sleep(), @LINE)
		word := &(&C.vkw_completion(storage)).done
		for { mut value := C.rcuh_load32(word); if value != 0 && C.rcuh_compare32(word, &value, value - 1) { return }; pause() }
	}
}
@[export: 'kzalloc'] pub fn allocate(bytes usize, gfp u32) voidptr {
	unsafe {
		check(gfp == 3264 && may_sleep(), @LINE)
		C.rcuh_add32(&allocation_calls, 1)
		if allocation_fail_after == 0 { allocation_fail_after = -1; return nil }
		if allocation_fail_after > 0 { allocation_fail_after-- }
		mut owner := voidptr(nil)
		check(C.posix_memalign(&owner, 32, bytes) == 0, @LINE)
		C.memset(owner, 0, bytes); C.rcuh_add32(&allocation_live, 1)
		return owner
	}
}
@[export: 'kfree'] pub fn deallocate(owner C.rcuh_const_voidp) {
	unsafe { check(usize(owner) != 0 && C.rcuh_load32(&allocation_live) != 0, @LINE); C.rcuh_add32(&allocation_live, u32(-1)); C.free(voidptr(owner)) }
}
// Fail-fast transport guards, never an allocator or deferred-free model.
// The separate deferred_free fixture executes the original runtime.v paths.
@[export: 'vkr_page_allocation_size'] pub fn unsupported_page_owner(_owner voidptr) usize {
	check(false, @LINE)
	return 0
}
@[export: 'vkr_kvfree'] pub fn unsupported_page_free(_owner voidptr) { check(false, @LINE) }
@[export: 'vkr_rcu_host_create_error'] pub fn create_error() i32 {
	unsafe {
		C.rcuh_add32(&create_calls, 1)
		if create_fail_after == 0 { create_fail_after = -1; return -12 }
		if create_fail_after > 0 { create_fail_after-- }
		return 0
	}
}
@[export: 'vkr_rcu_host_worker_enter'] pub fn worker_enter() {
	unsafe { ctx := context(); ctx.worker = true; C.rcuh_add32(&worker_live, 1); C.rcuh_add32(&worker_enters, 1) }
}
@[export: 'vkr_rcu_host_worker_leave'] pub fn worker_leave() {
	unsafe { ctx := context(); check(ctx.worker && may_sleep(), @LINE); C.rcuh_add32(&worker_live, u32(-1)); C.rcuh_add32(&worker_exits, 1) }
}
@[export: 'vinix_linuxkpi_current_task'] pub fn current_task() &C.task_struct { return unsafe { &context().task } }
@[export: 'get_task_struct'] pub fn get_task(task &C.task_struct) &C.task_struct {
	unsafe { ctx := &Context(task.vinix_thread); check(C.rcuh_load32(&ctx.retired) == 0, @LINE); C.rcuh_add32(&ctx.refs, 1); return task }
}
@[export: 'put_task_struct'] pub fn put_task(task &C.task_struct) { unsafe { release_context(&Context(task.vinix_thread)) } }
@[export: 'vinix_linuxkpi_test_thread_reap_ready'] pub fn retired(owner voidptr) bool {
	unsafe { C.rcuh_add32(&retirement_queries, 1); return C.rcuh_load32(&(&Context(owner)).retired) != 0 }
}

fn callback(head &C.callback_head) {
	unsafe {
		node := &Node(head)
		ledger := node.ledger
		index := node.index
		remaining := node.remaining
		free_self := node.free_self
		free_before_wait := node.free_before_wait
		check(context().pins != 0 && (context().flags & 512) != 0 && context().depth == 0 && !may_sleep(), @LINE)
		C.rcuh_add32(&ledger.calls, 1)
		if ledger.order != nil { ledger.order[index] = C.rcuh_add32(&order_next, 1) }
		if free_before_wait {
			check(free_self && remaining == 1, @LINE)
			C.free(node); C.rcuh_add32(&ledger.freed, 1)
		}
		C.rcuh_store32(&ledger.entered, 1)
		for C.rcuh_load32(&ledger.release) == 0 { C.sched_yield() }
		if remaining > 1 {
			node.remaining = remaining - 1
			C.call_rcu(head, callback)
		} else if free_self && !free_before_wait {
			C.free(node)
			C.rcuh_add32(&ledger.freed, 1)
		}
		// No head access after recursive enqueue or free. Ledger belongs to the
		// controller until the genuine barrier and all waiter joins return.
		C.rcuh_add32(&ledger.terminal, 1)
	}
}
fn start_waiter(waiter &Waiter, operation Operation, cookie usize) {
	unsafe { waiter.operation = operation; waiter.cookie = cookie; check(C.pthread_create(&waiter.thread, nil, wait_actor, waiter) == 0, @LINE) }
	await32(&waiter.entered, 1)
}
fn wait_actor(argument voidptr) voidptr {
	unsafe {
		waiter := &Waiter(argument); context().waiter = waiter
		C.rcuh_store32(&waiter.entered, 1)
		match waiter.operation {
			.synchronize { C.synchronize_rcu() }
			.expedited { C.synchronize_rcu_expedited() }
			.barrier { C.rcu_barrier() }
			.conditional { C.cond_synchronize_rcu(waiter.cookie) }
		}
		check(may_sleep(), @LINE); C.rcuh_store32(&waiter.done, 1)
		C.pthread_exit(nil)
		return nil
	}
}
fn join_waiter(waiter &Waiter) { check(C.pthread_join(waiter.thread, unsafe { nil }) == 0 && C.rcuh_load32(&waiter.done) == 1, @LINE) }

fn test_bootstrap(mode i32) {
	unsafe {
		check(!C.vkr_rcu_ready() && C.rcuh_head_bytes() == 16 && C.rcuh_head_alignment() == 8, @LINE)
		before := C.rcuh_load32(&allocation_calls)
		C.rcuh_store32(&smp_transport_ready, 0)
		check(C.vkr_rcu_bootstrap(configured_cpus) == -22, @LINE)
		C.rcuh_store32(&smp_transport_ready, 1)
		check(C.vkr_rcu_bootstrap(0) == -22 && C.vkr_rcu_bootstrap(257) == -22 && C.vkr_rcu_bootstrap(configured_cpus - 1) == -22, @LINE)
		ctx := context(); ctx.constructor = false
		check(C.vkr_rcu_bootstrap(configured_cpus) == -1, @LINE); ctx.constructor = true
		saved := irq_save(); check(C.vkr_rcu_bootstrap(configured_cpus) == -1 && (ctx.flags & 512) == 0, @LINE); irq_restore(saved)
		preempt_disable(); check(C.vkr_rcu_bootstrap(configured_cpus) == -1 && ctx.pins == 1, @LINE); preempt_enable()
		ctx.depth = 1; check(C.vkr_rcu_bootstrap(configured_cpus) == -1, @LINE); ctx.depth = 0
		check(C.rcuh_load32(&allocation_calls) == before && C.rcuh_load32(&worker_live) == 0 && C.rcuh_load32(&context_live) == 1, @LINE)
		if mode != 0 {
			if mode <= 2 { allocation_fail_after = mode - 1 } else { create_fail_after = mode - 3 }
			check(C.vkr_rcu_bootstrap(configured_cpus) == -12 && !C.vkr_rcu_ready(), @LINE)
			check(C.rcuh_load32(&allocation_live) == 0 && C.rcuh_load32(&worker_live) == 0 && C.rcuh_load32(&context_live) == 1, @LINE)
			check(C.rcuh_load32(&worker_enters) == C.rcuh_load32(&worker_exits), @LINE)
		}
		allocation_fail_after = -1; create_fail_after = -1
		check(C.vkr_rcu_bootstrap(configured_cpus) == 0 && C.vkr_rcu_ready(), @LINE)
		check(C.rcuh_load32(&allocation_live) == 2 && C.rcuh_load32(&worker_live) == 2 && C.rcuh_load32(&context_live) == 3, @LINE)
		before_reuse := C.rcuh_load32(&allocation_calls)
		check(C.vkr_rcu_bootstrap(configured_cpus) == -114 && C.rcuh_load32(&allocation_calls) == before_reuse, @LINE)
	}
}

fn test_cookie_boundaries() {
	// Literal results from Linux 6.6.157 kernel/rcu/rcu.h:164 and the original
	// unsigned ULONG_CMP macros. Call the actual generated production helper;
	// no live epoch is manufactured and no comparison algorithm lives here.
	unsafe {
		for entry in [
			CookieBoundary{observed: 0, cookie: 4, expected: false},
			CookieBoundary{observed: 1, cookie: 8, expected: false},
			CookieBoundary{observed: 4, cookie: 4, expected: true},
			CookieBoundary{observed: 7, cookie: 8, expected: false},
			CookieBoundary{observed: 8, cookie: 8, expected: true},
			CookieBoundary{observed: 9, cookie: 8, expected: true},
			CookieBoundary{observed: 0, cookie: 8, expected: true},
			CookieBoundary{observed: 0xfffffffffffffff9, cookie: 0, expected: false},
			CookieBoundary{observed: 0xfffffffffffffff8, cookie: 0, expected: true},
			CookieBoundary{observed: 0xffffffffffffffff, cookie: 0, expected: false},
			CookieBoundary{observed: 0, cookie: 0, expected: true},
			CookieBoundary{observed: 0xfffffffffffffffc, cookie: 0, expected: false},
			CookieBoundary{observed: 0, cookie: 0xfffffffffffffffc, expected: true},
			CookieBoundary{observed: 0xffffffffffffffff, cookie: 4, expected: false},
			CookieBoundary{observed: 0xfffffffffffffffc, cookie: 4, expected: true},
			CookieBoundary{observed: 0xfffffffffffffff9, cookie: 0xfffffffffffffffc, expected: false},
			CookieBoundary{observed: 0xfffffffffffffff4, cookie: 0xfffffffffffffffc, expected: true},
			CookieBoundary{observed: 0x8000000000000000, cookie: 0, expected: true},
			CookieBoundary{observed: 0x8000000000000001, cookie: 0, expected: true},
			CookieBoundary{observed: 0x7fffffffffffffff, cookie: 0, expected: true},
			CookieBoundary{observed: 0, cookie: 0x8000000000000000, expected: true},
			CookieBoundary{observed: 0, cookie: 0x8000000000000001, expected: true},
			CookieBoundary{observed: 0, cookie: 0x7fffffffffffffff, expected: true},
			CookieBoundary{observed: 0x8000000000000000, cookie: 0x8000000000000001, expected: false},
			CookieBoundary{observed: 0x8000000000000000, cookie: 0x8000000000000007, expected: false},
			CookieBoundary{observed: 0x8000000000000000, cookie: 0x8000000000000008, expected: true},
		]! {
			check(C.compatcore__rcu_sequence_exact_done(entry.observed, entry.cookie) == entry.expected, @LINE)
		}
	}
}

fn test_reader(kind u32, cpu u32) {
	unsafe {
		route(cpu); mut ledger := Ledger{}; mut node := Node{ledger: &ledger}; mut waiter := Waiter{}
		if kind == 0 { C.rcuh_read_lock(); C.rcuh_read_lock() }
		if kind == 1 || kind == 3 { preempt_disable(); preempt_disable() }
		mut saved := usize(0)
		if kind == 2 || kind == 3 { saved = irq_save() }
		before := C.rcuh_load64(&ipi_attempts[cpu])
		cookie := C.get_state_synchronize_rcu()
		C.call_rcu(&node.head, callback); start_waiter(&waiter, .synchronize, 0)
		await_attempt(cpu, before)
		check(C.rcuh_load32(&ledger.calls) == 0 && C.rcuh_load32(&waiter.done) == 0 && !C.poll_state_synchronize_rcu(cookie), @LINE)
		if kind == 0 { C.rcuh_read_unlock(); check(context().pins == 1, @LINE) }
		if kind == 1 || kind == 3 { preempt_enable(); check(context().pins == 1, @LINE) }
		before_inner := C.rcuh_load64(&ipi_attempts[cpu]); await_attempt(cpu, before_inner)
		check(C.rcuh_load32(&ledger.calls) == 0 && C.rcuh_load32(&waiter.done) == 0, @LINE)
		if kind == 0 { C.rcuh_read_unlock() }
		if kind == 1 || kind == 3 { preempt_enable() }
		if kind == 3 {
			check(context().pins == 0 && (context().flags & 512) == 0, @LINE)
			before_unpin := C.rcuh_load64(&ipi_attempts[cpu]); await_attempt(cpu, before_unpin)
			check(C.rcuh_load32(&ledger.calls) == 0 && C.rcuh_load32(&waiter.done) == 0, @LINE)
		}
		if kind == 2 || kind == 3 { irq_restore(saved) }
		join_waiter(&waiter); await32(&ledger.terminal, 1); C.rcu_barrier()
		check(C.poll_state_synchronize_rcu(cookie) && ledger.calls == 1 && may_sleep(), @LINE)
		route(0)
	}
}

fn test_cookies() {
	unsafe {
		route(1); preempt_disable()
		before := C.rcuh_load64(&ipi_attempts[1])
		second_cpu := if configured_cpus > 2 { u32(2) } else { u32(0) }
		before_return := returns(second_cpu)
		first := C.start_poll_synchronize_rcu(); await_attempt(1, before)
		await_return(second_cpu, before_return)
		// This CPU has genuinely reported the first period, then enters a new
		// read scope before the later cookie is captured.
		mut second := Reader{cpu: second_cpu}
		check(C.pthread_create(&second.thread, nil, reader_actor, &second) == 0, @LINE)
		await32(&second.ready, 1)
		// This snapshot occurs inside an already-requested period. It requires
		// a subsequent full period, not merely the first period's completion.
		later := C.get_state_synchronize_rcu()
		requested := C.start_poll_synchronize_rcu()
		check(!C.poll_state_synchronize_rcu(first) && !C.poll_state_synchronize_rcu(later) && !C.poll_state_synchronize_rcu(requested), @LINE)
		preempt_enable(); await_poll(first)
		check(!C.poll_state_synchronize_rcu(later) && !C.poll_state_synchronize_rcu(requested), @LINE)
		mut pending := Waiter{}; start_waiter(&pending, .conditional, later)
		await32(&pending.parks, 1); check(C.rcuh_load32(&pending.done) == 0, @LINE)
		C.rcuh_store32(&second.quit, 1); check(C.pthread_join(second.thread, nil) == 0, @LINE)
		await_poll(requested); join_waiter(&pending); check(C.poll_state_synchronize_rcu(later), @LINE)
		preempt_disable()
		mut conditional := Waiter{}; start_waiter(&conditional, .conditional, later); join_waiter(&conditional)
		check(context().pins == 1, @LINE); preempt_enable(); route(0)
	}
}
fn reader_actor(argument voidptr) voidptr {
	unsafe {
		reader := &Reader(argument); context(); route(reader.cpu); C.rcuh_read_lock()
		C.rcuh_store32(&reader.ready, 1)
		for C.rcuh_load32(&reader.quit) == 0 { C.sched_yield() }
		C.rcuh_read_unlock(); check(may_sleep(), @LINE); C.pthread_exit(nil)
		return nil
	}
}
fn new_freeing_node(ledger &Ledger, remaining u32) &Node {
	unsafe {
		node := &Node(C.calloc(1, sizeof(Node))); check(node != nil, @LINE)
		node.ledger = ledger; node.remaining = remaining; node.free_self = true
		return node
	}
}
fn test_self_free() {
	mut freed := Ledger{}
	for index := u32(0); index < 200; index++ {
		node := new_freeing_node(unsafe { &freed }, 1)
		C.call_rcu(&node.head, callback)
	}
	C.rcu_barrier(); check(freed.calls == 200 && freed.freed == 200 && freed.terminal == 200, @LINE)
	mut recursive := Ledger{}
	node := new_freeing_node(unsafe { &recursive }, 20)
	C.call_rcu(&node.head, callback)
	await32(&recursive.terminal, 20); C.rcu_barrier(); check(recursive.calls == 20 && recursive.freed == 1, @LINE)
}
fn test_single_cpu() {
	mut empty := Waiter{}
	preempt_disable(); start_waiter(&empty, .barrier, 0); join_waiter(&empty)
	check(context().pins == 1, @LINE); preempt_enable()
	mut ledger := Ledger{}
	node := new_freeing_node(unsafe { &ledger }, 1)
	preempt_disable()
	before := attempts(0); cookie := C.start_poll_synchronize_rcu()
	C.call_rcu(&node.head, callback); await_attempt(0, before)
	check(C.rcuh_load32(&ledger.calls) == 0 && !C.poll_state_synchronize_rcu(cookie), @LINE)
	preempt_enable(); await_poll(cookie); C.rcu_barrier()
	check(ledger.calls == 1 && ledger.terminal == 1 && ledger.freed == 1, @LINE)
	old := C.get_state_synchronize_rcu(); C.synchronize_rcu_expedited()
	check(C.poll_state_synchronize_rcu(old), @LINE); C.cond_synchronize_rcu(old)
	test_self_free()
}
fn test_callbacks() {
	unsafe {
		mut ledger := Ledger{order: &batch_order[0]}; order_next = 0
		route(1); preempt_disable()
		for index := u32(0); index < 4097; index++ { batch[index] = Node{ledger: &ledger,index: index}; C.call_rcu(&batch[index].head, callback) }
		check(ledger.calls == 0, @LINE); preempt_enable(); route(0)
		C.rcu_barrier(); check(ledger.calls == 4097 && ledger.terminal == 4097, @LINE)
		for index := u32(0); index < 4097; index++ { check(batch_order[index] == index, @LINE) }
		test_self_free()
		mut atomic_ledger := Ledger{}; mut atomic_node := Node{ledger: &atomic_ledger}
		before := C.rcuh_load32(&allocation_calls); allocation_fail_after = 0
		preempt_disable(); saved := irq_save(); C.call_rcu(&atomic_node.head, callback)
		check(allocation_fail_after == 0 && C.rcuh_load32(&allocation_calls) == before && context().pins == 1 && (context().flags & 512) == 0, @LINE)
		irq_restore(saved); preempt_enable(); allocation_fail_after = -1; C.rcu_barrier(); check(atomic_ledger.calls == 1, @LINE)
	}
}
fn test_barriers() {
		route(1); preempt_disable()
		mut empty := Waiter{}; start_waiter(&empty, .barrier, 0); join_waiter(&empty)
		check(context().pins == 1, @LINE); preempt_enable(); route(0)
		mut ledger := Ledger{release: 0}
		mut node := new_freeing_node(unsafe { &ledger }, 1)
		node.free_before_wait = true
		C.call_rcu(&node.head, callback); await32(&ledger.entered, 1)
		check(C.rcuh_load32(&ledger.freed) == 1 && C.rcuh_load32(&ledger.terminal) == 0, @LINE)
		mut waiters := [20]Waiter{}
		for index := 0; index < 20; index++ { start_waiter(unsafe { &waiters[index] }, .barrier, 0); await32(unsafe { &waiters[index].parks }, 1) }
		mut normal := Waiter{}; mut expedited := Waiter{}
		start_waiter(&normal, .synchronize, 0); start_waiter(&expedited, .expedited, 0)
		await32(&normal.parks, 1); await32(&expedited.parks, 1)
		before := attempts(0); await_attempt(0, before)
		for index := 0; index < 20; index++ { check(C.rcuh_load32(unsafe { &waiters[index].done }) == 0, @LINE) }
		// The paused callback's genuine preemption pin is itself an implicit
		// reader; a later synchronize is allowed to wait for its return.
		check(C.rcuh_load32(&normal.done) == 0 && C.rcuh_load32(&expedited.done) == 0, @LINE)
		// Each old barrier has reached its real wait after taking the ordinal
		// snapshot. A later callback is excluded by this backend's stronger
		// snapshot contract; Linux does not require that stronger exclusion.
		route(1); preempt_disable()
		mut later := Ledger{}
		late_node := new_freeing_node(unsafe { &later }, 1)
		C.call_rcu(&late_node.head, callback)
		C.rcuh_store32(&ledger.release, 1)
		for index := 0; index < 20; index++ { join_waiter(unsafe { &waiters[index] }) }
		check(C.rcuh_load32(&later.calls) == 0 && C.rcuh_load32(&later.freed) == 0 && context().pins == 1, @LINE)
		preempt_enable(); route(0)
		join_waiter(&normal); join_waiter(&expedited); C.rcu_barrier()
		check(ledger.calls == 1 && ledger.terminal == 1 && later.calls == 1 && later.freed == 1, @LINE)
}

fn invalid_callback(_head &C.callback_head) { C.rcu_barrier(); check(false, @LINE) }
fn test_invalid_context(mode i32) {
	unsafe {
		match mode {
			10 { C.rcuh_read_lock(); C.synchronize_rcu() }
			11 { irq_save(); C.synchronize_rcu_expedited() }
			12 { context().depth = 1; C.synchronize_rcu() }
			13 { mut node := Node{}; C.call_rcu(&node.head, invalid_callback); for { pause() } }
			14 { irq_save(); C.start_poll_synchronize_rcu() }
			15 { cookie := C.get_state_synchronize_rcu(); C.rcuh_read_lock(); C.cond_synchronize_rcu(cookie) }
			else { check(false, @LINE) }
		}
		check(false, @LINE)
	}
}

@[export: 'main'] pub fn main(argc i32, argv &&char) i32 {
	unsafe {
		check(argc == 3 && C.pthread_key_create(&context_key, context_destructor) == 0, @LINE)
		configured_cpus = u32(C.atoi(argv[1])); mode := C.atoi(argv[2])
		check(configured_cpus >= 1 && configured_cpus <= 256 && ((mode >= 0 && mode <= 4) || (mode >= 10 && mode <= 15)), @LINE)
		context().constructor = true
		test_cookie_boundaries()
		check(C.vkm_cpu_masks_bootstrap(configured_cpus) == 0, @LINE)
		C.rcuh_store32(&smp_transport_ready, 1); test_bootstrap(if mode < 10 { mode } else { 0 })
		if mode >= 10 { test_invalid_context(mode) }
		if configured_cpus == 1 {
			test_single_cpu()
		} else {
			for kind := u32(0); kind < 4; kind++ { test_reader(kind, 1) }
			for selected in [u32(0), configured_cpus - 1, u32(63), u32(64), u32(127), u32(128), u32(255)]! {
				if selected < configured_cpus { test_reader(1, selected) }
			}
			test_cookies(); test_callbacks(); test_barriers()
		}
		C.vkr_rcu_shutdown_for_test()
		check(!C.vkr_rcu_ready() && C.rcuh_load32(&allocation_live) == 0 && C.rcuh_load32(&worker_live) == 0 && C.rcuh_load32(&context_live) == 1, @LINE)
		check(C.rcuh_load32(&worker_enters) == C.rcuh_load32(&worker_exits) && C.rcuh_load32(&retirement_queries) >= 2, @LINE)
		owner := context(); check(C.pthread_setspecific(context_key, nil) == 0, @LINE); context_destructor(owner)
		check(C.rcuh_load32(&context_live) == 0 && C.pthread_key_delete(context_key) == 0, @LINE)
		C.printf(c'PASS: %u CPU original RCU heads, implicit scopes, cookies, callbacks, barriers, mode %d; %u assertions\n', configured_cpus, mode, C.rcuh_load32(&assertions))
		return 0
	}
}
