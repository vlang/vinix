// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the device core asks of an AHCI controller besides finding its disks:
// stop them before the machine powers off, put them down for a sleep and
// bring them back after it, and recover a port whose disk stopped answering.
//
// The four share one piece of machinery. A port is brought to a known state
// by stopping its command engine and resetting the link (COMRESET), after
// which the disk owns none of the port's memory and the port is programmed
// again from what the driver kept. That is what a resume needs, since the
// controller may have lost power and with it every register; and it is what
// recovery needs, since a command that timed out may still be in flight until
// the link is reset. The sequence and its timings follow Linux's libahci
// (ahci_do_hardreset, ahci_stop_engine, ahci_stop_fis_rx).
module ahci

import devcore

// Port registers the rest of the driver does not name.
const port_cmd_sud = u32(1) << 1
const port_cmd_pod = u32(1) << 2
const port_det_mask = u32(0xf)
const port_det_established = u32(3)
const port_tfd_busy = u32(0x88)

// The specification's bounds: 500 ms for the command list or FIS receive to
// stop, a millisecond of COMRESET, and a link that is coming up at all does so
// in well under a second. A disk may then take seconds to spin up before it
// stops reporting busy.
const engine_stop_ns = 500 * devcore.millisecond
const comreset_ns = devcore.millisecond
const link_up_ns = 2 * devcore.second
const ready_ns = 15 * devcore.second
const hba_reset_ns = devcore.second

const ata_standby_immediate = u8(0xe0)

fn port_command_stopped(context voidptr) bool {
	mut volatile regs := unsafe { &AHCIPortRegisters(context) }
	return regs.cmd & hba_cmd_cr == 0
}

fn port_fis_stopped(context voidptr) bool {
	mut volatile regs := unsafe { &AHCIPortRegisters(context) }
	return regs.cmd & hba_cmd_fr == 0
}

fn port_link_up(context voidptr) bool {
	mut volatile regs := unsafe { &AHCIPortRegisters(context) }
	return regs.ssts & port_det_mask == port_det_established
}

fn port_ready(context voidptr) bool {
	mut volatile regs := unsafe { &AHCIPortRegisters(context) }
	// All ones is a port that is not there any more, not a ready one.
	return regs.tfd != 0xffffffff && regs.tfd & port_tfd_busy == 0
}

fn hba_reset_done(context voidptr) bool {
	mut volatile regs := unsafe { &AHCIRegisters(context) }
	return regs.ghc & 1 == 0
}

// Stop the port issuing commands and receiving FISes. False when the
// controller would not stop, in which case it may still be writing to the
// port's memory.
fn (mut d AHCIDevice) stop_port() bool {
	mut volatile regs := d.regs
	regs.cmd &= ~u32(hba_cmd_st)
	if !devcore.spin_until(port_command_stopped, voidptr(d.regs), engine_stop_ns) {
		return false
	}
	regs.cmd &= ~u32(hba_cmd_fre)
	return devcore.spin_until(port_fis_stopped, voidptr(d.regs), engine_stop_ns)
}

// Reset the link and program the port again. Afterwards the disk has
// forgotten whatever it was doing and the port is as initialise() left it.
// The caller holds the disk's lock.
fn (mut d AHCIDevice) reset_port() bool {
	mut volatile regs := d.regs
	if !d.stop_port() {
		return false
	}
	regs.clb = u32(d.command_list)
	regs.clbu = u32(d.command_list >> 32)
	regs.fb = u32(d.fis_base)
	regs.fbu = u32(d.fis_base >> 32)
	regs.ie = 0
	regs.ints = u32(-1)
	regs.serr = u32(-1)
	// The first FIS a reset disk sends is its signature; the port has to be
	// receiving to take it. Power and spin-up are asked for where the
	// controller makes them the driver's business.
	regs.cmd |= port_cmd_pod | port_cmd_sud
	regs.cmd |= hba_cmd_fre

	control := regs.sstl & ~port_det_mask
	regs.sstl = control | 1
	devcore.stall(comreset_ns)
	regs.sstl = control
	if !devcore.spin_until(port_link_up, voidptr(d.regs), link_up_ns) {
		return false
	}
	regs.serr = u32(-1)
	if !devcore.spin_until(port_ready, voidptr(d.regs), ready_ns) {
		return false
	}
	regs.ints = u32(-1)
	return true
}

