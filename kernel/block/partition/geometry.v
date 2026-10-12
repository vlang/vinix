// SPDX-License-Identifier: GPL-2.0-or-later
module partition

// GPT's last LBA is inclusive. Dropping its final sector makes a filesystem
// which fills its partition appear larger than the exposed block device.
fn gpt_sector_count(first u64, last u64, disk_sectors u64) ?u64 {
	if first > last || last >= disk_sectors { return none }
	return last - first + 1
}
