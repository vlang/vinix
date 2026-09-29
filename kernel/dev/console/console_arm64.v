@[has_globals]
module console

import sched
import aarch64.uart
import aarch64.virtio_input
import aarch64.virtio_net
import dev.e1000
import socket.inet
import apple.wifi
import apple.spi_keyboard
import flanterm as _

// Poll UART, VirtIO and the built-in Apple SPI keyboard into the console.
// Called from the scheduler's await() loop to avoid needing a separate thread.
pub fn poll_uart_input() {
	// Networking shares the scheduler's idle poll path with input devices, so
	// blocking socket operations keep hardware, DHCP and TCP timers moving.
	virtio_net.poll()
	e1000.poll()
	inet.poll()
	c := uart.getc()
	if c >= 0 {
		mut byte_val := u8(c)
		if byte_val == 0x7f {
			byte_val = `\b`
		}
		add_to_buf(&byte_val, 1, true)
	}
	// Poll virtio keyboard
	virtio_input.poll()
	if vi_outlen > 0 {
		add_to_buf(&vi_outbuf[0], vi_outlen, true)
		vi_outlen = 0
	}

	// The driver releases its lock before entering the console/termios path.
	mut apple_input := [128]u8{}
	apple_count := spi_keyboard.poll(&apple_input[0], u64(apple_input.len), console_decckm)
	if apple_count > 0 {
		add_to_buf(&apple_input[0], u64(apple_count), true)
	}
	wifi.poll()
}

pub fn initialise() {
	C.flanterm_set_callback(flanterm_ctx, voidptr(flanterm_callback))

	setup_console()

	// Initialize only after console/termios setup and before polling starts.
	spi_keyboard.initialise()
	wifi.initialise()

	// Register UART polling callback with the scheduler's await() loop.
	// Under HVF, IRQ injection is broken, so we can't use a separate
	// UART polling thread (it would starve all other threads).
	sched.set_uart_poll_callback(voidptr(poll_uart_input))
}

// Caps Lock is kept by whichever keyboard toggled it: VirtIO and USB share one
// state, the built-in Apple keyboard has its own.
fn caps_lock_on() bool {
	return vi_caps_active || spi_keyboard.caps_lock()
}

// What the console shows goes to the UART as well.
fn mirror_to_serial(buf voidptr, count u64) {
	uart.write(charptr(buf), count)
}
