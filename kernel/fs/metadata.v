// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import resource
import time

fn change_owner(mut res resource.Resource, uid u32, gid u32) ? {
	// -1 leaves that owner unchanged; chown with no selected owner is a no-op.
	if uid == u32(0xffffffff) && gid == u32(0xffffffff) { return }
	update := resource.MetadataUpdate{
		uid_set: uid != u32(0xffffffff)
		uid: uid
		gid_set: gid != u32(0xffffffff)
		gid: gid
		clear_setid: true
	}
	resource.update_metadata(mut res, unsafe { &update })?
}

fn file_time_kind(value time.TimeSpec) resource.MetadataTime {
	if value.tv_nsec == utime_omit { return .unchanged }
	if value.tv_nsec == utime_now { return .now }
	return .value
}

// Permission and range validation remain in set_file_times. Pass the original
// request to the backend instead of staging values in a concurrently refreshed
// Stat; .now also carries the resolved local time for legacy local providers.
fn apply_file_times(mut res resource.Resource, requested [2]time.TimeSpec, now time.TimeSpec) ? {
	update := resource.MetadataUpdate{
		atime_kind: file_time_kind(requested[0])
		atime: if requested[0].tv_nsec == utime_now { now } else { requested[0] }
		mtime_kind: file_time_kind(requested[1])
		mtime: if requested[1].tv_nsec == utime_now { now } else { requested[1] }
		ctime_set: true
		ctime: now
	}
	resource.update_metadata(mut res, unsafe { &update })?
}
