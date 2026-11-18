module g13contract

import g13layout

fn logical_queue_contract(file string, fake string, queue string) ! {
	require(file.count('workqueue.free_workqueue(') == 7 && fake.count('workqueue.free_workqueue(') == 2, 'All logical queue owner and failure paths dispose metadata')!
	late := section(file, '// Asahi reserves render scratch', '\tf.queues << wq', 'Unpublished render-scratch rejection')!
	require_order(late, ['release_g13_queue_resources(g13_resources)', 'if !released',
		'resources: g13_resources', 'logical.destroy()', 'workqueue.free_workqueue(logical)',
		'if released { gpu.free_g13_queue_record(g13_resources) }', 'return -22'], 'Late rejection retains or disposes every owner before returning')!
	for code in [file, fake] {
		require_order(code, ['record := unsafe { ', '.queues.delete(', 'workqueue.free_workqueue(record)'], 'Foreach removal preserves a pointer value before deleting its alias')!
	}
	require_order(fake, ['if !queue.is_empty()', 'return -16', 'queue.destroy()', 'record := unsafe { queue }', 'file.queues.delete(index)', 'workqueue.free_workqueue(record)'], 'Idle destroy drains completion before final record reclamation')!
	worker := section(fake, 'fn fake_completion_worker(', 'fn next_unused_vm_id(', 'Fake completion')!
	require_order(worker, ['completion.queue.complete(', 'completion.file.finish_pending_job(', 'free(voidptr(completion.item))'], 'Last queue access and unlock precede the file pin release')!
	require(worker.count('completion.queue') == 1, 'No queue access after possible final close')!
	dispose := queue.all_after('pub fn free_workqueue(')
	require_order(dispose, ['queue &WorkQueue)', 'queue.pending_count == 0', 'unsafe { free(queue) }'], 'Separate one-shot metadata disposal')!
	require(dispose.count('free(') == 1 && !queue.all_before('pub fn free_workqueue(').contains('free(wq)'), 'Destroy never frees a locked record')!
}
fn test_logical_queue_final_owners_and_completion_order() {
	root := g13layout.repo_root()
	file := read(root + '/kernel/gpu/agx/file/file.v')!
	fake := read(root + '/kernel/gpu/agx/fake/driver.v')!
	queue := read(root + '/kernel/gpu/agx/workqueue/workqueue.v')!
	logical_queue_contract(file, fake, queue)!
	for token in ['record := unsafe { q }', 'workqueue.free_workqueue(record)',
		'logical.destroy()', 'workqueue.free_workqueue(logical)'] {
		if _ := logical_queue_contract(file.replace(token, ''), fake, queue) { assert false, token }
	}
	for token in ['record := unsafe { queue }', 'if !queue.is_empty()', 'completion.queue.complete('] {
		if _ := logical_queue_contract(file, fake.replace(token, ''), queue) { assert false, token }
	}
}
