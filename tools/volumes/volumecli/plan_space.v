// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct SpaceWindow {
	start     u64
	end       u64 // Exclusive. The caller owns the choice of this allocation region.
	alignment u64
}

struct FreeExtent {
	offset u64
	length u64
}

struct FreeExtents {
mut:
	count   int
	rows    [65]FreeExtent // At most one more gap than the 64 occupied mappings.
	total   u64
	largest u64
}

fn space_window_valid(window SpaceWindow) bool {
	return window.start < window.end && window.alignment != 0
		&& window.alignment & (window.alignment - 1) == 0
}

// Only saved desired extents are occupied here. Filesystems, partition tables,
// unlisted live views and protected extents are checked separately at application.
@[direct_array_access]
fn bundle_free_extents(set &PlanSet, disk int, window SpaceWindow, mut space FreeExtents) bool {
	if !bundle_set_valid(set) || disk < 0 || disk >= set.count || !space_window_valid(window) {
		plan_error(c'invalid space request or absent disk')
		return false
	}
	plan := unsafe { &set.plans[disk] }
	if window.end > plan.key.bytes || window.alignment < plan.key.sector
		|| window.start % plan.key.sector != 0 || window.end % plan.key.sector != 0 {
		plan_error(c'allocation region and alignment must fit the saved disk sectors')
		return false
	}
	// Sort indices, keeping the saved row order and all desired state untouched.
	mut order := [64]u32{}
	for i := u32(0); i < plan.count; i++ {
		mut at := i
		for at > 0 && plan.rows[order[at - 1]].offset > plan.rows[i].offset {
			order[at] = order[at - 1]
			at--
		}
		order[at] = i
	}
	space = FreeExtents{}
	mut cursor := window.start
	for i := u32(0); i < plan.count; i++ {
		row := plan.rows[order[i]]
		if row.offset >= window.end { break }
		if row.offset + row.length <= cursor { continue }
		add_free_gap(mut space, cursor, row.offset, window.alignment)
		cursor = row.offset + row.length
		if cursor >= window.end { break }
	}
	add_free_gap(mut space, cursor, window.end, window.alignment)
	return true
}

@[direct_array_access]
fn add_free_gap(mut space FreeExtents, start u64, end u64, alignment u64) {
	if start >= end { return }
	padding := (alignment - (start & (alignment - 1))) & (alignment - 1)
	// Bound before adding padding, including ranges near the u64 limit.
	if padding >= end - start { return }
	gap := FreeExtent{ offset: start + padding, length: end - start - padding }
	space.rows[space.count] = gap
	space.count++
	space.total += gap.length
	if gap.length > space.largest { space.largest = gap.length }
}

@[direct_array_access]
fn bundle_allocate_row(mut set PlanSet, disk int, window SpaceWindow, request &Request,
	mut chosen Request) bool {
	if request.version != 1 || request.slot >= 64 || request.flags > 1 || request.length == 0 {
		plan_error(c'invalid allocation slot, mode or size')
		return false
	}
	mut space := unsafe { &FreeExtents(C.alloca(sizeof(FreeExtents))) }
	unsafe { *space = FreeExtents{} }
	if !bundle_free_extents(unsafe { &set }, disk, window, mut space) { return false }
	if request.length % set.plans[disk].key.sector != 0 {
		plan_error(c'allocation size must be sector aligned')
		return false
	}
	for i in 0 .. space.count {
		if space.rows[i].length < request.length { continue }
		row := Request{
			slot:   request.slot
			offset: space.rows[i].offset
			length: request.length
			flags:  request.flags
		}
		if !bundle_add_row(mut set, disk, &row) { return false }
		chosen = row
		return true
	}
	plan_error(c'no aligned contiguous gap fits the requested size')
	return false
}

fn space_bundle_plan(path &char, disk int, window SpaceWindow, request &Request, allocate bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *edit = PlanEdit{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, allocate) { return 1 }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !read_bundle(edit.source, mut set, false) { return 1 }
	if allocate {
		mut chosen := Request{}
		if !bundle_allocate_row(mut set, disk, window, request, mut chosen)
			|| !publish_edit_bundle(edit, set) {
			return 1
		}
		return finish_bundle_report(C.printf(c'planned allocation disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu\n',
			u32(disk), chosen.slot, chosen.offset, chosen.length, chosen.flags) >= 0)
	}
	mut space := unsafe { &FreeExtents(C.alloca(sizeof(FreeExtents))) }
	unsafe { *space = FreeExtents{} }
	if !bundle_free_extents(set, disk, window, mut space) { return 1 }
	return finish_bundle_report(report_free_extents(disk, window, space))
}

@[direct_array_access]
fn report_free_extents(disk int, window SpaceWindow, space &FreeExtents) bool {
	for i in 0 .. space.count {
		if C.printf(c'space disk=%u offset=%lu bytes=%lu\n', u32(disk), space.rows[i].offset,
			space.rows[i].length) < 0 {
			return false
		}
	}
	return C.printf(c'planned space disk=%u start=%lu end=%lu alignment=%lu gaps=%u bytes=%lu largest=%lu\n',
		u32(disk), window.start, window.end, window.alignment, u32(space.count), space.total,
		space.largest) >= 0
}
