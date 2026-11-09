// SPDX-License-Identifier: GPL-2.0-or-later
// Destructive probe only for the explicitly marked 4 MiB test fixture.
module ata

import powerpc.serial

pub fn check_disposable_disk() {
	mut sector := [512]u8{}
	mut good := capacity() == 8192 && read(0, unsafe { &sector[0] })
	label := c'VINIX-PPC-ATA-TEST'
	for i in 0 .. 18 { if sector[i] != unsafe { u8(label[i]) } { good = false } }
	if good {
		good = read(8191, unsafe { &sector[0] })
		previous := sector[0]
		if previous > 1 { good = false }
		for i in 0 .. 512 { sector[i] = u8(i * 37 + int(previous) + 1) }
		if good { good = write(8191, unsafe { &sector[0] }) && flush() && read(8191, unsafe { &sector[0] }) }
		for i in 0 .. 512 { if sector[i] != u8(i * 37 + int(previous) + 1) { good = false } }
		if read(8192, unsafe { &sector[0] }) || write(8192, unsafe { &sector[0] }) { good = false }
	}
	serial.text(if good { c'VINIX-PPC: PASS ATA read write flush bounds\n' } else { c'VINIX-PPC: FAIL ATA disk fixture\n' })
}
