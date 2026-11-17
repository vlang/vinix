module g13contract

import g13layout

fn test_normal_teardown_retains_private_ranges_until_collection() {
	root := g13layout.repo_root()
	source := read(root + '/kernel/gpu/agx/gpu/g13.v')!
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	check_teardown_gc_local(source, manager)!
	for name in ['free_g13_render_buffer_locked', 'free_g13_queue_resources_locked', 'free_g13_render_job_locked', 'free_g13_compute_job_locked'] {
		body := section(source, 'fn (mut mgr GpuManager) ' + name + '(', '\n}\n', 'Mutation')!
		for heap in ['g13_private', 'g13_gpu_readonly'] {
			changed := source.replace(body, body.replace('mgr.g13_shared.gc()', 'mgr.' + heap + '.gc()\n\tmgr.g13_shared.gc()'))
			if _ := check_teardown_gc_local(changed, manager) { assert false, name }
		}
	}
	if _ := check_teardown_gc_local(source, manager.replace('mgr.g13_private.gc()', '')) { assert false }
	if _ := check_teardown_gc_local(source, manager.replace('mgr.stop_firmware_cpus(mgr.firmware_roles)', '')) { assert false }
}
