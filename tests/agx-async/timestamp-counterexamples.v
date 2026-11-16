// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 3, 'usage: timestamp-counterexamples RUNNER FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[2])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 variants := [
  ['capture-rollback', 'submission_timestamps.v', '--timestamp-source',
   'if code != 0 { f.release_g13_submission_timestamps(timestamps);', 'if code != 0 {',
   'file.check_timestamp_failures:', 'capture prefix rollback'],
  ['pending-retirement', 'pending.v', '--pending-source',
   'owner.release_g13_submission_timestamps(item.timestamps)', '_ = owner',
   'file.check_timestamp_retirement:', 'retirement releases detached mapping once'],
  ['transfer-flag', 'file.v', '--file-source',
   'timestamps_transferred = true', 'timestamps_transferred = false',
   'file.check_timestamp_retirement:', 'all command captures retained'],
  ['compute-pair', 'file.v', '--file-source',
   'compute_ts := timestamps.addresses(index, 2)', 'compute_ts := timestamps.addresses(index, 0)',
   'file.check_timestamp_retirement:', 'resolved compute destinations'],
 ]
 mut receipts := []string{}
 for item in variants {
  source := os.read_file(repo + '/kernel/gpu/agx/file/' + item[1])!
  assert source.count(item[3]) == 1, item[0]
  mutant := source.replace(item[3], item[4])
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  path := dir + '/' + item[1]; os.write_file(path, mutant)!
  os.setenv('AGX_ASYNC_TEST_BINARY', dir + '/test', true)
  os.unsetenv('AGX_ASYNC_TEST_C')
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args([item[2], path]); process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('FAIL: fn ' + item[5]) && log.contains(item[6])
   && !log.contains('error:') && os.is_file(dir + '/test'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' sha256 ' + sha256.sum(mutant.bytes()).hex()
  println(item[0] + ': compiled; intended timestamp ownership assertion failed')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
