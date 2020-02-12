module sys

struct DebugSink {
mut:
	name string
	line_consumer fn(string)
}

pub fn printk(msg string) {
	// V compiler is broken (no .len for static sized arrays)
	for i := 0; i < 8; i++ {
		// V compiler is broken (arrays are broken)
		sink_val := &DebugSink(u64(kernel.devices.debug_sinks) + u64(i) * u64(sizeof(DebugSink)))

		if voidptr(sink_val.line_consumer) != nullptr {
			// V compiler is broken (trying to call functions from struct members results in some weird C code)
			hack := sink_val.line_consumer
			hack(msg)
		}
	}
}

fn (kernel &VKernel) init_debug() {

}


pub fn (kernel &VKernel) register_debug_sink(sink DebugSink) {
	// V compiler is broken
	for i := 0; i < 8; i++ {
		// V compiler is broken
		mut sink_val := &DebugSink(u64(kernel.devices.debug_sinks) + u64(i) * u64(sizeof(DebugSink)))
		
		if sink_val.name.len == 0 {
			// V compiler is broken
			sink_val.name = sink.name
			sink_val.line_consumer = sink.line_consumer
			break
		}
	}
}

fn new_debug_dmesg_ring() DebugSink {
	return DebugSink {
		name: 'dmesg_ring',
		line_consumer: debug_dmesg_ring_consumer
	}
}

fn debug_dmesg_ring_consumer(msg string) {
	fbcon_println(msg)
}
