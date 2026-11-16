// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
 begin := source.index(start) or { return error('missing ' + start) }
 finish := source.index_after(end, begin + start.len) or { return error('missing ' + end) }
 return source[begin..finish]
}
fn field(source string, structure string, name string) !string {
 body := section(source, 'struct ' + structure + ' {', '\n}')!
 for line in body.split_into_lines() {
  words := line.trim_space().fields()
  if words.len >= 2 && words[0] == name { return name + ' ' + words[1] }
 }
 return error('missing field ' + structure + '.' + name)
}
fn run(compiler string, flags []string) ! {
 mut process := os.new_process(compiler)
 process.set_args(flags); process.run(); process.wait()
 if process.code != 0 { exit(process.code) }
 process.close()
}
fn main() {
 $if !arm64 { eprintln('This probe executes the ARM atomic instructions on an ARM host.'); exit(2) }
 os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
 mut options := map[string]string{}
 for i := 1; i < os.args.len; i += 2 {
  assert i + 1 < os.args.len && os.args[i] in ['--pending-source', '--file-source', '--atomic-source']
  options[os.args[i]] = os.args[i + 1]
 }
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 scratch := os.join_path(os.temp_dir(), 'vinix-agx-native-errors-${os.getpid()}')
 os.mkdir_all(scratch + '/katomic')!; os.mkdir_all(scratch + '/file')!
 defer { os.rmdir_all(scratch) or { panic(err) } }
 atomics := os.read_file(options['--atomic-source'] or { repo + '/kernel/katomic/katomic_arm64.v' })!
 os.write_file(scratch + '/katomic/production.v', atomics)!
 // Preserve the production instruction bodies. Only Darwin symbol spelling
 // and ELF-only type directives are adapted for the host object format.
 assembly := os.read_file(repo + '/kernel/asm/aarch64/kio.S')!
 mut selected := '.text\n'
 mut declarations := '#include <stdint.h>\n'
 for width in [8, 16, 32, 64] {
  for op in ['ldar', 'stlr'] {
   name := 'vinix_' + op + width.str()
   raw := section(assembly, name + ':\n', '\n.globl')!.all_after(name + ':\n')
   end := (raw.index('\n    ret') or { panic('missing return') }) + '\n    ret'.len
   body := raw[..end]
   for line in raw[end..].split_into_lines() { assert line.trim_space() == '' || line.trim_space().starts_with('//') }
   selected += '.globl _' + name + '\n.p2align 2\n_' + name + ':\n' + body + '\n'
   scalar := 'uint' + width.str() + '_t'
   declarations += if op == 'ldar' { scalar + ' ' + name + '(void *);\n' }
    else { 'void ' + name + '(void *, ' + scalar + ');\n' }
  }
 }
 os.write_file(scratch + '/atomics.S', selected)!
 os.write_file(scratch + '/atomics.h', declarations)!
 os.write_file(scratch + '/katomic/host.v', 'module katomic\n#flag -I' + scratch + '\n#flag ' + scratch + '/atomics.S\n#include "atomics.h"\n')!
 pending := os.read_file(options['--pending-source'] or { repo + '/kernel/gpu/agx/file/pending.v' })!
 source := os.read_file(options['--file-source'] or { repo + '/kernel/gpu/agx/file/file.v' })!
 command_field := field(pending, 'G13PendingCommand', 'error')!
 aggregate_field := field(pending, 'G13PendingSubmission', 'failure')!
 production := 'module file\nimport katomic\nstruct G13PendingCommand {\nmut:\n' + command_field + '\ndone bool\n}\nstruct G13PendingSubmission {\nmut:\ncommands [64]G13PendingCommand\ncommand_count u32\n' + aggregate_field + '\n}\nstruct G13SubmitCompletion {\nmut:\nsubmission &G13PendingSubmission = unsafe { nil }\ncommand_index u32\n}\n' +
  section(pending, 'fn g13_pending_error(', 'fn ')! +
  section(source, 'fn finish_g13_submit(', 'fn g13_render_completed(')! +
  '\nfn discard_g13_completion(mut state G13SubmitCompletion) {}\n' +
  'fn command_errno(value int) ' + command_field.fields()[1] + ' { return ' + command_field.fields()[1] + '(value) }\n' +
  'fn aggregate_errno(value int) ' + aggregate_field.fields()[1] + ' { return ' + aggregate_field.fields()[1] + '(value) }\n'
 os.write_file(scratch + '/file/production.v', production)!
 os.cp(repo + '/tests/agx-native-errors/test.v', scratch + '/file/test.v')!
 os.write_file(scratch + '/main.v', 'import file\nfn main() { file.run_checks() }\n')!
 compiler := os.getenv_opt('V') or { 'v' }
 mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
  '-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
  '-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch + '/main.v']
 run(compiler, flags)!
 if output := os.getenv_opt('AGX_NATIVE_ERROR_C') {
  assert output.ends_with('.c'); flags[flags.len - 2] = output; run(compiler, flags)!
 }
 if output := os.getenv_opt('AGX_NATIVE_ERROR_BINARY') { os.cp(scratch + '/test', output)! }
 if output := os.getenv_opt('AGX_NATIVE_ERROR_FIXTURE') {
  assert !os.exists(output); os.cp_all(scratch, output, false)!
 }
 run(scratch + '/test', [])!
}
