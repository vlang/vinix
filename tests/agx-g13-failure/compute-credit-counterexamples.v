// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 3, 'usage: compute-credit-counterexamples FAILURE_RUNNER FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[2])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
 credit := '!queue.subqueues[2].events.record_completion(owned.event_slot, owned.stamp_value)'
 variants := [
  ['credit-held', 'reaper', credit, 'false', 'gpu.GpuManager.compute_retirement_free:', 'completed compute work returns event credit before disposal'],
  ['wrong-pipe', 'reaper', 'retire_g13_subqueue_locked(owned.queue, 2,', 'retire_g13_subqueue_locked(owned.queue, 1,',
   'gpu.check_compute_retirement_matrix:', 'completed compute must reach backing cleanup'],
  ['early-retirement', 'reaper', 'if !job.quarantined && !event.stamp_value_completed(job.event_slot, job.stamp_value)', 'if false',
   'gpu.check_compute_retirement_matrix:', 'running compute work must retain backing and credit'],
  ['lost-credit-error', 'reaper', credit,
   '!(queue.subqueues[2].events.record_completion(owned.event_slot, owned.stamp_value) || true)',
   'gpu.GpuManager.compute_retirement_free:', 'completed compute work returns event credit before disposal'],
  ['callback-replay', 'complete', 'job.completion = unsafe { nil }', 'job.completion = job.completion',
   'gpu.check_compute_retirement_matrix:', 'compute completion consumes its callback exactly once'],
 ]
 mut receipts := []string{}
 for item in variants {
  start_token := if item[1] == 'reaper' { 'fn (mut mgr GpuManager) reap_g13_compute_jobs()' } else { 'fn complete_g13_compute_job(' }
  end_token := if item[1] == 'reaper' { '// Firmware is stopped before this is called, so no completion flush' } else { '// Construct one byte-exact' }
  start := source.index(start_token) or { panic('target method') }
  end := source.index_after(end_token, start) or { panic('target end') }
  method := source[start..end]
  assert method.count(item[2]) == 1, item[0]
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  mutant := source[..start] + method.replace(item[2], item[3]) + source[end..]
  os.write_file(dir + '/g13.v', mutant)!
  os.setenv('AGX_G13_TEST_BINARY', dir + '/test', true)
  os.setenv('AGX_G13_TEST_C', dir + '/test.c', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize', '--g13-source', dir + '/g13.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('FAIL: fn ' + item[4]) && log.contains(item[5])
   && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(mutant.bytes()).hex()
  println(item[0] + ': compiled; designated compute retirement assertion failed')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
