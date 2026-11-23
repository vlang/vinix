// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import lib
import proc
import resource
import stat

pub struct StatMount {
pub:
	id u64
	root bool
}

// Every completed lookup has its own route. Mount records and their IDs stay
// valid even after a move, lazy detach, or release of the source descriptor.
fn capture_stat_mount(out &StatMount, context &lib.MountContext, node voidptr) {
	if out == unsafe { nil } { return }
	entry := unsafe { &Mount(lib.mount_context_top(context)) }
	if entry != unsafe { nil } {
		unsafe { *out = StatMount{id: u64(entry.public_id), root: node == voidptr(entry.root)} }
	}
}

fn stat_description(mut handle file.Handle, statbuf &stat.Stat, mount_info &StatMount) (u64, u64) {
	handle.mac_check(proc.mac_inspect) or { return errno.err, errno.get() }
	capture_stat_mount(mount_info, &handle.mount, handle.node)
	mut res := handle.resource
	return stat_resource(mut res, statbuf)
}

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
