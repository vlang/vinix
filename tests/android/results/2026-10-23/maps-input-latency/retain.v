import os
import json2
import crypto.sha256
import compress.gzip

struct Inputs {
	variant                     string
	native_variant              string
	framework_jar               string
	native_source_files         int
	native_sources_sha256       map[string]string
	additional_native_sha256    map[string]string
	files_sha256                map[string]string
	staged_runtime_sha256       map[string]string
	inherited_receipts_sha256   map[string]string
	scope                       string
}

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn copy_file(source string, target string) ! {
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
}

fn retain_inputs(out string, b string, version string, native_version string, framework_jar string) ! {
	run := b + 'attempt' + version
	dest := out + '/' + version
	os.mkdir_all(dest)!
	manifest := json2.decode[map[string]string](os.read_file(b + 'native' + native_version + '-sources.json')!)!
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'native' + native_version + '-exact-sources.json.gz')!)!.bytestr())!
	assert sources.len == manifest.len
	assert 'timing231.v' in sources && 'runtime.v' in sources && 'ws_views.v' in sources
	for name, source in sources {
		assert sha256.sum(source.bytes()).hex() == manifest[name], name
		assert hash(b + 'native' + native_version + '/atlframework/' + name)! == manifest[name], name
	}
	mut extra := map[string]string{}
	for name in ['android-native.c', 'androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		extra[name] = hash(b + 'native' + native_version + '/' + name)!
	}
	mut files := map[string]string{}
	for path in ['libnative' + native_version + '.so', 'GoogleMaps.apk', 'GooglePlayServices.apk',
		'GooglePlayStore.apk', framework_jar, 'suite159', 'launcher200'] {
		files[path] = hash(b + path)!
	}
	mut staged := map[string]string{}
	for path in ['opt/android-test/native-guest',
		'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session'] {
		staged[path] = hash(run + '/module/' + path)!
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == files['libnative' + native_version + '.so']
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == files[framework_jar]
	mut inherited := map[string]string{}
	for path in ['../render-node-outline/receipt.json', '../maps-ws/attempt218-runtime-identities.json'] {
		inherited[path] = hash(out + '/' + path)!
	}
	for source, name in {
		b + 'native' + native_version + '-sources.json': 'native-sources-sha256.json'
		b + 'native' + native_version + '-exact-sources.json.gz': 'native-exact-sources.json.gz'
		b + 'native' + native_version + '-identity.txt': 'native-identity.txt'
		b + 'build-native' + native_version + '.v': 'build-native.v'
		b + 'prepare' + version + '.v': 'prepare.v'
		b + 'run' + version + '.v': 'run.v'
		b + 'interact' + version + '.v': 'interact.v'
		b + 'attempt' + version + '.json': 'configuration.json'
	} {
		copy_file(source, dest + '/' + name)!
	}
	production_manifest := b + 'native' + native_version + '-production-source-sha256.json'
	if os.exists(production_manifest) {
		copy_file(production_manifest, dest + '/native-production-source-sha256.json')!
	}
	os.write_file_array(dest + '/native-build.log.gz', gzip.compress(os.read_bytes(b + 'native' + native_version + '-build.log')!)!)!
	os.write_file(dest + '/inputs.json', json2.encode(Inputs{
		variant: version
		native_variant: native_version
		framework_jar: framework_jar
		native_source_files: sources.len
		native_sources_sha256: manifest
		additional_native_sha256: extra
		files_sha256: files
		staged_runtime_sha256: staged
		inherited_receipts_sha256: inherited
		scope: 'Exact native V text and staged runtime identities. The reused maps-live-vm boot image, kernel, and EFI variables were not hashed before this run. Framework228 source/DEX identities are inherited from the adjacent committed outline receipt; later framework changes require their own receipt. Build-helper text is captured at retention time; the verified exact native archive identifies the compiled inputs.'
	}, prettify: true) + '\n')!
	println('MAPS-INPUT-LATENCY-INPUTS ' + version + ' PASS sources=' + sources.len.str() + ' staged=' + staged.len.str())
}

fn retain_result(out string, b string, version string) ! {
	dest := out + '/' + version
	run := b + 'attempt' + version
	assert os.exists(dest + '/inputs.json'), 'Retain inputs while the staging module still exists'
	copy_file(run + '/results.json', dest + '/results.json')!
	copy_file(run + '/companion-packages.json', dest + '/companion-packages.json')!
	app := run + '/google-maps'
	serial := os.read_bytes(app + '/serial.log')!
	if os.exists(app + '/serial.log.gz') {
		assert gzip.decompress(os.read_bytes(app + '/serial.log.gz')!)! == serial
	}
	os.write_file_array(dest + '/serial.log.gz', gzip.compress(serial)!)!
	for name in os.ls(app)! {
		if name in ['serial.log', 'serial.log.gz'] { continue }
		if os.file_ext(name) in ['.png', '.log', '.txt', '.json'] || name == 'qemu.pid' {
			copy_file(app + '/' + name, dest + '/' + name)!
		}
	}
	for name in ['attempt' + version + '-harness.log', 'interact' + version + '.log',
		'attempt' + version + '-timeline.log', 'pan' + version + '.log',
		'manual' + version + '.v', 'keys' + version + '.v', 'zoom' + version + '.v',
		'trace-input.v'] {
		if os.exists(b + name) { copy_file(b + name, dest + '/' + name)! }
	}
	if os.exists(app + '/network.pcap') {
		os.write_file(dest + '/network-pcap-sha256.txt', hash(app + '/network.pcap')! + '\n')!
	}
	if os.exists(out + '/../input-drain/receipt.json') {
		os.write_file(out + '/host-proof-receipt-sha256.txt', hash(out + '/../input-drain/receipt.json')! + '\n')!
	}
	if os.exists(out + '/../notification-cancel/receipt.json') {
		os.write_file(out + '/notification-proof-receipt-sha256.txt', hash(out + '/../notification-cancel/receipt.json')! + '\n')!
	}
	println('MAPS-INPUT-LATENCY-RESULT ' + version + ' PASS raw results/serial/screens/logs retained')
}

fn main() {
	assert os.args.len in [3, 5] && os.args[1] in ['231', '232', '233'] && os.args[2] in ['inputs', 'result'], 'usage: retain.v 231|232|233 inputs|result [native-variant framework-jar-relative-to-build/android-maps]'
	out := os.dir(@FILE)
	b := 'build/android-maps/'
	if os.args[2] == 'inputs' {
		native_version := if os.args.len == 5 { os.args[3] } else { os.args[1] }
		framework_jar := if os.args.len == 5 { os.args[4] } else { 'framework228-outline/api-impl.jar' }
		retain_inputs(out, b, os.args[1], native_version, framework_jar)!
	}
	else { retain_result(out, b, os.args[1])! }
	mut artifacts := map[string]string{}
	for path in os.walk_ext(out, '') {
		name := path.all_after(out + '/')
		if name !in ['receipt.json', 'validation.log', 'retain', 'validate'] {
			artifacts[name] = hash(path)!
		}
	}
	os.write_file(out + '/receipt.json', json2.encode(artifacts, prettify: true) + '\n')!
}
