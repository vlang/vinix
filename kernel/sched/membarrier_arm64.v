// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import aarch64.cpu
import aarch64.gic
import katomic
import klock

const max_sync_core_cpus = 256

__global (
	sync_core_lock    klock.Lock
	sync_core_pending [max_sync_core_cpus]u64
)

pub fn sync_core_supported() bool {
	if !gic.is_initialised() || cpu_locals.len > max_sync_core_cpus { return false }
	for local in cpu_locals {
		if local.mpidr & 0xff >= 16 { return false }
	}
	return true
}

fn answer_sync_core() {
	ints := cpu.interrupt_toggle(false)
	defer { cpu.interrupt_toggle(ints) }
	number := cpu.read_tpidr_el1()
	if number >= max_sync_core_cpus || katomic.load(&sync_core_pending[number]) == 0 { return }
	cpu.dsb_ish()
	cpu.isb()
	// Publish the acknowledgment only after this CPU synchronized its pipeline.
	katomic.store(mut &sync_core_pending[number], u64(0))
	cpu.sev()
}

// The caller holds no process/page-map locks. Interrupts stay disabled on the
// sending CPU so it cannot migrate while the request is in flight. Concurrent
// callers answer an earlier request while waiting for its lock, preventing two
// CPUs entering membarrier together from waiting for each other's interrupt.
pub fn synchronize_core() {
	for !sync_core_lock.test_and_acquire() { answer_sync_core() }
	defer { sync_core_lock.release() }
	me := cpu.read_tpidr_el1()
	cpu.dsb_ish()
	for index, local in cpu_locals {
		if u64(index) == me || katomic.load(&local.online) == 0 { continue }
		katomic.store(mut &sync_core_pending[index], u64(1))
		gic.send_sync_core(local.mpidr)
	}
	cpu.isb()
	for index, local in cpu_locals {
		mut spins := u64(0)
		for katomic.load(&sync_core_pending[index]) != 0 {
			spins++
			if spins % 1000000 == 0 { gic.send_sync_core(local.mpidr) }
		}
	}
	cpu.dsb_ish()
}
