// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
module typec

#include "apple_display_hotplug.h"

struct C.vinix_display_hotplug_state {
mut:
	candidate_since_ms u64
	status u32
	data_status u32
	stable u8
	candidate u8
	initialized u8
}

fn C.memset(dest voidptr, value i32, length usize) voidptr

@[export: 'vinix_display_hotplug_state_size']
fn hotplug_state_size() usize {
	return sizeof(C.vinix_display_hotplug_state)
}

@[export: 'vinix_display_hotplug_reset']
fn hotplug_reset(state &C.vinix_display_hotplug_state) {
	if usize(state) == 0 { return }
	unsafe { C.memset(state, 0, sizeof(C.vinix_display_hotplug_state)) }
}

// HPD can stay low until external DCP starts; presence and a negotiated
// display-capable transport suffice for the first attach.
@[export: 'vinix_display_hotplug_candidate']
fn hotplug_candidate(status u32, data_status u32) i32 {
	display_mode := u32(C.VINIX_CD321X_DATA_DP_CONNECTION)
		| u32(C.VINIX_CD321X_DATA_TBT_CONNECTION) | u32(C.VINIX_CD321X_DATA_USB4_CONNECTION)
	return i32(status & u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT) != 0
		&& data_status & u32(C.VINIX_CD321X_DATA_CONNECTION) != 0
		&& data_status & display_mode != 0)
}

@[export: 'vinix_display_hotplug_sample']
fn hotplug_sample(state &C.vinix_display_hotplug_state, status u32, data_status u32,
	now_ms u64, debounce_ms u64) i32 {
	if usize(state) == 0 { return C.VINIX_DISPLAY_HOTPLUG_NONE }
	connected := u8(hotplug_candidate(status, data_status))
	unsafe {
		state.status = status
		state.data_status = data_status
		if state.initialized == 0 {
			state.initialized = 1
			state.stable = connected
			state.candidate = connected
			state.candidate_since_ms = now_ms
			return C.VINIX_DISPLAY_HOTPLUG_NONE
		}
		if state.candidate != connected {
			state.candidate = connected
			state.candidate_since_ms = now_ms
			return C.VINIX_DISPLAY_HOTPLUG_NONE
		}
		if state.stable == state.candidate { return C.VINIX_DISPLAY_HOTPLUG_NONE }
		// Unsigned elapsed time preserves debounce across a counter wrap.
		if now_ms - state.candidate_since_ms < debounce_ms { return C.VINIX_DISPLAY_HOTPLUG_NONE }
		state.stable = state.candidate
		return if state.stable != 0 { i32(C.VINIX_DISPLAY_HOTPLUG_CONNECTED) }
			else { i32(C.VINIX_DISPLAY_HOTPLUG_DISCONNECTED) }
	}
}

@[export: 'vinix_display_hotplug_connected']
fn hotplug_connected(state &C.vinix_display_hotplug_state) i32 {
	return i32(usize(state) != 0 && state.initialized != 0 && state.stable != 0)
}

@[export: 'vinix_display_hotplug_choose_action']
pub fn hotplug_choose_action(connected i32, reboot_enabled i32, reboot_attempted i32,
	panel_width u64, panel_height u64) i32 {
	if connected == 0 { return C.VINIX_DISPLAY_HOTPLUG_IGNORE }
	if reboot_enabled != 0 && reboot_attempted == 0
		&& panel_width == 2560 && panel_height == 1600 {
		return C.VINIX_DISPLAY_HOTPLUG_REBOOT
	}
	return C.VINIX_DISPLAY_HOTPLUG_REPAINT
}
