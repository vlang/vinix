// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run_checks() !int {
 assert os.args.len == 2 || (os.args.len == 4 && os.args[2] == '--allocator-source')
 assert os.args[1] in ['--measure', '--measure-padding', '--sanitize']
 assert os.user_os() == 'macos', 'retained host allocation measurement uses Darwin malloc statistics'
 // Default nano-zone statistics showed an additional 512-block step during
 // churn. Use the ordinary allocator for this exact live-byte measurement.
 os.setenv('MallocNanoZone', '0', true)
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 source := if os.args.len == 4 { os.abs_path(os.args[3]) } else { repo + '/kernel/gpu/agx/alloc/alloc.v' }
 scratch := os.join_path(os.temp_dir(), 'vinix-agx-heap-${os.getpid()}')
 assert !os.exists(scratch)
 os.mkdir_all(scratch)!
 defer { os.rmdir_all(scratch) or { panic(err) } }
 os.cp_all(repo + '/tests/agx-heap/fixture', scratch, false)!
 os.mkdir_all(scratch + '/gpu/agx/alloc')!
 os.mkdir_all(scratch + '/lib')!
 os.cp(source, scratch + '/gpu/agx/alloc/alloc.v')!
 os.cp(repo + '/kernel/lib/math.v', scratch + '/lib/math.v')!
 mut args := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc',
  '-path', scratch + '|@vlib|@vmodules']
 if os.args[1] == '--sanitize' {
  args << ['-d', 'agx_heap_sanitized', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
   '-ldflags', '-fsanitize=address,undefined']
 }
 compiler := os.getenv_opt('V') or { 'v' }
 mut build := os.new_process(compiler)
 mut build_args := args.clone(); build_args << ['-o', scratch + '/test', scratch + '/main']
 build.set_args(build_args); build.run(); build.wait()
 if build.code != 0 { return build.code }
 if target := os.getenv_opt('AGX_HEAP_TEST_C') {
  mut generated := os.new_process(compiler)
  mut c_args := args.clone(); c_args << ['-o', target, scratch + '/main']
  generated.set_args(c_args); generated.run(); generated.wait()
  if generated.code != 0 { return generated.code }
 }
 if target := os.getenv_opt('AGX_HEAP_TEST_BINARY') { os.cp(scratch + '/test', target)! }
 mut test := os.new_process(scratch + '/test')
 if os.args[1] in ['--measure', '--measure-padding'] { test.set_args([os.args[1]]) }
 test.run(); test.wait(); return test.code
}

fn main() {
 code := run_checks() or { panic(err) }
 assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-heap-${os.getpid()}')),
  'temporary fixture cleanup must finish before process exit'
 exit(code)
}
