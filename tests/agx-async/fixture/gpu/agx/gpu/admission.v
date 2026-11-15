module gpu

// Injected capacity service. The lifetime fixture runs the native preflight
// with real tickets, host prefixes, TVB binding and firmware-record storage.
pub fn (mut mgr GpuManager) g13_batch_ready(jobs [64]G13SubmissionJob, count u32) bool {
	mgr.admissions++
	if mgr.on_admit != unsafe { nil } {
		hook := mgr.on_admit
		mgr.on_admit = unsafe { nil }
		hook()
	}
	if mgr.state != .running || count == 0 || count > 64 { return false }
	mut queue := &G13QueueResources(unsafe { nil })
	mut events := [3]u32{}
	mut commands := [3]u32{}
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		owner := if source.render != unsafe { nil } { source.render.queue } else { source.compute.queue }
		if queue == unsafe { nil } { queue = owner }
		assert voidptr(queue) == voidptr(owner)
		initial := if source.render != unsafe { nil } { source.render.initial_sources } else { source.compute.initial_sources }
		barriers := if source.render != unsafe { nil } { source.render.barrier_sources } else { source.compute.barrier_sources }
		resolved := mgr.resolve_initial_sources(queue, initial, barriers) or { return false }
		mut prefixes := u32(0)
		for value in resolved { if value != 0 { prefixes++ } }
		if source.render != unsafe { nil } {
			assert !source.render.submitted && !source.render.released
			events[0]++
			events[1]++
			commands[0] += 1 + prefixes
			commands[1] += 2
		} else {
			assert !source.compute.submitted && !source.compute.released
			events[2]++
			commands[2] += 1 + prefixes
		}
	}
	if mgr.g13_queue_dispatch_blocked_locked(queue) { return false }
	mut used := [3]u32{}
	for job in mgr.g13_render_jobs {
		if job.submitted && voidptr(job.queue) == voidptr(queue) { used[0]++; used[1]++ }
	}
	for job in mgr.g13_compute_jobs {
		if job.submitted && voidptr(job.queue) == voidptr(queue) { used[2]++ }
	}
	for pipe in 0 .. 3 {
		if events[pipe] != 0 && (used[pipe] + events[pipe] >= queue.admission_slots[pipe]
			|| commands[pipe] >= queue.admission_space[pipe]) { return false }
	}
	return true
}
