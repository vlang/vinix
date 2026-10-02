@[has_globals]
module ahci

import pci
import memory
import stat
import klock
import event.eventstruct
import resource
import errno
import block.partition
import fs
import katomic
import lib
import time.sys
import proc
import x86.hpet as hpet_clock

const ahci_class = 0x1
const ahci_subclass = 0x6
const ahci_progif = 0x1
const sata_ata = 0x101
const sata_atapi = u32(0xeb140101)
const sata_semb = u32(0xc33C0101)
const sata_pm = u32(0x96690101)
const hba_cmd_st = 0x1
const hba_cmd_fre = 0x10
const hba_cmd_fr = 0x4000
const hba_cmd_cr = 0x8000
const fis_reg_h2d = 0x27
const fis_reg_d2h = 0x34
const fis_dma_enable = 0x39
const fis_dma_setup = 0x41
const fis_data = 0x46
const fis_bist = 0x58
const fis_pio_setup = 0x5f
const fis_device_bits = 0xa1
const sector_size = 0x200
// The most one command moves: the size of each disk's bounce buffer. A
// command has one PRDT entry, which would take up to 4 MiB.
const max_transfer = u64(1024 * 1024)
const command_timeout_ns = u64(30_000_000_000)
const port_error_mask = u32((1 << 30) | (1 << 29) | (1 << 28) | (1 << 27) | (1 << 26) | (1 << 24))

@[packed]
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

@[packed]
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

@[packed]
struct AHCIHBACommand {
pub mut:
	flags    u16
	prdtl    u16
	prdbc    u32
	ctba     u32
	ctbau    u32
	reserved [4]u32
}

@[packed]
struct AHCIHBAPrdt {
pub mut:
	dba      u32
	dbau     u32
	reserved u32
	dbc      u32
}

@[packed]
struct AHCIHBACommandTable {
pub mut:
	cfis     [64]u8
	acmd     [16]u8
	reserved [48]u8
	prdt     [1]AHCIHBAPrdt
}

@[packed]
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

@[packed]
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
	volatile regs    &AHCIRegisters

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
	// Where every transfer is staged: max_transfer bytes, physically
	// contiguous, taken once while memory still has runs that long.
	bounce voidptr = unsafe { nil }
	// A timed-out command may still own the permanent bounce buffer and
	// command tables. Keep them allocated and refuse to reuse this port.
	failed        bool
	flush_command u8
}

__global (
	ahci_controller_list []&AHCIController
)

fn (mut dev AHCIDevice) read(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	return dev.transfer(buffer, loc, count, false)
}

fn (mut dev AHCIDevice) write(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	return dev.transfer(buffer, loc, count, true)
}

fn (mut dev AHCIDevice) sync(_handle voidptr) ? {
	dev.l.acquire()
	defer { dev.l.release() }
	if dev.failed || dev.flush_command == 0 {
		errno.set(errno.eio)
		return none
	}
	slot := dev.find_cmd_slot() or {
		errno.set(errno.eio)
		return none
	}
	mut volatile regs := dev.regs
	mut volatile header := unsafe {
		&AHCIHBACommand((u64(regs.clb) | (u64(regs.clbu) << 32)) + higher_half +
			slot * sizeof(AHCIHBACommand))
	}
	// FLUSH CACHE is a non-data command: there is no PRDT or write flag.
	header.flags = u16(sizeof(AHCIFISh2d) / 4)
	header.prdtl = 0
	header.prdbc = 0
	mut volatile table := unsafe {
		&AHCIHBACommandTable((u64(header.ctba) | (u64(header.ctbau) << 32)) + higher_half)
	}
	mut volatile fis := unsafe { &AHCIFISh2d(&table.cfis) }
	unsafe { C.memset(fis, 0, sizeof(AHCIFISh2d)) }
	fis.fis_type = fis_reg_h2d
	fis.flags = 1 << 7
	fis.command = dev.flush_command
	if !dev.send_cmd(slot) {
		errno.set(errno.eio)
		return none
	}
}

