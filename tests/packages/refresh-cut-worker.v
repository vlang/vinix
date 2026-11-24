// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

#include <fcntl.h>
#include <unistd.h>

fn C.open(&char, int, ...int) int
fn C.write(int, voidptr, uint) int

fn checkpoint(progress pkgprotocol.Progress) {
	phase := match progress.phase {
		'verify' { if progress.repository == 'fixture' { 'fetched' } else { '' } }
		'history-committed' { 'history' }
		'complete' { 'catalog' }
		else { '' }
	}
	if phase != os.args[2] { return }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(&char(console.str), C.O_WRONLY)
	marker := 'PACKAGE REFRESH CUT ' + phase + '\n'
	if fd < 0 || C.write(fd, marker.str, uint(marker.len)) != marker.len {
		panic('cannot write refresh cut marker to the guest console')
	}
	// QEMU is killed here. The worker holds the writer lock and cannot run
	// deferred cleanup or issue any more writes.
	for { time.sleep(time.second) }
}

fn main() {
	if os.args.len != 3 || os.args[2] !in ['fetched', 'history', 'catalog'] {
		eprintln('use refresh-cut-worker ROOT fetched|history|catalog')
		exit(2)
	}
	mut catalog := pkgcore.Service{ root: os.args[1], offline: true, progress: checkpoint }.refresh_repository('fixture') or {
		eprintln(err)
		exit(1)
	}
	catalog.close()
	eprintln('refresh returned without reaching the selected cut point')
	exit(1)
}
