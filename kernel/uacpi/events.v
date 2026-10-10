// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// ACPI events: the interrupt firmware raises them with, and the work they
// lead to.
//
// Everything a PC's firmware has to say while the machine runs -- the power
// button was pressed, the lid closed, the battery is low, a dock arrived --
// comes through one interrupt, the SCI. uACPI knows what to do with it, but
// asks its host for two things, and both used to be stubs here: a handler for
// that interrupt was accepted and never installed, and the work the handler
// defers (running the AML method for an event, delivering a Notify) was
// refused. No event could arrive.
//
// The SCI is level triggered: it stays asserted until its cause has been
// cleared in the ACPI registers. The interrupt itself therefore only masks
// the line and wakes a thread; the thread runs uACPI's handler, which clears
// the cause, and unmasks the line again. That keeps the interpreter's locks
// and port I/O out of interrupt context.
//
// uACPI installs its handler while the namespace is initialised, before the
// second CPU and the scheduler exist, so installing only records it and
// start_events() does the rest once threads can run.
@[has_globals]
module uacpi

import acpisync
import event
import event.eventstruct
import katomic
import klock
import sched
import x86.apic
import x86.idt

// uACPI's fixed events, by its numbers.
pub const fixed_event_power_button = 2
pub const fixed_event_sleep_button = 3
pub const fixed_event_rtc = 4

// What an interrupt handler tells uACPI.
const interrupt_handled = u32(1)

// MADT interrupt source flags: active low, level triggered. What the
// specification says the SCI is when the MADT does not say otherwise.
const sci_default_flags = u16(0xf)

@[c_extern]
fn C.uacpi_finalize_gpe_initialization() UACPIStatus
@[c_extern]
fn C.uacpi_install_fixed_event_handler(event int, handler voidptr, user voidptr) UACPIStatus

struct SciState {
mut:
	installed bool
	routed    bool
	irq       u32
	gsi       u32
	flags     u16
	vector    u8
	lapic     u32
	handler   fn (voidptr) u32 = unsafe { nil }
	context   voidptr
	wake      eventstruct.Event
	// How many times the line has been raised, for anyone wondering whether
	// events arrive at all.
	count u64
}

struct DeferredWork {
mut:
	handler fn (voidptr) = unsafe { nil }
	context voidptr
}

const work_slots = 64

__global (
	uacpi_sci          SciState
	uacpi_work         [work_slots]DeferredWork
	uacpi_work_count   int
	uacpi_work_lock    klock.Lock
	uacpi_work_wake    eventstruct.Event
	// Work taken off the queue and not yet finished.
	uacpi_work_running u32
	uacpi_work_thread  u64
	uacpi_button_hook  ButtonHook
	uacpi_events_up    bool
	// Set while the SCI thread is inside uACPI's handler.
	uacpi_sci_busy u32
)

struct ButtonHook {
mut:
	pressed fn (event int) = unsafe { nil }
}

// uACPI's host call: remember the handler. One line is supported, the SCI;
// a GPE block with an interrupt of its own is refused rather than accepted
// and never served.
fn install_interrupt(irq u32, handler fn (voidptr) u32, context voidptr, out_handle &voidptr) UACPIStatus {
	if uacpi_sci.installed {
		return UACPIStatus.unimplemented
	}
	uacpi_sci.irq = irq
	uacpi_sci.handler = handler
	uacpi_sci.context = context
	uacpi_sci.installed = true
	unsafe {
		*out_handle = voidptr(&uacpi_sci)
	}
	return UACPIStatus.ok
}

fn uninstall_interrupt(handle voidptr) UACPIStatus {
	if handle != voidptr(&uacpi_sci) || !uacpi_sci.installed {
		return UACPIStatus.invalid_argument
	}
	if uacpi_sci.routed {
		apic.io_apic_set_gsi_redirect(uacpi_sci.lapic, uacpi_sci.vector, uacpi_sci.gsi,
			uacpi_sci.flags, false)
		uacpi_sci.routed = false
	}
	uacpi_sci.installed = false
	uacpi_sci.handler = unsafe { nil }
	return UACPIStatus.ok
}

