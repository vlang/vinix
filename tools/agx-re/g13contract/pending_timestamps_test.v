module g13contract

import g13layout

fn test_timestamp_owners_require_bounded_capture_and_retirement_before_file_release() {
 root := g13layout.repo_root()
 file := read(root + '/kernel/gpu/agx/file/file.v')!
 pending := read(root + '/kernel/gpu/agx/file/pending.v')!
 owners := read(root + '/kernel/gpu/agx/file/submission_timestamps.v')!
 check_pending_timestamps_local(file, pending, owners)!
 for token in ['defer { if !timestamps_transferred', 'timestamps: timestamps', 'timestamps_transferred = true'] {
  if _ := check_pending_timestamps_local(file.replace(token, ''), pending, owners) { assert false, token }
 }
 for token in ['katomic.store(mut &submission.commands[command_index].callback_finished, true)', 'command_index := state.command_index'] {
  if _ := check_pending_timestamps_local(file.replace(token, ''), pending, owners) { assert false, token }
 }
 if _ := check_pending_timestamps_local(file, pending.replace('release_completed_g13_timestamps(item)', ''), owners) { assert false }
 for token in ['command.timestamps_released || !katomic.load(&command.callback_finished)', 'command.timestamps_released = true'] {
  if _ := check_pending_timestamps_local(file, pending, owners.replace(token, '')) { assert false, token }
 }
 for token in ['owner.release_g13_submission_timestamps(item.timestamps)', 'assert katomic.load(&item.callbacks_remaining) == 0'] {
  if _ := check_pending_timestamps_local(file, pending.replace(token, ''), owners) { assert false, token }
 }
 for token in ['if !requested { return 0, G13SubmissionTimestamps{} }',
  'timestamps.entries[index] = G13TimestampReferences{}', 'f.release_g13_submission_timestamps(timestamps);'] {
  if _ := check_pending_timestamps_local(file, pending, owners.replace(token, '')) { assert false, token }
 }
}
