// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Extend eligibility in place, retaining membership order and every desired row.
// Saved physical capacity must be adopted separately before extending into it.
@[direct_array_access]
fn bundle_pool_expand(mut set PlanSet, pool u32, disk u32, end u64) bool {
	if pool >= 64 || disk >= u32(set.count) || !bundle_set_valid(unsafe { &set }) {
		return false
	}
	for i in 0 .. set.regions {
		previous := set.windows[i]
		if previous.pool != pool || previous.disk != disk { continue }
		if end < previous.window.end {
			plan_error(c'pool eligibility cannot shrink')
			return false
		}
		set.windows[i] = PoolRegion{pool: pool, disk: disk,
			window: SpaceWindow{start: previous.window.start, end: end, alignment: previous.window.alignment}}
		if !bundle_set_valid(unsafe { &set }) {
			set.windows[i] = previous
			plan_error(c'pool expansion is unaligned, out of bounds or overlaps another pool region')
			return false
		}
		return true
	}
	plan_error(c'allocation pool member is absent')
	return false
}

// Growth never relocates a mapping or consumes another member's free space.
// Both the previous and requested extents must fit this pool's member region.
@[direct_array_access]
fn bundle_pool_grow(mut set PlanSet, pool u32, slot u32, length u64, disk &u32) bool {
	if pool >= 64 || slot >= 64 || length == 0 || !bundle_set_valid(unsafe { &set }) {
		return false
	}
	for p in 0 .. set.count {
		for at := u32(0); at < set.plans[p].count; at++ {
			row := set.plans[p].rows[at]
			if row.slot != slot { continue }
			for i in 0 .. set.regions {
				region := set.windows[i]
				if region.pool != pool || region.disk != u32(p) { continue }
				if row.offset < region.window.start || row.offset >= region.window.end
					|| row.length > region.window.end - row.offset
					|| length > region.window.end - row.offset {
					plan_error(c'previous and requested mapping extents must fit the selected pool member')
					return false
				}
				if !bundle_grow_row(mut set, slot, length) { return false }
				unsafe { *disk = u32(p) }
				return true
			}
			plan_error(c'mapping disk is not a member of the selected pool')
			return false
		}
	}
	plan_error(c'planned mapping slot is absent')
	return false
}

// Equal-size retries still republish and flush the complete desired bundle.
fn grow_pool_plan(path &char, pool u32, index u32, size u64, expand bool) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open pool bundle'); return 1 }
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !read_bundle(fd, mut set, false) { return 1 }
	mut disk := index
	changed := if expand {
		bundle_pool_expand(mut set, pool, index, size)
	} else {
		bundle_pool_grow(mut set, pool, index, size, unsafe { &disk })
	}
	if !changed || !publish_bundle(path, set) { return 1 }
	if expand {
		return finish_bundle_report(C.printf(c'planned pool expansion pool=%u disk=%u end=%lu\n',
			pool, disk, size) >= 0)
	}
	return finish_bundle_report(C.printf(c'planned pool growth pool=%u disk=%u slot=%u bytes=%lu\n',
		pool, disk, index, size) >= 0)
}
