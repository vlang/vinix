// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing production section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing production terminator: ${end}') }
	return source[begin..finish]
}

fn run_checks() int {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	assert os.args.len == 1 || os.args[1..] == ['--sanitize']
		|| (os.args.len == 4 && os.args[1] == '--sanitize' && os.args[2] == '--g13-source')
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
	production += section(source, 'pub fn (mut mgr GpuManager) set_file_reaper(', '// Serialize accepted submissions') or { panic(err) }
	production += section(source, 'pub fn (mut mgr GpuManager) handle_event()', 'fn (mut mgr GpuManager) handle_role_system_message') or { panic(err) }
	production += section(source, 'fn (mut mgr GpuManager) check_g13_firmware_health()', '// Shutdown the GPU') or { panic(err) }
	production += source.all_after('// Shutdown the GPU\n')
	production += (os.read_file('${repo}/kernel/gpu/agx/gpu/g13_recovery.v') or { panic(err) }).all_after('import aarch64.timer\n')
	production = production.replace('import sched\n', 'import sched\nimport aarch64.timer\n')
	submissions := os.read_file(if os.args.len == 4 { os.args[3] } else { '${repo}/kernel/gpu/agx/gpu/g13.v' }) or { panic(err) }
	barriers := os.read_file('${repo}/kernel/gpu/agx/gpu/g13_barriers.v') or { panic(err) }
	production += section(barriers, 'const g13_barrier_stride', 'fn g13_barrier_source(') or { panic(err) }
	production += section(submissions, 'fn (mut mgr GpuManager) g13_ring_has_space_locked(', 'fn (mut mgr GpuManager) submit_g13_queue_command(') or { panic(err) }
	production += section(submissions, 'fn (mut mgr GpuManager) publish_g13_render_job_locked(', '// Transfer a prepared render pass') or { panic(err) }
	production += section(submissions, 'fn (mut mgr GpuManager) retire_g13_subqueue_locked(', 'fn build_g13_attachments(') or { panic(err) }
	production += (section(submissions, 'fn complete_g13_render_job(', '// Construct the complete paired') or { panic(err) })
		.replace('complete_g13_render_job', 'checked_complete_g13_render_job')
	production += (section(submissions, 'fn (mut mgr GpuManager) reap_g13_render_jobs()', '// Firmware is stopped before this is called') or { panic(err) })
		.replace('reap_g13_render_jobs', 'checked_reap_g13_render_jobs')
		.replace('free_g13_render_job_locked', 'retirement_test_free')
		.replace('read_g13_render_result', 'retirement_test_result')
		.replace('complete_g13_render_job', 'checked_complete_g13_render_job')
		.replace('end_g13_operation_locked', 'retirement_test_end')
	production += section(submissions, 'fn (mut mgr GpuManager) auto_grow_g13_tvb_locked(', '// Caller holds mgr.lock. Idle queues') or { panic(err) }
	production += section(submissions, 'const g13_tvb_max_size', 'fn write_g13_timestamp(') or { panic(err) }
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
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals', '-path',
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
	if output := os.getenv_opt('AGX_G13_TEST_C') {
		assert output.ends_with('.c')
		mut cflags := flags.clone(); cflags[cflags.len - 2] = output
		mut generated := os.new_process(os.getenv_opt('V') or { 'v' })
		generated.set_args(cflags); generated.run(); generated.wait()
		if generated.code != 0 { return generated.code }
	}
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
