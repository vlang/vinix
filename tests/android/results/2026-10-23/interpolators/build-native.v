import os
import crypto.sha256
import json2
import compress.gzip

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, r.output
}

fn main() {
	assert os.args.len == 2, 'usage: build-native235 <reviewed-overlay-sha256.json>'
	b := 'build/android-maps/'
	out := b + 'native235'
	assert !os.exists(out) && !os.exists(b + 'libnative235.so'), 'immutable output already exists'
	assert hash(b + 'libnative233.so')! == 'e94ca96bf9809c65392741964e3dcab985d17a5ae660c4d5fef46ef5cb19bd04'
	assert hash(b + 'framework234-interpolators/api-impl.jar')! == '643d292a4c862ca09bcf1f9c0579ad9c077ad8d1b477ed3a33d3ff1ac8300c13'
	baseline := json2.decode[map[string]string](os.read_file(b + 'native233-sources.json')!)!
	base_source := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'native233-exact-sources.json.gz')!)!.bytestr())!
	assert baseline.len == 82 && base_source.len == baseline.len
	for name, source in base_source {
		assert sha256.sum(source.bytes()).hex() == baseline[name]!, name
		assert hash(b + 'native233/atlframework/' + name)! == baseline[name]!, name
	}
	reviewed := json2.decode[map[string]string](os.read_file(os.args[1])!)!
	assert reviewed.len == 4
	expected := ['path_animation.v', 'path_animation_curves.v', 'path_curves.v', 'paths.v']
	mut overlays := map[string]string{}
	for path, digest in reviewed {
		assert path.starts_with('build-support/android/nativews/') && os.base(path) in expected, path
		assert os.base(path) !in overlays, path
		assert hash(path)! == digest, 'overlay differs from reviewed source: ' + path
		overlays[os.base(path)] = os.read_file(path)!
		assert sha256.sum(overlays[os.base(path)].bytes()).hex() == digest, 'overlay changed while freezing: ' + path
	}
	os.mkdir_all(out + '/atlframework')!
	for name, source in base_source {
		os.write_file(out + '/atlframework/' + name, source)!
	}
	for name, source in overlays {
		os.write_file(out + '/atlframework/' + name, source)!
	}
	mut hashes := map[string]string{}
	mut exact := map[string]string{}
	mut delta := map[string]string{}
	mut changed := []string{}
	mut paths := os.walk_ext(out + '/atlframework', '.v')
	paths.sort()
	for path in paths {
		name := os.base(path)
		assert name !in hashes, name
		hashes[name] = hash(path)!
		exact[name] = os.read_file(path)!
		if name !in baseline || hashes[name] != baseline[name] {
			changed << name
			delta[name] = if name in baseline {
				baseline[name] + ' -> ' + hashes[name]
			} else {
				'new -> ' + hashes[name]
			}
		}
	}
	assert changed == expected, changed.str()
	assert hashes.len == 83
	for name in ['ws_views.v', 'runtime.v', 'timing231.v', 'notifications.v'] {
		assert hashes[name]! == baseline[name]!, name
	}
	os.write_file(b + 'native235-sources.json', json2.encode(hashes, prettify: true) + '\n')!
	os.write_file_array(b + 'native235-exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	os.write_file(b + 'native235-source-delta.json', json2.encode(delta, prettify: true) + '\n')!
	mut identities := {
		'baseline_native233_sha256':        hash(b + 'libnative233.so')!
		'baseline_sources_sha256':          hash(b + 'native233-sources.json')!
		'baseline_exact_sources_sha256':    hash(b + 'native233-exact-sources.json.gz')!
		'framework234_sha256':              hash(b + 'framework234-interpolators/api-impl.jar')!
		'reviewed_overlay_manifest_sha256': hash(os.args[1])!
	}
	for path, digest in reviewed { identities[path] = digest }
	for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(b + 'native233/' + header, out + '/' + header)!
		assert hash(out + '/' + header)! == hash(b + 'native233/' + header)!, header
		identities['header/' + header] = hash(out + '/' + header)!
	}
	os.write_file(b + 'native235-production-source-sha256.json', json2.encode(identities,
		prettify: true
	) + '\n')!
	println('NATIVE235-SOURCES PASS83 exact sources; four reviewed overlays; all timing/runtime/input/notification sources unchanged')
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
		'-lm', '-o', b + 'libnative235.so'])
	identity := 'NATIVE235 ' + hash(b + 'libnative235.so')!
	println(identity)
	os.write_file(b + 'native235-identity.txt', identity + '\n')!
}
