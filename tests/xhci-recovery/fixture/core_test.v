// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module xhci

#include <stdio.h>
#flag -Dkprintf=printf

fn C.kprintf(&char, ...int) int

struct Command {
	d0 u32
	d1 u32
	d2 u32
	d3 u32
}

__global (
	xhci_functions    [8]HidFunction
	xhci_function_cnt int
	xhci_devices      [17]Device
	xhci_ep0_failed   [17]bool
	xhci_db           u64
	stopped bool
	stop_in_command bool
	released []u16
	xhci_repeat_code u16
	xhci_repeat_slot u32
	xhci_repeat_dci u32
	xhci_repeat_next u64
	ram               [16384]u32
	commands          []Command
	actions           []string
	doorbells         []u32
	report_lengths    []u32
	fail_command      u32
	fail_control      bool
	in_command        bool
	injected          []Event
	control_injected  []Event
)

fn mem_rd(addr u64) u32 { return ram[addr / 4] }

fn mem_wr(addr u64, value u32) { ram[addr / 4] = value }

fn mem_wr64(addr u64, value u64) {
	mem_wr(addr, u32(value))
	mem_wr(addr + 4, u32(value >> 32))
}

fn barrier() {}

fn barrier_full() {}

fn alloc_page() (u64, u64) { return 0x1000, 0x1000 }

fn wr(addr u64, value u32) {
	assert addr >= xhci_db
	assert value == 1 || value == 3 || value == 5
	if value == 1 { return }
	doorbells << u32((addr - xhci_db) / 4)
	actions << 'doorbell'
}

fn (mut f HidFunction) report(length u32) { report_lengths << length }

// Model command()/await_transfer() draining unrelated completions. Calling
// another command here would mean recovery recursively entered the wait.
fn command(d0 u32, d1 u32, d2 u32, d3 u32) ?Event {
	assert !in_command
	in_command = true
	defer { in_command = false }
	kind := (d3 >> 10) & 0x3f
	commands << Command{d0, d1, d2, d3}
	actions << if kind == trb_reset_endpoint { 'reset' } else { 'dequeue' }
	pending := injected.clone()
	injected.clear()
	for ev in pending { handle_event(ev) }
	if stop_in_command { stopped = true }
	if kind == fail_command { return none }
	return Event{}
}

fn await_transfer(slot u32, dci u32, trb u64) ?Event {
	assert !in_command
	assert slot == 1 && dci == 1
	assert trb == xhci_devices[1].ep0.phys + 16
	actions << "clear"
	pending := control_injected.clone()
	control_injected.clear()
	for ev in pending { handle_event(ev) }
	if fail_control { return none }
	return Event{}
}

fn recovery_stopped() bool { return stopped }

fn sink_key(code u16, value u32) {
	assert value == 0
	released << code
}

fn fixture() {
	xhci_functions = [8]HidFunction{}
	xhci_devices = [17]Device{}
	xhci_ep0_failed = [17]bool{}
	stopped = false
	stop_in_command = false
	released = []u16{}
	xhci_repeat_code = 0
	xhci_repeat_next = 0
	xhci_repeat_slot = 0
	xhci_repeat_dci = 0
	xhci_function_cnt = 1
	xhci_db = 0x100000
	ram = [16384]u32{}
	commands = []Command{}
	actions = []string{}
	doorbells = []u32{}
	report_lengths = []u32{}
	injected = []Event{}
	control_injected = []Event{}
	fail_command = 0
	fail_control = false
	in_command = false
	xhci_transfer_errors = 0
	xhci_recoveries = 0
	xhci_recovery_failures = 0
	xhci_unexpected_events = 0
	xhci_recovering = false
	xhci_devices[1] = Device{ slot: 1, ep0: Ring{phys: 0x3000, virt: 0x3000, cycle: 1} }
	xhci_functions[0] = HidFunction{ slot: 1, dci: 3, packet: 8, ring: new_ring() }
	queue_report(mut xhci_functions[0])
	actions.clear()
	doorbells.clear()
}

fn completion(i int, code u32, residual u32) Event {
	f := xhci_functions[i]
	return Event{
		param:   f.outstanding
		status:  (code << 24) | residual
		control: (trb_transfer_event << 10) | (f.slot << 24) | (f.dci << 16)
	}
}

fn test_success_short_packet_and_one_outstanding() {
	fixture()
	queue_report(mut xhci_functions[0])
	assert doorbells.len == 0
	handle_event(completion(0, cc_success, 0))
	handle_event(completion(0, cc_short_packet, 5))
	handle_event(completion(0, cc_short_packet, 8))
	assert report_lengths == [u32(8), 3, 0]
	assert doorbells == [u32(1), 1, 1]
	assert commands.len == 0
	assert xhci_functions[0].queued
}

