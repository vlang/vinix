// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing ${end}') }
	return source[begin..finish]
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-counter-${os.getpid()}')
	os.mkdir_all(scratch + '/gpu/agx')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	for name in ['fw', 'hw'] {
		os.symlink('${repo}/kernel/gpu/agx/${name}', '${scratch}/gpu/agx/${name}')!
	}
	for name in ['klock', 'katomic'] {
		os.cp_all('${repo}/tests/agx-g13-failure/fixture/${name}', '${scratch}/${name}', false)!
	}
	source := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v')!
	production := 'module gpu\nimport gpu.agx.fw\n' +
		section(source, 'fn write_g13_timestamp(', 'struct G13EventResources {')! +
		section(source, 'struct G13CommandCounter {', '// The firmware samples')!
	os.write_file('${scratch}/gpu/production.v', production)!
	os.cp('${repo}/tests/agx-command-counter/check.v', '${scratch}/gpu/check.v')!
	os.write_file('${scratch}/main.v', 'import gpu\nfn main() { gpu.check_counters() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_COUNTER_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
