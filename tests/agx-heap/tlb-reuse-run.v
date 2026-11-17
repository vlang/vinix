// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run_checks() !int {
 repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
 scratch := os.join_path(os.temp_dir(), 'vinix-agx-heap-tlb-${os.getpid()}')
 assert !os.exists(scratch)
 os.mkdir_all(scratch)!
 defer { os.rmdir_all(scratch) or { panic(err) } }
 os.cp_all(repo + '/tests/agx-tlb/fixture', scratch, false)!
 for name in ['alloc', 'pgtable'] {
  os.mkdir_all(scratch + '/gpu/agx/' + name)!
  os.cp(repo + '/kernel/gpu/agx/' + name + '/' + name + '.v', scratch + '/gpu/agx/' + name + '/' + name + '.v')!
 }
 os.cp(repo + '/kernel/gpu/agx/tlb/plan.v', scratch + '/gpu/agx/tlb/plan.v')!
 os.write_file(scratch + '/gpu/agx/pgtable/host.v', 'module pgtable\n__global higher_half = u64(0)\n')!
 os.cp(repo + '/tests/agx-heap/tlb-reuse.v', scratch + '/main.v')!
 mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals', '-path', scratch + '|@vlib|@vmodules',
  '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
 mut build := os.new_process(os.getenv_opt('V') or { 'v' })
 mut build_args := flags.clone(); build_args << ['-o', scratch + '/test', scratch + '/main.v']
 build.set_args(build_args); build.run(); build.wait()
 if build.code != 0 { return build.code }
 if output := os.getenv_opt('AGX_HEAP_TLB_BINARY') { os.cp(scratch + '/test', output)! }
 if output := os.getenv_opt('AGX_HEAP_TLB_C') {
  mut generated := os.new_process(os.getenv_opt('V') or { 'v' })
  build_args = flags.clone(); build_args << ['-o', output, scratch + '/main.v']
  generated.set_args(build_args); generated.run(); generated.wait()
  if generated.code != 0 { return generated.code }
 }
 mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); return test.code
}

fn main() {
 code := run_checks() or { panic(err) }
 assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-heap-tlb-${os.getpid()}'))
 exit(code)
}
