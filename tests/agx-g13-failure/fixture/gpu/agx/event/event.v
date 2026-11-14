@[has_globals]
module event

pub const max_stamps = u32(128)

pub fn scan_all_completions() {}

__global completed = [128]bool{}

pub fn stamp_completed(slot u32) bool { return completed[slot] }

pub fn set_completed(slot u32, value bool) { completed[slot] = value }
