module g13contract

import g13layout

fn test_orphan_queue_retry_preserves_logical_and_captured_owners() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	gpu := read(root + '/kernel/gpu/agx/gpu/g13.v')!
	worker := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	check_orphan_queue_local(file, gpu, worker)!
	for token in ['if queue.id == ownership.queue_id { named = true; break }',
		'if named || ownership.resources.has_file_references() { continue }',
		'owned.reap_orphaned_g13_queues_locked()', 'f.g13_queues.delete(index)'] {
		if _ := check_orphan_queue_local(file.replace(token, ''), gpu, worker) { assert false, token }
	}
	if _ := check_orphan_queue_local(file, gpu.replace('if owned.has_file_references() { return false }', ''), worker) { assert false }
	if _ := check_orphan_queue_local(file, gpu, worker.replace('mgr.reap_file_resources()', '')) { assert false }
	if _ := check_orphan_queue_local(file, gpu, worker.replace('sched.reschedule()', 'sched.yield(false)')) { assert false }
}

fn test_orphan_queue_reference_keeps_fallible_construction_before_publication() {
	file := 'pub(crate) fn queue_create( let mut queue = reg_data.gpu.new_queue( vm)?; queue.reserve_render_scs(data.render_scs_layout)?; data.queue_id = resv.index().try_into()?; resv.fill(Arc::pin_init(new_mutex!(queue), GFP_KERNEL)?)?;\n/// IOCTL: queue_destroy:'
	queue := '    pub(crate) fn new( let mut notifier_list = alloc.shared.new_default()?; let threshold = owned()?; let notifier: Arc<T> = owned()?; let buffer = owned()?; let mut ret = Queue::ver { }; ret.inner.buffer.ensure_blocks(tvb_blocks)?; ret.q_vtx = Some(owned()?); ret.q_frag = Some(owned()?); ret.q_comp = Some(owned()?); Ok(ret)\nconst SQ_RENDER:'
	check_orphan_queue_reference(file, queue)!
	for token in ['queue.reserve_render_scs(data.render_scs_layout)?', 'resv.fill(Arc::pin_init(new_mutex!(queue), GFP_KERNEL)?)?'] {
		if _ := check_orphan_queue_reference(file.replace(token, ''), queue) { assert false, token }
	}
	if _ := check_orphan_queue_reference(file, queue.replace('ret.q_frag = Some(', 'ret.q_frag = None; other(')) { assert false }
}
