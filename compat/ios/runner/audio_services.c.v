// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn audio_play_system_sound(sound u32) {
	// kSystemSoundID_Vibrate explicitly does nothing on hardware without a
	// vibration actuator. Vinix currently has no such backend. Other IDs need
	// a system-sound registry and playback backend before they can be accepted.
	if sound != 4095 { panic('iOS: unsupported SystemSoundID; only vibration without an actuator is implemented') }
}

fn audio_show_fourcc(value u32, output &u8) {
	unsafe {
		output[0] = u8(value >> 24)
		output[1] = u8(value >> 16)
		output[2] = u8(value >> 8)
		output[3] = u8(value)
		output[4] = 0
	}
}

fn audio_show_write(stream voidptr, buffer &u8, length int, capacity int) bool {
	return length >= 0 && length < capacity && C.fwrite(buffer, 1, usize(length), stream) == usize(length)
}

// Only registry-owned AUGraphs are inspected. Keep their units alive under
// the same recursive lock used by graph mutation and disposal; never read a
// foreign object or a stale handle as an Apple/private C++ object.
fn audio_show_graph_native(handle u64, stream voidptr) bool {
	if ios_runtime == unsafe { nil } || stream == unsafe { nil } { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	graph := ios_runtime.audio_graphs[handle] or { return false }
	mut buffer := [512]u8{}
	mut length := C.snprintf(unsafe { &char(&buffer[0]) }, 512, c'AudioUnitGraph 0x%llX:\n  Member Nodes:\n', handle)
	if !audio_show_write(stream, unsafe { &buffer[0] }, length, 512) { return false }
	for i in 0 .. graph.count {
		node := unsafe { &graph.nodes[i] }
		description := audio_description(node.component) or { return false }
		mut kind := [5]u8{}; mut subtype := [5]u8{}; mut manufacturer := [5]u8{}
		audio_show_fourcc(description.kind, unsafe { &kind[0] })
		audio_show_fourcc(description.subtype, unsafe { &subtype[0] })
		audio_show_fourcc(description.manufacturer, unsafe { &manufacturer[0] })
		length = C.snprintf(unsafe { &char(&buffer[0]) }, 512, c'\tnode %d: \'%s\' \'%s\' \'%s\', instance 0x%llX\n',
			i32(i + 1), unsafe { &kind[0] }, unsafe { &subtype[0] }, unsafe { &manufacturer[0] }, node.unit)
		if !audio_show_write(stream, unsafe { &buffer[0] }, length, 512) { return false }
		for bus, source in node.sources {
			if source == 0 { continue }
			length = C.snprintf(unsafe { &char(&buffer[0]) }, 512, c'\tconnection: node %d output 0 -> node %d input %d\n', source, i32(i + 1), i32(bus))
			if !audio_show_write(stream, unsafe { &buffer[0] }, length, 512) { return false }
		}
	}
	// This graph subset has no deferred AUGraphUpdate operations. Initialization
	// and running flags reflect the current graph, rather than causing playback.
	length = C.snprintf(unsafe { &char(&buffer[0]) }, 512, c'  CurrentState:\n\tmLastUpdateError=0, eventsToProcess=F, isInitialized=%c, isRunning=%c\n',
		if graph.initialized { i32(`T`) } else { i32(`F`) }, if graph.running { i32(`T`) } else { i32(`F`) })
	return audio_show_write(stream, unsafe { &buffer[0] }, length, 512)
}

fn audio_ca_show(handle u64) {
	if !audio_show_graph_native(handle, C.ios_host_stdio(2)) { panic('iOS: CAShow requires a live AUGraph and writable diagnostic stream') }
}

fn audio_ca_show_file(handle u64, file u64) {
	if system_data == unsafe { nil } { panic('iOS: CAShowFile requires initialized Darwin stdio') }
	if !audio_show_graph_native(handle, stdio_native(file)) { panic('iOS: CAShowFile requires a live AUGraph and writable diagnostic stream') }
}

fn audio_services_symbol(symbol string) ?u64 {
	return match symbol {
		'_AudioServicesPlaySystemSound' { u64(unsafe { voidptr(audio_play_system_sound) }) }
		'_CAShow' { u64(unsafe { voidptr(audio_ca_show) }) }
		'_CAShowFile' { u64(unsafe { voidptr(audio_ca_show_file) }) }
		else { none }
	}
}
