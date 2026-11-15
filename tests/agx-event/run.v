// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-event-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-event/fixture', scratch, false)!
	for name in ['klock', 'katomic'] {
		os.cp_all('${repo}/tests/agx-g13-failure/fixture/${name}', '${scratch}/${name}', false)!
	}
	os.mkdir_all('${scratch}/gpu/agx/event')!
	os.cp('${repo}/kernel/gpu/agx/event/event.v', '${scratch}/gpu/agx/event/event.v')!
	os.cp('${repo}/kernel/gpu/agx/event/workqueue.v', '${scratch}/gpu/agx/event/workqueue.v')!
	os.write_file('${scratch}/gpu/agx/event/host.v', 'module event\n__global higher_half = u64(0)\n')!
	os.cp('${repo}/tests/agx-event/test.v', '${scratch}/main.v')!
	os.cp('${repo}/tests/agx-event/admission.v', '${scratch}/admission.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	mut flags := ['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-path',
		'${scratch}|@vlib|@vmodules']
	if '--sanitize' in os.args {
		flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address,undefined']
	}
	flags << ['-o', '${scratch}/test', scratch]
	build.set_args(flags)
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_EVENT_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut test := os.new_process('${scratch}/test')
	test.run()
	test.wait()
	exit(test.code)
}
