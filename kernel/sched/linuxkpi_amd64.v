// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import katomic
import lib
import proc
import x86.cpu
import x86.cpu.local as cpulocal

__global (
	linuxkpi_iowait_counts [256]u32
)

fn C.vinix_linuxkpi_task_in_iowait(storage voidptr) bool

// IRQs are off and the run-queue lock is held. The reservation contains an
// origin CPU, never a pointer into a sleeping task's stack or a borrowed task.
fn linuxkpi_iowait_end_locked(mut t proc.Thread) {
	$if linuxkpi ? {
		origin := t.linuxkpi_iowait_cpu_plus_one
		if origin == 0 {
			return
		}
		if origin > 256 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: invalid I/O wait origin')
		}
		index := origin - 1
		count := katomic.load(&linuxkpi_iowait_counts[index])
		if count == 0 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: I/O wait count underflow')
		}
		t.linuxkpi_iowait_cpu_plus_one = 0
		katomic.store(mut &linuxkpi_iowait_counts[index], count - 1)
	}
}

// schedule() calls this after dequeue and its accepted-signal check, before
// dropping the Linux task wait lock. A wake before this helper simply leaves
// the task runnable; a wake after it ends the reservation under the same lock.
pub fn linuxkpi_iowait_block(owner &proc.Thread) {
	$if linuxkpi ? {
		if cpu.interrupt_state() || voidptr(owner) != voidptr(proc.current_thread()) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: invalid I/O block caller')
		}
		scheduler_queue_lock.acquire()
		defer {
			scheduler_queue_lock.release()
		}
		mut t := unsafe { owner }
		if t.is_dead || t.is_in_queue || !C.vinix_linuxkpi_task_in_iowait(voidptr(&t.linuxkpi_task[0])) {
			return
		}
		if t.linuxkpi_iowait_cpu_plus_one != 0 {
			lib.kpanic(unsafe { nil }, c'linuxkpi: duplicate I/O block reservation')
		}
		index := u32(cpulocal.current().cpu_number)
		if index >= 256 || index >= u32(cpu_locals.len) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: invalid I/O block CPU')
		}
		count := katomic.load(&linuxkpi_iowait_counts[index])
		if count == u32(-1) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: I/O wait count overflow')
		}
		t.linuxkpi_iowait_cpu_plus_one = index + 1
		katomic.store(mut &linuxkpi_iowait_counts[index], count + 1)
	}
}

pub fn linuxkpi_iowait_count(index u32) u32 {
	if index >= 256 || index >= u32(cpu_locals.len) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid I/O query CPU')
	}
	return katomic.load(&linuxkpi_iowait_counts[index])
}
