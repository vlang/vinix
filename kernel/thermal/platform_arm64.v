// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the architecture itself brings to thermal management. On arm64 that
// is nothing: there is no register every CPU has that reads its temperature
// or its energy, so a machine's sensors are its own drivers' to register --
// Apple's SMC, a device tree's thermal zones -- through register_zone().
module thermal

fn platform_start() {
}

// Whether the polling thread has anything of the platform's to look after.
fn platform_polls() bool {
	return false
}

fn platform_poll() {
}

// The power the processor package drew over the last polling interval, in
// milliwatts. None here: no counter says.
pub fn package_power_mw() ?u64 {
	return none
}
