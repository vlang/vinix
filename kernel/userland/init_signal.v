// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

import proc

// Send init `signal`, but only if it has a handler for it: the default action
// of most signals would kill it, and the kernel asking init for something
// must not be what takes the system down. True if the signal was sent.
pub fn signal_init_if_handled(signal int) bool {
	if signal <= 0 || signal > 64 {
		return false
	}
	mut target := proc.pin_process_at(1)
	if target == unsafe { nil } {
		return false
	}
	defer {
		proc.unpin_process(target)
	}
	if target.threads.len == 0 {
		return false
	}
	handler := target.threads[0].sigactions[signal].sa_sigaction
	if handler == sig_dfl || handler == sig_ign {
		return false
	}
	signal_process(mut target, signal)
	return true
}
