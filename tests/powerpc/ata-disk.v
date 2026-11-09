// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os

fn run(args []string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..]); p.wait()
	code := p.code; p.close()
	if code != 0 { return error('command failed: ' + args.join(' ')) }
}

fn test_disk(output string) ! {
	if os.exists(output) { return error('Use a fresh output directory') }
	os.mkdir_all(output)!
	disk := output + '/ata-test.raw'
	mut data := []u8{len: 4 * 1024 * 1024}
	label := 'VINIX-PPC-ATA-TEST'
	copy(mut data[..label.len], label.bytes())
	os.write_file_array(disk, data)!
	os.setenv('VINIX_PPC_DISK', disk, true)
	os.setenv('VINIX_PPC_TEST_ATA', '1', true)
	for attempt in 1 .. 3 {
		run(['v', 'run', 'tools/powerpc', 'test-kernel', output + '/boot-${attempt}'])!
		log := os.read_file(output + '/boot-${attempt}/kernel-boot.log')!
		if !log.contains('VINIX-PPC: PASS ATA read write flush bounds') { return error('ATA probe did not pass') }
		after := os.read_bytes(disk)!
		for i in 0 .. data.len - 512 { if after[i] != data[i] { return error('ATA wrote outside its test sector') } }
		for i in 0 .. 512 { if after[data.len - 512 + i] != u8(i * 37 + attempt) { return error('Sector did not survive QEMU exit') } }
	}
	os.cp(@FILE, output + '/ata-disk.v')!
	os.write_file(output + '/SHA256SUMS', sha256.hexhash(os.read_bytes(disk)!.bytestr()) + '  ata-test.raw\n'
		+ sha256.hexhash(os.read_bytes(@FILE)!.bytestr()) + '  ata-disk.v\n')!
	println('PASS native ATA: write/flush/read, bounds, reboot persistence and untouched neighbours')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: v run tests/powerpc/ata-disk.v FRESH_OUTPUT'); exit(2) }
	test_disk(os.abs_path(os.args[1])) or { eprintln(err); exit(1) }
}
