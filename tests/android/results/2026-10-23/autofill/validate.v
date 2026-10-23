import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const task = base + 'autofill222/'
const dest = 'tests/android/results/2026-10-23/autofill/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn read_serial(mode string) !string {
	return gzip.decompress(os.read_bytes(task + 'run-' + mode + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
}

fn main() {
	b := read_serial('baseline')!
	f := read_serial('fixed')!
	marker := 'BOOTSTRAP-AUTOFILL-PASS toggle-wrapper true false typed-values parcel equality wrong-getters null-text empty-text'
	assert b.contains('java.lang.NoClassDefFoundError:') && b.contains('android/view/autofill/AutofillValue')
	assert !b.contains(marker)
	assert f.count(marker) >= 1
	assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
	old := gzip.decompress(os.read_bytes(base + 'content-capture221/run-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
	mut markers := []string{}
	for line in old.split_into_lines() {
		if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
		name := line.all_before(' ')
		if name in markers { continue }
		assert f.contains(name), name
		markers << name
	}
	os.mkdir_all(dest)!
	mut artifacts := map[string]json2.Any{}
	for mode in ['baseline', 'fixed'] {
		for name in ['results.json', 'bootstrap-fixture/serial.log.gz',
			'bootstrap-fixture/application.png', 'staged-runtime-sha256.json'] {
			out := mode + '-' + os.base(name)
			os.cp(task + 'run-' + mode + '/' + name, dest + out)!
			artifacts[out] = hash(dest + out)!
		}
		for name in ['-harness.log', '.json'] {
			out := mode + if name == '.json' { '-configuration.json' } else { name }
			os.cp(task + mode + name, dest + out)!
			artifacts[out] = hash(dest + out)!
		}
		row := json2.decode[[]map[string]json2.Any](os.read_file(task + 'run-' + mode + '/results.json')!)![0]
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(base + 'autofill222-apk/bootstrap.apk')!
		runtime := json2.decode[map[string]string](os.read_file(task + 'run-' + mode + '/staged-runtime-sha256.json')!)!
		jar := if mode == 'baseline' {
			base + 'framework221-content-capture/api-impl.jar'
		} else {
			base + 'framework222-autofill/api-impl.jar'
		}
		assert runtime['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == hash(jar)!
		assert runtime['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']! == hash(base + 'libnative204.so')!
		assert runtime['usr/bin/run-android-calculator']! == hash(base + 'launcher200')!
	}
	for source, out in {
		'validate-autofill222.v':                                          'validate.v'
		'prepare-autofill222.v':                                           'prepare.v'
		'autofill222/staged-hashes.v':                                     'staged-hashes.v'
		'build-framework222-autofill.v':                                   'build-framework.v'
		'framework222-autofill/framework-manifest.json':                   'fixed-framework-manifest.json'
		'framework222-autofill/sources/androidtools/framework_autofill.v': 'framework-source.v'
		'build-framework222-autofill.log':                                 'framework-build.log'
		'bootstrap222-autofill-build.log':                                 'fixture-build.log'
		'finalize-autofill222.v':                                          'finalize-fixture.v'
		'finalize-autofill222.log':                                        'finalize-fixture.log'
		'suite-low-disk.v':                                                'suite.v'
	} {
		os.cp(base + source, dest + out)!
		artifacts[out] = hash(dest + out)!
	}
	for source, out in {
		'bootstrap222-autofill-compile.log': 'fixture-compile.log.gz'
	} {
		os.write_file_array(dest + out, gzip.compress(os.read_bytes(base + source)!)!)!
		artifacts[out] = hash(dest + out)!
	}
	for entry in [
		['fixture-sources.tar.gz', base + 'autofill222-apk', 'smali', 'res'],
		['fixed-framework-generated.tar.gz', base + 'framework222-autofill/smali',
			'android/view/autofill/AutofillValue.smali',
			'android/view/autofill/VinixAutofillValueCreator.smali'],
	] {
		mut args := ['tar', '-czf', os.abs_path(dest + entry[0]), '-C', entry[1]]
		args << entry[2..]
		r := os.exec(args)
		assert r.exit_code == 0, r.output
		artifacts[entry[0]] = hash(dest + entry[0])!
	}
	mut sources := map[string]json2.Any{}
	sources['tests/native-android-tools/androidtools/framework_autofill.v'] = hash(base + 'framework222-autofill/sources/androidtools/framework_autofill.v')!
	for path in ['tests/native-android-ws/startupfixture/autofill.v'] {
		sources[path] = hash(path)!
	}
	receipt := {
		'artifacts_sha256':               json2.Any(artifacts)
		'sources_sha256':                 json2.Any(sources)
		'baseline_framework_sha256':      json2.Any(hash(base + 'framework221-content-capture/api-impl.jar')!)
		'fixed_framework_sha256':         json2.Any(hash(base + 'framework222-autofill/api-impl.jar')!)
		'fixture_apk_sha256':             json2.Any(hash(base + 'autofill222-apk/bootstrap.apk')!)
		'native204_sha256':               json2.Any(hash(base + 'libnative204.so')!)
		'harness_binary_sha256':          json2.Any(hash(base + 'suite159')!)
		'autofill_pass_count':            json2.Any(f.count(marker))
		'previous_pass_markers_retained': json2.Any(markers.len)
		'fixture_build_note':             json2.Any('The first fixture assembly rejected a wide literal without its required L suffix and produced no classes.dex. The probe source was corrected, then finalize-fixture.v regenerated the probe smali, asserted successful DEX output, assembled, and signed the identical APK used by both boots. The failed first build and successful finalization logs are retained.')
		'scope':                          json2.Any('Native WS synthetic regression. Identical signed APK fails with NoClassDefFoundError for AutofillValue on prior framework221-content-capture, and passes on framework222-autofill. A separate wrapper creates both toggle values as used by Maps. It covers all four types, values and type predicates, wrong-getter IllegalStateException, null and empty text, Parcelable interface roundtrips, typed creator arrays, equality and equal hashes, and inequality across types. Plain text is covered; preserving styled text spans in parcels is unsupported. Native204 and launcher200 are identical across boots. Maps behavior is retained separately.')
	}
	os.write_file(dest + 'receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('AUTOFILL-VALIDATION PASS identical signed APK; baseline missing class; fixed typed values and parcel contracts; ' + markers.len.str() + ' previous probe markers retained; staged hashes verified')
}
