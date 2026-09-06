// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module spi_keyboard

#include "apple_spi_keyboard.h"

fn C.vinix_apple_spi_touchpad_read(output &int) int

__global (
	apple_spi_touchpad_reported = false
	apple_spi_touchpad_cached   = false
	apple_spi_touchpad_cache    = [8]int{}
)

// The shared keyboard poller pumps BOTH devices. A pointer read only takes a
// snapshot; it must not steal SPI packets from the console keyboard path.
// output has 8 words: x, y, max_x, max_y, buttons, pressed, released, scroll.
//
// It must not wait for that poller either. The console path takes this same
// lock with a try-acquire and gives up the moment it loses, so a compositor
// reading the pointer once a frame and blocking here starves the very poller
// that produces the reports -- the cursor then moves in steps, the harder it
// is asked the worse it gets. The pointer device also holds its own lock
// across this call, so the wait would spin with interrupts already masked.
pub fn read_pointer(output &int) bool {
	if !apple_spi_keyboard_lock.test_and_acquire() {
		return replay_pointer(output)
	}
	defer { apple_spi_keyboard_lock.release() }
	if C.vinix_apple_spi_touchpad_read(output) == 0 {
		return false
	}
	if !apple_spi_touchpad_reported {
		apple_spi_touchpad_reported = true
		println('apple-spi-tp: first valid touchpad report received')
	}
	unsafe {
		for i := 0; i < 8; i++ {
			apple_spi_touchpad_cache[i] = output[i]
		}
	}
	apple_spi_touchpad_cached = true
	// Keep returning a final release after a transport failure disables the
	// keyboard poller. Dropping the device here could leave a drag stuck down.
	return true
}

// What the last read saw, for a caller that arrived while the poller held the
// lock. Position and held buttons still describe the device. The edges do not:
// `pressed`, `released` and `scroll` are each reported once, so repeating them
// would deliver a second click, or a second release, that nobody made.
fn replay_pointer(output &int) bool {
	if !apple_spi_touchpad_cached {
		return false
	}
	unsafe {
		for i := 0; i < 5; i++ {
			output[i] = apple_spi_touchpad_cache[i]
		}
		output[5] = 0
		output[6] = 0
		output[7] = 0
	}
	return true
}
