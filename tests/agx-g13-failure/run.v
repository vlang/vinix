// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing production section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing production terminator: ${end}') }
	return source[begin..finish]
}

fn check_crashlog_output(output string) {
	valid := [
		'crash message cafe: one',
		'crash message cafe: two',
		'crash message cafe: last',
		'crash firmware: vM1!',
		'crash time: -81985529216486896',
		'crash mailbox history type=17 index=5',
		'#000@88888888: 0123456789abcdef fedcba9876543210',
		'#001@00000003: 0000000000000001 0000000000000002',
		'exception mode=EL2h pc=0x222222222 sp=0x111111111 psr=0x209 far=0x333333333 esr=0x444444444',
		'x00-x03 = 1111000000000000 1111000000000001 1111000000000002 1111000000000003',
		'x24-x27 = 1111000000000018 1111000000000019 111100000000001a 111100000000001b',
		'x28-x30 = 111100000000001c 111100000000001d 111100000000001e',
	]
	for expected in valid {
		assert output.count(expected + '\n') == 2, expected
	}
	for kind in ['Cstr', 'Cver', 'Ctim', 'Cmbx', 'Crg8'] {
		assert output.count('crash entry ' + kind + '\n') == 2, kind
	}
	assert output.count('crashed task 47\n') == 4
	assert output.count('crash message 7: private snapshot\n') == 4
	assert output.count('cannot allocate crash log snapshot\n') == 2
	assert output.count('cannot copy crash log at ') == 4
	assert output.count('crash log has no terminator\n') == 2
	assert output.count('unknown crashlog message ') == 4
	assert output.count('crash mailbox history type=') == 2
	assert !output.contains('#002@')
}

