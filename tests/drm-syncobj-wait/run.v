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
	os.cp_all('${repo}/tests/agx-file-close/fixture/klock', '${scratch}/klock', false)!
	os.cp_all('${repo}/tests/agx-async/fixture/katomic', '${scratch}/katomic', false)!
	os.cp_all('${repo}/tests/agx-async/fixture/event', '${scratch}/event', false)!
	os.cp('${repo}/kernel/file/reservation.v', '${scratch}/file/reservation.v')!
	native_file := os.read_file('${repo}/kernel/file/file.v')!
	os.write_file('${scratch}/file/table.v', 'module file\nimport proc\nimport errno\n' +
		section(native_file, 'pub fn fdnum_create_from_fd(', '// Make room in a descriptor table')!)!
	source := os.read_file('${repo}/kernel/drm/drm.v')!
	production := 'module drm\nimport drm.ioctl\nimport drm.syncobj\nimport usercopy\nimport sched\nimport proc\nimport katomic\nimport file\nimport resource\nimport errno\nimport stat\nimport klock\nimport memory\nimport event.eventstruct\n' +
		section(source, 'struct SyncFileResource {', '// A PRIME fd')! +
		section(source, 'fn (mut this SyncFileResource) poll_status(', '__global (')! +
		section(source, 'fn ioctl_syncobj_create(', 'fn create_prime_fd(')! +
		section(source, 'fn ioctl_syncobj_destroy(', 'fn ioctl_syncobj_wait(')! +
		section(source, 'fn ioctl_syncobj_wait(', 'fn core_ioctl(')!
	os.write_file('${scratch}/drm/production.v', production)!
	os.cp('${repo}/kernel/drm/syncobj_fd.v', '${scratch}/drm/syncobj_fd.v')!
	os.cp('${repo}/kernel/drm/sync_file_info.v', '${scratch}/drm/sync_file_info.v')!
	os.cp('${repo}/kernel/drm/sync_file_deadline.v', '${scratch}/drm/sync_file_deadline.v')!
	// Execute the native sync-array staging/publication functions without
	// pulling unrelated render/compute decoding into this focused fixture.
	submission := os.read_file('${repo}/kernel/gpu/agx/submission/submission.v')!
	os.mkdir_all('${scratch}/gpu/agx/submission')!
	os.write_file('${scratch}/gpu/agx/submission/production.v', 'module submission\nimport drm.ioctl\nimport drm.syncobj\nimport usercopy\n' +
		section(submission, 'pub const max_syncs =', 'pub struct SyncArray {')! +
		section(submission, 'pub struct SyncArray {', 'pub struct Command {')! +
		section(submission, 'pub fn stage_sync_array(', '// Snapshot one descriptor')!)!
	os.write_file('${scratch}/drm/registration.v', 'module drm\nimport drm.ioctl\n' +
		section(source, 'struct DrmIoctlLayout {', 'fn common_ioctl_layout(')! +
		section(source, 'fn common_ioctl_layout(', 'fn ioctl_layout(')!)!
	os.cp('${repo}/kernel/drm/wait_storage.v', '${scratch}/drm/wait_storage.v')!
	os.cp('${repo}/tests/drm-syncobj-wait/capture_checks.v', '${scratch}/drm/syncobj/capture_checks.v')!
	process_source := os.read_file('${repo}/kernel/proc/proc.v')!
	os.write_file('${scratch}/proc/production.v', 'module proc\nimport katomic\n' +
		section(process_source, 'pub fn pending_signals(', '// Read-mostly limits')!)!
	os.write_file('${scratch}/main.v', 'import drm\nfn main() { drm.run_wait_checks(); drm.run_large_wait_checks(); drm.run_reset_checks(); drm.run_signal_checks(); drm.run_create_checks(); drm.run_namespace_checks(); drm.run_sharing_checks(); drm.run_sync_file_import_checks(); drm.run_sync_file_poll_checks(); drm.run_sync_file_info_checks(); drm.run_sync_file_deadline_checks(); drm.run_timeline_boundary_checks(); drm.run_export_reservation_checks(); drm.run_sync_lookup_checks() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	arguments := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v']
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
