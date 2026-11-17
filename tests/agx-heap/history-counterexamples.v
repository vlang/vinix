// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: history-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 trailing := '\ttrailing_order := if va + aligned_size < gap_end { h.newest_hole_order_locked() } else { u64(0) }\n'
 assert source.count(trailing) == 1
 reversed := source.replace(trailing, '').replace('\tleading_order :=', trailing + '\tleading_order :=')
 variants := [
  ['original-source', os.read_file(os.args[2])!, 'equal-size holes must prefer the newest eligible insertion', '--sanitize-history'],
  ['lowest-address', source.replace('(span == best_span && order > best_order)', 'false'), 'equal-size holes must prefer the newest eligible insertion', '--sanitize-history'],
  ['oldest-hole', source.replace('order > best_order', 'order < best_order'), 'equal-size holes must prefer the newest eligible insertion', '--sanitize-history'],
  ['reverse-split', reversed, 'split must insert the trailing remainder after the equal leading remainder', '--sanitize-history'],
  ['stale-coalesce', source.replace('previous.hole_order = h.newest_hole_order_locked()', 'previous.hole_order = 0'), 'equal-size holes must prefer the newest eligible insertion', '--sanitize-history'],
  ['unbounded-count', source.replace('\th.hole_count--', '\t// omitted decrement'), 'hole ranks must remain bounded by current holes', '--sanitize-history-invariants'],
  ['skip-rank-compaction', source.replace('if record.hole_order > order { record.hole_order-- }', 'if false { record.hole_order-- }'), 'following rank must match chronological hole history', '--sanitize-history-invariants'],
  ['stale-head', source.replace('if h.head_hole_order > order { h.head_hole_order-- }', 'if false { h.head_hole_order-- }'), 'head rank must match chronological hole history', '--sanitize-history-invariants'],
 ]
 mut receipts := []string{}
 for item in variants {
  directory := state + '/' + item[0]; os.mkdir_all(directory)!
  assert item[1] != source
  os.write_file(directory + '/alloc.v', item[1])!
  os.setenv('AGX_HEAP_TEST_C', directory + '/test.c', true)
  os.setenv('AGX_HEAP_TEST_BINARY', directory + '/test', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args([item[3], '--allocator-source', directory + '/alloc.v'])
  process.set_redirect_stdio(); process.run()
  output := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(directory + '/run.log', output)!
  assert process.code != 0 && output.contains(item[2]) && !output.contains('error:')
   && os.is_file(directory + '/test') && os.is_file(directory + '/test.c'), item[0] + ': ' + output
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
  println(item[0] + ': compiled; designated hole-history failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
