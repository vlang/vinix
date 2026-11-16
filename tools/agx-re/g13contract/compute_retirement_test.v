module g13contract

import g13layout

fn test_compute_retirement_requires_stamp_pipe_credit_and_quarantine_gates() {
 native := read(g13layout.repo_root() + '/kernel/gpu/agx/gpu/g13.v')!
 check_compute_retirement_local(native)!
 for token in ['if !job.submitted',
  'if !job.quarantined && !event.stamp_value_completed(job.event_slot, job.stamp_value)',
  'if !owned.retirement_published',
  'queue.subqueues[2].events.record_completion(owned.event_slot, owned.stamp_value)',
  'owned.retirement_published = true', 'owned.completion_ready = true'] {
  if _ := check_compute_retirement_local(native.replace(token, '')) { assert false, token }
 }
 if _ := check_compute_retirement_local(native.replace('retire_g13_subqueue_locked(owned.queue, 2,', 'retire_g13_subqueue_locked(owned.queue, 1,')) { assert false }
}
