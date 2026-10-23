import os
import crypto.sha256
import json2
import compress.gzip

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, r.output
}

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn strip_timing(body string) string {
	mut lines := []string{}
	for line in body.split('\n') {
		if line.contains('timing231_traversal_ok := ws_dispatch_traversal') {
			lines << '\t\tif !ws_dispatch_traversal(e, window) { return }'
		} else if line.contains('timing231') || line.contains('WS-TIMING231') {
			continue
		} else {
			lines << line
		}
	}
	return lines.join('\n').replace('\t\t\tif ws.dirty {\n\t\t\t\tws_render(e)\n\t\t\t}\n', '\t\t\tif ws.dirty { ws_render(e) }\n')
}

fn main() {
	b := 'build/android-maps/'
	out := b + 'native232'
	assert !os.exists(out)
	assert hash(b + 'libnative231.so')! == 'c6ef185c72eb3203dac3dbc373c044fd4867f0b19f861a844dd959d35a904693'
	baseline := json2.decode[map[string]string](os.read_file(b + 'native231-sources.json')!)!
	before := 'fn ws_input(e voidptr) {\n\tif ws.input < 0 { return }\n\tmut descriptor := WsPoll{ fd: ws.input, events: 1 }\n\tif C.poll(voidptr(&descriptor), 1, 0) <= 0 { return }\n'
	after := 'fn ws_input(e voidptr) {\n\tif ws.input < 0 { return }\n\t// Drain a bounded batch so queued movement cannot postpone button-up\n\t// and subsequent input behind a separate rendered frame per record.\n\tfor _ in 0 .. 64 {\n\t\tif !ws.running || pending(e) { return }\n\t\tmut descriptor := WsPoll{ fd: ws.input, events: 1 }\n\t\tif C.poll(voidptr(&descriptor), 1, 0) <= 0 { return }\n\t\tunsafe { if FramePush(slot(e, 19))(e, 128) < 0 { return } }\n\t\tws_input_event(e)\n\t\tpop_frame(e)\n\t}\n}\n\n// A separate call releases each text payload stack buffer before the next event.\nfn ws_input_event(e voidptr) {\n'
	production_before := os.read_file(b + 'native229/atlframework/ws_views.v')!
	assert production_before.count(before) == 1
	production_after := os.read_file('build-support/android/nativews/ws_views.v')!
	assert production_after == production_before.replace(before, after), 'production must contain only the bounded input-drain delta from frozen229'
	os.mkdir_all(out)!
	os.cp_all(b + 'native231/atlframework', out + '/atlframework', false)!
	for path in os.walk_ext(out + '/atlframework', '.v') {
		assert hash(path)! == baseline[os.base(path)]!, path
	}
	views := os.read_file(out + '/atlframework/ws_views.v')!
	assert views.count(before) == 1
	instrumented_after := views.replace(before, after)
	assert strip_timing(instrumented_after) == production_after, 'stripped diagnostic view source must exactly equal production'
	assert strip_timing(os.read_file(out + '/atlframework/runtime.v')!) == os.read_file(b + 'native230/atlframework/runtime.v')!, 'stripped runtime must equal exact pending-input guard source'
	os.write_file(out + '/atlframework/ws_views.v', instrumented_after)!
	mut hashes := map[string]string{}
	mut exact := map[string]string{}
	mut changed := []string{}
	for path in os.walk_ext(out + '/atlframework', '.v') {
		name := os.base(path)
		hashes[name] = hash(path)!
		exact[name] = os.read_file(path)!
		if hashes[name] != baseline[name]! { changed << name }
	}
	assert changed == ['ws_views.v'], changed.str()
	assert hashes.len == baseline.len
	os.write_file(b + 'native232-sources.json', json2.encode(hashes, prettify: true) + '\n')!
	os.write_file_array(b + 'native232-exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	os.write_file(b + 'native232-production-source-sha256.txt', sha256.sum(production_after.bytes()).hex() + '\n')!
	for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(b + 'native231/' + header, out + '/' + header)!
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
		'-lm', '-o', b + 'libnative232.so'])
	identity := 'NATIVE232 ' + hash(b + 'libnative232.so')!
	println(identity)
	os.write_file(b + 'native232-identity.txt', identity + '\n')!
}
