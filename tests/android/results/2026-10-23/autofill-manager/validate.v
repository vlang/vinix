import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const task = base + 'autofill-manager223/'
const dest = 'tests/android/results/2026-10-23/autofill-manager/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn read_serial(mode string) !string {
	return gzip.decompress(os.read_bytes(task + 'run-' + mode + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
}

fn main() {
	b := read_serial('baseline')!
	f := read_serial('fixed')!
	marker := 'BOOTSTRAP-AUTOFILL-MANAGER-PASS context-lookup no-service virtual-visible virtual-hidden enter values-true-false exit no-callback bounds'
	assert b.contains('java.lang.NoSuchMethodError:') && b.contains('notifyViewVisibilityChanged(Landroid/view/View;IZ)V')
	assert !b.contains(marker)
	assert f.count(marker) >= 1
	assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
	old := gzip.decompress(os.read_bytes(base + 'autofill222/run-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
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
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(base + 'autofill-manager223-apk/bootstrap.apk')!
		runtime := json2.decode[map[string]string](os.read_file(task + 'run-' + mode + '/staged-runtime-sha256.json')!)!
		jar := if mode == 'baseline' {
			base + 'framework222-autofill/api-impl.jar'
		} else {
			base + 'framework223-autofill/api-impl.jar'
		}
		assert runtime['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == hash(jar)!
		assert runtime['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']! == hash(base + 'libnative204.so')!
		assert runtime['usr/bin/run-android-calculator']! == hash(base + 'launcher200')!
	}
	for source, out in {
		'validate-autofill-manager223.v':                                  'validate.v'
		'prepare-autofill-manager223.v':                                   'prepare.v'
		'autofill-manager223/staged-hashes.v':                             'staged-hashes.v'
		'build-framework223-autofill.v':                                   'build-framework.v'
		'framework223-autofill/framework-manifest.json':                   'fixed-framework-manifest.json'
		'framework223-autofill/sources/androidtools/framework_autofill.v': 'framework-source.v'
		'build-framework223-autofill.log':                                 'framework-build.log'
		'finalize-autofill-manager223.v':                                  'finalize-fixture.v'
		'finalize-autofill-manager223.log':                                'finalize-fixture.log'
		'suite-low-disk.v':                                                'suite.v'
	} {
		os.cp(base + source, dest + out)!
		artifacts[out] = hash(dest + out)!
	}
	for entry in [
		['fixture-sources.tar.gz', base + 'autofill-manager223-apk', 'smali', 'res'],
		['fixed-framework-generated.tar.gz', base + 'framework223-autofill/smali',
			'android/view/autofill/AutofillManager.smali'],
	] {
		mut args := ['tar', '-czf', os.abs_path(dest + entry[0]), '-C', entry[1]]
		args << entry[2..]
		r := os.exec(args)
		assert r.exit_code == 0, r.output
		artifacts[entry[0]] = hash(dest + entry[0])!
	}
	mut sources := map[string]json2.Any{}
	sources['tests/native-android-tools/androidtools/framework_autofill.v'] = hash(base + 'framework223-autofill/sources/androidtools/framework_autofill.v')!
	for path in ['tests/native-android-ws/startupfixture/autofill_manager.v'] {
		sources[path] = hash(path)!
	}
	receipt := {
		'artifacts_sha256':               json2.Any(artifacts)
		'sources_sha256':                 json2.Any(sources)
		'baseline_framework_sha256':      json2.Any(hash(base + 'framework222-autofill/api-impl.jar')!)
		'fixed_framework_sha256':         json2.Any(hash(base + 'framework223-autofill/api-impl.jar')!)
		'fixture_apk_sha256':             json2.Any(hash(base + 'autofill-manager223-apk/bootstrap.apk')!)
		'native204_sha256':               json2.Any(hash(base + 'libnative204.so')!)
		'harness_binary_sha256':          json2.Any(hash(base + 'suite159')!)
		'autofill_manager_pass_count':    json2.Any(f.count(marker))
		'previous_pass_markers_retained': json2.Any(markers.len)
		'scope':                          json2.Any('Native WS synthetic no-service AutofillManager regression. The identical signed APK fails on framework222-autofill with the exact missing virtual visibility overload used by Maps, and passes on framework223-autofill. The probe retrieves the manager through Context, registers a callback, sends virtual visibility, enter, true and false value, exit and hidden notifications, checks no callback was emitted and the caller Rect remains unchanged, then unregisters. Native204 and launcher200 are identical. Prior AutofillValue and all earlier fixture probes are retained. Maps behavior is recorded separately.')
	}
	os.write_file(dest + 'receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('AUTOFILL-MANAGER-VALIDATION PASS identical signed APK; baseline exact missing visibility overload; fixed no-service notification contract; ' + markers.len.str() + ' previous probe markers retained; staged hashes verified')
}
