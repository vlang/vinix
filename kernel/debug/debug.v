module debug

pub struct Sink {
mut:
	name string
	line_consumer fn(string)
}

__global sinks [32]debug.Sink

pub fn printk(msg string) {
	// V compiler is broken (no .len for static sized arrays)
	for i := 0; i < 32; i++ {
		sink_val := &sinks[i]
		
		if voidptr(sink_val.line_consumer) != voidptr(0) {
			hack := sink_val.line_consumer
			hack(msg)
		}
	}
}

pub fn register_sink(sink Sink) {
	// V compiler is broken
	for i := 0; i < 32; i++ {
		mut sink_val := &sinks[i]
		
		if sink_val.name.len == 0 {
			sink_val.name = sink.name
			sink_val.line_consumer = sink.line_consumer
			break
		}
	}
}
