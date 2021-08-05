module ata

import pci
import stat
import klock
import memory
import resource
import fs
import x86.kio
import lib
import errno

const pci_class = 0x1
const pci_subclass = 0x1
const pci_progif = 0x80
const ata_ports = [0x1f0, 0x1f0, 0x170, 0x170]
const ata_bytes_per_sector = 512
const ata_sectors_per_prdt = 16
const ata_bytes_per_prdt = ata_bytes_per_sector * ata_sectors_per_prdt

[packed]
struct PRDT {
pub mut:
	buffer_phys u32
	transfer_size u16
	mark_end u16
}

struct ATADrive {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock

	// ATA specific stuff.
	is_master bool
	data_port u16
	error_port u16
	sector_count_port u16
	lba_low_port u16
	lba_mid_port u16
	lba_hi_port u16
	device_port u16
	cmd_port u16
	bar4 u16
	bmr_command u16
	bmr_status u16
	bmr_prdt u16
	prdt &PRDT
	prdt_phys u32
	prdt_cache &byte
}

pub fn initialise() {
	// Fetch and setup the PCI device.
	mut dev := pci.get_device_by_class(pci_class, pci_subclass, pci_progif) or {
		print('ata: No suitable PCI devices found\n')
		return
	}
	dev.enable_bus_mastering()

	// Probe ports and add devices.
	mut index := 0
	for i in 0 .. ata_ports.len {
		drive := init_ata_drive(i, mut dev) or {
			continue
		}
		name := 'ata${index}'
		fs.devtmpfs_add_device(drive, name)
		print("ata: Port ${i} initialised as ${name} (${drive.stat.size} bytes)\n")
		index += 1
	}
}

fn init_ata_drive(port_index int, mut pci_device pci.PCIDevice) ?&ATADrive {
	assert port_index < ata_ports.len

	// Fetch the IO ports and comm addresses of the drive.
	port := u16(ata_ports[port_index])
	mut bar4 := u16(pci_device.read<u32>(0x20))
	if bar4 & 1 != 0 {
		bar4 &= 0xfffffffc
	}
	mut dev := &ATADrive{
		is_master: port_index % 2 != 0
		data_port: port
		error_port: port + 1
		sector_count_port: port + 2
		lba_low_port: port + 3
		lba_mid_port: port + 4
		lba_hi_port: port + 5
		device_port: port + 6
		cmd_port: port + 7
		bar4: bar4
		bmr_command: bar4
		bmr_status: bar4 + 2
		bmr_prdt: bar4 + 4
		prdt: &PRDT(0) // To be filled later.
		prdt_phys: 0 // To be filled later.
		prdt_cache: &byte(0) // To be filled later.
	}

	// Identify the drive.
	val := if dev.is_master { 0xa0 } else { 0xb0 }
	kio.port_out<byte>(dev.device_port, byte(val))
	kio.port_out<byte>(dev.sector_count_port, 0)
	kio.port_out<byte>(dev.lba_low_port, 0)
	kio.port_out<byte>(dev.lba_mid_port, 0)
	kio.port_out<byte>(dev.lba_hi_port, 0)
	kio.port_out<byte>(dev.cmd_port, 0xec)

	if kio.port_in<byte>(dev.cmd_port) == 0 {
		print('ata: Port ${port_index} is not connected\n')
		return none
	} else {
		mut timeout := 0
		for kio.port_in<byte>(dev.cmd_port) & 0b10000000 != 0 {
			if timeout == 100000 {
				print('ata: Port ${port_index} is not answering\n')
				return none
			}
			timeout += 1
		}
	}

	// Check for non-standard ATAPI.
	if kio.port_in<byte>(dev.lba_mid_port) != 0 || kio.port_in<byte>(dev.lba_hi_port) != 0 {
		print("ata: Port ${port_index} is non-standard ATAPI\n")
		return none
	}

	mut timeout := 0
	for {
		status := kio.port_in<byte>(dev.cmd_port)
		if status & 0b00000001 != 0 {
			print("ata: Port ${port_index} errored out\n")
			return none
		}
		if status & 0b00001000 != 0 {
			break
		}
		if timeout == 100000 {
			print("ata: Port ${port_index} hanged\n")
			return none
		}
	}

	// Storing identify info.
	mut identify := [256]u16{}
	for i in 0 .. identify.len {
		identify[i] = kio.port_in<u16>(dev.data_port)
	}

	// Wacky PCI things
	mut cmd_register := pci_device.read<u32>(0x4)
	if cmd_register & (1 << 2) == 0 {
		cmd_register |= 1 << 2
		pci_device.write(0x4, cmd_register)
	}

	// Final touches to the dev structure and return.
	dev.stat.blocks = unsafe { (&u64(u64(&identify[100])))[0] }
	dev.stat.blksize = 512
	dev.stat.size = dev.stat.blocks * dev.stat.blksize
	dev.stat.rdev = resource.create_dev_id()
	dev.stat.mode = 0o644 | stat.ifblk
	dev.prdt_phys = u32(u64(memory.pmm_alloc(1, 4096)))
	dev.prdt = &PRDT(dev.prdt_phys + higher_half)
	dev.prdt.buffer_phys = u32(u64(memory.pmm_alloc(lib.div_roundup<u64>(ata_bytes_per_prdt, page_size), 4096)))
	dev.prdt.transfer_size = ata_bytes_per_prdt
	dev.prdt.mark_end = 0x8000
	dev.prdt_cache = &byte(u64(dev.prdt.buffer_phys) + higher_half)
	return dev
}

