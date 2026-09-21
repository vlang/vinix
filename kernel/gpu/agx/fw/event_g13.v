// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// G13 v12.3 notifier objects shared by all native subqueues belonging to one
// DRM queue. The linked-list head is self-linked through `next`, matching the
// reference firmware builder; `prev` remains null until firmware links it.

@[packed]
pub struct G13LinkedListHead {
pub mut:
	prev u64
	next u64
}

@[packed]
pub struct G13NotifierList {
pub mut:
	list_head G13LinkedListHead
	unk_10   u64
}

@[packed]
pub struct G13NotifierState {
pub mut:
	unk_14       u32
	unk_18       u64
	unk_20       u32
	vm_slot      u32
	has_vertex   u32
	stamp_vertex [4]u64
	has_fragment u32
	stamp_fragment [4]u64
	has_compute  u32
	stamp_compute [4]u64
	in_list      u32
	list_head    G13LinkedListHead
}

@[packed]
pub struct G13Notifier {
pub mut:
	threshold  u64
	generation u32
	cur_count  u32
	unk_10     u32
	state      G13NotifierState
}

pub fn g13_notifier_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { u64(sizeof(G13Notifier)) }
		.v13_5_partial { u64(0xb0) }
		else { none }
	}
}

pub fn initialize_g13_notifier(data voidptr, size u64, abi hw.FirmwareAbi,
	threshold u64, generation u32) bool {
	required := g13_notifier_active_size(abi) or { return false }
	if data == unsafe { nil } || size < required || threshold == 0 {
		return false
	}
	unsafe {
		mut notifier := &G13Notifier(data)
		notifier.threshold = threshold
		notifier.generation = generation
		notifier.unk_10 = 0x50
		if abi == .v13_5_partial {
			mut bytes := &u8(data)
			for offset := u32(0xa8); offset < 0xb0; offset++ {
				bytes[offset] = 0xff
			}
		}
	}
	return true
}

pub fn validate_g13_event_layouts() bool {
	return sizeof(G13LinkedListHead) == 0x10 && sizeof(G13NotifierList) == 0x18
		&& sizeof(G13NotifierState) == 0x94 && sizeof(G13Notifier) == 0xa8
}
