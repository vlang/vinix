// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolResizeRequest {
mut:
	key DiskKey
	pool u32
	start u64
	end u64
}

struct PoolResizeBatch {
mut:
	count int
	rows [64]PoolResizeRequest
}

struct PoolResizeResults {
mut:
	count int
	rows [64]PoolRegion
	previous [64]SpaceWindow
}

// Check occupation against each original window and disjointness against the
// complete candidate. Adjacent pools can exchange unused bytes in either request
// order, without publishing an intermediate overlap or changing their priority.
@[direct_array_access]
fn bundle_pool_resize_batch(mut set PlanSet, batch &PoolResizeBatch,
	mut results PoolResizeResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for previous in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
				plan_error(c'resize bundle has ambiguous disk identities'); return false
			}
		}
	}
	for i in 0 .. batch.count {
		request := batch.rows[i]
		if request.pool >= 64 || request.start >= request.end || !forget_identity_valid(unsafe { &request.key }) { return false }
		for previous in 0 .. i {
			other := batch.rows[previous]
			if request.pool == other.pool && enrollment_identity_matches(unsafe { &request.key }, unsafe { &other.key }) {
				plan_error(c'resize batch repeats a pool member'); return false
			}
		}
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &PoolResizeResults(C.alloca(sizeof(PoolResizeResults))) }
	unsafe { *candidate = set; *outcome = PoolResizeResults{count: batch.count} }
	for i in 0 .. batch.count {
		request := batch.rows[i]; mut disk := -1
		for at in 0 .. set.count {
			if enrollment_identity_matches(unsafe { &request.key }, unsafe { &set.plans[at].key }) { disk = at; break }
		}
		if disk < 0 { plan_error(c'resize disk identity is not enrolled'); return false }
		key := set.plans[disk].key
		if request.end > key.bytes || request.start % key.sector != 0 || request.end % key.sector != 0 {
			plan_error(c'resize bounds must fit saved disk sectors'); return false
		}
		mut found := false
		for at in 0 .. set.regions {
			previous := set.windows[at]
			if previous.pool != request.pool || previous.disk != u32(disk) { continue }
			for row := u32(0); row < set.plans[disk].count; row++ {
				mapping := set.plans[disk].rows[row]; mapping_end := mapping.offset + mapping.length
				start := if mapping.offset > previous.window.start { mapping.offset } else { previous.window.start }
				end := if mapping_end < previous.window.end { mapping_end } else { previous.window.end }
				if start < end && (request.start > start || request.end < end) {
					plan_error(c'resize would release occupied desired mapping bytes'); return false
				}
			}
			candidate.windows[at] = PoolRegion{pool: previous.pool, disk: previous.disk,
				window: SpaceWindow{start: request.start, end: request.end, alignment: previous.window.alignment}}
			outcome.previous[i] = previous.window; outcome.rows[i] = candidate.windows[at]; found = true; break
		}
		if !found { plan_error(c'resize pool member is absent'); return false }
	}
	if !bundle_set_valid(candidate) { plan_error(c'resized pool windows overlap or are invalid'); return false }
	set = unsafe { *candidate }; results = unsafe { *outcome }; return true
}

@[direct_array_access]
fn resize_batch_pool_plan(path &char, batch &PoolResizeBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolResizeResults(C.alloca(sizeof(PoolResizeResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolResizeResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_resize_batch(mut set, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-pool-resize') } } else { unsafe { &char(c'planned-pool-resize') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', results.count, operation) >= 0
	for i in 0 .. results.count {
		row := results.rows[i]; previous := results.previous[i]
		mut identity := [41]char{}; disk_identity(unsafe { &batch.rows[i].key }, &identity[0])
		action := if row.window.start == previous.start && row.window.end == previous.end { unsafe { &char(c'keep') } } else { unsafe { &char(c'resize') } }
		if C.printf(c'request=%d pool=%u disk=%u action=%s previous_start=%lu previous_end=%lu start=%lu end=%lu alignment=%lu identity=%s\n',
			i, row.pool, row.disk, action, previous.start, previous.end, row.window.start, row.window.end, row.window.alignment, &identity[0]) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