fn test_halting_errors_defer_and_recover_once() {
	for code in [cc_babble, cc_usb_transaction_error, cc_stall] {
		fixture()
		handle_event(completion(0, code, 0))
		assert actions.len == 0
		assert xhci_functions[0].disabled && xhci_functions[0].recovery_pending
		assert !xhci_functions[0].queued
		queue_report(mut xhci_functions[0])
		assert doorbells.len == 0
		recover_endpoints()
		assert actions == if code == cc_stall {
			['reset', 'clear', 'dequeue', 'doorbell']
		} else {
			['reset', 'dequeue', 'doorbell']
		}
		assert xhci_transfer_errors == 1 && xhci_recoveries == 1
		assert xhci_last_error_slot == 1 && xhci_last_error_dci == 3
		assert xhci_last_error_code == code
		assert commands[0].d3 == (14 << 10) | (3 << 16) | (1 << 24)
		assert commands[1].d3 == (16 << 10) | (3 << 16) | (1 << 24)
		assert commands[1].d0 == 0x1011
		assert commands[1].d1 == 0 && commands[1].d2 == 0
		recover_endpoints()
		assert xhci_recoveries == 1 && doorbells == [u32(1)]
		if code == cc_stall {
			assert xhci_devices[1].ep0.index == 2
		}
	}
}

fn test_dequeue_uses_producer_cycle_after_link_wrap() {
	fixture()
	xhci_functions[0].queued = false
	xhci_functions[0].ring.index = 254
	queue_report(mut xhci_functions[0])
	assert xhci_functions[0].ring.index == 0
	assert xhci_functions[0].ring.cycle == 0
	assert mem_rd(0x1000 + 255 * 16 + 12) & 1 == 1
	actions.clear()
	handle_event(completion(0, cc_babble, 0))
	recover_endpoints()
	assert commands[1].d0 == 0x1000
	assert mem_rd(0x1000 + 12) & 1 == 0
	assert actions == ['reset', 'dequeue', 'doorbell']
}

fn test_failure_gates_leave_dma_buffer_disabled() {
	for stage in ['reset', 'clear', 'dequeue'] {
		fixture()
		fail_command = match stage {
			'reset' { trb_reset_endpoint }
			'dequeue' { trb_set_dequeue }
			else { u32(0) }
		}
		fail_control = stage == 'clear'
		handle_event(completion(0, cc_stall, 0))
		recover_endpoints()
		assert xhci_recovery_failures == 1 && xhci_recoveries == 0
		assert xhci_functions[0].disabled && !xhci_functions[0].queued
		assert !xhci_functions[0].recovery_pending
		assert doorbells.len == 0 && report_lengths.len == 0
		assert actions == match stage {
			'reset' { ['reset'] }
			'clear' { ['reset', 'clear'] }
			else { ['reset', 'clear', 'dequeue'] }
		}
		queue_report(mut xhci_functions[0])
		recover_endpoints()
		assert doorbells.len == 0 && xhci_recovery_failures == 1
		assert xhci_ep0_failed[1] == (stage == 'clear')
	}
}

fn test_unsolicited_stale_and_event_data_do_not_requeue() {
	fixture()
	old := completion(0, cc_success, 0)
	handle_event(Event{ ...old, param: old.param + 16 })
	handle_event(Event{ ...old, control: old.control | 4 })
	assert doorbells.len == 0 && xhci_functions[0].queued
	handle_event(old)
	handle_event(old)
	assert doorbells.len == 1 && report_lengths.len == 1
	assert xhci_unexpected_events == 3
	failed := completion(0, cc_stall, 0)
	handle_event(failed)
	handle_event(failed)
	assert xhci_transfer_errors == 1 && doorbells.len == 1
}

fn test_other_endpoints_during_command_wait_do_not_recurse() {
	fixture()
	xhci_function_cnt = 3
	for i in 1 .. 3 {
		xhci_functions[i] = HidFunction{
			slot:   u32(i + 1)
			dci:    3
			packet: 8
			ring:   Ring{ phys: u64(i + 1) * 0x1000, virt: u64(i + 1) * 0x1000, cycle: 1 }
		}
		queue_report(mut xhci_functions[i])
	}
	actions.clear()
	doorbells.clear()
	first := completion(0, cc_babble, 0)
	handle_event(first)
	injected = [first, completion(1, cc_usb_transaction_error, 0), completion(2, cc_short_packet, 4)]
	recover_endpoints()
	assert xhci_recoveries == 2 && xhci_transfer_errors == 2
	assert report_lengths == [u32(4)]
	assert doorbells == [u32(3), 1, 2]
	assert commands.len == 4
	for i in 0 .. 3 {
		assert xhci_functions[i].queued
	}
	// A lower-index endpoint failing while a later one recovers stays
	// deferred safely until the next round, without reusing its buffer.
	handle_event(completion(1, cc_babble, 0))
	injected = [completion(0, cc_babble, 0)]
	recover_endpoints()
	assert xhci_functions[0].disabled && xhci_functions[0].recovery_pending
	assert !xhci_functions[0].queued
	recover_endpoints()
	assert xhci_functions[0].queued && xhci_recoveries == 4
}

