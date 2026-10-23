import os
import json2
import crypto.sha256
import compress.gzip

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn canonical_pipeline(source string) string {
	return source.split_into_lines().filter(!it.trim_space().starts_with('//')).join('\n')
		.replace('\n', '').replace('\t', '').replace(' ', '')
}

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
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-blur-styles/framework/exact-sources.json.gz')!)!.bytestr())!
	delta := json2.decode[map[string]map[string]string](os.read_file(out + '/framework/source-delta-from241.json')!)!
	assert framework.len == 111 && previous_framework.len == 110
	mut changed := 0
	for path, source in framework {
		if source == previous_framework[path] { continue }
		assert path in ['tests/native-android-tools/androidtools/framework_startup.v',
			'tests/native-android-tools/androidtools/framework_canvas_save_flags.v']
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
	assert native == prior_native, 'Maps242 must reuse the exact native235 sources'
	files := row['files_sha256']!.as_map()
	previous_inputs := json2.decode[map[string]json2.Any](os.read_file(out + '/../maps-blur-styles/inputs.json')!)!
	previous_files := previous_inputs['files_sha256']!.as_map()
	for path in ['libnative235.so', 'GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk',
		'suite239-stream', 'launcher200'] {
		assert files[path]!.str() == previous_files[path]!.str(), path
	}
	assert files['libnative235.so']!.str() == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	assert files['framework242-canvas-save/api-impl.jar']!.str() == '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74'
	assert manifest['output_sha256']!.str() == files['framework242-canvas-save/api-impl.jar']!.str()
	staged := row['staged_runtime_sha256']!.as_map()
	assert staged.len == 7
	previous_staged := previous_inputs['staged_runtime_sha256']!.as_map()
	for path, sum in staged {
		if path.ends_with('/api-impl.jar') { continue }
		assert sum.str() == previous_staged[path]!.str(), path
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == files['libnative235.so']!.str()
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == files['framework242-canvas-save/api-impl.jar']!.str()
	pre := json2.decode[map[string]string](os.read_file(out + '/pre-run/sha256.json')!)!
	assert pre.len == 7 && pre['boot/vinix'].len == 64
	assert digest(out + '/pre-run/limine.conf')! == pre['boot/limine.conf']
	for name in ['build/android-maps/maps-live-vm/boot.img',
		'build/android-maps/maps-live-vm/efivars.fd', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'build/android-maps/suite239-stream', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
		assert pre[name].len == 64, name
	}
	assert pre['build/android-maps/suite239-stream'] == files['suite239-stream']!.str()
	assert os.read_file(out + '/maps-resources/apk-sha256.txt')!.trim_space() == files['GoogleMaps.apk']!.str()
	for name in ['fpA', '4QZ', 'c0L', 'aJ7'] {
		xml := os.read_file(out + '/maps-resources/' + name + '.txt')!
		assert xml.contains('E: pathInterpolator') && xml.contains('controlX1') && xml.contains('controlY2'), name
	}
	smali := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/framework/generated-smali.json.gz')!)!.bytestr())!
	assert smali.len == 25
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
	assert smali['android/view/WindowInsets$Builder.smali'].contains('build()Landroid/view/WindowInsets;')
	assert smali['android/view/WindowInsets.smali'].contains('getInsets(I)Landroid/graphics/Insets;')
	assert smali['android/view/WindowInsets$Type.smali'].contains('systemOverlays()I')
	assert smali['android/graphics/Insets.smali'].contains('of(IIII)Landroid/graphics/Insets;')
	date_utils := smali['android/text/format/DateUtils.smali']
	assert date_utils.contains('formatDateRange(Landroid/content/Context;Ljava/util/Formatter;JJILjava/lang/String;)Ljava/util/Formatter;')
	assert date_utils.contains('Llibcore/icu/DateIntervalFormat;->formatDateRange(JJILjava/lang/String;)Ljava/lang/String;')
	blur := smali['android/graphics/BlurMaskFilter$Blur.smali']
	for style in ['NORMAL', 'SOLID', 'OUTER', 'INNER'] {
		assert blur.contains('.field public static final enum ' + style + ':Landroid/graphics/BlurMaskFilter$Blur;'), style
	}
	assert blur.contains('.field final native_int:I')
	canvas := smali['android/graphics/Canvas.smali']
	assert canvas.contains('.method public saveLayer(FFFFLandroid/graphics/Paint;I)I')
	assert canvas.contains('invoke-virtual/range {p0 .. p5}, Landroid/graphics/Canvas;->saveLayer(FFFFLandroid/graphics/Paint;)I')
	assert smali['android/atl/GskCanvas.smali'].contains('.method public save()I')
	assert os.read_file(out + '/streaming/prototype.log')!.contains('STREAM238 ALL PASS')
	assert os.read_file(out + '/streaming/root-proof.log')!.contains('STREAM238 ALL PASS')
	assert os.read_file(out + '/streaming/production-proof.log')!.contains('1 passed, 1 total')
	pipeline := os.read_file(out + '/streaming/pipeline.v.txt')!
	frozen_suite := os.read_file(out + '/helpers/suite239-stream.v')!
	baseline_suite := os.read_file(out + '/helpers/suite-low-disk.v')!
	assert frozen_suite.ends_with('\n' + pipeline)
	old_stage := "\tarchive := output + '/module.tar'\n\tchecked(['tar', '--format=ustar', '-cf', archive, '-C', module_root, '.'])!\n\tchecked(['mcopy', '-o', '-i', settings['boot_image']!.str(), archive, '::/boot/qemu-runtime.tar'])!\n\tos.rm(archive)!"
	new_stage := "\tstream_module(module_root, settings['boot_image']!.str())!"
	assert frozen_suite[..frozen_suite.len - pipeline.len - 1].replace(new_stage, old_stage) == baseline_suite
	production := os.read_file(out + '/streaming/production/stream.v')!
	scoped_pipeline := pipeline.replace('StreamStatuses', 'Statuses')
		.replace('stream_spawn', 'spawn_child').replace('stream_wait', 'wait_child')
		.replace('stream_commands', 'commands').replace('fn stream_module', 'pub fn copy')
	assert canonical_pipeline(production.all_after('#include <spawn.h>')) == canonical_pipeline(scoped_pipeline.all_after('#include <spawn.h>'))
	production_hashes := json2.decode[map[string]string](os.read_file(out + '/streaming/production-sources-sha256.json')!)!
	for path, sum in production_hashes {
		assert digest(out + '/streaming/production/' + os.base(path))! == sum, path
	}
	if os.args[1] == 'result' {
		serial := gzip.decompress(os.read_bytes(out + '/serial.log.gz')!)!
		result := json2.decode[[]json2.Any](os.read_file(out + '/results.json')!)![0].as_map()
		assert sha256.sum(serial).hex() == result['serial_sha256']!.str()
		assert result['metadata']!.as_map()['apk_sha256']!.str() == files['GoogleMaps.apk']!.str()
		log := serial.bytestr()
		assert result['outcome']!.str() == 'startup_failed'
		assert log.contains('ANDROID-WS-FAIL input or render')
		assert log.contains('java.lang.UnsatisfiedLinkError: No implementation found for long android.widget.PopupMenu.native_init()')
		assert log.contains('APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true')
		assert !log.contains('NoSuchMethodError: No virtual method saveLayer(FFFFLandroid/graphics/Paint;I)I'), 'Prior Canvas overload blocker must be reported if it recurs'
		assert os.exists(out + '/observations.json'), 'Outcome must be recorded separately after actual UI review'
		observations := json2.decode[map[string]json2.Any](os.read_file(out + '/observations.json')!)!
		assert observations['reviewed_by']!.str().len > 0
		assert observations['place_selection']!.str().len > 0
		assert observations['directions']!.str().len > 0
		assert observations['raw_outcome']!.str().starts_with(result['outcome']!.str()), 'Preserve raw classifier'
		assert observations['qualification']!.str().len > 0
		assert observations['preview']!.str().len > 0
		for name in ['map-before-input.png', 'search-paris.png', 'paris-selected.png',
			'directions-opened.png', 'origin-query.png', 'route-selected.png'] {
			assert os.exists(out + '/run/' + name), name
		}
		assert !os.exists(out + '/run/route-preview.png'), 'Preview capture failed after app exit'
		println('MAPS242-INTEGRITY PASS raw results/serial and observations retained; no success inferred from classifier')
	} else {
		println('MAPS242-INPUT-INTEGRITY PASS exact framework/native sources; staged runtime; pre-run image/kernel/EFI/QEMU hashes; Maps XML dumps; outcome pending')
	}
}