fn (mut dev ATADrive) read(handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	// Check alignment to the sector boundary.
	if loc % ata_bytes_per_sector != 0 || count % ata_bytes_per_sector != 0 {
		errno.set(errno.eio)
		return none
	}

	// Actually read.
	sector_start := loc / ata_bytes_per_sector
	sector_count := count / ata_bytes_per_sector

	dev.l.acquire()
	defer {
		dev.l.release()
	}

	for i := u64(0); i < sector_count; i += ata_sectors_per_prdt {
		sector_loc := sector_start + i
		kio.port_out<byte>(dev.bmr_command, 0)
		kio.port_out<u32>(dev.bmr_prdt, dev.prdt_phys)
		bmr_status := kio.port_in<byte>(dev.bmr_status)
		kio.port_out<byte>(dev.bmr_status, bmr_status | 0x4 | 0x2)

		val := if dev.is_master { 0x40 } else { 0x50 }
		kio.port_out<byte>(dev.device_port, byte(val))

		actual_count := if i + ata_sectors_per_prdt > sector_count {
			sector_count % ata_sectors_per_prdt
		} else {
			ata_sectors_per_prdt
		}

		kio.port_out<byte>(dev.sector_count_port, byte(actual_count >> 8))
		kio.port_out<byte>(dev.lba_low_port, byte((sector_loc & 0x000000FF000000) >> 24))
		kio.port_out<byte>(dev.lba_mid_port, byte((sector_loc & 0x0000FF00000000) >> 32))
		kio.port_out<byte>(dev.lba_hi_port, byte((sector_loc & 0x00FF0000000000) >> 40))
		kio.port_out<byte>(dev.sector_count_port, byte(actual_count & 0xff))
		kio.port_out<byte>(dev.lba_low_port, byte(sector_loc & 0x000000000000FF))
		kio.port_out<byte>(dev.lba_mid_port, byte((sector_loc & 0x0000000000FF00) >> 8))
		kio.port_out<byte>(dev.lba_hi_port, byte((sector_loc & 0x00000000FF0000) >> 16))

		kio.port_out<byte>(dev.cmd_port, 0x25) // READ_DMA command
		kio.port_out<byte>(dev.bmr_command, 0x8 | 0x1)

		for {
			status := kio.port_in<byte>(dev.cmd_port)
			if status & 0x80 == 0 {
				break
			}
			if status & 0x01 != 0 {
				print("ata: Error reading sector ${sector_loc} on drive")
				return none
			}
		}
		kio.port_out<byte>(dev.bmr_command, 0)

		buffer_final := voidptr(u64(buffer) + i * ata_bytes_per_sector)
		unsafe { C.memcpy(buffer_final, dev.prdt_cache, actual_count * ata_bytes_per_sector) }

	}
	return i64(count)
}

