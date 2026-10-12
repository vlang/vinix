// SPDX-License-Identifier: GPL-2.0-or-later
// The production startup.v runs against a controller with switchable power,
// write-one-to-clear status and optional delayed firmware handoff. QEMU's
// permanently powered root ports cannot exercise the power-off boot case.
@[has_globals]
module xhci

struct Write {
	addr  u64
	value u32
}

__global (
	xhci_cap              u64
	xhci_ports            u32
	registers             [16384]u32
	writes                []Write
	clock_ns              u64
	firmware_release_ns   u64
	legacy_reg            u64
	connected_after_power bool
)

fn reset_fixture() {
	xhci_cap = 0x100000
	xhci_ports = 3
	registers = [16384]u32{}
	writes = []Write{}
	clock_ns = 0
	firmware_release_ns = 0
	legacy_reg = 0
	connected_after_power = false
}

fn port_register(port u32) u64 {
	return xhci_cap + 0x1000 + u64(port - 1) * 16
}

fn reg_index(addr u64) int {
	assert addr >= xhci_cap && addr < xhci_cap + 0x10000
	assert addr & 3 == 0
	return int((addr - xhci_cap) / 4)
}

fn rd(addr u64) u32 {
	i := reg_index(addr)
	if addr == legacy_reg && firmware_release_ns != 0 && clock_ns >= firmware_release_ns {
		registers[i] &= ~(u32(1) << 16)
	}
	return registers[i]
}

fn wr(addr u64, value u32) {
	i := reg_index(addr)
	writes << Write{addr, value}
	if addr >= port_register(1) && addr <= port_register(xhci_ports) {
		// PED and change status are W1C. Power is ordinary read/write.
		registers[i] &= ~(value & 0x00fe0002)
		registers[i] = (registers[i] & ~u32(1 << 9)) | (value & (1 << 9))
		if connected_after_power && value & (1 << 9) != 0 {
			registers[i] |= 1
		}
	} else {
		registers[i] = value
	}
}

fn now_ns() u64 {
	return clock_ns
}

fn busywait_us(us u64) {
	clock_ns += us * 1000
}

fn test_unpowered_ports_report_devices_after_power_and_debounce() {
	reset_fixture()
	connected_after_power = true
	// Include an enabled port with all change bits set: a power write must
	// neither disable it nor acknowledge changes nor initiate any reset.
	registers[reg_index(port_register(1))] = 0x00fe0002
	registers[reg_index(port_register(2))] = 1 << 9
	power_ports(1 << 3)
	assert clock_ns == 100000000
	assert writes.len == 2 // The already powered port is left alone.
	for port in [u32(1), 3] {
		assert rd(port_register(port)) & 0x201 == 0x201
	}
	assert rd(port_register(1)) & 0x00fe0002 == 0x00fe0002
	for write in writes {
		assert write.value & 0x80ff0012 == 0
	}
}

fn test_always_powered_controller_needs_no_port_writes() {
	reset_fixture()
	power_ports(0)
	assert writes.len == 0
	assert clock_ns == 100000000
}

fn test_delayed_firmware_handoff_finishes_before_timeout() {
	reset_fixture()
	legacy_reg = xhci_cap + 0x100
	firmware_release_ns = 250000000
	registers[reg_index(legacy_reg)] = 1 | (1 << 16)
	registers[reg_index(legacy_reg + 4)] = 0xffffffff
	assert take_ownership(0x100, 0x10000)
	assert clock_ns == firmware_release_ns
	assert writes.len == 2
	assert rd(legacy_reg) & (1 << 16) == 0
	assert rd(legacy_reg) & (1 << 24) != 0
	assert rd(legacy_reg + 4) & 0x0000e011 == 0
}

fn test_stuck_firmware_is_forced_off_after_bounded_wait() {
	reset_fixture()
	legacy_reg = xhci_cap + 0x100
	registers[reg_index(legacy_reg)] = 1 | (1 << 16)
	assert take_ownership(0x100, 0x10000)
	assert clock_ns == 1000000000
	assert writes.len == 3
	assert rd(legacy_reg) & (1 << 16) == 0
	assert rd(legacy_reg) & (1 << 24) != 0
}

fn test_capabilities_are_optional_and_links_are_relative() {
	reset_fixture()
	assert take_ownership(0, 0x10000)
	assert writes.len == 0
	registers[0x100 / 4] = 2 | (4 << 8)
	legacy_reg = xhci_cap + 0x110
	registers[0x110 / 4] = 1
	assert take_ownership(0x100, 0x10000)
	assert writes[0].addr == legacy_reg
	assert clock_ns == 0
}

fn test_bad_capabilities_cannot_access_outside_the_bar() {
	reset_fixture()
	assert !take_ownership(0x10000, 0x10000)
	registers[0xfffc / 4] = 1
	assert !take_ownership(0xfffc, 0x10000)
	registers[0xfffc / 4] = 2 | (4 << 8)
	assert !take_ownership(0xfffc, 0x10000)
	assert writes.len == 0
}
