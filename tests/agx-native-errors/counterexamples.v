// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn git_blob(repo string, path string) !string {
 mut process := os.new_process('git')
 process.set_args(['-C', repo, 'show', '71ea9ac50ef3ebdf81ac015fee709275f70b7a18:' + path])
 process.set_redirect_stdio(); process.run(); result := process.stdout_slurp() + process.stderr_slurp(); process.wait()
 assert process.code == 0; process.close(); return result
}
fn main() {
 assert os.args.len == 4, 'usage: counterexamples RUNNER ORIGINAL_BASELINE_BUNDLE FRESH_EXTERNAL_DIRECTORY'
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 state := os.abs_path(os.args[3])
 assert !os.exists(state) && !state.starts_with(repo + '/')
 os.mkdir_all(state)!
 atomic_source := os.read_file(repo + '/kernel/katomic/katomic_arm64.v')!
 source := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
 mut receipts := []string{}
 for name in ['original-int-width', 'narrow-load', 'narrow-store', 'lost-override'] {
  dir := state + '/' + name; os.mkdir_all(dir)!
  mut flags := []string{}
  expected := if name == 'narrow-load' { 'native command errno load' }
   else if name == 'lost-override' { 'native aggregate error override' } else { 'native command errno storage' }
  if name == 'original-int-width' {
   for file in ['file.v', 'pending.v'] {
    path := 'kernel/gpu/agx/file/' + file
    before := os.read_file(os.args[2] + '/source/' + path)!
    assert before == git_blob(repo, path)!, path
    os.write_file(dir + '/' + file, before)!
    flags << [if file == 'file.v' { '--file-source' } else { '--pending-source' }, dir + '/' + file]
   }
   atomic_path := 'kernel/katomic/katomic_arm64.v'
   before_atomic := os.read_file(os.args[2] + '/source/' + atomic_path)!
   assert before_atomic == git_blob(repo, atomic_path)!
   os.write_file(dir + '/atomic.v', before_atomic)!
   flags << ['--atomic-source', dir + '/atomic.v']
  } else {
   original := if name == 'lost-override' { source } else { atomic_source }
   old := match name { 'narrow-load' { 'return T(C.vinix_ldar64(voidptr(var)))' }
    'narrow-store' { 'C.vinix_stlr64(voidptr(var), u64(value))' }
    else { 'result = int(override_error)' } }
   replacement := match name { 'narrow-load' { 'return T(C.vinix_ldar32(voidptr(var)))' }
    'narrow-store' { 'C.vinix_stlr32(voidptr(var), u32(value))' }
    else { 'result = 0' } }
   assert original.count(old) == 1, name
   path := dir + '/source.v'; os.write_file(path, original.replace(old, replacement))!
   flags << [if name == 'lost-override' { '--file-source' } else { '--atomic-source' }, path]
  }
  os.setenv('AGX_NATIVE_ERROR_BINARY', dir + '/test', true)
  os.setenv('AGX_NATIVE_ERROR_C', dir + '/test.c', true)
  os.setenv('AGX_NATIVE_ERROR_FIXTURE', dir + '/fixture', true)
  mut process := os.new_process(os.abs_path(os.args[1])); process.set_args(flags); process.set_redirect_stdio(); process.run()
  log := process.stdout_slurp() + process.stderr_slurp(); process.wait(); os.write_file(dir + '/run.log', log)!
  assert process.code != 0 && log.contains('FAIL: fn file.run_checks:') && log.contains(expected)
   && !log.contains('error:') && os.is_file(dir + '/test') && os.is_file(dir + '/test.c'), name + ': ' + log
  process.close()
  receipts << name + ' test sha256 ' + sha256.sum(os.read_bytes(dir + '/test')!).hex()
  println(name + ': compiled; designated native error assertion failed')
 }
 os.write_file(state + '/receipts.txt', receipts.join('\n') + '\n')!
}
