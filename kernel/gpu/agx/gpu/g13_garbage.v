// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import aarch64.timer
import katomic

const g13_max_fw_garbage_bytes = u64(16 * 1024 * 1024)
const g13_max_fw_garbage_objects = u64(2048)

fn g13_heap_garbage_needs_collection(private_count u64, private_bytes u64,
	readonly_count u64, readonly_bytes u64) bool {
	return private_bytes > g13_max_fw_garbage_bytes || readonly_bytes > g13_max_fw_garbage_bytes
		|| private_count > g13_max_fw_garbage_objects || readonly_count > g13_max_fw_garbage_objects
}

// Caller holds mgr.lock, serializing device-control producers and shutdown.
// Leave every deferred owner reserved on failure. The firmware worker observes
// sticky channel faults separately, just as for other failed publications.
fn (mut mgr GpuManager) flush_g13_fw_cache_locked() bool {
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 { return false }
	message := fw.make_g13_cache_flush(mgr.hw_config.firmware_abi) or { return false }
	token := mgr.channels.device_ctrl.enqueue_with_token(voidptr(&message)) or { return false }
	if !mgr.ring_device_control() { return false }
	started := timer.get_ns()
	for mgr.channels.device_ctrl.read_pointer() != token {
		if mgr.state != .running || mgr.channels.device_ctrl.has_fault()
			|| timer.get_ns() - started >= u64(1_000_000_000) { return false }
		katomic.sync()
	}
	return true
}

// Asahi checks both deferred heaps when borrowing the kernel allocators. Only
// counts captured before the cache barrier may be collected: later releases
// must remain reserved for a subsequent barrier. Initialization has no running
// firmware and keeps its existing explicit unwind collection.
fn (mut mgr GpuManager) collect_g13_heap_garbage_locked() {
	if mgr.state != .running || mgr.hw_config.gpu_gen != .g13 { return }
	private_count, private_bytes := mgr.g13_private.garbage()
	readonly_count, readonly_bytes := mgr.g13_gpu_readonly.garbage()
	if !g13_heap_garbage_needs_collection(private_count, private_bytes, readonly_count, readonly_bytes) { return }
	if !mgr.flush_g13_fw_cache_locked() {
		C.printf(c'agx: failed to flush firmware cache for heap collection\n')
		return
	}
	mgr.g13_private.collect_garbage(private_count)
	mgr.g13_gpu_readonly.collect_garbage(readonly_count)
}
