// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_sync_file_deadline_contract(drm string, uapi string, implementation string) ! {
	dispatch := section(drm, 'fn (mut this SyncFileResource) ioctl(', 'fn (mut this SyncFileResource) unref(', 'Sync-file deadline dispatch')!
	require_order(dispatch, ['if u32(request) == ioctl.sync_ioc_set_deadline', 'sync_file_deadline_ioctl(this.fence, u64(argp))',
		'errno.set(u64(-result))', 'resource.default_ioctl'], 'Typed deadline dispatch')!
	require(integer_constant(uapi, 'sync_ioc_set_deadline', 'Deadline command')! == 0x40103e05, 'Deadline command changed')!
	require_order(section(uapi, 'pub struct SyncSetDeadline {', '\n}', 'Deadline request layout')!,
		['deadline_ns u64', 'pad u64'], 'Fixed-width deadline fields')!
	require(uapi.contains('sizeof(SyncSetDeadline) == 16'), 'Deadline layout must be validated')!
	query := implementation.all_after('fn sync_file_deadline_ioctl(').all_after(') int {')
	require_order(query, ['mut request := ioctl.SyncSetDeadline{}',
		'usercopy.copy_from_user(unsafe { &request }, address, sizeof(ioctl.SyncSetDeadline))', 'return -14',
		'if request.pad != 0 { return -22 }', 'syncobj.set_deadline(fence, i64(request.deadline_ns))',
		'return 0'], 'Copy and reserved-field validation precede the fence hint')!
	require(query.count('usercopy.copy_from_user(') == 1 && !query.contains('usercopy.copy_to_user(')
		&& !query.contains('memory.') && query.count('syncobj.') == 1 && !query.contains('sched.'),
		'Forward one hint without allocating, sleeping or copying output')!
}

fn check_sync_file_deadline_reference(reference string, header string, fences string, rust string, scheduler string) ! {
	require_order(section(header, 'struct sync_set_deadline {', '};', 'Linux deadline layout')!,
		['__u64\tdeadline_ns', '__u64\tpad'], 'Linux deadline fields')!
	require(header.contains('SYNC_IOC_SET_DEADLINE\t_IOW(SYNC_IOC_MAGIC, 5, struct sync_set_deadline)'), 'Linux deadline encoding changed')!
	require_order(section(reference, 'static int sync_file_ioctl_set_deadline(', 'static long sync_file_ioctl(', 'Linux deadline ioctl')!,
		['copy_from_user(&ts,', 'return -EFAULT', 'if (ts.pad)', 'return -EINVAL',
		'dma_fence_set_deadline(sync_file->fence, ns_to_ktime(ts.deadline_ns))', 'return 0'], 'Linux deadline ioctl validation')!
	require_order(section(fences, 'void dma_fence_set_deadline(', 'EXPORT_SYMBOL(dma_fence_set_deadline)', 'Linux optional deadline callback')!,
		['ops = rcu_dereference(fence->ops)', 'if (ops && ops->set_deadline && !dma_fence_is_signaled(fence))',
		'ops->set_deadline(fence, deadline)'], 'Callback-free fences ignore hints')!
	require(section(rust, 'const VTABLE: bindings::dma_fence_ops', '\n    };', 'Rust leaf fence operations')!.contains('set_deadline: None'),
		'Asahi Rust leaf deadline callback changed')!
	stub := section(fences, 'static const struct dma_fence_ops dma_fence_stub_ops', '\n};', 'Linux stub operations')!
	require(!stub.contains('.set_deadline'), 'Private stub deadline behavior changed')!
	require_order(section(scheduler, 'static void drm_sched_fence_set_deadline_finished(', 'static const struct dma_fence_ops drm_sched_fence_ops_scheduled', 'Linux scheduler deadline forwarding')!,
		['ktime_before(fence->deadline, deadline)', 'fence->deadline = deadline',
		'dma_fence_set_deadline(parent, deadline)'], 'Scheduler wrappers retain and forward deadline hints')!
}
