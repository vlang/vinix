import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: garbage-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 order_failure := 'GC must retire deferred ranges in release FIFO order'
 stats_failure := 'garbage statistics must match count and rounded deferred bytes'
 ranks_failure := 'release ranks must match the bounded pending FIFO'
 variants := [
  ['original-source', os.read_file(os.args[2])!, order_failure, '--sanitize-garbage-probe'],
  ['lifo', source.replace('a.release_order == 1', 'a.release_order == h.garbage_count'), order_failure, '--sanitize-garbage-probe'],
  ['va-order', source.replace('if !a.in_use && a.release_order == 1 { break }', 'if !a.in_use { break }'), order_failure, '--sanitize-garbage-probe'],
  ['ignore-limit', source.replace('if count < h.garbage_count { count } else { h.garbage_count }', 'h.garbage_count'), stats_failure, '--sanitize-garbage-limits'],
  ['duplicate-release', source.replace('if a.va == va && a.in_use {', 'if a.va == va {'), stats_failure, '--sanitize-garbage-limits'],
  ['raw-bytes', source.replace('h.garbage_bytes += a.size', 'h.garbage_bytes += 1'), stats_failure, '--sanitize-garbage-limits'],
  ['stale-bytes', source.replace('h.garbage_bytes -= a.size', '// omitted byte decrement'), stats_failure, '--sanitize-garbage-limits'],
  ['stale-count', source.replace('h.garbage_count--', '// omitted pending count decrement'), stats_failure, '--sanitize-garbage-limits'],
  ['uncompacted-ranks', source.replace('if pending.release_order > 1 { pending.release_order-- }', 'if false { pending.release_order-- }'), stats_failure, '--sanitize-garbage-limits'],
  ['missing-rank', source.replace('a.release_order = h.garbage_count', 'a.release_order = 0'), ranks_failure, '--sanitize-garbage-limits'],
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
  println(item[0] + ': compiled; designated garbage FIFO failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
