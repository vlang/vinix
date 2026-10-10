// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// PCI functions put to sleep with the machine.
//
// A driver's suspend makes its device quiet: no interrupts, nothing in
// flight. The device is still fully powered. One with a power management
// capability can be told to give most of that up -- D3hot, in which it
// answers in configuration space and nowhere else -- and for a suspend to
// idle that is most of what there is to save; before a suspend to RAM it is
// the state the platform expects to find a device in when it cuts the power.
//
// So after every driver has suspended, pci_sleep_all() puts into D3hot each
// function whose driver can bring it back from nothing, and before the first
// driver resumes, pci_wake_all() brings them back to D0 and writes their
// configuration space back as pci_state.v does after a loss of power: a
// function need not keep anything across D3hot (one that does says so, "no
// soft reset"), and most forget their address registers with the rest.
//
// Which functions: those bound to a driver that has both a suspend and a
// resume -- the same test that decides whether the machine may be suspended
// to RAM at all, because the question is the same -- that were suspended for
// this sleep, are in D0 now, and are not allowed to wake the machine: nothing
// here arms a function to signal from D3 (PME), so one that must be able to
// wake it stays as its driver left it. Bridges have no driver and stay in
// D0, so what is behind them can still be reached.
//
// A function that does not take the state is left in D0 and counted. One that
// does not come back is not resumed: its driver would set up a device that is
// not listening. It is reported as failed, and recovery resets it or lets it
// go, as for any device that stopped answering.
//
// The steps and the delays are those of Linux's pci_set_power_state():
// PME switched off and its stale status cleared on the way down, ten
// milliseconds after either change before the function is spoken to again.
//
// `vinix.pci_d3=off` keeps every function in D0 through every sleep.
@[has_globals]
module devcore

import pci

const pci_power_d3hot = u16(3)
const pci_power_pme_enable = u16(1) << 8
// What a function is given after it is told to change state, before it is
// spoken to again.
const pci_d3_settle_ms = u64(10)

__global (
	devcore_pci_d3_decided bool
	devcore_pci_d3_off     bool
	// Functions the last sleep put into D3hot, and all sleeps together;
	// those that would not go, and those that did not come back.
	devcore_pci_d3_last    u64
	devcore_pci_d3_total   u64
	devcore_pci_d3_refused u64
	devcore_pci_d3_stuck   u64
	// Registers the last wake from D3 found changed and wrote back.
	devcore_pci_d3_rewritten u64
)

// Whether functions are put into D3 for a sleep at all.
pub fn pci_d3_wanted() bool {
	if !devcore_pci_d3_decided {
		devcore_pci_d3_off = !boot_flag('vinix.pci_d3=', true)
		devcore_pci_d3_decided = true
	}
	return !devcore_pci_d3_off
}

// The power state a function is in by its own account: 0 to 3 for D0 to
// D3hot, or -1 for one that has no power management capability or is not
// there. A function without the capability is always in D0.
pub fn pci_power_state(p &pci.PCIDevice) int {
	power := p.capability(pci_cap_power)
	if power == 0 {
		return -1
	}
	control := p.read[u16](u32(power) + 4)
	if control == 0xffff {
		return -1
	}
	return int(control & pci_power_state_mask)
}

