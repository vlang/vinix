module zonemodel

import os

fn test_random_migrating_ownership_and_cache_drains() { migrating_ownership() }

fn test_cached_pages_are_not_reclaimable() { cached_pages() }

fn test_live_survivor_pins_backing() { live_survivor() }

fn test_failed_batch_does_not_reserve_anything() { failed_batch() }

fn test_partial_allocation_magazine_free_swap() { partial_swap() }

fn test_source_integration_contract() {
	source_integration(os.dir(os.dir(os.dir(os.dir(@FILE)))))!
}
