// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_compute_retirement_local(native string) ! {
 reaper := section(native, 'fn (mut mgr GpuManager) reap_g13_compute_jobs()',
  '// Firmware is stopped before this is called, so no completion flush', 'Compute retirement')!
 require_order(reaper, ['if !job.submitted', 'if job.quarantined', 'continue',
  'if !job.quarantined && !event.stamp_value_completed(job.event_slot, job.stamp_value)',
  'continue', 'if !owned.retirement_published',
  'mgr.retire_g13_subqueue_locked(owned.queue, 2, owned.retirement_sequence, owned.ring_slot)',
  'queue.subqueues[2].events.record_completion(owned.event_slot, owned.stamp_value)',
  'mgr.state = .error', 'owned.quarantined = true', 'complete_g13_compute_job(mut owned, false)', 'continue',
  'owned.retirement_published = true', 'owned.completion_result = owned.timestamp_values()',
  'owned.completion_ready = true', 'mgr.end_g13_operation_locked()',
  'complete_g13_compute_job(mut owned, owned.error.status == 0)', 'mgr.free_g13_compute_job_locked(mut owned, true)'],
  'Compute credit follows completion/ring proof and precedes shared cleanup')!
}
