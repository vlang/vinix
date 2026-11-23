// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import aarch64.cpu
import aarch64.gic
import katomic
import klock

const max_sync_core_cpus = 256
const membarrier_memory = u64(1)
const membarrier_sync_core = u64(2)

__global (
	sync_core_lock    klock.Lock
	sync_core_pending [max_sync_core_cpus]u64
)

pub fn membarrier_supported() bool {
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
	if number >= max_sync_core_cpus { return }
	request := katomic.load(&sync_core_pending[number])
	if request == 0 { return }
	cpu.dsb_ish()
	if request == membarrier_sync_core { cpu.isb() }
	// Publish the acknowledgment after the requested barrier completes.
	katomic.store(mut &sync_core_pending[number], u64(0))
	cpu.sev()
}

// The caller holds no process/page-map locks. Interrupts stay disabled on the
// sending CPU so it cannot migrate while the request is in flight. Concurrent
// callers answer an earlier request while waiting for its lock, preventing two
// CPUs entering membarrier together from waiting for each other's interrupt.
fn membarrier_rendezvous(request u64) {
	for !sync_core_lock.test_and_acquire() { answer_sync_core() }
	defer { sync_core_lock.release() }
	me := cpu.read_tpidr_el1()
	cpu.dsb_ish()
	for index, local in cpu_locals {
		if u64(index) == me || katomic.load(&local.online) == 0 { continue }
		katomic.store(mut &sync_core_pending[index], request)
		gic.send_sync_core(local.mpidr)
	}
	if request == membarrier_sync_core { cpu.isb() }
	for index, local in cpu_locals {
		mut spins := u64(0)
		for katomic.load(&sync_core_pending[index]) != 0 {
			spins++
			if spins % 1000000 == 0 { gic.send_sync_core(local.mpidr) }
		}
	}
	cpu.dsb_ish()
}

pub fn synchronize_core() {
	membarrier_rendezvous(membarrier_sync_core)
}

pub fn synchronize_memory() {
	membarrier_rendezvous(membarrier_memory)
}
