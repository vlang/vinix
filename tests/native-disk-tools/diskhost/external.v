// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import hash.crc32
import os

fn external_gpt(path string) ! {
	total := u64(66 * 1024 * 1024 / 512)
	last := total - 1
	mut entries := []u8{len: 128 * 128}
	put(mut entries, 0, 0x477284830fc63daf, 8)
	put(mut entries, 8, 0xe47d47d8693d798e, 8)
	put(mut entries, 16, 0x1122334455667788, 8)
	put(mut entries, 24, 0x8877665544332211, 8)
	put(mut entries, 32, 2048, 8)
	put(mut entries, 40, 2048 + 64 * 1024 * 1024 / 512 - 1, 8)
	mut header := []u8{len: 512}
	put(mut header, 0, 0x5452415020494645, 8)
	put(mut header, 8, 0x10000, 4)
	put(mut header, 12, 92, 4)
	put(mut header, 24, 1, 8)
	put(mut header, 32, last, 8)
	put(mut header, 40, 34, 8)
	put(mut header, 48, last - 33, 8)
	put(mut header, 56, 0x1234567812345678, 8)
	put(mut header, 64, 0x8765432187654321, 8)
	put(mut header, 72, 2, 8)
	put(mut header, 80, 128, 4)
	put(mut header, 84, 128, 4)
	put(mut header, 88, u64(crc32.sum(entries)), 4)
	put(mut header, 16, u64(crc32.sum(header[..92])), 4)
	mut file := os.open_file(path, 'r+')!
	defer { file.close() }
	mut protective := mbr(1, u32(last))
	protective[450] = 0xee
	file.write_to(0, protective)!
	file.write_to(512, header)!
	file.write_to(1024, entries)!
	file.write_to((last - 32) * 512, entries)!
	put(mut header, 24, last, 8)
	put(mut header, 32, 1, 8)
	put(mut header, 72, last - 32, 8)
	put(mut header, 16, 0, 4)
	put(mut header, 16, u64(crc32.sum(header[..92])), 4)
	file.write_to(last * 512, header)!
}

fn external(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
	], 'Usage: run-guest [--arch aarch64|amd64] [--state-dir FRESH-DIR] --kernel-dir DIR')!
	arch := options.value('--arch', 'amd64')
	work := work_dir(options, 'vinix-external-mount-')!
	defer { remove_private(work, options) }
	kernel_dir := kernel(work, options.value('--kernel-dir', ''), arch)!
	executable := tool()!
	link := flags(arch)
	fixture := work + '/fixture.o'
	guesthost.compile_module(root() + '/tests/ext-mount/guest', fixture,
		if arch == 'amd64' { 'x86_64' } else { 'aarch64' }, link)!
	run([...link, fixture, '-o', work + '/init'])!
	seed := work + '/seed'
	mkdir(seed)!
	os.write_file(seed + '/marker', 'external Linux volume\n')!
	mut fragmented := os.create(seed + '/fragmented')!
	for i in 0 .. 9 { fragmented.write_to(u64(i * 8192), []u8{len: 4096, init: u8(i + 1)})! }
	fragmented.close()
	os.symlink('marker', seed + '/short-link')!
	os.symlink('this/is/a/long/symlink/target/with/more/than/sixty/bytes/to/exercise/extents', seed + '/long-link')!
	for kind in ['ext2', 'ext4'] {
		image := work + '/' + kind + '.img'
		sparse_file(image, 64 * 1024 * 1024)!
		run([os.dir(executable) + '/mke2fs', '-q', '-F', '-t', kind, '-b', '4096', '-d', seed,
			image])!
		disk := work + '/' + kind + '.raw'
		sparse_file(disk, 66 * 1024 * 1024)!
		if kind == 'ext4' {
			external_gpt(disk)!
		} else {
			write_mbr(disk, 2048, 64 * 1024 * 1024 / 512)!
		}
		mut file := os.open_file(disk, 'r+')!
		file.write_to(1024 * 1024, os.read_bytes(image)!)!
		file.close()
	}
	// Retainable geometry with an invalid root exercises a failure after the
	// filesystem cache is registered. Use ext2 so no metadata checksum needs
	// repairing when changing the root's on-disk mode to a regular file.
	mut bad := os.read_bytes(work + '/ext2.img')!
	inode_table := u64(bad[4104]) | (u64(bad[4105]) << 8) | (u64(bad[4106]) << 16) | (u64(bad[4107]) << 24)
	inode_size := u64(bad[1112]) | (u64(bad[1113]) << 8)
	put(mut bad, int(inode_table * 4096 + inode_size), 0x8180, 2)
	os.write_file_array(work + '/badroot.img', bad)!
	sparse_file(work + '/badroot.raw', 66 * 1024 * 1024)!
	write_mbr(work + '/badroot.raw', 2048, 64 * 1024 * 1024 / 512)!
	mut bad_disk := os.open_file(work + '/badroot.raw', 'r+')!
	bad_disk.write_to(1024 * 1024, bad)!
	bad_disk.close()
	suffix := if arch == 'amd64' { '.raw' } else { '.img' }
	ext4_before := hosttest.sha(work + '/ext4' + suffix)!
	archive := guesthost.image(work + '/init', work)!
	configured := guesthost.launch(work + '/init', archive, work, kernel_dir,
		if arch == 'amd64' { 'x86_64' } else { 'aarch64' }, true)!
	mut argv := configured.command.clone()
	for kind in if arch == 'amd64' {
		['ext2', 'ext4', 'badroot']
	} else {
		['badroot', 'ext4', 'ext2']
	} {
		argv << ['-drive', 'if=none,format=raw,file=' + work + '/' + kind + suffix + ',id=' + kind,
			'-device', if arch == 'amd64' {
				'ide-hd,drive=' + kind + ',bus=ide.' + match kind {
					'ext2' { '0' }
					'ext4' { '1' }
					else { '3' }
				}
			} else {
				'virtio-blk-device,drive=' + kind
			}]
	}
	result := guesthost.boot_from(argv, configured.env, work,
		['EXT MOUNT START', 'EXT MOUNT PASS'], ['EXT MOUNT FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'],
		timeout()!, true, '')!
	if result != 0 { return result }
	if hosttest.sha(work + '/ext4' + suffix)! != ext4_before {
		return error('Read-only ext4 volume changed')
	}
	// Extract the partition after unmount, check Linux can read the ext2 write,
	// and let e2fsck independently validate all metadata touched by Vinix.
	disk := os.read_bytes(work + '/ext2' + suffix)!
	start := if arch == 'amd64' { 1024 * 1024 } else { 0 }
	os.write_file_array(work + '/ext2-after.img', disk[start..start + 64 * 1024 * 1024])!
	run([os.dir(executable) + '/e2fsck', '-f', '-n', work + '/ext2-after.img'])!
	run([executable, '-R', 'dump /marker ' + work + '/marker', work + '/ext2-after.img'])!
	if os.read_file(work + '/marker')! != 'EXT2 write persisted!\n' {
		return error('ext2 write did not persist')
	}
	println('PASS ' + arch + ': external partition mounts, ext2 persistence, ext4 reads and write denial; ext4 disk unchanged')
	return 0
}
