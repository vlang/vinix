// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub struct DiskBudget {
pub:
	required u64 // payload/staging requirement plus reserved space
	shortfall u64
	overflow bool
}

// No wrapped arithmetic or allocation, including untrusted SDK-1 counters.
pub fn disk_budget(available u64, needed u64, reserve u64) DiskBudget {
	if needed > ~u64(0) - reserve { return DiskBudget{overflow: true} }
	required := needed + reserve
	return DiskBudget{required: required, shortfall: if available < required { required - available } else { u64(0) }}
}

pub fn (budget DiskBudget) fits() bool { return !budget.overflow && budget.shortfall == 0 }

// A zero-cost ordinary review describes a no-op: the service returns before
// enforcing its reserve. Mirror publication always checks its destination.
pub fn (review Review) space_sufficient() bool {
	return (review.operation != 'mirror' && review.disk_needed == 0)
		|| disk_budget(review.disk_available, review.disk_needed, review.disk_reserve).fits()
}

// A shared destination already includes acquisition. A separate cache needs
// its own reserve only when bytes must actually be acquired.
pub fn (mirror MirrorReview) cache_space_sufficient() bool {
	return mirror.shared_disk || mirror.cache_needed == 0
		|| disk_budget(mirror.cache_available, mirror.cache_needed, mirror.review.disk_reserve).fits()
}
