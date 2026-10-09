module pagecache

import cgcontrol
import errno
import proc

struct GroupDevice {
mut:
	writes int
	groups [4]&cgcontrol.Group
	fail bool
}

fn group_load(_context voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	assert false // Whole-page replacements need no read.
	return none
}

fn group_store(context voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
	mut device := unsafe { &GroupDevice(context) }
	device.groups[device.writes] = proc.current_cgroup_io()
	device.writes++
	if device.fail { errno.set(errno.eio); return none }
	return i64(count)
}

fn test_dirty_origins_split_runs_survive_failed_writeback_and_restore_issuer() {
	mut left := cgcontrol.Group{}
	mut right := cgcontrol.Group{}
	mut device := GroupDevice{fail: true}
	mut cache := Cache{capacity: 4}
	defer {
		proc.io_group = unsafe { nil }
		cache.release(unsafe { &device }, group_store) or { panic('release failed') }
	}
	mut payload := [4096]u8{}
	proc.io_group = unsafe { &left }
	assert cache.write(unsafe { &device }, group_load, group_store, unsafe { &payload[0] }, 0, 4096, 8192)? == 4096
	proc.io_group = unsafe { &right }
	assert cache.write(unsafe { &device }, group_load, group_store, unsafe { &payload[0] }, 4096, 4096, 8192)? == 4096
	proc.io_group = unsafe { nil }
	mut failed := false
	cache.sync(unsafe { &device }, group_store) or { failed = true }
	assert failed && device.writes == 1
	assert voidptr(device.groups[0]) == voidptr(unsafe { &left })
	assert proc.current_cgroup_io() == unsafe { nil }
	device.fail = false
	cache.sync(unsafe { &device }, group_store)?
	assert device.writes == 3
	assert (voidptr(device.groups[1]) == voidptr(unsafe { &left })
		&& voidptr(device.groups[2]) == voidptr(unsafe { &right }))
		|| (voidptr(device.groups[2]) == voidptr(unsafe { &left })
		&& voidptr(device.groups[1]) == voidptr(unsafe { &right }))
	assert proc.current_cgroup_io() == unsafe { nil }
}
