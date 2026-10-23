import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const task = base + 'paint226/'
const dest = 'tests/android/results/2026-10-23/paint-filters/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn read_serial(mode string) !string {
	return gzip.decompress(os.read_bytes(task + 'run-' + mode + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
}

fn main() {
	b := read_serial('baseline')!
	f := read_serial('fixed')!
	marker := 'BOOTSTRAP-PAINT-FILTERS-PASS SRC_IN porter-duff-equivalence opaque partial-alpha setter-return clear translucent-reassign legacy-reassign ALPHA_8-mask'
	assert b.contains('java.lang.AssertionError: SRC_IN filtered bitmap pixel') && b.contains('PaintFiltersProbe.pixels')
	assert !b.contains(marker)
	assert f.count(marker) >= 1
	assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
	old := gzip.decompress(os.read_bytes(base + 'alpha224/run-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
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
	mut outcomes := map[string]json2.Any{}
	mut failure_markers := map[string]json2.Any{}
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
		outcomes[mode] = row['outcome']!
		failure_markers[mode] = row['failure_markers']!
		if mode == 'fixed' {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			for value in row['failure_markers']!.as_array() {
				line := value.str()
				assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
			}
		}
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(base + 'paint226-apk/bootstrap.apk')!
		runtime := json2.decode[map[string]string](os.read_file(task + 'run-' + mode + '/staged-runtime-sha256.json')!)!
		jar := if mode == 'baseline' {
			base + 'framework223-autofill/api-impl.jar'
		} else {
			base + 'framework226-filters/api-impl.jar'
		}
		assert runtime['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == hash(jar)!
		assert runtime['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']! == hash(base + 'libnative225.so')!
		assert runtime['usr/bin/run-android-calculator']! == hash(base + 'launcher200')!
	}
	for source, out in {
		'validate-paint226.v':                                                 'validate.v'
		'prepare-paint226.v':                                                  'prepare.v'
		'paint226/staged-hashes.v':                                            'staged-hashes.v'
		'build-framework226-filters.v':                                        'build-framework.v'
		'framework226-filters/framework-manifest.json':                        'fixed-framework-manifest.json'
		'framework226-filters/sources/androidtools/framework_paint_filters.v': 'framework-source.v'
		'finalize-paint226.v':                                                 'finalize-fixture.v'
		'paint226-apk-build.log':                                              'finalize-fixture.log'
		'paint226/initial-baseline-serial.log.gz':                             'initial-baseline-serial.log.gz'
		'paint226/initial-paint_filters.v':                                    'initial-paint_filters.v'
		'paint226/transient-boot-serial.log.gz':                               'transient-boot-serial.log.gz'
		'paint226/transient-boot-results.json':                                'transient-boot-results.json'
		'suite-low-disk.v':                                                    'suite.v'
	} {
		os.cp(base + source, dest + out)!
		artifacts[out] = hash(dest + out)!
	}
	os.write_file_array(dest + 'framework-build.log.gz', gzip.compress(os.read_bytes(base + 'framework226-filters-build.log')!)!)!
	artifacts['framework-build.log.gz'] = hash(dest + 'framework-build.log.gz')!
	if os.is_file(dest + 'framework-build.log') { os.rm(dest + 'framework-build.log')! }
	for entry in [
		['fixture-sources.tar.gz', base + 'paint226-apk', 'smali', 'res'],
		['fixed-framework-generated.tar.gz', base + 'framework226-filters/smali',
			'android/graphics/Paint.smali'],
		['fixed-framework-v-sources.tar.gz', base + 'framework226-filters/sources', 'androidtools'],
		['fixture-v-sources.tar.gz', base + 'paint226/source/startupfixture', 'paint_filters.v',
			'startup.v', 'alpha8.v', 'alpha8_gl.v'],
	] {
		mut args := ['tar', '-czf', os.abs_path(dest + entry[0]), '-C', entry[1]]
		args << entry[2..]
		r := os.exec(args)
		assert r.exit_code == 0, r.output
		artifacts[entry[0]] = hash(dest + entry[0])!
	}
	mut sources := map[string]json2.Any{}
	sources['tests/native-android-tools/androidtools/framework_paint_filters.v'] = hash(base + 'framework226-filters/sources/androidtools/framework_paint_filters.v')!
	for path in ['tests/native-android-ws/startupfixture/paint_filters.v'] {
		sources[path] = hash(path)!
	}
	receipt := {
		'artifacts_sha256':               json2.Any(artifacts)
		'sources_sha256':                 json2.Any(sources)
		'baseline_framework_sha256':      json2.Any(hash(base + 'framework223-autofill/api-impl.jar')!)
		'fixed_framework_sha256':         json2.Any(hash(base + 'framework226-filters/api-impl.jar')!)
		'fixture_apk_sha256':             json2.Any(hash(base + 'paint226-apk/bootstrap.apk')!)
		'initial_fixture_apk_sha256':     json2.Any('b63a86ef999b275cd19adc683b09c1e90b4abd00b287a194c2542c3ec4f2a5e7')
		'initial_fixture_limit':          json2.Any('The first Paint APK stopped before the intended pixel comparison because the test called an existing unsupported Paint.getColorFilter API. Its log and fixture source are retained separately. The identity checks were narrowed to the existing setColorFilter return value, then the same newly signed APK was run on both framework223 and framework226. Result claims and fixture hashes describe this corrected pair; no getColorFilter implementation is claimed.')
		'transient_boot_limit':           json2.Any('The first launch of the corrected APK timed out in firmware before any kernel or launcher marker. Its raw serial and harness result are retained as transient-boot artifacts. The unchanged baseline configuration and APK were restaged and rerun; the final pair is used for all pixel result claims.')
		'native225_sha256':               json2.Any(hash(base + 'libnative225.so')!)
		'harness_binary_sha256':          json2.Any(hash(base + 'suite159')!)
		'paint_filter_pass_count':        json2.Any(f.count(marker))
		'previous_pass_markers_retained': json2.Any(markers.len)
		'harness_outcomes':               json2.Any(outcomes)
		'harness_failure_markers':        json2.Any(failure_markers)
		'harness_qualification':          json2.Any('The raw harness outcomes and failure markers are retained. Native225 contains inherited Maps-only reflection diagnostics that print and clear missing nge/bB errors for fixture Main, so startup_failed is not a clean harness startup pass. The fixed claim is limited to the exact Paint pixel assertions, all previous probe markers, no fixture assertion or WS-FAIL, no app exit, and READY. The validator permits only those known reflection diagnostic markers on the fixed run.')
		'scope':                          json2.Any('Native WS SRC_IN color-filter regression. The identical signed APK fails on framework223 when BlendModeColorFilter silently loses tint, and passes on framework226-filters. It checks legacy/modern SRC_IN pixel equivalence for opaque and partial source alpha, setColorFilter return identity, clearing, translucent reassignment, legacy reassignment, and an ALPHA_8 source mask. Native225 and launcher200 are identical. Both prior ALPHA8 Canvas/GL probes and all earlier fixture probes plus READY are retained. No other BlendMode support is claimed. Maps behavior is recorded separately.')
	}
	os.write_file(dest + 'receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('PAINT-FILTERS-VALIDATION PASS identical signed APK; baseline loses modern tint; fixed SRC_IN pixel contract; ' + markers.len.str() + ' previous probe markers retained; staged hashes verified')
}
