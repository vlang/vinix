// SPDX-License-Identifier: GPL-2.0-or-later
module userland

import proc

// Linux force_sig_seccomp reports the rejected call and filter data, and
// forces the default disposition when SIGSYS was ignored or blocked.
pub fn force_seccomp_signal(mut t proc.Thread, nr u64, address u64, data u32) {
	t.seccomp_signal = proc.SeccompSignal{
		pending: true
		data: data
		syscall: u32(nr)
		address: address
	}
	bit := signal_bit(31)
	if t.sigactions[31].sa_sigaction == sig_ign || t.masked_signals & bit != 0 {
		t.sigactions[31].sa_sigaction = sig_dfl
		t.masked_signals &= ~bit
	}
	sendsig(&t, u8(31))
}

fn take_seccomp_signal(mut t proc.Thread, signum int, shared bool) proc.SeccompSignal {
	if shared || signum != 31 || !t.seccomp_signal.pending { return proc.SeccompSignal{} }
	info := t.seccomp_signal
	t.seccomp_signal.pending = false
	return info
}
