// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-gem-private-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/gem-private/fixture', scratch, false)!
	os.cp_all(repo + '/tests/agx-g13-failure/fixture/klock', scratch + '/klock', false)!
	os.mkdir_all(scratch + '/drm/gem')!
	os.cp(repo + '/kernel/drm/gem/gem.v', scratch + '/drm/gem/gem.v')!
	os.cp(repo + '/kernel/drm/gem/backing.v', scratch + '/drm/gem/backing.v')!
	os.write_file(scratch + '/drm/gem/host.v', 'module gem\n__global page_size = u64(16384)\n__global higher_half = u64(0)\n')!
	os.cp(repo + '/tests/gem-private/test.v', scratch + '/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch + '/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('GEM_PRIVATE_TEST_BINARY') { os.cp(scratch + '/test', output)! }
	if output := os.getenv_opt('GEM_PRIVATE_TEST_C') {
		mut generated := os.new_process(os.getenv_opt('V') or { 'v' })
		generated.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
			'-path', scratch + '|@vlib|@vmodules', '-o', output, scratch + '/main.v'])
		generated.run()
		generated.wait()
		if generated.code != 0 { exit(generated.code) }
	}
	mut check := os.new_process(scratch + '/test')
	check.run()
	check.wait()
	exit(check.code)
}
