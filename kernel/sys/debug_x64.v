module sys

import debug
import io

fn new_debug_e9port() debug.Sink {
	return debug.Sink {
		name: 'e9port'
		line_consumer: debug_e9port_consumer
	}
}

fn debug_e9port_consumer(msg string) {
	for i := 0; i < msg.len; i++ {
		io.outb(0xe9, msg.str[i])
	}
	io.outb(0xe9, `\n`)
}

fn new_debug_dmesg_ring() debug.Sink {
	return debug.Sink {
		name: 'dmesg_ring',
		line_consumer: debug_dmesg_ring_consumer
	}
}

fn debug_dmesg_ring_consumer(msg string) {
	fbcon_println(msg)
}