// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import memory
import pci
import lib
import x86.cpu
import x86.cpu.local as cpulocal
import sched
import proc
import klock
import katomic
import x86.hpet as hpet_clock
import time

__global (
	preempt_depth     [256]u32
	preempt_pending   [256]bool
	preempt_deferrals [256]u64
	fpu_borrowed      [256]bool
)

fn may_preempt() bool {
	index := cpulocal.current().cpu_number
	if preempt_depth[index] != 0 {
		preempt_pending[index] = true
		preempt_deferrals[index]++
		return false
	}
	preempt_pending[index] = false
	return true
}

@[export: 'vinix_linuxkpi_preempt_disable']
fn preempt_disable() {
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	if preempt_depth[index] == u32(-1) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: preemption depth overflow')
	}
	preempt_depth[index]++
	cpu.interrupt_toggle(ints)
}

@[export: 'vinix_linuxkpi_preempt_enable']
fn preempt_enable() {
	release_preemption(true)
}

@[export: 'vinix_linuxkpi_preempt_enable_no_resched']
fn preempt_enable_no_resched() {
	release_preemption(false)
}

fn release_preemption(allow_reschedule bool) {
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	if preempt_depth[index] == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unbalanced preempt_enable')
	}
	preempt_depth[index]--
	reschedule := allow_reschedule && preempt_depth[index] == 0 && preempt_pending[index]
		&& ints
	if reschedule {
		preempt_pending[index] = false
	}
	cpu.interrupt_toggle(ints)
	if reschedule {
		sched.reschedule()
	}
}

@[export: 'vinix_linuxkpi_preempt_count']
fn native_preempt_count() u32 {
	ints := cpu.interrupt_toggle(false)
	depth := preempt_depth[cpulocal.current().cpu_number]
	cpu.interrupt_toggle(ints)
	return depth
}

@[export: 'vinix_linuxkpi_cpu_id']
fn native_cpu_id() u32 {
	ints := cpu.interrupt_toggle(false)
	index := u32(cpulocal.current().cpu_number)
	cpu.interrupt_toggle(ints)
	return index
}

@[export: 'vinix_linuxkpi_preempt_check_resched']
fn preempt_check_resched() {
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	reschedule := ints && preempt_depth[index] == 0 && preempt_pending[index]
	if reschedule {
		preempt_pending[index] = false
	}
	cpu.interrupt_toggle(ints)
	if reschedule {
		sched.reschedule()
	}
}

fn C.vinix_linuxkpi_task_view(voidptr, voidptr, int, int, voidptr, u64, bool) voidptr
fn C.vinix_linuxkpi_task_selftest() int

@[export: 'vinix_linuxkpi_current_task']
fn current_task() voidptr {
	mut t := proc.current_thread()
	if t == unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'linuxkpi: current requested without a running thread')
	}
	name := t.comm
	exiting := katomic.load(&t.must_exit) || katomic.load(&t.exit_claimed) != 0
	return C.vinix_linuxkpi_task_view(voidptr(&t.linuxkpi_task[0]), voidptr(t), t.tid,
		t.process.pid, name.str, u64(name.len), exiting)
}

@[export: 'vinix_linuxkpi_task_signal_pending']
fn task_signal_pending(owner voidptr, fatal bool) bool {
	t := unsafe { &proc.Thread(owner) }
	pending := katomic.load(&t.pending_signals)
	if katomic.load(&t.must_exit) || pending & (u64(1) << 8) != 0 {
		return true
	}
	return !fatal && pending & ~katomic.load(&t.masked_signals) != 0
}

@[export: 'vinix_linuxkpi_task_get']
fn task_get(owner voidptr) {
	proc.pin_thread(unsafe { &proc.Thread(owner) })
}

@[export: 'vinix_linuxkpi_task_put']
fn task_put(owner voidptr) {
	proc.unpin_thread(unsafe { &proc.Thread(owner) })
	// Last put must also collect when no subsequent thread exits.
	sched.reap_deferred()
}

@[export: 'vinix_linuxkpi_task_is_dead']
fn task_is_dead(owner voidptr) bool {
	t := unsafe { &proc.Thread(owner) }
	return katomic.load(&t.is_dead)
}

@[export: 'vinix_linuxkpi_task_queued']
fn task_queued(owner voidptr) bool {
	t := unsafe { &proc.Thread(owner) }
	return katomic.load(&t.is_in_queue)
}

// Self-test injection follows native signal publication/enqueue ordering.
@[export: 'vinix_linuxkpi_test_task_signal']
fn test_task_signal(owner voidptr, pending u64) {
	mut t := unsafe { &proc.Thread(owner) }
	katomic.store(mut &t.pending_signals, pending)
	if pending != 0 {
		sched.enqueue_thread(t, true)
	}
}

