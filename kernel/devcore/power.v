// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What a driver's resume may ask about the sleep it is resuming from.
//
// Most devices are untouched by a suspend to idle and blank after a suspend
// to RAM. A driver that always sets its device up from nothing in resume --
// the AHCI and e1000 drivers do -- need not know which it was. One whose
// device is what wakes the machine from a suspend to idle, and must be left
// alone then, asks.
@[has_globals]
module devcore

__global (
	devcore_power_lost bool
)

// Whoever carried out the sleep says whether the devices lost power in it,
// before resume_all(), and takes it back after.
pub fn set_power_lost(lost bool) {
	devcore_power_lost = lost
}

// Whether the machine is coming back from a sleep in which the devices were
// without power. Only meaningful inside a resume callback.
pub fn power_lost() bool {
	return devcore_power_lost
}
