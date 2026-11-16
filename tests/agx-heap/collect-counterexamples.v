// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 4, 'usage: collect-counterexamples HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/alloc/alloc.v')!
 variants := [
  ['original-source', os.read_file(os.args[2])!],
  ['suffix-only', source.replace('if !a.in_use {', 'if !a.in_use && a.va + a.size == h.top {')],
  ['live-stop', source.replace('if !a.in_use {', 'if a.in_use { break }\n\t\tif !a.in_use {')],
  ['free-live', source.replace('if !a.in_use {', 'if true {')],
  ['interior-frontier', source.replace('if a.va + a.size == h.top {', 'if true {')],
  ['skip-record', source.replace('idx--', 'idx -= 2')],
 ]
 mut receipts := []string{}
 for item in variants {
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  assert item[1] != source
  os.write_file(dir + '/alloc.v', item[1])!
  os.setenv('AGX_HEAP_TEST_C', dir + '/test.c', true)
  os.setenv('AGX_HEAP_TEST_BINARY', dir + '/test', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize-collect', '--allocator-source', dir + '/alloc.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('GC must discard interior records while pins stay live')
   && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(item[1].bytes()).hex()
  println(item[0] + ': compiled; designated heap collection failure detected')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