@[export: 'vinix_linuxkpi_task_enqueue']
fn task_enqueue(owner voidptr) bool {
	return sched.enqueue_thread(unsafe { &proc.Thread(owner) }, false)
}

@[export: 'vinix_linuxkpi_task_dequeue']
fn task_dequeue(owner voidptr) {
	assert owner == voidptr(proc.current_thread())
	sched.dequeue_thread(unsafe { &proc.Thread(owner) })
}

@[export: 'vinix_linuxkpi_task_park']
fn task_park() {
	assert may_sleep()
	sched.yield(true)
}

@[export: 'vinix_linuxkpi_need_resched']
fn need_resched() bool {
	ints := cpu.interrupt_toggle(false)
	needed := preempt_pending[cpulocal.current().cpu_number]
	cpu.interrupt_toggle(ints)
	return needed
}

@[export: 'vinix_linuxkpi_cond_resched']
fn cond_resched() int {
	if !may_sleep() {
		return 0
	}
	// A voluntary yield is valid even when the timer already preempted us.
	// No preemption pin or IRQ-off section may cross this scheduling point.
	sched.reschedule()
	return 1
}

fn C.vinix_linuxkpi_selftest() int
fn C.vinix_linuxkpi_tigerlake_id(u16, u16, u32) bool

@[export: 'vinix_linuxkpi_alloc_pages']
fn alloc_pages(count u64, reclaim bool) voidptr {
	phys := if reclaim {
		memory.pmm_alloc_nozero_fallible(count)
	} else {
		memory.pmm_alloc_nozero_nowait(count)
	}
	if phys == unsafe { nil } {
		return unsafe { nil }
	}
	return voidptr(u64(phys) + higher_half)
}

@[export: 'vinix_linuxkpi_may_sleep']
fn may_sleep() bool {
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	allowed := ints && preempt_depth[index] == 0
	cpu.interrupt_toggle(ints)
	return allowed
}

@[export: 'vinix_linuxkpi_free_pages']
fn free_pages(base voidptr, count u64) {
	memory.pmm_free(voidptr(u64(base) - higher_half), count)
}

@[export: 'vinix_linuxkpi_page_size']
fn native_page_size() u64 {
	return page_size
}

@[export: 'vinix_linuxkpi_irq_save']
fn irq_save() u64 {
	return if cpu.interrupt_toggle(false) { u64(1) << 9 } else { u64(0) }
}

@[export: 'vinix_linuxkpi_irq_flags']
fn irq_flags() u64 {
	return if cpu.interrupt_state() { u64(1) << 9 } else { u64(0) }
}

@[export: 'vinix_linuxkpi_irq_restore']
fn irq_restore(flags u64) {
	index := cpulocal.current().cpu_number
	ints := flags & (u64(1) << 9) != 0
	reschedule := ints && preempt_depth[index] == 0 && preempt_pending[index]
	if reschedule {
		preempt_pending[index] = false
	}
	cpu.interrupt_toggle(ints)
	if reschedule {
		sched.reschedule()
	}
}

@[export: 'vinix_linuxkpi_spin_wait']
fn spin_wait() {
	// Locks with IRQs disabled must still answer pending TLB shootdowns.
	klock.spin_hint()
}

@[export: 'vinix_linuxkpi_bug']
fn bug(_file &char, _line int) {
	lib.kpanic(unsafe { nil }, c'Linux compatibility layer BUG')
}

@[export: 'vinix_linuxkpi_warn']
fn warn(file &char, line int) {
	C.kprintf(c'linuxkpi: warning at %s:%d\n', file, line)
}

@[export: 'vinix_linuxkpi_clock_ns']
fn clock_ns() u64 {
	return hpet_clock.nanoseconds()
}

@[export: 'vinix_linuxkpi_clock_resolution_ns']
fn clock_resolution_ns() u32 {
	return hpet_clock.resolution_nanoseconds()
}

fn C.vinix_linuxkpi_time_tick(u64)

fn tick_deadlines() {
	C.vinix_linuxkpi_time_tick(hpet_clock.nanoseconds())
}

@[export: 'vinix_linuxkpi_refcount_warning']
fn refcount_warning(kind int) {
	C.kprintf(c'linuxkpi: refcount saturated after invalid operation %d; retaining object\n', kind)
}

