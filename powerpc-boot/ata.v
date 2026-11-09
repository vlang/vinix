// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn discover_ata(node u32) {
	if boot_info.ata_count >= 4 || (!compatible(node, c'keylargo-ata') && !compatible(node, c'heathrow-ata')) { return }
	parent := relation(c'parent', node)
	mut reg := [4]u32{}
	mut bars := [30]u32{}
	if get_property(node, c'reg', unsafe { &reg[0] }, sizeof(reg)) < 8 || reg[1] < 0x200 { return }
	length := get_property(parent, c'assigned-addresses', unsafe { &bars[0] }, sizeof(bars))
	if length < 20 || length > int(sizeof(bars)) || length % 20 != 0 { return }
	for i := 0; i + 4 < length / 4; i += 5 {
		if bars[i] & 0x03000000 != 0x02000000 || bars[i + 1] != 0 || bars[i + 3] != 0
			|| reg[0] > bars[i + 4] || reg[1] > bars[i + 4] - reg[0]
			|| bars[i + 2] < 0x80000000 || bars[i + 2] > 0xffffffff - bars[i + 4] { continue }
		base := bars[i + 2] + reg[0]
		boot_info.ata[boot_info.ata_count] = base
		boot_info.ata_count++
		puts(c'VINIX-PPC: MacIO ATA '); hex(base); puts(c'\r\n')
		break
	}
}
