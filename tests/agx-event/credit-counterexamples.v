// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
 assert os.args.len == 3, 'usage: credit-counterexamples EVENT_RUNNER FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[2])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 source := os.read_file(repo + '/kernel/gpu/agx/event/workqueue.v')!
 start := source.index('pub fn (mut queue WorkQueueEvents) record_completion(') or { panic('credit method') }
 end := source.index_after('pub fn (mut queue WorkQueueEvents) release(', start) or { panic('release method') }
 method := source[start..end]
 variants := [
  ['foreign-slot', 'if !queue.owns_slot(slot)', 'if false', 'foreign slot cannot return credit'],
  ['inactive', 'ticket.active && ', '', 'inactive retained value cannot return credit'],
  ['unpublished', ' && ticket.published', '', 'unpublished ticket cannot return credit'],
  ['no-progress', 'queue.completed_value = value', 'queue.completed_value = queue.completed_value',
   'completed publications return credit while their tickets stay retained'],
  ['reverse-progress', 'if i32(value - queue.completed_value) > 0', 'if true',
   'completed publications return credit while their tickets stay retained'],
  ['consume-owner', 'return true', 'queue.users = 0; return true', 'duplicate completion remains idempotent'],
  ['skip-overflow', 'block = block.next', 'block = unsafe { nil }', 'every published overflow ticket returns completion credit'],
 ]
 mut receipts := []string{}
 for item in variants {
  assert method.count(item[1]) == 1, item[0]
  dir := state + '/' + item[0]; os.mkdir_all(dir)!
  mutant := source[..start] + method.replace(item[1], item[2]) + source[end..]
  os.write_file(dir + '/workqueue.v', mutant)!
  os.setenv('AGX_EVENT_TEST_BINARY', dir + '/test', true)
  os.setenv('AGX_EVENT_TEST_C', dir + '/test.c', true)
  mut process := os.new_process(os.abs_path(os.args[1]))
  process.set_args(['--sanitize', '--workqueue-source', dir + '/workqueue.v'])
  process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
  os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('FAIL: fn main.check_retained_event_credits:')
   && log.contains(item[3]) && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), item[0] + ': ' + log
  process.close()
  receipts << item[0] + ' source sha256 ' + sha256.sum(mutant.bytes()).hex()
  println(item[0] + ': compiled; designated retained event credit assertion failed')
 }
 os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