@[export: 'vinix_linuxkpi_cpu_has']
fn cpu_has(feature u32) bool {
	// Linux's feature word 0 is leaf 1 EDX; word 4 is leaf 1 ECX.
	ok, _, _, ecx, edx := cpu.cpuid(1, 0)
	if !ok {
		return false
	}
	bits := match feature / 32 {
		0 { edx }
		4 { ecx }
		else {
			lib.kpanic(unsafe { nil }, c'linuxkpi: unsupported CPU feature word')
			u32(0)
		}
	}
	return bits & (u32(1) << (feature % 32)) != 0
}

@[export: 'vinix_linuxkpi_fpu_begin']
fn fpu_begin() {
	preempt_disable()
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	index := local.cpu_number
	borrower := proc.current_thread()
	if fpu_borrowed[index] || borrower == unsafe { nil }
		|| borrower.fpu_storage == unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid kernel FPU borrow')
	}
	// The running thread already owns aligned XSAVE/FXSAVE storage. Keeping
	// preemption disabled pins that owner until all its registers are restored.
	fpu_borrowed[index] = true
	fpu_save(borrower.fpu_storage)
	cpu.interrupt_toggle(ints)
}

@[export: 'vinix_linuxkpi_fpu_end']
fn fpu_end() {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	index := local.cpu_number
	if !fpu_borrowed[index] {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unbalanced kernel FPU end')
	}
	fpu_restore(proc.current_thread().fpu_storage)
	fpu_borrowed[index] = false
	cpu.interrupt_toggle(ints)
	preempt_enable()
}

fn C.i915_memcpy_init_early(voidptr)
fn C.vinix_linuxkpi_wc_selftest() int
fn C.vinix_linuxkpi_task_native_selftest() int
fn C.vinix_linuxkpi_sync_selftest() int
fn C.vinix_linuxkpi_sync_native_selftest() int
fn C.vinix_linuxkpi_time_selftest() int
fn C.vinix_linuxkpi_time_native_selftest() int
fn C.vinix_linuxkpi_percpu_bootstrap(u32) int

