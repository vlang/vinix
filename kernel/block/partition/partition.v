module partition

import memory
import stat
import klock
import event.eventstruct
import resource
import lib
import fs
import errno

const gpt_signature = u64(0x5452415020494645)

// The scan reads the entry array into one buffer before parsing it, so what
// the header claims is capped: the UEFI minimum table is 128 entries of 128
// bytes, and a table past this bound is malformed whatever the disk size.
const gpt_max_table_bytes = u64(1024 * 1024)

// LBA 0 holds the protective MBR and LBA 1 the header, so a primary entry
// array starts at LBA 2 at the earliest.
const gpt_min_table_lba = u64(2)

struct Partition {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	parent_device &resource.Resource
	device_offset u64
	sector_cnt    u64
	identity resource.BlockIdentity
}

@[packed]
struct MBRPartition {
pub mut:
	drive_status   u8
	starting_chs   [3]u8
	partition_type u8
	ending_chs     [3]u8
	starting_lba   u32
	sector_cnt     u32
}

struct GPTPartitionEntry {
pub mut:
	partition_type_guid [2]u64
	partition_guid      [2]u64
	starting_lba        u64
	last_lba            u64
	flags               u64
	name                [9]u64
}

@[packed]
struct GPTPartitionTableHDR {
pub mut:
	identifier            u64
	version               u32
	hdr_size              u32
	checksum              u32
	reserved0             u32
	hdr_lba               u64
	alt_hdr_lba           u64
	first_block           u64
	last_block            u64
	guid                  [2]u64
	partition_array_lba   u64
	partition_entry_cnt   u32
	partition_entry_size  u32
	crc32_partition_array u32
}

fn (this &Partition) block_identity() resource.BlockIdentity { return this.identity }

fn (mut this Partition) read_only_backend() bool { return resource.backend_is_read_only(mut this.parent_device) }

fn (mut this Partition) block_status() resource.BlockStatus {
	mut result := resource.block_status(mut this.parent_device) or { return resource.BlockStatus{version: 0} }
	result.bytes = u64(this.stat.size)
	result.sector = u64(this.stat.blksize)
	result.disk_id = this.identity.disk_id
	result.start = this.identity.start
	result.flags |= resource.block_parent_counters
	return result
}

fn partition_identity(parent resource.BlockIdentity, offset u64, length u64) resource.BlockIdentity {
	if !parent.valid() || offset > parent.length || length > parent.length - offset {
		return resource.BlockIdentity{is_block: true}
	}
	return resource.BlockIdentity{is_block: true, disk_id: parent.disk_id, start: parent.start + offset, length: length}
}

fn (mut this Partition) write(handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if (count + loc) > (this.sector_cnt * this.parent_device.stat.blksize) {
		return none
	}

	return this.parent_device.write(handle, buffer, loc + this.device_offset, count)
}

fn (mut this Partition) read(handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if (count + loc) > (this.sector_cnt * this.parent_device.stat.blksize) {
		return none
	}

	return this.parent_device.read(handle, buffer, loc + this.device_offset, count)
}

fn (mut this Partition) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return this.parent_device.ioctl(handle, request, argp)
}

// A partition has no separate write cache. Its persistence barrier is the
// parent's, including errors from the hardware cache flush.
fn (mut this Partition) sync(handle voidptr) ? {
	resource.sync_resource(mut this.parent_device, handle)?
}

fn (mut this Partition) discard(offset u64, bytes u64) ? {
	if !resource.discard_range_valid(u64(this.stat.size), u64(this.stat.blksize), offset, bytes) {
		errno.set(errno.einval); return none
	}
	if resource.backend_is_read_only(mut this.parent_device) { errno.set(errno.erofs); return none }
	resource.discard_resource(mut this.parent_device, this.device_offset + offset, bytes)?
}

fn (mut this Partition) unref(handle voidptr) ? {
	return this.parent_device.unref(handle)
}

fn (mut this Partition) link(_handle voidptr) ? {
}

fn (mut this Partition) unlink(_handle voidptr) ? {
}

fn (mut this Partition) grow(handle voidptr, new_size u64) ? {
	return this.parent_device.grow(handle, new_size)
}

fn (mut this Partition) mmap(handle voidptr, page u64, flags int) voidptr {
	return this.parent_device.mmap(handle, page, flags)
}

// The device name of partition `index`: the device's own and the number. The
// device node keeps it as its name.
fn partition_name(prefix string, index int) string {
	mut text := lib.new_text(prefix.len + 20)
	text.add(prefix)
	text.add_decimal(i64(index))
	return text.str()
}

