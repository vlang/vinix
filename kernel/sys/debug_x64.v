module sys

import io

fn new_debug_e9port() DebugSink {
	return DebugSink {
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
