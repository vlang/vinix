// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import stat

// Network resources may need an RPC before returning attributes. The backend
// returns the value while its lock is held, so a concurrent refresh cannot
// change individual fields between refresh and the caller's copy.
pub interface StatSnapshotResource {
mut:
	snapshot_stat() ?stat.Stat
}

struct StatSnapshotCall {
mut:
	backend StatSnapshotResource
}

pub fn snapshot_stat(mut res Resource) ?stat.Stat {
	if mut res is StatSnapshotResource {
		mut call := unsafe { &StatSnapshotCall(C.vinix_stack_alloc(sizeof(StatSnapshotCall))) }
		unsafe { call.backend = StatSnapshotResource(res) }
		return call.backend.snapshot_stat()
	}
	return res.stat
}
