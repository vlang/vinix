// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import katomic

// Caller holds mgr.lock. The manager/file owners retain every queued object,
// its mapped context and VM until retirement and UAT cleanup both finish.
fn (mut mgr GpuManager) append_g13_context_locked(mut resources G13QueueResources) {
	resources.context_next = unsafe { nil }
	if mgr.g13_context_tail == unsafe { nil } {
		mgr.g13_context_head = &resources
	} else {
		mgr.g13_context_tail.context_next = &resources
	}
	mgr.g13_context_tail = &resources
}

fn (mut mgr GpuManager) defer_g13_context_locked(mut resources G13QueueResources) bool {
	if resources.context_retirement == .complete { return true }
	if resources.context_retirement == .fresh {
		resources.context_retirement = .queued
		mgr.append_g13_context_locked(mut resources)
	}
	return false
}

// Match Asahi's swap-before-drain policy: process the release-order snapshot
// before borrowing an allocator. Unpublished failures remain queued for a
// later borrow. Published failures remain quarantined and cannot be replayed.
fn (mut mgr GpuManager) collect_g13_context_garbage_locked() {
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 { return }
	mut current := mgr.g13_context_head
	mgr.g13_context_head = unsafe { nil }
	mgr.g13_context_tail = unsafe { nil }
	for current != unsafe { nil } {
		mut resources := current
		current = resources.context_next
		resources.context_next = unsafe { nil }
		if !mgr.invalidate_g13_context_locked(mut resources)
			&& resources.context_retirement == .queued {
			mgr.append_g13_context_locked(mut resources)
		}
	}
}

// Caller holds mgr.lock and has excluded every queue user. Keep the context
// mapped through DestroyContext acknowledgement. A published failure is never
// replayed: firmware may have consumed it and recycled its context IDs. Such a
// queue remains quarantined until stopped-firmware teardown bypasses this gate.
fn (mut mgr GpuManager) invalidate_g13_context_locked(mut resources G13QueueResources) bool {
	if resources.context_retirement == .complete { return true }
	if resources.context_retirement == .pending { return false }
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13
		|| resources.context.va == 0 || resources.context.phys == 0 || !resources.context.mapped {
		return false
	}
	private_count, _ := mgr.g13_private.garbage()
	readonly_count, _ := mgr.g13_gpu_readonly.garbage()
	katomic.sync()
	message := fw.make_g13_context_invalidate(mgr.hw_config.firmware_abi,
		resources.context.cpu_address(), resources.context.size, resources.context.va) or { return false }
	token := mgr.channels.device_ctrl.enqueue_with_token(voidptr(&message)) or { return false }
	resources.context_retirement = .pending
	if !mgr.ring_device_control() { return false }
	if !mgr.wait_g13_device_control_locked(token) { return false }
	resources.context_retirement = .complete
	mgr.g13_private.collect_garbage(private_count)
	mgr.g13_gpu_readonly.collect_garbage(readonly_count)
	return true
}
