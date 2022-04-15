// ahci.v: AHCI driver.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module ahci

import pci
import memory
import stat
import klock
import event
import event.eventstruct
import resource
import errno
import block.partition
import fs
import katomic

const (
	ahci_class      = 0x1
	ahci_subclass   = 0x6
	ahci_progif     = 0x1
	sata_ata        = 0x101
	sata_atapi      = 0xeb140101
	sata_semb       = 0xc33C0101
	sata_pm         = 0x96690101
	hba_cmd_st      = 0x1
	hba_cmd_fre     = 0x10
	hba_cmd_fr      = 0x4000
	hba_cmd_cr      = 0x8000
	fis_reg_h2d     = 0x27
	fis_reg_d2h     = 0x34
	fis_dma_enable  = 0x39
	fis_dma_setup   = 0x41
	fis_data        = 0x46
	fis_bist        = 0x58
	fis_pio_setup   = 0x5f
	fis_device_bits = 0xa1
	sector_size     = 0x200
)

[packed]
struct AHCIRegisters {
pub mut:
	cap       u32
	ghc       u32
	ints      u32
	pi        u32
	vs        u32
	ccc_ctl   u32
	ccc_ports u32
	em_lock   u32
	em_ctl    u32
	cap2      u32
	bohc      u32
	reserved  [29]u32
	vendor    [24]u32
}

[packed]
struct AHCIPortRegisters {
pub mut:
	clb       u32
	clbu      u32
	fb        u32
	fbu       u32
	ints      u32
	ie        u32
	cmd       u32
	reserved0 u32
	tfd       u32
	sig       u32
	ssts      u32
	sstl      u32
	serr      u32
	sact      u32
	ci        u32
	sntf      u32
	fbs       u32
	devslp    u32
	reserved1 [11]u32
	vs        [10]u32
}

[packed]
struct AHCIHBACommand {
pub mut:
	flags    u16
	prdtl    u16
	prdbc    u32
	ctba     u32
	ctbau    u32
	reserved [4]u32
}

[packed]
struct AHCIHBAPrdt {
pub mut:
	dba      u32
	dbau     u32
	reserved u32
	dbc      u32
}

[packed]
struct AHCIHBACommandTable {
pub mut:
	cfis     [64]u8
	acmd     [16]u8
	reserved [48]u8
	prdt     [1]AHCIHBAPrdt
}

[packed]
struct AHCIFISh2d {
pub mut:
	fis_type u8
	flags    u8
	command  u8
	featurel u8
	lba0     u8
	lba1     u8
	lba2     u8
	device   u8
	lba3     u8
	lba4     u8
	lba5     u8
	featureh u8
	countl   u8
	counth   u8
	icc      u8
	control  u8
	reserved u32
}

[packed]
struct AHCIFISd2h {
	fis_type  u8
	flags     u8
	status    u8
	error     u8
	lba0      u8
	lba1      u8
	lba2      u8
	device    u8
	lba3      u8
	lba4      u8
	lba5      u8
	reserved2 u8
	countl    u8
	counth    u8
	reserved3 u8
	reserved4 u8
}

struct AHCIController {
pub mut:
	pci_bar pci.PCIBar

	volatile regs &AHCIRegisters

	version_min u32
	version_maj u32

	port_cnt  u32
	cmd_slots u32

	device_list []&AHCIDevice
}

struct AHCIDevice {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	parent_controller &AHCIController
	volatile regs              &AHCIPortRegisters
}

__global (
	ahci_controller_list []&AHCIController
)

fn (mut dev AHCIDevice) read(handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if loc % dev.stat.blksize != 0 || count % dev.stat.blksize != 0 {
		errno.set(errno.eio)
		return none
	}

	start_blk := loc / dev.stat.blksize
	page_cnt := count / dev.stat.blksize

	aligned_buffer := voidptr(u64(memory.pmm_alloc(page_cnt)) + higher_half)

	if dev.rw_lba(aligned_buffer, start_blk, page_cnt, false) == -1 {
		errno.set(errno.eio)
		memory.pmm_free(aligned_buffer, page_cnt)
		return none
	}

	unsafe { C.memcpy(buffer, aligned_buffer, count) }

	memory.pmm_free(voidptr(u64(aligned_buffer) - higher_half), page_cnt)

	return i64(count)
}

fn (mut dev AHCIDevice) write(handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if loc % dev.stat.blksize != 0 || count % dev.stat.blksize != 0 {
		errno.set(errno.eio)
		return none
	}

	start_blk := loc / dev.stat.blksize
	page_cnt := count / dev.stat.blksize

	aligned_buffer := voidptr(u64(memory.pmm_alloc(page_cnt)) + higher_half)
	unsafe { C.memcpy(aligned_buffer, buffer, count) }

	if dev.rw_lba(aligned_buffer, start_blk, page_cnt, true) == -1 {
		errno.set(errno.eio)
		memory.pmm_free(aligned_buffer, page_cnt)
		return none
	}

	memory.pmm_free(voidptr(u64(aligned_buffer) - higher_half), page_cnt)

	return i64(count)
}

