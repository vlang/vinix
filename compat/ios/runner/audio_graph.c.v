// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct AudioGraphNode {
mut:
	component u64
	unit u64
	sources [16]i32 // 1-based node ID; zero means disconnected.
	callbacks [16]AudioCallback
}

struct AudioGraph {
mut:
	nodes [16]AudioGraphNode
	count i32
	opened bool
	initialized bool
	running bool
}

fn audio_graph_new(result &u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if result == unsafe { nil } { return -50 }
	mut graph := unsafe { &AudioGraph(C.calloc(1, sizeof(AudioGraph))) }
	if graph == unsafe { nil } { unsafe { *result = 0 }; return -108 }
	ios_runtime.audio_graphs[u64(graph)] = graph
	unsafe { *result = u64(graph) }
	return 0
}

fn audio_graph_busy(graph &AudioGraph) bool {
	for index in 0 .. graph.count {
		if unit := ios_runtime.audio_units[graph.nodes[index].unit] { if unit.rendering { return true } }
	}
	return false
}

fn audio_graph_dispose(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if audio_graph_busy(graph) { return -10863 }
	// A unit outside this graph may also hold a connection to one of its units.
	for _, unit in ios_runtime.audio_units {
		if unit.graph == handle { continue }
		for index in 0 .. unit.input_count {
			if source := ios_runtime.audio_units[unit.inputs[index].source] { if source.graph == handle { return -10863 } }
		}
	}
	for index in 0 .. graph.count {
		if found := ios_runtime.audio_units[graph.nodes[index].unit] {
			mut unit := unsafe { &AudioUnit(found) }
			audio_unit_free_buffers(mut unit)
			ios_runtime.audio_units.delete(u64(unit))
			C.free(unit)
		}
	}
	ios_runtime.audio_graphs.delete(handle)
	C.free(graph)
	return 0
}

fn audio_graph_add(handle u64, description &AudioDescription, result &i32) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if description == unsafe { nil } || result == unsafe { nil } { return -50 }
	if graph.opened || graph.count == 16 { return -10863 }
	component := audio_component_find(0, description)
	if component == 0 { return -3000 }
	graph.nodes[graph.count].component = component
	graph.count++
	unsafe { *result = graph.count }
	return 0
}

fn audio_graph_open(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if graph.opened { return 0 }
	for index in 0 .. graph.count {
		status := audio_unit_new(graph.nodes[index].component, unsafe { &graph.nodes[index].unit })
		if status != 0 {
			for previous in 0 .. index { audio_unit_dispose(graph.nodes[previous].unit); graph.nodes[previous].unit = 0 }
			return status
		}
	}
	for index in 0 .. graph.count {
		mut unit := ios_runtime.audio_units[graph.nodes[index].unit] or { return -10864 }
		unit.graph = handle
		for bus in 0 .. 16 {
			source := graph.nodes[index].sources[bus]
			unit.inputs[bus].source = if source == 0 { u64(0) } else { graph.nodes[source - 1].unit }
			unit.inputs[bus].callback = graph.nodes[index].callbacks[bus]
		}
	}
	graph.opened = true
	return 0
}

fn audio_graph_info(handle u64, node i32, description &AudioDescription, result &u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if node < 1 || node > graph.count { return -50 }
	if description == unsafe { nil } && result == unsafe { nil } { return -50 }
	if description != unsafe { nil } { audio_component_description(graph.nodes[node - 1].component, description) }
	if result != unsafe { nil } { unsafe { *result = graph.nodes[node - 1].unit } }
	return 0
}

fn audio_graph_reaches(graph &AudioGraph, source i32, target i32, depth int) bool {
	if source == target || depth >= 16 { return true }
	for input in graph.nodes[source - 1].sources {
		if input != 0 && audio_graph_reaches(graph, input, target, depth + 1) { return true }
	}
	return false
}

fn audio_graph_connect(handle u64, source i32, output u32, target i32, input u32) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if source < 1 || source > graph.count || target < 1 || target > graph.count { return -10860 }
	if graph.initialized || audio_graph_busy(graph) { return -10863 }
	if output != 0 || input >= 16 || (graph.nodes[target - 1].component == 1 && input != 0) { return -10861 }
	if audio_graph_reaches(graph, source, target, 0) { return -10861 }
	if graph.opened {
		mut unit := ios_runtime.audio_units[graph.nodes[target - 1].unit] or { return -10864 }
		if input >= unit.input_count { return -10861 }
		unit.inputs[input].source = graph.nodes[source - 1].unit
		unit.inputs[input].callback = AudioCallback{}
	}
	graph.nodes[target - 1].sources[input] = source
	graph.nodes[target - 1].callbacks[input] = AudioCallback{}
	return 0
}

