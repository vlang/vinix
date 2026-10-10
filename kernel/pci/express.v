// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The PCI Express capability, as far as a port with a slot needs it: the
// registers that say whether a card is in the slot, whether its link is up,
// and that switch the slot's power and lights.
module pci

pub const capability_express = u8(0x10)

// Registers of the capability, as offsets from where it starts.
pub const express_flags = u32(0x02)
pub const express_link_capabilities = u32(0x0c)
pub const express_link_status = u32(0x12)
pub const express_slot_capabilities = u32(0x14)
pub const express_slot_control = u32(0x18)
pub const express_slot_status = u32(0x1a)

// express_flags: what kind of port this is, and whether it has a slot.
pub const express_type_root_port = u16(4)
pub const express_type_downstream = u16(6)
pub const express_flag_slot = u16(1) << 8

// express_link_capabilities / express_link_status.
pub const link_reports_active = u32(1) << 20
pub const link_training = u16(1) << 11
pub const link_active = u16(1) << 13

// express_slot_capabilities.
pub const slot_has_button = u32(1) << 0
pub const slot_has_power_switch = u32(1) << 1
pub const slot_has_attention_light = u32(1) << 3
pub const slot_has_power_light = u32(1) << 4
pub const slot_surprise = u32(1) << 5
pub const slot_hotplug = u32(1) << 6
// The port does not report when a command has taken effect.
pub const slot_no_completion = u32(1) << 18

// express_slot_control. A light is on (1), blinking (2) or off (3).
pub const control_attention_light_shift = 6
pub const control_power_light_shift = 8
pub const control_light_mask = u16(3)
pub const light_on = u16(1)
pub const light_blink = u16(2)
pub const light_off = u16(3)
// Set to cut the slot's power.
pub const control_power_off = u16(1) << 10

// express_slot_status. All but the two states are set by the port when
// something happens, and cleared by writing a one.
pub const status_button_pressed = u16(1) << 0
pub const status_power_fault = u16(1) << 1
pub const status_presence_changed = u16(1) << 3
pub const status_command_completed = u16(1) << 4
pub const status_present = u16(1) << 6
pub const status_link_changed = u16(1) << 8
pub const status_events = u16(0x011f)

// Where a capability starts in the function's configuration space, or 0 if
// it has none. The list is firmware's and hardware's; the walk is bounded,
// and stops at anything that could not be a capability.
pub fn (dev &PCIDevice) capability(id u8) u16 {
	if !dev.present() || dev.read[u16](0x06) & (1 << 4) == 0 {
		return 0
	}
	// A CardBus bridge keeps the pointer to its list elsewhere.
	pointer := if dev.header_type == 2 { u32(0x14) } else { u32(0x34) }
	mut offset := u16(dev.read[u8](pointer))
	for _ in 0 .. 48 {
		if offset < 0x40 || offset > 0xfc || offset & 3 != 0 {
			return 0
		}
		header := dev.read[u16](offset)
		if header == 0xffff {
			return 0
		}
		if u8(header) == id {
			return offset
		}
		offset = header >> 8
	}
	return 0
}
