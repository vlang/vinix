import os
import json2
import crypto.sha256
import compress.gzip

fn digest(path string) !string {
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
	out := os.dir(@FILE)
	artifacts := json2.decode[map[string]string](os.read_file(out + '/receipt.json')!)!
	for name, expected in artifacts {
		assert digest(out + '/' + name)! == expected, name
	}
	mut inputs := map[string]map[string]json2.Any{}
	mut sources := map[string]map[string]string{}
	mut versions := ['231', '232']
	if os.exists(out + '/233/inputs.json') { versions << '233' }
	for version in versions {
		path := out + '/' + version
		row := json2.decode[map[string]json2.Any](os.read_file(path + '/inputs.json')!)!
		for name, expected in row['inherited_receipts_sha256']!.as_map() {
			assert digest(out + '/' + name)! == expected.str(), version + '/' + name
		}
		manifest := row['native_sources_sha256']!.as_map()
		exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(path + '/native-exact-sources.json.gz')!)!.bytestr())!
		assert exact.len == 82 && row['native_source_files']!.int() == exact.len
		assert manifest.len == exact.len
		for name, source in exact {
			assert sha256.sum(source.bytes()).hex() == manifest[name]!.str(), version + '/' + name
		}
		staged := row['staged_runtime_sha256']!.as_map()
		files := row['files_sha256']!.as_map()
		native_version := if 'native_variant' in row { row['native_variant']!.str() } else { version }
		framework_jar := if 'framework_jar' in row { row['framework_jar']!.str() } else { 'framework228-outline/api-impl.jar' }
		assert staged.len == 7
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == files['libnative' + native_version + '.so']!.str()
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == files[framework_jar]!.str()
		serial := gzip.decompress(os.read_bytes(path + '/serial.log.gz')!)!
		result := json2.decode[[]json2.Any](os.read_file(path + '/results.json')!)![0].as_map()
		assert sha256.sum(serial).hex() == result['serial_sha256']!.str(), version
		assert result['metadata']!.as_map()['apk_sha256']!.str() == files['GoogleMaps.apk']!.str(), version
		if version == '232' {
			assert serial.bytestr().contains('ANDROID-WS-FAIL main looper')
			assert serial.bytestr().contains('java.lang.IllegalStateException: Vinix notification service unavailable')
			assert serial.bytestr().contains('android.app.NotificationManager.nativeCancel')
			assert !serial.bytestr().contains('WS-TIMING231 input_read')
		} else {
			assert serial.bytestr().contains('WS-TIMING231 input_read'), version
			assert os.exists(path + '/manual-timeline.log'), version
			assert os.exists(path + '/map-before-input.png'), version
			if version == '233' {
				assert serial.bytestr().contains('ANDROID-WS-FAIL input or render')
				assert serial.bytestr().contains('Failed to parse interpolator, no start tag found')
				assert serial.bytestr().contains('com.google.android.material.progressindicator.LinearProgressIndicator.<init>')
			} else {
				assert !serial.bytestr().contains('ANDROID-WS-FAIL'), version
			}
		}
		inputs[version] = row
		sources[version] = exact
	}
	mut changed := []string{}
	for name, source in sources['231'] {
		if sources['232'][name] != source { changed << name }
	}
	assert changed == ['ws_views.v'], changed.str()
	before := 'fn ws_input(e voidptr) {\n\tif ws.input < 0 { return }\n\tmut descriptor := WsPoll{ fd: ws.input, events: 1 }\n\tif C.poll(voidptr(&descriptor), 1, 0) <= 0 { return }\n'
	after := 'fn ws_input(e voidptr) {\n\tif ws.input < 0 { return }\n\t// Drain a bounded batch so queued movement cannot postpone button-up\n\t// and subsequent input behind a separate rendered frame per record.\n\tfor _ in 0 .. 64 {\n\t\tif !ws.running || pending(e) { return }\n\t\tmut descriptor := WsPoll{ fd: ws.input, events: 1 }\n\t\tif C.poll(voidptr(&descriptor), 1, 0) <= 0 { return }\n\t\tunsafe { if FramePush(slot(e, 19))(e, 128) < 0 { return } }\n\t\tws_input_event(e)\n\t\tpop_frame(e)\n\t}\n}\n\n// A separate call releases each text payload stack buffer before the next event.\nfn ws_input_event(e voidptr) {\n'
	assert sources['231']['ws_views.v'].count(before) == 1
	assert sources['231']['ws_views.v'].replace(before, after) == sources['232']['ws_views.v']
	assert digest(out + '/../input-drain/receipt.json')! == os.read_file(out + '/host-proof-receipt-sha256.txt')!.trim_space()
	host_proof := json2.decode[map[string]json2.Any](os.read_file(out + '/../input-drain/receipt.json')!)!
	assert sha256.sum(strip_timing(sources['231']['ws_views.v']).bytes()).hex() == host_proof['baseline_source_sha256']!.str()
	assert sha256.sum(strip_timing(sources['232']['ws_views.v']).bytes()).hex() == host_proof['fixed_source_sha256']!.str()
	baseline_files := inputs['231']['files_sha256']!.as_map()
	fixed_files := inputs['232']['files_sha256']!.as_map()
	for name in ['GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk',
		'framework228-outline/api-impl.jar', 'suite159', 'launcher200'] {
		assert baseline_files[name]!.str() == fixed_files[name]!.str(), name
	}
	baseline_staged := inputs['231']['staged_runtime_sha256']!.as_map()
	fixed_staged := inputs['232']['staged_runtime_sha256']!.as_map()
	for name, value in baseline_staged {
		if name == 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so' { continue }
		assert value.str() == fixed_staged[name]!.str(), name
	}
	if '233' in inputs {
		mut later_changed := []string{}
		for name, source in sources['232'] {
			if sources['233'][name] != source { later_changed << name }
		}
		assert later_changed == ['notifications.v'], later_changed.str()
		assert digest(out + '/../notification-cancel/receipt.json')! == os.read_file(out + '/notification-proof-receipt-sha256.txt')!.trim_space()
		notification_proof := json2.decode[map[string]json2.Any](os.read_file(out + '/../notification-cancel/receipt.json')!)!
		assert sha256.sum(sources['232']['notifications.v'].bytes()).hex() == notification_proof['baseline_source_sha256']!.str()
		assert sha256.sum(sources['233']['notifications.v'].bytes()).hex() == notification_proof['fixed_source_sha256']!.str()
		later_files := inputs['233']['files_sha256']!.as_map()
		for name in ['GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk', 'suite159', 'launcher200', 'framework228-outline/api-impl.jar'] {
			assert later_files[name]!.str() == fixed_files[name]!.str(), name
		}
		later_staged := inputs['233']['staged_runtime_sha256']!.as_map()
		for name, value in fixed_staged {
			if name == 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so' { continue }
			assert value.str() == later_staged[name]!.str(), name
		}
	}
	println('MAPS-INPUT-LATENCY-INTEGRITY PASS variants=' + versions.join(',') + '; raw result/serial hashes; exact82 V sources; bounded-input-only 231/232 delta matches host proof; 232 notification startup failure preserved; optional233 notification-only delta checked when present; no isolated Maps performance result is claimed')
}
