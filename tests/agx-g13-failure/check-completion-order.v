// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn body(source string, name string) !string {
	for line in source.split_into_lines() {
		if line.len == 0 || line[0].is_space() { continue }
		if !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { return error(name) }
		finish := source.index_after('\n}\n', start) or { return error(name) }
		return source[start..finish + 3]
	}
	return error('missing ' + name)
}
fn normalize(source string, function string) !string {
	mut result := body(source, function)!
	mut constants := map[string]string{}
	for line in source.split_into_lines() {
		if !line.starts_with('_SL(_str_') { continue }
		name := line.all_after('_SL(').all_before(',')
		constants[name] = line.all_after(name + ', ')
	}
	mut i := 0
	mut out := []u8{}
	for i < result.len {
		if matches_at(result, i, '_str_') {
			mut end := i + 5
			for end < result.len && result[end].is_digit() { end++ }
			key := result[i..end]
			assert key in constants, key
			out << constants[key].bytes(); i = end
		} else { out << result[i]; i++ }
	}
	return out.bytestr()
}
fn ordered(source string, tokens []string) {
	mut position := 0
	for token in tokens {
		position = (source.index_after(token, position) or { panic(token) }) + token.len
	}
}


fn matches_at(source string, start int, prefix string) bool {
	if start + prefix.len > source.len { return false }
	for n, b in prefix { if source[start + n] != b { return false } }
	return true
}

fn discard_path_hashes(source string) string {
 mut out := []u8{}
 mut i := 0
 for i < source.len {
  if matches_at(source, i, '__discard_') && i + 10 < source.len && source[i + 10].is_digit() {
   mut end := i + 10
   for end < source.len && source[end].is_digit() { end++ }
   assert source[end] == `_`
   out << '__discard_PATH'.bytes(); i = end
  } else { out << source[i]; i++ }
 }
 return out.bytestr()
}

fn declaration(source string, name string) !string {
 start := source.index('struct ' + name + ' {') or { return error(name) }
 end := source.index_after('\n};', start) or { return error(name) }
 return source[start..end + 3]
}


