import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn uncompressed(out string, name string) !string {
	return gzip.decompress(os.read_bytes(out + '/' + name)!)!.bytestr()
}

fn main() {
	out := os.dir(@FILE)
	receipt := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
	assert receipt.inputs['build/android-maps/framework228-outline/api-impl.jar'] == '26b21262b67e92c77bcf57b9480bc881b0683ac0e8d6f97dba105ef453f3fe5a'
	assert receipt.inputs['build/android-maps/libnative229.so'] == '1370bbfebd982d5597c4ccf9d2dd37df02d34a57b5b22afbaad008c1a158e3c6'
	assert receipt.inputs['build/android-maps/outline228-apk/bootstrap.apk'] == '409786d77830fa5d918a5e342972a0326509c71d7a75fa19fbe082b3e6a8e0c7'
	for name, digest in receipt.artifacts {
		assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == digest, name
	}
	fixture := json2.decode[map[string]string](uncompressed(out, 'fixture-sources.json.gz')!)!
	fixture_hashes := json2.decode[map[string]string](os.read_file(out + '/fixture-sources-sha256.json')!)!
	assert fixture.len == fixture_hashes.len
	for name, source in fixture {
		assert sha256.sum(source.bytes()).hex() == fixture_hashes[name], name
	}
	initial := json2.decode[map[string]string](uncompressed(out, 'initial-draw-color/fixture-sources.json.gz')!)!
	assert initial.len == fixture.len
	for name, source in initial {
		if name != 'render_node_outline.v' { assert fixture[name] == source, name }
	}
	initial_failure := uncompressed(out, 'initial-draw-color/fixed-serial.log.gz')!
	assert initial_failure.contains('RenderNodeOutlineProbe.fill2') && initial_failure.contains('java.lang.AssertionError')
	manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/framework-manifest.json')!)!['sources']!.as_map()
	framework := json2.decode[map[string]string](uncompressed(out, 'framework-sources.json.gz')!)!
	assert framework.len == 104 && framework.len == manifest.len
	for name, source in framework {
		assert sha256.sum(source.bytes()).hex() == manifest[name]!.str(), name
	}
	mut native_sources := map[string]map[string]string{}
	for version in ['228', '229'] {
		sources := json2.decode[map[string]string](uncompressed(out, 'native' + version + '-sources.json.gz')!)!
		hashes := json2.decode[map[string]string](os.read_file(out + '/native' + version + '-sources-sha256.json')!)!
		assert sources.len == 81 && sources.len == hashes.len
		for name, source in sources {
			assert sha256.sum(source.bytes()).hex() == hashes[name], name
		}
		native_sources[version] = sources
	}
	mut changed := []string{}
	for name, source in native_sources['228'] {
		if source != native_sources['229'][name] { changed << name }
	}
	assert changed == ['path_clipping.v'], changed.str()
	assert native_sources['229']['path_clipping.v'].contains('f64(')
	host := json2.decode[map[string]json2.Any](os.read_file(out + '/host/host-proof.json')!)!
	assert host['fixed_path_clipping_sha256']!.str() == sha256.sum(native_sources['229']['path_clipping.v'].bytes()).hex()
	counted := os.read_file(out + '/host/counted-run-final.log')!
	assert counted.contains('allocated=8177 released=8177')
	assert counted.contains('both allocation failure branches preserve prior clip and free partial allocation')
	assert os.read_file(out + '/host/asan-run-final.log')!.contains('finite huge triangle does not overflow crossings')
	baseline := uncompressed(out, 'baseline-serial.log.gz')!
	fixed := uncompressed(out, 'fixed-serial.log.gz')!
	assert baseline.contains('UnsupportedOperationException: Native WS RenderNode supports rectangular outline clipping only')
	assert baseline.contains('org.vinix.bootstrap.RenderNodeOutlineProbe.node0')
	assert !baseline.contains('BOOTSTRAP-RENDER-NODE-OUTLINE-PASS')
	for marker in ['BOOTSTRAP-RENDER-NODE-OUTLINE-PASS 5600-pixels', 'BOOTSTRAP-ALPHA8-GL-PASS',
		'ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent'] {
		assert fixed.contains(marker), marker
	}
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError')
	assert !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	for variant, serial in {
		'baseline': baseline
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + variant + '-results.json')!)![0].as_map()
		assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == receipt.inputs['build/android-maps/outline228-apk/bootstrap.apk']
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		staged := json2.decode[map[string]string](os.read_file(out + '/' + variant + '-staged-runtime-sha256.json')!)!
		for path, digest in staged {
			assert digest == receipt.inputs[variant + '/staged/' + path]
		}
		if variant == 'fixed' {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			for marker in row['failure_markers']!.as_array() {
				line := marker.str()
				assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
			}
		}
	}
	previous := uncompressed(out + '/../canvas-z', 'fixed-serial.log.gz')!
	mut markers := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in markers { continue }
		assert fixed.contains(name), name
		markers << name
	}
	for path in ['usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'opt/android-test/native-guest'] {
		assert receipt.inputs['baseline/staged/' + path] == receipt.inputs['fixed/staged/' + path], path
	}
	for variant in ['baseline', 'fixed'] {
		jar := if variant == 'baseline' {
			'framework227-canvas-z/api-impl.jar'
		} else {
			'framework228-outline/api-impl.jar'
		}
		native := if variant == 'baseline' { 'libnative225.so' } else { 'libnative229.so' }
		assert receipt.inputs[variant + '/staged/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == receipt.inputs['build/android-maps/' + jar]
		assert receipt.inputs[variant + '/staged/opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == receipt.inputs['build/android-maps/' + native]
		render_node := uncompressed(out, variant + '-RenderNode.smali.gz')!
		assert render_node.contains('.method private vinixClipOutline(Landroid/graphics/Canvas;)V') == (variant == 'fixed')
		gsk := uncompressed(out, variant + '-GskCanvas.smali.gz')!
		assert gsk.contains('native_clipPath(JJI)Z') == (variant == 'fixed')
	}
	assert uncompressed(out, 'RenderNodeOutlineProbe.smali.gz')!.contains('5600-pixels')
	assert fixture['render_node_outline.v'].contains('70-intersections')
	println('RENDER-NODE-OUTLINE-VALIDATION PASS baseline exact exception; fixed5600 pixels +${markers.len} prior probes +READY; exact V/actual DEX/staged identities; native229 single-file robustness delta; raw harness limitation retained')
}
