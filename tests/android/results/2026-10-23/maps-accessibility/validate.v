import os
import json2
import crypto.sha256
import compress.gzip

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	out := os.dir(@FILE)
	assert os.args.len == 2 && os.args[1] in ['inputs', 'result'], 'usage: validate.v inputs|result'
	artifacts := json2.decode[map[string]string](os.read_file(out + '/receipt.json')!)!
	for path, expected in artifacts {
		assert digest(out + '/' + path)! == expected, path
	}
	row := json2.decode[map[string]json2.Any](os.read_file(out + '/inputs.json')!)!
	prior := row['prior_receipt']!.str()
	assert digest(out + '/' + prior)! == row['prior_receipt_sha256']!.str()
	manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/framework/manifest.json')!)!
	framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/framework/exact-sources.json.gz')!)!.bytestr())!
	declared := manifest['sources']!.as_map()
	assert framework.len == declared.len && framework.len == row['framework_source_files']!.int()
	for path, source in framework {
		assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path
	}
	assert 'tests/native-android-tools/androidtools/framework_interpolators.v' in framework
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-interpolators/framework/exact-sources.json.gz')!)!.bytestr())!
	delta := json2.decode[map[string]map[string]string](os.read_file(out + '/framework/source-delta-from234.json')!)!
	assert framework.len == 105 && framework.len == previous_framework.len
	mut changed := 0
	for path, source in framework {
		assert path in previous_framework
		if source == previous_framework[path] { continue }
		assert path == 'tests/native-android-tools/androidtools/framework_startup.v'
		assert delta[path]['previous_sha256'] == sha256.sum(previous_framework[path].bytes()).hex()
		assert delta[path]['current_sha256'] == sha256.sum(source.bytes()).hex()
		changed++
	}
	assert changed == 1 && delta.len == 1
	native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/native/exact-sources.json.gz')!)!.bytestr())!
	native_manifest := json2.decode[map[string]string](os.read_file(out + '/native/sources-sha256.json')!)!
	assert native.len == 82 && native.len == native_manifest.len && row['native_source_files']!.int() == 82
	for path, source in native {
		assert sha256.sum(source.bytes()).hex() == native_manifest[path], path
	}
	prior_native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-input-latency/233/native-exact-sources.json.gz')!)!.bytestr())!
	assert native == prior_native, 'Maps235 must reuse the exact native233 sources'
	files := row['files_sha256']!.as_map()
	assert files['libnative233.so']!.str() == 'e94ca96bf9809c65392741964e3dcab985d17a5ae660c4d5fef46ef5cb19bd04'
	assert files['framework235-accessibility/api-impl.jar']!.str() == '6810384e4ccc548adcf16a9d9cbc57d70c3250b50bda912fa32edf2af5874dfd'
	assert manifest['output_sha256']!.str() == files['framework235-accessibility/api-impl.jar']!.str()
	staged := row['staged_runtime_sha256']!.as_map()
	assert staged.len == 7
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == files['libnative233.so']!.str()
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == files['framework235-accessibility/api-impl.jar']!.str()
	pre := json2.decode[map[string]string](os.read_file(out + '/pre-run/sha256.json')!)!
	assert pre.len == 7 && pre['boot/vinix'].len == 64
	assert digest(out + '/pre-run/limine.conf')! == pre['boot/limine.conf']
	for name in ['build/android-maps/maps-live-vm/boot.img',
		'build/android-maps/maps-live-vm/efivars.fd', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'build/android-maps/suite159', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		assert pre[name].len == 64, name
	}
	assert pre['build/android-maps/suite159'] == files['suite159']!.str()
	assert os.read_file(out + '/maps-resources/apk-sha256.txt')!.trim_space() == files['GoogleMaps.apk']!.str()
	for name in ['fpA', '4QZ', 'c0L', 'aJ7'] {
		xml := os.read_file(out + '/maps-resources/' + name + '.txt')!
		assert xml.contains('E: pathInterpolator') && xml.contains('controlX1') && xml.contains('controlY2'), name
	}
	smali := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/framework/generated-smali.json.gz')!)!.bytestr())!
	assert smali.len == 15
	assert smali['android/graphics/drawable/PathParser.smali'].starts_with('.class public ')
	view := smali['android/view/View.smali']
	for method in ['getAccessibilityTraversalBefore()I', 'getAccessibilityTraversalAfter()I',
		'setAccessibilityTraversalBefore(I)V', 'setAccessibilityTraversalAfter(I)V',
		'vinixInitAccessibilityTraversal(Landroid/content/Context;Landroid/util/AttributeSet;II)V'] {
		assert view.contains(method), method
	}
	assert smali['android/view/animation/AnimationUtils.smali'].contains('VinixInterpolatorXml;->parse')
	if os.args[1] == 'result' {
		serial := gzip.decompress(os.read_bytes(out + '/serial.log.gz')!)!
		result := json2.decode[[]json2.Any](os.read_file(out + '/results.json')!)![0].as_map()
		assert sha256.sum(serial).hex() == result['serial_sha256']!.str()
		assert result['metadata']!.as_map()['apk_sha256']!.str() == files['GoogleMaps.apk']!.str()
		assert os.exists(out + '/observations.json'), 'Outcome must be recorded separately after actual UI review'
		observations := json2.decode[map[string]json2.Any](os.read_file(out + '/observations.json')!)!
		assert observations['reviewed_by']!.str().len > 0
		assert observations['place_selection']!.str().len > 0
		assert observations['directions']!.str().len > 0
		text := serial.bytestr()
		assert result['outcome']!.str() == 'startup_failed'
		assert text.contains('ANDROID-WS-FAIL input or render')
		assert text.contains('No virtual method setTransform(Landroid/graphics/Matrix;)V in class Landroid/view/TextureView;')
		assert text.contains('APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true')
		assert !text.contains('No virtual method setAccessibilityTraversalAfter(I)V')
		for name in ['map-ready.png', 'search-cleared.png', 'search-paris-final.png',
			'place-after-selection.png', 'place-settled.png', 'place-rendered.png', 'manual-timeline.log'] {
			assert os.exists(out + '/run/' + name), name
		}
		println('MAPS235-INTEGRITY PASS raw results/serial and observations retained; no success inferred from classifier')
	} else {
		println('MAPS235-INPUT-INTEGRITY PASS exact framework/native sources; staged runtime; pre-run image/kernel/EFI/QEMU hashes; Maps XML dumps; outcome pending')
	}
}