fn run_checks() int {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	assert os.args.len == 1 || os.args[1..] == ['--sanitize']
		|| (os.args.len == 4 && os.args[1] == '--sanitize'
		&& os.args[2] in ['--g13-source', '--gpu-source', '--rtkit-source', '--mailbox-source', '--aic-source'])
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-g13-failure-${os.getpid()}')
	os.mkdir_all(scratch) or { panic(err) }
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(os.join_path(repo, 'tests/agx-g13-failure/fixture'), scratch, false) or { panic(err) }
	os.mkdir_all('${scratch}/apple/rtkit') or { panic(err) }
	rtkit_source := if os.args.len == 4 && os.args[2] == '--rtkit-source' { os.args[3] } else { '${repo}/kernel/apple/rtkit/rtkit.v' }
	os.cp(rtkit_source, '${scratch}/apple/rtkit/rtkit.v') or { panic(err) }
	mailbox_source := if os.args.len == 4 && os.args[2] == '--mailbox-source' { os.args[3] } else { '${repo}/kernel/apple/mailbox/mailbox.v' }
	mailbox_code := os.read_file(mailbox_source) or { panic(err) }
	assert mailbox_code.count('module mailbox\n') == 1
	os.mkdir_all('${scratch}/apple/ascmailbox') or { panic(err) }
	os.write_file('${scratch}/apple/ascmailbox/mailbox.v', mailbox_code.replace('module mailbox\n', 'module ascmailbox\n')) or { panic(err) }
	os.cp('${repo}/kernel/apple/mailbox/rxirq.v', '${scratch}/apple/mailbox/rxirq.v') or { panic(err) }
	os.mkdir_all('${scratch}/aarch64/aic') or { panic(err) }
	aic_source := if os.args.len == 4 && os.args[2] == '--aic-source' { os.args[3] } else { '${repo}/kernel/aarch64/aic/aic.v' }
	os.cp(aic_source, '${scratch}/aarch64/aic/aic.v') or { panic(err) }
	event_queue := os.read_file('${repo}/kernel/gpu/agx/event/workqueue.v') or { panic(err) }
	os.write_file('${scratch}/gpu/agx/event/queue.v', 'module event\n' +
		(section(event_queue, 'pub struct WorkQueueEvents {', 'pub fn (mut queue WorkQueueEvents) retain(') or { panic(err) }) +
		(section(event_queue, 'pub fn (queue &WorkQueueEvents) owns_slot(', '// Caller holds the manager lock and a physical-slot pin.') or { panic(err) }) +
		(section(event_queue, 'pub fn (mut queue WorkQueueEvents) record_completion(', 'pub fn (mut queue WorkQueueEvents) release(') or { panic(err) }) +
		(section(event_queue, 'pub fn (queue &WorkQueueEvents) can_submit(', '// Caller has checked every participating subqueue') or { panic(err) })) or { panic(err) }
	os.mkdir_all('${scratch}/gpu/agx/channel') or { panic(err) }
	os.cp('${repo}/kernel/gpu/agx/channel/channel.v', '${scratch}/gpu/agx/channel/channel.v') or { panic(err) }
	os.write_file('${scratch}/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n') or { panic(err) }
	source := os.read_file(if os.args.len == 4 && os.args[2] == '--gpu-source' { os.args[3] } else { '${repo}/kernel/gpu/agx/gpu/gpu.v' }) or { panic(err) }
	mut production := 'module gpu\nimport aarch64.cpu\nimport apple.mailbox\nimport apple.rtkit\nimport gpu.agx.fw\nimport gpu.agx.event\nimport gpu.agx.alloc\nimport gpu.agx.channel\nimport gpu.agx.pgtable\nimport katomic\nimport sched\n__global higher_half = u64(0)\n'
	production += section(source, 'const g13_channel_allocation_count', 'const buffer_allocator_default') or { panic(err) }
	production += section(source, 'struct G13ChannelAllocations {', '@[inline]\nfn pipe_index') or { panic(err) }
	production += section(source, 'const buffer_allocator_g13_rtkit', '\n') or { panic(err) }
	production += '\n'
	production += section(source, 'pub const ep_firmware', 'pub const msg_fwctl') or { panic(err) }
	production += section(source, 'pub const msg_rx_doorbell', 'const g13_channel_allocation_count') or { panic(err) }
	production += section(source, 'fn (mut mgr GpuManager) boot_firmware_role(', 'fn (mut mgr GpuManager) recv_role_message(') or { panic(err) }
	production += section(source, 'fn (mut mgr GpuManager) recv_role_message(', 'fn (mut mgr GpuManager) stop_firmware_cpus(') or { panic(err) }
	production += section(source, 'fn allocate_rtkit_shmem(', 'struct G13ChannelAllocations {') or { panic(err) }
	production += (section(source, 'fn (mut mgr GpuManager) release_rtkit_buffers(', 'fn (mut mgr GpuManager) alloc_g13_channel_pair(') or { panic(err) })
		.replace('release_rtkit_buffers()', 'checked_release_rtkit_buffers()')
	production += section(source, 'fn (mut mgr GpuManager) alloc_g13_shared_buffer(', '// Timestamp objects are GEM-owned') or { panic(err) }
	production += section(source, 'fn (mut mgr GpuManager) alloc_g13_channel_pair(', '// Map the t8103 firmware') or { panic(err) }
	production += (section(source, 'fn (mut mgr GpuManager) free_g13_channel_allocations(', 'fn (mut mgr GpuManager) fail_g13_initialization(') or { panic(err) })
		.replace('release_g13_channels()', 'checked_release_g13_channels()')
	production += section(source, 'fn (mut mgr GpuManager) fail_g13_initialization(', '// Allocate the completion-tracking resources') or { panic(err) }
	production += section(source, 'pub fn (mut mgr GpuManager) set_file_reaper(', '// Serialize accepted submissions') or { panic(err) }
	production += section(source, 'fn (mut mgr GpuManager) dequeue_g13_rx(', 'fn rtkit_transport_running(') or { panic(err) }
	production += section(source, 'fn rtkit_transport_running(', '// Drain the ASC transport') or { panic(err) }
	production += (section(source, 'fn (mut mgr GpuManager) poll_rtkit_messages(', '// The manager lock guards teardown') or { panic(err) })
		.replace('poll_rtkit_messages()', 'checked_poll_rtkit_messages()')
	production += section(source, 'fn (mut mgr GpuManager) read_g13_fw_log(', '// Shutdown the GPU') or { panic(err) }
	production += source.all_after('// Shutdown the GPU\n')
	production += (os.read_file('${repo}/kernel/gpu/agx/gpu/g13_recovery.v') or { panic(err) }).all_after('import aarch64.timer\n')
	production = production.replace('import sched\n', 'import sched\nimport aarch64.timer\n')
	production = production.replace('import aarch64.timer\n', 'import aarch64.timer\nimport aarch64.aic\n')
	submissions := os.read_file(if os.args.len == 4 && os.args[2] == '--g13-source' { os.args[3] } else { '${repo}/kernel/gpu/agx/gpu/g13.v' }) or { panic(err) }
	production += section(submissions, 'pub fn (mut mgr GpuManager) refresh_g13_submit_globals()',
		'// The firmware samples pending_submissions') or { panic(err) }
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
	production += (section(submissions, 'fn complete_g13_compute_job(', '// Construct one byte-exact') or { panic(err) })
		.replace('complete_g13_compute_job', 'checked_complete_g13_compute_job')
	production += (section(submissions, 'fn (mut mgr GpuManager) reap_g13_compute_jobs()', '// Firmware is stopped before this is called, so no completion flush') or { panic(err) })
		.replace('reap_g13_compute_jobs', 'checked_reap_g13_compute_jobs')
		.replace('free_g13_compute_job_locked', 'compute_retirement_free')
		.replace('complete_g13_compute_job', 'checked_complete_g13_compute_job')
		.replace('end_g13_operation_locked', 'compute_retirement_end')
	timestamp_end := if submissions.contains('pub fn free_g13_queue_record(') { 'pub fn free_g13_queue_record(' }
		else { 'pub fn (mut mgr GpuManager) create_g13_queue_resources(' }
	production += section(submissions, 'pub fn (job &G13ComputeJobResources) timestamp_values()', timestamp_end) or { panic(err) }
	production += section(submissions, 'pub fn (queue &G13QueueResources) has_file_references()', '// Caller holds mgr.lock. Asahi QueueInner') or { panic(err) }
	production += (section(submissions, 'pub fn (mut mgr GpuManager) release_g13_queue_resources(', '// Quarantined backing must retire') or { panic(err) })
		.replace('release_g13_queue_resources', 'checked_release_g13_queue_resources')
		.replace('free_g13_queue_resources_locked', 'completion_test_free_queue')
	production += section(submissions, 'fn (mut mgr GpuManager) auto_grow_g13_tvb_locked(', '// Caller holds mgr.lock. Idle queues') or { panic(err) }
	production += section(submissions, 'const g13_tvb_max_size', 'fn write_g13_timestamp(') or { panic(err) }
	os.write_file('${scratch}/gpu/production.v', production) or { panic(err) }
	os.mkdir_all('${scratch}/gpu/agx/alloc') or { panic(err) }
	allocator := os.read_file('${repo}/kernel/gpu/agx/alloc/alloc.v') or { panic(err) }
	constants := section(allocator, 'pub const g13_private_start', '// --- Individual allocation record ---') or { panic(err) }
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
	result := os.exec(['${scratch}/test'])
	print(result.output)
	if result.exit_code == 0 {
		check_crashlog_output(result.output)
		assert result.output.count('rtkit[g13-send]: management reply type 0x2 timed out\n') == 2
		assert result.output.count('rtkit[g13-send]: management reply type 0x8 timed out\n') == 4
		assert result.output.count('syslog message: abcdefghijklmnopqrstuvw:   trim\n') == 2
		assert result.output.count('syslog message: wide: ' + 'M'.repeat(254) + '\n') == 2
		assert result.output.count('syslog message: one: \n') == 2
		assert result.output.count('syslog message: ') == 6
	}
	return result.exit_code
}

fn main() {
	exit(run_checks())
}
