// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolRegion {
	pool u32
mut:
	disk   u32
	window SpaceWindow
}

struct PoolSpace {
mut:
	regions    u32
	gaps       u32
	bytes_low  u64
	bytes_high u64
	largest    u64
}

// One region per pool/disk pair; all pool regions on a disk are disjoint.
// Regions refer to enrolled disk indices, never volatile device paths.
@[direct_array_access]
fn pool_regions_valid(set &PlanSet) bool {
	if set.regions < 0 || set.regions > 64 { return false }
	for i in 0 .. set.regions {
		region := set.windows[i]
		if region.pool >= 64 || region.disk >= u32(set.count) || !space_window_valid(region.window) {
			return false
		}
		key := unsafe { &set.plans[region.disk].key }
		if region.window.end > key.bytes || region.window.alignment < key.sector
			|| region.window.start % key.sector != 0 || region.window.end % key.sector != 0 {
			return false
		}
		for j in 0 .. i {
			other := set.windows[j]
			if other.disk == region.disk {
				if other.pool == region.pool || (region.window.start < other.window.end
					&& other.window.start < region.window.end) {
					return false
				}
			} else if capacity_identifier_matches(key, unsafe { &set.plans[other.disk].key }) {
				return false
			}
		}
	}
	return true
}

@[direct_array_access]
fn bundle_pool_add(mut set PlanSet, region &PoolRegion) bool {
	if !bundle_set_valid(unsafe { &set }) || set.regions >= 64 {
		plan_error(c'invalid bundle or full allocation pool table')
		return false
	}
	at := set.regions
	previous := set.windows[at]
	set.windows[at] = unsafe { *region }
	set.regions++
	if !pool_regions_valid(unsafe { &set }) {
		set.regions--
		set.windows[at] = previous
		plan_error(c'invalid, duplicate, overlapping or ambiguous allocation pool region')
		return false
	}
	return true
}

@[direct_array_access]
fn bundle_pool_remove(mut set PlanSet, pool u32, disk u32) bool {
	if !bundle_set_valid(unsafe { &set }) || pool >= 64 || disk >= u32(set.count) { return false }
	for i in 0 .. set.regions {
		if set.windows[i].pool != pool || set.windows[i].disk != disk { continue }
		for j := i + 1; j < set.regions; j++ { set.windows[j - 1] = set.windows[j] }
		set.regions--
		set.windows[set.regions] = PoolRegion{}
		return true
	}
	plan_error(c'allocation pool member is absent')
	return false
}

// The sum can exceed u64 across disks. Keep and print the full capacity.
fn pool_add_bytes(mut total PoolSpace, bytes u64) {
	before := total.bytes_low
	total.bytes_low += bytes
	if total.bytes_low < before { total.bytes_high++ }
}

@[direct_array_access]
fn pool_bytes_decimal(total &PoolSpace, out &char) {
	mut words := [u32(total.bytes_high >> 32), u32(total.bytes_high), u32(total.bytes_low >> 32),
		u32(total.bytes_low)]!
	mut reversed := [40]char{}
	mut count := 0
	for {
		mut remainder := u64(0)
		for i in 0 .. 4 {
			value := (remainder << 32) | u64(words[i])
			words[i] = u32(value / 10)
			remainder = value % 10
		}
		reversed[count] = char(u8(`0`) + u8(remainder))
		count++
		if words[0] | words[1] | words[2] | words[3] == 0 { break }
	}
	unsafe {
		for i in 0 .. count { out[i] = reversed[count - i - 1] }
		out[count] = 0
	}
}

// Enumerate all selected regions before reporting. Query failure leaves the
// caller's result unchanged; selection order is the saved membership order.
@[direct_array_access]
fn bundle_pool_space(set &PlanSet, pool u32, mut result PoolSpace) bool {
	if pool >= 64 || !bundle_set_valid(set) { return false }
	mut total := PoolSpace{}
	mut space := unsafe { &FreeExtents(C.alloca(sizeof(FreeExtents))) }
	unsafe { *space = FreeExtents{} }
	for i in 0 .. set.regions {
		region := set.windows[i]
		if region.pool != pool { continue }
		if !bundle_free_extents(set, int(region.disk), region.window, mut space) { return false }
		total.regions++
		total.gaps += u32(space.count)
		pool_add_bytes(mut total, space.total)
		if space.largest > total.largest { total.largest = space.largest }
	}
	if total.regions == 0 {
		plan_error(c'allocation pool is absent')
		return false
	}
	result = total
	return true
}

