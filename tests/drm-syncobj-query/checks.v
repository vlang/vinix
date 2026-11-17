// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import memory
import usercopy

__global query_target &syncobj.SyncObj = unsafe { nil }
__global query_replacement &syncobj.DmaFence = unsafe { nil }
__global query_handles &u32 = unsafe { nil }
__global query_reused &syncobj.SyncObj = unsafe { nil }

fn query_publish_after_output(_ u64, _ u64) { syncobj.replace_fence(query_target, query_replacement) }
fn query_reuse_after_output(_ u64, _ u64) {
	handle := query_target.handle
	assert syncobj.destroy(11, handle)
	query_reused = make_object(0)
	assert query_reused.handle == handle
	unsafe { query_handles[1] = ~u32(0) }
}

fn query_chain(obj &syncobj.SyncObj, point u64) (&syncobj.DmaFence, &syncobj.DmaFence) {
	leaf := make_fence()
	chain := syncobj.reserve_chain() or { panic('chain') }
	remember_fence(chain)
	assert syncobj.add_chain_point(obj, chain, leaf, point)
	return chain, leaf
}

fn query_request(handles &u32, points &u64, count u32, flags u32) ioctl.DrmSyncobjTimelineArray {
	usercopy.allow(u64(handles), u64(count) * sizeof(u32))
	usercopy.allow_output(u64(points), u64(count) * sizeof(u64))
	return ioctl.DrmSyncobjTimelineArray{handles: u64(handles), points: u64(points), count_handles: count, flags: flags}
}

fn retire_query() {
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
}

