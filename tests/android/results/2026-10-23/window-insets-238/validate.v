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
	assert r.inputs['build/android-maps/insets238-apk/bootstrap.apk'] == '10331cbe7450f866e7e7ae737ced53653b1ce079d630190ff702773abf8210b0'
	assert r.inputs['build/android-maps/framework236-texture/api-impl.jar'] == '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584'
	assert r.inputs['build/android-maps/framework238-insets/api-impl.jar'] == 'd505eb42053525b014784c17f693f0ecd85914a3f076f45721ce8da5eeb3fe1e'
	assert r.inputs['build/android-maps/libnative235.so'] == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!
	assert base.contains('java.lang.NoClassDefFoundError:') && base.contains('WindowInsets$Builder')
	assert base.contains('WindowInsetsProbe.check') && !base.contains('BOOTSTRAP-WINDOW-INSETS-PASS')
	assert base.contains('BOOTSTRAP-INTERPOLATORS-PASS') && base.contains('BOOTSTRAP-TEXTURE-TRANSFORM-PASS')
	assert fixed.contains('BOOTSTRAP-WINDOW-INSETS-PASS defaults legacy-five typed-masks maxima visibility copy-build-isolation consume replacement inset-clamp negative-arguments')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	mut framework := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/insets238-apk/bootstrap.apk']
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
		jar := if mode == 'baseline' { 'framework236-texture' } else { 'framework238-insets' }
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
	assert framework['baseline'].len == 106 && framework['fixed'].len == 107
	mut changed := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changed << os.base(name) }
	}
	changed.sort()
	assert changed == ['framework_insets.v', 'framework_startup.v'], changed.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}
	assert !os.exists(out + '/baseline-WindowInsets$Builder.smali.gz')
	builder := read_gzip(out + '/fixed-WindowInsets$Builder.smali.gz')!
	assert builder.contains('.method public constructor <init>()V') && builder.contains('.method public build()Landroid/view/WindowInsets;')
	startup := read_gzip(out + '/StartupProbe.smali.gz')!
	assert startup.contains('InterpolatorProbe;->check') && startup.contains('TextureViewTransformProbe;->check') && startup.contains('WindowInsetsProbe;->check')
	probe := read_gzip(out + '/WindowInsetsProbe.smali.gz')!
	for name in ['legacy', 'typed', 'negative', 'consumedAndIme'] {
		assert probe.contains('.method private static ' + name + '()V'), name
	}
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
	previous := read_gzip(out + '/../texture-transform/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	println('WINDOW-INSETS VALIDATION PASS identical signed APK/native235; missing Builder baseline; legacy/typed values, copies, consumed/IME edge semantics, inset/replacement checks +${prior.len} prior probes +READY on framework238')
}
