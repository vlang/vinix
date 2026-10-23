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
	assert r.inputs['build/android-maps/accessibility235-apk/bootstrap.apk'] == 'a6941021c172b2e9fef91e64c03405996df8b6f87a6f4cb30d2c0269b949001e'
	assert r.inputs['build/android-maps/interpolators234-apk/bootstrap.apk'] == '6dc384bc7cd0ace193317c5ebb45adb5d691a475e5e0a91756710320d0cde447'
	assert r.inputs['build/android-maps/framework234-interpolators/api-impl.jar'] == '643d292a4c862ca09bcf1f9c0579ad9c077ad8d1b477ed3a33d3ff1ac8300c13'
	assert r.inputs['build/android-maps/framework235-accessibility/api-impl.jar'] == '6810384e4ccc548adcf16a9d9cbc57d70c3250b50bda912fa32edf2af5874dfd'
	assert r.inputs['build/android-maps/libnative233.so'] == 'e94ca96bf9809c65392741964e3dcab985d17a5ae660c4d5fef46ef5cb19bd04'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!
	assert base.contains('java.lang.NoSuchMethodError:') && base.contains('getAccessibilityTraversalBefore()I')
	assert base.contains('StartupProbe.accessibilityTraversal') && !base.contains('BOOTSTRAP-ACCESSIBILITY-TRAVERSAL-PASS')
	assert fixed.contains('BOOTSTRAP-ACCESSIBILITY-TRAVERSAL-PASS constructors default-no-id per-view before-after replacement reset repeated-set unresolved-ids xml-inflation')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/accessibility235-apk/bootstrap.apk']
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
			'framework234-interpolators'
		} else {
			'framework235-accessibility'
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == r.inputs['build/android-maps/libnative233.so']
		manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-framework-manifest.json')!)!['sources']!.as_map()
		sources := json2.decode[map[string]string](read_gzip(out + '/' + mode + '-framework-sources.json.gz')!)!
		assert sources.len == manifest.len
		for name, source in sources {
			assert sha256.sum(source.bytes()).hex() == manifest[name]!.str(), name
		}
	}
	probe := read_gzip(out + '/StartupProbe.smali.gz')!
	assert probe.contains('accessibilityTraversal(Landroid/content/Context;)V') && probe.contains('xml-inflation')
	assert !probe.contains('InterpolatorProbe;->check')
	assert os.read_file(out + '/compiled-xml.txt')!.contains('accessibilityTraversalBefore') && os.read_file(out + '/compiled-xml.txt')!.contains('accessibilityTraversalAfter')
	fixture := json2.decode[map[string]string](read_gzip(out + '/fixture-sources.json.gz')!)!
	hashes := json2.decode[map[string]string](os.read_file(out + '/fixture-sources-sha256.json')!)!
	assert fixture.len == hashes.len
	for name, source in fixture {
		assert sha256.sum(source.bytes()).hex() == hashes[name], name
	}
	base_sources := json2.decode[map[string]string](read_gzip(out + '/baseline-framework-sources.json.gz')!)!
	fixed_sources := json2.decode[map[string]string](read_gzip(out + '/fixed-framework-sources.json.gz')!)!
	assert base_sources.len == 105 && fixed_sources.len == base_sources.len
	mut changed := []string{}
	for name, source in fixed_sources {
		assert name in base_sources, name
		if source != base_sources[name] { changed << name }
	}
	assert changed.len == 1 && changed[0].ends_with('/framework_startup.v'), changed.str()
	assert !read_gzip(out + '/baseline-View.smali.gz')!.contains('.method public getAccessibilityTraversalBefore()I')
	assert read_gzip(out + '/fixed-View.smali.gz')!.contains('.method public getAccessibilityTraversalBefore()I')
	previous := read_gzip(out + '/../render-node-outline/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	println('ACCESSIBILITY-TRAVERSAL VALIDATION PASS identical signed APK/native233; exact missing API baseline; constructors/state/XML inflation +${prior.len} prior probes +READY on framework235')
}
