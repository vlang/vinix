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
	assert r.inputs['build/android-maps/dates240-apk/bootstrap.apk'] == '7106274b55c8acae999b978b3aec56c5af1326dd90e4009b78ccb9f993a1c1ae'
	assert r.inputs['build/android-maps/framework239-insets/api-impl.jar'] == '68ad3466f9a8c84770fa0e40e39d1a3b0b6666f2b6d7ca67aeab53e6785e3aae'
	assert r.inputs['build/android-maps/framework240-date-ranges/api-impl.jar'] == '02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1'
	assert r.inputs['build/android-maps/libnative235.so'] == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!

	full := 'formatDateRange(Landroid/content/Context;Ljava/util/Formatter;JJILjava/lang/String;)Ljava/util/Formatter;'
	assert base.contains('java.lang.NoSuchMethodError: No static method ' + full)
	assert base.contains('DateRangesProbe.render') && base.contains('DateRangesProbe.cases') && base.contains('DateRangesProbe.check')
	assert !base.contains('BOOTSTRAP-DATE-RANGES-PASS') && base.contains('BOOTSTRAP-WINDOW-INSETS-PASS')
	assert fixed.contains('BOOTSTRAP-DATE-RANGES-PASS formatter-identity percent-prefix repeated-append default-locale timezone-null-UTC-explicit 12h-24h-preference range-date-endpoints string-point-wrappers closed-formatter IO-cause')
	assert fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	mut framework := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/dates240-apk/bootstrap.apk']
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
		jar := if mode == 'baseline' { 'framework239-insets' } else { 'framework240-date-ranges' }
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
	assert framework['baseline'].len == 108 && framework['fixed'].len == 109
	mut changed := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changed << os.base(name) }
	}
	changed.sort()
	assert changed == ['framework_date_ranges.v', 'framework_startup.v'], changed.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}

	baseline_api := read_gzip(out + '/baseline-DateUtils.smali.gz')!
	fixed_api := read_gzip(out + '/fixed-DateUtils.smali.gz')!
	assert !baseline_api.contains('.method public static ' + full)
	assert fixed_api.contains('.method public static ' + full)
	assert fixed_api.contains('Llibcore/icu/DateIntervalFormat;->formatDateRange')
	assert fixed_api.contains('.catch Ljava/io/IOException;')
	startup := read_gzip(out + '/StartupProbe.smali.gz')!
	assert startup.contains('DateRangesProbe;->check') && startup.contains('WindowInsetsProbe;->check')
	probe := read_gzip(out + '/DateRangesProbe.smali.gz')!
	for name in ['cases', 'wrappers', 'errors'] {
		assert probe.contains('.method private static ' + name + '()V'), name
	}
	assert probe.contains('move-object/from16 v1, p6')
	assert probe.contains('Ljava/util/Locale;->setDefault(Ljava/util/Locale$Category;Ljava/util/Locale;)V')
	assert probe.contains('Ljava/util/Formatter;->close()V') && probe.contains('Ljava/util/FormatterClosedException;')
	assert probe.contains('Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;')
	appendable := read_gzip(out + '/FailRangeAppendable.smali.gz')!
	assert appendable.count('.method public append(') == 3 && appendable.contains('range-append-failure')
	assert sha256.sum(os.read_bytes(out + '/../window-insets/receipt.json')!).hex() == r.inputs['prior-window-insets/receipt.json']
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
	previous := read_gzip(out + '/../window-insets/fixed-serial.log.gz')!
	mut prior := []string{}
	for line in previous.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in prior { continue }
		assert fixed.contains(name), name
		prior << name
	}
	println('DATE-RANGES VALIDATION PASS identical signed APK/native235; exact missing Formatter API baseline; numerical date/time ranges, zones/hour flags, append identity/literals/wrappers, error causes and global-state cleanup +${prior.len} prior probes +READY; raw fixed startup_failed limited to two inherited nge diagnostics')
}