fn main() {
 assert os.args.len == 3 || (os.args.len == 4 && os.args[3] == '--x86'),
  'usage: check-completion-order BASELINE_C CURRENT_C [--x86]'
 old := os.read_file(os.args[1])!
 current := os.read_file(os.args[2])!
 if os.args.len == 4 {
  assert discard_path_hashes(old) == discard_path_hashes(current)
  println('x86 generated C matches baseline after normalizing compiler discard-variable path hashes.')
  return
 }
 for suffix in ['prepare_g13_render_job', 'prepare_g13_render_job_with_timestamps',
  'prepare_g13_compute_job', 'prepare_g13_compute_job_with_timestamps',
  'free_g13_render_job_locked', 'free_g13_compute_job_locked', 'retire_g13_subqueue_locked',
  'submit_g13_batch', 'retire_g13_render_stages_locked', 'release_g13_queue_resources',
  'release_all_g13_render_jobs', 'release_all_g13_compute_jobs'] {
  symbol := 'gpu__agx__gpu__GpuManager__' + suffix
  assert normalize(old, symbol)! == normalize(current, symbol)!, symbol
 }
 for symbol in ['gpu__agx__file__GpuFile__close', 'gpu__agx__gpu__event_worker',
  'gpu__agx__file__GpuFile__capture_submission_queue', 'gpu__agx__file__release_submission_queue',
  'gpu__agx__file__GpuFile__reap_detached_timestamp_objects_locked', 'gpu__agx__file__discard_g13_completion',
  'gpu__agx__file__g13_compute_completed', 'gpu__agx__file__g13_render_completed',
  'gpu__agx__gpu__complete_g13_render_job', 'gpu__agx__gpu__complete_g13_compute_job',
  'gpu__agx__gpu__G13ComputeJobResources__timestamp_values', 'gpu__agx__gpu__read_g13_render_result',
  'gpu__agx__file__g13_render_stage_completed', 'gpu__agx__file__release_completed_g13_timestamps',
  'gpu__agx__file__GpuFile__release_g13_timestamp_pair', 'gpu__agx__file__g13_pending_error',
  'gpu__agx__file__cancel_g13_pending', 'gpu__agx__file__poll_g13_pending',
  'gpu__agx__file__process_pending_submissions', 'gpu__agx__file__finish_g13_submit',
  'gpu__agx__file__GpuFile__submit_g13_staged'] {
  assert normalize(old, symbol)! == normalize(current, symbol)!, symbol
 }
 for suffix in ['retain', 'release', 'ticket', 'resolve_initial', 'can_submit', 'admit', 'can_publish_batch', 'can_publish', 'publish', 'record_completion'] {
  symbol := 'gpu__agx__event__WorkQueueEvents__' + suffix
  assert normalize(old, symbol)! == normalize(current, symbol)!, symbol
 }
 for symbol in ['gpu__agx__event__WorkQueueEvents', 'gpu__agx__event__TicketBlock', 'gpu__agx__event__PendingTicket',
  'gpu__agx__event__Ticket', 'gpu__agx__gpu__G13RenderJobResources', 'gpu__agx__gpu__G13ComputeJobResources',
  'gpu__agx__gpu__G13QueueResources', 'fw__G13JobTimestamps'] {
  assert declaration(old, symbol)! == declaration(current, symbol)!, symbol
 }
 for engine in ['render', 'compute'] {
  prefix := 'gpu__agx__gpu__'
  symbol := prefix + 'GpuManager__reap_g13_' + engine + '_jobs'
  before := normalize(old, symbol)!; after := normalize(current, symbol)!
  success := prefix + 'complete_g13_' + engine + '_job(owned, owned->error.status == 0);'
  failure := prefix + 'complete_g13_' + engine + '_job(owned, false);'
  cleanup := 'if (' + prefix + 'GpuManager__free_g13_' + engine + '_job_locked(mgr, owned, true)) {'
  mut restored := after
  early := '			' + success + '
'
  assert after.count(early) == 1 && after.count(success) == 1
  assert before.count('				' + success + '
') == 1
  assert before.count(failure) == 2 && after.count(failure) == 1
  restored = restored.replace(early, '')
  deletion := '
				array_delete(&mgr->g13_' + engine + '_jobs, v_index);
'
  assert restored.count(deletion) == 1
  restored = restored.replace(deletion, deletion + '				' + success + '
')
  quarantine := '			} else {
				owned->quarantined = true;
'
  assert restored.count(quarantine) == 1
  restored = restored.replace(quarantine, quarantine + '				' + failure + '
')
  if engine == 'render' {
   cached := '			if (!owned->completion_result_ready) {
				owned->completion_result = ' + prefix + 'read_g13_render_result(owned);
				owned->completion_result_ready = true;
			}
'
   assert restored.count(cached) == 1
   restored = restored.replace(cached, '			owned->completion_result = ' + prefix + 'read_g13_render_result(owned);
			owned->completion_result_ready = true;
')
  }
  assert restored == before, engine + ': only callback ordering and render cache guard may differ'
  ordered(after, ['owned->completion_result =', 'end_g13_operation_locked', success, cleanup, 'v_free(owned)'])
 }
 println('Completion order native review: eight owning/event/timestamp declarations, ten event methods, twelve preparation/cleanup/queue/stop bodies and all file/pending ownership/error publication functions match baseline.')
 println('Both reapers reduce exactly to baseline after restoring only callback ordering and the render cache guard. Hardware result publication precedes backing disposal; queue/VM ownership guards remain unchanged.')
 println('Baseline ARM C sha256 ' + digest(os.args[1])!)
 println('Current ARM C sha256 ' + digest(os.args[2])!)
}
