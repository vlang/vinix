// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

$if package_enrollment_crash_fixture ? {
	fn enrollment_cut_checkpoint(phase string) {
		scenario := os.read_file('/etc/hwtest-scenario') or { panic(err) }
		if scenario.trim_space() != 'enrollment-cut-' + phase { return }
		console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
		fd := C.openat(C.AT_FDCWD, console.str, C.O_WRONLY)
		marker := 'PACKAGE ENROLLMENT CUT ' + phase + '\n'
		if fd < 0 || C.write(fd, marker.str, uint(marker.len)) != marker.len {
			panic('cannot write enrollment cut marker to the guest console')
		}
		// QEMU is killed while the CLI still holds the writer lock.
		for { time.sleep(time.second) }
	}
}