pub fn initialise() {
	$if linuxkpi ? {
		sched.register_preemption_guard(voidptr(may_preempt))
		if C.vinix_linuxkpi_percpu_bootstrap(u32(cpu_locals.len)) != 0 {
			lib.kpanic(unsafe { nil }, c'Linux compatibility per-CPU initialization failed')
		}
		C.i915_memcpy_init_early(unsafe { nil })
		tick_deadlines()
		if !time.register_tick_hook(tick_deadlines) {
			lib.kpanic(unsafe { nil }, c'Linux compatibility timer hook registration failed')
		}
		before := memory.free_bytes()
		for _ in 0 .. 200 {
			if C.vinix_linuxkpi_selftest() != 0 || C.vinix_linuxkpi_task_selftest() != 0
				|| C.vinix_linuxkpi_sync_selftest() != 0 || C.vinix_linuxkpi_time_selftest() != 0 {
				lib.kpanic(unsafe { nil }, c'Linux compatibility layer self-test failed')
			}
		}
		if memory.free_bytes() != before {
			lib.kpanic(unsafe { nil }, c'Linux compatibility layer self-test leaked pages')
		}
		C.kprintf(c'linuxkpi: 200 allocator, IRQ lock, Linux list/sort/rbtree self-tests passed; no pages retained\n')
		C.kprintf(c'linuxkpi: raw locks, bitmaps, byte order and bounded strings passed\n')
		C.kprintf(c'linuxkpi: static and dynamic per-CPU isolation passed on %u CPUs\n',
			u32(cpu_locals.len))
		C.kprintf(c'linuxkpi: current task identity and guarded voluntary rescheduling passed\n')
		// A stack-only probe exercises the native counters without retaining a
		// real saturated Thread. Never publish this object to the scheduler.
		mut ref_probe := proc.Thread{}
		proc.pin_thread(unsafe { &ref_probe })
		if ref_probe.pins != 1 {
			lib.kpanic(unsafe { nil }, c'Native thread reference acquire failed')
		}
		proc.unpin_thread(unsafe { &ref_probe })
		if ref_probe.pins != 0 {
			lib.kpanic(unsafe { nil }, c'Native thread reference release failed')
		}
		ref_probe.pins = 0x7ffffffe
		proc.pin_thread(unsafe { &ref_probe })
		proc.pin_thread(unsafe { &ref_probe })
		proc.unpin_thread(unsafe { &ref_probe })
		if ref_probe.pins != 0x7fffffff {
			lib.kpanic(unsafe { nil }, c'Native thread references did not saturate')
		}
		// Warm the native Thread slab on the CPUs used by the worker test.
		for _ in 0 .. 3 {
			if C.vinix_linuxkpi_task_native_selftest() != 0 {
				lib.kpanic(unsafe { nil }, c'Linux task wait/reference self-test failed')
			}
		}
		task_before := memory.free_bytes()
		if C.vinix_linuxkpi_task_native_selftest() != 0 {
			lib.kpanic(unsafe { nil }, c'Linux task wait/reference self-test failed')
		}
		// join publishes its result before the target finishes switching away.
		// Give that final scheduler reaper a chance to finish on another CPU.
		reap_start := hpet_clock.nanoseconds()
		for memory.free_bytes() != task_before && hpet_clock.nanoseconds() - reap_start < 1000000000 {
			sched.reap_deferred()
			sched.reschedule()
		}
		if memory.free_bytes() != task_before {
			lib.kpanic(unsafe { nil }, c'Linux task self-test retained native pages')
		}
		C.kprintf(c'linuxkpi: blocking wakeups, join/detach and 70 retained exited tasks passed; no pages retained\n')
		for _ in 0 .. 3 {
			if C.vinix_linuxkpi_sync_native_selftest() != 0 {
				lib.kpanic(unsafe { nil }, c'Linux synchronization self-test failed')
			}
		}
		sync_before := memory.free_bytes()
		if C.vinix_linuxkpi_sync_native_selftest() != 0 {
			lib.kpanic(unsafe { nil }, c'Linux synchronization self-test failed')
		}
		sync_reap_start := hpet_clock.nanoseconds()
		for memory.free_bytes() != sync_before && hpet_clock.nanoseconds() - sync_reap_start < 1000000000 {
			sched.reap_deferred()
			sched.reschedule()
		}
		if memory.free_bytes() != sync_before {
			lib.kpanic(unsafe { nil }, c'Linux synchronization self-test retained native pages')
		}
		C.kprintf(c'linuxkpi: sleeping mutexes, wait queues and completions passed on 4 workers; no pages retained\n')
		for _ in 0 .. 3 {
			if C.vinix_linuxkpi_time_native_selftest() != 0 {
				lib.kpanic(unsafe { nil }, c'Linux timed-wait self-test failed')
			}
		}
		time_before := memory.free_bytes()
		if C.vinix_linuxkpi_time_native_selftest() != 0 {
			lib.kpanic(unsafe { nil }, c'Linux timed-wait self-test failed')
		}
		time_reap_start := hpet_clock.nanoseconds()
		for memory.free_bytes() != time_before && hpet_clock.nanoseconds() - time_reap_start < 1000000000 {
			sched.reap_deferred()
			sched.reschedule()
		}
		if memory.free_bytes() != time_before {
			lib.kpanic(unsafe { nil }, c'Linux timed-wait self-test retained native pages')
		}
		C.kprintf(c'linuxkpi: monotonic clocks and timed task/queue/completion waits passed on 4 workers; no pages retained\n')
		// Exercise a real scheduler interrupt with preemption disabled and
		// IRQs still enabled, rather than relying only on host lock tests.
		preempt_disable()
		ints := cpu.interrupt_toggle(false)
		index := cpulocal.current().cpu_number
		deferred_before := preempt_deferrals[index]
		cpu.interrupt_toggle(ints)
		start := hpet_clock.nanoseconds()
		for hpet_clock.nanoseconds() - start < 20000000 {
			klock.spin_hint()
		}
		cpu.interrupt_toggle(false)
		deferred := preempt_deferrals[index] > deferred_before
		preempt_enable_no_resched()
		no_resched_balanced := preempt_depth[index] == 0 && preempt_pending[index]
		if !no_resched_balanced {
			lib.kpanic(unsafe { nil }, c'Linux compatibility no-resched lost pending preemption')
		}
		irq_restore(if ints { u64(1) << 9 } else { u64(0) })
		if !deferred {
			lib.kpanic(unsafe { nil }, c'Linux compatibility preemption guard was not exercised')
		}
		C.kprintf(c'linuxkpi: scheduler deferred preemption while IRQs stayed enabled\n')
		C.kprintf(c'linuxkpi: no-resched preserved pending preemption\n')
		if C.vinix_linuxkpi_wc_selftest() != 0 {
			lib.kpanic(unsafe { nil }, c'Linux i915 WC copy or FPU preservation failed')
		}
		dev := pci.get_device_by_vendor(0x8086, 0x9a49, 0) or { return }
		class_code := (u32(dev.class) << 16) | (u32(dev.subclass) << 8) | u32(dev.prog_if)
		if C.vinix_linuxkpi_tigerlake_id(dev.vendor_id, dev.device_id, class_code) {
			C.kprintf(c'linuxkpi: Tiger Lake 8086:9a49 found at %02llx:%02llx.%llx; i915 compatibility incomplete, driver not bound\n',
				u64(dev.bus), u64(dev.slot), u64(dev.function))
		}
	}
}