// Move `count` bytes at `loc` through the bounce buffer, a chunk per
// command. One command at a time: the port is stopped and started around
// each, and the page cache's writeback thread shares the disk with whoever
// else is reading or writing it. The buffer used to be allocated for each
// call, a page per sector; once the page cache had filled memory, no run was
// that long and the allocator panicked.
fn (mut dev AHCIDevice) transfer(buffer voidptr, loc u64, count u64, write bool) ?i64 {
	if loc % dev.stat.blksize != 0 || count % dev.stat.blksize != 0 {
		errno.set(errno.eio)
		return none
	}
	if count == 0 {
		return 0
	}
	// A program's buffer (read(2) of /dev/sd0 hands it over as it is) is
	// copied with no lock held: touching it can fault, and the fault can come
	// back here for a page of a file on this disk.
	user := u64(buffer) < memory.user_address_limit()
	mut staging := voidptr(unsafe { nil })
	mut staging_pages := u64(0)
	mut most := max_transfer
	if user {
		// As much as a command takes, or a page when memory is short.
		staging_pages = lib.div_roundup(if count < max_transfer { count } else { max_transfer },
			page_size)
		mut physical := memory.pmm_alloc_nozero_fallible(staging_pages)
		if physical == unsafe { nil } {
			staging_pages = 1
			physical = memory.pmm_alloc_nozero_fallible(1)
		}
		if physical == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		staging = voidptr(u64(physical) + higher_half)
		most = staging_pages * page_size
	}
	defer {
		if staging != unsafe { nil } {
			memory.pmm_free(voidptr(u64(staging) - higher_half), staging_pages)
		}
	}
	for done := u64(0); done < count; {
		chunk := if count - done < most { count - done } else { most }
		caller := voidptr(u64(buffer) + done)
		near := if user { staging } else { caller }
		if write && user {
			unsafe { C.memcpy(staging, caller, chunk) }
		}
		dev.l.acquire()
		if dev.failed {
			dev.l.release()
			errno.set(errno.eio)
			return none
		}
		if write {
			unsafe { C.memcpy(dev.bounce, near, chunk) }
		}
		ok := dev.rw_lba(dev.bounce, (loc + done) / u64(dev.stat.blksize),
			chunk / u64(dev.stat.blksize), write) != -1
		if ok && !write {
			unsafe { C.memcpy(near, dev.bounce, chunk) }
		}
		dev.l.release()
		if !ok {
			errno.set(errno.eio)
			return none
		}
		proc.account_disk_transfer(chunk, write)
		if !write && user {
			unsafe { C.memcpy(caller, staging, chunk) }
		}
		done += chunk
	}
	return i64(count)
}

fn (mut dev AHCIDevice) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut dev AHCIDevice) unref(_handle voidptr) ? {
	katomic.dec(mut &dev.refcount)
}

fn (mut dev AHCIDevice) link(_handle voidptr) ? {
	katomic.inc(mut &dev.stat.nlink)
}

fn (mut dev AHCIDevice) unlink(_handle voidptr) ? {
	katomic.dec(mut &dev.stat.nlink)
}

fn (mut dev AHCIDevice) grow(_handle voidptr, _new_size u64) ? {
	return none
}

fn (mut dev AHCIDevice) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

fn (mut d AHCIDevice) find_cmd_slot() ?u32 {
	if d.failed { return none }
	mut volatile regs := d.regs
	for i := u32(0); i < d.parent_controller.cmd_slots; i++ {
		if ((regs.sact | regs.ci) & (1 << i)) == 0 {
			return i
		}
	}
	return none
}

fn (mut d AHCIDevice) set_prdt(cmd_hdr &AHCIHBACommand, buffer u64, interrupt u32, byte_cnt u32) &AHCIHBACommandTable {
	mut volatile cmd_table := unsafe {
		&AHCIHBACommandTable((u64(cmd_hdr.ctba) | (u64(cmd_hdr.ctbau) << 32)) + higher_half)
	}

	cmd_table.prdt[0].dba = u32(buffer)
	cmd_table.prdt[0].dbau = u32(buffer >> 32)
	cmd_table.prdt[0].dbc = byte_cnt | ((interrupt & 1) << 31)

	return cmd_table
}

