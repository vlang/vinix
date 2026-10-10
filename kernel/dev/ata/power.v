// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// An IDE controller and its drives across a sleep.
//
// This driver keeps nothing in the controller between requests: every
// transfer programs the bus-master registers and the drive's task file from
// scratch, and every write is followed by a cache flush. So there is little
// to do, and what there is concerns timing. Going down, each drive's request
// in flight is let finish and later ones are held (ATADrive.wait_awake()).
// Coming back -- after a suspend to RAM the device core has already put the
// controller's configuration space back, its bus-master registers' address
// with it -- the controller is allowed to master the bus again and each
// drive is waited for: one that lost power spins up before it takes a
// command, which is seconds on a disk that turns.
@[has_globals]
module ata

import devcore
import x86.kio

// How long a drive may take over one command. The slowest it has is the
// cache flush, for which the standard allows thirty seconds.
const command_timeout_ns = 30 * devcore.second
// How long a drive may take to be ready after its power came back.
const spin_up_ns = 10 * devcore.second

__global (
	ata_drives      [4]&ATADrive
	ata_drive_count int
)

fn remember_drive(drive &ATADrive) {
	if ata_drive_count < 4 {
		ata_drives[ata_drive_count] = unsafe { drive }
		ata_drive_count++
	}
}

// Wait for the drive to finish the command it was given. False if it says
// the command failed, or has not finished in the time a drive is allowed:
// a drive that is gone reads as busy for ever.
fn (dev &ATADrive) finished() bool {
	limit := devcore.deadline(command_timeout_ns)
	for {
		status := kio.port_in[u8](dev.cmd_port)
		if status & 0x80 == 0 {
			return true
		}
		if status & 0x01 != 0 || limit.expired() {
			return false
		}
	}
	return false
}

// Hold a request until the drive is awake again. Called before the drive's
// lock is taken.
fn (dev &ATADrive) wait_awake() {
	for dev.asleep {
		devcore.sleep_ms(10)
	}
}

fn drive_ready(context voidptr) bool {
	dev := unsafe { &ATADrive(context) }
	status := kio.port_in[u8](dev.cmd_port)
	// Not busy, and ready; all ones is no drive at all.
	return status != 0xff && status & 0x80 == 0 && status & 0x40 != 0
}

fn controller_suspend(mut core devcore.Device) bool {
	for i in 0 .. ata_drive_count {
		mut drive := ata_drives[i]
		drive.asleep = true
		// The request in flight holds the lock until it is done.
		drive.l.acquire()
		drive.l.release()
	}
	return true
}

fn controller_resume(mut core devcore.Device) bool {
	core.pci.enable_bus_mastering()
	mut all := true
	for i in 0 .. ata_drive_count {
		mut drive := ata_drives[i]
		kio.port_out[u8](drive.device_port, if drive.is_master { u8(0xa0) } else { u8(0xb0) })
		if !devcore.sleep_until(drive_ready, voidptr(drive), spin_up_ns, 10) {
			C.kprintf(c'ata: drive %lld did not come back from the sleep\n', i64(i))
			all = false
		}
		// Awake either way: a drive that did not come back fails its
		// requests by their own timeout instead of holding them for ever.
		drive.asleep = false
	}
	return all
}
