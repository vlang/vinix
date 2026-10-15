// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type ASPlay = fn (u32)
type ASShow = fn (u64)
type ASFile = fn (u64, u64)
type ASNew = fn (&u64) i32
type ASAdd = fn (u64, &AudioDescription, &i32) i32
type ASStep = fn (u64) i32
type ASProbe = fn (u64, u64, u64, &u64)
struct ASApi { native bool play u64 show u64 file u64 new_graph ASNew add ASAdd open ASStep initialize ASStep start ASStep stop ASStep uninitialize ASStep drop ASStep }
fn as_api(native bool) ASApi {
	$if macos { if native {
		lib := C.dlopen(c'/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox', 2); assert lib != unsafe { nil }
		return ASApi{native: true, play: u64(C.dlsym(lib, c'AudioServicesPlaySystemSound')), show: u64(C.dlsym(lib, c'CAShow')), file: u64(C.dlsym(lib, c'CAShowFile')),
			new_graph: unsafe { ASNew(C.dlsym(lib, c'NewAUGraph')) }, add: unsafe { ASAdd(C.dlsym(lib, c'AUGraphAddNode')) },
			open: unsafe { ASStep(C.dlsym(lib, c'AUGraphOpen')) }, initialize: unsafe { ASStep(C.dlsym(lib, c'AUGraphInitialize')) },
			start: unsafe { ASStep(C.dlsym(lib, c'AUGraphStart')) }, stop: unsafe { ASStep(C.dlsym(lib, c'AUGraphStop')) },
			uninitialize: unsafe { ASStep(C.dlsym(lib, c'AUGraphUninitialize')) }, drop: unsafe { ASStep(C.dlsym(lib, c'DisposeAUGraph')) }}
	} }
	return ASApi{play: runtime_symbol('/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox', '_AudioServicesPlaySystemSound') or { panic(err) },
		show: runtime_symbol('/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox', '_CAShow') or { panic(err) },
		file: runtime_symbol('/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox', '_CAShowFile') or { panic(err) },
		new_graph: audio_graph_new, add: audio_graph_add, open: audio_graph_open, initialize: audio_graph_initialize,
		start: audio_graph_start, stop: audio_graph_stop, uninitialize: audio_graph_uninitialize, drop: audio_graph_dispose}
}
fn as_vibrate(api ASApi) {
	for _ in 0 .. 32 { unsafe { ASPlay(voidptr(api.play))(4095) } }
}
fn as_vibration_cases(api ASApi, code u64, guard u64) {
	assert api.play != 0 && api.show != 0 && api.file != 0
	// No result register belongs to a void API. Only preserved registers and
	// capture boundaries are checked; all unused arguments/x8 are protected.
	for value in [u64(4095), u64(0xdeadbeef00000fff)]! {
		mut capture := [u64(0xcafe), 0, 0, 0, 0xbeef]!
		unsafe { ASProbe(voidptr(code))(api.play, value, guard, &capture[1]) }
		assert capture[0] == 0xcafe && capture[2] == guard && capture[3] == 0x1234 && capture[4] == 0xbeef
	}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn as_vibrate(api) }
	workers.wait(); unsafe { workers.free() }
}
fn as_snapshot(api ASApi, graph u64) string {
	stream := C.tmpfile(); assert stream != unsafe { nil }
	file := if api.native { u64(stream) } else { stdio_wrap(stream) }
	unsafe { ASFile(voidptr(api.file))(graph, file) }
	assert C.fflush(stream) == 0 && C.fseek(stream, 0, 0) == 0
	mut bytes := [16384]u8{}
	count := C.fread(unsafe { &bytes[0] }, 1, 16383, stream); assert count > 0 && count < 16383
	text := unsafe { tos_clone(&bytes[0]) }
	if api.native { assert C.fclose(stream) == 0 } else { assert darwin_fclose(file) == 0 }
	return text
}
fn as_graph_reader(api ASApi, graph u64) {
	for _ in 0 .. 8 { text := as_snapshot(api, graph); assert text.contains("node 1: 'auou' 'genr' 'appl'") && text.contains('isInitialized=F, isRunning=F'); unsafe { text.free() } }
}
fn as_graph_cases(api ASApi) {
	mut graph := u64(0); assert api.new_graph(&graph) == 0 && graph != 0
	initial := as_snapshot(api, graph); assert initial.contains('AudioUnitGraph 0x') && initial.contains('Member Nodes:') && !initial.contains('node 1:') && initial.contains('isInitialized=F, isRunning=F'); unsafe { initial.free() }
	description := AudioDescription{0x61756f75, 0x67656e72, 0x6170706c, 0, 0}; mut node := i32(0)
	assert api.add(graph, &description, &node) == 0 && node == 1
	for stage in 0 .. 6 {
		status := match stage { 0 { i32(0) } 1 { api.open(graph) } 2 { api.initialize(graph) } 3 { api.start(graph) } 4 { api.stop(graph) } else { api.uninitialize(graph) } }
		assert status == 0
		text := as_snapshot(api, graph)
		assert text.contains("node 1: 'auou' 'genr' 'appl'")
		assert text.contains(if stage in [2, 3, 4]! { 'isInitialized=T' } else { 'isInitialized=F' })
		assert text.contains(if stage == 3 { 'isRunning=T' } else { 'isRunning=F' })
		unsafe { text.free() }
	}
	// The void default sink is callable without changing graph state. Native
	// CAShow uses os_log; the private runtime's diagnostic sink is stderr.
	unsafe { ASShow(voidptr(api.show))(graph) }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn as_graph_reader(api, graph) }
	workers.wait(); unsafe { workers.free() }
	assert api.drop(graph) == 0
	if !api.native { assert ios_runtime.audio_graphs.len == 0 && ios_runtime.audio_units.len == 0 && system_data.streams.len == 3 }
}
fn as_private_graph_cases(guard u64) {
	assert !audio_show_graph_native(guard, voidptr(guard)) && !audio_show_graph_native(0, voidptr(guard))
	mut graph := u64(0); assert audio_graph_new(&graph) == 0
	mut a := i32(0); mut b := i32(0)
	description := audio_description(1) or { panic('output') }; mixer := audio_description(2) or { panic('mixer') }
	assert audio_graph_add(graph, &description, &a) == 0 && audio_graph_add(graph, &mixer, &b) == 0
	assert audio_graph_connect(graph, a, 0, b, 0) == 0
	before := *ios_runtime.audio_graphs[graph]
	text := as_snapshot(as_api(false), graph)
	assert text.contains("node 2: 'aumx' 'mcmx' 'appl'") && text.contains('connection: node 1 output 0 -> node 2 input 0')
	unsafe { text.free() }
	assert *ios_runtime.audio_graphs[graph] == before
	readonly := C.fopen(c'/dev/null', c'r'); assert readonly != unsafe { nil }
	assert !audio_show_graph_native(graph, readonly) && C.ferror(readonly) != 0; assert C.fclose(readonly) == 0
	assert audio_graph_dispose(graph) == 0 && !audio_show_graph_native(graph, voidptr(guard))
}
fn as_child(mode string) {
	objc_start(); system_data_start() or { panic(err) }
	if mode == 'sound' { audio_play_system_sound(1000); exit(0) }
	guard := C.mmap(unsafe { nil }, usize(C.getpagesize()), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert guard != voidptr(-1)
	if mode == 'graph' { audio_ca_show(u64(guard)); exit(0) }
	mut graph := u64(0); assert audio_graph_new(&graph) == 0
	audio_ca_show_file(graph, u64(guard)); exit(0)
}
fn as_rejections() {
	for mode in ['sound', 'graph', 'file']! {
		mut p := os.new_process(os.executable()); p.set_redirect_stdio_merged()
		mut env := os.environ(); env['VINIX_IOS_AUDIO_SERVICES_CHILD'] = mode; p.set_environment(env)
		p.run(); log := p.stdout_slurp(); p.wait(); code := p.code; p.close()
		assert code != 0 && log.contains(match mode { 'sound' { 'unsupported SystemSoundID' } 'graph' { 'CAShow requires a live AUGraph' } else { 'invalid Darwin FILE pointer' } })
		assert !log.contains('ERROR: AddressSanitizer') && !log.contains('runtime error:')
		unsafe { log.free() }
	}
}
fn test_audio_services() {
	mode := os.getenv('VINIX_IOS_AUDIO_SERVICES_CHILD'); if mode != '' { as_child(mode); return }
	page := usize(C.getpagesize()); code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert code != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 }
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xaa0203e8, 0xaa0203f4, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5, 0xaa0203e6, 0xaa0203e7, 0xd2824695, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, voidptr(u64(code) + 88)); guard := u64(code) + u64(page)
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		api := as_api(true); as_vibration_cases(api, u64(code), guard); as_graph_cases(api)
		println('IOS-AUDIO-SERVICES-NATIVE: uint32 void vibration ABI, guarded unused arguments, preserved contexts, concurrent calls, real AUGraph node/state diagnostics and concurrent FILE snapshots')
	}
	as_rejections()
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }
		api := as_api(false); as_vibration_cases(api, u64(code), guard); as_graph_cases(api); as_private_graph_cases(guard)
		for name in ['_AudioServicesPlaySystemSound', '_CAShow', '_CAShowFile']! { for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/AudioUnit.framework/AudioUnit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, name) { assert false } } }
		assert ios_runtime.audio_graphs.len == 0 && ios_runtime.audio_units.len == 0 && system_data.streams.len == 3
		objc_stop(); assert ios_runtime.live == 0; system_data_stop(); assert system_data == unsafe { nil }
	}
	println('IOS-AUDIO-SERVICES: no-actuator vibration profile, explicit rejection of other sounds, live-graph diagnostics, Darwin FILE translation, real graph flags/connections, protected foreign/stale handles, write failures and two drained runtimes')
}