fn (mut d AHCIDevice) send_cmd(slot u32) bool {
	// The registers are read through a volatile local. V does not carry
	// `volatile` on a struct field into C, and in a -prod kernel each loop
	// below then read its register once and spun for good.
	mut volatile regs := d.regs
	if d.failed { return false }
	deadline := hpet_clock.nanoseconds() + command_timeout_ns
	for (regs.tfd & (0x88)) != 0 {
		if hpet_clock.nanoseconds() >= deadline {
			d.failed = true
			return false
		}
		klock.spin_hint()
	}

	regs.cmd &= ~hba_cmd_st

	for (regs.cmd & hba_cmd_cr) != 0 {
		if hpet_clock.nanoseconds() >= deadline {
			d.failed = true
			return false
		}
		klock.spin_hint()
	}

	// FIS receive before start, as the specification orders them. This set
	// hba_cmd_fr, the read-only "FIS receive running" bit, so from the second
	// command on the port ran without it.
	regs.cmd |= hba_cmd_fre
	regs.cmd |= hba_cmd_st
	regs.ints = u32(-1)
	regs.serr = u32(-1)
	katomic.sync()
	regs.ci = 1 << slot

	for regs.ci & (1 << slot) != 0 {
		if regs.ints & port_error_mask != 0 || hpet_clock.nanoseconds() >= deadline {
			// Stop issuing work. Do not reuse DMA memory even if this engine
			// fails to stop; all device-owned allocations are permanent.
			regs.cmd &= ~hba_cmd_st
			d.failed = true
			return false
		}
		klock.spin_hint()
	}
	katomic.sync()
	ok := regs.ints & port_error_mask == 0 && regs.tfd & 1 == 0

	// Stopped when the list engine says so (CR), and FIS receive the same
	// way (FR); this waited on the bits it had just cleared.
	regs.cmd &= ~hba_cmd_st
	for (regs.cmd & hba_cmd_cr) != 0 {
		if hpet_clock.nanoseconds() >= deadline {
			d.failed = true
			return false
		}
		klock.spin_hint()
	}
	regs.cmd &= ~hba_cmd_fre
	for (regs.cmd & hba_cmd_fr) != 0 {
		if hpet_clock.nanoseconds() >= deadline {
			d.failed = true
			return false
		}
		klock.spin_hint()
	}
	return ok
}

fn (mut d AHCIDevice) rw_lba(buffer voidptr, start u64, cnt u64, rw bool) int {
	cmd_slot := d.find_cmd_slot() or {
		print('ahci: no free cmd slot (come back later)\n')
		return -1
	}

	mut volatile regs := d.regs
	mut volatile cmd_hdr := unsafe {
		&AHCIHBACommand((u64(regs.clb) | (u64(regs.clbu) << 32)) + higher_half +
			cmd_slot * sizeof(AHCIHBACommand))
	}

	cmd_hdr.flags &= ~(0b11111 | (1 << 6))
	cmd_hdr.flags |= u16(sizeof(AHCIFISh2d) / 4)
	if rw { cmd_hdr.flags |= 1 << 6 }
	cmd_hdr.prdtl = 1
	cmd_hdr.prdbc = 0

	mut volatile cmd_table := d.set_prdt(cmd_hdr, u64(buffer) - higher_half, 1, u32(cnt * sector_size - 1))

	mut volatile cmd_ptr := unsafe { &AHCIFISh2d(&cmd_table.cfis) }
	unsafe { C.memset(cmd_ptr, 0, sizeof(AHCIFISh2d)) }

	if rw == true {
		cmd_ptr.command = 0x35
	} else {
		cmd_ptr.command = 0x25
	}

	cmd_ptr.fis_type = fis_reg_h2d
	cmd_ptr.flags = (1 << 7)
	cmd_ptr.device = 1 << 6

	cmd_ptr.lba0 = u8(start & 0xff)
	cmd_ptr.lba1 = u8((start >> 8) & 0xff)
	cmd_ptr.lba2 = u8((start >> 16) & 0xff)
	cmd_ptr.lba3 = u8((start >> 24) & 0xff)
	cmd_ptr.lba4 = u8((start >> 32) & 0xff)
	cmd_ptr.lba5 = u8((start >> 40) & 0xff)

	cmd_ptr.countl = u8(cnt & 0xff)
	cmd_ptr.counth = u8((cnt >> 8) & 0xff)

	if !d.send_cmd(cmd_slot) { return -1 }

	return 0
}

