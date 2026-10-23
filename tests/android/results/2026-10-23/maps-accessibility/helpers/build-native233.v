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
	assert os.args.len == 2, 'usage: build-native233 <reviewed-notifications-sha256>'
	notification_sha := os.args[1]
	assert notification_sha.len == 64 && notification_sha.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
	b := 'build/android-maps/'
	out := b + 'native233'
	assert !os.exists(out) && !os.exists(b + 'libnative233.so')
	assert hash(b + 'libnative232.so')! == '2c749a6046515c663039d4123048c437a69d8509cdfb35d4e77c7742c089a8cc'
	assert hash(b + 'framework228-outline/api-impl.jar')! == '26b21262b67e92c77bcf57b9480bc881b0683ac0e8d6f97dba105ef453f3fe5a'
	baseline := json2.decode[map[string]string](os.read_file(b + 'native232-sources.json')!)!
	assert baseline.len == 82
	for path in os.walk_ext(b + 'native232/atlframework', '.v') {
		assert hash(path)! == baseline[os.base(path)]!, 'frozen232 source changed: ' + path
	}
	assert os.walk_ext(b + 'native232/atlframework', '.v').len == baseline.len
	notifications := os.read_file('build-support/android/nativews/notifications.v')!
	assert sha256.sum(notifications.bytes()).hex() == notification_sha, 'notification fix is not the reviewed source'
	assert notification_sha != baseline['notifications.v']!
	production_views := os.read_file('build-support/android/nativews/ws_views.v')!
	assert strip_timing(os.read_file(b + 'native232/atlframework/ws_views.v')!) == production_views, 'stripped232 views must remain byteexact production'
	guard_runtime := os.read_file(b + 'native230/atlframework/runtime.v')!
	assert strip_timing(os.read_file(b + 'native232/atlframework/runtime.v')!) == guard_runtime, 'stripped232 runtime must retain exact230 guard'
	assert guard_runtime == os.read_file('build-support/android/nativews/runtime.v')!, 'production runtime must retain exact230 guard'
	os.mkdir_all(out)!
	os.cp_all(b + 'native232/atlframework', out + '/atlframework', false)!
	os.write_file(out + '/atlframework/notifications.v', notifications)!
	mut hashes := map[string]string{}
	mut exact := map[string]string{}
	mut changed := []string{}
	mut paths := os.walk_ext(out + '/atlframework', '.v')
	paths.sort()
	for path in paths {
		name := os.base(path)
		assert name !in hashes, 'source basename collision'
		hashes[name] = hash(path)!
		exact[name] = os.read_file(path)!
		if hashes[name] != baseline[name]! { changed << name }
	}
	assert changed == ['notifications.v'], changed.str()
	assert hashes.len == 82
	assert strip_timing(exact['ws_views.v']!) == production_views
	assert strip_timing(exact['runtime.v']!) == guard_runtime
	os.write_file(b + 'native233-sources.json', json2.encode(hashes, prettify: true) + '\n')!
	os.write_file_array(b + 'native233-exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	production_receipt := {
		'baseline_native232_sha256': hash(b + 'libnative232.so')!
		'baseline_sources_sha256': hash(b + 'native232-sources.json')!
		'framework228_sha256': hash(b + 'framework228-outline/api-impl.jar')!
		'notifications.v': notification_sha
		'ws_views.v': sha256.sum(production_views.bytes()).hex()
		'runtime.v': sha256.sum(guard_runtime.bytes()).hex()
	}
	os.write_file(b + 'native233-production-source-sha256.json', json2.encode(production_receipt, prettify: true) + '\n')!
	for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(b + 'native232/' + header, out + '/' + header)!
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
		'-lm', '-o', b + 'libnative233.so'])
	identity := 'NATIVE233 ' + hash(b + 'libnative233.so')!
	println(identity)
	os.write_file(b + 'native233-identity.txt', identity + '\n')!
}
