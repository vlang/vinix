// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing ${end}') }
	return source[begin..finish]
}

fn checks() !int {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	assert os.args.len == 1 || (os.args.len == 3 && os.args[1] in ['--file-source', '--timestamp-source', '--gpu-source', '--modern-source'])
		|| (os.args.len == 2 && os.args[1] in ['--record-measure', '--scs-measure', '--advice-measure', '--advice-trace'])
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	temp_dir := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	scratch := os.join_path(temp_dir, 'vinix-agx-close-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-file-close/fixture', scratch, false)!
	for name in ['katomic'] {
		os.cp_all('${repo}/tests/agx-g13-failure/fixture/${name}', '${scratch}/${name}', false)!
	}
	for path in ['drm/ioctl', 'drm/asahi', 'gpu/agx/alloc', 'gpu/agx/bo', 'gpu/agx/vm', 'gpu/agx/params'] {
		os.mkdir_all(os.dir('${scratch}/${path}'))!
		os.symlink('${repo}/kernel/${path}', '${scratch}/${path}')!
	}
	source := os.read_file(if os.args.len == 3 && os.args[1] == '--file-source' { os.args[2] } else { '${repo}/kernel/gpu/agx/file/file.v' })!
	production := 'module file\nimport drm\nimport drm.gem\nimport drm.ioctl\nimport drm.asahi\nimport aarch64.timer\nimport gpu.agx.bo as agxbo\nimport gpu.agx.params as agxparams\nimport gpu.agx.gpu\nimport gpu.agx.mmu\nimport gpu.agx.pgtable\nimport gpu.agx.vm as agxvm\nimport gpu.agx.workqueue\nimport katomic\nimport memory\nimport proc\n' +
		section(source, 'fn get_or_create_file(', 'pub fn release_handle(')! +
		section(source, 'struct GpuMapping {', 'struct G17QueueOwnership {')! +
		section(source, 'struct G13SubmissionQueue {', '@[heap]\nstruct G13SubmitCompletion {')! +
		section(source, 'pub fn release_handle(', '// Tear the file down.')!
			.replace('objects: agxbo.new_table(manager.hw_config.gpu_gen == .g13)',
				'objects: Objects{table: agxbo.new_table(manager.hw_config.gpu_gen == .g13)}') +
		section(source, 'fn (mut f GpuFile) import_object(', 'fn (mut f GpuFile) mmap_attributes(')! +
		section(source, 'fn (mut f GpuFile) mmap_attributes(', '// Caller holds file.lock')! +
		section(source, 'fn lookup_file(', 'fn ioctl_get_params_handler(')! +
		section(source, 'fn (mut f GpuFile) capture_submission_queue(', '// Copy userspace input')! +
		section(source, 'pub fn (mut f GpuFile) close()', 'fn (mut f GpuFile) import_object(')! +
		section(source, 'fn (mut f GpuFile) retire_mapping_locked(', '// Reserve a nonzero per-open queue ID.')! +
		section(source, 'fn (f &GpuFile) find_vm(', 'fn asahi_variant(')! +
		section(source, 'fn (mut f GpuFile) allocate_timestamp_id_locked(', 'fn (f &GpuFile) find_vm(')! +
		section(source, 'fn (mut f GpuFile) allocate_queue_id_locked(', 'fn (mut f GpuFile) allocate_timestamp_id_locked(')! +
		section(source, 'pub fn (mut f GpuFile) ioctl_vm_create(', 'pub fn (mut f GpuFile) ioctl_gem_bind(')! +
		section(source, 'pub fn (f &GpuFile) ioctl_get_params(', 'pub fn (mut f GpuFile) ioctl_vm_create(')! +
		section(source, 'pub fn (mut f GpuFile) ioctl_gem_bind(', 'pub fn (f &GpuFile) ioctl_get_time(')! +
		section(source, 'pub fn (mut f GpuFile) ioctl_gem_bind_object(', 'fn discard_g13_completion(')! +
		section(source, 'pub fn (f &GpuFile) ioctl_get_time(', 'pub fn (mut f GpuFile) ioctl_gem_bind_object(')! +
		section(source, 'fn dispatch(', 'fn lookup_file(')! +
		source[source.index('fn ioctl_get_params_handler(') or { panic('handlers') }..]
	os.write_file('${scratch}/gpu/agx/file/production.v', production)!
	os.cp(if os.args.len == 3 && os.args[1] == '--modern-source' { os.args[2] } else { repo + '/kernel/gpu/agx/file/modern.v' }, scratch + '/gpu/agx/file/modern.v')!
	os.cp(os.getenv_opt('AGX_MADVISE_SOURCE') or { repo + '/kernel/drm/gem/advice.v' }, scratch + '/drm/gem/advice.v')!
	os.cp(repo + '/tests/agx-gem-advice/checks.v', scratch + '/gpu/agx/file/advice_checks.v')!
	for name in ['backend.v', 'checks.v'] { os.cp(repo + '/tests/agx-modern-ioctl/' + name, scratch + '/gpu/agx/file/modern_' + name)! }
	os.cp(repo + '/tests/agx-queue-scs/checks.v', scratch + '/gpu/agx/file/scs_checks.v')!
	os.mkdir_all(scratch + '/aarch64/timer')!
	os.cp(repo + '/tests/agx-modern-ioctl/timer.v', scratch + '/aarch64/timer/timer.v')!
	os.cp('${repo}/kernel/gpu/agx/file/closing.v', '${scratch}/gpu/agx/file/closing.v')!
	logical := os.read_file(repo + '/kernel/gpu/agx/workqueue/workqueue.v')!
	assert logical.contains('\npub fn free_workqueue(')
	os.write_file(scratch + '/gpu/agx/workqueue/dispose.v', 'module workqueue\npub fn free_workqueue_real(' + logical.all_after('\npub fn free_workqueue('))!
	os.cp(if os.args.len == 3 && os.args[1] == '--timestamp-source' { os.args[2] } else { '${repo}/kernel/gpu/agx/file/timestamps.v' }, '${scratch}/gpu/agx/file/timestamp_capture_production.v')!
	gpu_source := os.read_file(if os.args.len == 3 && os.args[1] == '--gpu-source' { os.args[2] } else { '${repo}/kernel/gpu/agx/gpu/gpu.v' })!
	g13_source := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v')!
	os.write_file('${scratch}/gpu/agx/gpu/registration.v', 'module gpu\nimport katomic\nimport gpu.agx.alloc\nimport gpu.agx.mmu\nimport gpu.agx.pgtable\n' +
		section(g13_source, 'pub fn free_g13_queue_record(', 'pub fn (mut mgr GpuManager) create_g13_queue_resources(')!.replace('free_g13_queue_record(', 'free_g13_queue_record_real(') +
		section(g13_source, 'pub fn (mut queue G13QueueResources) retain_file_reference()', '// Caller holds mgr.lock. Asahi QueueInner')! +
		section(gpu_source, 'pub fn (mut mgr GpuManager) can_query_global_params(', 'pub fn new_gpu_manager(')! +
		section(gpu_source, 'pub fn (mut mgr GpuManager) queue_file_retirement(', 'fn (mut mgr GpuManager) reap_file_resources(')! +
		section(gpu_source, 'fn (mgr &GpuManager) g13_submission_status_locked()', '// Take a temporary submission lease')!
			.replace('g13_submission_status_locked(', 'g13_submission_status_real_locked(') +
		section(gpu_source, 'pub fn (mut mgr GpuManager) finish_g13_file_mapping(', '// Publish a G13 UAT invalidation through')! +
		section(gpu_source, 'pub fn (mut mgr GpuManager) map_g13_timestamp_buffer(', 'fn alloc_fixed_buffer(')!
			.replace('unmap_g13_timestamp_buffer', 'checked_timestamp_unmap')
			.replace('mgr.g13_timestamp.allocations', 'mgr.g13_timestamp.heap.allocations')
			.replace('map_g13_timestamp_buffer', 'checked_timestamp_map'))!
	mmu_source := os.read_file('${repo}/kernel/gpu/agx/mmu/mmu.v')!
	os.write_file('${scratch}/gpu/agx/mmu/identity.v', 'module mmu\nimport klock\nimport gpu.agx.vm as agxvm\n' +
		section(mmu_source, '__global context_identity_lock', '// Driver-owned backing')!)!
	drm_source := os.read_file('${repo}/kernel/drm/drm.v')!
	gem_source := os.read_file('${repo}/kernel/drm/gem/gem.v')!
	os.write_file('${scratch}/drm/gem/prime_fences.v', 'module gem\nimport memory\n' +
		section(gem_source, 'pub struct PrimeFence {', '@[heap]\npub struct GemObject')!)!
	os.cp_all(repo + '/tests/drm-wire/fixture/errno', scratch + '/errno', false)!
	os.cp(repo + '/tests/agx-modern-ioctl/drm.v', scratch + '/drm/modern_fixture.v')!
	os.write_file(scratch + '/drm/wire.v', 'module drm\nimport drm.gem\nimport drm.ioctl\nimport usercopy\nimport memory\nimport memory.mmap\nimport errno\n' +
		section(drm_source, 'pub fn static_ioctl_table(', '// Store a driver definition')! +
		section(drm_source, 'fn decode_ioctl_cmd(', '// The node is /dev/dri/')! +
		section(drm_source, 'fn ioctl_gem_close(', 'fn ioctl_syncobj_create(')! +
		section(drm_source, 'fn (mut this DrmNode) mapping_attributes(', 'fn (mut this DrmNode) read(')! +
		section(drm_source, 'fn (mut this DrmNode) ioctl(', 'fn (mut this DrmNode) unref(')!)!
	priority := os.read_file('${repo}/kernel/gpu/agx/fw/workqueue.v')!
	os.mkdir_all('${scratch}/gpu/agx/fw')!
	os.write_file('${scratch}/gpu/agx/fw/priority.v', 'module fw\n@[packed]\n' +
		section(priority, 'pub struct G13WorkQueuePriority {', '// QueueInfo for G13')! +
		section(priority, 'pub fn g13_workqueue_priority(', 'pub fn initialize_g13_gpu_context(')!)!
	for name in ['queue_records.v', 'stats_darwin.c.v'] { os.cp(repo + '/tests/agx-queue-records/' + name, scratch + '/gpu/agx/file/' + name)! }
	os.cp(repo + '/tests/agx-workqueue-records/file_records.v', scratch + '/gpu/agx/file/logical_records.v')!
	if os.args.len == 2 { os.write_file(scratch + '/main.v', 'import gpu.agx.file\nfn main() { file.' +
		if os.args[1] == '--scs-measure' { 'measure_scs_rejection()' } else if os.args[1] == '--advice-measure' { 'measure_advice()' } else if os.args[1] == '--advice-trace' { 'trace_advice()' } else { 'measure_queue_records()' } + ' }\n')! }
	else { os.cp('${repo}/tests/agx-file-close/test.v', '${scratch}/main.v')! }
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-d', 'queue_records_sanitized', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v']
	if os.args.len == 2 { flags = ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals', '-path', scratch + '|@vlib|@vmodules', '-o', scratch + '/test', scratch + '/main.v'] }
	build.set_args(flags)
	build.run()
	build.wait()
	if build.code != 0 { return build.code }
	if output := os.getenv_opt('AGX_CLOSE_TEST_C') {
		assert output.ends_with('.c')
		mut cflags := build.args.clone(); cflags[cflags.len - 2] = output
		mut generated := os.new_process(os.getenv_opt('V') or { 'v' })
		generated.set_args(cflags); generated.run(); generated.wait()
		if generated.code != 0 { return generated.code }
	}
	if output := os.getenv_opt('AGX_CLOSE_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	return check.code
}

fn main() { code := checks() or { panic(err) }; exit(code) }