fn (mut dev AHCIDevice) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut dev AHCIDevice) unref(handle voidptr) ? {
	katomic.dec(dev.refcount)
}

fn (mut dev AHCIDevice) link(handle voidptr) ? {
	katomic.inc(dev.stat.nlink)
}

fn (mut dev AHCIDevice) unlink(handle voidptr) ? {
	katomic.dec(dev.stat.nlink)
}

fn (mut dev AHCIDevice) grow(handle voidptr, new_size u64) ? {
	return error('')
}

fn (mut dev AHCIDevice) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut d AHCIDevice) find_cmd_slot() ?u32 {
	for i := u32(0); i < d.parent_controller.cmd_slots; i++ {
		if ((d.regs.sact | d.regs.ci) & (1 << i)) == 0 {
			return i
		}
	}
	return none
}

fn (mut d AHCIDevice) set_prdt(cmd_hdr &AHCIHBACommand, buffer u64, interrupt u32, byte_cnt u32) &AHCIHBACommandTable {
	mut volatile cmd_table := &AHCIHBACommandTable(cmd_hdr.ctba + higher_half)

	cmd_table.prdt[0].dba = u32(buffer)
	cmd_table.prdt[0].dbau = u32(buffer >> 32)
	cmd_table.prdt[0].dbc = byte_cnt | ((interrupt & 1) << 31)

	return cmd_table
}

fn (mut d AHCIDevice) send_cmd(slot u32) {
	for (d.regs.tfd & (0x88)) != 0 {}

	d.regs.cmd &= ~ahci.hba_cmd_st

	for (d.regs.cmd & ahci.hba_cmd_cr) != 0 {}

	d.regs.cmd |= ahci.hba_cmd_fr | ahci.hba_cmd_st
	d.regs.ci = 1 << slot

	for d.regs.ci & (1 << slot) != 0 {}

	d.regs.cmd &= ~ahci.hba_cmd_st
	for (d.regs.cmd & ahci.hba_cmd_st) != 0 {}
	d.regs.cmd &= ~ahci.hba_cmd_fre
}

fn (mut d AHCIDevice) rw_lba(buffer voidptr, start u64, cnt u64, rw bool) int {
	cmd_slot := d.find_cmd_slot() or {
		print('ahci: no free cmd slot (come back later)\n')
		return -1
	}

	mut volatile cmd_hdr := &AHCIHBACommand(d.regs.clb + higher_half +
		cmd_slot * sizeof(AHCIHBACommand))

	cmd_hdr.flags &= ~(0b11111 | (1 << 6))
	cmd_hdr.flags |= u16(sizeof(AHCIFISh2d) / 4)
	cmd_hdr.prdtl = 1

	mut volatile cmd_table := d.set_prdt(cmd_hdr, u64(buffer) - higher_half, 1, u32(cnt * ahci.sector_size - 1))

	mut volatile cmd_ptr := unsafe { &AHCIFISh2d(&cmd_table.cfis) }
	unsafe { C.memset(cmd_ptr, 0, sizeof(AHCIFISh2d)) }

	if rw == true {
		cmd_ptr.command = 0x35
	} else {
		cmd_ptr.command = 0x25
	}

	cmd_ptr.fis_type = ahci.fis_reg_h2d
	cmd_ptr.flags = (1 << 7)
	cmd_ptr.device = 1 << 6

	cmd_ptr.lba0 = start & 0xff
	cmd_ptr.lba1 = start >> 8 & 0xff
	cmd_ptr.lba2 = start >> 16 & 0xff
	cmd_ptr.lba3 = start >> 24 & 0xff
	cmd_ptr.lba4 = start >> 32 & 0xff
	cmd_ptr.lba5 = start >> 40 & 0xff

	cmd_ptr.countl = cnt & 0xff
	cmd_ptr.counth = cnt >> 8 & 0xff

	d.send_cmd(cmd_slot)

	return 0
}

