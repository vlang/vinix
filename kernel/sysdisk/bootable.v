// SPDX-License-Identifier: GPL-2.0-or-later
module sysdisk

import block.partition
import fs
import fs.ext2
import initramfs
import krandom
import limine
import memory
import pagecache
import resource
import stat
import sysdisk.disklayout as layout

const transfer_bytes = u64(1024 * 1024)

fn install_bootable() Outcome {
	image := initramfs.image_id()
	if image.len == 0 {
		panic('sysdisk: the installation media has no system image ID')
	}
	defer { unsafe { image.free() } }

	disks := whole_disks()
	defer { unsafe { disks.free() } }
	table := table_buffer()
	defer { memory.free(table) }
	mut selected := &fs.VFSNode(unsafe { nil })
	mut id := layout.Identity{}
	for disk in disks {
		if !supported_disk(disk) {
			continue
		}
		mut candidate := unsafe { disk.resource }
		if resource.backend_is_read_only(mut candidate) {
			continue
		}
		mut candidate_id := layout.Identity{}
		if previous := read_installation(disk, table, false) {
			if !previous.pending {
				continue
			}
			candidate_id = previous.id
		} else if !blank(disk) || !blank_interior(disk) {
			continue
		}
		if selected != unsafe { nil } {
			panic('sysdisk: more than one installation target; connect only one empty or unfinished disk')
		}
		selected = disk
		id = candidate_id
	}
	if selected == unsafe { nil } {
		panic('sysdisk: connect an empty writable disk of at least 4 GiB with 512-byte sectors, or restart and choose Try Vinix')
	}

	if id.disk.matches(layout.Guid{}) {
		id = new_identity()
	}
	report('sysdisk: installing onto', selected, '')
	if !prepare_boot(selected, table, id) {
		panic('sysdisk: could not install the boot files; restart from the ISO to retry')
	}
	device := root_device(selected) or { panic('sysdisk: could not open the system partition') }
	if !ext2.format(device, 'vinix') {
		panic('sysdisk: could not format the system partition; restart from the ISO to retry')
	}
	mut root := open_root(device) or { panic('sysdisk: could not mount the new system partition') }
	if !fs.install_empty_disk_root(mut root) {
		panic('sysdisk: could not prepare the new root; restart from the ISO to retry')
	}
	initramfs.install('')
	init := fs.get_node(root, '/sbin/init', true) or { panic('sysdisk: the installed system has no init') }
	if !stat.isreg(init.resource.stat.mode) || init.resource.stat.mode & 0o111 == 0
		|| init.resource.stat.size <= 0 || !pagecache.sync_all() || !write_id(image)
		|| !pagecache.sync_all() || !write_layout(selected, table, id, false) {
		panic('sysdisk: the installation could not be committed; restart from the ISO to retry')
	}
	println('sysdisk: installed; remove the ISO or USB before the next boot')
	return .installed
}

fn mount_bootable() Outcome {
	// Limine loaded the kernel from the EFI partition. Use its GPT identities
	// instead of device enumeration order, which can change between boots.
	file := limine.kernel_file()
	if file == unsafe { nil } {
		panic('sysdisk: Limine did not identify the boot disk')
	}
	disk_id := guid_from_limine(&file.gpt_disk_uuid)
	esp_id := guid_from_limine(&file.gpt_part_uuid)
	disks := whole_disks()
	defer { unsafe { disks.free() } }
	table := table_buffer()
	defer { memory.free(table) }
	mut selected := &fs.VFSNode(unsafe { nil })
	for disk in disks {
		if !supported_disk(disk) {
			continue
		}
		found := read_installation(disk, table, true) or { continue }
		if !found.id.disk.matches(disk_id) || !found.id.esp.matches(esp_id) {
			continue
		}
		if found.pending {
			panic('sysdisk: installation unfinished; boot the ISO and choose Install Vinix again')
		}
		if selected != unsafe { nil } {
			panic('sysdisk: multiple disks have the boot disk identity')
		}
		selected = disk
	}
	if selected == unsafe { nil } {
		panic('sysdisk: could not find the Vinix boot disk')
	}
	device := root_device(selected) or { panic('sysdisk: could not open the installed system partition') }
	mut root := open_root(device) or { panic('sysdisk: could not mount the installed system partition') }
	if !fs.install_disk_root(mut root) {
		panic('sysdisk: could not start the installed system')
	}
	report('sysdisk: running from the system on', selected, '')
	return .booted
}

fn supported_disk(disk &fs.VFSNode) bool {
	return u64(disk.resource.stat.blksize) == layout.sector_bytes
		&& u64(disk.resource.stat.size) >= layout.min_disk_bytes
		&& u64(disk.resource.stat.size) % layout.sector_bytes == 0
}

fn blank_interior(disk &fs.VFSNode) bool {
	report('sysdisk: checking for data on', disk, '')
	buffer := memory.malloc(transfer_bytes)
	if buffer == unsafe { nil } {
		return false
	}
	defer { memory.free(buffer) }
	end := u64(disk.resource.stat.size) - transfer_bytes
	words := unsafe { &u64(buffer) }
	for offset := transfer_bytes; offset < end; offset += transfer_bytes {
		length := if end - offset < transfer_bytes { end - offset } else { transfer_bytes }
		if !read_disk(disk, buffer, offset, length) {
			return false
		}
		for i in 0 .. length / 8 {
			if unsafe { words[i] } != 0 {
				return false
			}
		}
	}
	return true
}

