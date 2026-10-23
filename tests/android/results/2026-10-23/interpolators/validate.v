import os
import crypto.sha256
import json2
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn uncompressed(path string) !string {
	return gzip.decompress(os.read_bytes(path)!)!.bytestr()
}

fn main() {
	out := os.dir(@FILE)
	r := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
	for name, digest in r.artifacts {
		assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == digest, name
	}
	assert r.inputs['build/android-maps/interpolators234-apk/bootstrap.apk'] == '6dc384bc7cd0ace193317c5ebb45adb5d691a475e5e0a91756710320d0cde447'
	assert r.inputs['build/android-maps/libnative233.so'] == 'e94ca96bf9809c65392741964e3dcab985d17a5ae660c4d5fef46ef5cb19bd04'
	assert r.inputs['build/android-maps/framework228-outline/api-impl.jar'] == '26b21262b67e92c77bcf57b9480bc881b0683ac0e8d6f97dba105ef453f3fe5a'
	assert r.inputs['build/android-maps/framework234-interpolators/api-impl.jar'] == '643d292a4c862ca09bcf1f9c0579ad9c077ad8d1b477ed3a33d3ff1ac8300c13'
	assert r.inputs['build/android-maps/libnative235.so'] != r.inputs['build/android-maps/libnative233.so']
	base := uncompressed(out + '/baseline-serial.log.gz')!
	rejected := uncompressed(out + '/rejected234-serial.log.gz')!
	fixed := uncompressed(out + '/fixed-serial.log.gz')!
	assert base.contains('java.lang.AssertionError: interpolator resource must load a nonnull curve')
	assert base.contains('org.vinix.bootstrap.InterpolatorProbe.load')
	assert !base.contains('BOOTSTRAP-INTERPOLATORS-PASS')
	assert rejected.contains('java.lang.AssertionError: interpolator numerical curve')
	assert rejected.contains('org.vinix.bootstrap.InterpolatorProbe.check(Unknown Source:1172)')
	assert !rejected.contains('BOOTSTRAP-INTERPOLATORS-PASS')
	assert os.read_file(out + '/rejected234-path-precision.log')!.contains('error=0.021939219863693765')
	assert fixed.contains('BOOTSTRAP-INTERPOLATORS-PASS maps-four-curves ten-tags')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError')
	assert !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	for mode, serial in {
		'baseline':    base
		'rejected234': rejected
		'fixed':       fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/interpolators234-apk/bootstrap.apk']
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		if mode != 'fixed' {
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
		for name, digest in staged {
			assert digest == r.inputs[mode + '/staged/' + name], name
		}
		jar := if mode == 'baseline' {
			'framework228-outline'
		} else {
			'framework234-interpolators'
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		native_library := if mode == 'fixed' { 'libnative235.so' } else { 'libnative233.so' }
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == r.inputs['build/android-maps/' + native_library]
		manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-framework-manifest.json')!)!['sources']!.as_map()
		sources := json2.decode[map[string]string](uncompressed(out + '/' + mode + '-framework-sources.json.gz')!)!
		assert sources.len == manifest.len
		for name, source in sources {
			assert sha256.sum(source.bytes()).hex() == manifest[name]!.str(), name
		}
	}
	for name in ['usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'opt/android-test/native-guest'] {
		assert r.inputs['baseline/staged/' + name] == r.inputs['fixed/staged/' + name], name
		assert r.inputs['rejected234/staged/' + name] == r.inputs['fixed/staged/' + name], name
	}
	fixture := json2.decode[map[string]string](uncompressed(out + '/fixture-sources.json.gz')!)!
	hashes := json2.decode[map[string]string](os.read_file(out + '/fixture-sources-sha256.json')!)!
	assert fixture.len == hashes.len
	for name, source in fixture {
		assert sha256.sum(source.bytes()).hex() == hashes[name], name
	}
	probe := uncompressed(out + '/InterpolatorProbe.smali.gz')!
	assert probe.contains('cmpg-float') && probe.contains('if-gtz')
	assert probe.contains('fixture_interpolator_maps0') && probe.contains('fixture_interpolator_outside_controls')
	assert uncompressed(out + '/baseline-AnimationUtils.smali.gz')!.contains('loadInterpolator(Landroid/content/Context;I)Landroid/view/animation/Interpolator;')
	assert uncompressed(out + '/fixed-AnimationUtils.smali.gz')!.contains('VinixInterpolatorXml;->parse')
	assert uncompressed(out + '/fixed-PathInterpolator.smali.gz')!.contains('PathParser;->createPathFromPathData')
	mut native_hashes := map[string]map[string]string{}
	for mode in ['baseline', 'fixed'] {
		native := json2.decode[map[string]string](uncompressed(out + '/' + mode + '-native-sources.json.gz')!)!
		version_hashes := json2.decode[map[string]string](os.read_file(out + '/' + mode + '-native-sources-sha256.json')!)!
		assert native.len == version_hashes.len
		assert native.len == if mode == 'baseline' { 82 } else { 83 }
		for name, source in native {
			assert sha256.sum(source.bytes()).hex() == version_hashes[name], name
		}
		native_hashes[mode] = version_hashes
	}
	mut changed := []string{}
	for name, digest in native_hashes['fixed'] {
		if name !in native_hashes['baseline'] || digest != native_hashes['baseline'][name] {
			changed << name
		}
	}
	changed.sort()
	assert changed == ['path_animation.v', 'path_animation_curves.v', 'path_curves.v', 'paths.v'], changed.str()
	for name in ['runtime.v', 'ws_views.v', 'timing231.v', 'notifications.v'] {
		assert native_hashes['fixed'][name] == native_hashes['baseline'][name], name
	}
	identities := json2.decode[map[string]string](os.read_file(out + '/fixed-native-production-source-sha256.json')!)!
	reviewed_path := out + '/fixed-native-reviewed-overlays.json'
	assert sha256.sum(os.read_bytes(reviewed_path)!).hex() == identities['reviewed_overlay_manifest_sha256']
	reviewed := json2.decode[map[string]string](os.read_file(reviewed_path)!)!
	assert reviewed.len == changed.len
	for path, digest in reviewed {
		assert digest == native_hashes['fixed'][os.base(path)] && digest == identities[path], path
	}
	host_receipt_path := out + '/path-precision-host-receipt.json'
	assert sha256.sum(os.read_bytes(host_receipt_path)!).hex() == r.inputs['path-precision-host-receipt']
	host := json2.decode[map[string]string](os.read_file(host_receipt_path)!)!
	assert host['normal_exit_code'] == '0' && host['asan_exit_code'] == '0'
	for path, digest in reviewed {
		assert host[path] == digest, path
	}
	previous := uncompressed(out + '/../render-node-outline/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	println('INTERPOLATORS-VALIDATION PASS identical signed APK; baseline exact null-loader failure; rejected234 exact pathData error; unchanged234 framework with native235 passes all10 tags +4 Maps numeric curves +path validation +parser close +${prior.len} prior probes +READY; only four native precision sources changed')
}
