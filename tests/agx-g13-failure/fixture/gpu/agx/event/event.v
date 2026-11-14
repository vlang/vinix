@[has_globals]
module event

pub const max_stamps = u32(128)

pub fn scan_all_completions() {}

__global completed = [128]bool{}
__global reported_stamps = [128]u32{}
__global has_value = [128]bool{}

pub fn stamp_completed(slot u32) bool { return completed[slot] }

pub fn stamp_value_completed(slot u32, value u32) bool {
	return if has_value[slot] { i32(reported_stamps[slot] - value) >= 0 } else { completed[slot] }
}

pub fn set_completed(slot u32, value bool) { completed[slot] = value; has_value[slot] = false }

pub fn set_value(slot u32, value u32) { reported_stamps[slot] = value; has_value[slot] = true }
