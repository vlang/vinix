// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 3, 'usage: render-timestamp-counterexamples ASYNC_RUNNER FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[2])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 variants := [
  ['wrong-stage', 'file.v', '--file-source', 'render_stage_finished[pipe], true',
   'render_stage_finished[1 - pipe], true', 'completed stage releases exactly its selected pair'],
  ['aggregate-only', 'submission_timestamps.v', '--timestamp-source', '!katomic.load(&command.render_stage_finished[pipe])',
   '!katomic.load(&command.callback_finished)', 'completed stage releases exactly its selected pair'],
  ['early-done', 'submission_timestamps.v', '--timestamp-source', '!katomic.load(&command.render_stage_finished[pipe])',
   '!katomic.load(&command.done)', 'forged completion must retain stage destinations'],
  ['cross-stage-release', 'submission_timestamps.v', '--timestamp-source',
   'file.release_g13_timestamp_pair(mut item.timestamps.entries[index], u32(pipe))',
   'file.release_g13_timestamps(mut item.timestamps.entries[index])', 'active peer retains both timestamp destinations'],
 ]
 mut receipts := []string{}
 for item in variants {
  source := os.read_file(repo + '/kernel/gpu/agx/file/' + item[1])!
  assert source.count(item[3]) == 1, item[0]
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  mutant := source.replace(item[3], item[4])
  os.write_file(dir + '/source.v', mutant)!
  os.setenv('AGX_ASYNC_TEST_BINARY', dir + '/test', true)
  os.setenv('AGX_ASYNC_TEST_C', dir + '/test.c', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args([item[2], dir + '/source.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('FAIL: fn file.check_render_stage_timestamps:')
   && log.contains(item[5]) && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(mutant.bytes()).hex()
  println(item[0] + ': compiled; designated render timestamp assertion failed')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
