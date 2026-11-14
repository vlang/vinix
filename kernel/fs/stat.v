// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import resource
import stat

fn stat_resource(mut res resource.Resource, statbuf &stat.Stat) (u64, u64) {
	snapshot := resource.snapshot_stat(mut res) or { return errno.err, errno.get() }
	unsafe { *statbuf = snapshot }
	return 0, 0
}

fn stat_path_resource(mut res resource.Resource, statbuf &stat.Stat) (u64, u64) {
	// A remote RPC can outlast the grace period of a lockless path lookup.
	// Pin only opt-in providers: legacy device close callbacks can have side
	// effects, and ordinary cached stats never enter a blocking backend.
	needs_pin := res is resource.StatSnapshotResource
	if needs_pin {
		retain_open_origin(mut res) or { return errno.err, errno.get() }
	}
	defer { if needs_pin { resource.release_resource(mut res) } }
	return stat_resource(mut res, statbuf)
}
