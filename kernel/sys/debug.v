module sys

struct DebugSink {
mut:
	name string
	line_consumer fn(string)
}

pub fn printk(msg string) {
	outs := kernel.devices.debug_sinks

	for i := 0; i < 8; i++ {
		if outs[i].name.len != 0 && voidptr(outs[i].line_consumer) != nullptr {
			outs[i].line_consumer(msg)
		}
	}
}

fn (kernel &VKernel) init_debug() {

}


pub fn (kernel &VKernel) register_debug_sink(sink DebugSink) {
	mut sink_list := kernel.devices.debug_sinks

	for i := 0; i < 8; i++ {
		mut sink_val := sink_list[i]

		if sink_val.name.len == 0 {
			// V sucks, we need to copy the fields manually...
			sink_val.name = sink.name
			sink_val.line_consumer = sink.line_consumer
			
			break
		}
	}
}

fn debug_dmesg_ring_new() DebugSink {
	return DebugSink {
		name: 'dmesg_ring',
		line_consumer: debug_dmesg_ring_consumer
	}
}

fn debug_dmesg_ring_consumer(msg string) {

}