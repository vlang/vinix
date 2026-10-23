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
	assert r.inputs['build/android-maps/blur241-apk/bootstrap.apk'] == '2a13d5fc0c0e1c97a9d132c3de5d17548b62bdcf8b8af132c25e6c5fcbbe0545'
	assert r.inputs['build/android-maps/framework240-date-ranges/api-impl.jar'] == '02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1'
	assert r.inputs['build/android-maps/framework241-blur-styles/api-impl.jar'] == '60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04'
	assert r.inputs['build/android-maps/libnative235.so'] == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!

	assert base.contains('java.lang.NoSuchFieldError: No static field OUTER of type Landroid/graphics/BlurMaskFilter$Blur;')
	assert base.contains('BlurStylesProbe.check') && base.contains('BOOTSTRAP-DATE-RANGES-PASS')
	assert !base.contains('BOOTSTRAP-BLUR-STYLES-PASS')
	assert fixed.contains('BOOTSTRAP-BLUR-STYLES-PASS OUTER NORMAL-SOLID-OUTER-INNER names ordinals native-ids distinct-identities values-order clone-isolation valueOf-valid-unknown-null')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	mut framework := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/blur241-apk/bootstrap.apk']
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
			'framework240-date-ranges'
		} else {
			'framework241-blur-styles'
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
	assert framework['baseline'].len == 109 && framework['fixed'].len == 110
	mut changed := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changed << os.base(name) }
	}
	changed.sort()
	assert changed == ['framework_blur_styles.v', 'framework_startup.v'], changed.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}

	baseline_api := read_gzip(out + '/baseline-BlurMaskFilter$Blur.smali.gz')!
	fixed_api := read_gzip(out + '/fixed-BlurMaskFilter$Blur.smali.gz')!
	assert !baseline_api.contains('.field public static final enum OUTER:') && !baseline_api.contains('native_int:I')
	for name in ['NORMAL', 'SOLID', 'OUTER', 'INNER'] {
		assert fixed_api.contains('.field public static final enum ' + name + ':'), name
	}
	assert fixed_api.contains('.field final native_int:I') && fixed_api.contains('iput p2, p0,')
	assert fixed_api.contains('->clone()Ljava/lang/Object;') && fixed_api.contains('Ljava/lang/Enum;->valueOf')
	assert read_gzip(out + '/baseline-BlurMaskFilter.smali.gz')! == read_gzip(out + '/fixed-BlurMaskFilter.smali.gz')!
	startup := read_gzip(out + '/StartupProbe.smali.gz')!
	assert startup.contains('BlurStylesProbe;->check') && startup.contains('DateRangesProbe;->check')
	probe := read_gzip(out + '/BlurStylesProbe.smali.gz')!
	for part in ['->OUTER:', '->getDeclaringClass()', '->getDeclaredField(', '->getInt(',
		'->getModifiers()', 'aput-object', '.catch Ljava/lang/IllegalArgumentException;',
		'.catch Ljava/lang/NullPointerException;'] {
		assert probe.contains(part), part
	}
	assert sha256.sum(os.read_bytes(out + '/../date-ranges/receipt.json')!).hex() == r.inputs['prior-date-ranges/receipt.json']
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
	previous := read_gzip(out + '/../date-ranges/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	assert prior.len == 105
	println('BLUR-STYLES VALIDATION PASS identical signed APK/native235; exact missing OUTER field baseline; all4 enum names/order/ordinals/native IDs, identity, clone isolation and valueOf errors +${prior.len} prior probes +READY; raw fixed startup_failed limited to two inherited nge diagnostics')
}
