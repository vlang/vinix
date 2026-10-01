// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import memory
import pci
import lib
import x86.cpu
import x86.cpu.local as cpulocal
import sched
import klock
import x86.hpet as hpet_clock

__global (
	preempt_depth     [256]u32
	preempt_pending   [256]bool
	preempt_deferrals [256]u64
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
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	if preempt_depth[index] == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unbalanced preempt_enable')
	}
	preempt_depth[index]--
	reschedule := preempt_depth[index] == 0 && preempt_pending[index] && ints
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

pub fn initialise() {
	$if linuxkpi ? {
		sched.register_preemption_guard(voidptr(may_preempt))
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
		cpu.interrupt_toggle(ints)
		preempt_enable()
		if !deferred {
			lib.kpanic(unsafe { nil }, c'Linux compatibility preemption guard was not exercised')
		}
		C.kprintf(c'linuxkpi: scheduler deferred preemption while IRQs stayed enabled\n')
		dev := pci.get_device_by_vendor(0x8086, 0x9a49, 0) or { return }
		class_code := (u32(dev.class) << 16) | (u32(dev.subclass) << 8) | u32(dev.prog_if)
		if C.vinix_linuxkpi_tigerlake_id(dev.vendor_id, dev.device_id, class_code) {
			C.kprintf(c'linuxkpi: Tiger Lake 8086:9a49 found at %02llx:%02llx.%llx; i915 compatibility incomplete, driver not bound\n',
				u64(dev.bus), u64(dev.slot), u64(dev.function))
		}
	}
}
