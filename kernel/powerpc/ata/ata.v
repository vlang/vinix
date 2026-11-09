// SPDX-License-Identifier: GPL-2.0-or-later
// MacIO ATA taskfile PIO: firmware supplies the controller address/timings.
@[has_globals]
module ata

import powerpc.boot
import powerpc.cpu
import powerpc.mmio
import powerpc.ohci
import powerpc.serial

__global ata_base u32
__global ata_drive u8
__global ata_sectors u32
__global ata_hz u32
__global ata_ready bool

fn delay() { for _ in 0 .. 4 { mmio.read8(ata_base + 0x160) } }

fn wait_status(data bool) bool {
	deadline := cpu.timebase() + u64(ata_hz) * 3
	for cpu.timebase() < deadline {
		status := mmio.read8(ata_base + 0x70)
		if status == 0 || status == 0xff { return false }
		if status & 0x80 == 0 {
			if status & 0x21 != 0 { return false }
			if !data || status & 8 != 0 { return true }
		}
		ohci.poll()
	}
	return false
}

pub fn init(info &boot.Info) {
	ata_hz = info.timebase_hz
	for controller := u32(0); controller < info.ata_count && controller < 4; controller++ {
		ata_base = info.ata[controller]
		mmio.write8(ata_base + 0x160, 2) // nIEN: this driver completes commands by polling
		for unit in 0 .. 2 {
			ata_drive = u8(unit << 4)
			mmio.write8(ata_base + 0x60, 0xa0 | ata_drive)
			delay()
			mmio.write8(ata_base + 0x20, 0); mmio.write8(ata_base + 0x30, 0)
			mmio.write8(ata_base + 0x40, 0); mmio.write8(ata_base + 0x50, 0)
			mmio.write8(ata_base + 0x70, 0xec)
			delay()
			if !wait_status(true) { continue } // excludes ATAPI CD-ROMs
			mut identity := [256]u16{}
			for i in 0 .. 256 { identity[i] = mmio.read16(ata_base) }
			if !wait_status(false) || identity[49] & 0x200 == 0 { continue }
			ata_sectors = u32(identity[60]) | u32(identity[61]) << 16
			if ata_sectors < 2048 || ata_sectors > 0x10000000 || identity[83] & 0x1000 == 0 { continue }
			ata_ready = true
			serial.text(c'VINIX-PPC: ATA disk sectors '); serial.hex(ata_sectors); serial.text(c'\n')
			return
		}
	}
	ata_base = 0
}

pub fn capacity() u32 { return if ata_ready { ata_sectors } else { u32(0) } }

fn command(lba u32, writing bool) bool {
	if !ata_ready || lba >= ata_sectors { return false }
	mmio.write8(ata_base + 0x60, 0xe0 | ata_drive | u8(lba >> 24))
	delay()
	if !wait_status(false) { return false }
	mmio.write8(ata_base + 0x20, 1)
	mmio.write8(ata_base + 0x30, u8(lba)); mmio.write8(ata_base + 0x40, u8(lba >> 8)); mmio.write8(ata_base + 0x50, u8(lba >> 16))
	mmio.write8(ata_base + 0x70, if writing { u8(0x30) } else { u8(0x20) })
	delay()
	return wait_status(true)
}

pub fn read(lba u32, data &u8) bool {
	if !command(lba, false) { return false }
	for i := u32(0); i < 512; i += 2 {
		word := mmio.read16(ata_base)
		unsafe { data[i] = u8(word); data[i + 1] = u8(word >> 8) }
	}
	return wait_status(false)
}

pub fn write(lba u32, data &u8) bool {
	if !command(lba, true) { return false }
	for i := u32(0); i < 512; i += 2 { mmio.write16(ata_base, unsafe { u16(data[i]) | u16(data[i + 1]) << 8 }) }
	return wait_status(false)
}

pub fn flush() bool {
	if !ata_ready { return false }
	mmio.write8(ata_base + 0x60, 0xe0 | ata_drive)
	delay()
	if !wait_status(false) { return false }
	mmio.write8(ata_base + 0x70, 0xe7)
	delay()
	return wait_status(false)
}
