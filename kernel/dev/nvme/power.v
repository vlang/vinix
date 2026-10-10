// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Telling an NVMe controller that power is about to go.
//
// A flush makes the data durable; the shutdown notification lets the drive
// finish its own bookkeeping -- the mapping tables it keeps in volatile
// memory -- so that it does not have to rebuild them from its journal the
// next time it is powered, and does not count an unsafe shutdown against
// itself. The controller is asked with CC.SHN and says it is done in
// CSTS.SHST; the specification lets it take as long as its RTD3 entry
// latency, which is seconds on a slow drive.
module nvme

import devcore

// CC.SHN, bits 15:14: 01 asks for a normal shutdown.
const cc_shutdown_mask = u32(3) << 14
const cc_shutdown_normal = u32(1) << 14
// CSTS.SHST, bits 3:2: 10 says shutdown processing is complete.
const csts_shutdown_mask = u32(3) << 2
const csts_shutdown_complete = u32(2) << 2

const shutdown_timeout_ns = 10 * devcore.second

fn shutdown_complete(context voidptr) bool {
	mut volatile regs := unsafe { &NVMERegisters(context) }
	// All ones is a controller that is gone, which is as shut down as it gets.
	return regs.csts == 0xffffffff || regs.csts & csts_shutdown_mask == csts_shutdown_complete
}

// Before power off or reset. The caller has flushed the filesystems; from
// here on the controller takes no more requests.
fn controller_shutdown(mut dev devcore.Device) {
	mut controller := unsafe { &NVMEController(dev.driver_data) }
	if controller == unsafe { nil } || controller.regs == unsafe { nil } {
		return
	}
	controller.l.acquire()
	controller.failed = true
	controller.l.release()
	mut volatile regs := controller.regs
	regs.cc = (regs.cc & ~cc_shutdown_mask) | cc_shutdown_normal
	if !devcore.sleep_until(shutdown_complete, voidptr(controller.regs), shutdown_timeout_ns, 1) {
		print('nvme: the controller did not finish shutting down in time\n')
	}
}