fn (mut dev ATADrive) write(handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	// Check alignment to the sector boundary.
	if loc % ata_bytes_per_sector != 0 || count % ata_bytes_per_sector != 0 {
		errno.set(errno.eio)
		return none
	}

	// Actually write.
	sector_start := loc / ata_bytes_per_sector
	sector_count := count / ata_bytes_per_sector

	dev.l.acquire()
	defer {
		dev.l.release()
	}

	for i := u64(0); i < sector_count; i += ata_sectors_per_prdt {
		sector_loc := sector_start + i

		kio.port_out<byte>(dev.bmr_command, 0)
		kio.port_out<u32>(dev.bmr_prdt, dev.prdt_phys)
		bmr_status := kio.port_in<byte>(dev.bmr_status)
		kio.port_out<byte>(dev.bmr_status, bmr_status | 0x4 | 0x2)

		val :=  if dev.is_master { 0x40 } else { 0x50 }
		kio.port_out<byte>(dev.device_port, byte(val))

		actual_count := if i + ata_sectors_per_prdt > sector_count {
			sector_count % ata_sectors_per_prdt
		} else {
			ata_sectors_per_prdt
		}

		// Copy buffer to DMA area.
		buffer_final := voidptr(u64(buffer) + i * ata_bytes_per_sector)
		unsafe { C.memcpy(dev.prdt_cache, buffer_final, actual_count * ata_bytes_per_sector) }

		kio.port_out<byte>(dev.sector_count_port, byte(actual_count >> 8))
		kio.port_out<byte>(dev.lba_low_port, byte((sector_loc & 0x000000FF000000) >> 24))
		kio.port_out<byte>(dev.lba_mid_port, byte((sector_loc & 0x0000FF00000000) >> 32))
		kio.port_out<byte>(dev.lba_hi_port, byte((sector_loc & 0x00FF0000000000) >> 40))
		kio.port_out<byte>(dev.sector_count_port, byte(actual_count & 0xff))
		kio.port_out<byte>(dev.lba_low_port, byte(sector_loc & 0x000000000000FF))
		kio.port_out<byte>(dev.lba_mid_port, byte((sector_loc & 0x0000000000FF00) >> 8))
		kio.port_out<byte>(dev.lba_hi_port, byte((sector_loc & 0x00000000FF0000) >> 16))

		kio.port_out<byte>(dev.cmd_port, 0x35) // WRITE_DMA command
		kio.port_out<byte>(dev.bmr_command, 0x1)

		for {
			status := kio.port_in<byte>(dev.cmd_port)
			if status & 0x80 == 0 {
				break
			}
			if status & 0x01 != 0 {
				print("ata: Error reading sector ${sector_loc} on drive")
				return none
			}
		}
		kio.port_out<byte>(dev.bmr_command, 0)

		kio.port_out<byte>(dev.device_port, byte(val))
		kio.port_out<byte>(dev.cmd_port, 0xea) // Cache flush EXT command.

		for {
			status := kio.port_in<byte>(dev.cmd_port)
			if status & 0x80 == 0 {
				break
			}
			if status & 0x01 != 0 {
				print("ata: Error reading sector ${sector_loc} on drive")
				return none
			}
		}
	}

	return i64(count)
}

fn (mut dev ATADrive) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut dev ATADrive) close(handle voidptr) ? {
	dev.l.acquire()
	dev.refcount--
	dev.l.release()
}

fn (mut dev ATADrive) grow(handle voidptr, new_size u64) ? {
	return error('')
}
