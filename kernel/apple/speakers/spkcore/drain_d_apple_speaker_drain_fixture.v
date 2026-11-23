// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module spkcore

const simulated_shutdown_gpio = u64(1)

// Only the simulated amplifier shutdown pin is available to the controller.
__global (
	drain_test_gpio u32
	write_test_pcm [8]i16
)

fn drain_test_read(_ voidptr, address u64) u32 {
	if address != simulated_shutdown_gpio {
		panic('unexpected read in Apple speaker drain fixture')
	}
	return drain_test_gpio
}

fn drain_test_write(_ voidptr, address u64, value u32) {
	if address != simulated_shutdown_gpio || value & 1 != 0 {
		panic('unexpected write in Apple speaker drain fixture')
	}
	drain_test_gpio = value
}

pub fn begin_drain_test() {
	drain_test_gpio = 1
	spk_controller = Speakers{}
	spk_controller.state = st_idle
	spk_controller.cfg.shutdown_gpio = simulated_shutdown_gpio
	spk_controller.io.read32 = drain_test_read
	spk_controller.io.write32 = drain_test_write
}

pub fn drain_test_shutdown_asserted() bool {
	return drain_test_gpio & 1 == 0
}

pub fn end_drain_test() {
	spk_controller = Speakers{}
}

fn write_test_now(_ voidptr) u64 {
	return 1
}

pub fn begin_write_test() {
	begin_drain_test()
	write_test_pcm = [8]i16{}
	spk_controller.cfg.tx_buffer = unsafe { u64(&write_test_pcm[0]) }
	spk_controller.tx_ring = u32(sizeof(write_test_pcm))
	spk_controller.io.now_us = write_test_now
	spk_controller.volume = 100
}

pub fn write_test_prefix_matches(input &i16) bool {
	if spk_controller.written != sizeof(write_test_pcm) || spk_controller.reserved != 0 {
		return false
	}
	for index, sample in write_test_pcm {
		if sample != unsafe { input[index] } {
			return false
		}
	}
	return true
}
