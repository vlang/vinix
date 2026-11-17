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
  'queue.release_file_reference()', 'katomic.dec(mut &item.vm.inflight', 'memory.free(voidptr(item))'], 'Timestamp retirement precedes file/VM owner release')!
 // Registration may hand the node to another CPU before returning.
 tail := staged.all_after('timestamps_transferred = true')
 require(!tail.contains('pending.') && !tail.contains('timestamps.'), 'Accepted storage must never be accessed after transfer')!
 discard := section(file, 'fn discard_g13_completion(', 'fn finish_g13_submit(', 'Private command callback retirement')!
 require_order(discard, ['command_index := state.command_index', 'free(voidptr(state))',
  'katomic.store(mut &submission.commands[command_index].callback_finished, true)',
  'katomic.dec(mut &submission.callbacks_remaining)'], 'Callback backing retires before command ownership publication')!
 reap := section(owners, 'fn release_completed_g13_timestamps(', '// Consume one owner', 'Completed command timestamp release')!
 require_order(reap, ['if item.timestamps.count == 0', 'command.timestamps_released || !katomic.load(&command.callback_finished)',
  'file.release_g13_timestamps(mut item.timestamps.entries[index])', 'command.timestamps_released = true'], 'Each completed command releases once')!
 require(!reap.contains('command.done') && !reap.contains('final_fence'), 'Early completion and user fences must not release captures')!
 require_order(reap, ['command.stage_timestamps_released[pipe] || !katomic.load(&command.render_stage_finished[pipe])',
  'file.release_g13_timestamp_pair(mut item.timestamps.entries[index], u32(pipe))',
  'command.stage_timestamps_released[pipe] = true'], 'Independent private stage ownership release')!
 stage := section(file, 'fn g13_render_stage_completed(', 'fn g13_render_completed(', 'Private stage callback')!
 require_order(stage, ['pipe >= 2', 'state.submission == unsafe { nil }',
  'katomic.store(mut &state.submission.commands[state.command_index].render_stage_finished[pipe], true)'], 'Stage callback only publishes private completion')!
 require(!stage.contains('release_g13') && !stage.contains('.lock.'), 'Stage callback cannot take file locks or release owners')!
 require(file.contains('set_g13_render_completion(entry.render_job, g13_render_completed, g13_render_stage_completed, voidptr(completion))'), 'Stage and aggregate callbacks must share installed owner')!
 require_order(pending, ['if earlier || poll_g13_pending(mut item) {', 'release_completed_g13_timestamps(item)',
  'retained_count++'], 'Retained and FIFO-blocked nodes still reap completed command owners')!
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
