// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 3, 'usage: render-retirement-counterexamples RUNNER FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[2])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
 variants := [
  ['wait-peer', 'if job.retirement_failed && !job.quarantined {',
   'if !vertex_done || !fragment_done { return 0 }\n\tif job.retirement_failed && !job.quarantined {',
   'gpu.check_render_retirement_matrix:', 'independent vertex free-pointer image'],
  ['wrong-vertex-pipe', 'mgr.retire_g13_subqueue_locked(job.queue, 0, job.vertex_retirement_sequence, job.vertex_ring_slot)',
   'mgr.retire_g13_subqueue_locked(job.queue, 1, job.vertex_retirement_sequence, job.vertex_ring_slot)',
   'gpu.check_render_retirement_matrix:', 'completed stage free pointers'],
  ['fragment-coupled', 'if fragment_done && !job.fragment_retirement_published {',
   'if vertex_done && fragment_done && !job.fragment_retirement_published {',
   'gpu.check_render_retirement_matrix:', 'independent fragment free-pointer image'],
  ['premature-error', 'return if fragment_done { -1 } else { 0 }', 'return -1',
   'gpu.check_render_retirement_failure:', 'partial failure must wait for active peer'],
  ['forget-error', 'if job.retirement_failed && !job.quarantined {', 'if false {',
   'gpu.check_render_retirement_failure:', 'sticky failure must be reported after peer completion'],
  ['early-shared-cleanup', 'if retirement == 0 { continue }', 'if false { continue }',
   'gpu.GpuManager.retirement_test_free:', 'shared backing cannot be freed before both stage retirements'],
  ['aggregate-gate', 'if !job.vertex_retirement_published || !job.fragment_retirement_published { return 0 }',
   'if !job.vertex_retirement_published && !job.fragment_retirement_published { return 0 }',
   'gpu.check_render_retirement_matrix:', 'stage completion result'],
  ['missing-vertex-notification', 'job.stage_completion(0, job.completion_data)', 'job.stage_completion(1, job.completion_data)',
   'gpu.check_render_reaper_integration:', 'completed vertex stage publishes its private notification'],
  ['stage-callback-live', 'job.stage_completion = unsafe { nil }', 'job.stage_completion = job.stage_completion',
   'gpu.check_render_reaper_integration:', 'aggregate callback clears stage callback backing'],
  ['vertex-credit-held', '!queue.subqueues[0].events.record_completion(job.vertex_event_slot, job.vertex_stamp_value)', 'false',
   'gpu.check_render_event_credits:', 'completed render stage returns event admission credit'],
  ['fragment-credit-held', '!queue.subqueues[1].events.record_completion(job.fragment_event_slot, job.fragment_stamp_value)', 'false',
   'gpu.check_render_event_credits:', 'completed render stage returns event admission credit'],
 ]
 mut receipts := []string{}
 for item in variants {
  assert source.count(item[1]) == 1, item[0]
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  mutant := source.replace(item[1], item[2])
  os.write_file(dir + '/g13.v', mutant)!
  os.setenv('AGX_G13_TEST_BINARY', dir + '/test', true)
  os.setenv('AGX_G13_TEST_C', dir + '/test.c', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize', '--g13-source', dir + '/g13.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('FAIL: fn ' + item[3]) && log.contains(item[4])
   && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(mutant.bytes()).hex()
  println(item[0] + ': compiled; designated render retirement assertion failed')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