fn audio_graph_callback(handle u64, node i32, input u32, callback &AudioCallback) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if node < 1 || node > graph.count { return -10860 }
	if callback == unsafe { nil } { return -50 }
	if input >= 16 || (graph.nodes[node - 1].component == 1 && input != 0) { return -10861 }
	if audio_graph_busy(graph) { return -10863 }
	if graph.opened {
		mut unit := ios_runtime.audio_units[graph.nodes[node - 1].unit] or { return -10864 }
		if input >= unit.input_count { return -10861 }
		unit.inputs[input].callback = *callback
		unit.inputs[input].source = 0
	}
	graph.nodes[node - 1].callbacks[input] = *callback
	graph.nodes[node - 1].sources[input] = 0
	return 0
}

fn audio_graph_initialize(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if !graph.opened { return -10867 }
	if graph.initialized { return 0 }
	for index in 0 .. graph.count {
		status := audio_unit_initialize(graph.nodes[index].unit)
		if status != 0 {
			for previous in 0 .. index { audio_unit_uninitialize(graph.nodes[previous].unit) }
			return status
		}
	}
	graph.initialized = true
	return 0
}

fn audio_graph_uninitialize(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if audio_graph_busy(graph) { return -10863 }
	for index in 0 .. graph.count { if graph.nodes[index].unit != 0 { audio_unit_uninitialize(graph.nodes[index].unit) } }
	graph.initialized = false
	graph.running = false
	return 0
}

fn audio_graph_start(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if !graph.initialized { return -10867 }
	mut outputs := 0
	for index in 0 .. graph.count { if graph.nodes[index].component == 1 { outputs++ } }
	if outputs != 1 { return -10862 }
	for index in 0 .. graph.count {
		if graph.nodes[index].component == 1 {
			status := audio_output_start(graph.nodes[index].unit)
			if status != 0 { return status }
		}
	}
	graph.running = true
	return 0
}

fn audio_graph_stop(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut graph := ios_runtime.audio_graphs[handle] or { return -50 }
	for index in 0 .. graph.count { if graph.nodes[index].component == 1 && graph.nodes[index].unit != 0 { audio_output_stop(graph.nodes[index].unit) } }
	graph.running = false
	return 0
}

fn audio_graph_is_running(handle u64, result &u8) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	graph := ios_runtime.audio_graphs[handle] or { return -50 }
	if result == unsafe { nil } { return -50 }
	unsafe { *result = u8(graph.running) }
	return 0
}

fn audio_graphs_stop() {
	for _, graph in ios_runtime.audio_graphs { C.free(graph) }
	unsafe { ios_runtime.audio_graphs.free() }
}

fn audio_graph_symbol(symbol string) ?u64 {
	address := match symbol {
		'_NewAUGraph' { unsafe { voidptr(audio_graph_new) } }
		'_DisposeAUGraph' { unsafe { voidptr(audio_graph_dispose) } }
		'_AUGraphAddNode' { unsafe { voidptr(audio_graph_add) } }
		'_AUGraphOpen' { unsafe { voidptr(audio_graph_open) } }
		'_AUGraphNodeInfo' { unsafe { voidptr(audio_graph_info) } }
		'_AUGraphConnectNodeInput' { unsafe { voidptr(audio_graph_connect) } }
		'_AUGraphSetNodeInputCallback' { unsafe { voidptr(audio_graph_callback) } }
		'_AUGraphInitialize' { unsafe { voidptr(audio_graph_initialize) } }
		'_AUGraphUninitialize' { unsafe { voidptr(audio_graph_uninitialize) } }
		'_AUGraphStart' { unsafe { voidptr(audio_graph_start) } }
		'_AUGraphStop' { unsafe { voidptr(audio_graph_stop) } }
		'_AUGraphIsRunning' { unsafe { voidptr(audio_graph_is_running) } }
		else { return none }
	}
	return u64(address)
}
