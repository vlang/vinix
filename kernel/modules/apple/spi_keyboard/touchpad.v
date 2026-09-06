// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module spi_keyboard

#include "apple_spi_keyboard.h"

fn C.vinix_apple_spi_touchpad_read(output &int) int

__global (
	apple_spi_touchpad_reported = false
)

// The shared keyboard poller pumps BOTH devices. A pointer read only takes a
// snapshot; it must not steal SPI packets from the console keyboard path.
// output has 8 words: x, y, max_x, max_y, buttons, pressed, released, scroll.
pub fn read_pointer(output &int) bool {
	apple_spi_keyboard_lock.acquire()
	defer { apple_spi_keyboard_lock.release() }
	if C.vinix_apple_spi_touchpad_read(output) == 0 {
		return false
	}
	if !apple_spi_touchpad_reported {
		apple_spi_touchpad_reported = true
		println('apple-spi-tp: first valid touchpad report received')
	}
	// Keep returning a final release after a transport failure disables the
	// keyboard poller. Dropping the device here could leave a drag stuck down.
	return true
}
