// SPDX-License-Identifier: GPL-2.0-or-later
module nvme

import errno
import memory
import resource

@[packed]
struct NVMECommandGetLog {
pub mut:
	nsid u32
	reserved1 [2]u64
	prp1 u64
	prp2 u64
	cdw10 u32
	cdw11 u32
	cdw12 u32
	cdw13 u32
	cdw14 u32
	cdw15 u32
}

// Controller-wide health, even when queried through a particular namespace.
// A private page lets other namespaces submit commands between the two admin
// requests. Neither the boot identity nor a shared DMA buffer is overwritten.
fn (mut dev NVMENamespace) block_health() ?resource.BlockHealth {
	mut completed := false
	defer { if !completed { dev.metrics.failed() } }
	if dev.parent_controller.failed { errno.set(errno.enodev); return none }
	physical := memory.pmm_alloc_nozero_fallible(1) @[freed]
	if physical == unsafe { nil } { errno.set(errno.enomem); return none }
	mut owned := false
	defer {
		// send_cmd_and_wait returns this marker only when a timed-out
		// controller could not be disabled. Retain its submitted page.
		if !owned { memory.pmm_free(physical, 1) }
	}
	bounce := voidptr(u64(physical) + higher_half)
	mut command := unsafe { &NVMECommand(C.vinix_stack_alloc(sizeof(NVMECommand))) }
	mut report := resource.BlockHealth{protocol: resource.health_nvme, disk_id: dev.stat.rdev}
	for index in 0 .. 2 {
		unsafe {
			C.memset(bounce, 0, page_size)
			*command = NVMECommand{}
			if index == 0 {
				command.opcode = opcode_identify
				command.private.identify.cns = 1
				command.private.identify.prp1 = u64(physical)
			} else {
				command.opcode = 0x02 // Admin Get Log Page, not an NVM read.
				command.private.get_log.nsid = u32(-1)
				command.private.get_log.prp1 = u64(physical)
				// SMART/Health (LID=2), retain asynchronous events (RAE=1),
				// 128 dwords (NUMDL=127). Offset, LSP and NUMDU stay zero.
				command.private.get_log.cdw10 = 2 | (1 << 15) | (127 << 16)
			}
		}
		status := dev.parent_controller.admin_queue.send_cmd_and_wait(mut command, -1)
		if status != 0 {
			owned = status == command_dma_owned
			errno.set(errno.eio); return none
		}
		unsafe {
			if index == 0 { C.memcpy(&report.identify[0], bounce, 512) }
			else { C.memcpy(&report.data[0], bounce, 512) }
		}
	}
	report.flags = resource.health_supported | resource.health_enabled
		| resource.health_data_valid | resource.health_status_valid
	if report.data[0] != 0 { report.flags |= resource.health_threshold_exceeded }
	completed = true
	return report
}
