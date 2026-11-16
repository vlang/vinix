// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_render_retirement_local(native string) ! {
 stages := section(native, 'fn (mut mgr GpuManager) retire_g13_render_stages_locked(', 'fn build_g13_attachments(', 'Independent render stage retirement')!
 require_order(stages, ['if job.retirement_published { return 1 }',
  'vertex_done := job.vertex_retirement_published || job.quarantined',
  'fragment_done := job.fragment_retirement_published || job.quarantined',
  'if job.retirement_failed && !job.quarantined',
  'return if vertex_done && fragment_done { -1 } else { 0 }',
  'if vertex_done && !job.vertex_retirement_published',
  'mgr.retire_g13_subqueue_locked(job.queue, 0, job.vertex_retirement_sequence, job.vertex_ring_slot)',
  'return if fragment_done { -1 } else { 0 }', 'job.vertex_retirement_published = true',
  'if fragment_done && !job.fragment_retirement_published',
  'mgr.retire_g13_subqueue_locked(job.queue, 1, job.fragment_retirement_sequence, job.fragment_ring_slot)',
  'return if vertex_done { -1 } else { 0 }', 'job.fragment_retirement_published = true',
  'if !job.vertex_retirement_published || !job.fragment_retirement_published { return 0 }',
  'job.retirement_published = true'], 'Separate ring publication and shared completion gate')!
 require(stages.count('job.retirement_failed = true') == 2, 'Both stage failures must remain sticky')!
 reaper := section(native, 'fn (mut mgr GpuManager) reap_g13_render_jobs()', '// Firmware is stopped before this is called', 'Shared render reaper')!
 require_order(reaper, ['retirement := mgr.retire_g13_render_stages_locked(mut owned)',
  'if retirement == 0 { continue }', 'if retirement < 0 {', 'owned.quarantined = true',
  'complete_g13_render_job(mut owned, false)', 'continue', 'read_g13_render_result(owned)',
  'mgr.free_g13_render_job_locked(mut owned, true)', 'complete_g13_render_job(mut owned, owned.error.status == 0)'], 'No shared cleanup or callback before both stages complete')!
 require(!reaper.contains('event.stamp_value_completed('), 'Whole-pass stamp gates must not prevent independent stage retirement')!
}

fn check_render_retirement_reference(workqueue string, render string) ! {
 require_order(workqueue, ['let last_wptr = inner.pending[completed_commands - 1].inner.wptr()',
  'for mut cmd in inner.pending.drain(..completed_commands)', 'cmd.as_mut().inner_mut().complete()',
  'raw.cpu_freeptr.store(last_wptr, Ordering::Release)'], 'Asahi publishes each workqueue completed prefix')!
 require_order(render, ['let frag_job = job.get_frag()?', 'frag_job.add_cb(frag,',
  'let vtx_job = job.get_vtx()?', 'vtx_job.add_cb(vtx,'], 'Asahi render uses separate stage workqueues')!
}