fn prepare_boot(disk &fs.VFSNode, table &layout.Table, id layout.Identity) bool {
	image := initramfs.disk_boot_archive(layout.root_start * layout.sector_bytes) or { return false }
	defer { image.release() }
	if !write_layout(disk, table, id, true) {
		return false
	}
	// Leave both GPT copies alone. The template contains the BIOS boot code
	// and a FAT EFI partition with Limine and the kernel. Their LBAs are fixed.
	for offset := layout.bios_start * layout.sector_bytes; offset < image.size; offset += transfer_bytes {
		if !write_disk(disk, voidptr(u64(image.address) + offset), offset, transfer_bytes) {
			return false
		}
	}
	mut mbr := layout.protective_mbr(disk_sectors(disk))
	unsafe { C.memcpy(&mbr[0], image.address, 440) }
	return write_disk(disk, &mbr[0], 0, layout.sector_bytes) && flush_disk(disk)
}

fn root_device(disk &fs.VFSNode) ?&fs.VFSNode {
	return partition.ensure_device(disk, layout.root_index, layout.root_start,
		layout.root_end(disk_sectors(disk)) - layout.root_start)
}

fn open_root(device &fs.VFSNode) ?&fs.VFSNode {
	mut filesystem, ok := ext2.ext2_init(device)
	if !ok {
		return none
	}
	return ext2.ext2_root(mut filesystem)
}

fn table_buffer() &layout.Table {
	table := memory.calloc(sizeof(layout.Table), 1)
	if table == unsafe { nil } {
		panic('sysdisk: could not allocate a partition table buffer')
	}
	return unsafe { &layout.Table(table) }
}

fn read_installation(disk &fs.VFSNode, table &layout.Table, allow_backup bool) ?layout.Installation {
	primary := read_layout(disk, table, false) or {
		// An old backup can survive repartitioning. Require a matching
		// primary table before authorising writes to an unfinished disk.
		if allow_backup {
			return read_layout(disk, table, true)
		}
		return none
	}
	if primary.pending {
		// A reset between committing the backup and primary can leave the
		// backup alone complete. Both describe the same system partition.
		if backup := read_layout(disk, table, true) {
			if !backup.pending && backup.id.disk.matches(primary.id.disk)
				&& backup.id.esp.matches(primary.id.esp) && backup.id.root.matches(primary.id.root) {
				return backup
			}
		}
	}
	return primary
}

fn read_layout(disk &fs.VFSNode, table &layout.Table, backup bool) ?layout.Installation {
	sectors := disk_sectors(disk)
	mut header := layout.Header{}
	if !read_disk(disk, &header, layout.header_lba(sectors, backup) * layout.sector_bytes,
		layout.sector_bytes)
		|| !read_disk(disk, table, layout.table_lba(sectors, backup) * layout.sector_bytes,
			sizeof(layout.Table)) {
		return none
	}
	return layout.inspect(header, table, sectors, backup)
}

fn write_layout(disk &fs.VFSNode, table &layout.Table, id layout.Identity, pending bool) bool {
	sectors := disk_sectors(disk)
	unsafe { C.memset(table, 0, sizeof(layout.Table)) }
	layout.entries(table, sectors, id, pending)
	// Publish ownership first on a blank disk. At commit time preserve the
	// pending primary until the completed backup is durable.
	for backup in [!pending, pending]! {
		header := layout.header(table, sectors, id.disk, backup)
		if !write_disk(disk, table, layout.table_lba(sectors, backup) * layout.sector_bytes,
			sizeof(layout.Table))
			|| !write_disk(disk, &header, layout.header_lba(sectors, backup) * layout.sector_bytes,
				layout.sector_bytes) || !flush_disk(disk) {
			return false
		}
	}
	return true
}

fn disk_sectors(disk &fs.VFSNode) u64 {
	return u64(disk.resource.stat.size) / layout.sector_bytes
}

fn read_disk(disk &fs.VFSNode, buffer voidptr, offset u64, length u64) bool {
	mut device := unsafe { disk.resource }
	read := device.read(unsafe { nil }, buffer, offset, length) or { return false }
	return u64(read) == length
}

fn write_disk(disk &fs.VFSNode, buffer voidptr, offset u64, length u64) bool {
	mut device := unsafe { disk.resource }
	written := device.write(unsafe { nil }, buffer, offset, length) or { return false }
	return u64(written) == length
}

fn flush_disk(disk &fs.VFSNode) bool {
	mut device := unsafe { disk.resource }
	resource.sync_resource(mut device, unsafe { nil }) or { return false }
	return true
}

fn new_identity() layout.Identity {
	krandom.initialise()
	return layout.Identity{ disk: new_guid(), bios: new_guid(), esp: new_guid(), root: new_guid() }
}

fn new_guid() layout.Guid {
	mut guid := layout.Guid{}
	if !krandom.fill(&guid, sizeof(layout.Guid), true) {
		panic('sysdisk: could not generate a disk identity')
	}
	guid.low = (guid.low & u64(0x0fffffffffffffff)) | u64(0x4000000000000000)
	guid.high = (guid.high & u64(0xffffffffffffff3f)) | u64(0x80)
	return guid
}

fn guid_from_limine(uuid &limine.LimineUUID) layout.Guid {
	mut guid := layout.Guid{}
	unsafe { C.memcpy(&guid, uuid, sizeof(layout.Guid)) }
	return guid
}
