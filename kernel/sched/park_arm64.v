// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module sched

// No sleep on this architecture powers processors down, so none is ever
// taken out of the scheduler; see park_amd64.v.
@[inline]
fn parking(_ u64) bool {
	return false
}
