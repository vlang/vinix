// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn execute(repo string, args []string, state string, expected int) !string {
 os.mkdir_all(state)!
 os.setenv('AGX_ASYNC_TEST_C', state + '/host.c', true)
 os.setenv('AGX_ASYNC_TEST_BINARY', state + '/host', true)
 os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
 mut flags := ['run', repo + '/tests/agx-async/run.v']; flags << args
 mut p := os.new_process(os.getenv_opt('V') or { 'v' }); p.set_args(flags); p.set_redirect_stdio_merged(); p.run()
 out := p.stdout_slurp(); p.wait(); os.write_file(state + '/host.log', out)!
 assert p.code == expected, out
 assert os.exists(state + '/host') && os.exists(state + '/host.c'), 'negative must compile'
 p.close(); return out
}
fn main() {
 assert os.args.len == 3 && os.args[1] in ['host', 'measure', 'trace', 'negative']
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[2])
 assert !state.starts_with(repo + '/') && !os.exists(state)
 if os.args[1] != 'negative' {
  mode := os.args[1]
  args := if mode == 'measure' { ['--measure-dependencies'] } else if mode == 'trace' { ['--trace-dependencies'] } else { []string{} }
  out := execute(repo, args, state, 0)!
  if mode == 'host' { assert out.contains('Job dependencies: 4096') && out.contains('AGX async:') }
  if mode == 'measure' { assert out.count('retained_blocks=0 retained_bytes=0') == 9 }
  println(mode + ' scheduler dependency checks pass.')
  return
 }
 os.mkdir_all(state)!
 for index, spec in [
  ['kernel/gpu/agx/file/file.v', 'agxsubmission.copy_job_dependencies(input_syncs)', 'agxsubmission.copy_sync_array(input_syncs)', 'pending work must own reduced dependencies'],
  ['kernel/gpu/agx/submission/dependencies.v', 'incoming.fence.seqno > previous.seqno', 'incoming.fence.seqno < previous.seqno', 'context keeps greatest unsigned sequence'],
  ['kernel/gpu/agx/submission/dependencies.v', 'incoming.fence.seqno > previous.seqno', 'incoming.fence.seqno >= previous.seqno', 'equal sequences keep the first record'],
  ['kernel/gpu/agx/submission/dependencies.v', 'code, copied := copy_sync_array(source)', 'code, copied := 0, *source', 'failed dependency copy must preserve caller ownership'],
 ] {
  source := os.read_file(repo + '/' + spec[0])!
  assert source.count(spec[1]) == 1
  path := state + '/mutant-' + index.str() + '.v'; os.write_file(path, source.replace(spec[1], spec[2]))!
  args := if index == 0 { ['--file-source', path] } else { ['--dependency-copy-only', '--dependency-source', path] }
  out := execute(repo, args, state + '/case-' + index.str(), 1)!
  assert out.contains(spec[3]), out
 }
 println('Four compiled negatives reject missing integration, wrong latest/tie selection and borrowed dynamic storage.')
}
