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
	previous_framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-popup-menus/framework/exact-sources.json.gz')!)!.bytestr())!
	delta := json2.decode[map[string]map[string]string](os.read_file(out + '/framework/source-delta-from243.json')!)!
	assert framework.len == 113 && previous_framework.len == 112
	mut changed := 0
	for path, source in framework {
		if source == previous_framework[path] { continue }
		assert path in ['tests/native-android-tools/androidtools/framework_classes.v',
			'tests/native-android-tools/androidtools/framework_action_provider.v']
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
	prior_native := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/../maps-popup-menus/native/exact-sources.json.gz')!)!.bytestr())!
	assert prior_native.len == native.len
	native_delta := json2.decode[map[string]map[string]string](os.read_file(out + '/native/source-delta-from236.json')!)!
	mut native_changed := 0
	for path, source in native {
		assert path in prior_native, path
		if source == prior_native[path] { continue }
		assert path == 'menus.v'
		assert native_delta[path]['previous_sha256'] == sha256.sum(prior_native[path].bytes()).hex()
		assert native_delta[path]['current_sha256'] == sha256.sum(source.bytes()).hex()
		native_changed++
	}
	assert native_changed == 0 && native_delta.len == 0
	files := row['files_sha256']!.as_map()
	previous_inputs := json2.decode[map[string]json2.Any](os.read_file(out + '/../maps-popup-menus/inputs.json')!)!
	previous_files := previous_inputs['files_sha256']!.as_map()
	for path in ['GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk',
		'suite239-stream', 'launcher200'] {
		assert files[path]!.str() == previous_files[path]!.str(), path
	}
	assert files['libnative236.so']!.str() == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	assert files['framework244-action-provider/api-impl.jar']!.str() == '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
	assert manifest['output_sha256']!.str() == files['framework244-action-provider/api-impl.jar']!.str()
	staged := row['staged_runtime_sha256']!.as_map()
	assert staged.len == 7
	previous_staged := previous_inputs['staged_runtime_sha256']!.as_map()
	for path, sum in staged {
		if path.ends_with('/api-impl.jar') { continue }
		assert sum.str() == previous_staged[path]!.str(), path
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == files['libnative236.so']!.str()
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == files['framework244-action-provider/api-impl.jar']!.str()
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
	assert smali.len == 34
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
	popup := smali['android/widget/PopupMenu.smali']
	assert popup.contains('vinixDialog:Landroid/app/Dialog;')
	assert popup.contains('Landroid/app/Dialog;->show()V')
	assert popup.contains('Landroid/view/VinixMenu;-><init>(Landroid/content/Context;)V')
	assert !popup.contains(' native ') && !popup.contains('MenuImpl;')
	assert smali['android/widget/VinixPopupMenuClick.smali'].contains('vinixActivate(Landroid/view/MenuItem;Landroid/app/Dialog;)V')
	assert smali['android/widget/VinixPopupMenuDismiss.smali'].contains('notified:Z')
	assert smali['android/view/VinixMenu.smali'].contains('.field private vinixContext:Landroid/content/Context;')
	assert smali['android/view/VinixMenuItem.smali'].contains('vinixInvokeClick()Z')
	provider := smali['android/view/ActionProvider.smali']
	assert provider.contains('.class public abstract Landroid/view/ActionProvider;')
	assert provider.contains('onCreateActionView()Landroid/view/View;')
	assert provider.contains('refreshVisibility()V')
	assert smali['android/view/ActionProvider$VisibilityListener.smali'].contains('onActionProviderVisibilityChanged(Z)V')
	assert smali['android/view/ActionProvider$SubUiVisibilityListener.smali'].contains('onSubUiVisibilityChanged(Z)V')
	assert smali['android/view/MenuItem.smali'].contains('setActionProvider(Landroid/view/ActionProvider;)Landroid/view/MenuItem;')
	assert smali['android/view/VinixMenuItem.smali'].contains('getActionProvider()Landroid/view/ActionProvider;')
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
	if os.exists(out + '/resume245/preflight.json') {
		preflight := json2.decode[map[string]json2.Any](os.read_file(out + '/resume245/preflight.json')!)!
		assert digest(out + '/resume245/preflight.json')! == os.read_file(out + '/resume245/preflight-sha256.txt')!.trim_space()
		assert preflight['archive_runtime_sha256']!.as_map() == staged
		assert preflight['staged_runtime_sha256']!.as_map() == staged
		resume_pre := preflight['pre_run_sha256']!.as_map()
		assert resume_pre.len == 7
		assert resume_pre['build/android-maps/maps-live-vm/boot.img']!.str() == preflight['boot_image_sha256']!.str()
		assert preflight['boot_image_size']!.i64() == 4294967296
		assert preflight['boot_image_mtime']!.i64() > 0
		for name in ['boot/vinix', 'boot/limine.conf', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
			'build/android-maps/suite239-stream', 'build/qemu-horizontal/bin/qemu-system-aarch64'] {
			assert resume_pre[name]!.str() == pre[name], name
		}
		helper_hashes := json2.decode[map[string]string](os.read_file(out + '/resume245/helpers-before-run.json')!)!
		assert helper_hashes.len == 15
		for name, sum in helper_hashes {
			assert sum.len == 64
			if os.file_ext(name) in ['.v', '.json'] {
				assert digest(out + '/resume245/helpers/' + os.base(name))! == sum, name
			}
		}
		resumed_suite := os.read_file(out + '/resume245/helpers/suite245-resume.v')!
		original_call := '\tprepare_module(settings, app, output)!'
		resume_call := '\tvalidate_resume245(settings, output)!'
		assert frozen_suite.count(original_call) == 1
		modified_prefix := frozen_suite.replace(original_call, resume_call)
		assert resumed_suite.starts_with(modified_prefix)
		added := resumed_suite[modified_prefix.len..]
		assert added.contains('fn validate_resume245(')
		assert added.contains('os.file_size(image)') && added.contains('os.file_last_mod_unix(image)')
		assert !added.contains('stream_module(') && !added.contains('prepare_module(')
		assert !added.contains('digest(image)'), 'The resumed suite trusts preflight plus size/mtime; it does not rehash the image'
		resume_delta := json2.decode[map[string]string](os.read_file(out + '/resume245/helpers/suite245-resume-delta.json')!)!
		assert resume_delta['original_source_sha256'] == sha256.sum(frozen_suite.bytes()).hex()
		assert resume_delta['resumed_source_sha256'] == sha256.sum(resumed_suite.bytes()).hex()
		mut resumed_config := json2.decode[map[string]json2.Any](os.read_file(out + '/resume245/helpers/attempt245.json')!)!
		resumed_config['output'] = 'build/android-maps/attempt244'
		assert resumed_config == json2.decode[map[string]json2.Any](os.read_file(out + '/configuration.json')!)!
		interrupted := json2.decode[map[string]json2.Any](os.read_file(out + '/interrupted244/interruption.json')!)!
		old_serial := gzip.decompress(os.read_bytes(out + '/interrupted244/serial.log.gz')!)!
		assert sha256.sum(old_serial).hex() == interrupted['serial_sha256']!.str()
		assert old_serial.len == interrupted['serial_bytes']!.int()
		assert !old_serial.bytestr().contains('APK-SUITE-EXIT id=google-maps')
		assert !old_serial.bytestr().contains('ANDROID-WS-FAIL')
		assert !interrupted['results_json_present']!.bool()
		assert !os.exists(out + '/interrupted244/results.json')
		assert !os.exists(out + '/interrupted244/attempt244-harness.log')
		assert !os.exists(out + '/interrupted244/interact244.log')
	}
	if os.args[1] == 'result' {
		serial := gzip.decompress(os.read_bytes(out + '/serial.log.gz')!)!
		interrupted := json2.decode[map[string]json2.Any](os.read_file(out + '/interruption245.json')!)!
		assert sha256.sum(serial).hex() == interrupted['serial_sha256']!.str()
		assert serial.len == interrupted['serial_bytes']!.int()
		log := serial.bytestr()
		assert log.contains('APK-SUITE-BEGIN id=google-maps ')
		assert log.contains('ANDROID-WS-READY backend=vinix-native')
		assert !log.contains('APK-SUITE-EXIT id=google-maps')
		assert !log.contains('ANDROID-WS-FAIL')
		for key in ['results_json_present', 'final_harness_log_present', 'final_interaction_log_present',
			'application_exit_marker_present', 'framework_failure_marker_present', 'observation_completed'] {
			assert !interrupted[key]!.bool(), key
		}
		assert interrupted['configured_observation_seconds']!.int() == 900
		assert interrupted['observed_end']!.str().contains('final raw classifier are unavailable')
		for path in ['results.json', 'run/attempt245-harness.log', 'run/interact245.log'] {
			assert !os.exists(out + '/' + path), path
		}
		processes := os.read_file(out + '/resume245/processes-at-recovery.txt')!
		assert !processes.contains('build/android-maps/run245')
		assert !processes.contains('build/android-maps/suite245-resume')
		assert !processes.contains('qemu-system-aarch64')
		assert os.exists(out + '/observations.json'), 'Outcome must be recorded separately after actual UI review'
		observations := json2.decode[map[string]json2.Any](os.read_file(out + '/observations.json')!)!
		assert observations['reviewed_by']!.str().len > 0
		assert observations['place_selection']!.str().len > 0
		assert observations['directions']!.str().len > 0
		assert observations['raw_outcome']!.str().starts_with('unavailable; Maps245 was interrupted'), 'Do not fabricate a raw classifier'
		assert observations['raw_outcome']!.str().contains('900-second observation did not complete')
		assert observations['qualification']!.str().len > 0
		assert observations['preview']!.str().len > 0
		assert observations['overflow']!.str().len > 0
		assert observations['return_to_routes']!.str().len > 0
		assert observations['overflow']!.str().contains('do not verify satellite imagery or terrain rendering')
		for name in ['map-before-input', 'search-empty', 'paris-results', 'paris-place', 'paris-place-tiles',
			'directions-empty', 'origin-query', 'route-estimates', 'route-preview', 'route-preview-next',
			'route-preview-previous', 'preview-overflow', 'preview-overflow-again', 'preview-satellite',
			'preview-terrain', 'route-after-preview'] {
			assert os.exists(out + '/run/' + name + '.png'), name
		}
		timeline := os.read_file(out + '/run/manual-timeline.log')!
		for action in ["'type', 'Paris'", "'type', 'Versailles, France'", 'MAP-COLOR-DETECTED',
			'route-preview-next.png', 'route-preview-previous.png', 'preview-overflow.png',
			'preview-satellite.png', 'preview-terrain.png', 'route-after-preview.png'] {
			assert timeline.contains(action), action
		}
		assert !timeline.contains('END exit=1')
		println('MAPS245-INTEGRITY PASS interrupted244/245 partial serial and completed UI workflow retained; no final classifier or completed 900-second observation')
	} else {
		println('MAPS244-INPUT-INTEGRITY PASS exact framework/native sources; staged runtime; pre-run image/kernel/EFI/QEMU hashes; Maps XML dumps; outcome recorded separately')
	}
}
