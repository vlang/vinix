// SPDX-License-Identifier: GPL-2.0-or-later
// Boot-only non-RT IRQ work. Callbacks execute on an actual native maskable
// IPI; local lazy work is promoted only by a real PIT tick.
@[translated]
module compatcore

#include "linuxkpi_irq_work_v_primitives.h"

struct C.irq_work {}
struct C.vkiw_work {
mut:
	next &C.vkiw_work
	flags u32
	func fn (&C.irq_work)
}
struct IrqWorkRun {
mut:
	next &IrqWorkRun
	work voidptr
}
fn C.vkiw_load32(&u32, i32) u32
fn C.vkiw_store32(&u32, u32, i32)
fn C.vkiw_or32(&u32, u32, i32) u32
fn C.vkiw_compare32(&u32, &u32, u32, i32, i32) bool
fn C.vkiw_fence(i32)
fn C.vkr_rcu_ready() bool
fn C.vinix_linuxkpi_irqwork_send_ipi(u32)

__global (
	vkiw_published u32
	vkiw_cpu_count u32
	vkiw_guard u32
	vkiw_raised [256]&C.vkiw_work
	vkiw_lazy [256]&C.vkiw_work
	vkiw_running_head &IrqWorkRun
	vkiw_sync_waits u64
)

fn irqwork_flags_valid(flags u32) bool {
	return (flags & ~u32(0x2f)) == 0
		&& ((flags & 3) == 0 || (flags & 0x20) != 0)
		&& ((flags & 1) == 0 || (flags & 2) != 0)
}
fn irqwork_valid_head(storage voidptr) {
	require(!is_null(storage) && usize(storage) % sizeof(voidptr) == 0)
}
fn irqwork_sleepable_context() bool {
	return C.vinix_linuxkpi_may_sleep() && C.vinix_linuxkpi_smp_task_present()
		&& C.vinix_linuxkpi_maskable_irq_depth() == 0 && C.vinix_linuxkpi_preempt_count() == 0
		&& (C.vinix_linuxkpi_irq_flags() & 512) != 0
}
fn irqwork_irq_context(cpu u32) {
	require(irq_work_ready() && cpu < unsafe { vkiw_cpu_count }
		&& cpu == C.vinix_linuxkpi_cpu_id()
		&& (C.vinix_linuxkpi_irq_flags() & 512) == 0
		&& C.vinix_linuxkpi_maskable_irq_depth() != 0)
}
fn irqwork_running_locked(storage voidptr) u32 {
	unsafe {
		mut count := u32(0)
		for run := vkiw_running_head; !is_null(run); run = run.next {
			if run.work == storage { require(count != u32(-1)); count++ }
		}
		return count
	}
}
@[export: 'vkiw_ready']
pub fn irq_work_ready() bool { return unsafe { C.vkiw_load32(&vkiw_published, 2) != 0 } }
@[export: 'vkiw_bootstrap']
pub fn irq_work_bootstrap(count u32) i32 {
	if count == 0 || count > 256 || !C.vkm_cpu_masks_ready() || !C.vks_smp_ready()
		|| !C.vkr_rcu_ready() || count != C.vkm_cpu_ids() || count != C.vkm_online_count() { return -22 }
	if irq_work_ready() { return -114 }
	if !C.vinix_linuxkpi_smp_boot_context() { return -1 }
	unsafe {
		C.vkp_spin_init(&vkiw_guard)
		vkiw_cpu_count = count
		for index in 0 .. 256 { vkiw_raised[index] = nil; vkiw_lazy[index] = nil }
		vkiw_running_head = nil
		vkiw_sync_waits = 0
		C.vkiw_store32(&vkiw_published, 1, 3)
	}
	return 0
}
@[export: 'vkiw_queue']
pub fn irq_work_queue(storage voidptr, requested i32) bool {
	unsafe {
		require(irq_work_ready() && requested >= -1)
		irqwork_valid_head(storage)
		C.vinix_linuxkpi_preempt_disable()
		source := C.vinix_linuxkpi_cpu_id()
		require(source < vkiw_cpu_count)
		target := if requested == -1 { source } else { u32(requested) }
		require(target < vkiw_cpu_count)
		work := &C.vkiw_work(storage)
		lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		flags := C.vkiw_load32(&work.flags, 0)
		require(irqwork_flags_valid(flags) && usize(voidptr(work.func)) >= 4096)
		old := C.vkiw_or32(&work.flags, 0x23, 5)
		if (old & 1) != 0 {
			C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
			C.vinix_linuxkpi_preempt_enable()
			return false
		}
		lazy := target == source && (old & 4) != 0
		raise := !lazy && is_null(vkiw_raised[target])
		if lazy { work.next = vkiw_lazy[target]; vkiw_lazy[target] = work }
		else { work.next = vkiw_raised[target]; vkiw_raised[target] = work }
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
		// Publication can already run and retire the object on another CPU.
		// Only captured scalar routing values remain live in this producer.
		if raise { C.vinix_linuxkpi_irqwork_send_ipi(target) }
		C.vinix_linuxkpi_preempt_enable()
		return true
	}
}
@[export: 'vkiw_single']
pub fn irq_work_single(storage voidptr) {
	unsafe {
		irqwork_valid_head(storage)
		owner_cpu := C.vinix_linuxkpi_cpu_id()
		irqwork_irq_context(owner_cpu)
		entry_depth := C.vinix_linuxkpi_maskable_irq_depth()
		entry_pins := C.vinix_linuxkpi_preempt_count()
		work := &C.vkiw_work(storage)
		mut run := IrqWorkRun{work: storage}
		// Taking this address in the enclosing unsafe scope keeps the native
		// callback record on its dispatch stack rather than boxing it.
		record := &run
		lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		old := C.vkiw_load32(&work.flags, 0)
		require(irqwork_flags_valid(old) && (old & 0x23) == 0x23
			&& usize(voidptr(work.func)) >= 4096)
		callback := work.func
		flags := old & ~u32(1)
		run.next = vkiw_running_head
		vkiw_running_head = record
		C.vkiw_store32(&work.flags, flags, 0)
		C.vkiw_fence(5)
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
		callback(&C.irq_work(storage))
		// The original BUSY transition follows the callback. Its enclosing
		// storage must remain backed through this CAS (RCU self-free is safe).
		require(C.vinix_linuxkpi_cpu_id() == owner_cpu
			&& (C.vinix_linuxkpi_irq_flags() & 512) == 0
			&& C.vinix_linuxkpi_maskable_irq_depth() == entry_depth
			&& C.vinix_linuxkpi_preempt_count() == entry_pins)
		retired_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		mut expected := flags
		C.vkiw_compare32(&work.flags, &expected, flags & ~u32(2), 5, 0)
		mut previous := &IrqWorkRun(nil)
		mut observed := vkiw_running_head
		for !is_null(observed) && usize(observed) != usize(record) {
			previous = observed
			observed = observed.next
		}
		require(!is_null(observed))
		if is_null(previous) { vkiw_running_head = run.next }
		else { previous.next = run.next }
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, retired_flags)
		// No work dereference is permitted after the final BUSY/record update.
	}
}
fn irqwork_run_list(cpu u32, lazy bool) {
	unsafe {
		lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		mut work := if lazy { vkiw_lazy[cpu] } else { vkiw_raised[cpu] }
		if lazy { vkiw_lazy[cpu] = nil } else { vkiw_raised[cpu] = nil }
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
		for !is_null(work) {
			next := work.next
			irq_work_single(work)
			// The detached next pointer is independent of the completed object.
			work = next
		}
	}
}
@[export: 'vkiw_drain']
pub fn irq_work_drain(cpu u32) {
	irqwork_irq_context(cpu)
	irqwork_run_list(cpu, false)
	irqwork_run_list(cpu, true)
}
@[export: 'vkiw_tick']
pub fn irq_work_tick(cpu u32) {
	irqwork_irq_context(cpu)
	irqwork_run_list(cpu, true)
}
@[export: 'vkiw_tick_all']
pub fn irq_work_tick_all() {
	unsafe {
		if !irq_work_ready() { return }
		require((C.vinix_linuxkpi_irq_flags() & 512) == 0
			&& C.vinix_linuxkpi_maskable_irq_depth() != 0)
		for cpu := u32(0); cpu < vkiw_cpu_count; cpu++ {
			lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
			pending := !is_null(vkiw_lazy[cpu])
			C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
			if pending { C.vinix_linuxkpi_irqwork_send_ipi(cpu) }
		}
	}
}
@[export: 'vkiw_needs_cpu']
pub fn irq_work_needs_cpu() bool {
	unsafe {
		require(irq_work_ready())
		lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		cpu := C.vinix_linuxkpi_cpu_id()
		require(cpu < vkiw_cpu_count)
		needed := !is_null(vkiw_lazy[cpu])
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
		return needed
	}
}
@[export: 'vkiw_raise']
pub fn irq_work_raise() {
	require(irq_work_ready())
	C.vinix_linuxkpi_preempt_disable()
	cpu := C.vinix_linuxkpi_cpu_id()
	require(cpu < unsafe { vkiw_cpu_count })
	C.vinix_linuxkpi_irqwork_send_ipi(cpu)
	C.vinix_linuxkpi_preempt_enable()
}
@[export: 'vkiw_running_count']
pub fn irq_work_running_count(storage voidptr) u32 {
	unsafe {
		require(irq_work_ready())
		lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		count := irqwork_running_locked(storage)
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
		return count
	}
}
@[export: 'vkiw_sync_wait_count']
pub fn irq_work_sync_wait_count() u64 {
	unsafe {
		require(irq_work_ready())
		lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
		count := vkiw_sync_waits
		C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
		return count
	}
}
@[export: 'vkiw_sync']
pub fn irq_work_sync(storage voidptr) {
	unsafe {
		require(irq_work_ready() && irqwork_sleepable_context())
		irqwork_valid_head(storage)
		work := &C.vkiw_work(storage)
		for {
			lock_flags := C.vkp_spin_lock_irqsave(&vkiw_guard)
			flags := C.vkiw_load32(&work.flags, 2)
			require(irqwork_flags_valid(flags))
			waiting := (flags & 3) != 0 || irqwork_running_locked(storage) != 0
			if waiting { require(vkiw_sync_waits != u64(-1)); vkiw_sync_waits++ }
			C.vkp_spin_unlock_irqrestore(&vkiw_guard, lock_flags)
			if !waiting { return }
			C.vinix_linuxkpi_spin_wait()
		}
	}
}
