module partition

import memory
import stat
import klock
import event
import event.eventstruct
import resource
import lib
import fs

const (
	gpt_signature = 0x5452415020494645
)

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
}

[packed]
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

[packed]
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

fn (mut this Partition) unref(handle voidptr) ? {
	return this.parent_device.unref(handle)
}

fn (mut this Partition) grow(handle voidptr, new_size u64) ? {
	return this.parent_device.grow(handle, new_size)
}

fn (mut this Partition) mmap(page u64, flags int) voidptr {
	return this.parent_device.mmap(page, flags)
}

pub fn scan_partitions(mut parent_device resource.Resource, prefix string) int {
	lba_buffer := memory.malloc(parent_device.stat.blksize)

	parent_device.read(0, lba_buffer, parent_device.stat.blksize, parent_device.stat.blksize) or {
		print('block: unable to read from device\n')
		return -1
	}

	gpt_hdr := unsafe { &GPTPartitionTableHDR(lba_buffer)[0] }

	if gpt_hdr.identifier == partition.gpt_signature {
		entry_list_lba := gpt_hdr.partition_array_lba
		entry_cnt := gpt_hdr.partition_entry_cnt
		entry_list_size := lib.align_up(sizeof(GPTPartitionEntry) * entry_cnt, parent_device.stat.blksize)

		if gpt_hdr.partition_entry_size != sizeof(GPTPartitionEntry) {
			print('gpt: fatal parsing error\n')
			return -1
		}

		partition_entry_buffer := memory.malloc(entry_list_size)

		parent_device.read(0, partition_entry_buffer, entry_list_lba * parent_device.stat.blksize,
			entry_list_size) or {
			print('block: unable to read from device\n')
			return -1
		}

		partition_entry_list := &GPTPartitionEntry(partition_entry_buffer)

		for i := 0; i < entry_cnt; i++ {
			partition_entry := unsafe { &GPTPartitionEntry(&partition_entry_list[i]) }

			if partition_entry.partition_type_guid[0] == 0
				&& partition_entry.partition_type_guid[1] == 0 {
				continue
			}

			mut partition := &Partition{
				device_offset: partition_entry.starting_lba * parent_device.stat.blksize
				sector_cnt: partition_entry.last_lba - partition_entry.starting_lba
				parent_device: unsafe { parent_device }
			}

			partition.stat.blocks = partition.sector_cnt
			partition.stat.blksize = parent_device.stat.blksize
			partition.stat.size = partition.sector_cnt * partition.stat.blksize
			partition.stat.rdev = resource.create_dev_id()
			partition.stat.mode = 0o644 | stat.ifblk

			print('gpt: partition detected [start: ${partition.device_offset:x} sector cnt: $partition.sector_cnt]\n')

			fs.devtmpfs_add_device(partition, '$prefix$i')
		}

		return 0
	}

	parent_device.read(0, lba_buffer, 0, parent_device.stat.blksize) or {
		print('block: unable to read from device\n')
		return -1
	}

	mbr_signature := unsafe { &u16(lba_buffer)[255] }

	if mbr_signature == 0xaa55 {
		partitions := &MBRPartition(u64(lba_buffer) + 0x1be)

		for i := 0; i < 4; i++ {
			if unsafe { partitions[i].partition_type } == 0
				|| unsafe { partitions[i].partition_type } == 0xee {
				continue
			}

			partition_entry := unsafe { &MBRPartition(&partitions[i]) }

			mut partition := &Partition{
				device_offset: partition_entry.starting_lba * parent_device.stat.blksize
				sector_cnt: partition_entry.sector_cnt
				parent_device: unsafe { parent_device }
			}

			partition.stat.blocks = partition.sector_cnt
			partition.stat.blksize = parent_device.stat.blksize
			partition.stat.size = partition.sector_cnt * partition.stat.blksize
			partition.stat.rdev = resource.create_dev_id()
			partition.stat.mode = 0o644 | stat.ifblk

			print('mbr: partition detected [start: ${partition.device_offset:x} sector cnt: $partition.sector_cnt]\n')

			fs.devtmpfs_add_device(partition, '$prefix$i')
		}

		return 0
	}

	return -1
}
