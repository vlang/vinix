module gpu

pub struct G13SubmissionJob {
pub:
	render  &G13RenderJobResources  = unsafe { nil }
	compute &G13ComputeJobResources = unsafe { nil }
}

pub struct G13InitialEvent {
pub:
	queue   &G13QueueResources = unsafe { nil }
	ordinal u32
	pipe    u32
	valid   bool
}

pub struct G13InitialEvents {
pub mut:
	values [2]G13InitialEvent
}

fn (mut mgr GpuManager) accept_g13_submission_locked(jobs [64]G13SubmissionJob, count u32) bool {
	if count == 0 || count > 64 { return false }
	mut queue := &G13QueueResources(unsafe { nil })
	mut last := [2]G13InitialEvent{}
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		if source.render != unsafe { nil } {
			assert source.compute == unsafe { nil } && !source.render.submitted && !source.render.released
			queue = source.render.queue
			last[0] = G13InitialEvent{ queue: queue, ordinal: source.render.ordinal, pipe: 0, valid: true }
		} else {
			assert source.compute != unsafe { nil } && !source.compute.submitted && !source.compute.released
			queue = source.compute.queue
			last[1] = G13InitialEvent{ queue: queue, ordinal: source.compute.ordinal, pipe: 1, valid: true }
		}
	}
	for pipe in 0 .. 2 {
		if last[pipe].valid { unsafe { queue.initial_events[pipe] = last[pipe] } }
	}
	return true
}

pub fn (mut mgr GpuManager) capture_g13_initial_events(queue &G13QueueResources, mask u32) ?G13InitialEvents {
	if mgr.state != .running { return none }
	mut capture := G13InitialEvents{}
	for pipe in 0 .. 2 {
		last := queue.initial_events[pipe]
		if !last.valid || mask & (u32(1) << pipe) == 0 { continue }
		mut active := false
		if pipe == 0 {
			for job in mgr.g13_render_jobs {
				if job.queue == queue && job.ordinal <= last.ordinal { active = true }
			}
		} else {
			for job in mgr.g13_compute_jobs {
				if job.queue == queue && job.ordinal <= last.ordinal { active = true }
			}
		}
		if active {
			capture.values[pipe] = last
			mgr.capture_pins++
		}
	}
	return capture
}

pub fn (mut mgr GpuManager) release_g13_initial_events(mut capture G13InitialEvents) {
	for mut value in capture.values {
		if value.valid {
			assert mgr.capture_pins > 0
			mgr.capture_pins--
		}
		value = G13InitialEvent{}
	}
}

fn (mgr &GpuManager) resolve_initial_sources(queue &G13QueueResources, initial [2]u32,
	current [2]u32) ?[2]u32 {
	mut resolved := current
	for pipe, source in initial {
		if source == 0 || mgr.firmware_done[source - 1] { continue }
		mut latest := u32(0)
		if pipe == 0 {
			for job in mgr.g13_render_jobs {
				if job.queue != queue || job.ordinal >= source { continue }
				if !job.submitted { return none }
				if job.ordinal + 1 > latest { latest = job.ordinal + 1 }
			}
		} else {
			for job in mgr.g13_compute_jobs {
				if job.queue != queue || job.ordinal >= source { continue }
				if !job.submitted { return none }
				if job.ordinal + 1 > latest { latest = job.ordinal + 1 }
			}
		}
		resolved[pipe] = latest
	}
	return resolved
}
