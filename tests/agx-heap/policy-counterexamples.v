// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: policy-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 immediate := 'nondeferred release must retire metadata before returning'
 deferred := 'the ordinary heap constructor must retain deferred owners'
 variants := [
  ['original-source', os.read_file(os.args[2])!, immediate, '--sanitize-policy-baseline'],
  ['ignored-policy', source.replace('heap.keep_garbage = keep_garbage', 'heap.keep_garbage = true'), immediate, '--sanitize-policy'],
  ['lost-policy', source.replace('return heap\n}\n\n// Checked rounding', 'return new_heap(name, start, end)\n}\n\n// Checked rounding'), immediate, '--sanitize-policy'],
  ['reversed-policy', source.replace('if !h.keep_garbage', 'if h.keep_garbage'), immediate, '--sanitize-policy'],
  ['zero-collection', source.replace('if !h.keep_garbage { h.collect_garbage_locked(1) }', 'if !h.keep_garbage { h.collect_garbage_locked(0) }'), immediate, '--sanitize-policy'],
  ['always-immediate', source.replace('if !h.keep_garbage', 'if true'), deferred, '--sanitize-policy'],
  ['wrong-default', source.replace('keep_garbage bool = true', 'keep_garbage bool = false'), deferred, '--sanitize-policy'],
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
  println(item[0] + ': compiled; designated release policy failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