// The interrupt: mask the line, which is still asserted, and leave the rest
// to the thread.
fn sci_interrupt(_num u32, _gpr_state voidptr) {
	apic.io_apic_set_gsi_redirect(uacpi_sci.lapic, uacpi_sci.vector, uacpi_sci.gsi, uacpi_sci.flags,
		false)
	apic.lapic_eoi()
	katomic.inc(mut &uacpi_sci.count)
	event.trigger(mut uacpi_sci.wake, false)
}

fn sci_thread() {
	for {
		generation := event.generation(mut uacpi_sci.wake)
		katomic.store(mut &uacpi_sci_busy, u32(1))
		if uacpi_sci.handler != unsafe { nil } {
			uacpi_sci.handler(uacpi_sci.context)
		}
		// The causes uACPI found are cleared; one that arrived since raises
		// the line again as soon as it is unmasked.
		if uacpi_sci.routed {
			apic.io_apic_set_gsi_redirect(uacpi_sci.lapic, uacpi_sci.vector, uacpi_sci.gsi,
				uacpi_sci.flags, true)
		}
		katomic.store(mut &uacpi_sci_busy, u32(0))
		event.await_one_from_generation(mut uacpi_sci.wake, true, generation) or {}
	}
}

// Whether nothing of uACPI's event handling is under way: the SCI thread is
// not in the handler, and no deferred work is queued or running. Whoever is
// about to enter a sleeping state with interrupts off asks this first, on the
// one processor still running: uACPI takes its event lock there, a lock that
// sleeps, and a thread put down in the middle of handling an event holds it.
pub fn events_idle() bool {
	if !uacpi_events_up {
		return true
	}
	uacpi_work_lock.acquire()
	idle := uacpi_work_count == 0 && katomic.load(&uacpi_work_running) == 0
		&& katomic.load(&uacpi_sci_busy) == 0
	uacpi_work_lock.release()
	return idle
}

// uACPI's host call: run `handler(context)` later, on a thread. Called from
// the SCI thread and from the interpreter; before the worker exists the work
// waits in the queue.
fn schedule_work(handler fn (voidptr), context voidptr) UACPIStatus {
	uacpi_work_lock.acquire()
	if uacpi_work_count >= work_slots {
		uacpi_work_lock.release()
		return UACPIStatus.out_of_memory
	}
	uacpi_work[uacpi_work_count].handler = handler
	uacpi_work[uacpi_work_count].context = context
	uacpi_work_count++
	uacpi_work_lock.release()
	event.trigger(mut uacpi_work_wake, false)
	return UACPIStatus.ok
}

fn work_thread() {
	uacpi_work_thread = acpisync.thread_id()
	for {
		generation := event.generation(mut uacpi_work_wake)
		uacpi_work_lock.acquire()
		if uacpi_work_count == 0 {
			uacpi_work_lock.release()
			event.await_one_from_generation(mut uacpi_work_wake, true, generation) or {}
			continue
		}
		handler := uacpi_work[0].handler
		context := uacpi_work[0].context
		for i := 0; i + 1 < uacpi_work_count; i++ {
			uacpi_work[i] = uacpi_work[i + 1]
		}
		uacpi_work_count--
		katomic.inc(mut &uacpi_work_running)
		uacpi_work_lock.release()
		handler(context)
		katomic.dec(mut &uacpi_work_running)
	}
}

// uACPI's host call: return once nothing scheduled is queued or running. A
// work item asking -- it removes a handler, say -- does not wait for itself.
fn wait_for_work() UACPIStatus {
	if !uacpi_events_up {
		return UACPIStatus.ok
	}
	own := if acpisync.thread_id() == uacpi_work_thread { u32(1) } else { u32(0) }
	for {
		uacpi_work_lock.acquire()
		idle := uacpi_work_count == 0 && katomic.load(&uacpi_work_running) <= own
		uacpi_work_lock.release()
		if idle {
			return UACPIStatus.ok
		}
		acpisync.sleep(1)
	}
	return UACPIStatus.ok
}

