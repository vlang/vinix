// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: reuse-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 variants := [
  ['original-source', os.read_file(os.args[2])!, 'GPU heap must reuse a collected interior range'],
  ['no-head-hole', source.replace('cursor := h.start', 'cursor := h.top'), 'GPU heap must reuse a collected interior range'],
  ['first-fit', source.replace('if !found || span < best_span', 'if !found'), 'best fit must rank complete holes before alignment padding'],
  ['aligned-rank', source.replace('span := gap_end - cursor', 'span := gap_end - address'), 'best fit must rank complete holes before alignment padding'],
  ['lower-top', source.replace('if va + aligned_size > h.top { h.top = va + aligned_size }', 'h.top = va + aligned_size'), 'interior reuse must preserve the highest reservation'],
  ['unsorted', source.replace('for index > 0 && h.allocations[index - 1].va > va', 'for index < 0 && h.allocations[index - 1].va > va'), 'reused records must remain in VA order'],
  ['pending-owner', source.replace('cursor = record.va + record.size', 'if record.in_use { cursor = record.va + record.size }'), 'GPU range placement must match candidate-enumeration model'],
  ['premature-gc', source.replace('va := h.find_address_locked(', 'h.gc_locked()\n\tva := h.find_address_locked('), 'GPU range placement must match candidate-enumeration model'],
 ]
 mut receipts := []string{}
 for item in variants {
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  assert item[1] != source
  os.write_file(dir + '/alloc.v', item[1])!
  os.setenv('AGX_HEAP_TEST_C', dir + '/test.c', true)
  os.setenv('AGX_HEAP_TEST_BINARY', dir + '/test', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize-reuse', '--allocator-source', dir + '/alloc.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains(item[2]) && !log.contains('error:')
   && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
  println(item[0] + ': compiled; designated heap reuse failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
