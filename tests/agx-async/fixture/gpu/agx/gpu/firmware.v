module gpu

// Injected firmware execution is separate from CPU callback delivery. Integer
// source ordinals model the already checked firmware prefixes, never job refs.
fn (mgr &GpuManager) firmware_barriers_ready(sources [2]u32) bool {
	for source in sources {
		if source != 0 && !mgr.firmware_done[source - 1] { return false }
	}
	return true
}

pub fn (mut mgr GpuManager) execute_vertex(ordinal u32) bool {
	for job in mgr.g13_render_jobs {
		if job.ordinal != ordinal { continue }
		if !job.submitted || !mgr.firmware_barriers_ready(job.barrier_sources) { return false }
		for prior in mgr.g13_render_jobs {
			if prior.queue == job.queue && prior.ordinal < ordinal && prior.submitted
				&& !mgr.firmware_vertex_done[prior.ordinal] {
				return false
			}
		}
		mgr.firmware_vertex_done[ordinal] = true
		return true
	}
	return false
}

pub fn (mut mgr GpuManager) execute_firmware(ordinal u32, status u32) bool {
	assert ordinal < 1024 && !mgr.firmware_done[ordinal]
	for job in mgr.g13_compute_jobs {
		if job.ordinal != ordinal { continue }
		if !job.submitted || !mgr.firmware_barriers_ready(job.barrier_sources) { return false }
		for prior in mgr.g13_compute_jobs {
			if prior.queue == job.queue && prior.ordinal < ordinal && prior.submitted
				&& !mgr.firmware_done[prior.ordinal] {
				return false
			}
		}
		mgr.firmware_status[ordinal] = status
		mgr.firmware_done[ordinal] = true
		return true
	}
	if !mgr.execute_vertex(ordinal) { return false }
	for job in mgr.g13_render_jobs {
		if job.ordinal != ordinal { continue }
		for prior in mgr.g13_render_jobs {
			if prior.queue == job.queue && prior.ordinal < ordinal && prior.submitted
				&& !mgr.firmware_done[prior.ordinal] {
				return false
			}
		}
		mgr.firmware_status[ordinal] = status
		mgr.firmware_done[ordinal] = true
		return true
	}
	return false
}

pub fn (mut mgr GpuManager) retire_firmware(ordinal u32) {
	assert mgr.firmware_done[ordinal]
	for job in mgr.g13_compute_jobs {
		if job.ordinal == ordinal {
			mgr.finish_compute_at(ordinal, mgr.firmware_status[ordinal])
			return
		}
	}
	mgr.finish_render_at(ordinal, mgr.firmware_status[ordinal])
}