pub fn scan_partitions(mut parent_device resource.Resource, prefix string) int {
	parent_identity := resource.block_identity(mut parent_device)
	blksize := u64(parent_device.stat.blksize)
	if blksize < 512 || blksize > 65536 || (blksize & (blksize - 1)) != 0 {
		print('block: invalid sector size\n')
		return -1
	}
	lba_buffer := memory.malloc(blksize)

	parent_device.read(0, lba_buffer, blksize, blksize) or {
		print('block: unable to read from device\n')
		return -1
	}

	gpt_hdr := unsafe { *&GPTPartitionTableHDR(lba_buffer) }

	if gpt_hdr.identifier == gpt_signature {
		// Every field below comes from the disk, and memory.malloc is
		// infallible: an allocation sized from an unvalidated header
		// turns a malformed disk into a kernel panic instead of an
		// unpartitioned device. Validate everything before allocating.
		disk_sectors := u64(parent_device.stat.size) / blksize

		entry_size := u64(gpt_hdr.partition_entry_size)
		// UEFI requires SizeOfPartitionEntry to be 128 * 2^n.
		if entry_size < u64(sizeof(GPTPartitionEntry)) || (entry_size & (entry_size - 1)) != 0 {
			print('gpt: invalid partition entry size\n')
			return -1
		}
		entry_cnt := u64(gpt_hdr.partition_entry_cnt)
		if entry_cnt == 0 {
			print('gpt: invalid partition entry count\n')
			return -1
		}
		// Both fields are 32-bit, so their product cannot wrap; refuse
		// any table beyond a small absolute bound whatever it claims.
		table_bytes := entry_cnt * entry_size
		if table_bytes > gpt_max_table_bytes {
			print('gpt: partition table too large\n')
			return -1
		}
		table_sectors := (table_bytes + blksize - 1) / blksize
		entry_list_lba := gpt_hdr.partition_array_lba
		// The array must sit between the header and the header's first
		// usable block, and inside the disk. Once these bounds hold the
		// subtractions cannot wrap, and neither can the byte offsets
		// computed from them below.
		if gpt_hdr.first_block < gpt_min_table_lba || gpt_hdr.first_block > disk_sectors
			|| entry_list_lba < gpt_min_table_lba || entry_list_lba >= gpt_hdr.first_block
			|| table_sectors > gpt_hdr.first_block - entry_list_lba {
			print('gpt: partition table extent out of range\n')
			return -1
		}

		entry_list_size := table_sectors * blksize
		partition_entry_buffer := memory.malloc(entry_list_size)

		parent_device.read(0, partition_entry_buffer, entry_list_lba * blksize, entry_list_size) or {
			print('block: unable to read from device\n')
			return -1
		}

		partition_entry_list := unsafe { &GPTPartitionEntry(partition_entry_buffer) }

		for i := 0; u64(i) < entry_cnt; i++ {
			// Entries may be spaced wider than the parsed 128 bytes.
			partition_entry := unsafe {
				&GPTPartitionEntry(u64(partition_entry_list) + u64(i) * entry_size)
			}

			if partition_entry.partition_type_guid[0] == 0
				&& partition_entry.partition_type_guid[1] == 0 {
				continue
			}
			sectors := gpt_sector_count(partition_entry.starting_lba, partition_entry.last_lba,
				u64(parent_device.stat.size) / u64(parent_device.stat.blksize)) or { continue }

			mut partition := &Partition{
				device_offset: u64(partition_entry.starting_lba * parent_device.stat.blksize)
				sector_cnt:    sectors
				parent_device: unsafe { parent_device }
			}

			partition.stat.blocks = partition.sector_cnt
			partition.stat.blksize = parent_device.stat.blksize
			partition.stat.size = partition.sector_cnt * partition.stat.blksize
			partition.identity = partition_identity(parent_identity, partition.device_offset,
				u64(partition.stat.size))
			partition.stat.rdev = resource.create_dev_id()
			partition.stat.mode = 0o600 | stat.ifblk

			C.kprintf(c'gpt: partition detected [start: %llx sector cnt: %llu]\n',
				u64(partition.device_offset), u64(partition.sector_cnt))

			fs.devtmpfs_add_device(partition, partition_name(prefix, i))
		}

		return 0
	}

	parent_device.read(0, lba_buffer, 0, u64(parent_device.stat.blksize)) or {
		print('block: unable to read from device\n')
		return -1
	}

	mbr_signature := unsafe { &u16(lba_buffer)[255] }

	if mbr_signature == 0xaa55 {
		partitions := unsafe { &MBRPartition(u64(lba_buffer) + 0x1be) }

		for i := 0; i < 4; i++ {
			if unsafe { partitions[i].partition_type } == 0
				|| unsafe { partitions[i].partition_type } == 0xee {
				continue
			}

			partition_entry := unsafe { &MBRPartition(&partitions[i]) }

			mut partition := &Partition{
				device_offset: u64(partition_entry.starting_lba * parent_device.stat.blksize)
				sector_cnt:    partition_entry.sector_cnt
				parent_device: unsafe { parent_device }
			}

			partition.stat.blocks = partition.sector_cnt
			partition.stat.blksize = parent_device.stat.blksize
			partition.stat.size = partition.sector_cnt * partition.stat.blksize
			partition.identity = partition_identity(parent_identity, partition.device_offset,
				u64(partition.stat.size))
			partition.stat.rdev = resource.create_dev_id()
			partition.stat.mode = 0o600 | stat.ifblk

			C.kprintf(c'mbr: partition detected [start: %llx sector cnt: %llu]\n',
				u64(partition.device_offset), u64(partition.sector_cnt))

			fs.devtmpfs_add_device(partition, partition_name(prefix, i))
		}

		return 0
	}

	return -1
}
