// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

pub fn map_mmio(base u64, _ u64) u64 { return base }

pub const page_size = u64(4096)

__global live_snapshots = u64(0)
__global snapshot_requests = u64(0)
__global fail_snapshot = false

pub fn get_hhdm_offset() u64 { return 0 }
pub fn snapshots() u64 { return live_snapshots }
pub fn requests() u64 { return snapshot_requests }
pub fn refuse_snapshot(refuse bool) { fail_snapshot = refuse }

pub fn pmm_alloc_nozero_nowait(pages u64) voidptr {
	assert pages > 0 && pages <= 4096
	snapshot_requests++
	if fail_snapshot { return unsafe { nil } }
	result := unsafe { C.malloc(pages * page_size) }
	assert result != unsafe { nil }
	live_snapshots++
	return result
}

pub fn pmm_free(physical voidptr, pages u64) {
	assert physical != unsafe { nil } && pages > 0 && live_snapshots > 0
	unsafe { C.free(physical) }
	live_snapshots--
}
