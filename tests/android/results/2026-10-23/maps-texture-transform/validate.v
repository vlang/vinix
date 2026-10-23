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
	assert digest(out + '/' + row['native_precision_receipt']!.str())! == row['native_precision_receipt_sha256']!.str()
	manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/framework/manifest.json')!)!
	framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/framework/exact-sources.json.gz')!)!.bytestr())!
	declared := manifest['sources']!.as_map()
	assert framework.len == declared.len && framework.len == row['framework_source_files']!.int()
	for path, source in framework {
		assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path
	}
	assert 'tests/native-android-tools/androidtools/framework_interpolators.v' in framework
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-accessibility/framework/exact-sources.json.gz')!)!.bytestr())!
	delta := json2.decode[map[string]map[string]string](os.read_file(out + '/framework/source-delta-from235.json')!)!
	assert framework.len == 106 && previous_framework.len == 105
	mut changed := 0
	for path, source in framework {
		if source == previous_framework[path] { continue }
		assert path in ['tests/native-android-tools/androidtools/framework_startup.v',
			'tests/native-android-tools/androidtools/framework_texture_transforms.v']
		expected_previous := if path in previous_framework {
			sha256.sum(previous_framework[path].bytes()).hex()
		} else {
			''
		}
		assert delta[path]['previous_sha256'] == expected_previous
		assert delta[path]['current_sha256'] == sha256.sum(source.bytes()).hex()
		changed++
	}
	assert changed == 2 && delta.len == 2
	for path in previous_framework.keys() {
		assert path in framework, path
	}
	native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/native/exact-sources.json.gz')!)!.bytestr())!
	native_manifest := json2.decode[map[string]string](os.read_file(out + '/native/sources-sha256.json')!)!
	assert native.len == 83 && native.len == native_manifest.len && row['native_source_files']!.int() == 83
	for path, source in native {
		assert sha256.sum(source.bytes()).hex() == native_manifest[path], path
	}
	prior_native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../interpolators/fixed-native-sources.json.gz')!)!.bytestr())!
	assert native == prior_native, 'Maps236 must reuse the exact native235 sources'
	files := row['files_sha256']!.as_map()
	assert files['libnative235.so']!.str() == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	assert files['framework236-texture/api-impl.jar']!.str() == '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584'
	assert manifest['output_sha256']!.str() == files['framework236-texture/api-impl.jar']!.str()
	staged := row['staged_runtime_sha256']!.as_map()
	assert staged.len == 7
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == files['libnative235.so']!.str()
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == files['framework236-texture/api-impl.jar']!.str()
	pre := json2.decode[map[string]string](os.read_file(out + '/pre-run/sha256.json')!)!
	assert pre.len == 7 && pre['boot/vinix'].len == 64
	assert digest(out + '/pre-run/limine.conf')! == pre['boot/limine.conf']
	for name in ['build/android-maps/maps-live-vm/boot.img',
		'build/android-maps/maps-live-vm/efivars.fd', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'build/android-maps/suite159', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		assert pre[name].len == 64, name
	}
	assert pre['build/android-maps/suite159'] == files['suite159']!.str()
	prelaunch := json2.decode[[]json2.Any](os.read_file(out + '/prelaunch-failure/results.json')!)![0].as_map()
	assert prelaunch['outcome']!.str() == 'harness_failure'
	assert prelaunch['harness_error']!.str().contains('tar: Write error')
	assert prelaunch['metadata']!.as_map()['apk_sha256']!.str() == files['GoogleMaps.apk']!.str()
	assert os.read_file(out + '/prelaunch-failure/run.log')!.contains(files['framework236-texture/api-impl.jar']!.str())
	assert os.read_file(out + '/maps-resources/apk-sha256.txt')!.trim_space() == files['GoogleMaps.apk']!.str()
	for name in ['fpA', '4QZ', 'c0L', 'aJ7'] {
		xml := os.read_file(out + '/maps-resources/' + name + '.txt')!
		assert xml.contains('E: pathInterpolator') && xml.contains('controlX1') && xml.contains('controlY2'), name
	}
	smali := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/framework/generated-smali.json.gz')!)!.bytestr())!
	assert smali.len == 16
	assert smali['android/graphics/drawable/PathParser.smali'].starts_with('.class public ')
	view := smali['android/view/View.smali']
	for method in ['getAccessibilityTraversalBefore()I', 'getAccessibilityTraversalAfter()I',
		'setAccessibilityTraversalBefore(I)V', 'setAccessibilityTraversalAfter(I)V',
		'vinixInitAccessibilityTraversal(Landroid/content/Context;Landroid/util/AttributeSet;II)V'] {
		assert view.contains(method), method
	}
	texture := smali['android/view/TextureView.smali']
	for method in ['setTransform(Landroid/graphics/Matrix;)V',
		'getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;'] {
		assert texture.contains(method), method
	}
	assert texture.contains('vinixContentTransform:Landroid/graphics/Matrix;')
	assert smali['android/view/animation/AnimationUtils.smali'].contains('VinixInterpolatorXml;->parse')
	if os.args[1] == 'result' {
		serial := gzip.decompress(os.read_bytes(out + '/serial.log.gz')!)!
		result := json2.decode[[]json2.Any](os.read_file(out + '/results.json')!)![0].as_map()
		assert sha256.sum(serial).hex() == result['serial_sha256']!.str()
		assert result['metadata']!.as_map()['apk_sha256']!.str() == files['GoogleMaps.apk']!.str()
		assert result['outcome']!.str() == 'startup_failed'
		log := serial.bytestr()
		assert log.contains('NoClassDefFoundError: Failed resolution of: Landroid/view/WindowInsets$Builder;')
		assert log.contains('at gfd.<init>') && log.contains('at gfs.<clinit>') && log.contains('at gfv.<clinit>')
		assert log.contains('Fatal signal 6 (SIGABRT)')
		assert log.contains('APK-SUITE-EXIT id=google-maps code=134 native_observed=true gtk_x11_absent=true')
		assert !log.contains('NoSuchMethodError: No virtual method setTransform(Landroid/graphics/Matrix;)V')
		assert os.exists(out + '/observations.json'), 'Outcome must be recorded separately after actual UI review'
		observations := json2.decode[map[string]json2.Any](os.read_file(out + '/observations.json')!)!
		assert observations['reviewed_by']!.str().len > 0
		assert observations['place_selection']!.str().len > 0
		assert observations['directions']!.str().len > 0
		println('MAPS236-INTEGRITY PASS raw results/serial and observations retained; no success inferred from classifier')
	} else {
		println('MAPS236-INPUT-INTEGRITY PASS exact framework/native sources; staged runtime; pre-run image/kernel/EFI/QEMU hashes; Maps XML dumps; outcome pending')
	}
}
