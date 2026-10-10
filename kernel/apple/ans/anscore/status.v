// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module anscore

// Boot-lived, scalar counters protected by the caller's ANS operation lock.
// Physical commands include native filesystem I/O and RMW boundary reads.
pub struct NamespaceMetrics {
pub mut:
	disk_id     u64
	reads       u64
	writes      u64
	read_bytes  u64
	write_bytes u64
	flushes     u64
	errors      u64
	last_error  u64
}

pub struct NamespaceStatus {
pub:
	valid              bool
	offline            bool
	writable_partition int = -1
	metrics            NamespaceMetrics
}

// Keep diagnostics outside the transport's mirrored, exported controller ABI.
// This driver has one boot-lived controller and eight bounded namespace slots.
__global namespace_metrics [8]NamespaceMetrics

pub fn reset_namespace_metrics() {
	unsafe { C.memset(&namespace_metrics, 0, sizeof(namespace_metrics)) }
}

fn a_count_transfer(a &Ans, index u32, bytes u64, writing bool) {
	if a != unsafe { &ans_controller } || index >= 8 || bytes == 0 { return }
	if writing {
		namespace_metrics[index].writes++
		namespace_metrics[index].write_bytes += bytes
	} else {
		namespace_metrics[index].reads++
		namespace_metrics[index].read_bytes += bytes
	}
}

fn a_count_flush(a &Ans, index u32) {
	if a == unsafe { &ans_controller } && index < 8 { namespace_metrics[index].flushes++ }
}

// Publishing the namespace precedes its partitions and retains the physical
// identity even after shutdown. This metadata does not authorize raw writes.
pub fn set_namespace_id(index u32, disk_id u64) {
	if index < ans_controller.nns && index < 8 {
		namespace_metrics[index].disk_id = disk_id
	}
}

pub fn namespace_status(index u32) NamespaceStatus {
	if index >= ans_controller.nns || index >= 8 { return NamespaceStatus{} }
	offline := ans_controller.live == 0 || ans_controller.dead != 0 || ans_controller.stopping != 0
		|| ans_controller.stopped != 0
	writable := !offline && ans_controller.write_enabled != 0 && ans_controller.write_fault == 0
		&& index == ans_controller.write_ns
	return NamespaceStatus{
		valid:              true
		offline:            offline
		writable_partition: if writable { int(ans_controller.write_part) } else { -1 }
		metrics:            namespace_metrics[index]
	}
}

// These count failed block-resource requests, including validation and health
// failures. A native filesystem's internal operation is not a block request.
pub fn namespace_failed(index u32, failure_code u64) {
	if index >= ans_controller.nns || index >= 8 { return }
	namespace_metrics[index].errors++
	namespace_metrics[index].last_error = if failure_code == 0 { u64(5) } else { failure_code }
}