// A command that moves no data: FLUSH CACHE, STANDBY IMMEDIATE. The caller
// holds the disk's lock.
fn (mut d AHCIDevice) command_without_data(command u8) bool {
	slot := d.find_cmd_slot() or { return false }
	mut volatile regs := d.regs
	mut volatile header := unsafe {
		&AHCIHBACommand((u64(regs.clb) | (u64(regs.clbu) << 32)) + higher_half +
			slot * sizeof(AHCIHBACommand))
	}
	header.flags = u16(sizeof(AHCIFISh2d) / 4)
	header.prdtl = 0
	header.prdbc = 0
	mut volatile table := unsafe {
		&AHCIHBACommandTable((u64(header.ctba) | (u64(header.ctbau) << 32)) + higher_half)
	}
	mut volatile fis := unsafe { &AHCIFISh2d(&table.cfis) }
	unsafe { C.memset(fis, 0, sizeof(AHCIFISh2d)) }
	fis.fis_type = fis_reg_h2d
	fis.flags = 1 << 7
	fis.command = command
	return d.send_cmd(slot)
}

// Leave the disk safe to lose power: its cache written out, and the disk
// told to stop, which parks a hard disk's heads and lets a solid state one
// finish its own bookkeeping. Then the port is stopped. The caller holds the
// disk's lock.
fn (mut d AHCIDevice) put_down() {
	if !d.failed {
		if d.flush_command != 0 {
			d.command_without_data(d.flush_command)
		}
		if !d.failed {
			d.command_without_data(ata_standby_immediate)
		}
	}
	d.stop_port()
}

// Before power off or reset. Nothing is expected to work afterwards, and a
// request that arrives anyway is refused rather than started on a disk that
// has been told to stop.
fn controller_shutdown(mut dev devcore.Device) {
	mut controller := unsafe { &AHCIController(dev.driver_data) }
	for mut disk in controller.device_list {
		disk.l.acquire()
		disk.put_down()
		disk.failed = true
		disk.l.release()
	}
	mut volatile regs := controller.regs
	regs.ghc &= ~u32(1 << 1)
}

// For system sleep. Requests that arrive from here on wait for the resume
// (AHCIDevice.wait_awake()); the one in flight finishes first, as taking the
// lock waits for it.
fn controller_suspend(mut dev devcore.Device) bool {
	mut controller := unsafe { &AHCIController(dev.driver_data) }
	for mut disk in controller.device_list {
		disk.asleep = true
		disk.l.acquire()
		disk.put_down()
		disk.l.release()
	}
	mut volatile regs := controller.regs
	regs.ghc &= ~u32(1 << 1)
	return true
}

// After a sleep the controller may have been without power: it is reset and
// put back into AHCI mode, and each port is reset and programmed again. A
// disk that does not come back is marked failed, and its requests fail,
// rather than holding up the resume of the others.
fn controller_resume(mut dev devcore.Device) bool {
	mut controller := unsafe { &AHCIController(dev.driver_data) }
	dev.pci.enable_bus_mastering()
	mut volatile regs := controller.regs
	regs.ghc |= u32(1) << 31
	regs.ghc |= 1
	if !devcore.spin_until(hba_reset_done, voidptr(controller.regs), hba_reset_ns) {
		return false
	}
	regs.ghc |= u32(1) << 31
	regs.ghc &= ~u32(1 << 1)
	mut all := true
	for mut disk in controller.device_list {
		disk.l.acquire()
		if disk.reset_port() {
			disk.failed = false
		} else {
			disk.failed = true
			all = false
		}
		disk.asleep = false
		disk.l.release()
	}
	return all
}

// Recovery: reset the ports that stopped answering, or every port when the
// reset was asked for by hand and none had. A port that comes back takes
// requests again.
fn controller_reset(mut dev devcore.Device) bool {
	mut controller := unsafe { &AHCIController(dev.driver_data) }
	mut any_failed := false
	for disk in controller.device_list {
		if disk.failed {
			any_failed = true
		}
	}
	mut all := true
	for mut disk in controller.device_list {
		if any_failed && !disk.failed {
			continue
		}
		disk.l.acquire()
		if disk.reset_port() {
			disk.failed = false
		} else {
			disk.failed = true
			all = false
		}
		disk.l.release()
	}
	return all
}

// Hold a request until the disk is awake again. Called before the disk's
// lock is taken, by everything that sends it a command.
fn (mut d AHCIDevice) wait_awake() {
	for d.asleep {
		devcore.sleep_ms(10)
	}
}
