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
import x86.hpet as hpet_clock

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
fn C.vinix_linuxkpi_percpu_bootstrap(u32) int

pub fn initialise() {
	$if linuxkpi ? {
		sched.register_preemption_guard(voidptr(may_preempt))
		if C.vinix_linuxkpi_percpu_bootstrap(u32(cpu_locals.len)) != 0 {
			lib.kpanic(unsafe { nil }, c'Linux compatibility per-CPU initialization failed')
		}
		C.i915_memcpy_init_early(unsafe { nil })
		before := memory.free_bytes()
		for _ in 0 .. 200 {
			if C.vinix_linuxkpi_selftest() != 0 {
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
