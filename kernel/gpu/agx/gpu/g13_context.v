// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import aarch64.timer
import katomic

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
	started := timer.get_ns()
	for mgr.channels.device_ctrl.read_pointer() != token {
		if mgr.state != .running || mgr.channels.device_ctrl.has_fault()
			|| timer.get_ns() - started >= u64(1_000_000_000) { return false }
		katomic.sync()
	}
	resources.context_retirement = .complete
	mgr.g13_private.collect_garbage(private_count)
	mgr.g13_gpu_readonly.collect_garbage(readonly_count)
	return true
}
