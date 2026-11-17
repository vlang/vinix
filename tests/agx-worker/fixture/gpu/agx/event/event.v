@[has_globals]
module event

__global scans = 0

pub fn reset() { scans = 0 }
pub fn count() int { return scans }
pub fn scan_all_completions() { scans++ }
