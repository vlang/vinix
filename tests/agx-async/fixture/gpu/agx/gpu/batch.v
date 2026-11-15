module gpu

// Adversarial backend: retains partial-transfer and immediate-free injection
// to verify the file layer's ownership mask. The native publisher is separately
// exercised with actual rings and never returns a partial mask.
pub fn (mut mgr GpuManager) submit_g13_batch(jobs [64]G13SubmissionJob, count u32) u64 {
	mut transferred := u64(0)
	mut blocked := [2]bool{}
	for index := u32(0); index < count; index++ {
		if mgr.state != .running { break }
		source := jobs[index]
		compute := source.compute != unsafe { nil }
		pipe := if compute { 1 } else { 0 }
		if blocked[pipe] { continue }
		ordinal := if compute { source.compute.ordinal } else { source.render.ordinal }
		dependencies := if compute { source.compute.barrier_sources } else { source.render.barrier_sources }
		for dependency in dependencies {
			if dependency == 0 { continue }
			for job in mgr.g13_compute_jobs { if job.ordinal + 1 == dependency && !job.submitted { blocked[pipe] = true } }
			for job in mgr.g13_render_jobs { if job.ordinal + 1 == dependency && !job.submitted { blocked[pipe] = true } }
		}
		if blocked[pipe] { continue }
		accepted := if compute { mgr.submit_g13_compute_job(source.compute) } else { mgr.submit_g13_render_job(source.render) }
		if accepted { transferred |= u64(1) << index } else { blocked[pipe] = true }
		if mgr.immediate_complete && int(ordinal) == mgr.immediate_fault_at { break }
	}
	return transferred
}
