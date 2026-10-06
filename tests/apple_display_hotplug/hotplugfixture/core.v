// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Independent display-hotplug oracle; exact original predicates and tags.
@[translated]
module hotplugfixture

#include <hotplug-native-abi.h>
@[typedef]
struct C.FILE {}

struct C.vinix_display_hotplug_state {
mut:
	candidate_since_ms u64
	status             u32
	data_status        u32
	stable             u8
	candidate          u8
	initialized        u8
}

@[c_extern]
__global C.stderr &C.FILE

fn C.fprintf(&C.FILE, &char, ...) i32
fn C.puts(&char) i32
fn C.vinix_display_hotplug_state_size() usize
fn C.vinix_display_hotplug_reset(&C.vinix_display_hotplug_state)
fn C.vinix_display_hotplug_candidate(u32, u32) i32
fn C.vinix_display_hotplug_sample(&C.vinix_display_hotplug_state, u32, u32, u64, u64) i32
fn C.vinix_display_hotplug_connected(&C.vinix_display_hotplug_state) i32
fn C.vinix_display_hotplug_choose_action(i32, i32, i32, u64, u64) i32

fn check(ok bool, line i32, expression &char) bool {
	if !ok { unsafe { C.fprintf(C.stderr, c'check failed at line %d: %s\n', line, expression) } }
	return ok
}