// Put every function that can come back from it into D3hot. Call with
// bindings frozen, after suspend_all() has succeeded. Nothing is done when
// there is nowhere to keep what the functions will forget.
pub fn pci_sleep_all() {
	devcore_pci_d3_last = 0
	devcore_pci_d3_rewritten = 0
	if !pci_d3_wanted() || !pci_save_all() {
		return
	}
	mut asked := 0
	for i := devcore_device_count - 1; i >= 0; i-- {
		mut dev := devcore_devices[i]
		if !dev.suspended || dev.state != .bound || dev.wakeup_enabled || !pci_function_present(dev) {
			continue
		}
		if dev.driver.suspend == unsafe { nil } || dev.driver.resume == unsafe { nil } {
			continue
		}
		saved := pci_saved_for(pci_bdf(dev.pci))
		if saved == unsafe { nil } {
			continue
		}
		power := saved.capability(pci_cap_power)
		if power == 0 {
			continue
		}
		control := dev.pci.read[u16](power + 4)
		if control == 0xffff || control & pci_power_state_mask != 0 {
			// Gone, or somewhere its driver or firmware put it.
			continue
		}
		// The status bit clears when written as one: a signal latched before
		// now is not one from this sleep.
		dev.pci.write[u16](power + 4, (control & ~(pci_power_state_mask | pci_power_pme_enable)) | pci_power_pme_status | pci_power_d3hot)
		dev.pci_asleep = true
		asked++
	}
	if asked == 0 {
		return
	}
	sleep_ms(pci_d3_settle_ms)
	for i := 0; i < devcore_device_count; i++ {
		mut dev := devcore_devices[i]
		if !dev.pci_asleep {
			continue
		}
		if pci_power_state(dev.pci) == int(pci_power_d3hot) {
			dev.d3_count++
			devcore_pci_d3_last++
			devcore_pci_d3_total++
			$if pci_d3_selftest ? {
				pci_forget(dev.pci)
			}
			continue
		}
		// It did not take the state. Whatever it made of the write, it is
		// told to be in D0, where its driver left it.
		dev.pci_asleep = false
		devcore_pci_d3_refused++
		saved := pci_saved_for(pci_bdf(dev.pci))
		if saved != unsafe { nil } {
			pci_wake_function(dev.pci, saved)
		}
		C.kprintf(c'devcore: %.*s would not go into D3; left in D0\n', i32(dev.name.len), dev.name.str)
	}
}

// Bring back what pci_sleep_all() put down, and give each function its
// configuration again. Called by resume_all() before the first driver's
// resume, so that whoever resumes the devices cannot forget it; does nothing
// when no function is down.
fn pci_wake_all() {
	mut patience := Deadline{}
	mut started := false
	// What is written back here is not the account of a suspend to RAM,
	// which pci_restore_report() gives.
	rewritten := devcore_pci_rewritten
	for i := 0; i < devcore_device_count; i++ {
		mut dev := devcore_devices[i]
		if !dev.pci_asleep {
			continue
		}
		dev.pci_asleep = false
		if !pci_function_present(dev) {
			continue
		}
		mut saved := pci_saved_for(pci_bdf(dev.pci))
		if saved == unsafe { nil } || saved.unrestored {
			// Found gone by the restore after a loss of power, which has
			// dealt with it.
			continue
		}
		if !started {
			patience = deadline(pci_answer_ns)
			started = true
		}
		if !pci_restore_function(dev.pci, saved, patience) {
			// Taken out while it slept, or changed for another: as after a
			// loss of power, nothing is written to it and its driver is not
			// asked to resume it.
			saved.unrestored = true
			dev.suspended = false
			devcore_pci_missing++
			C.kprintf(c'devcore: %.*s is gone or is not what it was; not woken from D3\n', i32(dev.name.len),
				dev.name.str)
			look_after_power_loss()
			continue
		}
		state := pci_power_state(dev.pci)
		if state > 0 {
			devcore_pci_d3_stuck++
			dev.suspended = false
			C.kprintf(c'devcore: %.*s did not come back from D3 (it says D%d)\n', i32(dev.name.len),
				dev.name.str, state)
			report_failure(mut dev, 'resume')
		}
	}
	devcore_pci_d3_rewritten = devcore_pci_rewritten - rewritten
	devcore_pci_rewritten = rewritten
}

// How many functions the last sleep put into D3hot, how many all sleeps did,
// how many would not go, how many did not come back, and how many registers
// the last wake found changed and wrote back.
pub fn pci_sleep_report() (u64, u64, u64, u64, u64) {
	return devcore_pci_d3_last, devcore_pci_d3_total, devcore_pci_d3_refused, devcore_pci_d3_stuck, devcore_pci_d3_rewritten
}

// What a function that keeps nothing across D3hot has lost by the time it
// is back in D0, done to it while it is down: its address registers, its
// command register and its interrupt line read zero. For a kernel built to
// test that all of it is put back (-d pci_d3_selftest) on a machine whose
// devices forget nothing, as QEMU's do not.
fn pci_forget(p &pci.PCIDevice) {
	p.write[u16](pci_command, 0)
	for word := 4; word <= 9; word++ {
		p.write[u32](u32(word * 4), 0)
	}
	p.write[u8](pci_interrupt_line, 0)
}
