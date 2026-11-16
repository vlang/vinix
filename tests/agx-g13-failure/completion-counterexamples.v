// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 3, 'usage: completion-counterexamples FAILURE_RUNNER FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[2])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
 mut receipts := []string{}
 for engine in ['render', 'compute'] {
  completion := 'complete_g13_' + engine + '_job(mut owned, owned.error.status == 0)'
  cleanup := 'if mgr.free_g13_' + engine + '_job_locked(mut owned, true) {'
  mut variants := [
   ['late', source.replace(completion, '').replace(cleanup, cleanup + '\n\t\t\t' + completion),
    'gpu.GpuManager.' + if engine == 'render' { 'retirement_test_free:' } else { 'compute_retirement_free:' },
    'completed ' + engine + ' callback precedes backing disposal'],
   ['false-failure', source.replace(completion, 'complete_g13_' + engine + '_job(mut owned, false)'),
    'gpu.check_' + engine + if engine == 'render' { '_reaper_integration:' } else { '_retirement_matrix:' },
    if engine == 'render' { 'retirement_success && retirement_callbacks == 1' } else { 'cleanup refusal preserves successful compute completion' }],
   ['lost-error', source.replace(completion, 'complete_g13_' + engine + '_job(mut owned, true)'),
    'gpu.check_' + engine + '_error_completion:', engine + ' hardware errors survive deferred cleanup'],
  ]
  start := source.index('pub fn (mut mgr GpuManager) release_g13_queue_resources(') or { panic('queue release') }
  end := source.index_after('// Quarantined backing must retire', start) or { panic('queue release end') }
  method := source[start..end]
  guard := 'for job in mgr.g13_' + engine + '_jobs {'
  peer := if engine == 'render' { 'compute' } else { 'render' }
  assert method.count(guard) == 1
  variants << ['lost-queue-owner', source[..start] + method.replace(guard, 'for job in mgr.g13_' + peer + '_jobs {') + source[end..],
   'gpu.check_' + engine + if engine == 'render' { '_reaper_integration:' } else { '_retirement_matrix:' },
   'completed ' + engine + ' backing retains queue ownership after submission pins end']
  if engine == 'render' {
   assert source.count('if !owned.completion_result_ready {') == 1
   variants << ['cache-reread', source.replace('if !owned.completion_result_ready {', 'if true {'),
    'gpu.check_render_reaper_integration:', 'render cleanup retries retain the first cached result']
  }
  for item in variants {
   name := engine + '-' + item[0]
   dir := state + '/' + name; os.mkdir_all(dir)!
   assert item[1] != source
   os.write_file(dir + '/g13.v', item[1])!
   os.setenv('AGX_G13_TEST_BINARY', dir + '/test', true)
   os.setenv('AGX_G13_TEST_C', dir + '/test.c', true)
   mut process := os.new_process(os.abs_path(os.args[1]))
   process.set_args(['--sanitize', '--g13-source', dir + '/g13.v'])
   process.set_redirect_stdio(); process.run()
   log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
   os.write_file(dir + '/run.log', log)!
   assert process.code != 0 && log.contains('FAIL: fn ' + item[2]) && log.contains(item[3])
    && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), name + ': ' + log
   process.close()
   receipts << name + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
   println(name + ': compiled; designated completion assertion failed')
  }
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