pub fn run_query_checks() {
	assert sizeof(ioctl.DrmSyncobjTimelineArray) == 24
	assert __offsetof(ioctl.DrmSyncobjTimelineArray, points) == 8
	assert __offsetof(ioctl.DrmSyncobjTimelineArray, count_handles) == 16
	assert __offsetof(ioctl.DrmSyncobjTimelineArray, flags) == 20
	assert ioctl.drm_ioctl_syncobj_query == 0xcb && ioctl.drm_syncobj_query_last_submitted == 1
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_query) or { panic('query registration') }
	assert layout.size == 24 && layout.direction == ioctl_write | ioctl_read
	assert u32(3) << 30 | u32(24) << 16 | u32(`d`) << 8 | ioctl.drm_ioctl_syncobj_query == 0xc01864cb
	memory.reset()
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	mut cases := 0
	for _ in 0 .. 100 {
		obj := make_object(0)
		mut handles := [4096]u32{init: obj.handle}
		mut points := [4096]u64{init: ~u64(0)}
		_, first := query_chain(obj, 10)
		_, second := query_chain(obj, 20)
		head, third := query_chain(obj, 30)
		for stage in 0 .. 4 {
			if stage == 1 { syncobj.signal_error(third, -5) }
			if stage == 2 { syncobj.signal(first) }
			if stage == 3 { syncobj.signal(second) }
			for count in [u32(1), 64, 65, 129, 4096]! { for flags in [u32(0), 1]! {
				mut request := query_request(unsafe { &handles[0] }, unsafe { &points[0] }, count, flags)
				before := memory.outstanding(); calls := memory.calls()
				assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == 0
				assert memory.outstanding() == before && memory.calls() == calls + int(count > 64)
				assert usercopy.reads == 1 && usercopy.writes == int(count)
				expected := if flags != 0 || stage == 3 { u64(30) } else if stage == 2 { u64(10) } else { u64(0) }
				for index in 0 .. int(count) { assert points[index] == expected }
				assert request.flags == flags && request.count_handles == count
				cases++
			} }
		}
		assert syncobj.is_signaled(head)
		// Invalid flags/count precede allocation, user reads and outputs.
		for flags in [u32(2), 4, ~u32(0)]! {
			mut request := query_request(unsafe { &handles[0] }, unsafe { &points[0] }, 4096, flags)
			before := memory.attempts()
			assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -22
			assert memory.attempts() == before && usercopy.reads == 0 && usercopy.writes == 0
			cases++
		}
		mut request := query_request(unsafe { &handles[0] }, unsafe { &points[0] }, 0, 0)
		assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -22
		assert ioctl_syncobj_query(unsafe { nil }, unsafe { &request }) == -14
		assert ioctl_syncobj_query(voidptr(11), unsafe { nil }) == -14
		for count in [u32(1), 65, 4096]! {
			for bad_index in [u32(0), count / 2, count - 1]! {
				handles[bad_index] = ~u32(0)
				request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, count, 0)
				assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -2
				assert usercopy.writes == 0, 'resolve every object before any output'
				handles[bad_index] = obj.handle
				cases++
			}
			request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, count, 0)
			assert ioctl_syncobj_query(voidptr(12), unsafe { &request }) == -2 && usercopy.writes == 0
			usercopy.inject_fault()
			assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -14 && usercopy.writes == 0
			cases += 2
			for bad_index in [u32(0), count / 2, count - 1]! {
				request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, count, 1)
				usercopy.fail_output_at(unsafe { u64(&points[0]) } + u64(bad_index) * 8)
				before := memory.outstanding()
				assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -14
				assert usercopy.writes == int(bad_index + 1) && memory.outstanding() == before
				cases++
			}
		}
		request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, 65, 0)
		memory.fail_next()
		assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -12
		assert usercopy.reads == 0 && usercopy.writes == 0
		// Later output failures preserve the copied prefix and original tail,
		// including a partial write inside one u64 point.
		for fault_offset in [0, 7, 8, 12, 23]! {
			for index in 0 .. 3 { points[index] = ~u64(0) }
			request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, 3, 1)
			usercopy.fail_output_at(unsafe { u64(&points[0]) } + u64(fault_offset))
			assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -14
			assert usercopy.writes == fault_offset / 8 + 1
			for index in 0 .. fault_offset / 8 { assert points[index] == 30 }
			for index in fault_offset / 8 + 1 .. 3 { assert points[index] == ~u64(0) }
			cases++
		}
		// Head snapshots happen per output, while object and handle snapshots
		// precede all outputs. A repeated handle can observe a newer head.
		query_target = obj
		query_replacement = remember_fence(syncobj.new_fence(999, ~u64(0)))
		request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, 2, 1)
		usercopy.after_next_output(query_publish_after_output)
		assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == 0
		assert points[0] == 30 && points[1] == 0
		syncobj.replace_fence(obj, head)
		query_handles = unsafe { &handles[0] }
		request = query_request(unsafe { &handles[0] }, unsafe { &points[0] }, 2, 1)
		usercopy.after_next_output(query_reuse_after_output)
		assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == 0
		assert points[0] == 30 && points[1] == 30
		cases += 2
		retire_query()
	}
	// Empty and non-chain objects report zero regardless of completion or
	// public sequence value. QUERY does not reinterpret the legacy point map.
	obj := make_object(0)
	mut one := [obj.handle]!
	mut result := u64(999)
	for mode in 0 .. 4 {
		if mode == 1 { syncobj.replace_fence(obj, remember_fence(syncobj.new_fence(7, ~u64(0)))) }
		if mode == 2 { syncobj.signal(current(obj)) }
		if mode == 3 { assert syncobj.add_timeline_point(obj, 77, make_fence()) }
		for flags in [u32(0), 1]! {
			mut request := query_request(unsafe { &one[0] }, unsafe { &result }, 1, flags)
			assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == 0 && result == 0
		}
	}
	mut bad_pointer := query_request(unsafe { &one[0] }, unsafe { &result }, 1, 0)
	bad_pointer.points = ~u64(0) - 3
	assert ioctl_syncobj_query(voidptr(11), unsafe { &bad_pointer }) == -14
	bad_pointer.points = 0
	assert ioctl_syncobj_query(voidptr(11), unsafe { &bad_pointer }) == -14
	bad_pointer.count_handles = ~u32(0)
	assert ioctl_syncobj_query(voidptr(11), unsafe { &bad_pointer }) == -12
	retire_query()
	query_target = unsafe { nil }; query_replacement = unsafe { nil }; query_handles = unsafe { nil }; query_reused = unsafe { nil }
	println('DRM timeline QUERY: ${cases} checks; 24-byte registration, 1..4096 records, completed versus submitted progress, reverse completion/errors, validation-before-output, lookup/copy/OOM cleanup, partial output faults, per-entry head snapshots and retained identities after handle reuse pass.')
}
