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
	assert r.inputs['build/android-maps/texture236-apk/bootstrap.apk'] == 'fc457eb30922cb2464e083e81e881748341a24234a9683cf450d694945c7bd53'
	assert r.inputs['build/android-maps/framework235-accessibility/api-impl.jar'] == '6810384e4ccc548adcf16a9d9cbc57d70c3250b50bda912fa32edf2af5874dfd'
	assert r.inputs['build/android-maps/framework236-texture/api-impl.jar'] == '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584'
	assert r.inputs['build/android-maps/libnative235.so'] == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!
	assert base.contains('java.lang.NoSuchMethodError:') && base.contains('setTransform(Landroid/graphics/Matrix;)V')
	assert base.contains('TextureViewTransformProbe.check') && !base.contains('BOOTSTRAP-TEXTURE-TRANSFORM-PASS')
	assert base.contains('BOOTSTRAP-INTERPOLATORS-PASS'), 'The numerical native235 interpolator checks must pass before the missing TextureView API.'
	assert fixed.contains('BOOTSTRAP-TEXTURE-TRANSFORM-PASS two-constructors matrix-nine-values input-copy output-copy fresh-output per-view replacement null-reset invalidation background-pixels geometry surface-unavailable')
	assert fixed.contains('BOOTSTRAP-ACCESSIBILITY-TRAVERSAL-PASS')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	mut framework := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/texture236-apk/bootstrap.apk']
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
			'framework235-accessibility'
		} else {
			'framework236-texture'
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == r.inputs['build/android-maps/libnative235.so']
		manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-framework-manifest.json')!)!['sources']!.as_map()
		sources := json2.decode[map[string]string](read_gzip(out + '/' + mode + '-framework-sources.json.gz')!)!
		assert sources.len == manifest.len
		for name, source in sources {
			assert sha256.sum(source.bytes()).hex() == manifest[name]!.str(), name
		}
		framework[mode] = sources
	}
	assert framework['baseline'].len == 105 && framework['fixed'].len == 106
	mut changed := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changed << os.base(name) }
	}
	changed.sort()
	assert changed == ['framework_startup.v', 'framework_texture_transforms.v'], changed.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}
	assert !read_gzip(out + '/baseline-TextureView.smali.gz')!.contains('.method public setTransform(')
	assert read_gzip(out + '/fixed-TextureView.smali.gz')!.contains('.method public setTransform(Landroid/graphics/Matrix;)V')
	probe := read_gzip(out + '/StartupProbe.smali.gz')!
	assert probe.contains('InterpolatorProbe;->check') && probe.contains('TextureViewTransformProbe;->check')
	assert read_gzip(out + '/TextureViewTransformProbe.smali.gz')!.contains('invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels')
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
	previous := read_gzip(out + '/../interpolators/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	println('TEXTURE-TRANSFORM VALIDATION PASS identical signed APK/native235; exact setter missing baseline; matrix ownership, reset, invalidation and pixel checks +${prior.len} prior probes +accessibility +READY on framework236')
}