fn (mut d AHCIDevice) initialise() ?int {
	cmd_slot := d.find_cmd_slot() or {
		print('ahci: no free cmd slot (come back later)\n')
		return none
	}

	mut volatile regs := d.regs
	command_list := u64(memory.pmm_alloc(1))

	regs.clb = u32(command_list)
	regs.clbu = u32(command_list >> 32)

	for i := u32(0); i < 32; i++ {
		mut volatile cmd_hdr := unsafe {
			&AHCIHBACommand((u64(regs.clb) | (u64(regs.clbu) << 32)) + higher_half +
				i * sizeof(AHCIHBACommand))
		}

		desc_base := u64(memory.pmm_alloc(1))

		cmd_hdr.ctba = u32(desc_base)
		cmd_hdr.ctbau = u32(desc_base >> 32)
	}

	fib_base := u64(memory.pmm_alloc(1))

	regs.fb = u32(fib_base)
	regs.fbu = u32(fib_base >> 32)

	regs.cmd |= (1 << 0) | (1 << 4)

	mut volatile cmd_hdr := unsafe {
		&AHCIHBACommand((u64(regs.clb) | (u64(regs.clbu) << 32)) + higher_half +
			cmd_slot * sizeof(AHCIHBACommand))
	}

	cmd_hdr.flags &= ~0b11111 | (1 << 7)
	cmd_hdr.flags |= u16(sizeof(AHCIFISh2d) / 4)
	cmd_hdr.prdtl = 1

	mut identity := unsafe { &u16(u64(memory.pmm_alloc(1)) + higher_half) }

	mut volatile cmd_table := d.set_prdt(cmd_hdr, u64(identity) - higher_half, 1, 511)

	mut volatile cmd_ptr := unsafe { &AHCIFISh2d(&cmd_table.cfis) }
	unsafe { C.memset(cmd_ptr, 0, sizeof(AHCIFISh2d)) }

	cmd_ptr.command = 0xec
	cmd_ptr.flags = (1 << 7)
	cmd_ptr.fis_type = fis_reg_h2d

	if !d.send_cmd(cmd_slot) {
		// IDENTIFY may still be writing; retain its page on failure.
		return none
	}
	// ATA IDENTIFY word 83 declares FLUSH CACHE/FLUSH CACHE EXT support.
	// Do not silently report a persistence barrier on an unsupported disk.
	commands := unsafe { identity[83] }
	if commands & 0xc000 == 0x4000 {
		if commands & (1 << 13) != 0 {
			d.flush_command = 0xea
		} else if commands & (1 << 12) != 0 {
			d.flush_command = 0xe7
		}
	}

	mut sector_cnt := unsafe { *(&u64(&identity[100])) }

	mut serial_number := &char(memory.malloc(21))
	mut firmware_revision := &char(memory.malloc(9))
	mut model_number := &char(memory.malloc(41))

	unsafe {
		C.memcpy(serial_number, &u8(identity) + 20, 20)

		for i := 0; i < 20; i += 2 { // swap endianess
			tmp := serial_number[i]
			serial_number[i] = serial_number[i + 1]
			serial_number[i + 1] = tmp
		}

		C.memcpy(firmware_revision, &u8(identity) + 46, 8)

		for i := 0; i < 8; i += 2 { // swap endianess
			tmp := firmware_revision[i]
			firmware_revision[i] = firmware_revision[i + 1]
			firmware_revision[i + 1] = tmp
		}

		C.memcpy(model_number, &u8(identity) + 54, 40)

		for i := 0; i < 40; i += 2 { // swap endianess
			tmp := model_number[i]
			model_number[i] = model_number[i + 1]
			model_number[i + 1] = tmp
		}

		C.kprintf(c'ahci: device: serial number: %s\n', serial_number)
		C.kprintf(c'ahci: device: firmware revision: %s\n', firmware_revision)
		C.kprintf(c'ahci: device: model number: %s\n', model_number)
		free(serial_number)
		free(firmware_revision)
		free(model_number)
	}
	C.kprintf(c'ahci: device: sector count: %llu\n', u64(sector_cnt))

	d.bounce = voidptr(u64(memory.pmm_alloc(lib.div_roundup(max_transfer, page_size))) +
		higher_half)

	d.stat.blocks = sector_cnt
	d.stat.blksize = sector_size
	d.stat.size = sector_cnt * sector_size
	d.stat.rdev = resource.create_dev_id()
	d.stat.mode = 0o644 | stat.ifblk
	memory.pmm_free(voidptr(u64(identity) - higher_half), 1)

	return 0
}

