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
	scratch := os.join_path(os.temp_dir(), 'vinix-drm-syncobj-wait-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/drm-syncobj-wait/fixture', scratch, false)!
	os.cp_all('${repo}/kernel/drm/syncobj', '${scratch}/drm/syncobj', false)!
	if capture_source := os.getenv_opt('DRM_TIMELINE_CAPTURE_SOURCE') {
		os.cp(capture_source, scratch + '/drm/syncobj/timeline_capture.v')!
	}
	if merge_source := os.getenv_opt('DRM_MERGE_SOURCE') { os.cp(merge_source, scratch + '/drm/syncobj/merge.v')! }
	if array_source := os.getenv_opt('DRM_ARRAY_SOURCE') { os.cp(array_source, scratch + '/drm/syncobj/array.v')! }
	// Inject allocator identity at the two exact production allocation sites.
	// Object/fence sizes may coincide; size alone cannot identify ownership.
	for name, pair in {
		'syncobj.v': ['memory.malloc_packed_fallible(sizeof(SyncObj))', 'memory.malloc_syncobj_fallible(sizeof(SyncObj))']
		'stub.v': ['memory.malloc_packed_fallible(sizeof(DmaFence))', 'memory.malloc_fence_fallible(sizeof(DmaFence))']
	} {
		path := '${scratch}/drm/syncobj/${name}'
		body := os.read_file(path)!
		assert body.count(pair[0]) == 1
		os.write_file(path, body.replace(pair[0], pair[1]))!
	}
	object_path := '${scratch}/drm/syncobj/syncobj.v'
	object_source := os.read_file(object_path)!
	alias_site := 'memory.malloc_packed_fallible(sizeof(SyncobjHandle))'
	assert object_source.count(alias_site) == 1
	os.write_file(object_path, object_source.replace(alias_site, 'memory.malloc_alias_fallible(sizeof(SyncobjHandle))'))!
	os.cp_all('${repo}/kernel/drm/ioctl', '${scratch}/drm/ioctl', false)!
	os.cp_all('${repo}/tests/agx-file-close/fixture/drm/gem', '${scratch}/drm/gem', false)!
	gem_source := os.read_file('${repo}/kernel/drm/gem/gem.v')!
	os.write_file('${scratch}/drm/gem/prime_fences.v', 'module gem\nimport memory\n' +
		section(gem_source, 'pub struct PrimeFence {', '@[heap]\npub struct GemObject')!)!
	os.cp_all('${repo}/tests/agx-file-close/fixture/memory/mmap', '${scratch}/memory/mmap', false)!
	os.cp_all('${repo}/tests/agx-file-close/fixture/klock', '${scratch}/klock', false)!
	os.cp_all('${repo}/tests/agx-async/fixture/katomic', '${scratch}/katomic', false)!
	os.cp_all('${repo}/tests/agx-async/fixture/event', '${scratch}/event', false)!
	os.mv('${scratch}/event_block.v', '${scratch}/event/nonblock.v')!
	os.cp('${repo}/kernel/file/reservation.v', '${scratch}/file/reservation.v')!
	os.cp('${repo}/kernel/file/eventfd.v', '${scratch}/file/eventfd.v')!
	native_file := os.read_file('${repo}/kernel/file/file.v')!
	os.write_file('${scratch}/file/table.v', 'module file\nimport proc\nimport errno\n' +
		section(native_file, 'pub fn fdnum_create_from_fd(', '// Make room in a descriptor table')!)!
	os.write_file('${scratch}/file/poll.v', 'module file\nimport proc\nimport errno\nimport resource\nimport event\nimport event.eventstruct\nimport time\nfn C.__builtin_alloca(usize) voidptr\n' +
		section(native_file, 'struct PollFD {', '// ppoll may sleep')!.replace('C.vinix_stack_alloc', 'C.__builtin_alloca'))!
	native_epoll := os.read_file('${repo}/kernel/file/epoll.v')!
	os.write_file('${scratch}/file/epoll_ready.v', 'module file\nimport resource\n' +
		section(native_epoll, 'struct EpollEntry {', '// Every epoll set')! +
		section(native_epoll, 'fn epoll_ready_events(', 'pub fn syscall_epoll_pwait(')!)!
	stack_list := os.read_file('${repo}/kernel/event/stack_list.v')!
	os.write_file('${scratch}/event/stack_list.v', 'module event\nimport event.eventstruct\n' +
		section(stack_list, '@[unsafe]', '// await_one is')!)!
	resource_source := os.read_file('${repo}/kernel/resource/resource.v')!
	os.write_file('${scratch}/resource/seek.v', 'module resource\n' +
		section(resource_source, 'pub interface SeekableResource {', '// An immutable backend')!)!
	os.write_file('${scratch}/resource/poll.v', 'module resource\nimport stat\n' +
		section(resource_source, 'pub interface PollableResource {', 'struct ReadOnlyScratch {')!)!
	os.write_file('${scratch}/resource/stat.v', os.read_file('${repo}/kernel/resource/stat.v')!
		.replace('C.vinix_stack_alloc', 'C.__builtin_alloca'))!
	vfs := os.read_file('${repo}/kernel/fs/vfs.v')!
	os.mkdir_all('${scratch}/fs')!
	os.write_file('${scratch}/fs/seek.v', 'module fs\nimport errno\nimport file\nimport proc\nimport resource\nimport stat\n' +
		section(vfs, 'pub const seek_cur =', 'pub const resolve_no_xdev')! +
		section(vfs, 'pub fn syscall_seek(', '// symlinkat(')!)!
	stat_source := os.read_file('${repo}/kernel/fs/stat.v')!
	os.write_file('${scratch}/fs/stat.v', 'module fs\nimport errno\nimport file\nimport proc\nimport resource\nimport stat\n' +
		section(stat_source, 'fn stat_resource(', 'fn stat_path_resource(')! +
		section(vfs, 'pub fn syscall_fstat(', 'pub fn syscall_linkat(')!)!
	source := os.read_file('${repo}/kernel/drm/drm.v')!
	production := 'module drm\nimport drm.ioctl\nimport drm.syncobj\nimport usercopy\nimport sched\nimport proc\nimport katomic\nimport file\nimport resource\nimport errno\nimport fs\nimport stat\nimport klock\nimport memory\nimport memory.mmap\nimport drm.gem\nimport event.eventstruct\n' +
		section(source, 'struct SyncFileResource {', 'fn (mut this SyncFileResource) poll_status(')! +
		section(source, 'fn (mut this SyncFileResource) poll_status(', '__global (')! +
		section(source, '__global (\n\tregistered_devices', 'fn decode_ioctl_cmd(')! +
		section(source, 'fn ioctl_syncobj_create(', 'fn ioctl_syncobj_wait(')! +
		section(source, 'fn ioctl_syncobj_wait(', 'fn core_ioctl(')!
	os.write_file('${scratch}/drm/production.v', production)!
	os.cp('${repo}/kernel/drm/prime_sync.v', '${scratch}/drm/prime_sync.v')!
	os.cp('${repo}/kernel/drm/syncobj_fd.v', '${scratch}/drm/syncobj_fd.v')!
	os.cp('${repo}/kernel/drm/syncobj_eventfd.v', '${scratch}/drm/syncobj_eventfd.v')!
	os.cp('${repo}/kernel/drm/sync_file_info.v', '${scratch}/drm/sync_file_info.v')!
	os.cp('${repo}/kernel/drm/sync_file_deadline.v', '${scratch}/drm/sync_file_deadline.v')!
	query_source := os.getenv_opt('DRM_QUERY_SOURCE') or { repo + '/kernel/drm/syncobj_query.v' }
	os.cp(query_source, scratch + '/drm/syncobj_query.v')!
	timeline_signal_source := os.getenv_opt('DRM_TIMELINE_SIGNAL_SOURCE') or { repo + '/kernel/drm/syncobj_timeline_signal.v' }
	os.cp(timeline_signal_source, scratch + '/drm/syncobj_timeline_signal.v')!
	timeline_wait_source := os.getenv_opt('DRM_TIMELINE_WAIT_SOURCE') or { repo + '/kernel/drm/syncobj_timeline_wait.v' }
	os.cp(timeline_wait_source, scratch + '/drm/syncobj_timeline_wait.v')!
	for name in ['syncobj_find', 'syncobj_transfer'] {
		source_path := os.getenv_opt('DRM_' + name.to_upper() + '_SOURCE') or { repo + '/kernel/drm/' + name + '.v' }
		os.cp(source_path, scratch + '/drm/' + name + '.v')!
	}
	// Execute the native sync-array staging/publication functions without
	// pulling unrelated render/compute decoding into this focused fixture.
	submission := os.read_file('${repo}/kernel/gpu/agx/submission/submission.v')!
	os.mkdir_all('${scratch}/gpu/agx/submission')!
	os.write_file('${scratch}/gpu/agx/submission/production.v', 'module submission\nimport drm.ioctl\nimport drm.syncobj\nimport usercopy\n' +
		section(submission, 'pub const max_syncs =', 'pub struct SyncArray {')! +
		section(submission, 'pub struct SyncArray {', 'pub struct Command {')! +
		section(submission, 'pub fn stage_sync_array(', '// Snapshot one descriptor')!)!
	os.cp('${repo}/kernel/gpu/agx/submission/sync_storage.v', '${scratch}/gpu/agx/submission/sync_storage.v')!
	os.cp('${repo}/kernel/gpu/agx/submission/modern.v', '${scratch}/gpu/agx/submission/modern.v')!
	os.cp_all('${repo}/kernel/drm/asahi', '${scratch}/drm/asahi', false)!
	os.write_file('${scratch}/drm/registration.v', 'module drm\nimport drm.ioctl\n' +
		section(source, 'struct DrmIoctlLayout {', 'fn common_ioctl_layout(')! +
		section(source, 'fn common_ioctl_layout(', 'fn ioctl_layout(')!)!
	os.cp('${repo}/kernel/drm/wait_storage.v', '${scratch}/drm/wait_storage.v')!
	os.cp('${repo}/tests/drm-syncobj-wait/capture_checks.v', '${scratch}/drm/syncobj/capture_checks.v')!
	os.cp(repo + '/tests/drm-timeline-chain/info_checks.v', scratch + '/drm/chain_info_checks.v')!
	os.cp(repo + '/tests/drm-syncobj-query/checks.v', scratch + '/drm/query_checks.v')!
	os.cp(repo + '/tests/drm-syncobj-query/trace.v', scratch + '/drm/syncobj/query_trace.v')!
	os.cp(repo + '/tests/drm-timeline-signal/checks.v', scratch + '/drm/timeline_signal_checks.v')!
	os.cp(repo + '/tests/drm-timeline-signal/lifetime.v', scratch + '/drm/syncobj/timeline_signal_lifetime.v')!
	os.cp(repo + '/tests/drm-timeline-wait/checks.v', scratch + '/drm/timeline_wait_checks.v')!
	os.cp(repo + '/tests/drm-timeline-wait/lifetime.v', scratch + '/drm/syncobj/timeline_wait_lifetime.v')!
	os.cp(repo + '/tests/drm-binary-transfer/checks.v', scratch + '/drm/binary_transfer_checks.v')!
	os.cp(repo + '/tests/drm-timeline-transfer/checks.v', scratch + '/drm/timeline_transfer_checks.v')!
	os.cp(repo + '/tests/drm-timeline-transfer/lifetime.v', scratch + '/drm/syncobj/timeline_transfer_lifetime.v')!
	if fake_source := os.getenv_opt('DRM_FAKE_FENCE_SOURCE') {
		os.mkdir_all(scratch + '/fake')!
		os.cp(fake_source, scratch + '/fake/fence.v')!
		os.cp(repo + '/tests/agx-fake-fences/checks.v', scratch + '/fake/checks.v')!
		os.cp(repo + '/tests/agx-fake-fences/context.v', scratch + '/drm/syncobj/fake_context_checks.v')!
		os.cp_all(repo + '/kernel/gpu/agx/workqueue', scratch + '/gpu/agx/workqueue', false)!
		os.cp(repo + '/tests/agx-fake-fences/transaction.v', scratch + '/fake/transaction.v')!
		fake_driver := os.read_file(os.getenv_opt('DRM_FAKE_DRIVER_SOURCE') or { repo + '/kernel/gpu/agx/fake/driver.v' })!
		fake_transaction := section(fake_driver, '\tmut vm_pinned := false\n', '\tstarted := timer.get_count()')!
		assert fake_transaction.count('install_output_syncs(&output_syncs,') == 1
		os.write_file(scratch + '/fake/transaction_production.v', 'module fake\nimport drm.syncobj\nimport gpu.agx.submission as agxsubmission\n' +
			'fn (mut file FakeG17File) reserve_output(mut vm FakeG17Vm, render_index int, output_syncs &agxsubmission.SyncArray) int {\n' +
			fake_transaction.replace('install_output_syncs(&output_syncs,', 'install_output_syncs(output_syncs,') +
			'\tfile.lock.release()\n\treturn 0\n}\n')!
	}
	$if macos {
		stats := os.read_file(repo + '/tests/agx-queue-records/stats_darwin.c.v')!
		os.write_file(scratch + '/drm/stats_darwin.c.v', stats.replace('module file', 'module drm'))!
	}
	process_source := os.read_file('${repo}/kernel/proc/proc.v')!
	os.write_file('${scratch}/proc/production.v', 'module proc\nimport katomic\n' +
		section(process_source, 'pub fn pending_signals(', '// Read-mostly limits')!)!
	os.write_file('${scratch}/main.v', 'import drm\nimport drm.syncobj\nimport os\nfn main() { if os.getenv("DRM_TIMELINE_TRANSFER_MEASURE") == "1" { drm.measure_timeline_transfer(); return }; if os.args.len > 1 && os.args[1] == "--timeline-transfer-trace" { drm.run_timeline_transfer_trace(); return }; if os.getenv("DRM_BINARY_TRANSFER_MEASURE") == "1" { drm.measure_binary_transfer_owners(); return }; if os.args.len > 1 && os.args[1] == "--binary-transfer-trace" { drm.run_binary_transfer_trace(); return }; if os.getenv("DRM_TIMELINE_WAIT_MEASURE") == "1" { drm.measure_timeline_wait_owners(); return }; if os.getenv("DRM_TIMELINE_SIGNAL_MEASURE") == "1" { drm.measure_timeline_signal_failures(); return }; if os.args.len > 1 && os.args[1] == "--timeline-wait-trace" { drm.run_timeline_wait_trace(); return }; if os.args.len > 1 && os.args[1] == "--query-trace" { syncobj.run_query_trace(); return }; if os.args.len > 1 && os.args[1] == "--timeline-signal-trace" { drm.run_timeline_signal_trace(); return }; drm.run_timeline_transfer_checks(); drm.run_binary_transfer_checks(); drm.run_timeline_wait_checks(); drm.run_timeline_signal_checks(); drm.run_query_checks(); drm.run_chain_info_checks(); drm.run_wait_checks(); drm.run_large_wait_checks(); drm.run_reset_checks(); drm.run_signal_checks(); drm.run_create_checks(); drm.run_namespace_checks(); drm.run_sharing_checks(); drm.run_sync_file_import_checks(); drm.run_sync_file_poll_checks(); drm.run_sync_file_info_checks(); drm.run_sync_file_deadline_checks(); drm.run_timeline_boundary_checks(); drm.run_export_reservation_checks(); drm.run_sync_lookup_checks() }\n')!
	if os.getenv_opt('DRM_FAKE_FENCE_SOURCE') != none {
		main_path := scratch + '/main.v'
		main_source := os.read_file(main_path)!
		os.write_file(main_path, 'import fake\n' + main_source.replace('fn main() {', 'fn main() { fake.run_checks();'))!
	}
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	mut arguments := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules']
	if os.getenv('DRM_TIMELINE_SIGNAL_MEASURE') != '1' && os.getenv('DRM_TIMELINE_WAIT_MEASURE') != '1' && os.getenv('DRM_BINARY_TRANSFER_MEASURE') != '1' && os.getenv('DRM_TIMELINE_TRANSFER_MEASURE') != '1' {
		arguments << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
	}
	arguments << ['-o', '${scratch}/test', '${scratch}/main.v']
	build.set_args(arguments)
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('DRM_SYNCOBJ_WAIT_TEST_C') {
		assert output.ends_with('.c')
		mut cargs := arguments.clone()
		cargs[cargs.len - 2] = output
		mut generated := os.new_process(os.getenv_opt('V') or { 'v' })
		generated.set_args(cargs); generated.run(); generated.wait()
		if generated.code != 0 { exit(generated.code) }
	}
	if output := os.getenv_opt('DRM_SYNCOBJ_WAIT_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
