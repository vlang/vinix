// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: bounds-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 post_gc := '\n\t\th.find_address_locked(h.end, aligned_size, actual_align) or {'
 assert source.count(post_gc) == 1
 variants := [
  ['original-source', os.read_file(os.args[2])!, 'invalid GPU heap alignment must not allocate'],
  ['requested-alignment', source.replace('size == 0 || (align != 0 && (align & (align - 1)) != 0)', 'size == 0'),
   'invalid GPU heap alignment must not allocate'],
  ['round-overflow', source.replace('value > ~u64(0) - mask', 'false'),
   'GPU heap allocation must match bounded division model'],
  ['interval-overflow', source.replace('address > end || size > end - address', 'false'),
   'overflowing GPU heap interval must not allocate'],
  ['post-gc-bounds', source.replace(post_gc, post_gc.replace('h.end', '~u64(0)')),
   'GPU heap allocation must match bounded division model'],
 ]
 mut receipts := []string{}
 for item in variants {
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  assert item[1] != source
  os.write_file(dir + '/alloc.v', item[1])!
  os.setenv('AGX_HEAP_TEST_C', dir + '/test.c', true)
  os.setenv('AGX_HEAP_TEST_BINARY', dir + '/test', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize-bounds', '--allocator-source', dir + '/alloc.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains(item[2]) && !log.contains('error:')
   && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  if item[0] == 'original-source' {
   mut overflow := os.new_process(dir + '/test')
   overflow.set_args(['--overflow-probe']); overflow.set_redirect_stdio(); overflow.run()
   overflow_log := overflow.stdout_slurp() + overflow.stderr_slurp(); overflow.wait()
   os.write_file(dir + '/overflow-probe.log', overflow_log)!
   assert overflow.code != 0 && overflow_log.contains('overflowing GPU heap interval must not allocate')
   overflow.close()
  }
  receipts << item[0] + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
  println(item[0] + ': compiled; designated heap bounds failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