// Run `handler(context)` on the event work thread, after what is queued
// there already: for a driver whose event needs methods evaluated, which the
// thread that hears of it must not do. False when the queue is full.
pub fn defer_work(handler fn (voidptr), context voidptr) bool {
	return schedule_work(handler, context) == .ok
}

// Whether the SCI is routed and the work thread runs.
pub fn events_started() bool {
	return uacpi_events_up
}

// A fixed-feature button. uACPI calls this from the SCI thread.
fn power_button_event(_ voidptr) u32 {
	if uacpi_button_hook.pressed != unsafe { nil } {
		uacpi_button_hook.pressed(fixed_event_power_button)
	}
	return interrupt_handled
}

fn sleep_button_event(_ voidptr) u32 {
	if uacpi_button_hook.pressed != unsafe { nil } {
		uacpi_button_hook.pressed(fixed_event_sleep_button)
	}
	return interrupt_handled
}

// Who is told when a fixed-feature power or sleep button is pressed.
pub fn on_fixed_button(pressed fn (event int)) {
	uacpi_button_hook.pressed = pressed
}

// How many times firmware has raised its interrupt.
pub fn sci_count() u64 {
	return katomic.load(&uacpi_sci.count)
}

// Route the SCI, start the two threads and let general purpose events
// through. Called once the scheduler runs.
pub fn start_events() {
	if uacpi_events_up || !uacpi_sci.installed {
		return
	}
	// The line the FADT names is an ISA interrupt; the MADT says which input
	// of the I/O APIC it really is and how it is wired.
	uacpi_sci.gsi = uacpi_sci.irq
	uacpi_sci.flags = sci_default_flags
	for i := 0; i < madt_isos.len; i++ {
		if u32(madt_isos[i].irq_source) == uacpi_sci.irq {
			uacpi_sci.gsi = madt_isos[i].gsi
			uacpi_sci.flags = madt_isos[i].flags
			// "Conforms to the bus" means level and active low for the SCI.
			if uacpi_sci.flags & 0x3 == 0 {
				uacpi_sci.flags |= 0x3
			}
			if uacpi_sci.flags & 0xc == 0 {
				uacpi_sci.flags |= 0xc
			}
			break
		}
	}
	uacpi_sci.lapic = cpu_locals[0].lapic_id
	uacpi_sci.vector = idt.allocate_vector()
	interrupt_table[uacpi_sci.vector] = voidptr(sci_interrupt)
	uacpi_events_up = true
	sched.new_kernel_thread(voidptr(work_thread), unsafe { nil }, true)
	sched.new_kernel_thread(voidptr(sci_thread), unsafe { nil }, true)
	uacpi_sci.routed = true
	apic.io_apic_set_gsi_redirect(uacpi_sci.lapic, uacpi_sci.vector, uacpi_sci.gsi, uacpi_sci.flags,
		true)

	if C.uacpi_install_fixed_event_handler(fixed_event_power_button, voidptr(power_button_event),
		unsafe { nil }) != .ok {
		// A machine whose power button is a device in the namespace has no
		// fixed one; that button is found with the other ACPI devices.
		print('uacpi: no fixed-feature power button\n')
	}
	C.uacpi_install_fixed_event_handler(fixed_event_sleep_button, voidptr(sleep_button_event),
		unsafe { nil })
	status := C.uacpi_finalize_gpe_initialization()
	if status != .ok {
		C.kprintf(c'uacpi: general purpose events not enabled: %s\n', C.uacpi_status_to_string(status))
	}
	C.kprintf(c'uacpi: events on, SCI is IRQ %llu (GSI %llu, vector 0x%llx)\n', u64(uacpi_sci.irq),
		u64(uacpi_sci.gsi), u64(uacpi_sci.vector))
}