fn (mut d AHCIDevice) initialise() ?int {
	cmd_slot := d.find_cmd_slot() or {
		print('ahci: no free cmd slot (come back later)\n')
		return none
	}

	mut volatile cmd_hdr := &AHCIHBACommand(d.regs.clb + higher_half +
		cmd_slot * sizeof(AHCIHBACommand))

	cmd_hdr.flags &= ~0b11111 | (1 << 7)
	cmd_hdr.flags |= u16(sizeof(AHCIFISh2d) / 4)
	cmd_hdr.prdtl = 1

	mut identity := &u16(u64(memory.pmm_alloc(1)) + higher_half)

	mut volatile cmd_table := d.set_prdt(cmd_hdr, u64(identity) - higher_half, 1, 511)

	mut volatile cmd_ptr := unsafe { &AHCIFISh2d(&cmd_table.cfis) }
	unsafe { C.memset(cmd_ptr, 0, sizeof(AHCIFISh2d)) }

	cmd_ptr.command = 0xec
	cmd_ptr.flags = (1 << 7)
	cmd_ptr.fis_type = ahci.fis_reg_h2d

	d.send_cmd(cmd_slot)

	mut sector_cnt := unsafe { *(&u64(&identity[100])) }

	mut serial_number := &char(memory.malloc(21))
	mut firmware_revision := &char(memory.malloc(9))
	mut model_number := &char(memory.malloc(41))

	unsafe {
		C.memcpy(serial_number, &byte(identity) + 20, 20)

		for i := 0; i < 20; i += 2 { // swap endianess
			tmp := serial_number[i]
			serial_number[i] = serial_number[i + 1]
			serial_number[i + 1] = tmp
		}

		C.memcpy(firmware_revision, &byte(identity) + 46, 8)

		for i := 0; i < 8; i += 2 { // swap endianess
			tmp := firmware_revision[i]
			firmware_revision[i] = firmware_revision[i + 1]
			firmware_revision[i + 1] = tmp
		}

		C.memcpy(model_number, &byte(identity) + 54, 40)

		for i := 0; i < 40; i += 2 { // swap endianess
			tmp := model_number[i]
			model_number[i] = model_number[i + 1]
			model_number[i + 1] = tmp
		}

		print('ahci: device: serial number: ${cstring_to_vstring(serial_number)}\n')
		print('ahci: device: firmware revision: ${cstring_to_vstring(firmware_revision)}\n')
		print('ahci: device: model number: ${cstring_to_vstring(model_number)}\n')
	}
	print('ahci: device: sector count: $sector_cnt\n')

	d.stat.blocks = sector_cnt
	d.stat.blksize = ahci.sector_size
	d.stat.size = sector_cnt * ahci.sector_size
	d.stat.rdev = resource.create_dev_id()
	d.stat.mode = 0o644 | stat.ifblk

	return 0
}

pub fn (mut c AHCIController) initialise(pci_device &pci.PCIDevice) int {
	pci_device.enable_bus_mastering()

	if pci_device.is_bar_present(0x5) == false {
		print('ahci: unable to locate BAR5\n')
		return -1
	}

	c.pci_bar = pci_device.get_bar(0x5)
	c.regs = &AHCIRegisters(c.pci_bar.base + higher_half)

	c.version_maj = c.regs.vs >> 16 & 0xffff
	c.version_min = c.regs.vs & 0xffff

	print('ahci: controller detected version ${c.version_maj:x}:${c.version_min:x}\n')

	if c.regs.cap & (1 << 31) == 0 {
		print('ahci: 64 bit addressing not supported\n')
		return -1
	}

	c.port_cnt = c.regs.cap & 0b11111
	c.cmd_slots = c.regs.cap >> 8 & 0b11111

	for i := u64(0); i < c.port_cnt; i++ {
		if c.regs.pi & (1 << i) != 0 {
			mut volatile port := &AHCIPortRegisters(c.pci_bar.base + sizeof(AHCIRegisters) +
				i * sizeof(AHCIPortRegisters) + higher_half)

			match port.sig {
				ahci.sata_ata {
					print('ahci: sata drive found on port $i\n')

					mut device := &AHCIDevice{
						parent_controller: unsafe { c }
						regs: port
					}

					device.initialise() or {
						print('unable to init device\n')
						continue
					}

					fs.devtmpfs_add_device(device, 'sd$c.device_list.len')
					partition.scan_partitions(mut device, 'sd$c.device_list.len-')

					c.device_list << device
				}
				ahci.sata_atapi {
					print('ahci: enclosure management bridge found on port $i\n')
				}
				ahci.sata_pm {
					print('ahci: port multipler found on port $i\n')
				}
				else {}
			}
		}
	}

	return 0
}

pub fn initialise() {
	for device in scanned_devices {
		if device.class == ahci.ahci_class && device.subclass == ahci.ahci_subclass
			&& device.prog_if == ahci.ahci_progif {
			mut ahci_device := &AHCIController{
				regs: 0
			}

			if ahci_device.initialise(device) != -1 {
				ahci_controller_list << ahci_device
			}
		}
	}
}
