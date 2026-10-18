// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing production section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing production terminator: ${end}') }
	return source[begin..finish]
}

fn run_checks() int {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-g13-failure-${os.getpid()}')
	os.mkdir_all(scratch) or { panic(err) }
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(os.join_path(repo, 'tests/agx-g13-failure/fixture'), scratch, false) or { panic(err) }
	os.mkdir_all('${scratch}/gpu/agx/channel') or { panic(err) }
	os.cp('${repo}/kernel/gpu/agx/channel/channel.v', '${scratch}/gpu/agx/channel/channel.v') or { panic(err) }
	os.write_file('${scratch}/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n') or { panic(err) }
	source := os.read_file('${repo}/kernel/gpu/agx/gpu/gpu.v') or { panic(err) }
	mut production := 'module gpu\nimport gpu.agx.fw\nimport gpu.agx.event\nimport gpu.agx.alloc\nimport katomic\nimport sched\n__global higher_half = u64(0)\n'
	production += section(source, 'pub fn (mut mgr GpuManager) handle_event()', 'fn (mut mgr GpuManager) handle_role_system_message') or { panic(err) }
	production += section(source, 'fn (mut mgr GpuManager) check_g13_firmware_health()', '// Shutdown the GPU') or { panic(err) }
	production += source.all_after('// Shutdown the GPU\n')
	submissions := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v') or { panic(err) }
	production += section(submissions, 'fn (mut mgr GpuManager) submit_g13_queue_commands(', 'fn (mut mgr GpuManager) submit_g13_queue_command(') or { panic(err) }
	production += section(submissions, 'fn (mut mgr GpuManager) publish_g13_render_job_locked(', '// Transfer a prepared render pass') or { panic(err) }
	os.write_file('${scratch}/gpu/production.v', production) or { panic(err) }
	os.mkdir_all('${scratch}/gpu/agx/alloc') or { panic(err) }
	allocator := os.read_file('${repo}/kernel/gpu/agx/alloc/alloc.v') or { panic(err) }
	constants := section(allocator, 'pub const g13_private_start', '// RTKit system endpoints') or { panic(err) }
	os.write_file('${scratch}/gpu/agx/alloc/constants.v', 'module alloc\n' + constants) or { panic(err) }
	// Keep the real firmware definitions and builders; replace only privileged
	// atomics/interrupt locks and hardware-facing manager services in the fixture.
	os.mkdir_all('${scratch}/gpu/agx') or { panic(err) }
	os.symlink('${repo}/kernel/gpu/agx/fw', '${scratch}/gpu/agx/fw') or { panic(err) }
	os.symlink('${repo}/kernel/gpu/agx/hw', '${scratch}/gpu/agx/hw') or { panic(err) }
	os.cp('${repo}/tests/agx-g13-failure/test.v', '${scratch}/main.v') or { panic(err) }
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	mut flags := ['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-path',
		'${scratch}|@vlib|@vmodules']
	if '--sanitize' in os.args {
		flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address,undefined']
	}
	flags << ['-o', '${scratch}/test', '${scratch}/main.v']
	build.set_args(flags)
	build.run()
	build.wait()
	if build.code != 0 { return build.code }
	if output := os.getenv_opt('AGX_G13_TEST_BINARY') {
		os.cp('${scratch}/test', output) or { panic(err) }
	}
	mut test := os.new_process('${scratch}/test')
	test.run()
	test.wait()
	return test.code
}

fn main() {
	exit(run_checks())
}
