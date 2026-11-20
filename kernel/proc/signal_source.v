// SPDX-License-Identifier: GPL-2.0-or-later
module proc

// Who sent a pending signal, as its siginfo_t reports it: si_code, si_pid and
// si_uid as the receiving process numbers them, and si_value for the queued
// kinds. kill and pidfd_send_signal record SI_USER, tkill and tgkill
// SI_TKILL, and rt_sigqueueinfo, rt_tgsigqueueinfo and pidfd_send_signal
// with a siginfo the caller's own fields. Vinix keeps one pending instance of
// each signal, and with it one sender; see posixtimer.record_thread_source.
pub struct SignalSource {
pub mut:
	code  i32
	pid   i32
	uid   u32
	value u64
}

pub const si_user = 0
pub const si_queue = -1
pub const si_tkill = -6
