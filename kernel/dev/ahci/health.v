// SPDX-License-Identifier: GPL-2.0-or-later
module ahci

import errno
import resource

// Called with the port lock held. Reuses the permanently mapped bounce
// buffer and command table; send_cmd quarantines both after a DMA timeout.
fn (mut dev AHCIDevice) health_command(opcode u8, feature u8, data bool) ? {
	slot := dev.find_cmd_slot() or { errno.set(errno.eio); return none }
	mut volatile regs := dev.regs
	mut volatile header := unsafe {
		&AHCIHBACommand((u64(regs.clb) | (u64(regs.clbu) << 32)) + higher_half
			+ slot * sizeof(AHCIHBACommand))
	}
	header.flags = u16(sizeof(AHCIFISh2d) / 4)
	header.prdtl = if data { u16(1) } else { u16(0) }
	header.prdbc = 0
	mut volatile table := unsafe {
		&AHCIHBACommandTable((u64(header.ctba) | (u64(header.ctbau) << 32)) + higher_half)
	}
	if data {
		unsafe { C.memset(dev.bounce, 0, 512) }
		table = dev.set_prdt(header, u64(dev.bounce) - higher_half, 0, 511)
	}
	mut volatile fis := unsafe { &AHCIFISh2d(&table.cfis) }
	unsafe {
		C.memset(fis, 0, sizeof(AHCIFISh2d))
		// AHCI received-FIS area: Register D2H FIS is at byte 0x40. Refuse
		// an absent response instead of treating a previous FIS as success.
		C.memset(voidptr(dev.fis_base + higher_half + 0x40), 0, sizeof(AHCIFISd2h))
	}
	fis.fis_type = fis_reg_h2d
	fis.flags = 1 << 7
	fis.command = opcode
	fis.featurel = feature
	if opcode == 0xb0 {
		fis.lba1 = 0x4f
		fis.lba2 = 0xc2
		if data { fis.countl = 1 }
	}
	if !dev.send_cmd(slot) { errno.set(errno.eio); return none }
	if data && header.prdbc != 512 { errno.set(errno.eio); return none }
}

fn ata_word(bytes &u8, word int) u16 {
	return unsafe { u16(bytes[word * 2]) | (u16(bytes[word * 2 + 1]) << 8) }
}

fn smart_checksum(bytes &u8) bool {
	mut sum := u32(0)
	for i in 0 .. 512 { sum += unsafe { bytes[i] } }
	return sum & 255 == 0
}

fn smart_status(fis &AHCIFISd2h) ?bool {
	if fis.fis_type != fis_reg_d2h || fis.status & 0xa9 != 0 {
		errno.set(errno.eio); return none
	}
	if fis.lba1 == 0x4f && fis.lba2 == 0xc2 { return false }
	if fis.lba1 == 0xf4 && fis.lba2 == 0x2c { return true }
	errno.set(errno.eio)
	return none
}

fn (mut dev AHCIDevice) block_health() ?resource.BlockHealth {
	mut completed := false
	defer { if !completed { dev.metrics.failed() } }
	dev.take(false)
	defer { dev.l.release() }
	if dev.failed { errno.set(errno.enodev); return none }
	mut report := resource.BlockHealth{protocol: resource.health_ata, disk_id: dev.stat.rdev}
	dev.health_command(0xec, 0, true)?
	unsafe { C.memcpy(&report.identify[0], dev.bounce, 512) }
	// Word 83 validates command support words 82-84; word 87 validates
	// enabled words 85-87. SMART support/enabled bits are in 82/85.
	if ata_word(&report.identify[0], 83) & 0xc000 == 0x4000
		&& ata_word(&report.identify[0], 82) & 1 != 0 {
		report.flags |= resource.health_supported
		if ata_word(&report.identify[0], 87) & 0xc000 == 0x4000
			&& ata_word(&report.identify[0], 85) & 1 != 0 {
			report.flags |= resource.health_enabled
			dev.health_command(0xb0, 0xd0, true)?
			if !smart_checksum(&u8(dev.bounce)) { errno.set(errno.eio); return none }
			unsafe { C.memcpy(&report.data[0], dev.bounce, 512) }
			report.flags |= resource.health_data_valid
			dev.health_command(0xb0, 0xda, false)?
			fis := unsafe { &AHCIFISd2h(dev.fis_base + higher_half + 0x40) }
			exceeded := smart_status(fis)?
			report.flags |= resource.health_status_valid
			if exceeded { report.flags |= resource.health_threshold_exceeded }
		}
	}
	completed = true
	return report
}
