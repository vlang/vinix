import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt220/'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn without_badging(value json2.Any) json2.Any {
	if value is map[string]json2.Any {
		mut result := map[string]json2.Any{}
		for key, item in value {
			if key != 'badging' { result[key] = without_badging(item) }
		}
		return result
	}
	if value is []json2.Any {
		mut result := []json2.Any{}
		for item in value { result << without_badging(item) }
		return result
	}
	return value
}

fn main() {
	raw := os.read_file(run + 'results.json')!
	mut row := without_badging(json2.decode[[]json2.Any](raw)![0]).as_map()
	serial := gzip.decompress(os.read_bytes(run + 'google-maps/serial.log.gz')!)!
	assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
	log := serial.bytestr()
	assert row['outcome']!.str() == 'startup_failed' && row['backend_ready']!.bool()
	assert log.count('ANDROID-WS-TRANSITION-FUTURE done=1') == 3
	assert log.contains('No virtual method getContentCaptureSession()Landroid/view/contentcapture/ContentCaptureSession;')
	assert log.contains('ANDROID-WS-TRANSITION-FUTURE-FAIL')
	mut messages := 0
	mut samples := []string{}
	for line in log.split_into_lines() {
		if line.starts_with('ANDROID-WS-QUEUE index=') {
			assert line.contains('barrier=0')
			messages++
		}
		if line.starts_with('ANDROID-WS-QUEUE-BEGIN') { samples << line.trim_space() }
	}
	assert samples.len == 3 && messages > 0
	mut artifacts := map[string]json2.Any{}
	for source, name in {
		run + 'google-maps/serial.log.gz': 'attempt220-google-maps-serial.log.gz'
		run + 'google-maps/initial.png': 'attempt220-google-maps-initial.png'
		run + 'google-maps/skip.png': 'attempt220-google-maps-skip.png'
		run + 'google-maps/skip-later.png': 'attempt220-google-maps-skip-later.png'
		run + 'google-maps/skip-second.png': 'attempt220-google-maps-skip-second.png'
		run + 'google-maps/application.png': 'attempt220-google-maps-application.png'
		base + 'attempt220.json': 'attempt220-configuration.json'
		base + 'attempt220-harness.log': 'attempt220-harness.log'
		base + 'interact220.log': 'attempt220-interaction.log'
		base + 'interact220.v': 'attempt220-interaction.v'
		base + 'run220.v': 'attempt220-run.v'
		base + 'prepare220.v': 'attempt220-prepare.v'
		base + 'build-native219.v': 'attempt220-native-build.v'
		base + 'queue220.v': 'queue220.v'
		base + 'native220-sources.json': 'native220-sources.json'
		base + 'retain220.v': 'retain220.v'
	} {
		os.cp(source, dest + name)!
		artifacts[name] = hash(dest + name)!
	}
	manifest := json2.decode[map[string]string](os.read_file(base + 'native220-sources.json')!)!
	mut source_texts := map[string]string{}
	paths := os.walk_ext(base + 'native218/atlframework', '.v')
	assert paths.len == manifest.len
	for path in paths {
		name := os.base(path)
		assert hash(path)! == manifest[name]!
		source_texts[name] = os.read_file(path)!
	}
	assert hash(base + 'queue220.v')! == manifest['queue219.v']!
	archive := 'attempt220-native-sources.json.gz'
	os.write_file_array(dest + archive, gzip.compress(json2.encode(source_texts).bytes())!)!
	restored := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dest + archive)!)!.bytestr())!
	assert restored.len == manifest.len
	for name, source in restored { assert sha256.sum(source.bytes()).hex() == manifest[name]! }
	artifacts[archive] = hash(dest + archive)!
	mut staged := map[string]json2.Any{}
	for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
		staged[path] = hash(run + 'module/' + path)!
	}
	native := staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str()
	assert native == hash(base + 'libnative220.so')!
	assert native.starts_with('d4a08') && native.ends_with('2809')
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == 'acd7c4ca1ab2447f528879b2ecc8533d38129627f50e867cc8a586b557978593'
	prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt218-runtime-identities.json')!)!
	prior_staged := prior['staged_runtime_sha256']!.as_map()
	for path, value in staged {
		if !path.ends_with('api-impl.jar') && !path.ends_with('libvinix-android-native.so') {
			assert value.str() == prior_staged[path]!.str()
		}
	}
	inputs := prior['input_files_sha256']!.as_map()
	assert row['metadata']!.as_map()['apk_sha256']!.str() == inputs[base + 'GoogleMaps.apk']!.str()
	for entry in row['companion_packages']!.as_array() {
		companion := entry.as_map()
		assert companion['metadata']!.as_map()['apk_sha256']!.str() == inputs[companion['apk']!.str()]!.str()
	}
	row['run'] = 'attempt220'
	row['startup_ui_passed'] = false
	row['search_passed'] = false
	row['manual_review'] = 'All retained screenshots still show onboarding. Future is completed in all three bounded samples; sample3 get() exposes NoSuchMethodError View.getContentCaptureSession during app-view attachment. The operator reports an additional successful click tool invocation around 13:27 local time; skip-second.png is retained but there is no persistent second-click tool log or synchronized event timestamp. It is not established which click caused the transition failure. Map/search remain unverified.'
	row['screenshot'] = 'attempt220-google-maps-application.png'
	row['serial_log'] = 'attempt220-google-maps-serial.log.gz'
	row['initial_screenshot'] = 'attempt220-google-maps-initial.png'
	row['skip_screenshot'] = 'attempt220-google-maps-skip.png'
	row['later_screenshot'] = 'attempt220-google-maps-skip-later.png'
	row['second_skip_screenshot'] = 'attempt220-google-maps-skip-second.png'
	row['badging_omission'] = 'Only metadata badging strings recursively omitted; remaining result fields retained.'
	os.write_file(dest + 'attempt220-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
	artifacts['attempt220-results.json'] = hash(dest + 'attempt220-results.json')!
	receipt := {
		'artifacts_sha256': json2.Any(artifacts)
		'staged_runtime_sha256': json2.Any(staged)
		'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
		'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
		'shared_input_identity_scope': json2.Any('Signed Maps/GMS/Store APK identities verified from result metadata against attempt218 verified inputs. Same launcher and staged launch components. Kernel/base identity remains inherited and unmeasured for this attempt.')
		'native_source_archive': json2.Any(archive)
		'native_source_scope': json2.Any('All native218/atlframework V source contents verified against native220-sources.json and compressed as a filename-to-source-text JSON map. Archive decoded and every restored hash checked. queue220.v is the exact queue219.v source used by corrected220; native build helper retains original output names from before prepare220 copied the binary/manifest.')
		'native_source_files': json2.Any(manifest.len)
		'queue_samples': json2.Any(samples)
		'queue_messages_observed': json2.Any(messages)
		'second_click_limit': json2.Any('Operator reports a second click around 13:27 local time; the click tool returned success with empty output. Only skip-second.png is retained. No persistent event log synchronizes this click with sample3, so no causal or failed-input conclusion is drawn.')
		'functional_outcome': json2.Any('FAILED: onboarding remains. Completed transition Future sample3 fails with NoSuchMethodError View.getContentCaptureSession during attachment. Three bounded queue samples contain no barriers; they do not establish queue state between samples. Map/search unverified.')
	}
	os.write_file(dest + 'attempt220-runtime-identities.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ATTEMPT220-RETENTION PASS serial, staged native220/full observer2 and shared APK/launcher identities; ${manifest.len} exact native V sources round-trip verified; 3 queue snapshots/${messages} messages, no observed barriers; functional outcome FAILED getContentCaptureSession')
}
