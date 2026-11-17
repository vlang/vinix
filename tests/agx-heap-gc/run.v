// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	assert os.args.len == 1 || os.args.len == 3 && os.args[1] in ['--source', '--wire-source']
	source := if os.args.len == 3 && os.args[1] == '--source' { os.abs_path(os.args[2]) } else { repo + '/kernel/gpu/agx/gpu/g13_garbage.v' }
	wire := if os.args.len == 3 && os.args[1] == '--wire-source' { os.abs_path(os.args[2]) } else { repo + '/kernel/gpu/agx/fw/channels.v' }
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-heap-gc-${os.getpid()}')
	assert !os.exists(scratch)
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-heap-gc/fixture', scratch, false)!
	for name in ['alloc', 'channel', 'fw', 'hw'] {
		os.mkdir_all(scratch + '/gpu/agx/' + name)!
		if name == 'hw' {
			os.rmdir(scratch + '/gpu/agx/' + name)!
			os.symlink(repo + '/kernel/gpu/agx/' + name, scratch + '/gpu/agx/' + name)!
		} else if name == 'fw' {
			os.cp(wire, scratch + '/gpu/agx/fw/channels.v')!
		} else {
			os.cp(repo + '/kernel/gpu/agx/' + name + '/' + name + '.v', scratch + '/gpu/agx/' + name + '/' + name + '.v')!
		}
	}
	os.cp(source, scratch + '/gpu/production.v')!
	os.write_file(scratch + '/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n')!
	os.mkdir_all(scratch + '/katomic')!
	os.cp(repo + '/tests/agx-g13-failure/fixture/katomic/atomic.v', scratch + '/katomic/atomic.v')!
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined']
	mut build := os.new_process(compiler)
	mut build_args := flags.clone(); build_args << ['-o', scratch + '/test', scratch + '/main.v']
	build.set_args(build_args)
	build.run(); build.wait(); assert build.code == 0
	if target := os.getenv_opt('AGX_HEAP_GC_C') {
		mut generated := os.new_process(compiler)
		mut c_args := flags.clone(); c_args << ['-o', target, scratch + '/main.v']
		generated.set_args(c_args)
		generated.run(); generated.wait(); assert generated.code == 0
	}
	if target := os.getenv_opt('AGX_HEAP_GC_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test')
	test.run(); test.wait()
	assert test.code == 0
}
