import os
import crypto.sha256
import json2
import compress.gzip

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, r.output
}

fn replace_once(body string, before string, after string) string {
	assert body.count(before) == 1, before
	return body.replace(before, after)
}

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	b := 'build/android-maps/'
	out := b + 'native231'
	assert !os.exists(out)
	os.mkdir_all(out)!
	os.cp_all(b + 'native229/atlframework', out + '/atlframework', false)!
	baseline := json2.decode[map[string]string](os.read_file(b + 'native229-sources.json')!)!
	for path in os.walk_ext(out + '/atlframework', '.v') {
		assert hash(path)! == baseline[os.base(path)]!, path
	}
	assert baseline['path_clipping.v']! == '5363c9d9431f1c830e1d04be52343b98bef516ee6b6b6bc7bcd2eeb5a34c99ef'
	mut runtime := os.read_file(out + '/atlframework/runtime.v')!
	runtime = replace_once(runtime, '\t\t\tws_input(e)\n', '\t\t\t// Rendering may leave the original Java exception pending. Input\n\t\t\t// dispatch uses JNI calls that are forbidden until it is reported.\n\t\t\tif !pending(e) { ws_input(e) }\n')
	assert runtime == os.read_file(b + 'native230/atlframework/runtime.v')!
	runtime = replace_once(runtime, '\t\tfor ws.running {\n', '\t\tfor ws.running {\n\t\t\tws_timing231_loop++\n\t\t\ttiming231_loop_start := ws_millis()\n\t\t\ttiming231_looper := ws_millis()\n')
	runtime = replace_once(runtime, "\t\t\tstatic_void(e, c'android/os/Looper', c'loop', c'()V', nil)\n", "\t\t\tstatic_void(e, c'android/os/Looper', c'loop', c'()V', nil)\n\t\t\tws_timing231_phase(c'looper', timing231_looper)\n")
	runtime = replace_once(runtime, '\t\t\tws_frames_dispatch()\n', "\t\t\ttiming231_frames := ws_millis()\n\t\t\tws_frames_dispatch()\n\t\t\tws_timing231_phase(c'frame_callbacks', timing231_frames)\n")
	runtime = replace_once(runtime, '\t\t\tif ws.dirty { ws_render(e) }\n', "\t\t\tif ws.dirty {\n\t\t\t\ttiming231_render := ws_millis()\n\t\t\t\tws_render(e)\n\t\t\t\tws_timing231_phase(c'render_total', timing231_render)\n\t\t\t}\n")
	runtime = replace_once(runtime, '\t\t\tif !pending(e) { ws_input(e) }\n', "\t\t\ttiming231_input := ws_millis()\n\t\t\tif !pending(e) { ws_input(e) }\n\t\t\tws_timing231_phase(c'input', timing231_input)\n\t\t\tws_timing231_phase(c'loop_total', timing231_loop_start)\n")
	os.write_file(out + '/atlframework/runtime.v', runtime)!
	mut views := os.read_file(out + '/atlframework/ws_views.v')!
	views = replace_once(views, '\t\tdecor := activity_decor(e, ws.activity)\n', '\t\ttiming231_attach := ws_millis()\n\t\tdecor := activity_decor(e, ws.activity)\n')
	views = replace_once(views, '\t\tws_attach_window(e, window, decor)\n', "\t\tws_attach_window(e, window, decor)\n\t\tws_timing231_phase(c'render_attach', timing231_attach)\n")
	views = replace_once(views, '\t\tmeasure := [Value{ i: ws.width | 0x40000000 }', '\t\ttiming231_measure := ws_millis()\n\t\tmeasure := [Value{ i: ws.width | 0x40000000 }')
	views = replace_once(views, "\t\tcall(e, decor, c'android/view/View', c'measure', c'(II)V', &measure[0])\n", "\t\tcall(e, decor, c'android/view/View', c'measure', c'(II)V', &measure[0])\n\t\tws_timing231_phase(c'render_measure', timing231_measure)\n")
	views = replace_once(views, '\t\tlayout := [Value{ i: 0 },', '\t\ttiming231_layout := ws_millis()\n\t\tlayout := [Value{ i: 0 },')
	views = replace_once(views, "\t\tcall(e, decor, c'android/view/View', c'layout', c'(IIII)V', &layout[0])\n", "\t\tcall(e, decor, c'android/view/View', c'layout', c'(IIII)V', &layout[0])\n\t\tws_timing231_phase(c'render_layout', timing231_layout)\n")
	views = replace_once(views, '\t\tif !ws_dispatch_traversal(e, window) { return }\n', "\t\ttiming231_traversal := ws_millis()\n\t\ttiming231_traversal_ok := ws_dispatch_traversal(e, window)\n\t\tws_timing231_phase(c'render_traversal', timing231_traversal)\n\t\tif !timing231_traversal_ok { return }\n")
	views = replace_once(views, '\t\tws_trace_tree(e, decor)\n', "\t\ttiming231_trace := ws_millis()\n\t\tws_trace_tree(e, decor)\n\t\tws_timing231_phase(c'render_trace', timing231_trace)\n")
	views = replace_once(views, "\t\tcall(e, decor, c'android/view/View', c'vinixDrawLayer', c'(Landroid/graphics/Canvas;)V', &args[0])\n", "\t\ttiming231_draw := ws_millis()\n\t\tcall(e, decor, c'android/view/View', c'vinixDrawLayer', c'(Landroid/graphics/Canvas;)V', &args[0])\n\t\tws_timing231_phase(c'render_draw', timing231_draw)\n")
	views = replace_once(views, '\tcount := C.read(ws.input, &event, sizeof(WsEvent))\n', "\tcount := C.read(ws.input, &event, sizeof(WsEvent))\n\tws_timing231_input_sequence++\n\ttiming231_sequence := ws_timing231_input_sequence\n\ttiming231_read := ws_millis()\n\tC.printf(c'WS-TIMING231 input_read loop=%zu sequence=%zu now_ms=%zu count=%d kind=%u x=%d y=%d value=%d length=%u magic=%x\\n', ws_timing231_loop, timing231_sequence, usize(timing231_read), i32(count), event.kind, event.x, event.y, event.value, event.length, event.magic)\n\tdefer { ws_timing231_input_done(timing231_sequence, timing231_read) }\n")
	os.write_file(out + '/atlframework/ws_views.v', views)!
	os.write_file(out + '/atlframework/timing231.v', "// Artifact-only runtime latency diagnostics. No JNI calls or dispatch changes.\n@[translated]\nmodule atlframework\n\n__global ws_timing231_loop usize\n__global ws_timing231_input_sequence usize\n\nfn ws_timing231_phase(phase &char, start i64) {\n\tnow := ws_millis()\n\tif now - start > 100 {\n\t\tC.printf(c'WS-TIMING231 phase loop=%zu name=%s duration_ms=%zu now_ms=%zu\\n', ws_timing231_loop, phase, usize(now - start), usize(now))\n\t}\n}\n\nfn ws_timing231_input_done(sequence usize, read_at i64) {\n\tmut descriptor := WsPoll{fd: ws.input, events: 1}\n\tready := C.poll(voidptr(&descriptor), 1, 0)\n\tnow := ws_millis()\n\tC.printf(c'WS-TIMING231 input_done loop=%zu sequence=%zu now_ms=%zu duration_ms=%zu ready=%d revents=%d running=%d\\n', ws_timing231_loop, sequence, usize(now), usize(now - read_at), ready, i32(descriptor.returned), i32(ws.running))\n}\n")!
	mut sources := map[string]string{}
	mut exact_sources := map[string]string{}
	mut changed := []string{}
	for path in os.walk_ext(out + '/atlframework', '.v') {
		name := os.base(path)
		sources[name] = hash(path)!
		exact_sources[name] = os.read_file(path)!
		if name in baseline && sources[name] != baseline[name]! { changed << name }
		if name !in ['runtime.v', 'ws_views.v', 'timing231.v'] {
			assert sources[name] == baseline[name]!, name
		}
	}
	changed.sort()
	assert changed == ['runtime.v', 'ws_views.v'], changed.str()
	assert sources.len == baseline.len + 1
	os.write_file(b + 'native231-sources.json', json2.encode(sources, prettify: true) + '\n')!
	os.write_file_array(b + 'native231-exact-sources.json.gz', gzip.compress(json2.encode(exact_sources).bytes())!)!
	for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(b + 'native229/' + header, out + '/' + header)!
	}
	os.setenv('VINIX_V_COMPILER', '/Users/alex/code/v/v_old', true)
	checked(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', 'run',
		'tests/linuxkpi/generate_module.v', out + '/atlframework', out + '/android-native.c', '--arch',
		'arm64'])
	runtime_root := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	checked(['aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden',
		'-shared', '-fPIC', '-I' + out, '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined',
		out + '/android-native.c', runtime_root + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed',
		runtime_root + '/usr/lib/libpng16.so.16', runtime_root + '/usr/lib/libsqlite3.so.0', '-ldl',
		'-lm', '-o', b + 'libnative231.so'])
	identity := 'NATIVE231 ' + hash(b + 'libnative231.so')!
	println(identity)
	os.write_file(b + 'native231-identity.txt', identity + '\n')!
}