fn test_control_wait_defers_errors_and_failed_ep0_is_not_reused() {
	fixture()
	xhci_function_cnt = 2
	xhci_functions[1] = HidFunction{
		slot:   1
		dci:    5
		packet: 8
		ring:   Ring{ phys: 0x2000, virt: 0x2000, cycle: 1 }
	}
	queue_report(mut xhci_functions[1])
	actions.clear()
	doorbells.clear()
	handle_event(completion(0, cc_stall, 0))
	control_injected = [completion(1, cc_stall, 0)]
	fail_control = true
	recover_endpoints()
	assert actions == ['reset', 'clear', 'reset']
	assert xhci_recovery_failures == 2 && xhci_recoveries == 0
	assert xhci_devices[1].ep0.index == 2
	assert doorbells.len == 0
	assert xhci_functions[0].disabled && xhci_functions[1].disabled
	assert !xhci_functions[0].queued && !xhci_functions[1].queued
}

fn test_ring_push_many_wraps_and_both_outgoing_cycles() {
	fixture()
	mut ring := new_ring()
	for wrap in 0 .. 40 {
		cycle := u32(1 - wrap % 2)
		for index in 0 .. 255 {
			assert ring.index == u32(index) && ring.cycle == cycle
			addr := ring.push(u32(wrap), u32(index), 8, (trb_normal << 10) | trb_cycle)
			assert addr == ring.phys + u64(index) * 16
			assert mem_rd(addr) == u32(wrap)
			assert mem_rd(addr + 4) == u32(index)
			assert mem_rd(addr + 12) == (trb_normal << 10) | cycle
		}
		assert ring.index == 0 && ring.cycle == cycle ^ 1
		assert mem_rd(ring.virt + 255 * 16 + 12) == (trb_link << 10) | trb_toggle_cycle | cycle
	}
}

fn test_permanent_disable_releases_only_failed_keyboard_and_its_repeat() {
	for failure in ['unsupported', 'recovery'] {
		fixture()
		xhci_function_cnt = 2
		xhci_functions[0].kind = kind_keyboard
		xhci_functions[0].keys = [u8(4), 5, 0, 0, 0, 0]!
		xhci_functions[0].modifiers = 3
		xhci_functions[1] = HidFunction{slot: 2, dci: 3, kind: kind_keyboard,
			keys: [u8(6), 0, 0, 0, 0, 0]!, modifiers: 4}
		xhci_repeat_code = 30
		xhci_repeat_slot = 1
		xhci_repeat_dci = 3
		xhci_repeat_next = 123
		if failure == 'unsupported' {
			handle_event(completion(0, 5, 0))
		} else {
			fail_command = trb_reset_endpoint
			handle_event(completion(0, cc_babble, 0))
			assert released.len == 0
			recover_endpoints()
		}
		assert released == [u16(29), 42, 30, 48]
		assert xhci_functions[0].keys == [6]u8{} && xhci_functions[0].modifiers == 0
		assert xhci_functions[1].keys[0] == 6 && xhci_functions[1].modifiers == 4
		assert xhci_repeat_code == 0 && xhci_repeat_next == 0
		forget_function_keys(mut xhci_functions[0])
		assert released.len == 4
	}
}

fn test_forget_function_preserves_other_keyboard_repeat_even_same_keycode() {
	fixture()
	xhci_functions[0].kind = kind_keyboard
	xhci_functions[0].keys[0] = 4
	xhci_repeat_code = 30
	xhci_repeat_slot = 2
	xhci_repeat_dci = 3
	xhci_repeat_next = 123
	forget_function_keys(mut xhci_functions[0])
	assert released == [u16(30)]
	assert xhci_repeat_code == 30 && xhci_repeat_next == 123
}

fn test_retained_enumeration_ep0_failure_prevents_control_submission() {
	fixture()
	mut dev := xhci_devices[1]
	fail_control = true
	assert !control(mut dev, 0x21, 0x0b, 0, 0, 0)
	assert dev.ep0_failed
	// Match attach's retention after take_hid_functions, including a failed
	// boot-protocol request whose failure enumeration intentionally ignores.
	xhci_devices[dev.slot] = dev
	xhci_ep0_failed[dev.slot] = dev.ep0_failed
	index := dev.ep0.index
	actions.clear()
	fail_control = false
	assert !control(mut xhci_devices[1], 0x02, 1, 0, 0x81, 0)
	assert xhci_devices[1].ep0.index == index && actions.len == 0
	handle_event(completion(0, cc_stall, 0))
	recover_endpoints()
	assert actions == ['reset']
	assert xhci_recovery_failures == 1
}

fn test_stop_relinquishes_recovery_after_current_command() {
	fixture()
	handle_event(completion(0, cc_babble, 0))
	stopped = true
	recover_endpoints()
	assert commands.len == 0 && xhci_functions[0].recovery_pending
	stopped = false
	stop_in_command = true
	recover_endpoints()
	assert actions == ['reset']
	assert !xhci_recovering && !xhci_functions[0].queued
}
