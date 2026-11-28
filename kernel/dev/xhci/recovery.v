// SPDX-License-Identifier: GPL-2.0-or-later
module xhci

const trb_reset_endpoint = u32(14)
const trb_set_dequeue = u32(16)
const cc_babble = u32(3)
const cc_usb_transaction_error = u32(4)
const cc_stall = u32(6)

__global (
	xhci_transfer_errors   u64
	xhci_last_error_slot   u32
	xhci_last_error_dci    u32
	xhci_last_error_code   u32
	xhci_recoveries        u64
	xhci_recovery_failures u64
	xhci_unexpected_events u64
	xhci_recovering        bool
)

fn queue_report(mut f HidFunction) {
	if f.queued || f.disabled || f.recovery_pending {
		return
	}
	f.outstanding = f.ring.push(u32(f.buf_phys), u32(f.buf_phys >> 32), f.packet,
		(trb_normal << 10) | trb_ioc | trb_isp)
	f.queued = true
	ring_doorbell(f.slot, f.dci)
}

fn handle_event(ev Event) {
	if event_type(ev) != trb_transfer_event {
		return
	}
	for i := 0; i < xhci_function_cnt; i++ {
		mut f := &xhci_functions[i]
		if f.slot != event_slot(ev) || f.dci != event_endpoint(ev) {
			continue
		}
		// Event Data is not used by these single-Normal-TRB TDs. Never let
		// an unsolicited/stale event release DMA ownership or multiply TDs.
		if !f.queued || ev.param != f.outstanding || ev.control & (1 << 2) != 0 {
			xhci_unexpected_events++
			return
		}
		f.queued = false
		code := event_code(ev)
		if code == cc_success || code == cc_short_packet {
			residual := ev.status & 0xffffff
			length := if residual < f.packet { f.packet - residual } else { u32(0) }
			f.report(length)
			queue_report(mut f)
			return
		}
		xhci_transfer_errors++
		xhci_last_error_slot = f.slot
		xhci_last_error_dci = f.dci
		xhci_last_error_code = code
		f.disabled = true
		f.recovery_code = code
		f.recovery_pending = code == cc_babble || code == cc_usb_transaction_error
			|| code == cc_stall
		if !f.recovery_pending {
			forget_function_keys(mut f)
		}
		C.kprintf(c'xhci: transfer error slot %llu DCI %llu code %llu\n',
			u64(f.slot), u64(f.dci), u64(code))
		return
	}
	xhci_unexpected_events++
}

fn recover_endpoint(mut f HidFunction) bool {
	command(0, 0, 0, (trb_reset_endpoint << 10) | (f.dci << 16) | (f.slot << 24)) or {
		return false
	}
	if recovery_stopped() {
		return false
	}
	if f.recovery_code == cc_stall {
		if f.slot == 0 || f.slot >= u32(xhci_devices.len)
			|| xhci_devices[f.slot].slot != f.slot || xhci_ep0_failed[f.slot] {
			return false
		}
		// CLEAR_FEATURE(ENDPOINT_HALT), addressed to the interrupt IN endpoint.
		if !control(mut xhci_devices[f.slot], 0x02, 1, 0, u16(0x80 | (f.dci / 2)), 0) {
			// A timeout does not return EP0's DMA ownership. Do not submit
			// another control TD on this slot until controller reinitialisation.
			xhci_ep0_failed[f.slot] = true
			return false
		}
	}
	if recovery_stopped() {
		return false
	}
	// push() has already advanced past the failed TD and handled the Link
	// at wrap. Both the address and DCS must describe that next free slot.
	dequeue := (f.ring.phys + u64(f.ring.index) * 16) | u64(f.ring.cycle)
	command(u32(dequeue), u32(dequeue >> 32), 0,
		(trb_set_dequeue << 10) | (f.dci << 16) | (f.slot << 24)) or { return false }
	return !recovery_stopped()
}

// Only the poller calls this, after draining events. command()/control()
// may handle other completions, but handle_event never issues commands.
// Clear pending before waiting, retaining disabled throughout those waits.
fn recover_endpoints() {
	if xhci_recovering || recovery_stopped() {
		return
	}
	xhci_recovering = true
	for i := 0; i < xhci_function_cnt; i++ {
		// Resume waits for this poller before freeing DMA. Start no further
		// recovery once stopped; only the current bounded wait may finish.
		if recovery_stopped() {
			break
		}
		mut f := &xhci_functions[i]
		if !f.recovery_pending {
			continue
		}
		f.recovery_pending = false
		if !recover_endpoint(mut f) {
			forget_function_keys(mut f)
			xhci_recovery_failures++
			C.kprintf(c'xhci: recovery failed slot %llu DCI %llu; input disabled\n',
				u64(f.slot), u64(f.dci))
			continue
		}
		xhci_recoveries++
		C.kprintf(c'xhci: recovered slot %llu DCI %llu\n', u64(f.slot), u64(f.dci))
		f.disabled = false
		queue_report(mut f)
	}
	xhci_recovering = false
}