fn display_status(transport u32) u32 {
	return u32(C.VINIX_CD321X_DATA_CONNECTION) | u32(C.VINIX_CD321X_DATA_HPD_LEVEL) | transport
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut state := C.vinix_display_hotplug_state{}
		if !check(C.vinix_display_hotplug_state_size() == sizeof(C.vinix_display_hotplug_state), 25, c'vinix_display_hotplug_state_size() == sizeof(state)') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(nil, 0, 0, 0, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 26, c'vinix_display_hotplug_sample(NULL, 0, 0, 0, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(nil) == 0, 28, c'!vinix_display_hotplug_connected(NULL)') {
			return 1
		}
		C.vinix_display_hotplug_reset(nil)
		C.vinix_display_hotplug_reset(&state)

		if !check(C.vinix_display_hotplug_candidate(0, 0) == 0, 32, c'!vinix_display_hotplug_candidate(0, 0)') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			display_status(0)) == 0, 33, c'!vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, display_status(0))') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			u32(C.VINIX_CD321X_DATA_DP_CONNECTION)) == 0, 35, c'!vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, VINIX_CD321X_DATA_DP_CONNECTION)') {
			return 1
		}
		/* A cold attach has no DCP to produce HPD yet. */
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			u32(C.VINIX_CD321X_DATA_CONNECTION) | u32(C.VINIX_CD321X_DATA_DP_CONNECTION)) != 0, 38, c'vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, VINIX_CD321X_DATA_CONNECTION | VINIX_CD321X_DATA_DP_CONNECTION)') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			u32(C.VINIX_CD321X_DATA_CONNECTION) | u32(C.VINIX_CD321X_DATA_TBT_CONNECTION)) != 0, 40, c'vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, VINIX_CD321X_DATA_CONNECTION | VINIX_CD321X_DATA_TBT_CONNECTION)') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			u32(C.VINIX_CD321X_DATA_CONNECTION) | u32(C.VINIX_CD321X_DATA_USB4_CONNECTION)) != 0, 42, c'vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, VINIX_CD321X_DATA_CONNECTION | VINIX_CD321X_DATA_USB4_CONNECTION)') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			display_status(u32(C.VINIX_CD321X_DATA_DP_CONNECTION))) != 0, 44, c'vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, display_status(VINIX_CD321X_DATA_DP_CONNECTION))') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			display_status(u32(C.VINIX_CD321X_DATA_TBT_CONNECTION))) != 0, 46, c'vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, display_status(VINIX_CD321X_DATA_TBT_CONNECTION))') {
			return 1
		}
		if !check(C.vinix_display_hotplug_candidate(u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			display_status(u32(C.VINIX_CD321X_DATA_USB4_CONNECTION))) != 0, 48, c'vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT, display_status(VINIX_CD321X_DATA_USB4_CONNECTION))') {
			return 1
		}

		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 100, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 51, c'vinix_display_hotplug_sample(&state, 0, 0, 100, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) == 0, 53, c'!vinix_display_hotplug_connected(&state)') {
			return 1
		}

		data := display_status(u32(C.VINIX_CD321X_DATA_TBT_CONNECTION))
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 200, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 56, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 200, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 699, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 59, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 699, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 700, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_CONNECTED, 62, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 700, 500) == VINIX_DISPLAY_HOTPLUG_CONNECTED') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) != 0, 65, c'vinix_display_hotplug_connected(&state)') {
			return 1
		}

		/* A short HPD pulse must not disconnect a working display. */
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT),
			data & ~u32(C.VINIX_CD321X_DATA_HPD_LEVEL), 800, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 68, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data & ~VINIX_CD321X_DATA_HPD_LEVEL, 800, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 900, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 72, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 900, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) != 0, 75, c'vinix_display_hotplug_connected(&state)') {
			return 1
		}

		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 1000, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 77, c'vinix_display_hotplug_sample(&state, 0, 0, 1000, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 1500, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_DISCONNECTED, 79, c'vinix_display_hotplug_sample(&state, 0, 0, 1500, 500) == VINIX_DISPLAY_HOTPLUG_DISCONNECTED') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) == 0, 81, c'!vinix_display_hotplug_connected(&state)') {
			return 1
		}

		/* A connection that disappears inside the debounce window is ignored. */
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 1600, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 84, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 1600, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 1900, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 87, c'vinix_display_hotplug_sample(&state, 0, 0, 1900, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) == 0, 89, c'!vinix_display_hotplug_connected(&state)') {
			return 1
		}

		/* Debouncing uses modulo time so a monotonic counter wrap is harmless. */
		C.vinix_display_hotplug_reset(&state)
		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, u64(0xffffffffffffffff) - 300, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 93, c'vinix_display_hotplug_sample(&state, 0, 0, UINT64_MAX - 300, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, u64(0xffffffffffffffff) - 200, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 95, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, UINT64_MAX - 200, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 298, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 98, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 298, 500) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state,
			u32(C.VINIX_CD321X_STATUS_PLUG_PRESENT), data, 299, 500) ==
			C.VINIX_DISPLAY_HOTPLUG_CONNECTED, 101, c'vinix_display_hotplug_sample(&state, VINIX_CD321X_STATUS_PLUG_PRESENT, data, 299, 500) == VINIX_DISPLAY_HOTPLUG_CONNECTED') {
			return 1
		}

		/* First attach recovery is deliberately narrow and one-shot. */
		if !check(C.vinix_display_hotplug_choose_action(0, 1, 0, 2560, 1600) ==
			C.VINIX_DISPLAY_HOTPLUG_IGNORE, 106, c'vinix_display_hotplug_choose_action(0, 1, 0, 2560, 1600) == VINIX_DISPLAY_HOTPLUG_IGNORE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_choose_action(1, 0, 0, 2560, 1600) ==
			C.VINIX_DISPLAY_HOTPLUG_REPAINT, 108, c'vinix_display_hotplug_choose_action(1, 0, 0, 2560, 1600) == VINIX_DISPLAY_HOTPLUG_REPAINT') {
			return 1
		}
		if !check(C.vinix_display_hotplug_choose_action(1, 1, 0, 2560, 1600) ==
			C.VINIX_DISPLAY_HOTPLUG_REBOOT, 110, c'vinix_display_hotplug_choose_action(1, 1, 0, 2560, 1600) == VINIX_DISPLAY_HOTPLUG_REBOOT') {
			return 1
		}
		if !check(C.vinix_display_hotplug_choose_action(1, 1, 1, 2560, 1600) ==
			C.VINIX_DISPLAY_HOTPLUG_REPAINT, 112, c'vinix_display_hotplug_choose_action(1, 1, 1, 2560, 1600) == VINIX_DISPLAY_HOTPLUG_REPAINT') {
			return 1
		}
		if !check(C.vinix_display_hotplug_choose_action(1, 1, 0, 5120, 2880) ==
			C.VINIX_DISPLAY_HOTPLUG_REPAINT, 114, c'vinix_display_hotplug_choose_action(1, 1, 0, 5120, 2880) == VINIX_DISPLAY_HOTPLUG_REPAINT') {
			return 1
		}
		if !check(C.vinix_display_hotplug_choose_action(1, 1, 0, 0, 0) ==
			C.VINIX_DISPLAY_HOTPLUG_REPAINT, 116, c'vinix_display_hotplug_choose_action(1, 1, 0, 0, 0) == VINIX_DISPLAY_HOTPLUG_REPAINT') {
			return 1
		}

		/* C truth values need not be 1, and action arguments are 32-bit ints. */
		if !check(C.vinix_display_hotplug_choose_action(i32(-2147483648), -1, 0, 2560, 1600) ==
			C.VINIX_DISPLAY_HOTPLUG_REBOOT, 120, c'vinix_display_hotplug_choose_action(INT32_MIN, -1, 0, 2560, 1600) == VINIX_DISPLAY_HOTPLUG_REBOOT') {
			return 1
		}
		if !check(C.vinix_display_hotplug_choose_action(i32(-2147483648), -1, i32(-2147483648), 2560, 1600) ==
			C.VINIX_DISPLAY_HOTPLUG_REPAINT, 122, c'vinix_display_hotplug_choose_action(INT32_MIN, -1, INT32_MIN, 2560, 1600) == VINIX_DISPLAY_HOTPLUG_REPAINT') {
			return 1
		}

		/* An already-attached display at initialization is baseline state, not
     * a post-boot event. Preserve uninterpreted controller bits as evidence. */
		C.vinix_display_hotplug_reset(&state)
		if !check(C.vinix_display_hotplug_sample(&state, u32(0xffffffff), data, 0, 0) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 128, c'vinix_display_hotplug_sample(&state, UINT32_MAX, data, 0, 0) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) == 1, 130, c'vinix_display_hotplug_connected(&state) == 1') {
			return 1
		}
		if !check(state.status == u32(0xffffffff) && state.data_status == data, 131, c'state.status == UINT32_MAX && state.data_status == data') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state, u32(0xffffffff), data, 1, 0) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 132, c'vinix_display_hotplug_sample(&state, UINT32_MAX, data, 1, 0) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}

		/* Even zero debounce confirms a changed candidate in a second sample,
     * and emits the transition only once. */
		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 2, 0) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 137, c'vinix_display_hotplug_sample(&state, 0, 0, 2, 0) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 2, 0) ==
			C.VINIX_DISPLAY_HOTPLUG_DISCONNECTED, 139, c'vinix_display_hotplug_sample(&state, 0, 0, 2, 0) == VINIX_DISPLAY_HOTPLUG_DISCONNECTED') {
			return 1
		}
		if !check(C.vinix_display_hotplug_sample(&state, 0, 0, 2, 0) ==
			C.VINIX_DISPLAY_HOTPLUG_NONE, 141, c'vinix_display_hotplug_sample(&state, 0, 0, 2, 0) == VINIX_DISPLAY_HOTPLUG_NONE') {
			return 1
		}
		if !check(C.vinix_display_hotplug_connected(&state) == 0, 143, c'!vinix_display_hotplug_connected(&state)') {
			return 1
		}

		C.puts(c'apple display hotplug state tests passed')
		return 0
	}
}
