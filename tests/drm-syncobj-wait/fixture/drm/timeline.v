// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import gpu.agx.submission
import memory
import usercopy

__global timeline_cases = 0

fn stage_timeline(owner u64, handle u32, value u64, input bool) (int, submission.SyncArray) {
	item := ioctl.DrmAsahiSync{ handle: handle, sync_type: ioctl.asahi_sync_timeline_syncobj, timeline_value: value }
	usercopy.allow(unsafe { u64(&item) }, sizeof(item))
	code, staged := submission.stage_sync_array(owner, unsafe { u64(&item) }, 1, input)
	assert usercopy.reads == 1 && usercopy.writes == 0
	timeline_cases++
	return code, staged
}

fn expect_timeline(obj &syncobj.SyncObj, query u64, expected &syncobj.DmaFence) {
	result := syncobj.get_timeline_fence(obj, query) or {
		assert expected == unsafe { nil }, 'missing timeline candidate for ${query}'
		timeline_cases++
		return
	}
	assert voidptr(result) == voidptr(expected), 'wrong timeline candidate for ${query}'
	assert !obj.lock.is_held()
	timeline_cases++
}

fn retire_timeline_fixture() {
	assert memory.outstanding() == 0
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
}

pub fn run_timeline_boundary_checks() {
	memory.reset()
	// The actual Asahi output installer publishes MAX, then the native input
	// stager must accept a lower point covered by that submission.
	for _ in 0 .. 200 {
		obj := make_object(0); maximum := make_fence()
		code, output := stage_timeline(11, obj.handle, ~u64(0), false)
		assert code == 0 && output.count == 1 && output.timeline_values[0] == ~u64(0)
		assert submission.install_output_syncs(unsafe { &output }, maximum)
		submission.release_sync_array(output)
		attempts := memory.attempts()
		code_in, captured := stage_timeline(11, obj.handle, ~u64(0) - 1, true)
		assert code_in == 0, 'MAX must cover the lower input point'
		assert captured.count == 1 && voidptr(captured.fences[0]) == voidptr(maximum)
		assert memory.attempts() == attempts && !obj.lock.is_held()
		// Later publication changes subsequent selection but not a staged input.
		closer := make_fence()
		assert syncobj.add_timeline_point(obj, ~u64(0) - 1, closer)
		expect_timeline(obj, ~u64(0) - 1, closer)
		expect_timeline(obj, ~u64(0), maximum)
		assert !syncobj.add_timeline_point(obj, ~u64(0), closer)
		assert !syncobj.add_timeline_point(obj, 0, maximum)
		assert !syncobj.add_timeline_point(obj, 3, unsafe { nil })
		assert !obj.lock.is_held()
		// Reset/handle reuse removes membership; the staged retained leaf still
		// completes independently of replacement work and the new handle owner.
		syncobj.replace_fence(obj, unsafe { nil })
		expect_timeline(obj, ~u64(0) - 1, unsafe { nil })
		assert syncobj.destroy(11, obj.handle)
		reused := make_object(0); assert reused.handle == obj.handle
		assert syncobj.add_timeline_point(reused, ~u64(0), closer)
		syncobj.signal_error(maximum, -5)
		assert voidptr(captured.fences[0]) == voidptr(maximum)
		assert syncobj.is_signaled(captured.fences[0]) && syncobj.get_error(captured.fences[0]) == -5
		assert !syncobj.is_signaled(closer)
		retire_timeline_fixture()
	}
	// A sorted independent oracle chooses the first present unsigned value at
	// or above the query. Cover every subset and all 24 insertion permutations.
	values := [u64(1), u64(1) << 63, ~u64(0) - 1, ~u64(0)]!
	queries := [u64(0), 1, 2, (u64(1) << 63) - 1, u64(1) << 63,
		(u64(1) << 63) + 1, ~u64(0) - 2, ~u64(0) - 1, ~u64(0)]!
	for a in 0 .. 4 { for b in 0 .. 4 { for c in 0 .. 4 { for d in 0 .. 4 {
		if a == b || a == c || a == d || b == c || b == d || c == d { continue }
		for mask in 0 .. 16 {
			obj := make_object(0)
			fences := [make_fence(), make_fence(), make_fence(), make_fence()]!
			for index in [a, b, c, d]! {
				if mask & (1 << index) != 0 { assert syncobj.add_timeline_point(obj, values[index], fences[index]) }
			}
			attempts := memory.attempts()
			for query in queries {
				mut expected := &syncobj.DmaFence(unsafe { nil })
				if query != 0 {
					for index in 0 .. 4 {
						if mask & (1 << index) != 0 && values[index] >= query { expected = unsafe { fences[index] }; break }
					}
				}
				expect_timeline(obj, query, expected)
				code, input := stage_timeline(11, obj.handle, query, true)
				if expected == unsafe { nil } {
					assert code == -22 && input.count == 0
					for index in 0 .. 64 { assert input.objects[index] == unsafe { nil } && input.fences[index] == unsafe { nil } }
				} else {
					assert code == 0 && input.count == 1 && input.timeline[0] && input.timeline_values[0] == query
					assert voidptr(input.objects[0]) == voidptr(obj) && voidptr(input.fences[0]) == voidptr(expected)
				}
				assert !obj.lock.is_held()
			}
			assert memory.attempts() == attempts
			retire_timeline_fixture()
		}
	} } } }
	expect_timeline(unsafe { nil }, 1, unsafe { nil })
	println('DRM timeline boundary: ${timeline_cases} checks; MAX fallback and exact points, unsigned boundary oracle over all subsets/permutations, actual Asahi output/input staging, stable captures, reset/reuse, no lookup allocation and released locks passed')
}
