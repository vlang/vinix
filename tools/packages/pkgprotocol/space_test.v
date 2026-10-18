// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

fn test_disk_budget_preserves_exact_boundaries_without_overflow() {
	for needed in [u64(0), 1, 4096, ~u64(0) / 2, ~u64(0)]! {
		for reserve in [u64(0), 1, 1024, ~u64(0) / 2, ~u64(0)]! {
			for available in [u64(0), 1, 4096, ~u64(0) / 2, ~u64(0)]! {
				budget := disk_budget(available, needed, reserve)
				if needed > ~u64(0) - reserve {
					assert budget.overflow && !budget.fits() && budget.required == 0 && budget.shortfall == 0
				} else {
					assert !budget.overflow && budget.required == needed + reserve
					assert budget.fits() == (available >= needed + reserve)
					assert budget.shortfall == if available < needed + reserve { needed + reserve - available } else { u64(0) }
				}
			}
		}
	}
	for total in [u64(1), 5120, ~u64(0)]! {
		assert disk_budget(total, total - 1, 1).fits()
		assert disk_budget(total - 1, total - 1, 1).shortfall == 1
	}
	println('SOFTWARE SPACE 125 counter combinations and exact/one-byte-short boundaries preserve reserve without overflow PASS')
}

fn test_review_space_semantics_match_noop_and_offline_export_checks() {
	for operation in ['install', 'remove', 'upgrade', 'repair', 'deploy', 'rollback']! {
		assert (Review{operation: operation, disk_reserve: ~u64(0)}).space_sufficient()
		assert (Review{operation: operation, disk_needed: 4096, disk_available: 5120, disk_reserve: 1024}).space_sufficient()
		assert !(Review{operation: operation, disk_needed: 4096, disk_available: 5119, disk_reserve: 1024}).space_sufficient()
		assert !(Review{operation: operation, disk_needed: ~u64(0), disk_available: ~u64(0), disk_reserve: 1}).space_sufficient()
	}
	assert !(Review{operation: 'mirror', disk_reserve: 1}).space_sufficient()
	for same_disk in [false, true]! {
		for acquired in [u64(0), 4096]! {
			for free in [u64(0), 5119, 5120]! {
				mirror := MirrorReview{shared_disk: same_disk, cache_needed: acquired, cache_available: free, review: Review{disk_reserve: 1024}}
				assert mirror.cache_space_sufficient() == (same_disk || acquired == 0 || free >= 5120)
			}
		}
	}
	println('SOFTWARE SPACE ordinary no-op reserve exemptions, mirror destination enforcement, shared-disk accounting and separate warm/cold caches PASS')
}
