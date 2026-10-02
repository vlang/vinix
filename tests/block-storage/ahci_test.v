module ahci

import x86.hpet as hpet_clock

fn setup(flush u8) &AHCIDevice {
	mut header := unsafe { &AHCIHBACommand(calloc(1, sizeof(AHCIHBACommand))) }
	table := u64(unsafe { calloc(1, sizeof(AHCIHBACommandTable)) })
	header.ctba = u32(table)
	header.ctbau = u32(table >> 32)
	list := u64(header)
	hpet_clock.set_hook(fn () {})
	return &AHCIDevice{
		regs:              &AHCIPortRegisters{ clb: u32(list), clbu: u32(list >> 32) }
		parent_controller: &AHCIController{ regs: unsafe { nil }, cmd_slots: 1 }
		flush_command:     flush
	}
}

fn test_flush_programs_nondata_command_and_returns_hardware_failure() {
	for opcode in [u8(0xe7), u8(0xea)] {
		mut device := setup(opcode)
		mut failed := false
		// RAM cannot emulate write-one-to-clear PxIS: its all-ones clear write
		// appears as a hardware error. Verify that this error is propagated,
		// and inspect the actual flush command programmed before submission.
		device.sync(unsafe { nil }) or { failed = true }
		assert failed
		header := unsafe { &AHCIHBACommand(u64(device.regs.clb) | (u64(device.regs.clbu) << 32)) }
		table := unsafe { &AHCIHBACommandTable(u64(header.ctba) | (u64(header.ctbau) << 32)) }
		fis := unsafe { &AHCIFISh2d(&table.cfis) }
		assert header.flags == sizeof(AHCIFISh2d) / 4
		assert header.prdtl == 0
		assert header.prdbc == 0
		assert fis.command == opcode
		assert fis.fis_type == fis_reg_h2d
		assert fis.flags == 1 << 7
		assert fis.countl == 0
		assert fis.counth == 0
		assert device.failed
		assert device.regs.cmd & hba_cmd_st == 0
	}
}

fn test_busy_port_times_out_and_cannot_reuse_command_tables() {
	mut device := setup(0xea)
	device.regs.tfd = 0x80
	assert !device.send_cmd(0)
	assert device.failed
	assert device.regs.ci == 0
	assert device.find_cmd_slot() == none
	mut failed := false
	device.sync(unsafe { nil }) or { failed = true }
	assert failed
	assert device.regs.ci == 0
}

fn test_unsupported_flush_refuses_persistence() {
	mut device := setup(0)
	mut failed := false
	device.sync(unsafe { nil }) or { failed = true }
	assert failed
	assert device.regs.ci == 0
}