pub fn (mut c AHCIController) declare_ownership() int {
	// Through a volatile local, as AHCIDevice.send_cmd() explains.
	mut volatile regs := c.regs
	if regs.cap2 & (1 << 0) == 0 {
		print('ahci: bios handoff not supported\n')
		return -1
	}

	regs.bohc |= (1 << 1)

	for regs.bohc & (1 << 0) == 0 {
		asm volatile amd64 {
			pause
		}
	}

	sys.nsleep(25 * 1000000)

	if regs.bohc & (1 << 4) != 0 {
		sys.nsleep(2 * 1000000000)
	}

	if regs.bohc & (1 << 4) != 0 || regs.bohc & (1 << 0) != 0 || regs.bohc & (1 << 1) == 0 {
		print('ahci: bios handoff failed\n')
		return -1
	}

	return 0
}

pub fn (mut c AHCIController) initialise(pci_device &pci.PCIDevice) int {
	pci_device.enable_bus_mastering()

	if pci_device.is_bar_present(0x5) == false {
		print('ahci: unable to locate BAR5\n')
		return -1
	}

	c.pci_bar = pci_device.get_bar(0x5)
	c.regs = unsafe { &AHCIRegisters(c.pci_bar.base + higher_half) }
	mut volatile regs := c.regs

	c.version_maj = (regs.vs >> 16) & 0xffff
	c.version_min = regs.vs & 0xffff

	C.kprintf(c'ahci: controller detected version %llx:%llx\n', u64(c.version_maj),
		u64(c.version_min))

	if regs.cap & (1 << 31) == 0 {
		print('ahci: 64 bit addressing not supported\n')
		return -1
	}

	c.declare_ownership()

	regs.ghc |= (1 << 31)
	regs.ghc &= ~(1 << 1)

	c.port_cnt = regs.cap & 0b11111
	c.cmd_slots = (regs.cap >> 8) & 0b11111

	for i := u64(0); i < c.port_cnt; i++ {
		if regs.pi & (1 << i) != 0 {
			mut volatile port := unsafe {
				&AHCIPortRegisters(c.pci_bar.base + sizeof(AHCIRegisters) +
					i * sizeof(AHCIPortRegisters) + higher_half)
			}

			match port.sig {
				sata_ata {
					C.kprintf(c'ahci: sata drive found on port %llu\n', u64(i))

					mut device := &AHCIDevice{
						parent_controller: unsafe { c }
						regs:              port
					}

					device.initialise() or {
						print('unable to init device\n')
						continue
					}

					// The device node keeps the name; the partitions' names are
					// made from the prefix, which goes afterwards.
					mut name := lib.new_text(8)
					name.add('sd')
					name.add_decimal(c.device_list.len)
					fs.devtmpfs_add_device(device, name.str())
					mut prefix_text := lib.new_text(8)
					prefix_text.add('sd')
					prefix_text.add_decimal(c.device_list.len)
					prefix_text.add_byte(`-`)
					prefix := prefix_text.str()
					partition.scan_partitions(mut device, prefix)
					unsafe { prefix.free() }

					c.device_list << device
				}
				sata_atapi {
					C.kprintf(c'ahci: enclosure management bridge found on port %llu\n', u64(i))
				}
				sata_pm {
					C.kprintf(c'ahci: port multipler found on port %llu\n', u64(i))
				}
				else {}
			}
		}
	}

	return 0
}

pub fn initialise() {
	for device in scanned_devices {
		if device.class == ahci_class && device.subclass == ahci_subclass
			&& device.prog_if == ahci_progif {
			mut ahci_device := &AHCIController{
				regs: unsafe { nil }
			}

			if ahci_device.initialise(device) != -1 {
				ahci_controller_list << ahci_device
			}
		}
	}
}
