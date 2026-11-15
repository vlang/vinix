@[has_globals]
module proc

import katomic
import kbudget

// Private Vinix operations. No descriptor or lock token is exposed by GET.
pub const pr_vinix_workload_lease = 0x56490003
pub const pr_vinix_workload_depth = 0x56490004
pub const max_workload_depth = 32

// One process reference, or one reference from a nested workload, retains
// this immutable chain. Fork adds a reference to the leaf, not every ancestor.
pub struct WorkloadLease {
pub mut:
	parent &WorkloadLease = unsafe { nil }
	depth int
	payload voidptr
	retire fn (&WorkloadLease)
mut:
	refs int = 1
	charge kbudget.Charge
}

pub fn new_workload_lease(payload voidptr, retire fn (&WorkloadLease)) ?&WorkloadLease {
	charge := reserve_kernel(.file, u64(sizeof(WorkloadLease)) * 2) or { return none }
	group := &WorkloadLease{payload: payload, retire: retire, charge: charge} @[freed]
	return group
}

pub fn drop_workload_lease(first &WorkloadLease) {
	mut group := unsafe { first }
	for group != unsafe { nil } {
		if katomic.dec(mut &group.refs) { return }
		parent := group.parent
		group.retire(group)
		kbudget.release(group.charge)
		unsafe { free(group) }
		group = parent
	}
}

pub fn inherit_workload(mut child Process, parent &Process) {
	if parent == unsafe { nil } { return }
	mut source := unsafe { parent }
	source.threads_lock.acquire()
	group := source.workload_lease
	if group != unsafe { nil } { katomic.inc(mut &group.refs) }
	child.workload_lease = group
	source.threads_lock.release()
}

// Exit and failed-clone teardown transfer the leaf reference out while locked.
// File/resource callbacks run after releasing threads_lock.
pub fn release_workload(mut process Process) {
	process.threads_lock.acquire()
	group := process.workload_lease
	process.workload_lease = unsafe { nil }
	process.threads_lock.release()
	drop_workload_lease(group)
}
