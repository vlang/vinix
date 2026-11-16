// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_pending_timestamps_local(file string, pending string, owners string) ! {
 staged := section(file, 'fn (mut f GpuFile) submit_g13_staged(', 'fn dispatch(', 'Shared copied submit')!
 require_order(staged, ['g13_submission_status()', 'new_g13_submission_timestamps(commands)',
  'defer { if !timestamps_transferred', 'f.lock.acquire()', 'f.lock.release()',
  'timestamps: timestamps', 'prepare_g13_compute_job_with_timestamps', 'prepare_g13_render_job_with_timestamps',
  'register_g13_pending', 'timestamps_transferred = true', 'queued = true'], 'Timestamp owner transfer and lock order')!
 require_order(owners, ['if !requested { return 0, G13SubmissionTimestamps{} }',
  'memory.malloc_packed_fallible(u64(commands.len) * sizeof(G13TimestampReferences))',
  'timestamps.entries[index] = G13TimestampReferences{}', 'f.capture_g13_timestamps(commands[index].timestamps',
  'if code != 0 { f.release_g13_submission_timestamps(timestamps);'], 'Bounded timestamp storage and prefix rollback')!
 require_order(pending, ['assert katomic.load(&item.callbacks_remaining) == 0',
  'signal_g13_submission_fence(item.final_fence', 'owner.release_g13_submission_timestamps(item.timestamps)',
  'queue.release_file_reference()', 'katomic.dec(mut &item.file.inflight_by_vm', 'memory.free(voidptr(item))'], 'Timestamp retirement precedes file/VM owner release')!
 // Registration may hand the node to another CPU before returning.
 tail := staged.all_after('timestamps_transferred = true')
 require(!tail.contains('pending.') && !tail.contains('timestamps.'), 'Accepted storage must never be accessed after transfer')!
}

fn check_pending_timestamps_reference(compute string, render string) ! {
 require_order(compute, ['user_timestamps.start = common::get_timestamp_object',
  'user_timestamps.end = common::get_timestamp_object', 'user_timestamps,',
  'user_timestamp_pointers: inner.user_timestamps.pointers()?'], 'Asahi compute retains captured destinations in work owner')!
 require_order(render, ['vtx_user_timestamps.start = common::get_timestamp_object',
  'vtx_user_timestamps.end = common::get_timestamp_object', 'frg_user_timestamps.start = common::get_timestamp_object',
  'frg_user_timestamps.end = common::get_timestamp_object', 'user_timestamps: frg_user_timestamps,',
  'user_timestamps: vtx_user_timestamps,'], 'Asahi render captures and retains each engine pair')!
}