@[direct_array_access]
fn bundle_pool_allocate(mut set PlanSet, pool u32, request &Request, disk &u32,
	mut chosen Request) bool {
	if pool >= 64 || request.version != 1 || request.slot >= 64 || request.flags > 1
		|| request.length == 0 || !bundle_set_valid(unsafe { &set }) {
		return false
	}
	// Validate global slot ownership independently of the cached slot mask.
	for p in 0 .. set.count {
		for row := u32(0); row < set.plans[p].count; row++ {
			if set.plans[p].rows[row].slot == request.slot {
				plan_error(c'pool allocation slot is already owned')
				return false
			}
		}
	}
	mut space := unsafe { &FreeExtents(C.alloca(sizeof(FreeExtents))) }
	unsafe { *space = FreeExtents{} }
	for i in 0 .. set.regions {
		region := set.windows[i]
		if region.pool != pool || request.length % set.plans[region.disk].key.sector != 0 {
			continue
		}
		if !bundle_free_extents(unsafe { &set }, int(region.disk), region.window, mut space) {
			return false
		}
		for gap in 0 .. space.count {
			if space.rows[gap].length < request.length { continue }
			row := Request{
				slot:   request.slot
				offset: space.rows[gap].offset
				length: request.length
				flags:  request.flags
			}
			if !bundle_add_row(mut set, int(region.disk), &row) { return false }
			unsafe { *disk = region.disk }
			chosen = row
			return true
		}
	}
	plan_error(c'no pool member has an aligned contiguous gap for this allocation')
	return false
}

// Regions and desired mappings use one checksummed atomic bundle, avoiding a
// separate pool file whose membership could disagree with a published mapping.
fn edit_pool_plan(path &char, region &PoolRegion, remove bool) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		C.perror(c'vinix-volume: open pool bundle')
		return 1
	}
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !read_bundle(fd, mut set, false) { return 1 }
	changed := if remove {
		bundle_pool_remove(mut set, region.pool, region.disk)
	} else {
		bundle_pool_add(mut set, region)
	}
	if !changed || !publish_bundle(path, set) { return 1 }
	return finish_bundle_report(C.printf(c'planned pool member pool=%u disk=%u removed=%u\n',
		region.pool, region.disk, u32(remove)) >= 0)
}

fn allocate_pool_plan(path &char, pool u32, request &Request) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		C.perror(c'vinix-volume: open pool bundle')
		return 1
	}
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !read_bundle(fd, mut set, false) { return 1 }
	mut disk := u32(0)
	mut chosen := Request{}
	if !bundle_pool_allocate(mut set, pool, request, unsafe { &disk }, mut chosen) || !publish_bundle(path, set) {
		return 1
	}
	return finish_bundle_report(C.printf(c'planned pool allocation pool=%u disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu\n',
		pool, disk, chosen.slot, chosen.offset, chosen.length, chosen.flags) >= 0)
}

@[direct_array_access]
fn report_pool_space(set &PlanSet, pool u32) bool {
	mut total := PoolSpace{}
	if !bundle_pool_space(set, pool, mut total) { return false }
	mut text := [40]char{}
	pool_bytes_decimal(&total, &text[0])
	mut space := unsafe { &FreeExtents(C.alloca(sizeof(FreeExtents))) }
	unsafe { *space = FreeExtents{} }
	for i in 0 .. set.regions {
		region := set.windows[i]
		if region.pool != pool { continue }
		if !bundle_free_extents(set, int(region.disk), region.window, mut space) { return false }
		if C.printf(c'pool=%u disk=%u start=%lu end=%lu alignment=%lu gaps=%u bytes=%lu largest=%lu\n',
			pool, region.disk, region.window.start, region.window.end, region.window.alignment,
			u32(space.count), space.total, space.largest) < 0 {
			return false
		}
	}
	return C.printf(c'pool=%u regions=%u gaps=%u bytes=%s largest=%lu\n', pool,
		total.regions, total.gaps, &text[0], total.largest) >= 0
}

fn space_pool_plan(path &char, pool u32) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		C.perror(c'vinix-volume: open pool bundle')
		return 1
	}
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !read_bundle(fd, mut set, false) { return 1 }
	return finish_bundle_report(report_pool_space(set, pool))
}
