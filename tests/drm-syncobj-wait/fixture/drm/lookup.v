// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import gpu.agx.submission
import memory
import usercopy

__global lookup_cases = 0

fn check_sync_lookup(items &ioctl.DrmAsahiSync, count u32, owner u64, input bool, available u64, expected int) submission.SyncArray {
	usercopy.allow(u64(items), available)
	attempts := memory.attempts()
	code, staged := submission.stage_sync_array(owner, u64(items), count, input)
	assert code == expected, 'sync lookup expected ${expected}, got ${code}'
	assert memory.attempts() == attempts && usercopy.writes == 0
	if expected != 0 {
		assert staged.count == 0
		for index in 0 .. 64 {
			assert staged.objects[index] == unsafe { nil } && staged.fences[index] == unsafe { nil }
			assert !staged.timeline[index] && staged.timeline_values[index] == 0
		}
	}
	lookup_cases++
	return staged
}

pub fn run_sync_lookup_checks() {
	memory.reset()
	for _ in 0 .. 200 {
		obj := make_object(0); fence := make_fence(); syncobj.replace_fence(obj, fence)
		assert syncobj.add_timeline_point(obj, 5, fence)
		empty := make_object(0)
		removed := make_object(0); assert syncobj.destroy(11, removed.handle)
		for input in [true, false]! {
			for timeline in [false, true]! {
				base := ioctl.DrmAsahiSync{ handle: obj.handle,
					sync_type: if timeline { ioctl.asahi_sync_timeline_syncobj } else { ioctl.asahi_sync_syncobj },
					timeline_value: if timeline { u64(5) } else { u64(0) } }
				mut items := [64]ioctl.DrmAsahiSync{init: base}
				for index in [0, 32, 63]! {
					for missing in [u32(0), ~u32(0), removed.handle]! {
						items[index].handle = missing
						check_sync_lookup(unsafe { &items[0] }, 64, 11, input, sizeof(items), -2)
						assert usercopy.reads == index + 1
					}
					// Descriptor validation and copy faults still precede lookup
					// of that descriptor, including a simultaneously missing handle.
					items[index].extensions = 1
					check_sync_lookup(unsafe { &items[0] }, 64, 11, input, sizeof(items), -22)
					items[index].extensions = 0; items[index].sync_type = ~u32(0)
					check_sync_lookup(unsafe { &items[0] }, 64, 11, input, sizeof(items), -22)
					items[index] = base; items[index].handle = 0
					check_sync_lookup(unsafe { &items[0] }, 64, 11, input, u64(index + 1) * sizeof(ioctl.DrmAsahiSync) - 1, -14)
					assert usercopy.reads == index + 1
					items[index] = base
				}
				for owner in [u64(0), 12, ~u64(0)]! {
					check_sync_lookup(unsafe { &items[0] }, 64, owner, input, sizeof(items), -2)
					assert usercopy.reads == 1
				}
				items[32].handle = empty.handle
				staged_empty := check_sync_lookup(unsafe { &items[0] }, 64, 11, input, sizeof(items), if input { -22 } else { 0 })
				if !input { assert staged_empty.count == 64 && voidptr(staged_empty.objects[32]) == voidptr(empty) }
				submission.release_sync_array(staged_empty)
				items[32] = base
				if timeline && input {
					items[32].timeline_value = 6
					check_sync_lookup(unsafe { &items[0] }, 64, 11, input, sizeof(items), -22)
					items[32] = base
				}
				valid := check_sync_lookup(unsafe { &items[0] }, 64, 11, input, sizeof(items), 0)
				assert valid.count == 64 && usercopy.reads == 64
				for index in 0 .. 64 {
					assert voidptr(valid.objects[index]) == voidptr(obj)
					assert voidptr(valid.fences[index]) == if input { voidptr(fence) } else { unsafe { nil } }
				}
				assert voidptr(current(obj)) == voidptr(fence) && !syncobj.is_signaled(fence)
				assert !obj.lock.is_held() && !empty.lock.is_held()
				submission.release_sync_array(valid)
			}
		}
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	println('Asahi sync lookup: ${lookup_cases} checks; ENOENT for missing/deleted/foreign-owner names, input/output binary/timeline arrays, first/middle/last failures, EINVAL empty fences, validation/copy precedence, empty staged failures and unchanged outputs passed')
}
