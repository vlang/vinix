// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module ahci

__global (
	calls int
	supported bool
	enabled bool
	support_valid bool
	enabled_valid bool
	broken_checksum bool
	short_call int
	fail_call int
	status_mid u8
	status_high u8
	status_type u8
	status_bits u8
)

fn (mut d AHCIDevice) wait_awake() {}

// Deterministic transport boundary. Descriptor/FIS setup and report parsing
// stay production code; no disk/controller is attached to these host tests.
fn (mut d AHCIDevice) send_cmd(_ u32) bool {
	calls++
	header := unsafe { &AHCIHBACommand(u64(d.regs.clb) | (u64(d.regs.clbu) << 32)) }
	table := unsafe { &AHCIHBACommandTable(u64(header.ctba) | (u64(header.ctbau) << 32)) }
	fis := unsafe { &AHCIFISh2d(&table.cfis) }
	response := unsafe { &AHCIFISd2h(d.fis_base + 0x40) }
	assert fis.fis_type == 0x27 && fis.flags == 0x80 && fis.device == 0
	assert fis.lba0 == 0 && fis.lba3 == 0 && fis.lba4 == 0 && fis.lba5 == 0
	assert fis.featureh == 0 && fis.counth == 0 && header.flags == 5 && header.prdbc == 0
	assert response.fis_type == 0 // old completion cleared before every command
	if calls == fail_call { d.failed=true; return false }
	if calls < 3 {
		assert header.prdtl == 1 && table.prdt[0].dbc == 511
		assert u64(table.prdt[0].dba) | (u64(table.prdt[0].dbau) << 32) == u64(d.bounce)
		unsafe { header.prdbc = if calls == short_call { u32(256) } else { u32(512) } }
		bytes := &u8(d.bounce)
		unsafe {
			for i in 0 .. 512 { assert bytes[i] == 0 }
			if calls == 1 {
				assert fis.command == 0xec && fis.featurel == 0 && fis.lba1 == 0 && fis.lba2 == 0 && fis.countl == 0
				bytes[166+1]=if support_valid { u8(0x40) } else { u8(0xc0) }
				bytes[174+1]=if enabled_valid { u8(0x40) } else { u8(0xc0) }
				bytes[164]=if supported { u8(1) } else { u8(0) }
				bytes[170]=if enabled { u8(1) } else { u8(0) }
				bytes[20]=0x42
			} else {
				assert fis.command == 0xb0 && fis.featurel == 0xd0 && fis.countl == 1
				assert fis.lba1 == 0x4f && fis.lba2 == 0xc2
				bytes[0]=1; bytes[2]=190; bytes[3]=3; bytes[5]=69; bytes[6]=68; bytes[7]=31
				mut sum:=u32(0); for i in 0 .. 511 { sum+=bytes[i] }
				bytes[511]=u8((256-(sum & 255)) & 255)
				if broken_checksum { bytes[509]^=1 }
			}
		}
	} else {
		assert calls == 3 && header.prdtl == 0
		assert fis.command == 0xb0 && fis.featurel == 0xda && fis.countl == 0
		assert fis.lba1 == 0x4f && fis.lba2 == 0xc2
		unsafe { *response=AHCIFISd2h{fis_type:status_type,status:status_bits,lba1:status_mid,lba2:status_high} }
	}
	return true
}
