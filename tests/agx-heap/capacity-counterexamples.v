// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: capacity-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 retire := 'old.free()'
 assert source.count(retire) == 1
 variants := [
  ['original-source', os.read_file(os.args[2])!],
  ['missing-retirement', source.replace(retire, '')],
  ['skipped-first-retirement', source.replace(retire, 'if old.cap != 2 { old.free() }')],
 ]
 mut receipts := []string{}
 for item in variants {
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  assert item[1] != source
  os.write_file(dir + '/alloc.v', item[1])!
  os.setenv('AGX_HEAP_TEST_C', dir + '/test.c', true)
  os.setenv('AGX_HEAP_TEST_BINARY', dir + '/test', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize-capacity', '--allocator-source', dir + '/alloc.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('GPU heap growth must free the previous pointer buffer')
   && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
  println(item[0] + ': compiled; designated heap capacity failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
