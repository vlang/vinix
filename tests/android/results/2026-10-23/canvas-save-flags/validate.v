import os
import crypto.sha256
import json2
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn read_gzip(path string) !string { return gzip.decompress(os.read_bytes(path)!)!.bytestr() }

fn main() {
	out := os.dir(@FILE)
	r := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
	for name, digest in r.artifacts {
		assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == digest, name
	}
	assert r.inputs['build/android-maps/canvas242-apk/bootstrap.apk'] == '8bc78cc4a9842f337189c204f069bab8085b07cc83f2c836994231f953245860'
	assert r.inputs['build/android-maps/framework241-blur-styles/api-impl.jar'] == '60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04'
	assert r.inputs['build/android-maps/framework242-canvas-save/api-impl.jar'] == '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74'
	assert r.inputs['build/android-maps/libnative235.so'] == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!

	assert base.contains('java.lang.NoSuchMethodError: No virtual method saveLayer(FFFFLandroid/graphics/Paint;I)I')
	assert base.contains('CanvasSaveFlagsProbe.check') && base.contains('BOOTSTRAP-BLUR-STYLES-PASS')
	assert !base.contains('BOOTSTRAP-CANVAS-SAVE-FLAGS-PASS')
	assert fixed.contains('BOOTSTRAP-CANVAS-SAVE-FLAGS-PASS exact-float-bits paint-null virtual-forward return flags-ignored nested-depth transforms clip-restore bitmap Picture RecordingCanvas 192-pixels')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	mut framework := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/canvas242-apk/bootstrap.apk']
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		if mode == 'baseline' {
			assert row['outcome']!.str() == 'startup_failed' && row['process_exited']!.bool()
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			assert row['outcome']!.str() == 'startup_failed' && row['failure_markers']!.as_array().len == 2
			for marker in row['failure_markers']!.as_array() {
				line := marker.str()
				assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
			}
		}
		staged := json2.decode[map[string]string](os.read_file(out + '/' + mode + '-staged-runtime-sha256.json')!)!
		assert staged.len == 6
		for name, digest in staged {
			assert digest == r.inputs[mode + '/staged/' + name], name
			if !name.ends_with('api-impl.jar') {
				assert digest == r.inputs['baseline/staged/' + name], name
			}
		}
		jar := if mode == 'baseline' {
			'framework241-blur-styles'
		} else {
			'framework242-canvas-save'
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == r.inputs['build/android-maps/libnative235.so']
		manifest_full := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-framework-manifest.json')!)!
		assert manifest_full['output_sha256']!.str() == staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']
		manifest := manifest_full['sources']!.as_map()
		sources := json2.decode[map[string]string](read_gzip(out + '/' + mode + '-framework-sources.json.gz')!)!
		assert sources.len == manifest.len
		for name, source in sources {
			assert sha256.sum(source.bytes()).hex() == manifest[name]!.str(), name
		}
		framework[mode] = sources
	}
	assert framework['baseline'].len == 110 && framework['fixed'].len == 111
	mut changed := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changed << os.base(name) }
	}
	changed.sort()
	assert changed == ['framework_canvas_save_flags.v', 'framework_startup.v'], changed.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}

	baseline_api := read_gzip(out + '/baseline-Canvas.smali.gz')!
	fixed_api := read_gzip(out + '/fixed-Canvas.smali.gz')!
	assert !baseline_api.contains('.method public saveLayer(FFFFLandroid/graphics/Paint;I)I')
	assert fixed_api.contains('.method public saveLayer(FFFFLandroid/graphics/Paint;I)I')
	assert fixed_api.contains('invoke-virtual/range {p0 .. p5}, Landroid/graphics/Canvas;->saveLayer(FFFFLandroid/graphics/Paint;)I')
	recorder := read_gzip(out + '/fixed-VinixPictureCanvas.smali.gz')!
	assert recorder.contains('.method public saveLayer(FFFFLandroid/graphics/Paint;I)I') && recorder.contains('VinixPictureCommand54;')
	command := read_gzip(out + '/fixed-VinixPictureCommand54.smali.gz')!
	assert command.contains('invoke-virtual/range {v0 .. v6}, Landroid/graphics/Canvas;->saveLayer(FFFFLandroid/graphics/Paint;I)I')
	assert read_gzip(out + '/fixed-RecordingCanvas.smali.gz')!.contains('.super Landroid/graphics/VinixPictureCanvas;')
	startup := read_gzip(out + '/StartupProbe.smali.gz')!
	assert startup.contains('CanvasSaveFlagsProbe;->check') && startup.contains('BlurStylesProbe;->check')
	probe := read_gzip(out + '/CanvasSaveFlagsProbe.smali.gz')!
	for part in ['->saveLayer(FFFFLandroid/graphics/Paint;I)I', '->restoreToCount(I)V',
		'->clipRect(IIII)Z', '->beginRecording(II)',
		'->beginRecording()Landroid/graphics/RecordingCanvas;', '->getPixels([IIIIIII)V', '0x7fc01234'] {
		assert probe.contains(part), part
	}
	forward := read_gzip(out + '/SaveLayerForwardCanvas.smali.gz')!
	assert forward.contains('.method public saveLayer(FFFFLandroid/graphics/Paint;)I')
	assert forward.contains('floatToRawIntBits(F)I') && forward.contains('expectedPaint:Landroid/graphics/Paint;')
	assert forward.contains('0x80000000') && forward.contains('0x7fc01234')
	assert sha256.sum(os.read_bytes(out + '/../blur-styles/receipt.json')!).hex() == r.inputs['prior-blur-styles/receipt.json']
	fixture := json2.decode[map[string]string](read_gzip(out + '/fixture-sources.json.gz')!)!
	hashes := json2.decode[map[string]string](os.read_file(out + '/fixture-sources-sha256.json')!)!
	assert fixture.len == hashes.len
	for name, source in fixture {
		assert sha256.sum(source.bytes()).hex() == hashes[name], name
	}
	native := json2.decode[map[string]string](read_gzip(out + '/native-sources.json.gz')!)!
	native_hashes := json2.decode[map[string]string](os.read_file(out + '/native-sources-sha256.json')!)!
	assert native.len == 83 && native.len == native_hashes.len
	for name, source in native {
		assert sha256.sum(source.bytes()).hex() == native_hashes[name], name
	}
	previous := read_gzip(out + '/../blur-styles/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	assert prior.len == 106
	println('CANVAS-SAVE-FLAGS VALIDATION PASS identical signed APK/native235; exact missing six-argument saveLayer baseline; raw float forwarding, Paint/null/return/flags, saved transforms/clips/depths and192 bitmap/Picture/RecordingCanvas pixels +${prior.len} prior probes +READY; raw fixed startup_failed limited to two inherited nge diagnostics')
}
