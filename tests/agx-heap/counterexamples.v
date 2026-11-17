// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 free_record := 'unsafe { free(a) }'
 assert source.count(free_record) == 1 && source.count('a.in_use = false') == 1
 variants := [
  ['original-source', os.read_file(os.args[2])!, '--measure', 'AGX heap repeated allocation retains metadata'],
  ['missing-free', source.replace(free_record, ''), '--measure', 'AGX heap repeated allocation retains metadata'],
  ['early-free', source.replace(free_record, '').replace('a.in_use = false', 'a.in_use = false\nfree(a)'),
   '--sanitize', 'AddressSanitizer: heap-use-after-free'],
  ['double-free', source.replace(free_record, free_record + '\n' + free_record),
   '--sanitize', 'AddressSanitizer: attempting double-free'],
 ]
 mut receipts := []string{}
 for item in variants {
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  os.write_file(dir + '/alloc.v', item[1])!
  os.setenv('AGX_HEAP_TEST_C', dir + '/test.c', true)
  os.setenv('AGX_HEAP_TEST_BINARY', dir + '/test', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args([item[2], '--allocator-source', dir + '/alloc.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains(item[3]) && !log.contains('error:')
   && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  if item[2] == '--measure' {
   sample := log.all_after('AGX-HEAP-RECORD bytes=').all_before('\n').u64()
   assert sample >= 24 && log.contains('retained_blocks=10000 retained_bytes=' + (10000 * sample).str())
   if item[0] == 'original-source' { assert sample == 32 && log.contains('retained_blocks=10000 retained_bytes=320000') }
  }
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
  println(item[0] + ': compiled; designated heap ownership failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
