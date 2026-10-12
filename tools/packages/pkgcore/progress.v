// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

fn no_progress(_ pkgprotocol.Progress) {}

fn transfer_size(path string) u64 {
	return if os.is_file(path) { os.file_size(path) } else { u64(0) }
}

// Borrowed event strings are valid during the callback; retaining observers
// clone them. Monitoring reaps the transfer child before returning on any error.
fn monitor_transfer(mut process os.Process, destination string, maximum u64, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) ! {
	for process.is_alive() {
		bytes := transfer_size(destination)
		if bytes > maximum {
			process.signal_kill()
			process.wait()
			os.rm(destination)!
			return error('download exceeded its authenticated size limit')
		}
		report(pkgprotocol.Progress{ ...event, current: bytes })
		time.sleep(200 * time.millisecond)
	}
	process.wait()
	bytes := transfer_size(destination)
	if bytes > maximum {
		os.rm(destination)!
		return error('download exceeded its authenticated size limit')
	}
	report(pkgprotocol.Progress{ ...event, current: bytes })
	if process.code != 0 { return error('download failed (${process.code}); retained partial data for retry') }
}
